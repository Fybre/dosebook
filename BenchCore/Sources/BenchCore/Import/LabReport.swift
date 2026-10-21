import Foundation

// Port of src/lib/import/labreport.ts. A line per analyte: name, number, maybe a
// unit and a reference interval. Every match keeps its source line for review,
// and a unit that does not match the library is flagged, never converted.

public struct LabCandidate: Equatable, Sendable {
    public enum Confidence: String, Sendable { case exact, loose, unitMismatch = "unit-mismatch" }
    public var markerId: String
    public var markerName: String
    public var value: Double
    /// The unit as printed, when one was found.
    public var unit: String?
    /// The unit the library charts this marker in.
    public var expectedUnit: String
    public var refLow: Double?
    public var refHigh: Double?
    /// The line it came from, so the user can check it.
    public var source: String
    public var confidence: Confidence
}

public struct LabReport: Equatable, Sendable {
    public var candidates: [LabCandidate]
    public var collectedAt: Millis?
    public var lab: String?
}

private let SYNONYMS: [(String, [String])] = [
    ("hba1c", ["hemoglobin a1c", "haemoglobin a1c", "glycohemoglobin", "a1c"]),
    ("glucose-fasting", ["glucose fasting", "fasting blood glucose", "glucose, fasting", "fbg"]),
    ("insulin-fasting", ["insulin fasting", "insulin, fasting"]),
    ("triglycerides", ["trigs", "tg"]),
    ("hdl", ["hdl cholesterol", "hdl-c", "cholesterol hdl"]),
    ("ldl", ["ldl cholesterol", "ldl-c", "cholesterol ldl", "ldl calculated"]),
    ("alt", ["alanine transaminase", "sgpt", "alt (sgpt)"]),
    ("ast", ["aspartate transaminase", "sgot", "ast (sgot)"]),
    ("creatinine", ["creatinine serum", "serum creatinine"]),
    ("lipase", ["serum lipase"]),
    ("haematocrit", ["hematocrit", "hct", "pcv", "packed cell volume"]),
    ("tsh", ["thyroid stimulating hormone", "thyrotropin"]),
    ("igf1", ["igf-1", "igf 1", "insulin like growth factor", "somatomedin c"]),
    ("bp-systolic", ["systolic", "systolic bp"]),
    ("bp-diastolic", ["diastolic", "diastolic bp"]),
    ("resting-hr", ["resting pulse", "pulse", "heart rate"]),
]

/// Names to search for, longest first, so the more specific analyte always wins.
private let SEARCH_TERMS: [(markerId: String, term: String, exact: Bool)] = {
    var rows: [(markerId: String, term: String, exact: Bool)] = []
    for m in Library.labMarkers {
        rows.append((m.id, m.name.lowercased(), true))
        if let aka = m.aka { rows.append((m.id, aka.lowercased(), false)) }
    }
    for (id, terms) in SYNONYMS { for term in terms { rows.append((id, term, false)) } }
    return rows.stableSorted { $0.term.u16Count > $1.term.u16Count }
}()

/// Length-preserving comparison form: positions found in it slice the original line.
private func normaliseLab(_ s: String) -> String {
    s.lowercased().replacingOccurrences(of: "µ", with: "u").replacingOccurrences(of: "μ", with: "u")
}

/// Where a name appears, tolerating any whitespace between its words; returns where the result starts.
private func findTerm(_ haystack: String, _ term: String) -> (start: Int, end: Int)? {
    let words = term.trimmingCharacters(in: .whitespaces).split(whereSeparator: { $0.isWhitespace }).map { NSRegularExpression.escapedPattern(for: String($0)) }
    guard let m = JSRegex("(?<![a-z0-9])\(words.joined(separator: #"\s+"#))(?![a-z])", "i").exec(haystack) else { return nil }
    return (m.index, m.end)
}

