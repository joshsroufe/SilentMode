import CoreFoundation
import Foundation
import os

struct SilentModeController {
    static let sharedStateDidChangeNotification = Notification.Name("com.josh.silentmode.sharedStateDidChange")

    private let logger = Logger(subsystem: "com.josh.silentmode", category: "Controller")
    private let soundPreferences = SystemSoundPreferences()
    private let notificationPreferences = NotificationSoundPreferences()
    private let storedPreferences = StoredSilentModePreferences()
    private let sharedState = SharedSilentModeState()
    private let minimumFallbackRestoreVolume = 0.5

    func isSilentModeEnabled() throws -> Bool {
        if storedPreferences.hasSilentModePreference {
            return storedPreferences.isSilentModeEnabled
        }
        return try soundPreferences.alertVolume() <= 0.001
    }

    func isSystemSilentModeEnabled() throws -> Bool {
        try soundPreferences.alertVolume() <= 0.001
    }

    func alertVolume() throws -> Double {
        try soundPreferences.alertVolume()
    }

    func setSilentModeEnabled(_ enabled: Bool) throws {
        try applySystemSilentMode(enabled)
        setStoredSilentModeEnabled(enabled)
        setSharedSilentModeEnabled(enabled)
    }

    func setSharedSilentModeEnabled(_ enabled: Bool) {
        sharedState.isSilentModeEnabled = enabled
        logger.info("Posting shared state changed notification with enabled \(enabled)")
        DistributedNotificationCenter.default().postNotificationName(
            Self.sharedStateDidChangeNotification,
            object: nil,
            userInfo: ["enabled": enabled],
            deliverImmediately: true
        )
    }

    func sharedSilentModeEnabled() -> Bool? {
        sharedState.isSilentModeEnabled
    }

    func setStoredSilentModeEnabled(_ enabled: Bool) {
        if enabled {
            captureRestoreSnapshotIfNeeded()
        }
        storedPreferences.isSilentModeEnabled = enabled
    }

    func applySystemSilentMode(_ enabled: Bool) throws {
        logger.info("Applying system silent mode \(enabled)")
        if enabled {
            let snapshot = soundPreferences.snapshot()
            captureRestoreSnapshotIfNeeded(snapshot: snapshot)
            try soundPreferences.setAlertVolume(0)
            try notificationPreferences.disableNotificationSounds(storedPreferences: storedPreferences)
        } else {
            if let snapshot = storedPreferences.restoreSoundSnapshot {
                try soundPreferences.restore(snapshot)
            } else {
                let restoreVolume = max(storedPreferences.restoreAlertVolume ?? 0.55, minimumFallbackRestoreVolume)
                try soundPreferences.setAlertVolume(restoreVolume)
            }
            try notificationPreferences.restoreNotificationSounds(storedPreferences: storedPreferences)
        }
    }

    func synchronizeSystemSoundWithSharedState() throws {
        guard let enabled = sharedState.isSilentModeEnabled ?? storedPreferences.silentModePreference else {
            return
        }

        setStoredSilentModeEnabled(enabled)
        let volume = try soundPreferences.alertVolume()

        if enabled && volume > 0.001 {
            try applySystemSilentMode(true)
        } else if !enabled && volume <= 0.001 {
            try applySystemSilentMode(false)
        }
    }

    private func captureRestoreSnapshotIfNeeded(snapshot: SystemSoundPreferences.Snapshot? = nil) {
        let snapshot = snapshot ?? soundPreferences.snapshot()
        if snapshot.effectiveAlertVolume > 0.001 {
            storedPreferences.restoreSoundSnapshot = snapshot
            storedPreferences.restoreAlertVolume = snapshot.effectiveAlertVolume
            return
        }

        if storedPreferences.restoreSoundSnapshot == nil {
            let fallbackVolume = max(storedPreferences.restoreAlertVolume ?? 0.55, minimumFallbackRestoreVolume)
            storedPreferences.restoreSoundSnapshot = .defaultRestored(volume: fallbackVolume)
            storedPreferences.restoreAlertVolume = fallbackVolume
        }
    }
}

struct NotificationSoundPreferences {
    private let logger = Logger(subsystem: "com.josh.silentmode", category: "NotificationSounds")
    private let soundEnabledBit = 1 << 2

    func disableNotificationSounds(storedPreferences: StoredSilentModePreferences) throws {
        var plist = try loadPlist()
        guard var apps = plist["apps"] as? [[String: Any]] else {
            return
        }

        if storedPreferences.notificationSoundFlagsSnapshot == nil {
            storedPreferences.notificationSoundFlagsSnapshot = makeSnapshot(from: apps)
        }

        var didChange = false
        for index in apps.indices {
            guard apps[index]["bundle-id"] is String,
                  let flags = apps[index]["flags"] as? Int else {
                continue
            }

            let mutedFlags = flags & ~soundEnabledBit
            if mutedFlags != flags {
                apps[index]["flags"] = mutedFlags
                didChange = true
            }
        }

        guard didChange else {
            return
        }

        plist["apps"] = apps
        try savePlist(plist)
        reloadNotificationServices()
    }

