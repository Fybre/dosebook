import SwiftUI
import Charts
import BenchCore
import BenchStore

/// Weight against one compound's dose steps: the line shaded by step, and how
/// weight moved during each, so a change of dose can be read against the scale.
struct WeightTrendView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var now: Millis
    @State private var peptideId: String?

    var body: some View {
        let data = store.data
        let mine = data.mine
        let unit = data.settings.weightUnit
        let series = weightSeries(mine.measurements)
        let compounds = mine.logs.filter { !$0.isSkipped }.map(\.peptideId).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let chosen = peptideId ?? mostTitratedCompound(mine.logs, now: now)
        let steps = chosen.map { doseSteps(mine.logs, peptideId: $0, now: now) } ?? []
        let perStep = weightDuring(steps, mine.measurements)
        let tones: [Tone] = [.sky, .grape, .tangerine, .mint, .rose, .leaf]
        GroupedList {
            if series.count < 2 || steps.isEmpty {
                Section { Text(t("ios_trend_empty")).foregroundStyle(.secondary) }
            } else {
                Section {
                    Picker(t("ios_trend_against"), selection: Binding(get: { chosen ?? "" }, set: { peptideId = $0 })) {
                        ForEach(compounds, id: \.self) { Text(data.peptide($0)?.name ?? $0).tag($0) }
                    }
                    let lo = min(series.first!.at, steps.first!.from), hi = max(series.last!.at, now)
                    Chart {
                        ForEach(Array(steps.enumerated()), id: \.offset) { i, s in
                            RectangleMark(xStart: .value("from", Date(millis: max(s.from, lo))), xEnd: .value("to", Date(millis: min(s.to, hi))))
                                .foregroundStyle(tones[i % tones.count].color.opacity(0.12))
                                .annotation(position: .top, alignment: .leading) {
                                    Text(formatDose(s.doseMcg)).font(.system(size: 9, weight: .semibold)).foregroundStyle(tones[i % tones.count].color)
                                }
                        }
                        if let goal = data.settings.weightGoal {
                            RuleMark(y: .value("goal", toDisplayWeight(goal.kg, unit)))
                                .foregroundStyle(Tone.sky.color).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                        }
                        ForEach(Array(series.enumerated()), id: \.offset) { _, p in
                            LineMark(x: .value("t", Date(millis: p.at)), y: .value("w", toDisplayWeight(p.kg, unit))).foregroundStyle(Color.primary)
                            PointMark(x: .value("t", Date(millis: p.at)), y: .value("w", toDisplayWeight(p.kg, unit))).foregroundStyle(Color.primary).symbolSize(14)
                        }
                    }
                    .chartXScale(domain: Date(millis: lo)...Date(millis: hi))
                    .chartYScale(domain: .automatic(includesZero: false))
                    .frame(height: 220)
                    .padding(.top, 12)
                }
                Section {
                    ForEach(Array(perStep.enumerated().reversed()), id: \.offset) { i, w in
                        HStack(alignment: .top, spacing: 10) {
                            RoundedRectangle(cornerRadius: 2).fill(tones[i % tones.count].color).frame(width: 4)
                            VStack(alignment: .leading, spacing: 3) {
                                HStack {
                                    Text(formatDose(w.step.doseMcg)).font(.subheadline.weight(.semibold))
                                    Spacer()
                                    if let rate = w.perWeekKg {
                                        Text(t("ios_trend_per_week", ["rate": .string((rate > 0 ? "+" : "−") + trim(abs(toDisplayWeight(rate, unit)), 2)), "unit": .string(unit.rawValue)]))
                                            .font(.subheadline.monospacedDigit()).foregroundStyle(rate < 0 ? Tone.leaf.color : Tone.tangerine.color)
                                    }
                                }
                                Text(i == perStep.count - 1 ? t("ios_trend_running", ["from": .string(formatDate(w.step.from))])
                                     : t("ios_trend_span", ["from": .string(formatDate(w.step.from)), "to": .string(formatDate(w.step.to))]))
                                    .font(.caption).foregroundStyle(.secondary)
                                if let c = w.changeKg {
                                    Text(t("ios_trend_change", ["change": .string((c > 0 ? "+" : c < 0 ? "−" : "") + trim(abs(toDisplayWeight(c, unit)), 1)), "unit": .string(unit.rawValue),
                                                                "weighins": .string(t("ios_trend_weighins", ["n": .number(Double(w.points))]))]))
                                        .font(.caption).foregroundStyle(.secondary)
                                } else {
                                    Text(t("ios_trend_too_few")).font(.caption).foregroundStyle(.tertiary)
                                }
                            }
                        }
                    }
                    FooterRow { Text(t("ios_trend_note")) }
                } header: { Text(t("ios_trend_steps")) } footer: { FooterWrap { Text(t("ios_trend_note")) }}
            }
        }
        .navigationTitle(t("ios_trend_title"))
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("done")) { dismiss() } } }
    }
}

