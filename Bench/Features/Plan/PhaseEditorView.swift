import SwiftUI
import BenchCore

func bandWeekRange(_ phases: [ProtocolPhase], _ index: Int) -> (start: Double, end: Double?) {
    var start = 1.0
    for i in 0..<index { start += max(0, phases[i].weeks) }
    if index == phases.count - 1 { return (start, nil) }
    return (start, start + max(0, phases[index].weeks) - 1)
}

func describeBandRange(_ phases: [ProtocolPhase], _ index: Int) -> String {
    let (start, end) = bandWeekRange(phases, index)
    guard let end else { return t("phase_week_onwards", ["start": .number(start)]) }
    if end == start { return t("phase_week_one", ["start": .number(start)]) }
    return t("phase_week_range", ["start": .number(start), "end": .number(end)])
}

/// Bands of weeks, each with a dose and, optionally, its own frequency.
struct PhaseEditorView: View {
    @Binding var phases: [ProtocolPhase]
    @Binding var unit: DoseUnit
    var protocolSchedule: Schedule

    var body: some View {
        Text(t("phase_intro")).font(.footnote).foregroundStyle(.secondary)
        Picker(t("phase_dose_unit"), selection: $unit) { Text("mcg").tag(DoseUnit.mcg); Text("mg").tag(DoseUnit.mg) }
            .pickerStyle(.segmented)
        ForEach(phases.indices, id: \.self) { i in band(i) }
        Button {
            let prev = phases.last
            phases.append(ProtocolPhase(step: phases.count + 1, doseMcg: prev?.doseMcg ?? 500, weeks: (prev?.weeks ?? 0) > 0 ? prev!.weeks : 4))
        } label: { Label(t("phase_add_band"), systemImage: "plus") }
        Text(t("phase_bands_ending", ["n": .number(Double(phases.count)), "dose": .string(formatDose(phases.last?.doseMcg ?? 0))]))
            .font(.caption).foregroundStyle(.secondary)
    }

    @ViewBuilder private func band(_ i: Int) -> some View {
        let phase = phases[i]
        let isLast = i == phases.count - 1
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(describeBandRange(phases, i)).font(.subheadline.bold())
                Spacer()
                if phases.count > 1 {
                    Button(role: .destructive) {
                        phases.remove(at: i)
                        for j in phases.indices { phases[j].step = j + 1 }
                    } label: { Image(systemName: "trash") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(t("phase_remove_band", ["n": .number(Double(i + 1))]))
                }
            }
            NumberRow(label: t("plan_dose"), value: Binding(
                get: { unit == .mg ? phases[i].doseMcg / 1000 : phases[i].doseMcg },
                set: { phases[i].doseMcg = unit == .mg ? $0 * 1000 : $0 }), suffix: unit.rawValue, range: 0...10_000_000)
            if isLast {
                Text(t("phase_runs_on")).font(.caption).foregroundStyle(.secondary)
            } else {
                NumberRow(label: t("phase_weeks"), value: Binding(get: { phases[i].weeks }, set: { phases[i].weeks = max(1, $0) }), suffix: t("weeks"), range: 1...104)
            }
            Picker(t("plan_how_often"), selection: Binding(
                get: { phase.schedule?.kind.rawValue ?? "inherit" },
                set: { v in
                    if v == "inherit" { phases[i].schedule = nil; return }
                    var s = phases[i].schedule ?? protocolSchedule
                    s.kind = ScheduleKind(rawValue: v)
                    phases[i].schedule = s
                })) {
                Text(t("phase_same_as_protocol")).tag("inherit")
                Text(t("plan_daily")).tag(ScheduleKind.daily.rawValue)
                Text(t("plan_every_n_days_short")).tag(ScheduleKind.intervalDays.rawValue)
                Text(t("plan_set_days")).tag(ScheduleKind.daysOfWeek.rawValue)
                Text(t("plan_as_needed")).tag(ScheduleKind.asNeeded.rawValue)
            }
            if let s = phase.schedule {
                if s.kind == .intervalDays {
                    NumberRow(label: t("plan_interval"), value: Binding(get: { phases[i].schedule?.intervalDays ?? 7 }, set: { phases[i].schedule?.intervalDays = max(1, $0) }), suffix: t("days"), range: 1...90)
                }
                if s.kind == .daysOfWeek {
                    WeekdayPicker(days: Binding(get: { phases[i].schedule?.daysOfWeek ?? [] }, set: { phases[i].schedule?.daysOfWeek = $0 }))
                }
                if s.kind != .asNeeded {
                    TimesOfDayEditor(times: Binding(
                        get: { phases[i].schedule?.timesOfDay ?? scheduleTimes(bandSchedule(protocolSchedule, phases[i].schedule)) },
                        set: { next in
                            phases[i].schedule?.timesOfDay = next
                            phases[i].schedule?.timeOfDay = next.filter { !$0.isEmpty }.sorted().first ?? "09:00"
                        }), dailyMcg: phase.doseMcg)
                }
            } else if protocolSchedule.kind != .asNeeded {
                let inherited = scheduleTimes(protocolSchedule)
                Text(describeSplit(phase.doseMcg, inherited) ?? t("phase_same_at_time", ["time": .string(inherited.first ?? "09:00")]))
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }
}
