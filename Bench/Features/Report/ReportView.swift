import SwiftUI
import UIKit
import BenchCore
import BenchStore

/// What a clinician needs on one page or a few: what is running, labs, outcomes, history.
/// Shared as a PDF made on the device; nothing leaves it unless you send it.
struct ReportView: View {
    @Environment(AppStore.self) private var store
    @State private var windowDays: Double = 90
    @State private var pdf: URL?

    var body: some View {
        let report = ReportModel(store.data, windowDays: windowDays)
        List {
            Section {
                Text(t("report_subtitle")).font(.footnote).foregroundStyle(.secondary)
                Picker(t("report_title"), selection: $windowDays) {
                    Text(t("report_last_30")).tag(30.0)
                    Text(t("report_last_90")).tag(90.0)
                    Text(t("report_last_6_months")).tag(180.0)
                    Text(t("report_last_year")).tag(365.0)
                }
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text(report.heading).font(.headline)
                    Text(report.meta).font(.caption).foregroundStyle(.secondary)
                    Text(report.compiled).font(.caption2).foregroundStyle(.secondary)
                }
            }
            tableSection(t("report_running"), report.running, empty: t("report_nothing_active"))
            if !report.interactions.isEmpty {
                Section(t("report_interactions")) {
                    ForEach(Array(report.interactions.enumerated()), id: \.offset) { _, i in
                        Text("**\(i.title).** \(i.detail)").font(.footnote)
                    }
                }
            }
            tableSection(t("report_bloodwork"), report.bloodwork, empty: t("report_no_labs"))
            Section(t("report_outcomes")) {
                ForEach(report.outcomes, id: \.label) { LabeledContent($0.label, value: $0.value) }
                if !report.feeling.isEmpty {
                    Text(t("report_mean_rating")).font(.caption).foregroundStyle(.secondary)
                    ForEach(report.feeling, id: \.label) { LabeledContent($0.label, value: $0.value) }
                }
            }
            .font(.footnote)
            if let s = report.suppression { Section(t("report_suppression")) { Text(s).font(.footnote) } }
            tableSection(t("report_dose_history"), report.history, empty: t("report_no_doses"), note: report.historyNote)
            Section { Text(report.footer).font(.caption2).foregroundStyle(.secondary) }
        }
        .navigationTitle(t("report_title"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if let pdf {
                    ShareLink(item: pdf) { Label(t("report_print"), systemImage: "square.and.arrow.up") }
                }
            }
        }
        .task(id: windowDays) { pdf = ReportPDF.write(report.html) }
    }

    @ViewBuilder private func tableSection(_ title: String, _ table: ReportModel.Table?, empty: String, note: String? = nil) -> some View {
        Section(title) {
            if let table {
                ForEach(Array(table.rows.enumerated()), id: \.offset) { _, row in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.first ?? "").font(.footnote.weight(.semibold))
                        ForEach(Array(row.enumerated().dropFirst()), id: \.offset) { i, cell in
                            HStack(alignment: .firstTextBaseline) {
                                Text(table.head[i]).font(.caption2).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                                Text(cell).font(.caption)
                            }
                        }
                    }
                }
                if let note { Text(note).font(.caption).foregroundStyle(.secondary) }
            } else {
                Text(empty).font(.footnote).foregroundStyle(.secondary)
            }
        }
    }
}

/// HTML to a paginated A4 PDF in the temporary directory.
@MainActor
enum ReportPDF {
    static func write(_ html: String) -> URL? {
        let formatter = UIMarkupTextPrintFormatter(markupText: html)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(formatter, startingAtPageAt: 0)
        let page = CGRect(x: 0, y: 0, width: 595.2, height: 841.8)
        renderer.setValue(page, forKey: "paperRect")
        renderer.setValue(page.insetBy(dx: 40, dy: 44), forKey: "printableRect")
        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, page, nil)
        for i in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: i, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bench-report.pdf")
        do { try data.write(to: url, options: .atomic) } catch { return nil }
        return url
    }
}
