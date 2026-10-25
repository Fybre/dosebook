import SwiftUI
import WidgetKit

struct DoseEntry: TimelineEntry {
    let date: Date
    let snapshot: WidgetSnapshot?
}

struct DoseProvider: TimelineProvider {
    func placeholder(in context: Context) -> DoseEntry { DoseEntry(date: Date(), snapshot: nil) }

    func getSnapshot(in context: Context, completion: @escaping (DoseEntry) -> Void) {
        completion(DoseEntry(date: Date(), snapshot: SharedStore.readSnapshot()))
    }

    /// One face now, and one at each dose time after it, so "next" moves on by itself.
    func getTimeline(in context: Context, completion: @escaping (Timeline<DoseEntry>) -> Void) {
        let snapshot = SharedStore.readSnapshot()
        let now = Date()
        var dates = [now]
        for d in snapshot?.doses ?? [] {
            let at = Date(timeIntervalSince1970: d.at / 1000)
            // The moment it is due, and the moment it has been waiting an hour.
            for moment in [at.addingTimeInterval(-3600), at, at.addingTimeInterval(3600)] where moment > now { dates.append(moment) }
        }
        let unique = Array(Set(dates)).sorted().prefix(24)
        completion(Timeline(entries: unique.map { DoseEntry(date: $0, snapshot: snapshot) }, policy: .after(now.addingTimeInterval(30 * 60))))
    }
}

struct DoseWidgetEntryView: View {
    @Environment(\.widgetFamily) private var family
    var entry: DoseEntry

    private var style: DoseWidgetStyle {
        switch family {
        case .systemMedium: .medium
        case .accessoryRectangular: .rectangular
        case .accessoryCircular: .circular
        case .accessoryInline: .inline
        default: .small
        }
    }

    var body: some View {
        DoseWidgetView(snapshot: entry.snapshot, date: entry.date, style: style)
    }
}

struct DoseWidget: Widget {
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: "BenchNextDose", provider: DoseProvider()) { entry in
            DoseWidgetEntryView(entry: entry)
                .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("Next dose")
        .description("What is due, with a button to log it.")
        .supportedFamilies([.systemSmall, .systemMedium, .accessoryRectangular, .accessoryCircular, .accessoryInline])
    }
}

@main
struct BenchWidgetBundle: WidgetBundle {
    var body: some Widget { DoseWidget() }
}
