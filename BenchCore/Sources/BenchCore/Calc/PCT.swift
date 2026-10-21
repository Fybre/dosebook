import Foundation

// Port of src/lib/calc/pct.ts. When suppressive compounds will have cleared, so
// a recovery protocol can start. Refuses to give a date where a compound's
// half-life has never been established in humans. Nothing here recommends one.

/// Five half-lives leaves about 3%: a convention, stated in the output.
public let CLEARED_FRACTION = 0.03

public struct SuppressiveCompound: Equatable, Sendable {
    public var peptideId: String
    public var name: String
    public var lastDoseAt: Millis
    public var halfLifeHours: Double?
    /// nil when the half-life is unknown, so no date can be given.
    public var clearedAt: Millis?
    public var unknownReason: String?
}

public struct PctPlan: Equatable, Sendable {
    /// Newest last dose first.
    public var compounds: [SuppressiveCompound]
    /// The latest clearance; nil if any compound blocked the calculation.
    public var earliestStart: Millis?
    public var blockedBy: [String]
    /// True once everything computable has cleared.
    public var clear: Bool
}

public func pctPlan(_ logs: [DoseLog], resolve: (String) -> Peptide?, nowMs: Millis = nowMillis()) -> PctPlan {
    var last = OrderedMap<String, Millis>()
    for log in logs where !log.isSkipped {
        guard resolve(log.peptideId)?.suppressesNaturalProduction == true else { continue }
        if let seen = last[log.peptideId] { if log.at > seen { last[log.peptideId] = log.at } }
        else { last[log.peptideId] = log.at }
    }
    let compounds = last.entries.map { peptideId, lastDoseAt -> SuppressiveCompound in
        let peptide = resolve(peptideId)!
        guard let h = peptide.halfLifeHours, h > 0 else {
            return SuppressiveCompound(peptideId: peptideId, name: peptide.name, lastDoseAt: lastDoseAt, halfLifeHours: nil,
                                       clearedAt: nil, unknownReason: peptide.halfLifeNote
                                           ?? "No half-life established in humans, so there is no honest clearance date.")
        }
        return SuppressiveCompound(peptideId: peptideId, name: peptide.name, lastDoseAt: lastDoseAt, halfLifeHours: h,
                                   clearedAt: lastDoseAt + hoursToClear(h) * HOUR_MS)
    }.stableSorted { $0.lastDoseAt > $1.lastDoseAt }
    let blockedBy = compounds.filter { $0.clearedAt == nil }.map(\.name)
    let known = compounds.compactMap(\.clearedAt)
    return PctPlan(compounds: compounds,
                   earliestStart: !blockedBy.isEmpty || known.isEmpty ? nil : known.max(),
                   blockedBy: blockedBy,
                   clear: !compounds.isEmpty && blockedBy.isEmpty && max(known.max() ?? 0, 0) <= nowMs)
}

/// Hours for a single dose to fall to `CLEARED_FRACTION` of its peak.
public func hoursToClear(_ halfLifeHours: Double) -> Double {
    guard halfLifeHours > 0 else { return 0 }
    return halfLifeHours * log2(1 / CLEARED_FRACTION)
}

/// What is left of the last dose now, 0 to 1; nil when unknowable. A future
/// timestamp reads as just taken.
public func remainingFraction(_ c: SuppressiveCompound, nowMs: Millis = nowMillis()) -> Double? {
    guard let h = c.halfLifeHours else { return nil }
    return fractionRemaining(max(0, (nowMs - c.lastDoseAt) / HOUR_MS), h)
}

public struct PctWeek: Sendable { public var week: Int; public var detail: String }

public struct PctTemplate: Sendable, Identifiable {
    public var id: String
    public var name: String
    public var summary: String
    public var compoundIds: [String]
    public var weeks: [PctWeek]
    public var source: String
    public var citationUrl: String
}

/// Published recovery protocols, each with what it was actually studied for. None is an approved use.
public let PCT_TEMPLATES: [PctTemplate] = [
    PctTemplate(
        id: "enclomiphene", name: "Enclomiphene",
        summary: "The isomer of clomiphene that raises LH and FSH without the slow-clearing one that causes most of the visual and mood complaints.",
        compoundIds: ["enclomiphene"],
        weeks: [PctWeek(week: 1, detail: "12.5 to 25 mg daily"), PctWeek(week: 2, detail: "12.5 to 25 mg daily"),
                PctWeek(week: 3, detail: "12.5 mg daily"), PctWeek(week: 4, detail: "12.5 mg daily, then stop and retest")],
        source: "Doses from the phase II trials of enclomiphene in men with secondary hypogonadism. The trials treated hypogonadism, not steroid-induced suppression.",
        citationUrl: "https://bjui-journals.onlinelibrary.wiley.com/doi/full/10.1111/bju.12363"),
    PctTemplate(
        id: "tamoxifen", name: "Tamoxifen",
        summary: "Blocks oestrogen feedback at the pituitary, raising LH and FSH. The longest-standing option and the one with the most human data behind the molecule, though not for this use.",
        compoundIds: ["tamoxifen"],
        weeks: [PctWeek(week: 1, detail: "20 mg daily"), PctWeek(week: 2, detail: "20 mg daily"),
                PctWeek(week: 3, detail: "10 mg daily"), PctWeek(week: 4, detail: "10 mg daily, then stop and retest")],
        source: "Doses are at or below the approved 20 to 40 mg range for breast cancer. Recovery of the axis is not an approved indication.",
        citationUrl: "https://pubmed.ncbi.nlm.nih.gov/1458563/"),
    PctTemplate(
        id: "hcg-then-serm", name: "hCG, then a SERM",
        summary: "hCG first to wake the testis directly, then a SERM once it stops, to restore the pituitary signal. Running hCG and the SERM together defeats the point: hCG suppresses the very signal the SERM is trying to raise.",
        compoundIds: ["hcg", "enclomiphene"],
        weeks: [PctWeek(week: 1, detail: "hCG 1000 IU every other day"), PctWeek(week: 2, detail: "hCG 1000 IU every other day, then stop hCG"),
                PctWeek(week: 3, detail: "Enclomiphene 25 mg daily"), PctWeek(week: 4, detail: "Enclomiphene 25 mg daily"),
                PctWeek(week: 5, detail: "Enclomiphene 12.5 mg daily"), PctWeek(week: 6, detail: "Enclomiphene 12.5 mg daily, then stop and retest")],
        source: "hCG doses are within the clinical range for hypogonadotropic hypogonadism. The sequence is community practice, not a studied protocol.",
        citationUrl: "https://www.fertstert.org/article/S0015-0282(16)60906-8/pdf"),
]

/// Bloodwork four weeks after the last dose of recovery, so it measures the recovery and not the drug.
public func retestAfter(_ protocolEndsAt: Millis, weeks: Double = 4) -> Millis {
    protocolEndsAt + weeks * 7 * DAY_MS
}
