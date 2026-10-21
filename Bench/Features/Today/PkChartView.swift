import SwiftUI
import Charts
import BenchCore

/// Estimated levels for the last fortnight and the coming week. Dashed for a
/// curve not measured in people. Touch to read any moment.
struct PkChartView: View {
    var series: [PkSeries]
    var now: Millis
    var weights: [BodyMeasurement] = []
    var weightUnit: WeightUnit = .kg
    var describeVial: (String) -> String? = { _ in nil }
    /// Defaults to the last fortnight and the coming week.
    var range: ClosedRange<Millis>? = nil
    /// Chart and readout only, for a single compound's demonstration curve.
    var compact = false
    @State private var picked: Date?

    private var from: Millis { range?.lowerBound ?? now - 14 * DAY_MS }
    private var to: Millis { range?.upperBound ?? now + 7 * DAY_MS }

    var body: some View {
        // Enough points that a short half-life is not aliased into uneven spikes: at least
        // four per half-life, between 240 and 1500 across the three weeks shown.
        let shortest = series.map(\.params.halfLifeHours).min() ?? 24
        let steps = Int(min(1500, max(240, (to - from) / HOUR_MS / max(0.25, shortest / 4))))
        let samples = series.map { s in (s, levelSeries(from, to, steps, s.doses, s.params, s.referenceMcg)) }
        let at = picked.map(\.millis) ?? now
        VStack(alignment: .leading, spacing: 10) {
            if !compact {
                CardHeader(title: t("now_circulating"))
                FlowLegend(series: series)
            }
            Chart {
                ForEach(samples, id: \.0.id) { s, points in
                    ForEach(points, id: \.t) { p in
                        LineMark(x: .value("t", Date(millis: p.t)), y: .value("level", p.level), series: .value("s", s.id))
                            .foregroundStyle(s.tone.color)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: s.basis.map { $0 == .published ? [] : [5, 4] } ?? []))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(s.doses.filter { $0.at >= from && $0.at <= to }, id: \.at) { d in
                        PointMark(x: .value("t", Date(millis: d.at)), y: .value("level", 0))
                            .symbol(.triangle).symbolSize(30).foregroundStyle(s.tone.color)
                    }
                }
                RuleMark(x: .value("now", Date(millis: now))).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                if let picked { RuleMark(x: .value("picked", picked)).foregroundStyle(Color.accentColor) }
            }
            .chartXScale(domain: Date(millis: from)...Date(millis: to))
            .chartYAxis { AxisMarks(position: .leading) }
            .chartXSelection(value: $picked)
            .frame(height: 200)
            readout(at)
            if !compact { Text(t("now_curve_note")).font(.caption2).foregroundStyle(.secondary) }
        }
    }

    @ViewBuilder private func readout(_ at: Millis) -> some View {
        let rows = series.map { ($0, breakdownAt(at, $0.doses, $0.params, $0.referenceMcg)) }
            .filter { $0.1.total > 0.005 }
            .sorted { $0.1.total > $1.1.total }
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(formatDate(at)), \(formatTime(at))").font(.caption.bold())
                Text(abs(at - now) < 60_000 ? "now" : at > now ? "projected" : "past").font(.caption).foregroundStyle(.secondary)
                Spacer()
                Text(t("pk_touch_chart")).font(.caption2).foregroundStyle(.secondary)
            }
            if rows.isEmpty {
                Text(t("pk_nothing_circulating")).font(.caption).foregroundStyle(.secondary)
            }
            ForEach(rows, id: \.0.id) { s, b in
                VStack(alignment: .leading, spacing: 2) {
                    HStack {
                        Circle().fill(s.tone.color).frame(width: 7, height: 7)
                        Text(s.label).font(.footnote.weight(.medium))
                        Spacer()
                        Text(t("now_percent_of_peak", ["pct": .string(jsToFixed(b.total * 100, 0))])).font(.footnote.monospacedDigit())
                    }
                    ForEach(Array(b.contributions.enumerated()), id: \.offset) { _, c in
                        Text("  \(formatDose(c.dose.amountMcg)) · \(relativeTime(c.dose.at, nowMs: at)) · \(percent(c.share))"
                             + (c.dose.vialId.flatMap(describeVial).map { " · \($0)" } ?? ""))
                            .font(.caption2).foregroundStyle(.secondary)
                    }
                }
            }
        }
    }
}

private struct FlowLegend: View {
    var series: [PkSeries]
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { items }
            VStack(alignment: .leading, spacing: 4) { items }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
    @ViewBuilder private var items: some View {
        ForEach(series) { s in
            HStack(spacing: 4) {
                if s.basis == nil || s.basis == .published { Circle().fill(s.tone.color).frame(width: 8, height: 8) }
                else { Circle().strokeBorder(s.tone.color, lineWidth: 1.5).frame(width: 8, height: 8) }
                Text(s.label)
                if s.basis == .elsewhere { Text(t("now_estimated")).foregroundStyle(.tertiary) }
                if s.basis == .yours { Text(t("now_your_figure")).foregroundStyle(.tertiary) }
            }
        }
    }
}
