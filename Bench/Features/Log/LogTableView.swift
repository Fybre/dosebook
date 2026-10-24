#if os(macOS)
import SwiftUI
import BenchCore

/// The Log as a table, on the Mac: every dose a row, sorted by any column.
/// Double-click a row (or right-click, Edit) to change it.
struct LogTableView: View {
    var logs: [DoseLog]
    var data: AppData
    var palette: Palette
    var onEdit: (String) -> Void

    @State private var sort = [KeyPathComparator(\Row.at, order: .reverse)]
    @State private var selection: Set<String> = []

    struct Row: Identifiable {
        var id: String
        var at: Millis
        var name: String
        var tone: Color
        var dose: Double
        var doseText: String
        var drawn: String
        var route: String
        var site: String
        var notes: String
    }

    var body: some View {
        let rows = logs.map(row).sorted(using: sort)
        Table(rows, selection: $selection, sortOrder: $sort) {
            TableColumn(t("report_col_date"), value: \.at) { r in Text(formatDateTime(r.at)).monospacedDigit() }
                .width(min: 150, ideal: 170)
            TableColumn(t("report_col_compound"), value: \.name) { r in Text(r.name).foregroundStyle(r.tone) }
                .width(min: 120, ideal: 180)
            TableColumn(t("report_col_dose"), value: \.dose) { r in Text(r.doseText).monospacedDigit() }
                .width(min: 90, ideal: 130)
            TableColumn(t("ios_col_drawn"), value: \.drawn) { r in Text(r.drawn).monospacedDigit() }
                .width(min: 70, ideal: 90)
            TableColumn(t("report_col_route"), value: \.route)
                .width(min: 80, ideal: 110)
            TableColumn(t("report_col_site"), value: \.site)
                .width(min: 90, ideal: 150)
            TableColumn(t("labs_notes"), value: \.notes)
        }
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let id = ids.first {
                Button(t("log_edit_dose", ["when": .string(rows.first { $0.id == id }.map { formatDateTime($0.at) } ?? "")])) { onEdit(id) }
            }
        } primaryAction: { ids in
            if let id = ids.first { onEdit(id) }
        }
    }

    private func row(_ l: DoseLog) -> Row {
        let peptide = data.peptide(l.peptideId)
        let tone = doseColor(palette, protocolId: l.protocolId, peptideId: l.peptideId)?.color ?? .primary
        // As the list shows them: tablets, presses or syringe marks, whichever this dose used.
        let drawn: String = l.isSkipped ? ""
            : l.tablets.map { t("count_tablets", ["n": .string(trim($0, 2))]) }
            ?? (l.route == .intranasal ? l.presses.map { t("count_presses", ["n": .number($0)]) }
                : l.units.map { "\(trim($0, 2))\(l.syringeScale == .u40 ? " (U-40)" : "")" }) ?? ""
        let site = l.site.flatMap { !l.isSkipped && routeHasSite(l.route) ? siteLabel($0) : nil } ?? ""
        return Row(id: l.id, at: l.at, name: peptide?.name ?? l.peptideId, tone: tone,
                   dose: l.isSkipped ? -1 : l.doseMcg,
                   doseText: l.isSkipped ? t("log_skipped") : doseLabel(l.doseMcg, peptide),
                   drawn: drawn, route: l.route.label, site: site, notes: l.notes ?? "")
    }
}
#endif
