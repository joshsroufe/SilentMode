import SwiftUI
import WidgetKit

@available(macOS 26.0, *)
@main
struct SilentModeControlBundle: WidgetBundle {
    var body: some Widget {
        SilentModeWidget()
        SilentModeControl()
    }
}
