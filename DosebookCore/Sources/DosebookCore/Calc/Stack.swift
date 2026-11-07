import Foundation

// Port of src/lib/calc/stack.ts. What is running at once, and whether any of it
// collides. Built on receptor classes, so it stays quiet for deliberate,
// complementary pairings (CJC-1295 + ipamorelin) and speaks for redundancy.

public enum StackIssueKind: String, Sendable {
    case duplicateCompound = "duplicate-compound"
    case sharedMechanism = "shared-mechanism"
    case componentOverlap = "component-overlap"
}

public enum StackSeverity: String, Sendable { case high, medium }

public struct StackIssue: Equatable, Sendable {
    public var kind: StackIssueKind
    public var severity: StackSeverity
    public var title: String
    public var detail: String
    public var protocolIds: [String]
    public var compounds: [String]
}

func classLabel(_ c: MechanismClass) -> String {
    switch c {
    case .glp1Agonist: "GLP-1 receptor agonists"
    case .gipAgonist: "GIP receptor agonists"
    case .glucagonAgonist: "glucagon receptor agonists"
    case .amylinAnalogue: "amylin analogues"
    case .ghrhAnalogue: "GHRH analogues"
    case .ghrelinAgonist: "ghrelin receptor agonists"
    case .aromataseInhibitor: "aromatase inhibitors"
    case .serm: "oestrogen receptor modulators"
    case .gonadotropin: "gonadotropins"
    default: c.rawValue
    }
}

func classRisk(_ c: MechanismClass) -> (severity: StackSeverity, why: String)? {
    switch c {
    case .glp1Agonist: (.high, "Nausea, vomiting and the dehydration that follows are dose-dependent and add up, and pancreatitis is the recognised serious risk of the class. No trial has tested two of them together.")
    case .gipAgonist: (.high, "The gastrointestinal effects are additive, and no trial has tested two of them together.")
    case .glucagonAgonist: (.high, "Glucagon agonism raises heart rate and hepatic glucose output. Two at once compounds both, and has not been studied.")
    case .amylinAnalogue: (.high, "Amylin analogues slow gastric emptying and suppress appetite through the same pathway, so the nausea is additive rather than complementary.")
    case .aromataseInhibitor: (.high, "Both suppress the same enzyme, and oestradiol that is driven too low costs joint comfort, libido, lipids and bone density. Crashed oestrogen usually feels worse than the high oestrogen it was meant to fix, and it is slower to correct.")
    case .serm: (.medium, "Two modulators competing at the same receptor gives no more blockade than one, while stacking the side effects. Tamoxifen alongside clomiphene during recovery is the common version of this.")
    case .gonadotropin: (.medium, "Sustained gonadotropin above replacement level desensitises the Leydig cells it is meant to be stimulating, and drives aromatisation upward at the same time.")
    case .ghrhAnalogue: (.medium, "Both act on the same pituitary receptor, so the second mostly adds side effects and cost rather than more growth hormone.")
    case .ghrelinAgonist: (.medium, "Both act on the same receptor and the pituitary response saturates, so the second adds hunger and cortisol more than effect.")
    default: nil
    }
}

private struct ActiveCompound {
    var protocolId: String
    var protocolName: String
    var peptideId: String
    var name: String
    var peptide: Peptide
    /// Insertion-ordered, as the original's Set.
    var classes: [MechanismClass]
}

private func activeCompounds(_ protocols: [DoseProtocol], _ resolve: (String) -> Peptide?) -> [ActiveCompound] {
    protocols.compactMap { p in
        guard p.active, let peptide = resolve(p.peptideId) else { return nil }
        var classes: [MechanismClass] = []
        func add(_ c: MechanismClass) { if !classes.contains(c) { classes.append(c) } }
        (peptide.mechanismClass ?? []).forEach(add)
        for c in peptide.components ?? [] {
            (c.peptideId.flatMap(resolve)?.mechanismClass ?? []).forEach(add)
        }
        return ActiveCompound(protocolId: p.id, protocolName: p.name, peptideId: p.peptideId, name: peptide.name,
                              peptide: peptide, classes: classes)
    }
}

