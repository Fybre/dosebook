import SwiftUI
import PhotosUI
import Vision
import BenchCore
import BenchStore

/// What a scan found, once checked, for the new-vial form to carry on with.
struct ScannedVial {
    var peptideId: String
    var strengthMg: Double
    var lot: String?
    var expiresAt: Millis?
}

/// Photograph a vial's label to start a protocol for it, and optionally put the
/// vial in Stock; or, from Stock, to fill in a new vial. The text is read on the
/// phone and the photo is not kept.
struct ScanVialView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    /// Called with the compound once the person continues to its protocol.
    var onContinue: (String) -> Void = { _ in }
    /// From Stock: hands the details back to the new-vial form instead.
    var onScanned: ((ScannedVial) -> Void)?

    @State private var photo: PhotosPickerItem?
    @State private var camera = false
    @State private var choosingFile = false
    @State private var reading = false
    @State private var lines: [String]?
    @State private var label: VialLabel?
    @State private var peptideId = ""
    @State private var strengthMg: Double = 0
    @State private var lot = ""
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var addToStock = true

    var body: some View {
        let data = store.data
        Form {
            if lines == nil {
                Section {
                    Text(t("ios_scan_intro")).font(.footnote).foregroundStyle(.secondary)
                    #if os(iOS)
                    Button { camera = true } label: { Label(t("ios_scan_camera"), systemImage: "camera") }
                        .disabled(!UIImagePickerController.isSourceTypeAvailable(.camera))
                    #endif
                    PhotosPicker(selection: $photo, matching: .images) { Label(t("ios_scan_library"), systemImage: "photo") }
                    Button { choosingFile = true } label: { Label(t("ios_scan_file"), systemImage: "doc") }
                    if reading { HStack { ProgressView(); Text(t("ios_scan_reading")).foregroundStyle(.secondary) } }
                }
            } else if lines!.isEmpty {
                Section {
                    CalloutText(t("ios_scan_nothing")).font(.footnote).callout(.tangerine)
                    Button(t("ios_scan_again")) { lines = nil }
                }
            } else {
                Section {
                    Picker(t("plan_peptide"), selection: $peptideId) {
                        Text(t("ios_scan_choose")).tag("")
                        ForEach(orderedChoices(data), id: \.id) { Text($0.name).tag($0.id) }
                    }
                    AmountRow(label: t("stock_strength"), value: $strengthMg, base: .mg, range: 0...100_000)
                    LabeledContent(t("ios_scan_lot")) {
                        TextField(t("ios_scan_lot"), text: $lot).multilineTextAlignment(.trailing).capitalisedCharacters().fieldTitleHidden()
                    }
                    Toggle(t("ios_scan_has_expiry"), isOn: $hasExpiry)
                    if hasExpiry { DatePicker(t("ios_scan_expiry"), selection: $expiry, displayedComponents: .date) }
                    FooterRow { Text(t("ios_scan_check")) }
                } header: { Text(t("ios_scan_found")) } footer: { FooterWrap { Text(t("ios_scan_check")) }}
                if onScanned == nil {
                    Section {
                        Toggle(t("ios_scan_add_stock"), isOn: $addToStock)
                        FooterRow { Text(t("ios_scan_add_stock_hint")) }
                    } footer: { FooterWrap { Text(t("ios_scan_add_stock_hint")) }}
                }
                Section {
                    DisclosureGroup(t("ios_scan_raw")) {
                        Text(lines!.joined(separator: "\n")).font(.caption.monospaced()).foregroundStyle(.secondary).textSelection(.enabled)
                    }
                    Button(t("ios_scan_again")) { lines = nil; label = nil; photo = nil }
                }
            }
        }
        .navigationTitle(t("ios_scan_title"))
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(onScanned == nil ? t("ios_scan_continue") : t("ios_scan_use"), action: proceed).disabled(peptideId.isEmpty || lines?.isEmpty != false)
            }
        }
        .onChange(of: photo) { _, item in
            guard let item else { return }
            Task { if let data = try? await item.loadTransferable(type: Data.self), let image = PlatformImage(data: data) { await read(image) } }
        }
        .fileImporter(isPresented: $choosingFile, allowedContentTypes: [.image]) { r in
            guard case .success(let url) = r else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            if let data = try? Data(contentsOf: url), let image = PlatformImage(data: data) { Task { await read(image) } }
        }
        #if os(iOS)
        .sheet(isPresented: $camera) {
            CameraPicker { image in Task { await read(image) } }.ignoresSafeArea()
        }
        #endif
        #if DEBUG
        .task {
            // `-scanImage <path>` reads a picture straight away, for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if lines == nil, let i = args.firstIndex(of: "-scanImage"), i + 1 < args.count, let image = PlatformImage(contentsOfFile: args[i + 1]) { await read(image) }
        }
        #endif
    }

    /// The likely matches first, then everything else.
    private func orderedChoices(_ data: AppData) -> [Peptide] {
        let all = data.allPeptides
        let first = (label?.candidates ?? []).compactMap { id in all.first { $0.id == id } }
        return first + all.filter { p in !first.contains { $0.id == p.id } }
    }

    private func read(_ image: PlatformImage) async {
        reading = true
        defer { reading = false }
        let found = await recognizeText(image)
        let parsed = parseVialLabel(found, peptides: store.data.allPeptides)
        label = parsed
        peptideId = parsed.peptideId ?? (parsed.candidates.count == 1 ? parsed.candidates[0] : "")
        strengthMg = parsed.strengthMg ?? store.data.peptide(peptideId)?.vialSizesMg.first ?? 0
        lot = parsed.lot ?? ""
        hasExpiry = parsed.expiresAt != nil
        if let e = parsed.expiresAt { expiry = Date(millis: e) }
        lines = found
    }

    private func proceed() {
        let trimmedLot = lot.trimmingCharacters(in: .whitespaces)
        if let onScanned {
            onScanned(ScannedVial(peptideId: peptideId, strengthMg: strengthMg, lot: trimmedLot.isEmpty ? nil : trimmedLot,
                                  expiresAt: hasExpiry ? endOfLocalDay(expiry.millis) : nil))
            dismiss()
            return
        }
        if addToStock, strengthMg > 0 {
            store.mutate {
                $0.addVial(Vial(id: "", profileId: "", peptideId: peptideId, strengthMg: strengthMg, state: .sealed,
                                lot: trimmedLot.isEmpty ? nil : trimmedLot, acquiredAt: nowMillis(),
                                expiresAt: hasExpiry ? endOfLocalDay(expiry.millis) : nil))
            }
        }
        onContinue(peptideId)
    }
}

