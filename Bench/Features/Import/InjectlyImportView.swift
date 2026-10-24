import SwiftUI
import UniformTypeIdentifiers
import BenchCore
import BenchStore

/// Moving across from Injectly in one go: its medications become compounds,
/// blends and protocols, and its logs and weight become history. Everything is
/// shown first, with anything uncertain left for you to settle.
struct InjectlyImportView: View {
    @Environment(AppStore.self) private var store
    @State private var picking = false
    @State private var items: [InjectlyItem] = []
    @State private var include: [Bool] = []
    /// Per item: also put the vial being drawn from in Stock, mixed.
    @State private var addVial: [Bool] = []
    @State private var history: [CanonicalRecord] = []
    @State private var historyProblems: [RowProblem] = []
    @State private var fileNames: [String] = []
    @State private var error: String?
    @State private var done: String?
    @State private var withDoses = true
    @State private var withWeights = true

    var body: some View {
        let data = store.data
        let preview = previewResults(data)
        let plan = historyPlan(data, preview)
        GroupedList {
            if let done { Section { CalloutText(done).font(.footnote).callout(.sky) } }
            if let error { Section { CalloutText(error).font(.footnote).callout(.rose) } }
            if items.isEmpty && history.isEmpty {
                Section {
                    Text(t("ios_inj_how")).font(.footnote).foregroundStyle(.secondary)
                    Button { picking = true } label: { Label(t("ios_inj_choose"), systemImage: "doc.on.doc") }
                }
            } else {
                Section { Text(t("ios_inj_files", ["files": .string(fileNames.joined(separator: ", "))])).font(.caption).foregroundStyle(.secondary) }
                if !items.isEmpty { setupSection(data) }
                historySection(plan)
                Section {
                    Button { apply(data, preview, plan) } label: { Label(t("ios_inj_import"), systemImage: "square.and.arrow.down") }
                        .disabled(!include.contains(true) && !addVial.contains(true) && (planIsEmpty(plan) || (!withDoses && !withWeights)))
                    Button(t("cancel"), action: reset)
                }
            }
        }
        .navigationTitle(t("ios_src_injectly"))
        .inlineTitle()
        // Any file: exports are often tagged loosely, and a greyed-out file cannot be picked.
        // Each file is told apart by its columns instead.
        .fileImporter(isPresented: $picking, allowedContentTypes: [.item], allowsMultipleSelection: true) { r in
            if case .success(let urls) = r { load(urls) }
        }
        #if DEBUG
        .onAppear {
            // `-injectlyFiles a.csv,b.csv` reads them straight away, for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if items.isEmpty, history.isEmpty, let i = args.firstIndex(of: "-injectlyFiles"), i + 1 < args.count {
                load(args[i + 1].split(separator: ",").map { URL(fileURLWithPath: String($0)) })
            }
        }
        #endif
    }

    // MARK: Reading

    private func reset() { items = []; include = []; addVial = []; history = []; historyProblems = []; fileNames = []; error = nil }

    private func load(_ urls: [URL]) {
        reset(); done = nil
        var meds: [InjectlyMedication] = []
        for url in urls {
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: url) else { continue }
            let table = toTable(parseDelimited(String(decoding: data, as: UTF8.self)))
            switch injectlyFileKind(table.headers) {
            case .medications?: meds += parseInjectlyMedications(table)
            case .logs?, .weight?:
                let read = injectlyProfile.read(table.records, table.headers)
                history += read.records; historyProblems += read.problems
            case .profile?: break
            case nil: continue
            }
            fileNames.append(url.lastPathComponent)
        }
        guard !fileNames.isEmpty else { error = t("ios_inj_no_files"); return }
        let data = store.data
        items = planInjectlySetup(meds, peptides: data.allPeptides, activeProtocols: data.mine.protocols.filter(\.active), logs: history)
        include = items.map { !$0.alreadyPlanned }
        let mixed = Set(data.mine.vials.filter { $0.state == .reconstituted }.map(\.peptideId))
        addVial = items.map { item in
            guard injectlyInUseVial(item.medication) != nil else { return false }
            if case .existing(let id) = item.compound, mixed.contains(id) { return false }
            return true
        }
    }

    /// What each included item would save, given the current choices.
    private func previewResults(_ data: AppData) -> [(index: Int, peptide: Peptide?, protocol_: DoseProtocol)] {
        items.indices.filter { include[$0] }.map { i in
            let r = injectlyResult(items[i], peptides: data.allPeptides, logs: history)
            return (i, r.newPeptide, r.protocol_)
        }
    }

    private func historyPlan(_ data: AppData, _ preview: [(index: Int, peptide: Peptide?, protocol_: DoseProtocol)]) -> ImportPlan {
        let peptides = data.allPeptides + preview.compactMap(\.peptide).filter { p in !data.allPeptides.contains { $0.id == p.id } }
        // A medication matched to a library compound by choice: its doses follow the choice, not its Injectly name.
        var rename: [String: String] = [:]
        for i in items.indices {
            if case .newCompound(_, let chosen?) = items[i].compound, let name = data.peptide(chosen)?.name { rename[items[i].medication.name] = name }
        }
        let records = history.map { r -> CanonicalRecord in
            if case .dose(let at, let label, let dose, let site, let notes, let row) = r, let to = rename[label] {
                return .dose(at: at, label: to, doseMcg: dose, site: site, notes: notes, sourceRow: row)
            }
            return r
        }
        let mine = data.mine
        return buildImportPlan(records: records, problems: historyProblems, peptides: peptides,
                               existingLogs: mine.logs.map { ($0.at, $0.peptideId) }, existingMeasurements: mine.measurements.map { ($0.at, $0.weightKg) },
                               blendDoseIsFirstPart: true)
    }

    /// The compound an item already is, when it is not being added.
    private func existingId(_ item: InjectlyItem) -> String? {
        if case .existing(let id) = item.compound { return id }
        return nil
    }

    // MARK: Sections

    @ViewBuilder private func setupSection(_ data: AppData) -> some View {
        Section {
            ForEach(items.indices, id: \.self) { i in
                let item = items[i]
                VStack(alignment: .leading, spacing: 8) {
                    Toggle(isOn: $include[i]) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.medication.name).font(.subheadline.weight(.semibold))
                            Text("\(doseLabelPerDay(item.doseMcg / Double(max(1, item.schedule.kind == .asNeeded ? 1 : scheduleTimes(item.schedule).count)), item.schedule.kind == .asNeeded ? 1 : scheduleTimes(item.schedule).count, injectlyPreviewPeptide(item, data))) · \(describeSchedule(item.schedule))").font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if include[i] { compoundRows(i, data) }
                    // Also offered for what is already planned: re-importing just to add the vials.
                    if include[i] || existingId(item) != nil, let v = injectlyInUseVial(item.medication) {
                        Toggle(isOn: $addVial[i]) {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(t("ios_inj_add_vial", ["mg": .string(trim(v.strengthMg, 3)), "ml": .string(trim(v.waterMl, 2))])).font(.subheadline)
                                Text(t("ios_inj_add_vial_hint")).font(.caption).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if item.alreadyPlanned { Text(t("ios_inj_already")).font(.caption).foregroundStyle(.secondary) }
                    ForEach(item.notes, id: \.self) { Text($0).font(.caption).foregroundStyle(Tone.tangerine.color) }
                }
                .padding(.vertical, 2)
            }
            FooterRow { Text(t("ios_inj_setup_hint")) }
        } header: { Text(t("ios_inj_setup")) } footer: { FooterWrap { Text(t("ios_inj_setup_hint")) }}
    }

    @ViewBuilder private func compoundRows(_ i: Int, _ data: AppData) -> some View {
        switch items[i].compound {
        case .existing(let id):
            Label("\(t("ios_inj_in_library")): \(data.peptide(id)?.name ?? id)", systemImage: "checkmark.circle").font(.caption).foregroundStyle(Tone.leaf.color)
        case .newBlend(let parts):
            Label(t("ios_inj_new_blend"), systemImage: "square.stack.3d.up").font(.caption.weight(.semibold)).foregroundStyle(Color.accentColor)
            ForEach(parts.indices, id: \.self) { k in
                let part = parts[k]
                Picker(selection: Binding(get: { part.chosen }, set: { setPart(i, k, $0) })) {
                    Text(t("ios_inj_name_only")).tag(String?.none)
                    ForEach(choices(part.candidates, data), id: \.id) { Text($0.name).tag(Optional($0.id)) }
                } label: {
                    Text("\(part.name)\(part.mgPerVial.map { " · \(trim($0, 3)) mg" } ?? "")").font(.subheadline)
                }
                if part.chosen == nil {
                    Text(part.candidates.count > 1 ? t("ios_inj_which") : t("ios_inj_name_only_hint")).font(.caption).foregroundStyle(Tone.tangerine.color)
                }
            }
        case .newCompound(let candidates, let chosen):
            Picker(t("ios_inj_which"), selection: Binding(get: { chosen }, set: { setCompound(i, candidates, $0) })) {
                Text(t("ios_inj_new_compound")).tag(String?.none)
                ForEach(choices(candidates, data), id: \.id) { Text($0.name).tag(Optional($0.id)) }
            }
            .font(.subheadline)
        }
    }

    /// The likely matches first, then the rest of the library.
    private func choices(_ candidates: [String], _ data: AppData) -> [Peptide] {
        let all = data.allPeptides.filter { !isBlend($0) }
        return candidates.compactMap { id in all.first { $0.id == id } } + all.filter { !candidates.contains($0.id) }
    }

    private func setPart(_ i: Int, _ k: Int, _ id: String?) {
        guard case .newBlend(var parts) = items[i].compound else { return }
        parts[k].chosen = id
        items[i].compound = .newBlend(parts)
    }

    private func setCompound(_ i: Int, _ candidates: [String], _ id: String?) {
        items[i].compound = .newCompound(candidates: candidates, chosen: id)
    }

    @ViewBuilder private func historySection(_ plan: ImportPlan) -> some View {
        Section {
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
            ForEach(plan.unresolved, id: \.label) { u in
                RichText(t("import_unresolved_row", ["label": .string(u.label), "rows": .string(t("count_rows", ["n": .number(Double(u.rows.count))])),
                                                      "list": .string(u.rows.prefix(6).map(String.init).joined(separator: ", "))]))
                    .font(.caption).foregroundStyle(Tone.tangerine.color)
            }
        } header: { Text(t("ios_inj_history")) }
    }

    // MARK: Saving

    private func apply(_ data: AppData, _ preview: [(index: Int, peptide: Peptide?, protocol_: DoseProtocol)], _ plan: ImportPlan) {
        let logs = withDoses ? plan.doses.map {
            DoseLog(id: "", profileId: "", peptideId: $0.peptideId, at: $0.at, doseMcg: $0.doseMcg, route: .subcutaneous, site: $0.site, notes: $0.notes)
        } : []
        let weights = withWeights ? plan.weights.map { BodyMeasurement(id: "", profileId: "", at: $0.at, weightKg: $0.weightKg, source: .manual) } : []
        // Each vial's compound: the one being added, or, for what is not, the one already there.
        let vialsIn: [(peptideId: String, strengthMg: Double, waterMl: Double)] = items.indices.compactMap { i in
            guard addVial[i], let v = injectlyInUseVial(items[i].medication),
                  let id = preview.first(where: { $0.index == i })?.protocol_.peptideId ?? existingId(items[i]) else { return nil }
            return (id, v.strengthMg, v.waterMl)
        }
        store.mutate { d in
            for r in preview {
                if let p = r.peptide, !d.allPeptides.contains(where: { $0.id == p.id }) { d.addCustomPeptide(p) }
                _ = d.addProtocol(r.protocol_)
            }
            // The vials being drawn from, mixed today and counted as full.
            for v in vialsIn {
                let id = d.addVial(Vial(id: "", profileId: "", peptideId: v.peptideId, strengthMg: v.strengthMg, state: .sealed, acquiredAt: nowMillis()))
                d.reconstituteVial(id, diluentMl: v.waterMl, diluent: .bacteriostatic)
            }
            d.importHistory(logs: logs, measurements: weights)
        }
        done = t("ios_inj_done", ["protocols": .string(t("count_protocols", ["n": .number(Double(preview.count))])),
                                  "doses": .string(t("count_doses", ["n": .number(Double(logs.count))])),
                                  "weights": .string(t("count_weights", ["n": .number(Double(weights.count))]))])
            + (vialsIn.isEmpty ? "" : " " + t("ios_inj_done_vials", ["vials": .string(t("count_vials", ["n": .number(Double(vialsIn.count))]))]))
        reset()
    }
}

/// The compound an item stands for in the preview, including a blend not yet saved.
@MainActor func injectlyPreviewPeptide(_ item: InjectlyItem, _ data: AppData) -> Peptide? {
    switch item.compound {
    case .existing(let id): return data.peptide(id)
    case .newCompound(_, let chosen): return chosen.flatMap { data.peptide($0) }
    case .newBlend: return injectlyResult(item, peptides: data.allPeptides, logs: []).newPeptide
    }
}
