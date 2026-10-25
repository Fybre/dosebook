#if DEBUG && os(iOS)
import SwiftUI
import BenchCore
import BenchStore

/// `-widgetPreview`: every widget face, drawn from the current data, for a look
/// without a Home Screen.
struct WidgetPreviewScreen: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let snapshot = WidgetSync.snapshot(store.data)
        let now = Date()
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                face("Small", .small, 158, 158, snapshot, now)
                face("Medium", .medium, 338, 158, snapshot, now)
                HStack(alignment: .top, spacing: 18) {
                    face("Rectangular", .rectangular, 170, 72, snapshot, now)
                    face("Circular", .circular, 72, 72, snapshot, now)
                }
                face("Inline", .inline, 240, 28, snapshot, now)
                face("Small, names hidden", .small, 158, 158, { var s = snapshot; s.showNames = false; return s }(), now)
                face("Empty", .medium, 338, 158, { var s = snapshot; s.doses = []; return s }(), now)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func face(_ title: String, _ style: DoseWidgetStyle, _ w: CGFloat, _ h: CGFloat, _ s: WidgetSnapshot, _ now: Date) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.caption).foregroundStyle(.secondary)
            DoseWidgetView(snapshot: s, date: now, style: style)
                .padding(style == .small || style == .medium ? 16 : 8)
                .frame(width: w, height: h)
                .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: style == .small || style == .medium ? 22 : 12))
        }
    }
}
#endif