/// Text in a photo, line by line, read on the device.
func recognizeText(_ image: PlatformImage) async -> [String] {
    guard let cg = image.pixels else { return [] }
    #if canImport(UIKit)
    let orientation = CGImagePropertyOrientation(image.imageOrientation)
    #else
    let orientation = CGImagePropertyOrientation.up
    #endif
    return await withCheckedContinuation { cont in
        let request = VNRecognizeTextRequest { req, _ in
            let lines = (req.results as? [VNRecognizedTextObservation] ?? []).compactMap { $0.topCandidates(1).first?.string }
            cont.resume(returning: lines)
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false
        DispatchQueue.global(qos: .userInitiated).async {
            do { try VNImageRequestHandler(cgImage: cg, orientation: orientation).perform([request]) } catch { cont.resume(returning: []) }
        }
    }
}

#if os(iOS)
private extension CGImagePropertyOrientation {
    init(_ o: UIImage.Orientation) {
        switch o {
        case .up: self = .up
        case .down: self = .down
        case .left: self = .left
        case .right: self = .right
        case .upMirrored: self = .upMirrored
        case .downMirrored: self = .downMirrored
        case .leftMirrored: self = .leftMirrored
        case .rightMirrored: self = .rightMirrored
        @unknown default: self = .up
        }
    }
}

/// The system camera, for one still.
struct CameraPicker: UIViewControllerRepresentable {
    var onImage: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }
    func updateUIViewController(_ controller: UIImagePickerController, context: Context) {}
    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPicker
        init(_ parent: CameraPicker) { self.parent = parent }
        func imagePickerController(_ picker: UIImagePickerController, didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage { parent.onImage(image) }
            parent.dismiss()
        }
        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) { parent.dismiss() }
    }
}
#endif
