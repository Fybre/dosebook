import Foundation

// Port of src/lib/calc/custom.ts. A compound the library does not have, built
// from a short form. A custom entry never pretends to be researched: no
// citations, and its dose range is always tagged anecdotal.

public struct CustomDraft: Equatable, Sendable {
    public var name: String
    public var category: PeptideCategory
    public var aka: String?
    public var summary: String?
    /// nil when unknown, which is the honest default.
    public var halfLifeHours: Double?
    public var routes: [Route]
    public var preparation: Preparation
    public var doseLowMcg: Double?
    public var doseHighMcg: Double?
    public var frequency: String?
    public var perWeek: Double?
    public var vialSizeMg: Double?
    public var iuPerMg: Double?
    public var notes: String?
    /// What a blend holds; empty for a single compound.
    public var components: [BlendComponent] = []
    /// Whether a dose is the whole blend split by mass, or the amount of each part.
    public var blendDosing: BlendDosing = .split

    public init(name: String = "", category: PeptideCategory = .repair, aka: String? = nil, summary: String? = nil,
                halfLifeHours: Double? = nil, routes: [Route] = [.subcutaneous], preparation: Preparation = .powder,
                doseLowMcg: Double? = nil, doseHighMcg: Double? = nil, frequency: String? = nil, perWeek: Double? = nil,
                vialSizeMg: Double? = nil, iuPerMg: Double? = nil, notes: String? = nil) {
        self.name = name; self.category = category; self.aka = aka; self.summary = summary
        self.halfLifeHours = halfLifeHours; self.routes = routes; self.preparation = preparation
        self.doseLowMcg = doseLowMcg; self.doseHighMcg = doseHighMcg; self.frequency = frequency
        self.perWeek = perWeek; self.vialSizeMg = vialSizeMg; self.iuPerMg = iuPerMg; self.notes = notes
    }
}

public enum DraftField: String, Sendable {
    case name, routes, halfLifeHours, doseLowMcg, doseHighMcg, perWeek, iuPerMg, vialSizeMg, components
}

public struct DraftProblem: Equatable, Sendable {
    public var field: DraftField
    public var message: String
}

/// Custom ids are namespaced so they can never collide with a built-in.
public let CUSTOM_PREFIX = "custom-"

public func slugifyCompound(_ name: String) -> String {
    let decomposed = name.lowercased().decomposedStringWithCompatibilityMapping
    let stripped = String(String.UnicodeScalarView(decomposed.unicodeScalars.filter { !(0x300...0x36F).contains($0.value) }))
    var slug = stripped.replacingOccurrences(of: "[^a-z0-9]+", with: "-", options: .regularExpression)
    slug = slug.replacingOccurrences(of: "^-+|-+$", with: "", options: .regularExpression)
    slug = String(slug.prefix(40))
    return CUSTOM_PREFIX + (slug.isEmpty ? "compound" : slug)
}

public func isCustomId(_ id: String) -> Bool { id.hasPrefix(CUSTOM_PREFIX) }

/// What is wrong with the draft, in field order. Loose about pharmacology,
/// strict about what would break the app.
public func validateDraft(_ draft: CustomDraft, existing: [Peptide], editingId: String? = nil) -> [DraftProblem] {
    var problems: [DraftProblem] = []
    let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    // An edit is only checked against your own compounds; a new entry against everything.
    let others = editingId.map { id in existing.filter { $0.id != id && isCustomId($0.id) } } ?? existing

    if name.isEmpty {
        problems.append(DraftProblem(field: .name, message: "Give it a name."))
    } else if others.contains(where: { $0.name.lowercased() == name.lowercased() }) {
        problems.append(DraftProblem(field: .name, message: "\(name) is already in the library. Use that entry, or pick a different name."))
    } else if others.contains(where: { $0.id == slugifyCompound(name) }) {
        problems.append(DraftProblem(field: .name, message: "You already have a compound with that name."))
    }
    if draft.routes.isEmpty { problems.append(DraftProblem(field: .routes, message: "Pick at least one route.")) }
    if let h = draft.halfLifeHours, !(h > 0) {
        problems.append(DraftProblem(field: .halfLifeHours, message: "A half-life has to be more than zero hours."))
    }
    if let low = draft.doseLowMcg, !(low > 0) {
        problems.append(DraftProblem(field: .doseLowMcg, message: "A dose has to be more than zero."))
    }
    if let low = draft.doseLowMcg, let high = draft.doseHighMcg, high < low {
        problems.append(DraftProblem(field: .doseHighMcg, message: "The high end cannot be below the low end."))
    }
    if let pw = draft.perWeek, !(pw > 0) {
        problems.append(DraftProblem(field: .perWeek, message: "Doses per week has to be more than zero, or supply and burn rate cannot be worked out."))
    }
    if let iu = draft.iuPerMg, !(iu > 0) {
        problems.append(DraftProblem(field: .iuPerMg, message: "Units per milligram has to be more than zero."))
    }
    if let v = draft.vialSizeMg, !(v > 0) {
        problems.append(DraftProblem(field: .vialSizeMg, message: "A vial size has to be more than zero."))
    }
    if !draft.components.isEmpty {
        let parts = draft.components
        let selfId = editingId ?? slugifyCompound(name)
        if parts.count < 2 {
            problems.append(DraftProblem(field: .components, message: "A blend needs at least two parts."))
        } else if parts.contains(where: { $0.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }) {
            problems.append(DraftProblem(field: .components, message: "Every part needs a name."))
        } else if parts.contains(where: { $0.peptideId == selfId }) {
            problems.append(DraftProblem(field: .components, message: "A blend cannot contain itself."))
        } else if draft.blendDosing == .split && parts.contains(where: { !(($0.mgPerVial ?? 0) > 0) }) {
            // Splitting a dose by mass needs every mass.
            problems.append(DraftProblem(field: .components, message: "Give the amount of each part in one vial, so a dose can be split between them."))
        } else if parts.contains(where: { ($0.mgPerVial ?? 1) <= 0 }) {
            problems.append(DraftProblem(field: .components, message: "An amount has to be more than zero."))
        }
    }
    return problems
}

