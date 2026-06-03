import AppIntents
import SwiftUI
import WidgetKit

@available(macOS 26.0, *)
struct SilentModeControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(
            kind: "com.josh.silentmode.control",
            provider: Provider()
        ) { isEnabled in
            ControlWidgetToggle(
                isOn: isEnabled,
                action: SetSilentModeIntent()
            ) {
                Label("Silent Mode", systemImage: isEnabled ? "bell.slash.fill" : "bell.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(isEnabled ? Color.red : Color.primary)
            } valueLabel: { value in
                Label(value ? "On" : "Off", systemImage: value ? "bell.slash.fill" : "bell.fill")
                    .symbolRenderingMode(.monochrome)
                    .foregroundStyle(value ? .red : .primary)
            }
            .tint(isEnabled ? .red : nil)
        }
        .displayName("Silent Mode")
        .description("Mute notification and alert sounds while keeping media audio on.")
    }
}

@available(macOS 26.0, *)
extension SilentModeControl {
    struct Provider: ControlValueProvider {
        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            try SilentModeController().isSilentModeEnabled()
        }
    }
}

@available(macOS 26.0, *)
struct SetSilentModeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Silent Mode"

    @Parameter(title: "Silent Mode")
    var value: Bool

    func perform() async throws -> some IntentResult {
        let controller = SilentModeController()
        controller.setSharedSilentModeEnabled(value)
        try? controller.applySystemSilentMode(value)
        ControlCenter.shared.reloadControls(ofKind: "com.josh.silentmode.control")
        return .result()
    }
}
