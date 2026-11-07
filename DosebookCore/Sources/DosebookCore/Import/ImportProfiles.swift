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
    /// The app records a blend dose as the amount of the blend's first part, as
    /// Injectly does, rather than as the whole blend drawn.
    public var blendDoseIsFirstPart = false
    /// 0 means "not this format". Higher wins.
    public var score: @Sendable ([String]) -> Int
    public var read: @Sendable ([[String: String]], [String]) -> ProfileResult
}

/// The first header whose normalised form matches one of `wanted`, then a containment match.
private func pick(_ headers: [String], _ wanted: [String], excluding: [String?] = []) -> String? {
    let normalised = headers.filter { h in !excluding.contains(h) }.map { ($0, normaliseHeader($0)) }
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
    func wordMatch(_ n: String, in text: String) -> JSRegex.Match? {
        JSRegex("(^|[^a-z0-9])\(NSRegularExpression.escapedPattern(for: n))([^a-z0-9]|$)").exec(text)
    }
    for (p, n) in candidates where n.u16Count >= 4 {
        guard let m = wordMatch(n, in: clean) else { continue }
        // A name that also names a different compound elsewhere is a mix, such as
        // "CJC-1295 & Ipamorelin". Filing it under either part would be wrong, so it
        // is left unresolved for a blend of that name to claim.
        let rest = clean.u16Slice(0, m.index) + " " + clean.u16Slice(m.end)
        if candidates.contains(where: { $0.0.id != p.id && $0.1.u16Count >= 4 && wordMatch($0.1, in: rest) != nil }) { return nil }
        // Also a mix when the name joins this compound to something else the library
        // does not know by that spelling ("CJC-1295 & Ipamorelin" has no plain CJC-1295).
        if JSRegex(#"[&+/]|\band\b"#).test(rest), JSRegex("[a-z][a-z0-9-]{2,}").test(JSRegex(#"\band\b"#).replaceAll(rest, " ")) { return nil }
        return p
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

private let DATE_HEADERS = ["date", "date time", "datetime", "timestamp", "day", "when", "date of dose",
                            "time logged", "logged at", "taken at", "measured at", "date taken"]
private let ZONE_HEADERS = ["timezone", "time zone", "tz"]
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
    let date = pick(headers, DATE_HEADERS), zone = pick(headers, ZONE_HEADERS)
    let time = pick(headers, TIME_HEADERS, excluding: [date, zone]), name = pick(headers, NAME_HEADERS)
    let dose = pick(headers, DOSE_HEADERS), site = pick(headers, SITE_HEADERS), weight = pick(headers, WEIGHT_HEADERS)
    let notes = pick(headers, NOTE_HEADERS)
    var out: [CanonicalRecord] = [], problems: [RowProblem] = []
    for (i, r) in records.enumerated() {
        let sourceRow = i + 2
        let rawDate = date.flatMap { r[$0] }
        guard let at = parseDate(rawDate, time.flatMap { r[$0] }, timeZone: zone.flatMap { r[$0] }) else {
            if !isBlank(rawDate) {
                problems.append(RowProblem(sourceRow: sourceRow, reason: "Could not read the date \"\(rawDate!)\". Dates must lead with the year, like 2026-07-26, a day-first or month-first date is ambiguous."))
            }
            continue
        }
        let label = name.flatMap { r[$0] } ?? ""
        if !isBlank(label) {
            let split = splitLabelAndDose(label)
            // A bare number takes the unit the column header names, else milligrams.
            let fromColumn = dose.flatMap { parseDoseMcg(r[$0], bareUnit: doseUnitFromHeader($0) ?? .mg) }
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

/// The mass unit a dose column declares, read off the raw header ("Dose in mcg", "Dose (mg)").
public func doseUnitFromHeader(_ header: String) -> DoseUnit? {
    let t = header.lowercased().replacingOccurrences(of: "µ", with: "u").replacingOccurrences(of: "μ", with: "u")
    if JSRegex(#"\b(mcg|ug|micrograms?)\b"#).test(t) { return .mcg }
    if JSRegex(#"\b(mg|milligrams?)\b"#).test(t) { return .mg }
    return nil
}

// MARK: Injectly

private let INJECTLY_LOG_HEADERS = ["medication name", "dose in mcg", "time logged", "timezone", "injection site"]
private let INJECTLY_WEIGHT_HEADERS = ["weight", "measured at", "linked log id"]

/// Injectly (iPhone) exports one CSV per kind. Its logs and weights are history and
/// can be read here; doses are in micrograms and times carry their own time zone.
public let injectlyProfile = ImportProfile(id: "injectly", name: "Injectly", blendDoseIsFirstPart: true, score: { headers in
    let seen = headers.map(normaliseHeader)
    let logs = INJECTLY_LOG_HEADERS.filter { seen.contains($0) }.count
    let weights = INJECTLY_WEIGHT_HEADERS.filter { seen.contains($0) }.count
    return logs >= 3 ? 100 + logs : weights == 3 ? 100 + weights : 0
}, read: { records, headers in
    var out: [CanonicalRecord] = [], problems: [RowProblem] = []
    let isWeights = headers.contains("Measured At")
    for (i, r) in records.enumerated() {
        let sourceRow = i + 2
        let raw = isWeights ? r["Measured At"] : r["Time logged"]
        guard let at = parseDate(raw, timeZone: r["Timezone"]) else {
            if !isBlank(raw) { problems.append(RowProblem(sourceRow: sourceRow, reason: "Could not read the date \"\(raw!)\".")) }
            continue
        }
        if isWeights {
            if let w = parseNumber(r["Weight (kg)"]), w > 0 { out.append(.weight(at: at, weightKg: w, sourceRow: sourceRow)) }
            continue
        }
        guard let label = r["Medication Name"], !isBlank(label) else { continue }
        let notes = r["Notes"].flatMap { isBlank($0) ? nil : $0 }
        out.append(.dose(at: at, label: label, doseMcg: parseDoseMcg(r["Dose in mcg"], bareUnit: .mcg),
                         site: mapSite(r["Injection Site"]), notes: notes, sourceRow: sourceRow))
    }
    return ProfileResult(records: out, problems: problems)
})

/// Files recognised as coming from a known app but holding no history to import.
public func notHistoryMessage(_ headers: [String]) -> String? {
    let seen = Set(headers.map(normaliseHeader))
    if seen.isSuperset(of: ["medication name", "vial mg", "bac ml"]) {
        return "This is Injectly's list of medications, which holds settings rather than doses. Import the logs and weight files from the same export. A blend in it, such as a CJC-1295 and ipamorelin mix, can be added under Library as your own blend with the same name, so its doses find it."
    }
    if seen == ["field", "value"] {
        return "This looks like an app's profile settings, which hold no doses or weights to import."
    }
    return nil
}

public let IMPORT_PROFILES = [shotsyProfile, injectlyProfile, genericProfile]

/// The best-scoring profile for these headers, or nil if none can read them.
public func detectProfile(_ headers: [String]) -> ImportProfile? {
    var best: ImportProfile?, bestScore = 0
    for p in IMPORT_PROFILES {
        let s = p.score(headers)
        if s > bestScore { best = p; bestScore = s }
    }
    return best
}
