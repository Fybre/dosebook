#if os(iOS)
import SwiftUI
import PhotosUI
import AVFoundation
import PDFKit
import UniformTypeIdentifiers
import BenchCore
import BenchStore

/// Report pages stay in memory; only verified, nonduplicate results are saved.
struct ScanLabView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var photos: [PhotosPickerItem] = []
    @State private var camera = false
    @State private var choosingPDF = false
    @State private var busy = false
    @State private var error: String?
    @State private var cameraDenied = false
    @State private var pages: [ScannedLabPage] = []
    @State private var pageID = UUID()
    @State private var zooming = false
    @State private var rows: [ScannedLabRow] = []
    @State private var at = Date()
    @State private var lab = ""
    @State private var missingDate = false

    private var page: ScannedLabPage? { pages.first { $0.id == pageID } }
    private var ready: [ScannedLabRow] {
        rows.filter { row in
            row.checked && row.valid && !duplicate(row) &&
            pages.contains { $0.id == row.pageID && $0.text == $0.parsedText }
        }
    }
    private func duplicate(_ row: ScannedLabRow) -> Bool {
        guard let value = row.value else { return false }
        if isDuplicateLab(markerId: row.candidate.markerId, value: value, at: at.millis, existing: store.data.mine.labs) { return true }
        // Only the first matching row in this report is eligible, regardless of page.
        return rows.prefix { $0.id != row.id }.contains { $0.candidate.markerId == row.candidate.markerId && $0.value == value }
    }

    var body: some View {
        GeometryReader { geometry in
            if !pages.isEmpty && geometry.size.width >= 700 {
                HStack(spacing: 0) {
                    photoReview.frame(width: geometry.size.width * 0.42)
                    reviewForm
                }
            } else {
                VStack(spacing: 0) {
                    if !pages.isEmpty { photoReview.frame(height: 230) }
                    reviewForm
                }
            }
        }
        .navigationTitle(t("ios_lab_scan_title"))
        .inlineTitle()
        .toolbar { ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } } }
        .interactiveDismissDisabled(busy)
        .fullScreenCover(isPresented: $camera) {
            CameraPicker { captured in Task { await read(captured) } }.ignoresSafeArea()
        }
        .sheet(isPresented: $zooming) {
            if let page { NavigationStack { LabPhotoZoom(image: page.image) } }
        }
        .alert(t("ios_lab_scan_camera_denied"), isPresented: $cameraDenied) {
            Button(t("ios_open_settings")) {
                if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
            }
            Button(t("cancel"), role: .cancel) {}
        }
        .fileImporter(isPresented: $choosingPDF, allowedContentTypes: [.pdf]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else {
                error = t("ios_lab_pdf_unreadable")
                return
            }
            Task { await readPDF(data) }
        }
        #if DEBUG
        .task {
            let args = ProcessInfo.processInfo.arguments
            if pages.isEmpty, let i = args.firstIndex(of: "-labPDF"), i + 1 < args.count,
               let data = try? Data(contentsOf: URL(fileURLWithPath: args[i + 1])) {
                await readPDF(data)
            }
            if pages.isEmpty, let i = args.firstIndex(of: "-labPhotos"), i + 1 < args.count {
                busy = true
                for path in args[i + 1].components(separatedBy: ",") {
                    if let image = UIImage(contentsOfFile: path) { await appendPage(image) }
                }
                busy = false
            }
        }
        #endif
        .onChange(of: photos) { _, items in
            guard !items.isEmpty else { return }
            Task {
                busy = true; error = nil
                defer { busy = false; photos = [] }
                for item in items {
                    do {
                        guard let data = try await item.loadTransferable(type: Data.self), let image = UIImage(data: data) else {
                            error = t("ios_lab_scan_unreadable"); continue
                        }
                        await appendPage(image)
                    } catch { self.error = t("ios_lab_scan_unreadable") }
                }
            }
        }
    }

    private var photoReview: some View {
        VStack(spacing: 8) {
            if let page {
                Button { zooming = true } label: {
                    Image(uiImage: page.image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
                .buttonStyle(.plain)
                .accessibilityLabel(t("ios_lab_zoom"))
                Picker(t("ios_lab_page"), selection: $pageID) {
                    ForEach(Array(pages.enumerated()), id: \.element.id) { index, p in
                        Text(t("ios_lab_page_number", ["n": .number(Double(index + 1))])).tag(p.id)
                    }
                }.pickerStyle(.menu)
            }
        }
        .padding(8)
        .background(Color(.secondarySystemGroupedBackground))
    }

    private var reviewForm: some View {
        Form {
            Section {
                Text(t("ios_lab_multipage_intro")).font(.footnote).foregroundStyle(.secondary)
                Button(action: takePhoto) { Label(t("ios_scan_camera"), systemImage: "camera") }
                    .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                PhotosPicker(selection: $photos, maxSelectionCount: 10, matching: .images) {
                    Label(t("ios_scan_library"), systemImage: "photo")
                }
                Button { choosingPDF = true } label: {
                    Label(t("ios_lab_choose_pdf"), systemImage: "doc.richtext")
                }
            }.disabled(busy)
            if busy { Section { ProgressView(t("ios_lab_reading")) } }
            if let error { Section { Text(error).foregroundStyle(.red) } }
            if pages.contains(where: { p in p.collectedAt.map { startOfLocalDay($0) != startOfLocalDay(at.millis) } ?? false }) {
                Section { Text(t("ios_lab_page_date")).foregroundStyle(.orange) }
            }
            if let page {
                Section {
                    DisclosureGroup(t("ios_scan_raw")) {
                        TextEditor(text: Binding(get: { self.page?.text ?? "" }, set: { value in
                            if let i = pages.firstIndex(where: { $0.id == pageID }) { pages[i].text = value }
                        })).frame(minHeight: 150).font(.caption.monospaced())
                        Button(t("ios_lab_scan_parse")) { parsePage(pageID) }
                    }
                    if page.text != page.parsedText { Text(t("ios_lab_reparse_needed")).font(.footnote).foregroundStyle(.orange) }
                    Button(t("ios_lab_remove_page"), role: .destructive) {
                        rows.removeAll { $0.pageID == pageID }
                        pages.removeAll { $0.id == pageID }
                        pageID = pages.first?.id ?? UUID()
                    }
                }.disabled(busy)
            }
            if !rows.isEmpty {
                Section {
                    DatePicker(t("log_when"), selection: $at, displayedComponents: .date)
                    if missingDate { Text(t("ios_lab_scan_date")).font(.footnote).foregroundStyle(.secondary) }
                    TextField(t("labs_lab_name"), text: $lab)
                    Text(t("ios_lab_scan_review")).font(.footnote).foregroundStyle(.secondary)
                }
                // Every row by identity, showing this page's: a filtered array of bindings
                // points at positions, and removing a page could leave one pointing past the end.
                ForEach($rows) { $row in
                    if row.pageID == pageID {
                    Section(row.candidate.markerName) {
                        Text(row.candidate.source).font(.caption.monospaced()).textSelection(.enabled)
                        if duplicate(row) {
                            Text(t("ios_lab_duplicate")).font(.footnote).foregroundStyle(.orange)
                        } else if row.candidate.confidence != .exact || row.candidate.unit == nil {
                            Text(t("ios_lab_uncertain")).font(.footnote).foregroundStyle(.orange)
                        }
                        if row.candidate.confidence == .unitMismatch {
                            Text(t("ios_lab_scan_units", ["found": .string(row.candidate.unit ?? ""), "expected": .string(row.candidate.expectedUnit)]))
                                .font(.footnote).foregroundStyle(.orange)
                        }
                        OptionalNumberRow(label: t("labs_value"), value: $row.value, suffix: row.candidate.expectedUnit)
                        OptionalNumberRow(label: t("labs_your_low"), value: $row.low, suffix: row.candidate.expectedUnit)
                        OptionalNumberRow(label: t("labs_your_high"), value: $row.high, suffix: row.candidate.expectedUnit)
                        Toggle(t("ios_lab_scan_verified"), isOn: $row.checked)
                            .disabled(!row.valid || duplicate(row) || page?.text != page?.parsedText)
                    }
                    .onChange(of: row.value) { row.checked = false }
                    .onChange(of: row.low) { row.checked = false }
                    .onChange(of: row.high) { row.checked = false }
                    }
                }
                Section {
                    Text(t("ios_lab_all_pages")).font(.footnote).foregroundStyle(.secondary)
                    Button(t("import_save_results", ["results": .string(t("count_results", ["n": .number(Double(ready.count))]))]), action: save)
                        .disabled(ready.isEmpty || busy)
                }
            }
        }
    }

    private func takePhoto() {
        Task {
            let allowed = await AVCaptureDevice.requestAccess(for: .video)
            if allowed { camera = true } else { cameraDenied = true }
        }
    }
    private func read(_ image: UIImage) async {
        busy = true; error = nil
        defer { busy = false }
        await appendPage(image)
    }
    private func readPDF(_ data: Data) async {
        busy = true; error = nil
        defer { busy = false }
        guard let document = PDFDocument(data: data), !document.isLocked, document.pageCount > 0 else {
            error = t("ios_lab_pdf_unreadable"); return
        }
        let limit = 20
        guard document.pageCount <= limit else {
            error = t("ios_lab_pdf_too_many", ["limit": .number(Double(limit))]); return
        }
        var failedPages = false
        for index in 0..<document.pageCount {
            guard let pdfPage = document.page(at: index) else { failedPages = true; continue }
            let bounds = pdfPage.bounds(for: .mediaBox)
            guard bounds.width > 0, bounds.height > 0 else { failedPages = true; continue }
            let scale = min(2.5, 2400 / bounds.width, 3200 / bounds.height)
            let image = pdfPage.thumbnail(of: CGSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            let textLines = pdfPage.string?.components(separatedBy: .newlines) ?? []
            await appendPage(image, textLines: textLines)
        }
        if failedPages { error = t("ios_lab_pdf_pages_failed") }
    }
    private func appendPage(_ image: UIImage, textLines: [String] = []) async {
        let scannedLines = await recognizeText(image, groupRows: true)
        // Digital PDFs can carry exact text. OCR also handles scanned PDFs and
        // often recovers table rows whose text layer is split into columns.
        // Keep both only when they find different markers, avoiding duplicate
        // raw text when either source already found all the results.
        let textCount = parseLabReport(textLines).candidates.count
        let scanCount = parseLabReport(scannedLines).candidates.count
        let combined = textLines + scannedLines
        let lines: [String]
        if !textLines.isEmpty && parseLabReport(combined).candidates.count > max(textCount, scanCount) {
            lines = combined
        } else {
            lines = textCount >= scanCount && !textLines.isEmpty ? textLines : scannedLines
        }
        let p = ScannedLabPage(image: image, text: lines.joined(separator: "\n"))
        let first = pages.isEmpty
        pages.append(p); pageID = p.id
        let report = parseLabReport(lines)
        if first {
            at = report.collectedAt.map { Date(millis: $0) } ?? Date()
            missingDate = report.collectedAt == nil; lab = report.lab ?? ""
        }
        parsePage(p.id)
    }
    private func parsePage(_ id: UUID) {
        guard let i = pages.firstIndex(where: { $0.id == id }) else { return }
        pages[i].parsedText = pages[i].text
        let report = parseLabReport(pages[i].text.components(separatedBy: .newlines))
        pages[i].collectedAt = report.collectedAt
        error = nil
        rows.removeAll { $0.pageID == id }
        rows += report.candidates.map { ScannedLabRow(pageID: id, candidate: $0, value: $0.value, low: $0.refLow, high: $0.refHigh) }
        if report.candidates.isEmpty { error = t("ios_lab_scan_empty") }
    }
    private func save() {
        let selected = ready
        guard !selected.isEmpty else { return }
        let name = lab.trimmingCharacters(in: .whitespacesAndNewlines)
        store.mutate { data in
            for row in selected {
                guard let value = row.value else { continue }
                data.addImportedLab(LabResult(id: "", profileId: "", at: at.millis, markerId: row.candidate.markerId, value: value,
                                              refLow: row.low, refHigh: row.high, lab: name.isEmpty ? nil : name))
            }
        }
        dismiss()
    }
}

private struct ScannedLabPage: Identifiable {
    let id = UUID()
    var image: UIImage
    var text: String
    var parsedText = ""
    var collectedAt: Millis?
}
private struct ScannedLabRow: Identifiable {
    let id = UUID()
    var pageID: UUID
    var candidate: LabCandidate
    var value: Double?
    var low: Double?
    var high: Double?
    var checked = false
    var valid: Bool {
        guard let value, value.isFinite, low?.isFinite != false, high?.isFinite != false else { return false }
        if let low, let high { return low < high }
        return true
    }
}
private struct LabPhotoZoom: View {
    @Environment(\.dismiss) private var dismiss
    var image: UIImage
    @State private var zoom = 1.0
    var body: some View {
        GeometryReader { geometry in
            VStack {
                ScrollView([.horizontal, .vertical]) {
                    Image(uiImage: image).resizable().scaledToFit()
                        .frame(width: geometry.size.width * zoom)
                }
                Slider(value: $zoom, in: 1...5) { Text(t("ios_lab_zoom")) }.padding()
            }
        }
        .navigationTitle(t("ios_lab_scan_photo"))
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("done")) { dismiss() } } }
    }
}
#endif
