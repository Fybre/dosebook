import SwiftUI
import Charts
import BenchCore

/// Estimated levels for the last fortnight and the coming week. Dashed for a
/// curve not measured in people. Touch to read any moment.
struct PkChartView: View {
    var series: [PkSeries]
    var now: Millis
    /// Every weight reading; drawn on a right-hand axis when `showWeight` is on. Left empty for a chart with no weight.
    var weights: [BodyMeasurement] = []
    var weightUnit: WeightUnit = .kg
    var showWeight = false
    /// Given, the header shows a button for it, when there are readings in the chart's window.
    var onToggleWeight: (() -> Void)? = nil
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
        // Weight, scaled into the height of the levels so one chart carries both; its own labels run down the right.
        let readings = weightSeries(weights).filter { Double($0.at) >= from && Double($0.at) <= to }
        let plotWeight = showWeight && !readings.isEmpty
        let levelTop = max(1.2, (samples.flatMap { $0.1.map(\.level) }.max() ?? 1) * 1.08)
        let shown = readings.map { toDisplayWeight($0.kg, weightUnit) }
        let wLo = (shown.min() ?? 0), wHi = max(shown.max() ?? 1, wLo + (weightUnit == .lb ? 2 : 1))
        let scaled = { (w: Double) -> Double in levelTop * (0.1 + 0.8 * (w - wLo) / (wHi - wLo)) }
        VStack(alignment: .leading, spacing: 10) {
            if !compact {
                HStack {
                    CardHeader(title: t("now_circulating"))
                    if let onToggleWeight, !readings.isEmpty {
                        Button(action: onToggleWeight) { Label(t("weight_title"), systemImage: "scalemass") }
                            .font(.caption).controlSize(.mini)
                            .buttonStyle(.bordered)
                            .tint(showWeight ? Tone.leaf.color : nil)
                            .accessibilityLabel(showWeight ? t("weight_hide_on_chart") : t("weight_show_on_chart"))
                            .accessibilityAddTraits(showWeight ? .isSelected : [])
                    }
                }
                FlowLegend(series: series, weight: plotWeight)
            }
            Chart {
                ForEach(samples, id: \.0.id) { s, points in
                    ForEach(points, id: \.t) { p in
                        LineMark(x: .value("t", Date(millis: p.t)), y: .value("level", p.level), series: .value("s", s.id))
                            .foregroundStyle(s.tone.color)
                            .lineStyle(StrokeStyle(lineWidth: 2, dash: s.basis.map { $0 == .published ? [] : [5, 4] } ?? []))
                            .interpolationMethod(.monotone)
                    }
                    ForEach(Array(s.doses.filter { $0.at >= from && $0.at <= to }.enumerated()), id: \.offset) { _, d in
                        PointMark(x: .value("t", Date(millis: d.at)), y: .value("level", 0))
                            .symbol(.triangle).symbolSize(30).foregroundStyle(s.tone.color)
                    }
                }
                // One dose's own peak: above it, doses are stacking up.
                RuleMark(y: .value("one dose", 1.0)).foregroundStyle(.secondary.opacity(0.6)).lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 4]))
                RuleMark(x: .value("now", Date(millis: now))).foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [2, 3]))
                if plotWeight {
                    ForEach(Array(readings.enumerated()), id: \.offset) { _, r in
                        let y = scaled(toDisplayWeight(r.kg, weightUnit))
                        LineMark(x: .value("t", Date(millis: r.at)), y: .value("weight", y), series: .value("s", "weight"))
                            .foregroundStyle(Tone.leaf.color).lineStyle(StrokeStyle(lineWidth: 2)).interpolationMethod(.monotone)
                        PointMark(x: .value("t", Date(millis: r.at)), y: .value("weight", y)).foregroundStyle(Tone.leaf.color).symbolSize(28)
                    }
                }
                if let picked { RuleMark(x: .value("picked", picked)).foregroundStyle(Color.accentColor) }
            }
            .chartXScale(domain: Date(millis: from)...Date(millis: to))
            .modifier(LevelScale(fixedTop: plotWeight ? levelTop : nil))
            .chartYAxis {
                AxisMarks(position: .leading)
                if plotWeight {
                    AxisMarks(position: .trailing, values: [scaled(wLo), scaled((wLo + wHi) / 2), scaled(wHi)]) { v in
                        AxisValueLabel {
                            if let y = v.as(Double.self) {
                                Text(trim(wLo + (y / levelTop - 0.1) / 0.8 * (wHi - wLo), 1)).foregroundStyle(Tone.leaf.color)
                            }
                        }
                    }
                }
            }
            .chartYAxisLabel(t("ios_chart_axis"), position: .leading)
            .chartXSelection(value: $picked)
            .frame(height: 200).chartWhenActive(height: 200)
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
            if showWeight, let w = weightSeries(weights).min(by: { abs($0.at - at) < abs($1.at - at) }), abs(w.at - at) <= 3 * DAY_MS {
                HStack {
                    Circle().fill(Tone.leaf.color).frame(width: 7, height: 7)
                    Text(t("weight_title")).font(.footnote.weight(.medium))
                    Spacer()
                    Text("\(trim(toDisplayWeight(w.kg, weightUnit), 1)) \(weightUnit.rawValue) · \(relativeTime(w.at, nowMs: at))").font(.footnote.monospacedDigit())
                }
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

/// The levels' own scale, left to the chart unless weight is drawn in the same height and needs a known top.
private struct LevelScale: ViewModifier {
    var fixedTop: Double?
    func body(content: Content) -> some View {
        if let fixedTop { content.chartYScale(domain: 0...fixedTop) } else { content }
    }
}

private struct FlowLegend: View {
    var series: [PkSeries]
    var weight = false
    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 10) { items }
            VStack(alignment: .leading, spacing: 4) { items }
        }
        .font(.caption).foregroundStyle(.secondary)
    }
    @ViewBuilder private var items: some View {
        if weight {
            HStack(spacing: 4) { Circle().fill(Tone.leaf.color).frame(width: 8, height: 8); Text(t("weight_title")) }
        }
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
