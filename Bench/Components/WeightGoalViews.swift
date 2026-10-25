import SwiftUI
import BenchCore
import BenchStore

/// Under the weight chart: the goal, and where the last month's trend puts you
/// against it. Without a goal, a way to set one.
struct WeightGoalRow: View {
    @Environment(AppStore.self) private var store
    var now: Millis
    @State private var editing = false

    var body: some View {
        let data = store.data
        let unit = data.settings.weightUnit
        VStack(alignment: .leading, spacing: 6) {
            if let goal = data.settings.weightGoal {
                HStack {
                    Label(t("ios_goal_line", ["goal": .string(trim(toDisplayWeight(goal.kg, unit), 1)), "unit": .string(unit.rawValue)]), systemImage: "flag.checkered")
                        .font(.subheadline.weight(.semibold))
                    Spacer()
                    Button(t("ios_goal_change")) { editing = true }.font(.caption).buttonStyle(.bordered).controlSize(.mini)
                }
                Text(goalSentence(weightGoalProgress(data.mine.measurements, goal: goal, now: now), unit: unit, now: now))
                    .font(.footnote).foregroundStyle(.secondary)
            } else {
                Button { editing = true } label: { Label(t("ios_goal_set"), systemImage: "flag.checkered") }
                    .font(.caption).buttonStyle(.bordered).controlSize(.small)
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { WeightGoalSheet() } }
    }
}

func goalSentence(_ p: GoalProgress, unit: WeightUnit, now: Millis) -> String {
    func rate(_ kg: Double) -> String { (kg > 0 ? "+" : "−") + trim(abs(toDisplayWeight(kg, unit)), 2) }
    switch p {
    case .needsData: return t("ios_goal_needs_data")
    case .reached: return t("ios_goal_reached")
    case .onTrack(let perWeek, let at):
        return t("ios_goal_on_track", ["rate": .string(rate(perWeek)), "unit": .string(unit.rawValue), "date": .string(formatDate(at, nowMs: now))])
    case .notHeadingThere(let perWeek): return t("ios_goal_not_heading", ["rate": .string(rate(perWeek)), "unit": .string(unit.rawValue)])
    case .slow: return t("ios_goal_slow")
    }
}

/// Set, change or remove the goal.
struct WeightGoalSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var target: Double?
    @State private var loaded = false

    var body: some View {
        let data = store.data
        let unit = data.settings.weightUnit
        let latest = latestWeightKg(data.mine.measurements)
        Form {
            Section {
                OptionalNumberRow(label: t("ios_goal_target"), value: $target, suffix: unit.rawValue)
                if let latest {
                    LabeledContent(t("weight_latest"), value: "\(trim(toDisplayWeight(latest, unit), 1)) \(unit.rawValue)")
                }
            } footer: { FooterWrap { Text(t("ios_goal_sheet_hint")) } }
            FooterRow { Text(t("ios_goal_sheet_hint")) }
            if data.settings.weightGoal != nil {
                Section {
                    Button(t("ios_goal_remove"), role: .destructive) {
                        store.mutate { $0.settings.weightGoal = nil }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(t("ios_goal_title"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("save")) {
                    guard let target, target > 0 else { return }
                    let kg = fromDisplayWeight(target, unit)
                    // Where you are now says which way the goal runs; kept if it is only being changed.
                    let start = store.data.settings.weightGoal?.startKg ?? latest ?? kg
                    store.mutate { $0.settings.weightGoal = WeightGoal(kg: kg, startKg: start) }
                    dismiss()
                }
                .disabled((target ?? 0) <= 0)
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            target = data.settings.weightGoal.map { jsFixed(toDisplayWeight($0.kg, unit), 1) }
        }
    }
}
