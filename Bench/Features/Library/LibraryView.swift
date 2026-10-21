import SwiftUI
import BenchCore
import BenchStore

private let EVIDENCE_RANK: [EvidenceLevel] = [.anecdotal, .preclinical, .preliminary, .clinical, .approved]

/// Every compound in the library, plus your own, grouped by what they are for.
struct LibraryView: View {
    @Environment(AppStore.self) private var store
    @State private var query = ""

    var body: some View {
        let peptides = store.data.allPeptides
        let q = query.trimmingCharacters(in: .whitespaces).lowercased()
        let filtered = q.isEmpty ? peptides : peptides.filter {
            $0.name.lowercased().contains(q) || $0.aka.contains { $0.lowercased().contains(q) }
                || $0.summary.lowercased().contains(q) || $0.category.label.lowercased().contains(q)
        }
        let byCategory = filtered.reduce(into: [(PeptideCategory, [Peptide])]()) { acc, p in
            if let i = acc.firstIndex(where: { $0.0 == p.category }) { acc[i].1.append(p) } else { acc.append((p.category, [p])) }
        }
        List {
            Section { Text(t("library_subtitle", ["n": .number(Double(peptides.count))])).font(.subheadline).foregroundStyle(.secondary) }
            if filtered.isEmpty {
                ContentUnavailableView.search(text: query)
            }
            CustomCompoundsSection()
            ForEach(byCategory, id: \.0.rawValue) { category, items in
                Section(category.label) {
                    ForEach(items) { p in
                        NavigationLink(value: p.id) { LibraryRow(peptide: p) }
                    }
                }
            }
        }
        .searchable(text: $query, prompt: t("library_search_placeholder"))
        .navigationTitle(t("library_title"))
        .peptideDestination()
    }
}

private struct LibraryRow: View {
    var peptide: Peptide
    var body: some View {
        let p = peptide
        let best = p.doseRanges.map(\.evidence).max { (EVIDENCE_RANK.firstIndex(of: $0) ?? -1) < (EVIDENCE_RANK.firstIndex(of: $1) ?? -1) }
        VStack(alignment: .leading, spacing: 4) {
            FlowLayout(spacing: 6) {
                Text(p.name).font(.body)
                if let best {
                    Pill(text: best.label, tone: best == .approved ? .leaf : best == .clinical ? .sky : best == .anecdotal ? .rose : .neutral)
                }
                if p.halfLifeHours == nil && !isBlend(p) { Pill(text: t("library_no_pk_data"), tone: .rose) }
            }
            Text(p.summary).font(.footnote).foregroundStyle(.secondary).lineLimit(3)
            Text("\(t("library_half_life")) \(formatHalfLife(p.halfLifeHours))" + (p.aka.isEmpty ? "" : " · \(t("library_also_known")) \(p.aka.prefix(2).joined(separator: ", "))"))
                .font(.caption).foregroundStyle(.tertiary)
        }
        .padding(.vertical, 2)
    }
}

/// Compounds you added, with how much of your history points at each.
private struct CustomCompoundsSection: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false
    @State private var editing: Peptide?
    @State private var confirming: Peptide?

    var body: some View {
        let data = store.data
        Section {
            Text(t("library_your_own_desc")).font(.footnote).foregroundStyle(.secondary)
            ForEach(data.customPeptides) { p in
                let protocols = data.protocols.filter { $0.peptideId == p.id }.count
                let logs = data.logs.filter { $0.peptideId == p.id }.count
                VStack(alignment: .leading, spacing: 4) {
                    FlowLayout(spacing: 6) {
                        Text(p.name).font(.subheadline.bold())
                        Pill(text: t("library_your_badge"), tone: .grape)
                        Pill(text: p.category.label)
                        // A blend's curves come from its parts, so it has no half-life to miss.
                        if p.halfLifeHours == nil && !isBlend(p) { Pill(text: t("library_no_half_life"), tone: .tangerine) }
                    }
                    Text(t("library_usage", ["protocols": .string(String(protocols)), "logs": .string(String(logs))])).font(.caption).foregroundStyle(.secondary)
                }
                .swipeActions {
                    Button(t("library_delete_name", ["name": .string(p.name)]), role: .destructive) { confirming = p }
                    Button(t("library_edit_name", ["name": .string(p.name)])) { editing = p }.tint(.accentColor)
                }
                .contextMenu {
                    Button { editing = p } label: { Label(t("library_edit_name", ["name": .string(p.name)]), systemImage: "pencil") }
                    Button(role: .destructive) { confirming = p } label: { Label(t("library_delete_name", ["name": .string(p.name)]), systemImage: "trash") }
                }
            }
            if data.customPeptides.isEmpty {
                Label(t("library_none_yet"), systemImage: "flask").font(.footnote).foregroundStyle(.secondary)
            }
            // Sheets and the dialog hang off a row rather than the Section: a Section
            // inside a List does not reliably present them.
            Button { adding = true } label: { Label(t("library_add_your_own"), systemImage: "plus") }
        #if DEBUG
                .onAppear {
                    // `-editCompound <id>` opens one of your compounds for editing, for screenshots.
                    let args = ProcessInfo.processInfo.arguments
                    if editing == nil, let i = args.firstIndex(of: "-editCompound"), i + 1 < args.count {
                        let p = data.customPeptides.first { $0.id == args[i + 1] }
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { editing = p }
                    }
                }
                #endif
                .sheet(isPresented: $adding) { NavigationStack { CustomCompoundForm() } }
                .sheet(item: $editing) { p in NavigationStack { CustomCompoundForm(editing: p) } }
                .confirmationDialog(confirming.map { t("library_delete_compound", ["name": .string($0.name)]) } ?? "",
                                    isPresented: Binding(get: { confirming != nil }, set: { if !$0 { confirming = nil } }), titleVisibility: .visible, presenting: confirming) { p in
                    Button(t("library_delete_compound", ["name": .string(p.name)]), role: .destructive) { store.mutate { $0.removeCustomPeptide(p.id) } }
                    Button(t("library_keep_it"), role: .cancel) {}
                } message: { p in
                    let protocols = data.protocols.filter { $0.peptideId == p.id }.count
                    let logs = data.logs.filter { $0.peptideId == p.id }.count
                    Text(logs > 0 || protocols > 0
                         ? t("library_delete_in_use", ["logs": .string(String(logs)), "protocols": .string(String(protocols)), "name": .string(p.name)])
                         : t("library_delete_safe", ["name": .string(p.name)]))
                }
        } header: {
            Text(t("library_your_own"))
        } footer: {
            if !data.customPeptides.isEmpty { Text(t("library_stored_on_device")) }
        }
    }
}

extension View {
    /// Peptide ids pushed with `NavigationLink(value:)` open the compound's page.
    func peptideDestination() -> some View {
        navigationDestination(for: String.self) { PeptideDetailView(peptideId: $0) }
    }
}
