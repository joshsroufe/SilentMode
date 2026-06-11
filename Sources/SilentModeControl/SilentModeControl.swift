import AppIntents
import os
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
        private let logger = Logger(subsystem: "com.josh.silentmode", category: "ControlCenter")

        var previewValue: Bool {
            false
        }

        func currentValue() async throws -> Bool {
            let controller = SilentModeController()
            let enabled: Bool
            if let sharedValue = controller.sharedSilentModeEnabled() {
                enabled = sharedValue
            } else {
                enabled = try controller.isSystemSilentModeEnabled()
            }
            logger.info("Control Center currentValue returned \(enabled)")
            return enabled
        }
    }
}

@available(macOS 26.0, *)
struct SetSilentModeIntent: SetValueIntent {
    static let title: LocalizedStringResource = "Set Silent Mode"
    private let logger = Logger(subsystem: "com.josh.silentmode", category: "ControlCenter")

    @Parameter(title: "Silent Mode")
    var value: Bool

    func perform() async throws -> some IntentResult {
        logger.info("Control Center perform started with value \(value)")
        let controller = SilentModeController()
        controller.setSharedSilentModeEnabled(value)
        logger.info("Control Center perform saved shared value \(value)")
        ControlCenter.shared.reloadControls(ofKind: "com.josh.silentmode.control")
        logger.info("Control Center perform requested control reload")
        return .result()
    }
}
