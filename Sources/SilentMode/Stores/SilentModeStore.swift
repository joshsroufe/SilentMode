import AudioToolbox
import Foundation
import Observation
import os
import WidgetKit

@Observable
final class SilentModeStore {
    private let controller: SilentModeController
    private let logger = Logger(subsystem: "com.josh.silentmode", category: "SilentMode")
    private let controlKind = "com.josh.silentmode.control"
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
        sharedStateObserver = DistributedNotificationCenter.default().addObserver(
            forName: SilentModeController.sharedStateDidChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            self?.refreshFromSystem(updateStatus: false)
        }
    }

    deinit {
        if let sharedStateObserver {
            DistributedNotificationCenter.default().removeObserver(sharedStateObserver)
        }
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
        controller.setSharedSilentModeEnabled(true)
        isSilentModeEnabled = true
        lastKnownAlertVolume = 0
        statusMessage = "Silent Mode is on. Local alert sounds are muted."

        do {
            try controller.applySystemSilentMode(true)
            logger.info("Silent Mode enabled")
        } catch {
            logger.error("Failed to enable Silent Mode: \(error.localizedDescription)")
        }

        reloadControlCenterControl()
    }

    private func disableSilentMode() {
        controller.setSharedSilentModeEnabled(false)
        isSilentModeEnabled = false
        statusMessage = "Silent Mode is off. Local alert sounds can play."

        do {
            try controller.applySystemSilentMode(false)
            let volume = try controller.alertVolume()
            lastKnownAlertVolume = volume
            logger.info("Silent Mode disabled")
        } catch {
            logger.error("Failed to disable Silent Mode: \(error.localizedDescription)")
        }

        reloadControlCenterControl()
    }

    private func reloadControlCenterControl() {
        if #available(macOS 26.0, *) {
            ControlCenter.shared.reloadControls(ofKind: controlKind)
        }
    }
}
