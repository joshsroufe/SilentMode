import AudioToolbox
import Foundation
import Observation
import os
import WidgetKit

@Observable
@MainActor
final class SilentModeStore {
    private let controller: SilentModeController
    private let logger = Logger(subsystem: "com.josh.silentmode", category: "SilentMode")
    private let controlKind = "com.josh.silentmode.control"
    @ObservationIgnored private var syncTimer: Timer?
    @ObservationIgnored private var sharedStateObserver: NSObjectProtocol?

    private(set) var isSilentModeEnabled: Bool
    private(set) var lastKnownAlertVolume: Double
    private(set) var statusMessage: String

    init(controller: SilentModeController = SilentModeController()) {
        self.controller = controller
        self.isSilentModeEnabled = false
        self.lastKnownAlertVolume = 0.55
        self.statusMessage = ""

        refreshFromSystem()
        startSharedStateObserver()
        startSyncTimer()
    }

    func toggleSilentMode() {
        setSilentMode(!isSilentModeEnabled)
    }

    func setSilentMode(_ enabled: Bool) {
        if enabled {
            enableSilentMode()
        } else {
            disableSilentMode()
        }
    }

    func enableForScreenSaver() {
        if isSilentModeEnabled {
            refreshFromSystem(updateStatus: false)
            return
        }

        enableSilentMode()
        statusMessage = "Silent Mode turned on because the screen saver started."
    }

    func restoreAfterScreenSaver() {
        refreshFromSystem(updateStatus: false)
        guard isSilentModeEnabled else {
            return
        }

        disableSilentMode()
        statusMessage = "Silent Mode restored after the screen saver ended."
    }

    func refreshFromSystem(updateStatus: Bool = true) {
        do {
            try? controller.synchronizeSystemSoundWithSharedState()
            let volume = try controller.alertVolume()
            let enabled = try controller.isSilentModeEnabled()
            isSilentModeEnabled = enabled
            lastKnownAlertVolume = volume
            if updateStatus {
                statusMessage = enabled ? "Notification and alert sounds are muted." : "Notification and alert sounds can play."
            }
        } catch {
            if updateStatus {
                statusMessage = "Could not read the current alert sound setting."
            }
            logger.error("Failed to refresh sound preferences: \(error.localizedDescription)")
        }
    }

    func playTestAlert() {
        refreshFromSystem()
        if isSilentModeEnabled || lastKnownAlertVolume <= 0.001 {
            statusMessage = "Silent Mode is on. No test sound was played."
            return
        }

        statusMessage = "Playing a test alert."
        AudioServicesPlayAlertSound(kSystemSoundID_UserPreferredAlert)
    }

    private func enableSilentMode() {
        controller.setStoredSilentModeEnabled(true)
        controller.setSharedSilentModeEnabled(true)
        isSilentModeEnabled = true
        lastKnownAlertVolume = 0
        statusMessage = "Silent Mode is on. Local alert sounds are muted."

        do {
            try controller.applySystemSilentMode(true)
            logger.info("Silent Mode enabled")
        } catch {
            statusMessage = "Silent Mode is on, but macOS blocked alert sound changes."
            logger.error("Failed to enable Silent Mode: \(error.localizedDescription)")
        }

        reloadControlCenterControl()
    }

    private func disableSilentMode() {
        controller.setStoredSilentModeEnabled(false)
        controller.setSharedSilentModeEnabled(false)
        isSilentModeEnabled = false
        statusMessage = "Silent Mode is off. Local alert sounds can play."

        do {
            try controller.applySystemSilentMode(false)
            let volume = try controller.alertVolume()
            lastKnownAlertVolume = volume
            logger.info("Silent Mode disabled")
        } catch {
            statusMessage = "Silent Mode is off, but macOS blocked restoring alert sounds."
            logger.error("Failed to disable Silent Mode: \(error.localizedDescription)")
        }

        reloadControlCenterControl()
    }

    private func reloadControlCenterControl() {
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: controlKind)
        }
    }

    private func startSharedStateObserver() {
        logger.info("Starting Control Center shared state observer")
        sharedStateObserver = DistributedNotificationCenter.default().addObserver(
            forName: SilentModeController.sharedStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let enabled = notification.userInfo?["enabled"] as? Bool
            Logger(subsystem: "com.josh.silentmode", category: "SilentMode").info("Received shared state notification with enabled \(String(describing: enabled))")
            Task { @MainActor in
                self?.applySharedStateChange(enabled: enabled)
            }
        }
    }

    private func applySharedStateChange(enabled: Bool?) {
        guard let enabled else {
            logger.info("Shared state notification did not include enabled; refreshing")
            refreshFromSystem(updateStatus: false)
            return
        }

        do {
            logger.info("Applying Control Center shared state \(enabled)")
            controller.setStoredSilentModeEnabled(enabled)
            try controller.applySystemSilentMode(enabled)
            let volume = try controller.alertVolume()
            isSilentModeEnabled = enabled
            lastKnownAlertVolume = volume
            statusMessage = enabled ? "Notification and alert sounds are muted." : "Notification and alert sounds can play."
            reloadControlCenterControl()
        } catch {
            statusMessage = "Could not apply the Control Center Silent Mode change."
            logger.error("Failed to apply shared Silent Mode state: \(error.localizedDescription)")
        }
    }

    private func startSyncTimer() {
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshFromSystem(updateStatus: false)
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        syncTimer = timer
    }
}

extension SilentModeStore: @unchecked Sendable {}
