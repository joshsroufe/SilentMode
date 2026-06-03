import SwiftUI

struct MenuBarStatusView: View {
    @Environment(\.openWindow) private var openWindow

    let store: SilentModeStore

    var body: some View {
        Button {
            store.toggleSilentMode()
        } label: {
            Label(store.isSilentModeEnabled ? "Turn Off" : "Turn On", systemImage: store.isSilentModeEnabled ? "bell.slash.fill" : "bell.fill")
        }

        Divider()

        Button {
            store.playTestAlert()
        } label: {
            Label("Test Alert", systemImage: "speaker.wave.2")
        }

        Button {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "main")
        } label: {
            Label("Open App", systemImage: "macwindow")
        }

        Divider()

        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }
}