private func trimmedOrNil(_ s: String?) -> String? {
    guard let t = s?.trimmingCharacters(in: .whitespacesAndNewlines), !t.isEmpty else { return nil }
    return t
}

/// Turn a validated draft into a library entry. What was not supplied stays absent.
public func draftToPeptide(_ draft: CustomDraft) -> Peptide {
    let name = draft.name.trimmingCharacters(in: .whitespacesAndNewlines)
    let low = draft.doseLowMcg
    let high = draft.doseHighMcg ?? draft.doseLowMcg
    var doseRanges: [DoseRange] = []
    if let low, let high {
        doseRanges = [DoseRange(lowMcg: low, highMcg: high, frequency: trimmedOrNil(draft.frequency) ?? "as planned",
                                perWeek: draft.perWeek ?? 7, evidence: .anecdotal,
                                note: "Your own figure, not from any published source.")]
    }
    var p = Peptide(
        id: slugifyCompound(name), name: name,
        aka: (draft.aka ?? "").split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty },
        category: draft.category,
        summary: trimmedOrNil(draft.summary) ?? "A compound you added yourself.",
        mechanism: trimmedOrNil(draft.notes) ?? "Not recorded. Add what you know under notes when you edit this entry.",
        halfLifeHours: draft.halfLifeHours, routes: draft.routes, doseRanges: doseRanges,
        vialSizesMg: vialSize(draft).map { [$0] } ?? [],
        status: "Added by you. The app knows nothing about this compound beyond what you typed.")
    let parts = draft.components.map { c in
        BlendComponent(peptideId: c.peptideId, name: c.name.trimmingCharacters(in: .whitespacesAndNewlines), mgPerVial: c.mgPerVial)
    }
    if !parts.isEmpty {
        p.components = parts
        p.blendDosing = draft.blendDosing == .perComponent ? .perComponent : nil
        if trimmedOrNil(draft.summary) == nil {
            p.summary = "A blend you added yourself: " + parts.map { c in c.mgPerVial.map { "\(c.name) \(jsNumberString($0)) mg" } ?? c.name }.joined(separator: ", ") + "."
        }
    }
    p.halfLifeNote = !parts.isEmpty && draft.halfLifeHours == nil
        ? "A blend has no half-life of its own. Each part is drawn on its own curve, from the library entry it is linked to."
        : draft.halfLifeHours == nil
        ? "You did not give a half-life, so no curve is drawn for this compound. Doses are still logged and counted."
        : "Your own figure. Not checked against any published source."
    p.preparation = draft.preparation
    p.iuPerMg = draft.iuPerMg
    p.reconstitutedDays = draft.preparation == .powder ? 28 : nil
    p.cautionBanner = "You created this entry. Every figure in it is yours, and none of it has been checked against a published source."
    return p
}

/// The vial size as typed, or for a blend the sum of its parts.
private func vialSize(_ draft: CustomDraft) -> Double? {
    if let v = draft.vialSizeMg, v != 0 { return v }
    let masses = draft.components.compactMap(\.mgPerVial)
    guard !draft.components.isEmpty, masses.count == draft.components.count else { return nil }
    let total = masses.reduce(0, +)
    return total > 0 ? jsFixed(total, 6) : nil
}

/// Read an entry back into a draft for editing. Lossy on purpose.
public func peptideToDraft(_ p: Peptide) -> CustomDraft {
    let dose = p.doseRanges.first
    var draft = CustomDraft(name: p.name, category: p.category, aka: p.aka.isEmpty ? nil : p.aka.joined(separator: ", "),
                       summary: p.summary, halfLifeHours: p.halfLifeHours, routes: p.routes,
                       preparation: p.preparation ?? .powder, doseLowMcg: dose?.lowMcg, doseHighMcg: dose?.highMcg,
                       frequency: dose?.frequency, perWeek: dose?.perWeek, vialSizeMg: p.vialSizesMg.first,
                       iuPerMg: p.iuPerMg, notes: p.mechanism)
    draft.components = p.components ?? []
    draft.blendDosing = blendDosing(p)
    // A vial size that is only the sum of the parts stays derived, so changing a part moves it.
    if let v = draft.vialSizeMg, !draft.components.isEmpty {
        draft.vialSizeMg = nil
        if vialSize(draft) != v { draft.vialSizeMg = v }
    }
    // The summary was written for the parts; let it be rewritten if they change.
    if isBlend(p) && p.summary.hasPrefix("A blend you added yourself") { draft.summary = nil }
    return draft
}