    func restoreNotificationSounds(storedPreferences: StoredSilentModePreferences) throws {
        guard let snapshot = storedPreferences.notificationSoundFlagsSnapshot else {
            return
        }

        var plist = try loadPlist()
        guard var apps = plist["apps"] as? [[String: Any]] else {
            return
        }

        var didChange = false
        for index in apps.indices {
            guard let bundleID = apps[index]["bundle-id"] as? String,
                  let flags = snapshot[bundleID] else {
                continue
            }

            if apps[index]["flags"] as? Int != flags {
                apps[index]["flags"] = flags
                didChange = true
            }
        }

        if didChange {
            plist["apps"] = apps
            try savePlist(plist)
            reloadNotificationServices()
        }

        storedPreferences.notificationSoundFlagsSnapshot = nil
    }

    private func makeSnapshot(from apps: [[String: Any]]) -> [String: Int] {
        var snapshot: [String: Int] = [:]
        for app in apps {
            guard let bundleID = app["bundle-id"] as? String,
                  let flags = app["flags"] as? Int else {
                continue
            }
            snapshot[bundleID] = flags
        }
        return snapshot
    }

    private func loadPlist() throws -> [String: Any] {
        let data = try Data(contentsOf: preferencesURL)
        let plist = try PropertyListSerialization.propertyList(from: data, options: [], format: nil)
        guard let dictionary = plist as? [String: Any] else {
            throw SilentModeError.unreadablePreference("notification sound settings")
        }
        return dictionary
    }

    private func savePlist(_ plist: [String: Any]) throws {
        let data = try PropertyListSerialization.data(fromPropertyList: plist, format: .binary, options: 0)
        try data.write(to: preferencesURL, options: [.atomic])
    }

    private func reloadNotificationServices() {
        for processName in ["usernoted", "NotificationCenter"] {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/killall")
            process.arguments = [processName]

            do {
                try process.run()
                process.waitUntilExit()
            } catch {
                logger.error("Failed to reload \(processName): \(error.localizedDescription)")
            }
        }
    }

    private var preferencesURL: URL {
        URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("Preferences")
            .appendingPathComponent("com.apple.ncprefs.plist")
    }
}

struct SystemSoundPreferences {
    struct Snapshot: Codable {
        var anyHost: HostValues
        var currentHost: HostValues

        var effectiveAlertVolume: Double {
            currentHost.alertVolume ?? anyHost.alertVolume ?? 0.55
        }

        static func defaultRestored(volume: Double) -> Snapshot {
            Snapshot(
                anyHost: HostValues(alertVolume: volume, uiAudioEnabled: true, feedbackEnabled: true),
                currentHost: HostValues(alertVolume: volume, uiAudioEnabled: true, feedbackEnabled: true)
            )
        }
    }

    struct HostValues: Codable {
        var alertVolume: Double?
        var uiAudioEnabled: Bool?
        var feedbackEnabled: Bool?
    }

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

    func snapshot() -> Snapshot {
        Snapshot(
            anyHost: values(for: kCFPreferencesAnyHost),
            currentHost: values(for: kCFPreferencesCurrentHost)
        )
    }

    func setMuted() throws {
        try setSoundControls(
            anyHost: HostValues(alertVolume: 0, uiAudioEnabled: false, feedbackEnabled: false),
            currentHost: HostValues(alertVolume: 0, uiAudioEnabled: false, feedbackEnabled: false)
        )
    }

    func restore(_ snapshot: Snapshot) throws {
        try setSoundControls(anyHost: snapshot.anyHost, currentHost: snapshot.currentHost)
    }

    func setAlertVolume(_ volume: Double) throws {
        let clampedVolume = clamp(volume)
        try setSoundControls(
            anyHost: HostValues(alertVolume: clampedVolume, uiAudioEnabled: clampedVolume > 0, feedbackEnabled: clampedVolume > 0),
            currentHost: HostValues(alertVolume: clampedVolume, uiAudioEnabled: clampedVolume > 0, feedbackEnabled: clampedVolume > 0)
        )
    }

    private func values(for host: CFString) -> HostValues {
        HostValues(
            alertVolume: doubleValue(for: alertVolumeKey, host: host),
            uiAudioEnabled: boolValue(for: uiAudioKey, host: host),
            feedbackEnabled: boolValue(for: feedbackKey, host: host)
        )
    }