/// Shows nearby Health readings for recorded dose changes, without assigning a cause.
struct VitalsTrendView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var now: Millis
    @State private var peptideId: String?

    var body: some View {
        let data = store.data
        let mine = data.mine
        let compounds = mine.logs.filter { !$0.isSkipped && $0.doseMcg > 0 }.map(\.peptideId)
            .reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
        let chosen = peptideId ?? mostTitratedCompound(mine.logs, now: now)
        let steps = chosen.map { doseSteps(mine.logs, peptideId: $0, now: now) } ?? []
        let comparisons = vitalsAroundDoseSteps(steps, mine.measurements, now: now)
        let hasVitals = mine.measurements.contains { $0.sleepHours != nil || $0.restingHrBpm != nil }

        GroupedList {
            Section { Text(t("ios_vitals_intro")).font(.footnote).foregroundStyle(.secondary) }
            if !compounds.isEmpty {
                Section {
                    Picker(t("ios_trend_against"), selection: Binding(get: { chosen ?? "" }, set: { peptideId = $0 })) {
                        ForEach(compounds, id: \.self) { Text(data.peptide($0)?.name ?? $0).tag($0) }
                    }
                }
            }
            if !hasVitals || steps.isEmpty {
                Section { Text(t("ios_vitals_empty")).foregroundStyle(.secondary) }
            } else {
                ForEach(Array(comparisons.suffix(8).enumerated().reversed()), id: \.offset) { _, comparison in
                    Section {
                        if comparison.afterTo > comparison.afterFrom {
                            Text(t("ios_vitals_period", [
                                "beforeFrom": .string(formatDate(comparison.beforeFrom)),
                                "beforeTo": .string(formatDate(addLocalDays(comparison.beforeTo, -1))),
                                "afterFrom": .string(formatDate(comparison.afterFrom)),
                                "afterTo": .string(formatDate(addLocalDays(comparison.afterTo, -1)))
                            ])).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(t("ios_vitals_no_after")).font(.caption).foregroundStyle(.secondary)
                        }
                        metric(t("ios_vitals_sleep"), comparison.sleepBefore, comparison.sleepAfter, unit: "h")
                        metric(t("ios_vitals_hr"), comparison.heartRateBefore, comparison.heartRateAfter, unit: "bpm")
                    } header: {
                        Text(t("ios_vitals_step", ["dose": .string(formatDose(comparison.step.doseMcg)),
                                                    "date": .string(formatDate(comparison.step.from))]))
                    }
                }
                Section { Text(t("ios_vitals_note")).font(.footnote).foregroundStyle(.secondary) }
            }
        }
        .navigationTitle(t("ios_vitals_title"))
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("done")) { dismiss() } } }
    }

    private func metric(_ title: String, _ before: VitalAverage, _ after: VitalAverage, unit: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title).font(.subheadline.weight(.semibold))
            Text(t("ios_vitals_values", [
                "before": .string(before.value.map { trim($0, 1) } ?? "—"),
                "beforeDays": .string(t("count_days", ["n": .number(Double(before.days))])),
                "after": .string(after.value.map { trim($0, 1) } ?? "—"),
                "afterDays": .string(t("count_days", ["n": .number(Double(after.days))])),
                "beforeUnit": .string(unit),
                "afterUnit": .string(unit)
            ])).font(.caption.monospacedDigit())
            if before.hasEnoughDays && after.hasEnoughDays, let b = before.value, let a = after.value {
                let delta = ((a - b) * 10).rounded() / 10
                Text(t("ios_vitals_difference", ["amount": .string((delta > 0 ? "+" : delta < 0 ? "−" : "") + trim(abs(delta), 1)),
                                                 "unit": .string(unit)]))
                    .font(.caption).foregroundStyle(.secondary)
            } else {
                Text(t("ios_vitals_insufficient")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }
}
