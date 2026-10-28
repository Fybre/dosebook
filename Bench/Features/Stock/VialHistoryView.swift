import SwiftUI
import BenchCore
import BenchStore

/// One vial's story: where it came from, every dose that came out of it, and how long the rest lasts.
struct VialHistoryView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var vial: Vial

    var body: some View {
        let data = store.data
        let now = nowMillis()
        // Read afresh, so a dose logged or edited while this is open shows.
        let v = data.mine.vials.first { $0.id == vial.id } ?? vial
        let h = vialHistory(data, v, nowMs: now)
        let peptide = data.peptide(v.peptideId)
        let currency = v.currency ?? data.settings.currency
        GroupedList {
            Section {
                row(t("ios_vh_state"), stateName(v))
                if let s = v.supplier, !s.isEmpty { row(t("ios_vh_supplier"), s) }
                if let l = v.lot, !l.isEmpty { row(t("ios_vh_lot"), l) }
                if let c = v.cost { row(t("ios_vh_cost"), formatMoney(c, currency)) }
                if let at = v.acquiredAt { row(t("ios_vh_added"), formatDate(at, nowMs: now)) }
                if let at = v.reconstitutedAt { row(t("ios_vh_mixed"), formatDate(at, nowMs: now)) }
                if let bud = v.budAt { row(t("ios_vh_use_by"), formatDate(bud, nowMs: now), tone: bud < now ? .rose : nil) }
                if let exp = v.expiresAt { row(t("ios_vh_expires"), formatDate(exp, nowMs: now), tone: exp < now ? .rose : nil) }
            } header: { Text("\(peptide?.name ?? v.peptideId) · \(jsNumberString(v.strengthMg)) mg") }

            if let water = v.diluentMl, water > 0 {
                Section(t("ios_vh_mixed_with")) {
                    row(t("ios_vh_water"), "\(trim(water, 2)) mL")
                    if let kind = v.diluent { row(t("ios_vh_water_kind"), diluentName(kind)) }
                    let conc = vialConcentration(v)
                    if conc.isFinite { row(t("ios_vh_concentration"), formatConcentration(conc)) }
                    if let b = data.mine.diluents.first(where: { $0.id == v.diluentBottleId }) {
                        row(t("ios_vh_bottle"), "\(diluentName(b.kind)), \(trim(b.volumeMl, 1)) mL")
                    }
                }
            }

            Section {
                row(t("ios_vh_drawn"), formatDose(h.drawnMcg))
                row(t("ios_vh_left"), formatDose(h.remainingMcg))
                if !h.doses.isEmpty {
                    row(t("ios_vh_taken"), String(h.doses.count))
                    row(t("ios_vh_average"), formatDose(h.averageMcg))
                    if let first = h.firstAt { row(t("ios_vh_first"), formatDate(first, nowMs: now)) }
                    if let last = h.lastAt { row(t("ios_vh_last"), formatDate(last, nowMs: now)) }
                }
                if let days = h.daysLeft, let end = h.emptyAt {
                    row(t("ios_vh_lasts"), "\(trim(days.rounded(), 0)) \(t("days")) · \(formatDate(end, nowMs: now))")
                }
            } footer: { FooterWrap { Text(t("ios_vh_lasts_hint")) } }

            Section(t("ios_vh_doses")) {
                if h.doses.isEmpty {
                    Text(t("ios_vh_none")).font(.footnote).foregroundStyle(.secondary)
                }
                ForEach(h.doses) { l in
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(formatDateTime(l.at, nowMs: now)).font(.subheadline)
                            if let site = l.site, routeHasSite(l.route) { Text(siteLabel(site)).font(.caption).foregroundStyle(.secondary) }
                        }
                        Spacer()
                        VStack(alignment: .trailing, spacing: 2) {
                            Text(doseLabel(l.doseMcg, peptide)).font(.subheadline.monospacedDigit())
                            if let u = l.units {
                                Text(t("ios_units_count", ["n": .string(trim(u, 2))])).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
        .readableWidth()
        .navigationTitle(t("ios_vial_history"))
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("done")) { dismiss() } } }
    }

    private func stateName(_ v: Vial) -> String {
        switch v.state {
        case .onOrder: t("stock_on_order")
        case .sealed: t("stock_sealed")
        case .reconstituted: t("stock_open")
        case .finished: t("stock_finished")
        default: v.state.rawValue.capitalized
        }
    }

    private func row(_ label: String, _ value: String, tone: Tone? = nil) -> some View {
        LabeledContent(label) { Text(value).monospacedDigit().foregroundStyle(tone?.color ?? .primary) }
    }
}