private func duplicateCompounds(_ compounds: [ActiveCompound]) -> [StackIssue] {
    var byPeptide = OrderedMap<String, [ActiveCompound]>()
    for c in compounds { byPeptide[c.peptideId, default: []].append(c) }
    return byPeptide.values.filter { $0.count > 1 }.map { group in
        StackIssue(kind: .duplicateCompound, severity: .high,
                   title: "\(group[0].name) is running in \(group.count) protocols at once",
                   detail: "\(group.map(\.protocolName).joined(separator: " and ")) both deliver \(group[0].name), so your real exposure is the sum of them. If that is deliberate, one protocol with the combined dose keeps the totals and the stock count honest.",
                   protocolIds: group.map(\.protocolId), compounds: [group[0].name])
    }
}

extension OrderedMap {
    subscript(key: Key, default value: @autoclosure () -> Value) -> Value {
        get { self[key] ?? value() }
        set { self[key] = newValue }
    }
}

private func sharedMechanisms(_ compounds: [ActiveCompound]) -> [StackIssue] {
    var byClass = OrderedMap<MechanismClass, OrderedMap<String, ActiveCompound>>()
    for c in compounds {
        for cls in c.classes {
            var seen = byClass[cls] ?? OrderedMap()
            seen[c.peptideId] = c
            byClass[cls] = seen
        }
    }
    return byClass.entries.compactMap { cls, seen in
        guard seen.count >= 2, let risk = classRisk(cls) else { return nil }
        let involved = seen.values
        return StackIssue(kind: .sharedMechanism, severity: risk.severity,
                          title: "\(involved.map(\.name).joined(separator: " and ")) are both \(classLabel(cls))",
                          detail: "\(risk.why) Their effects on this pathway do not simply add up to a better result.",
                          protocolIds: involved.map(\.protocolId), compounds: involved.map(\.name))
    }
}

private func componentOverlap(_ protocols: [DoseProtocol], _ resolve: @escaping (String) -> Peptide?, _ nowMs: Millis) -> [StackIssue] {
    struct Contribution { var peptideId: String?; var name: String; var weeklyMcg: Double; var typicalWeeklyHighMcg: Double? }
    struct Tally { var name: String; var weeklyMcg: Double; var typicalHighWeekly: Double?; var protocols: OrderedMap<String, String> }

    func contributions(_ peptide: Peptide, _ doseMcg: Double, _ perWeek: Double) -> [Contribution] {
        if let comps = peptide.components, !comps.isEmpty {
            return decomposeDose(peptide, doseMcg, resolve: resolve, dosesPerWeek: perWeek != 0 ? perWeek : nil).map {
                Contribution(peptideId: $0.peptideId, name: $0.name, weeklyMcg: $0.weeklyMcg ?? $0.mcg * perWeek,
                             typicalWeeklyHighMcg: $0.typicalWeeklyHighMcg)
            }
        }
        let range = peptide.doseRanges.first
        return [Contribution(peptideId: peptide.id, name: peptide.name, weeklyMcg: doseMcg * perWeek,
                             typicalWeeklyHighMcg: range.flatMap { $0.perWeek > 0 ? $0.highMcg * $0.perWeek : nil })]
    }

    var byComponent = OrderedMap<String, Tally>()
    for p in protocols where p.active {
        guard let peptide = resolve(p.peptideId) else { continue }
        let perWeek = protocolDosesPerWeek(p, nowMs)
        for part in contributions(peptide, scheduledDoseMcg(p, nowMs), perWeek) {
            guard let id = part.peptideId else { continue }
            var tally = byComponent[id] ?? Tally(name: part.name, weeklyMcg: 0, typicalHighWeekly: part.typicalWeeklyHighMcg, protocols: OrderedMap())
            tally.weeklyMcg += part.weeklyMcg
            tally.protocols[p.id] = p.name
            if tally.typicalHighWeekly == nil { tally.typicalHighWeekly = part.typicalWeeklyHighMcg }
            byComponent[id] = tally
        }
    }

    let mg: (Double) -> String = { "\(jsNumberString(jsFixed($0 / 1000, 3))) mg" }
    return byComponent.values.compactMap { t in
        guard t.protocols.count >= 2 else { return nil }
        let names = t.protocols.values.joined(separator: " and ")
        let over = t.typicalHighWeekly.map { t.weeklyMcg > $0 } ?? false
        return StackIssue(
            kind: .componentOverlap, severity: over ? .high : .medium,
            title: over ? "\(t.name) totals \(mg(t.weeklyMcg)) a week, above its usual range"
                : "\(t.name) is coming from \(t.protocols.count) protocols",
            detail: over
                ? "\(names) together deliver \(mg(t.weeklyMcg)) of \(t.name) a week, against a usual ceiling of \(mg(t.typicalHighWeekly!)). Neither protocol looks high on its own. It is the overlap that takes it over."
                : "\(names) both contain \(t.name), adding up to \(mg(t.weeklyMcg)) a week. Worth knowing, since neither protocol shows the combined figure on its own.",
            protocolIds: t.protocols.keys, compounds: [t.name])
    }
}

