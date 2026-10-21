import SwiftUI
import BenchCore
import BenchStore

/// Add (or edit) a compound the library does not have. Its dose range is
/// always tagged anecdotal and it carries no citations: nothing here is checked.
struct CustomCompoundForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var editing: Peptide? = nil
    var onCreated: ((Peptide) -> Void)? = nil
    @State private var draft = CustomDraft()
    @State private var loaded = false

    private var problems: [DraftProblem] { validateDraft(draft, existing: store.data.allPeptides, editingId: editing?.id) }
    private func error(_ f: DraftField) -> String? { problems.first { $0.field == f }?.message }

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    TextField(t("ccf_name_placeholder"), text: $draft.name)
                    if let e = error(.name), !draft.name.isEmpty { Text(e).font(.caption).foregroundStyle(Tone.rose.color) }
                }
                Picker(t("ccf_category"), selection: $draft.category) {
                    ForEach(PeptideCategory.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                VStack(alignment: .leading, spacing: 4) {
                    TextField(t("ccf_aka_placeholder"), text: Binding(get: { draft.aka ?? "" }, set: { draft.aka = $0 }))
                    Text(t("ccf_aka_hint")).font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text(t("ccf_compound")) } footer: { Text(t("ccf_category_hint")) }

            Section(t("ccf_how_you_take")) {
                ForEach(Route.allCases, id: \.self) { r in
                    Toggle(r.label, isOn: Binding(get: { draft.routes.contains(r) },
                                                  set: { draft.routes = $0 ? draft.routes + [r] : draft.routes.filter { $0 != r } }))
                }
                Picker(t("ccf_comes_as"), selection: $draft.preparation) {
                    Text(t("ccf_powder")).tag(Preparation.powder)
                    Text(t("ccf_solution")).tag(Preparation.solution)
                    Text(t("ccf_tablet")).tag(Preparation.tablet)
                }
                Text(t(draft.preparation == .powder ? "ccf_powder_hint" : draft.preparation == .tablet ? "ccf_tablet_hint" : "ccf_solution_hint"))
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section {
                OptionalNumberRow(label: t("ccf_half_life"), value: $draft.halfLifeHours, suffix: t("hours"), hint: t("ccf_half_life_hint"), error: error(.halfLifeHours))
                OptionalNumberRow(label: t("ccf_dose_low"), value: $draft.doseLowMcg, suffix: "mcg", error: error(.doseLowMcg))
                OptionalNumberRow(label: t("ccf_dose_high"), value: $draft.doseHighMcg, suffix: "mcg", error: error(.doseHighMcg))
                OptionalNumberRow(label: t("ccf_per_week"), value: $draft.perWeek, hint: t("ccf_per_week_hint"), error: error(.perWeek))
                OptionalNumberRow(label: t("ccf_vial_size"), value: $draft.vialSizeMg, suffix: "mg", hint: t("labs_optional"), error: error(.vialSizeMg))
                OptionalNumberRow(label: t("ccf_iu_per_mg"), value: $draft.iuPerMg, hint: t("ccf_iu_hint"), error: error(.iuPerMg))
            }

            Section(t("ccf_notes")) {
                TextField(t("ccf_notes_placeholder"), text: Binding(get: { draft.notes ?? "" }, set: { draft.notes = $0 }), axis: .vertical)
            }
            Section { Text(t("ccf_not_saved")).font(.caption).foregroundStyle(.secondary) }
        }
        .navigationTitle(editing == nil ? t("add_compound_inline") : editing!.name)
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing == nil ? t("ccf_add", ["name": .string(draft.name.isEmpty ? t("ccf_compound") : draft.name)]) : t("ccf_save_changes")) { save() }
                    .disabled(!problems.isEmpty)
            }
        }
        .onAppear {
            if !loaded, let editing { draft = peptideToDraft(editing) }
            loaded = true
        }
    }

    private func save() {
        if let editing {
            var next = draftToPeptide(draft)
            // Fields the form never offered are left as they were.
            next.sideEffects = editing.sideEffects
            next.contraindications = editing.contraindications
            next.extra = editing.extra
            store.mutate { $0.updateCustomPeptide(editing.id, next) }
            onCreated?(next)
        } else {
            let p = draftToPeptide(draft)
            store.mutate { $0.addCustomPeptide(p) }
            onCreated?(p)
        }
        dismiss()
    }
}
