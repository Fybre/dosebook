import Foundation

// Port of src/lib/import/profiles.ts. Recognising where an exported file came
// from, by a score over its headers, and reading its rows into canonical records.

/// One thing read out of a file, before it becomes app data.
public enum CanonicalRecord: Equatable, Sendable {
    /// `label` still has to be resolved against the library.
    case dose(at: Millis, label: String, doseMcg: Double?, site: InjectionSite?, notes: String?, sourceRow: Int)
    case weight(at: Millis, weightKg: Double, sourceRow: Int)
}

public struct RowProblem: Equatable, Sendable {
    public var sourceRow: Int
    public var reason: String
}

public struct ProfileResult: Equatable, Sendable {
    public var records: [CanonicalRecord]
    public var problems: [RowProblem]
}

public struct ImportProfile: Sendable {
    public var id: String
    public var name: String
    /// 0 means "not this format". Higher wins.
    public var score: @Sendable ([String]) -> Int
    public var read: @Sendable ([[String: String]], [String]) -> ProfileResult
}

/// The first header whose normalised form matches one of `wanted`, then a containment match.
private func pick(_ headers: [String], _ wanted: [String]) -> String? {
    let normalised = headers.map { ($0, normaliseHeader($0)) }
    for w in wanted { if let hit = normalised.first(where: { $0.1 == w }) { return hit.0 } }
    for w in wanted { if let hit = normalised.first(where: { $0.1.contains(w) }) { return hit.0 } }
    return nil
}

private func has(_ headers: [String], _ wanted: [String]) -> Int { pick(headers, wanted) != nil ? 1 : 0 }