private func stackedOrals(_ compounds: [ActiveCompound]) -> [StackIssue] {
    let orals = compounds.filter { $0.peptide.c17AlphaAlkylated == true }
    guard orals.count >= 2 else { return [] }
    return [StackIssue(kind: .sharedMechanism, severity: .high,
                       title: "\(orals.map(\.name).joined(separator: " and ")) are both 17-alpha-alkylated orals",
                       detail: "The alkylation that lets these survive first-pass metabolism is exactly what strains the liver, and the effect is additive. Two at once also compounds the fall in HDL, which is already steeper on orals than on injectables. Liver enzymes and a lipid panel are worth having before and during.",
                       protocolIds: orals.map(\.protocolId), compounds: orals.map(\.name))]
}

private func pointlessAromataseInhibitor(_ compounds: [ActiveCompound]) -> [StackIssue] {
    let inhibitors = compounds.filter { $0.peptide.mechanismClass?.contains(.aromataseInhibitor) == true }
    guard !inhibitors.isEmpty else { return [] }
    let androgens = compounds.filter { $0.peptide.aromatises != nil }
    guard !androgens.isEmpty, !androgens.contains(where: { $0.peptide.aromatises == true }) else { return [] }
    return [StackIssue(
        kind: .sharedMechanism, severity: .high,
        title: "\(inhibitors.map(\.name).joined(separator: " and ")) with nothing that aromatises",
        detail: "Nothing currently running converts to oestradiol: \(androgens.map(\.name).joined(separator: ", ")) \(androgens.count == 1 ? "does" : "do") not. An aromatase inhibitor here has no oestrogen to control and can only push yours below where you need it, which costs joint comfort, libido, mood and HDL, and is slower to recover from than high oestradiol would have been.",
        protocolIds: (inhibitors + androgens).map(\.protocolId),
        compounds: inhibitors.map(\.name) + androgens.map(\.name))]
}

/// Everything worth saying about the running combination, most serious first.
/// Empty is the normal case.
public func stackIssues(_ protocols: [DoseProtocol], resolve: @escaping (String) -> Peptide?, nowMs: Millis) -> [StackIssue] {
    let compounds = activeCompounds(protocols, resolve)
    guard compounds.count >= 2 else { return [] }
    let all = duplicateCompounds(compounds) + sharedMechanisms(compounds) + stackedOrals(compounds)
        + pointlessAromataseInhibitor(compounds) + componentOverlap(protocols, resolve, nowMs)
    return all.stableSorted { ($0.severity == .high ? 0 : 1) < ($1.severity == .high ? 0 : 1) }
}
