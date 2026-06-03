import CoreFoundation
import Foundation

struct SilentModeController {
    static let sharedStateDidChangeNotification = Notification.Name("com.josh.silentmode.sharedStateDidChange")

    private let soundPreferences = SystemSoundPreferences()
    private let storedPreferences = StoredSilentModePreferences()

    func isSilentModeEnabled() throws -> Bool {
        if storedPreferences.hasSilentModePreference {
            return storedPreferences.isSilentModeEnabled
        }
        return try soundPreferences.alertVolume() <= 0.001
    }

    func alertVolume() throws -> Double {
        try soundPreferences.alertVolume()
    }

    func setSilentModeEnabled(_ enabled: Bool) throws {
        try applySystemSilentMode(enabled)
        storedPreferences.isSilentModeEnabled = enabled
    }

    func setSharedSilentModeEnabled(_ enabled: Bool) {
        if enabled {
            let currentVolume = (try? soundPreferences.alertVolume()) ?? storedPreferences.restoreAlertVolume ?? 0.55
            let restoreVolume = max(currentVolume, 0.35)
            storedPreferences.restoreAlertVolume = restoreVolume
        }
        storedPreferences.isSilentModeEnabled = enabled
        notifySharedStateDidChange(enabled)
    }

    func applySystemSilentMode(_ enabled: Bool) throws {
        if enabled {
            let currentVolume = try soundPreferences.alertVolume()
            let restoreVolume = max(currentVolume, storedPreferences.restoreAlertVolume ?? 0.35, 0.35)
            storedPreferences.restoreAlertVolume = restoreVolume
            try soundPreferences.setAlertVolume(0)
        } else {
            let restoreVolume = max(storedPreferences.restoreAlertVolume ?? 0.55, 0.1)
            try soundPreferences.setAlertVolume(restoreVolume)
        }
    }

    func synchronizeSystemSoundWithSharedState() throws {
        guard storedPreferences.hasSilentModePreference else {
            return
        }

        let enabled = storedPreferences.isSilentModeEnabled
        let volume = try soundPreferences.alertVolume()

        if enabled && volume > 0.001 {
            try applySystemSilentMode(true)
        } else if !enabled && volume <= 0.001 {
            try applySystemSilentMode(false)
        }
    }

    private func notifySharedStateDidChange(_ enabled: Bool) {
        DistributedNotificationCenter.default().post(
            name: Self.sharedStateDidChangeNotification,
            object: nil,
            userInfo: ["isEnabled": enabled]
        )
    }
}

struct SystemSoundPreferences {
    private let globalDomain = kCFPreferencesAnyApplication
    private let alertVolumeKey = "com.apple.sound.beep.volume" as CFString
    private let uiAudioKey = "com.apple.sound.uiaudio.enabled" as CFString
    private let feedbackKey = "com.apple.sound.beep.feedback" as CFString

    func alertVolume() throws -> Double {
        let value = CFPreferencesCopyValue(
            alertVolumeKey,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesCurrentHost
        ) ?? CFPreferencesCopyValue(
            alertVolumeKey,
            globalDomain,
            kCFPreferencesCurrentUser,
            kCFPreferencesAnyHost
        )

        guard let value else {
            return 0.55
        }

        if let number = value as? NSNumber {
            return clamp(number.doubleValue)
        }

        throw SilentModeError.unreadablePreference("alert volume")
    }

    func setAlertVolume(_ volume: Double) throws {
        let clampedVolume = clamp(volume)
        let hosts = [kCFPreferencesAnyHost, kCFPreferencesCurrentHost]
        for host in hosts {
            CFPreferencesSetValue(
                alertVolumeKey,
                NSNumber(value: clampedVolume),
                globalDomain,
                kCFPreferencesCurrentUser,
                host
            )
            CFPreferencesSetValue(
                uiAudioKey,
                NSNumber(value: clampedVolume > 0),
                globalDomain,
                kCFPreferencesCurrentUser,
                host
            )
            CFPreferencesSetValue(
                feedbackKey,
                NSNumber(value: clampedVolume > 0),
                globalDomain,
                kCFPreferencesCurrentUser,
                host
            )
        }

        let synchronized = hosts
            .map { CFPreferencesSynchronize(globalDomain, kCFPreferencesCurrentUser, $0) }
            .allSatisfy { $0 }

        guard synchronized else {
            throw SilentModeError.preferenceWriteFailed
        }
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct StoredSilentModePreferences {
    private let defaults = UserDefaults(suiteName: "GUA7MK96W5.com.josh.silentmode") ?? .standard
    private let isEnabledKey = "SilentMode.isEnabled"
    private let restoreVolumeKey = "SilentMode.restoreAlertVolume"

    var isSilentModeEnabled: Bool {
        get {
            defaults.synchronize()
            return defaults.bool(forKey: isEnabledKey)
        }
        nonmutating set {
            defaults.set(newValue, forKey: isEnabledKey)
            defaults.synchronize()
        }
    }

    var hasSilentModePreference: Bool {
        defaults.synchronize()
        return defaults.object(forKey: isEnabledKey) != nil
    }

    var restoreAlertVolume: Double? {
        get {
            defaults.synchronize()
            guard defaults.object(forKey: restoreVolumeKey) != nil else {
                return nil
            }
            return defaults.double(forKey: restoreVolumeKey)
        }
        nonmutating set {
            if let newValue {
                defaults.set(min(max(newValue, 0), 1), forKey: restoreVolumeKey)
            } else {
                defaults.removeObject(forKey: restoreVolumeKey)
            }
            defaults.synchronize()
        }
    }
}

enum SilentModeError: LocalizedError {
    case preferenceWriteFailed
    case unreadablePreference(String)

    var errorDescription: String? {
        switch self {
        case .preferenceWriteFailed:
            "Could not write the alert sound preference."
        case let .unreadablePreference(name):
            "Could not read \(name)."
        }
    }
}