/// Free-text site names onto the app's set, from words. nil rather than a guess.
public func mapSite(_ text: String?) -> InjectionSite? {
    guard !isBlank(text), let text else { return nil }
    let t = text.lowercased()
    let test = { (p: String) in JSRegex(p).test(t) }
    let left = test(#"\bleft\b|\bl\b"#)
    let right = test(#"\bright\b|\br\b"#)
    let middle = test(#"\bmid\b|\bmiddle\b|\bcentre\b|\bcenter\b"#)
    let upper = test(#"\bupper\b|\btop\b"#)
    let lower = test(#"\blower\b|\bbottom\b"#)

    if test("stomach|abdomen|abdominal|belly|tummy") {
        guard let side = middle ? "m" : left ? "l" : right ? "r" : nil else { return nil }
        // Most exports only distinguish upper from lower; upper when unsaid.
        let band = lower ? "l" : upper ? "u" : "u"
        return InjectionSite(rawValue: "abdomen-\(band)\(side)")
    }
    if test("thigh|leg|quad") { return left ? .thighL : right ? .thighR : nil }
    if test("arm|delt|tricep|shoulder") { return left ? .armL : right ? .armR : nil }
    if test("glute|buttock|butt|hip") { return left ? .gluteL : right ? .gluteR : nil }
    return nil
}

/// "Mounjaro® 10.0 mg" → name and dose, separately.
public func splitLabelAndDose(_ label: String) -> (name: String, doseMcg: Double?) {
    let doseRe = JSRegex(#"([\d.]+)\s*(mcg|µg|μg|ug|mg|g)\b"#, "i")
    let doseMcg = doseRe.exec(label).flatMap { parseDoseMcg($0[0]) }
    var name = doseRe.replaceFirst(label, " ")
    name = JSRegex("[®™©]").replaceAll(name, " ")
    name = JSRegex(#"\s+"#).replaceAll(name, " ")
    return (name.trimmingCharacters(in: .whitespaces), doseMcg)
}

/// A product name to a library peptide: exact name or alias first, then the longest
/// whole-word match, so a blend that merely contains a name cannot capture it.
public func resolvePeptide(_ name: String, _ peptides: [Peptide]) -> Peptide? {
    var clean = JSRegex("[®™©]").replaceAll(name.lowercased(), "")
    clean = JSRegex(#"\s+"#).replaceAll(clean, " ").trimmingCharacters(in: .whitespacesAndNewlines)
    guard !clean.isEmpty else { return nil }
    let names = { (p: Peptide) in ([p.name] + p.aka).map { $0.lowercased() } }
    if let exact = peptides.first(where: { names($0).contains(clean) }) { return exact }
    let candidates = peptides.flatMap { p in names(p).map { (p, $0) } }.stableSorted { $0.1.u16Count > $1.1.u16Count }
    for (p, n) in candidates where n.u16Count >= 4 {
        let escaped = NSRegularExpression.escapedPattern(for: n)
        if JSRegex("(^|[^a-z0-9])\(escaped)([^a-z0-9]|$)").test(clean) { return p }
    }
    return nil
}

// MARK: Shotsy

private let SHOTSY_HEADERS = ["jab", "jab notes", "pain level", "recorded weight", "food noise"]

public let shotsyProfile = ImportProfile(id: "shotsy", name: "Shotsy", score: { headers in
    let seen = headers.map(normaliseHeader)
    let hits = SHOTSY_HEADERS.filter { seen.contains($0) }.count
    return hits >= 2 ? 100 + hits : 0
}, read: { records, _ in
    var out: [CanonicalRecord] = [], problems: [RowProblem] = []
    for (i, r) in records.enumerated() {
        let sourceRow = i + 2
        guard let at = parseDate(r["Date"], r["Time"]) else {
            if !isBlank(r["Date"]) { problems.append(RowProblem(sourceRow: sourceRow, reason: "Could not read the date \"\(r["Date"]!)\".")) }
            continue
        }
        if !isBlank(r["Jab"]), let jab = r["Jab"] {
            let split = splitLabelAndDose(jab)
            let notes = [r["Jab Notes"], r["Day Notes"]].compactMap { $0 }.filter { !isBlank($0) }.joined(separator: " · ")
            out.append(.dose(at: at, label: split.name.isEmpty ? jab : split.name, doseMcg: split.doseMcg, site: mapSite(r["Site"]),
                             notes: notes.isEmpty ? nil : notes, sourceRow: sourceRow))
        }
        if let w = parseNumber(r["Recorded Weight (kg)"]), w > 0 { out.append(.weight(at: at, weightKg: w, sourceRow: sourceRow)) }
    }
    return ProfileResult(records: out, problems: problems)
})

// MARK: Generic

private let DATE_HEADERS = ["date", "date time", "datetime", "timestamp", "day", "when", "date of dose"]
private let TIME_HEADERS = ["time", "time of day", "clock"]
private let NAME_HEADERS = ["peptide", "compound", "medication", "med", "drug", "product", "name", "jab", "shot", "injection", "substance"]
private let DOSE_HEADERS = ["dose", "dose mg", "dose mcg", "amount", "quantity", "strength", "dosage"]
private let SITE_HEADERS = ["site", "injection site", "location", "body site"]
private let WEIGHT_HEADERS = ["weight", "recorded weight", "body weight", "mass"]
private let NOTE_HEADERS = ["notes", "note", "comment", "comments", "jab notes"]

/// Above this, a figure cannot be a person's weight in kilograms.
private let IMPLAUSIBLE_KG: Double = 250

/// The unit a weight column declares, read off the raw header where "(lb)" lives.
public func weightUnitFromHeader(_ header: String) -> WeightUnit? {
    let t = header.lowercased()
    if JSRegex(#"\blbs?\b|pound"#).test(t) { return .lb }
    if JSRegex(#"\bkgs?\b|kilogram"#).test(t) { return .kg }
    return nil
}

public let genericProfile = ImportProfile(id: "generic", name: "Generic spreadsheet", score: { headers in
    guard has(headers, DATE_HEADERS) == 1 else { return 0 }
    let useful = has(headers, NAME_HEADERS) + has(headers, WEIGHT_HEADERS)
    return useful > 0 ? 1 + useful : 0
}, read: { records, headers in
    let date = pick(headers, DATE_HEADERS), time = pick(headers, TIME_HEADERS), name = pick(headers, NAME_HEADERS)
    let dose = pick(headers, DOSE_HEADERS), site = pick(headers, SITE_HEADERS), weight = pick(headers, WEIGHT_HEADERS)
    let notes = pick(headers, NOTE_HEADERS)
    var out: [CanonicalRecord] = [], problems: [RowProblem] = []
    for (i, r) in records.enumerated() {
        let sourceRow = i + 2
        let rawDate = date.flatMap { r[$0] }
        guard let at = parseDate(rawDate, time.flatMap { r[$0] }) else {
            if !isBlank(rawDate) {
                problems.append(RowProblem(sourceRow: sourceRow, reason: "Could not read the date \"\(rawDate!)\". Dates must lead with the year, like 2026-07-26, a day-first or month-first date is ambiguous."))
            }
            continue
        }
        let label = name.flatMap { r[$0] } ?? ""
        if !isBlank(label) {
            let split = splitLabelAndDose(label)
            let fromColumn = dose.flatMap { parseDoseMcg(r[$0]) }
            let note = notes.flatMap { r[$0] }.flatMap { isBlank($0) ? nil : $0 }
            out.append(.dose(at: at, label: split.name.isEmpty ? label : split.name, doseMcg: fromColumn ?? split.doseMcg,
                             site: site.flatMap { mapSite(r[$0]) }, notes: note, sourceRow: sourceRow))
        }
        if let weight, let w = parseNumber(r[weight]), w > 0 {
            let unit = weightUnitFromHeader(weight)
            if unit == .lb {
                out.append(.weight(at: at, weightKg: lbToKg(w), sourceRow: sourceRow))
            } else if unit == .kg || w <= IMPLAUSIBLE_KG {
                out.append(.weight(at: at, weightKg: w, sourceRow: sourceRow))
            } else {
                problems.append(RowProblem(sourceRow: sourceRow, reason: "Weight of \(jsNumberString(w)) is too high to be kilograms and the column does not say its unit. Label the column \"Weight (lb)\" or convert it."))
            }
        }
    }
    return ProfileResult(records: out, problems: problems)
})

public let IMPORT_PROFILES = [shotsyProfile, genericProfile]

/// The best-scoring profile for these headers, or nil if none can read them.
public func detectProfile(_ headers: [String]) -> ImportProfile? {
    var best: ImportProfile?, bestScore = 0
    for p in IMPORT_PROFILES {
        let s = p.score(headers)
        if s > bestScore { best = p; bestScore = s }
    }
    return best
}
