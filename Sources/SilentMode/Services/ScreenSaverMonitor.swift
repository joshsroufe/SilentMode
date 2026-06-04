import Foundation
import os

@MainActor
final class ScreenSaverMonitor {
    private let logger = Logger(subsystem: "com.josh.silentmode", category: "ScreenSaver")
    private var observers: [NSObjectProtocol] = []
    private weak var settings: AppSettingsStore?
    private weak var store: SilentModeStore?
    private var stateBeforeScreenSaver: Bool?
    private var didEnableForCurrentScreenSaver = false

    func start(settings: AppSettingsStore, store: SilentModeStore) {
        guard observers.isEmpty else {
            return
        }

        self.settings = settings
        self.store = store

        let startObserver = DistributedNotificationCenter.default().addObserver(
            forName: .screenSaverDidStart,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenSaverDidStart()
            }
        }

        let stopObserver = DistributedNotificationCenter.default().addObserver(
            forName: .screenSaverDidStop,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.screenSaverDidStop()
            }
        }

        observers.append(contentsOf: [startObserver, stopObserver])
    }

    private func screenSaverDidStart() {
        guard settings?.turnOnWithScreenSaver == true else {
            return
        }

        store?.refreshFromSystem(updateStatus: false)
        stateBeforeScreenSaver = store?.isSilentModeEnabled
        didEnableForCurrentScreenSaver = stateBeforeScreenSaver == false

        logger.info("Screen saver started; enabling Silent Mode")
        store?.enableForScreenSaver()
    }

    private func screenSaverDidStop() {
        guard settings?.turnOnWithScreenSaver == true else {
            resetScreenSaverState()
            return
        }

        guard didEnableForCurrentScreenSaver, stateBeforeScreenSaver == false else {
            resetScreenSaverState()
            return
        }

        logger.info("Screen saver stopped; restoring Silent Mode")
        store?.restoreAfterScreenSaver()
        resetScreenSaverState()
    }

    private func resetScreenSaverState() {
        stateBeforeScreenSaver = nil
        didEnableForCurrentScreenSaver = false
    }
}

private extension Notification.Name {
    static let screenSaverDidStart = Notification.Name("com.apple.screensaver.didstart")
    static let screenSaverDidStop = Notification.Name("com.apple.screensaver.didstop")
}
