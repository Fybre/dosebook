import SwiftUI
import BenchCore
import BenchStore

/// Every weigh-in of the profile showing, newest first: when, how much, and how far it moved from the one before.
struct WeightHistoryView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: BodyMeasurement?
    @State private var adding = false

    var body: some View {
        let data = store.data
        let unit = data.settings.weightUnit
        // Newest first; each row's change is from the reading just before it in time.
        let rows = data.mine.measurements.filter { ($0.weightKg ?? 0) > 0 }.sorted { $0.at > $1.at }
        GroupedList {
            if rows.isEmpty {
                Section { Text(t("ios_weight_history_none")).foregroundStyle(.secondary) }
            } else {
                Section {
                    ForEach(Array(rows.enumerated()), id: \.element.id) { i, m in
                        let kg = m.weightKg ?? 0
                        let delta = i + 1 < rows.count ? toDisplayWeight(kg, unit) - toDisplayWeight(rows[i + 1].weightKg ?? kg, unit) : nil
                        Button { editing = m } label: { row(m, kg: kg, delta: delta, unit: unit) }
                            .buttonStyle(.plain)
                            .rowActions {
                                Button(t("stock_delete"), role: .destructive) { remove(m) }
                            }
                    }
                }
            }
        }
        .navigationTitle(t("ios_weight_history"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label(t("ios_profile_weight_add"), systemImage: "plus") }
            }
        }
        .sheet(item: $editing) { m in NavigationStack { WeightEntry(editing: m) } }
        .sheet(isPresented: $adding) { NavigationStack { WeightEntry() } }
    }

    private func row(_ m: BodyMeasurement, kg: Double, delta: Double?, unit: WeightUnit) -> some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 2) {
                Text(formatDate(m.at)).font(.subheadline.weight(.semibold))
                HStack(spacing: 4) {
                    Text(formatTime(m.at))
                    if m.source == .healthConnect { Image(systemName: "heart.fill").accessibilityHidden(true) }
                }
                .font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text("\(trim(toDisplayWeight(kg, unit), 1)) \(unit.rawValue)").font(.subheadline.monospacedDigit())
                if let delta, abs(delta) >= 0.05 {
                    Text((delta > 0 ? "+" : "−") + trim(abs(delta), 1))
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                }
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
    }

    /// A reading that also carries other measurements loses only its weight.
    private func remove(_ m: BodyMeasurement) {
        let other = m.waistCm != nil || m.bodyFatPct != nil || m.sleepHours != nil || m.restingHrBpm != nil || !(m.notes ?? "").isEmpty
        store.mutate { d in
            if other { d.updateMeasurement(m.id) { $0.weightKg = nil } } else { d.removeMeasurement(m.id) }
        }
    }
}