private func sameUnit(_ a: String, _ b: String) -> Bool {
    let clean = { (s: String) in JSRegex(#"[\s.]"#).replaceAll(normaliseLab(s), "") }
    return clean(a) == clean(b)
}

/// Units with no slash or percent, which cannot be recognised by shape.
private let BARE_UNITS: Set<String> = ["%", "bpm", "mmhg", "fl", "pg", "ng", "mg", "g", "ml", "l", "ratio", "index", "iu", "miu", "uiu"]

private func numbersIn(_ line: String) -> [(value: Double, after: String, index: Int)] {
    JSRegex(#"(-?\d+(?:[.,]\d+)?)"#).all(line).compactMap { m in
        let raw = m[1]!
        let value = (JSRegex(#",\d{3}$"#).test(raw) ? raw.replacingFirst(",", "") : raw.replacingFirst(",", ".")).jsNumber
        guard value.isFinite else { return nil }
        return (value, line.u16Slice(m.index + raw.u16Count), m.index)
    }
}

private extension String {
    func replacingFirst(_ a: String, _ b: String) -> String {
        guard let r = range(of: a) else { return self }
        return replacingCharacters(in: r, with: b)
    }
}

private func unitAfter(_ after: String) -> String? {
    guard let m = JSRegex(#"^\s*([A-Za-zµμ%][A-Za-zµμ%/^\d.-]*)"#).exec(after) else { return nil }
    let unit = JSRegex("[.,;:]+$").replaceAll(m[1]!, "")
    guard !unit.isEmpty else { return nil }
    let shaped = unit.contains("/") || unit.contains("%")
    return shaped || BARE_UNITS.contains(normaliseLab(unit)) ? unit : nil
}

/// A reference interval, kept apart from the result so a bound is never charted as your value.
private func referenceIn(_ line: String) -> (low: Double?, high: Double?) {
    let num = { (s: String) in s.replacingFirst(",", ".").jsNumber }
    if let r = JSRegex(#"(?:ref(?:erence)?(?:\s*(?:range|interval))?\s*[:=]?\s*)?(-?\d+(?:[.,]\d+)?)\s*(?:-|to|–)\s*(-?\d+(?:[.,]\d+)?)"#, "i").exec(line) {
        let low = num(r[1]!), high = num(r[2]!)
        if low.isFinite && high.isFinite && high > low { return (low, high) }
    }
    if let m = JSRegex(#"[<≤]\s*(-?\d+(?:[.,]\d+)?)"#).exec(line) { return (nil, num(m[1]!)) }
    if let m = JSRegex(#"[>≥]\s*(-?\d+(?:[.,]\d+)?)"#).exec(line) { return (num(m[1]!), nil) }
    return (nil, nil)
}

private func findCollectedAt(_ lines: [String]) -> Millis? {
    let labelled = JSRegex(#"(collect(?:ed|ion)|drawn|specimen|sample|report(?:ed)?|date)\D{0,20}?([0-9][0-9./-]{6,})"#, "i")
    for line in lines.prefix(40) {
        if let m = labelled.exec(line), let parsed = parseDate(m[2]) { return parsed }
    }
    let any = JSRegex(#"\b(\d{4}-\d{2}-\d{2}|\d{1,2}[./-]\d{1,2}[./-]\d{2,4})\b"#)
    for line in lines.prefix(20) {
        if let m = any.exec(line), let parsed = parseDate(m[1]) { return parsed }
    }
    return nil
}

private func findLabName(_ lines: [String]) -> String? {
    let known = JSRegex(#"\b(quest|labcorp|sonic|synlab|randox|medichecks|thriva|bupa|nhs|srl|metropolis|thyrocare|dr\.?\s*lal)\b"#, "i")
    for line in lines.prefix(25) { if let m = known.exec(line) { return m[0] } }
    return nil
}

/// One result per marker; the first occurrence wins.
public func parseLabReport(_ lines: [String]) -> LabReport {
    var candidates: [LabCandidate] = [], claimed = Set<String>()
    let skip = JSRegex(#"^\s*(reference|normal|expected)\b"#)
    for line in lines {
        let haystack = normaliseLab(line)
        if skip.test(haystack) { continue }
        for (markerId, term, exact) in SEARCH_TERMS where !claimed.contains(markerId) {
            guard let found = findTerm(haystack, term) else { continue }
            let reference = referenceIn(line)
            // The first number after the name that is not a bound of the interval.
            guard let candidate = numbersIn(line).first(where: { n in
                n.index >= found.end && n.value != reference.low && n.value != reference.high
            }) else { continue }
            guard let marker = Library.marker(markerId) else { continue }
            let unit = unitAfter(candidate.after)
            let unitMatches = unit.map { sameUnit($0, marker.unit) } ?? true
            candidates.append(LabCandidate(markerId: markerId, markerName: marker.name, value: candidate.value, unit: unit,
                                           expectedUnit: marker.unit, refLow: reference.low, refHigh: reference.high,
                                           source: line.trimmingCharacters(in: .whitespacesAndNewlines),
                                           confidence: !unitMatches ? .unitMismatch : exact ? .exact : .loose))
            claimed.insert(markerId)
            break
        }
    }
    return LabReport(candidates: candidates, collectedAt: findCollectedAt(lines), lab: findLabName(lines))
}
