import Foundation

// Port of src/lib/calc/labs.ts. "Inside my lab's printed interval" and "which
// guideline band" are different claims; when neither applies the verdict is
// unknown, said out loud.

public enum LabStatus: String, Sendable { case inRange = "in-range", below, above, banded, unknown }

public struct LabVerdict: Equatable, Sendable {
    public var status: LabStatus
    public var label: String
    public var tone: Tone
    /// Where the judgement came from.
    public var basis: String?
}

private let UNKNOWN_VERDICT = LabVerdict(status: .unknown, label: "no range", tone: .muted, basis: nil)

func inBand(_ band: LabBand, _ value: Double) -> Bool {
    if let from = band.from, value < from { return false }
    if let under = band.under, value >= under { return false }
    return true
}

/// The lab's own interval wins when recorded; a guideline band otherwise.
public func verdictFor(_ marker: LabMarker?, _ result: LabResult) -> LabVerdict {
    guard let marker, result.value.isFinite else { return UNKNOWN_VERDICT }
    let value = result.value
    if result.refLow != nil || result.refHigh != nil {
        let hib = marker.higherIsBetter == true
        if let low = result.refLow, value < low {
            return LabVerdict(status: .below, label: "below range", tone: hib ? .rose : .tangerine, basis: "your lab's range")
        }
        if let high = result.refHigh, value > high {
            return LabVerdict(status: .above, label: "above range", tone: hib ? .tangerine : .rose, basis: "your lab's range")
        }
        return LabVerdict(status: .inRange, label: "in range", tone: .leaf, basis: "your lab's range")
    }
    if let g = marker.guideline, let band = g.bands.first(where: { inBand($0, value) }) {
        return LabVerdict(status: .banded, label: band.label, tone: Tone(rawValue: band.tone.rawValue) ?? .neutral, basis: g.source)
    }
    return UNKNOWN_VERDICT
}

public struct LabPoint: Equatable, Sendable {
    public var at: Millis
    public var value: Double
    public var id: String
}

public func labSeries(_ labs: [LabResult], _ markerId: String) -> [LabPoint] {
    labs.filter { $0.markerId == markerId && $0.value.isFinite }.map { LabPoint(at: $0.at, value: $0.value, id: $0.id) }
        .stableSorted { $0.at < $1.at }
}

public struct LabTrend: Equatable, Sendable {
    public var first: LabPoint
    public var latest: LabPoint
    public var delta: Double
    public var percent: Double?
    public var days: Double
}

public func labTrend(_ labs: [LabResult], _ markerId: String) -> LabTrend? {
    let s = labSeries(labs, markerId)
    guard s.count >= 2 else { return nil }
    let first = s[0], latest = s[s.count - 1]
    let delta = latest.value - first.value
    return LabTrend(first: first, latest: latest, delta: delta,
                    percent: first.value == 0 ? nil : (delta / abs(first.value)) * 100, days: (latest.at - first.at) / DAY_MS)
}

public func latestResult(_ labs: [LabResult], _ markerId: String) -> LabResult? {
    var best: LabResult?
    for l in labs where l.markerId == markerId { if best == nil || l.at > best!.at { best = l } }
    return best
}

/// Marker ids with at least one result, most recently measured first.
public func trackedMarkerIds(_ labs: [LabResult]) -> [String] {
    var newest = OrderedMap<String, Millis>()
    for l in labs { if let seen = newest[l.markerId] { if l.at > seen { newest[l.markerId] = l.at } } else { newest[l.markerId] = l.at } }
    return newest.entries.stableSorted { $0.value > $1.value }.map(\.key)
}

public struct LabCompoundTraits: Sendable {
    public var category: String
    public var mechanismClass: [String]
    public var c17AlphaAlkylated: Bool
    public init(category: String, mechanismClass: [String] = [], c17AlphaAlkylated: Bool = false) {
        self.category = category; self.mechanismClass = mechanismClass; self.c17AlphaAlkylated = c17AlphaAlkylated
    }
    public init(_ p: Peptide) {
        self.init(category: p.category.rawValue, mechanismClass: (p.mechanismClass ?? []).map(\.rawValue),
                  c17AlphaAlkylated: p.c17AlphaAlkylated == true)
    }
}

/// Which markers are worth watching for what is being run.
public func suggestedMarkerIds(_ compounds: [LabCompoundTraits]) -> [String] {
    var out: [String] = []
    func add(_ id: String) { if !out.contains(id) { out.append(id) } }
    for c in compounds {
        let classes = c.mechanismClass
        if c.category == "anabolic" {
            ["haematocrit", "hdl", "triglycerides", "bp-systolic", "bp-diastolic"].forEach(add)
            if c.c17AlphaAlkylated { add("alt"); add("ast") }
        }
        if c.category == "metabolic" || !classes.isEmpty { ["hba1c", "glucose-fasting", "triglycerides"].forEach(add) }
        if classes.contains("glp1-agonist") || classes.contains("gip-agonist") { add("lipase"); add("resting-hr") }
        if c.category == "growth-hormone" || classes.contains("ghrh-analogue") || classes.contains("ghrelin-agonist") {
            ["igf1", "glucose-fasting", "hba1c"].forEach(add)
        }
    }
    return out
}

public func missingMarkerIds(_ labs: [LabResult], _ compounds: [LabCompoundTraits]) -> [String] {
    let have = Set(labs.map(\.markerId))
    return suggestedMarkerIds(compounds).filter { !have.contains($0) }
}
