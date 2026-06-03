import SwiftUI
import WidgetKit

@available(macOS 26.0, *)
struct SilentModeWidget: Widget {
    let kind = "com.josh.silentmode.widget"

    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: SilentModeWidgetProvider()) { entry in
            SilentModeWidgetView(entry: entry)
                .containerBackground(.fill.tertiary, for: .widget)
        }
        .configurationDisplayName("Silent Mode")
        .description("Shows whether Silent Mode is muting alert sounds.")
        .supportedFamilies([.systemSmall])
    }
}

@available(macOS 26.0, *)
struct SilentModeWidgetProvider: TimelineProvider {
    func placeholder(in context: Context) -> SilentModeWidgetEntry {
        SilentModeWidgetEntry(date: Date(), isEnabled: false)
    }

    func getSnapshot(in context: Context, completion: @escaping (SilentModeWidgetEntry) -> Void) {
        completion(currentEntry())
    }

    func getTimeline(in context: Context, completion: @escaping (Timeline<SilentModeWidgetEntry>) -> Void) {
        completion(Timeline(entries: [currentEntry()], policy: .after(Date().addingTimeInterval(300))))
    }

    private func currentEntry() -> SilentModeWidgetEntry {
        let isEnabled = (try? SilentModeController().isSilentModeEnabled()) ?? false
        return SilentModeWidgetEntry(date: Date(), isEnabled: isEnabled)
    }
}

@available(macOS 26.0, *)
struct SilentModeWidgetEntry: TimelineEntry {
    let date: Date
    let isEnabled: Bool
}

@available(macOS 26.0, *)
struct SilentModeWidgetView: View {
    let entry: SilentModeWidgetEntry

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Image(systemName: entry.isEnabled ? "bell.slash.fill" : "bell.fill")
                .font(.system(size: 30, weight: .semibold))
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(entry.isEnabled ? .red : .primary)

            VStack(alignment: .leading, spacing: 2) {
                Text("Silent Mode")
                    .font(.headline)
                Text(entry.isEnabled ? "On" : "Off")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .padding()
    }
}
