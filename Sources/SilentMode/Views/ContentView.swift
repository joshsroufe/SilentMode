import SwiftUI

struct ContentView: View {
    let store: SilentModeStore
    let settings: AppSettingsStore

    var body: some View {
        VStack(spacing: 24) {
            Spacer(minLength: 10)

            ToggleButton(store: store)

            VStack(spacing: 8) {
                Text(store.isSilentModeEnabled ? "Silent Mode On" : "Silent Mode Off")
                    .font(.system(size: 34, weight: .semibold, design: .rounded))

                Text(store.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .frame(maxWidth: 340)
            }

            HStack(spacing: 12) {
                Button {
                    store.playTestAlert()
                } label: {
                    Label("Test", systemImage: "speaker.wave.2")
                }

                Button {
                    store.refreshFromSystem()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
            }
            .buttonStyle(.bordered)

            SettingsSection(settings: settings)

            Spacer(minLength: 10)
        }
        .padding(40)
    }
}

private struct ToggleButton: View {
    let store: SilentModeStore

    var body: some View {
        Button {
            store.toggleSilentMode()
        } label: {
            ZStack {
                Circle()
                    .fill(store.isSilentModeEnabled ? Color.red : Color.secondary.opacity(0.14))
                    .frame(width: 150, height: 150)

                Image(systemName: store.isSilentModeEnabled ? "bell.slash.fill" : "bell.fill")
                    .font(.system(size: 68, weight: .semibold))
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(store.isSilentModeEnabled ? .white : .primary)
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(store.isSilentModeEnabled ? "Turn Silent Mode off" : "Turn Silent Mode on")
    }
}

private struct SettingsSection: View {
    let settings: AppSettingsStore

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Settings")
                .font(.headline)

            VStack(spacing: 10) {
                SettingsToggleRow(
                    title: "Open at login",
                    description: "Adds Silent Mode to startup items.",
                    isOn: Binding(
                        get: { settings.openAtLogin },
                        set: { settings.setOpenAtLogin($0) }
                    )
                )

                Divider()

                SettingsToggleRow(
                    title: "Show in Dock",
                    description: "Shows the application in the Dock when running.",
                    isOn: Binding(
                        get: { settings.showInDock },
                        set: { settings.setShowInDock($0) }
                    )
                )

                Divider()

                SettingsToggleRow(
                    title: "Show app menu bar item",
                    description: "Shows Silent Mode's app menu bar item.",
                    isOn: Binding(
                        get: { settings.showInMenuBar },
                        set: { settings.setShowInMenuBar($0) }
                    )
                )
            }

        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct SettingsToggleRow: View {
    let title: String
    let description: String
    @Binding var isOn: Bool

    var body: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout)

                Text(description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 16)

            Toggle("", isOn: $isOn)
                .labelsHidden()
                .toggleStyle(.switch)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

#Preview {
    ContentView(store: SilentModeStore(), settings: AppSettingsStore())
}
