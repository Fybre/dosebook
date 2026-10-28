import SwiftUI
import AppIntents

// The widget's faces. Plain views of a snapshot at a moment, so the app can draw
// them too, for a look at them without a Home Screen.

enum DoseWidgetStyle { case small, medium, rectangular, circular, inline }

let widgetTeal = Color(red: 0.051, green: 0.580, blue: 0.533)

struct DoseWidgetView: View {
    var snapshot: WidgetSnapshot?
    var date: Date
    var style: DoseWidgetStyle

    private var nowMs: Double { date.timeIntervalSince1970 * 1000 }
    private func label(_ key: String, _ fallback: String) -> String { snapshot?.labels[key] ?? fallback }
    /// Not yet logged, and not so long ago it has stopped meaning anything.
    private var doses: [WidgetDose] { (snapshot?.doses ?? []).filter { $0.at > nowMs - 12 * 3_600_000 } }
    private var showNames: Bool { snapshot?.showNames ?? false }

    private enum Phase { case overdue, dueNow, next }
    private func phase(_ d: WidgetDose) -> Phase {
        if d.at < nowMs - 3_600_000 { return .overdue }
        return d.at <= nowMs + 3_600_000 ? .dueNow : .next
    }
    private func phaseText(_ p: Phase) -> String {
        switch p {
        case .overdue: label("overdue", "Overdue")
        case .dueNow: label("dueNow", "Due now")
        case .next: label("next", "Next")
        }
    }
    private func phaseColor(_ p: Phase) -> Color { p == .overdue ? .red : p == .dueNow ? .orange : widgetTeal }
    private func time(_ d: WidgetDose) -> Text { Text(Date(timeIntervalSince1970: d.at / 1000), style: .time) }
    private func name(_ d: WidgetDose) -> String { showNames ? d.name : label("doseWord", "A dose") }

    var body: some View {
        switch style {
        case .small: small
        case .medium: medium
        case .rectangular: rectangular
        case .circular: circular
        case .inline: inline
        }
    }

    // MARK: Pieces

    private var emptyText: String {
        if snapshot == nil { return label("open", "Open Dosebook to set up") }
        if snapshot?.paused == true { return label("paused", "Paused") }
        return (snapshot?.expected ?? 0) > 0 ? label("allDone", "All done today") : label("nothing", "Nothing scheduled")
    }

    private func ring(_ size: CGFloat, line: CGFloat) -> some View {
        let expected = max(1, (snapshot?.expected ?? 0) - (snapshot?.skipped ?? 0))
        let fraction = min(1, Double(snapshot?.taken ?? 0) / Double(expected))
        return ZStack {
            Circle().stroke(Color.secondary.opacity(0.25), lineWidth: line)
            Circle().trim(from: 0, to: fraction).stroke(widgetTeal, style: StrokeStyle(lineWidth: line, lineCap: .round)).rotationEffect(.degrees(-90))
            if snapshot?.paused == true {
                Image(systemName: "pause.fill").font(.system(size: size * 0.32)).foregroundStyle(.secondary)
            } else {
                Text("\(snapshot?.taken ?? 0)").font(.system(size: size * 0.34, weight: .bold, design: .rounded)).minimumScaleFactor(0.5)
            }
        }
        .frame(width: size, height: size)
    }

    private func logButton(_ d: WidgetDose) -> some View {
        Button(intent: LogDoseIntent(protocolId: d.protocolId, doseAt: d.at)) {
            Label(label("log", "Log"), systemImage: "plus").font(.caption.weight(.semibold)).foregroundStyle(.white)
                .lineLimit(1).fixedSize()
                .padding(.horizontal, 10).padding(.vertical, 5).background(widgetTeal, in: Capsule())
        }
        .buttonStyle(.plain)
    }

    // MARK: Faces

    private var small: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                ring(34, line: 5)
                Spacer()
                if let s = snapshot, s.expected > 0 {
                    Text("\(s.taken)/\(max(0, s.expected - s.skipped))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
            if let d = doses.first {
                let p = phase(d)
                Text(phaseText(p).uppercased()).font(.system(size: 10, weight: .bold)).foregroundStyle(phaseColor(p))
                time(d).font(.title3.bold())
                Text(name(d)).font(.caption).lineLimit(1).privacySensitive()
                if p != .next { logButton(d) }
            } else {
                Text(emptyText).font(.footnote.weight(.semibold)).foregroundStyle(.secondary)
            }
        }
    }

    private var medium: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(spacing: 4) {
                ring(56, line: 7)
                Text(label("today", "Today")).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
            }
            if doses.isEmpty {
                Text(emptyText).font(.subheadline.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(doses.prefix(3)) { d in
                        let p = phase(d)
                        HStack(spacing: 8) {
                            Circle().fill(phaseColor(p)).frame(width: 7, height: 7)
                            time(d).font(.subheadline.weight(.semibold).monospacedDigit()).lineLimit(1).fixedSize()
                            Text(showNames ? "\(d.name)" : label("doseWord", "A dose")).font(.caption).lineLimit(1).truncationMode(.tail).privacySensitive()
                            Spacer(minLength: 0)
                            if p != .next { logButton(d) }
                        }
                    }
                }
            }
        }
    }

    private var rectangular: some View {
        VStack(alignment: .leading, spacing: 1) {
            if let d = doses.first {
                let p = phase(d)
                Text(phaseText(p)).font(.caption2.weight(.bold)).foregroundStyle(.secondary)
                time(d).font(.headline)
                Text(name(d)).font(.caption).lineLimit(1).privacySensitive()
            } else {
                Text(emptyText).font(.caption.weight(.semibold))
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var circular: some View {
        let expected = max(1, (snapshot?.expected ?? 0) - (snapshot?.skipped ?? 0))
        return Gauge(value: Double(min(snapshot?.taken ?? 0, expected)), in: 0...Double(expected)) {
            Image(systemName: "syringe")
        } currentValueLabel: {
            Text("\(snapshot?.taken ?? 0)")
        }
        .gaugeStyle(.accessoryCircularCapacity)
    }

    private var inline: some View {
        Group {
            if let d = doses.first { Text("\(phaseText(phase(d))) \(Text(Date(timeIntervalSince1970: d.at / 1000), style: .time))") }
            else { Text(emptyText) }
        }
    }
}
