import AppKit
import Combine
import SwiftUI

@main
struct SilentModeApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = SilentModeStore()
    @State private var settings = AppSettingsStore()
    private let syncTimer = Timer.publish(every: 1, on: .main, in: .common).autoconnect()

    var body: some Scene {
        WindowGroup("Silent Mode", id: "main") {
            ContentView(store: store, settings: settings)
                .frame(minWidth: 500, minHeight: 620)
                .onAppear {
                    settings.applyStartupSettings()
                    store.refreshFromSystem(updateStatus: false)
                }
                .onReceive(syncTimer) { _ in
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
    func applicationWillFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(AppSettingsStore.persistedShowInDock() ? .regular : .accessory)
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if AppSettingsStore.persistedShowInDock() {
            NSApp.activate(ignoringOtherApps: true)
        }
    }
}
