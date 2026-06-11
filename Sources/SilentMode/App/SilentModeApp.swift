import AppKit
import Darwin
import SwiftUI

@main
struct SilentModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SilentModeStore()
    @State private var settings = AppSettingsStore()
    @State private var screenSaverMonitor = ScreenSaverMonitor()

    var body: some Scene {
        WindowGroup("Silent Mode", id: "main") {
            ContentView(store: store, settings: settings)
                .frame(minWidth: 500, minHeight: 620)
                .onAppear {
                    settings.applyStartupSettings()
                    screenSaverMonitor.start(settings: settings, store: store)
                    store.refreshFromSystem(updateStatus: false)
                }
        }
        .windowResizability(.contentSize)
        .commands {
            CommandMenu("Silent Mode") {
                Button(store.isSilentModeEnabled ? "Turn Silent Mode Off" : "Turn Silent Mode On") {
                    store.toggleSilentMode()
                }
                .keyboardShortcut("s", modifiers: [.command, .shift])

                Divider()

                Button("Test Alert Sound") {
                    store.playTestAlert()
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
            }
        }

        MenuBarExtra(
            "Silent Mode",
            systemImage: store.isSilentModeEnabled ? "bell.slash.fill" : "bell.fill",
            isInserted: Binding(
                get: { settings.showInMenuBar },
                set: { settings.setShowInMenuBar($0) }
            )
        ) {
            MenuBarStatusView(store: store)
                .onAppear {
                    store.refreshFromSystem(updateStatus: false)
                }
        }
        .menuBarExtraStyle(.menu)
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private let singleInstanceGuard = SingleInstanceGuard()

    func applicationWillFinishLaunching(_ notification: Notification) {
        guard singleInstanceGuard.acquire() else {
            activateExistingInstance()
            NSApp.terminate(nil)
            return
        }

        NSApp.setActivationPolicy(AppSettingsStore.persistedShowInDock() ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppSettingsStore.persistedShowInDock() {
            NSApp.activate(ignoringOtherApps: true)
        }
    }

    private func activateExistingInstance() {
        guard let bundleIdentifier = Bundle.main.bundleIdentifier else {
            return
        }

        NSRunningApplication
            .runningApplications(withBundleIdentifier: bundleIdentifier)
            .filter { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
            .sorted { ($0.launchDate ?? .distantPast) < ($1.launchDate ?? .distantPast) }
            .first?
            .activate(options: [.activateAllWindows])
    }
}

final class SingleInstanceGuard {
    private var lockDescriptor: CInt = -1

    func acquire() -> Bool {
        guard lockDescriptor == -1 else {
            return true
        }

        let lockFileURL = lockFileURL()
        try? FileManager.default.createDirectory(
            at: lockFileURL.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )

        let descriptor = open(lockFileURL.path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard descriptor != -1 else {
            return true
        }

        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            lockDescriptor = descriptor
            return true
        }

        close(descriptor)
        return false
    }

    deinit {
        if lockDescriptor != -1 {
            flock(lockDescriptor, LOCK_UN)
            close(lockDescriptor)
        }
    }

    private func lockFileURL() -> URL {
        let applicationSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
        let baseURL = applicationSupport ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Application Support")
        return baseURL
            .appendingPathComponent("SilentMode", isDirectory: true)
            .appendingPathComponent("SilentMode.lock", isDirectory: false)
    }
}
