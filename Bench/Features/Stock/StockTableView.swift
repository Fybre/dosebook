#if os(macOS)
import SwiftUI
import BenchCore

/// The shelf as a table, on the Mac: a row for every vial, sorted by any column.
/// Double-click a row (or right-click) for its history, to edit it or to delete it.
struct StockTableView: View {
    var vials: [Vial]
    var ctx: RowContext
    var onHistory: (Vial) -> Void
    var onEdit: (Vial) -> Void
    var onDelete: (Vial) -> Void

    @State private var sort = [KeyPathComparator(\Row.name)]
    @State private var selection: Set<String> = []

    struct Row: Identifiable {
        var id: String
        var vial: Vial
        var name: String
        var strengthMg: Double
        var state: String
        var leftMcg: Double
        var percent: Double
        var dosesLeft: Double
        var useBy: Double
        var expires: Double
        var supplier: String
        var lot: String
        var cost: Double
        var added: Double
    }

    var body: some View {
        let rows = vials.map(row).sorted(using: sort)
        Table(rows, selection: $selection, sortOrder: $sort) {
            TableColumn(t("report_col_compound"), value: \.name) { r in Text(r.name).fontWeight(.medium) }
                .width(min: 120, ideal: 180)
            TableColumn(t("ios_col_strength"), value: \.strengthMg) { r in Text("\(jsNumberString(r.strengthMg)) mg").monospacedDigit() }
                .width(min: 70, ideal: 90)
            TableColumn(t("ios_vh_state"), value: \.state) { r in Text(r.state) }
                .width(min: 90, ideal: 110)
            TableColumn(t("stock_remaining"), value: \.leftMcg) { r in Text("\(formatDose(r.leftMcg)) · \(trim(r.percent * 100, 0))%").monospacedDigit() }
                .width(min: 110, ideal: 140)
            TableColumn(t("ios_col_doses_left"), value: \.dosesLeft) { r in Text(r.dosesLeft > 0 ? trim(r.dosesLeft, 0) : "").monospacedDigit() }
                .width(min: 70, ideal: 90)
            TableColumn(t("ios_vh_use_by"), value: \.useBy) { r in dateCell(r.useBy, tint: r.vial.budAt.map { $0 < ctx.now } ?? false) }
                .width(min: 90, ideal: 110)
            TableColumn(t("ios_vh_expires"), value: \.expires) { r in dateCell(r.expires, tint: r.vial.expiresAt.map { $0 < ctx.now } ?? false) }
                .width(min: 90, ideal: 110)
            TableColumn(t("ios_vh_supplier"), value: \.supplier)
                .width(min: 80, ideal: 130)
            TableColumn(t("ios_vh_lot"), value: \.lot)
                .width(min: 60, ideal: 90)
            TableColumn(t("ios_vh_cost"), value: \.cost) { r in
                Text(r.vial.cost.map { formatMoney($0, r.vial.currency ?? ctx.data.settings.currency) } ?? "").monospacedDigit()
            }
            .width(min: 70, ideal: 90)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let v = vials.first(where: { $0.id == ids.first }) {
                Button(t("ios_vial_history")) { onHistory(v) }
                Button(t("ios_vial_edit")) { onEdit(v) }
                Divider()
                Button(t("stock_delete"), role: .destructive) { onDelete(v) }
            }
        } primaryAction: { ids in
            if let v = vials.first(where: { $0.id == ids.first }) { onHistory(v) }
        }
    }

    @ViewBuilder private func dateCell(_ ms: Double, tint: Bool) -> some View {
        if ms.isFinite && ms > 0 {
            Text(formatDate(ms, nowMs: ctx.now)).monospacedDigit().foregroundStyle(tint ? Tone.rose.color : .primary)
        }
    }

    private func row(_ v: Vial) -> Row {
        let st = vialStatus(v, nowMs: ctx.now)
        let dose = ctx.doseFor(v.peptideId)
        return Row(id: v.id, vial: v, name: ctx.data.peptide(v.peptideId)?.name ?? v.peptideId, strengthMg: v.strengthMg,
                   state: stateName(v.state), leftMcg: st.remainingMcg, percent: st.fractionRemaining,
                   dosesLeft: dose > 0 && v.state != .onOrder ? (st.remainingMcg / dose).rounded(.down) : 0,
                   useBy: v.budAt ?? 0, expires: v.expiresAt ?? 0, supplier: v.supplier ?? "", lot: v.lot ?? "",
                   cost: v.cost ?? 0, added: v.acquiredAt ?? 0)
    }

    private func stateName(_ s: VialState) -> String {
        switch s {
        case .onOrder: t("stock_on_order")
        case .sealed: t("stock_sealed")
        case .reconstituted: t("stock_open")
        case .finished: t("stock_finished")
        default: s.rawValue.capitalized
        }
    }
}
#endif
