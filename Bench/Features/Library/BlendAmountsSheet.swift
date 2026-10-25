import SwiftUI
import BenchCore
import BenchStore

/// What is in your vial of a library blend whose amounts vary by seller, so its
/// doses split per part like any other blend.
struct BlendAmountsSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var peptideId: String
    @State private var mg: [Double] = []
    @State private var loaded = false

    var body: some View {
        let library = Library.byId[peptideId]
        let parts = library?.components ?? []
        let saved = store.data.blendAmounts[peptideId] != nil
        Form {
            Section {
                ForEach(parts.indices, id: \.self) { i in
                    if i < mg.count {
                        AmountRow(label: parts[i].name, value: $mg[i], base: .mg, range: 0...100_000)
                    }
                }
                FooterRow { Text(t("ios_blend_amounts_hint", ["name": .string(library?.name ?? peptideId)])) }
            } header: { Text(t("ios_blend_amounts_title")) } footer: { FooterWrap { Text(t("ios_blend_amounts_hint", ["name": .string(library?.name ?? peptideId)])) }}
            if saved {
                Section {
                    Button(t("ios_blend_amounts_clear"), role: .destructive) {
                        store.mutate { $0.setBlendAmounts(peptideId, mg: nil) }
                        dismiss()
                    }
                }
            }
        }
        .navigationTitle(library?.name ?? peptideId)
        .inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("save")) {
                    store.mutate { $0.setBlendAmounts(peptideId, mg: mg) }
                    dismiss()
                }
                .disabled(mg.count != parts.count || mg.contains { $0 <= 0 })
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let known = store.data.blendAmounts[peptideId]
            mg = parts.indices.map { known?[safe: $0] ?? parts[$0].mgPerVial ?? 0 }
        }
    }
}

/// Asks for a blend's amounts while they are missing; once given, says what they
/// are with a way to change them. Silent for anything else.
struct BlendAmountsPrompt: View {
    @Environment(AppStore.self) private var store
    var peptideId: String
    @State private var editing = false

    var body: some View {
        let data = store.data
        let peptide = data.peptide(peptideId)
        Group {
            if blendNeedsAmounts(peptide) {
                VStack(alignment: .leading, spacing: 8) {
                    CalloutText(t("ios_blend_amounts_ask", ["name": .string(peptide?.name ?? peptideId), "parts": .string(blendContents(peptide) ?? "")])).font(.footnote)
                    Button { editing = true } label: { Label(t("ios_blend_amounts_set"), systemImage: "square.stack.3d.up") }
                        .buttonStyle(.bordered).controlSize(.small)
                }
                .callout(.tangerine)
            } else if data.blendAmounts[peptideId] != nil, let contents = blendContents(peptide) {
                HStack {
                    Text(t("ios_blend_amounts_yours", ["contents": .string(contents)])).font(.footnote).foregroundStyle(.secondary)
                    Spacer()
                    Button(t("ios_blend_amounts_change")) { editing = true }.font(.footnote)
                }
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { BlendAmountsSheet(peptideId: peptideId) } }
    }
}

private extension Array {
    subscript(safe i: Int) -> Element? { indices.contains(i) ? self[i] : nil }
}
