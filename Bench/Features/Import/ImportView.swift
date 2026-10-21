import SwiftUI
import PDFKit
import UniformTypeIdentifiers
import BenchCore
import BenchStore

/// Import from another app, or restore one of your own exports. Nothing is
/// written until the preview has been looked at and confirmed.
struct ImportView: View {
    @Environment(AppStore.self) private var store
    @State private var picking = false
    @State private var busy = false
    @State private var fileName = ""
    @State private var result: ReadResult?
    @State private var error: String?
    @State private var done: String?
    @State private var skipped = Set<String>()
    @State private var withDoses = true
    @State private var withWeights = true

    private static let types: [UTType] = [.commaSeparatedText, .tabSeparatedText, .plainText, .json, .pdf, .spreadsheet,
                                          UTType(filenameExtension: "xlsx"), UTType(filenameExtension: "xlsm")].compactMap { $0 }

    var body: some View {
        List {
            Section { Text(t("import_intro")).font(.footnote).foregroundStyle(.secondary) }
            if let done { Section { CalloutText(done).font(.footnote).callout(.sky) } }
            if let error {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        CalloutText(t("import_could_not_read"), bold: true)
                        CalloutText(error)
                    }
                    .font(.footnote).callout(.rose)
                }
            }
            switch result {
            case nil:
                Section {
                    Button { picking = true } label: { Label(busy ? t("import_reading") : t("import_choose_file"), systemImage: "doc.badge.plus") }
                        .disabled(busy)
                } footer: { Text(t("import_extensions")) }
            case .benchExport(let raw)?:
                benchExport(raw)
            case .labReport(let report, let lines)?:
                labPreview(report, lineCount: lines.count)
            case .table(_, let profile, let table, let plan)?:
                tablePreview(profile: profile, table: table, plan: plan)
            }
        }
        .navigationTitle(t("import_title"))
        .navigationBarTitleDisplayMode(.inline)
        #if DEBUG
        .onAppear {
            // `-importFile <path>` reads a file straight away, for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if result == nil, let i = args.firstIndex(of: "-importFile"), i + 1 < args.count { choose(URL(fileURLWithPath: args[i + 1])) }
        }
        #endif
        .fileImporter(isPresented: $picking, allowedContentTypes: Self.types) { r in
            guard case .success(let url) = r else { return }
            choose(url)
        }
    }

    // MARK: Reading

    private func choose(_ url: URL) {
        busy = true; error = nil; done = nil; result = nil
        defer { busy = false }
        let access = url.startAccessingSecurityScopedResource()
        defer { if access { url.stopAccessingSecurityScopedResource() } }
        fileName = url.lastPathComponent
        guard let data = try? Data(contentsOf: url) else { error = t("import_unreadable"); return }
        do {
            result = try readImportFile(name: url.lastPathComponent, bytes: [UInt8](data), options: ImportOptions(store.data), pdfFallback: pdfKitLines)
            withDoses = true; withWeights = true; skipped = []
        } catch let e as ImportError {
            error = e.message
        } catch {
            self.error = t("import_unreadable")
        }
    }

    /// PDFKit's reading of the text layer, for files whose fonts the built-in extractor cannot follow.
    private func pdfKitLines(_ bytes: [UInt8]) -> [String] {
        guard let doc = PDFDocument(data: Data(bytes)) else { return [] }
        return (0..<doc.pageCount).flatMap { (doc.page(at: $0)?.string ?? "").components(separatedBy: .newlines) }
    }

    private func reset() { result = nil; error = nil; fileName = ""; skipped = [] }

    // MARK: Own export

    @ViewBuilder private func benchExport(_ raw: Data) -> some View {
        let preview = try? AppData.load(raw)
        let doses = t("count_doses", ["n": .number(Double(preview?.logs.count ?? 0))])
        let protocols = t("count_protocols", ["n": .number(Double(preview?.protocols.count ?? 0))])
        Section {
            VStack(alignment: .leading, spacing: 4) {
                CalloutText(t("import_own_export"), bold: true)
                CalloutText(t("import_own_export_body", ["doses": .string(doses), "protocols": .string(protocols),
                                                          "current": .string(t("count_doses", ["n": .number(Double(store.data.mine.logs.count))]))]))
            }
            .font(.footnote).callout(.tangerine)
            Button(t("import_replace_everything"), role: .destructive) {
                do {
                    try store.importBackup(raw)
                    done = t("import_restored", ["doses": .string(doses), "protocols": .string(protocols)])
                } catch {
                    self.error = t("ios_import_not_bench")
                }
                reset()
            }
            Button(t("cancel"), action: reset)
        }
    }

    // MARK: Table

    @ViewBuilder private func tablePreview(profile: ImportProfile, table: ImportTable, plan: ImportPlan) -> some View {
        let span = planSpan(plan)
        let nothing = planIsEmpty(plan)
        let selectedNothing = (!withDoses || plan.doses.isEmpty) && (!withWeights || plan.weights.isEmpty)
        Section {
            HStack {
                Pill(text: profile.name, tone: .mint)
                Text("\(fileName) · \(t("count_rows", ["n": .number(Double(table.records.count))]))"
                     + (span.map { " · " + t("import_span", ["from": .string(formatDate($0.from)), "to": .string(formatDate($0.to))]) } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            Toggle(isOn: $withDoses) {
                VStack(alignment: .leading) {
                    Text(t("import_new_doses", ["n": .number(Double(plan.doses.count))]))
                    Text(plan.duplicateDoses > 0 ? t("import_dupes", ["n": .number(Double(plan.duplicateDoses))]) : t("import_none_skipped")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(plan.doses.isEmpty)
            Toggle(isOn: $withWeights) {
                VStack(alignment: .leading) {
                    Text(t("import_new_weights", ["n": .number(Double(plan.weights.count))]))
                    Text(plan.duplicateWeights > 0 ? t("import_dupes", ["n": .number(Double(plan.duplicateWeights))]) : t("import_none_skipped")).font(.caption).foregroundStyle(.secondary)
                }
            }
            .disabled(plan.weights.isEmpty)
        }
        if !plan.doses.isEmpty {
            Section(t("import_first_last")) {
                let sample = plan.doses.count <= 4 ? plan.doses : Array(plan.doses.prefix(2) + plan.doses.suffix(2))
                ForEach(Array(sample.enumerated()), id: \.offset) { _, d in
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            Text(formatDose(d.doseMcg)).font(.subheadline.monospacedDigit())
                            Text(d.peptideName).font(.subheadline)
                            Spacer()
                            Text(t("import_source_row", ["n": .number(Double(d.sourceRow))])).font(.caption2).foregroundStyle(.tertiary)
                        }
                        Text(formatDateTime(d.at) + (d.site.map { " · " + siteLabel($0) } ?? "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
            }
        }
        if !plan.unresolved.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label { CalloutText(t("import_not_in_library"), bold: true) } icon: { Image(systemName: "exclamationmark.triangle").foregroundStyle(Tone.tangerine.color) }
                    ForEach(plan.unresolved, id: \.label) { u in
                        CalloutText(t("import_unresolved_row", ["label": .string(u.label), "rows": .string(t("count_rows", ["n": .number(Double(u.rows.count))])),
                                                                 "list": .string(u.rows.prefix(6).map(String.init).joined(separator: ", ") + (u.rows.count > 6 ? "…" : ""))]))
                    }
                    CalloutText(t("import_add_compound"))
                }
                .font(.footnote).callout(.tangerine)
            }
        }
        if !plan.problems.isEmpty {
            Section {
                DisclosureGroup(t("import_rows_unreadable", ["rows": .string(t("count_rows", ["n": .number(Double(plan.problems.count))]))])) {
                    ForEach(Array(plan.problems.prefix(20).enumerated()), id: \.offset) { _, p in
                        Text("**\(t("import_row_label", ["n": .number(Double(p.sourceRow))]))** \(p.reason)").font(.caption)
                    }
                }
            }
        }
        if nothing { Section { CalloutText(t("import_nothing_new")).font(.footnote).callout(.sky) } }
        Section {
            Button { apply(plan) } label: { Label(t("import_action", ["what": .string(describePlan(plan))]), systemImage: "square.and.arrow.down") }
                .disabled(nothing || selectedNothing)
            Button(t("cancel"), action: reset)
        }
    }

    private func apply(_ plan: ImportPlan) {
        let logs = withDoses ? plan.doses.map {
            DoseLog(id: "", profileId: "", peptideId: $0.peptideId, at: $0.at, doseMcg: $0.doseMcg, route: .subcutaneous, site: $0.site, notes: $0.notes)
        } : []
        let weights = withWeights ? plan.weights.map { BodyMeasurement(id: "", profileId: "", at: $0.at, weightKg: $0.weightKg, source: .manual) } : []
        store.mutate { $0.importHistory(logs: logs, measurements: weights) }
        done = t("import_imported", ["doses": .string(t("count_doses", ["n": .number(Double(logs.count))])),
                                     "weights": .string(t("count_weights", ["n": .number(Double(weights.count))]))])
        reset()
    }

    // MARK: Lab report

    @ViewBuilder private func labPreview(_ report: LabReport, lineCount: Int) -> some View {
        let keeping = report.candidates.filter { !skipped.contains($0.markerId) }
        let suspect = report.candidates.filter { $0.confidence == .unitMismatch }
        let markers = t("count_markers", ["n": .number(Double(report.candidates.count))])
        let when = report.collectedAt.map { formatDate($0) } ?? t("import_lab_today")
        Section {
            Label(t("import_lab_report"), systemImage: "drop.fill").font(.subheadline.bold()).foregroundStyle(Tone.sky.color)
            Text("\(fileName) · \(t("import_lines_read", ["n": .number(Double(lineCount))]))").font(.caption).foregroundStyle(.secondary)
            Text((report.lab.map { t("import_lab_recognised_from", ["markers": .string(markers), "lab": .string($0), "date": .string(when)]) }
                  ?? t("import_lab_recognised", ["markers": .string(markers), "date": .string(when)]))
                 + (report.collectedAt == nil ? " " + t("import_lab_no_date") : "") + " " + t("import_lab_check"))
                .font(.footnote)
        }
        if !suspect.isEmpty {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    CalloutText(t("import_units_title"), bold: true)
                    CalloutText(t("import_units_body", ["markers": .string(suspect.map(\.markerName).joined(separator: ", "))]))
                }
                .font(.footnote).callout(.tangerine)
            }
        }
        Section {
            ForEach(report.candidates, id: \.markerId) { c in
                let on = !skipped.contains(c.markerId)
                Button {
                    if on { skipped.insert(c.markerId) } else { skipped.remove(c.markerId) }
                } label: {
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: on ? "checkmark.circle.fill" : "circle").foregroundStyle(on ? Color.accentColor : .secondary)
                        VStack(alignment: .leading, spacing: 3) {
                            FlowLayout(spacing: 6) {
                                Text(c.markerName).font(.subheadline.weight(.medium))
                                Text("\(jsNumberString(c.value)) \(c.unit ?? c.expectedUnit)").font(.subheadline.monospacedDigit())
                                if c.refLow != nil || c.refHigh != nil {
                                    Text(t("import_ref_range", ["low": .string(c.refLow.map { jsNumberString($0) } ?? "n/a"), "high": .string(c.refHigh.map { jsNumberString($0) } ?? "n/a")]))
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                if c.confidence == .unitMismatch { Pill(text: t("import_expects_unit", ["unit": .string(c.expectedUnit)]), tone: .tangerine) }
                                if c.confidence == .loose { Pill(text: t("import_matched_loosely")) }
                            }
                            Text(c.source).font(.caption.monospaced()).foregroundStyle(.secondary)
                        }
                    }
                    .opacity(on ? 1 : 0.5)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
        Section {
            Button(t("import_save_results", ["results": .string(t("count_results", ["n": .number(Double(keeping.count))]))])) { applyLabs(report) }
                .disabled(keeping.isEmpty)
            Button(t("cancel"), action: reset)
        }
    }

    private func applyLabs(_ report: LabReport) {
        let at = report.collectedAt ?? nowMillis()
        let rows = report.candidates.filter { !skipped.contains($0.markerId) }
        store.mutate { d in
            for c in rows {
                d.addLab(LabResult(id: "", profileId: "", at: at, markerId: c.markerId, value: c.value, refLow: c.refLow, refHigh: c.refHigh, lab: report.lab))
            }
        }
        let saved = t("import_saved_results", ["results": .string(t("count_results", ["n": .number(Double(rows.count))])), "date": .string(formatDate(at))])
        done = report.collectedAt == nil ? "\(saved) \(t("import_no_date_used"))" : saved
        reset()
    }
}