    private func setSoundControls(anyHost: HostValues, currentHost: HostValues) throws {
        set(anyHost.alertVolume.map { NSNumber(value: clamp($0)) }, for: alertVolumeKey, host: kCFPreferencesAnyHost)
        set(anyHost.uiAudioEnabled.map { NSNumber(value: $0) }, for: uiAudioKey, host: kCFPreferencesAnyHost)
        set(anyHost.feedbackEnabled.map { NSNumber(value: $0) }, for: feedbackKey, host: kCFPreferencesAnyHost)

        set(currentHost.alertVolume.map { NSNumber(value: clamp($0)) }, for: alertVolumeKey, host: kCFPreferencesCurrentHost)
        set(currentHost.uiAudioEnabled.map { NSNumber(value: $0) }, for: uiAudioKey, host: kCFPreferencesCurrentHost)
        set(currentHost.feedbackEnabled.map { NSNumber(value: $0) }, for: feedbackKey, host: kCFPreferencesCurrentHost)

        let synchronized = [kCFPreferencesAnyHost, kCFPreferencesCurrentHost]
            .map { CFPreferencesSynchronize(globalDomain, kCFPreferencesCurrentUser, $0) }
            .allSatisfy { $0 }

        guard synchronized else {
            throw SilentModeError.preferenceWriteFailed
        }
    }

    private func set(_ value: NSNumber?, for key: CFString, host: CFString) {
        CFPreferencesSetValue(
            key,
            value,
            globalDomain,
            kCFPreferencesCurrentUser,
            host
        )
    }

    private func doubleValue(for key: CFString, host: CFString) -> Double? {
        guard let value = CFPreferencesCopyValue(key, globalDomain, kCFPreferencesCurrentUser, host) else {
            return nil
        }

        return (value as? NSNumber).map { clamp($0.doubleValue) }
    }

    private func boolValue(for key: CFString, host: CFString) -> Bool? {
        guard let value = CFPreferencesCopyValue(key, globalDomain, kCFPreferencesCurrentUser, host) else {
            return nil
        }

        return (value as? NSNumber)?.boolValue
    }

    private func clamp(_ value: Double) -> Double {
        min(max(value, 0), 1)
    }
}

struct StoredSilentModePreferences {
    private let defaults = UserDefaults.standard
    private let isEnabledKey = "SilentMode.isEnabled"
    private let restoreVolumeKey = "SilentMode.restoreAlertVolume"
    private let restoreSnapshotKey = "SilentMode.restoreSoundSnapshot"
    private let notificationFlagsSnapshotKey = "SilentMode.notificationSoundFlagsSnapshot"

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

    var silentModePreference: Bool? {
        defaults.synchronize()
        guard defaults.object(forKey: isEnabledKey) != nil else {
            return nil
        }
        return defaults.bool(forKey: isEnabledKey)
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

    var restoreSoundSnapshot: SystemSoundPreferences.Snapshot? {
        get {
            defaults.synchronize()
            guard let data = defaults.data(forKey: restoreSnapshotKey) else {
                return nil
            }
            return try? JSONDecoder().decode(SystemSoundPreferences.Snapshot.self, from: data)
        }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: restoreSnapshotKey)
            } else {
                defaults.removeObject(forKey: restoreSnapshotKey)
            }
            defaults.synchronize()
        }
    }

    var notificationSoundFlagsSnapshot: [String: Int]? {
        get {
            defaults.synchronize()
            guard let data = defaults.data(forKey: notificationFlagsSnapshotKey) else {
                return nil
            }
            return try? JSONDecoder().decode([String: Int].self, from: data)
        }
        nonmutating set {
            if let newValue, let data = try? JSONEncoder().encode(newValue) {
                defaults.set(data, forKey: notificationFlagsSnapshotKey)
            } else {
                defaults.removeObject(forKey: notificationFlagsSnapshotKey)
            }
            defaults.synchronize()
        }
    }
}

struct SharedSilentModeState {
    private struct State: Codable {
        let isEnabled: Bool
    }

    private let appGroupIdentifier = "GUA7MK96W5.com.josh.silentmode"
    private let stateFileName = "SilentModeState.json"

    var isSilentModeEnabled: Bool? {
        get {
            guard let data = try? Data(contentsOf: stateFileURL) else {
                return nil
            }

            return try? JSONDecoder().decode(State.self, from: data).isEnabled
        }
        nonmutating set {
            guard let newValue else {
                try? FileManager.default.removeItem(at: stateFileURL)
                return
            }

            do {
                try FileManager.default.createDirectory(
                    at: stateFileURL.deletingLastPathComponent(),
                    withIntermediateDirectories: true
                )
                let data = try JSONEncoder().encode(State(isEnabled: newValue))
                try data.write(to: stateFileURL, options: [.atomic])
            } catch {
                Logger(subsystem: "com.josh.silentmode", category: "Controller")
                    .error("Failed to write shared Silent Mode state: \(error.localizedDescription)")
            }
        }
    }

    private var stateFileURL: URL {
        if let containerURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: appGroupIdentifier) {
            return containerURL.appendingPathComponent(stateFileName)
        }

        return URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library")
            .appendingPathComponent("Group Containers")
            .appendingPathComponent(appGroupIdentifier)
            .appendingPathComponent(stateFileName)
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
