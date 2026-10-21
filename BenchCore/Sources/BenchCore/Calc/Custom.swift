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
    case name, routes, halfLifeHours, doseLowMcg, doseHighMcg, perWeek, iuPerMg, vialSizeMg
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
        vialSizesMg: (draft.vialSizeMg ?? 0) != 0 ? [draft.vialSizeMg!] : [],
        status: "Added by you. The app knows nothing about this compound beyond what you typed.")
    p.halfLifeNote = draft.halfLifeHours == nil
        ? "You did not give a half-life, so no curve is drawn for this compound. Doses are still logged and counted."
        : "Your own figure. Not checked against any published source."
    p.preparation = draft.preparation
    p.iuPerMg = draft.iuPerMg
    p.reconstitutedDays = draft.preparation == .powder ? 28 : nil
    p.cautionBanner = "You created this entry. Every figure in it is yours, and none of it has been checked against a published source."
    return p
}

/// Read an entry back into a draft for editing. Lossy on purpose.
public func peptideToDraft(_ p: Peptide) -> CustomDraft {
    let dose = p.doseRanges.first
    return CustomDraft(name: p.name, category: p.category, aka: p.aka.isEmpty ? nil : p.aka.joined(separator: ", "),
                       summary: p.summary, halfLifeHours: p.halfLifeHours, routes: p.routes,
                       preparation: p.preparation ?? .powder, doseLowMcg: dose?.lowMcg, doseHighMcg: dose?.highMcg,
                       frequency: dose?.frequency, perWeek: dose?.perWeek, vialSizeMg: p.vialSizesMg.first,
                       iuPerMg: p.iuPerMg, notes: p.mechanism)
}
