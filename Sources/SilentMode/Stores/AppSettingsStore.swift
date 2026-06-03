import AppKit
import Foundation
import Observation
import os
import ServiceManagement

@Observable
@MainActor
final class AppSettingsStore {
    private enum Key {
        static let openAtLogin = "Settings.openAtLogin"
        static let showInDock = "Settings.showInDock"
        static let showInMenuBar = "Settings.showInMenuBar"
    }

    private let defaults: UserDefaults
    private let logger = Logger(subsystem: "com.josh.silentmode", category: "Settings")

    private(set) var openAtLogin: Bool
    private(set) var showInDock: Bool
    private(set) var showInMenuBar: Bool

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.openAtLogin = defaults.object(forKey: Key.openAtLogin) as? Bool ?? false
        self.showInDock = Self.persistedShowInDock(defaults: defaults)
        self.showInMenuBar = defaults.object(forKey: Key.showInMenuBar) as? Bool ?? true
    }

    static func persistedShowInDock(defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: Key.showInDock) as? Bool ?? true
    }

    func applyStartupSettings() {
        applyDockVisibility()
    }

    func setOpenAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }

            openAtLogin = enabled
            defaults.set(enabled, forKey: Key.openAtLogin)
        } catch {
            logger.error("Failed to update login item: \(error.localizedDescription)")
        }
    }

    func setShowInDock(_ shown: Bool) {
        showInDock = shown
        defaults.set(shown, forKey: Key.showInDock)
        applyDockVisibility()
    }

    func setShowInMenuBar(_ shown: Bool) {
        showInMenuBar = shown
        defaults.set(shown, forKey: Key.showInMenuBar)
    }

    private func applyDockVisibility() {
        if showInDock {
            NSApp.setActivationPolicy(.regular)
            NSApp.activate(ignoringOtherApps: true)
        } else {
            NSApp.setActivationPolicy(.accessory)
        }
    }
}
