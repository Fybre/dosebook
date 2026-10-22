import Foundation

// Reading a vial's label from the text a camera found on it. Labels have no
// standard layout, so this looks for the things every label carries: what it is
// and how much, and the lot and expiry when they are printed. Everything found is
// shown for checking before anything is saved.

public struct VialLabel: Equatable, Sendable {
    /// The library compound named on the label, if one clearly is.
    public var peptideId: String?
    /// Every compound the label could mean, for choosing when it is not clear.
    public var candidates: [String]
    public var strengthMg: Double?
    public var lot: String?
    /// The last day of the month printed, at local midnight.
    public var expiresAt: Millis?
}

public func parseVialLabel(_ lines: [String], peptides: [Peptide]) -> VialLabel {
    let cleaned = lines.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
    let text = cleaned.joined(separator: " ")

    // The compound: a whole line first, as a label usually gives the name a line
    // of its own; then the name with any strength removed; then anywhere in the text.
    var found: Peptide?
    for line in cleaned {
        if let p = resolvePeptide(line, peptides) ?? resolvePeptide(splitLabelAndDose(line).name, peptides) { found = p; break }
    }
    if found == nil { found = resolvePeptide(splitLabelAndDose(text).name, peptides) }
    var candidates = found.map { [$0.id] } ?? []
    if found == nil {
        for line in cleaned {
            let c = candidatePeptides(splitLabelAndDose(line).name, peptides).map(\.id)
            if !c.isEmpty { candidates = c; break }
        }
    }

    // The strength: the first amount with a mass unit. IU only where the library
    // says how many make a milligram.
    var strength: Double?
    if let m = JSRegex(#"(\d+(?:[.,]\d+)?)\s*(mg|mcg|µg|μg|ug|iu)\b"#, "i").exec(text) {
        let n = m[1]!.replacingOccurrences(of: ",", with: ".").jsNumber
        switch m[2]!.lowercased() {
        case "mg": strength = n
        case "iu": strength = found?.iuPerMg.flatMap { $0 > 0 ? n / $0 : nil }
        default: strength = n / 1000
        }
        if let s = strength, !(s > 0 && s.isFinite) { strength = nil }
    }

    let lot = JSRegex(#"\b(?:lot|batch|b\.?\s?n\.?)\s*(?:no\.?|number|#)?\s*[:#]?\s*([A-Z0-9][A-Z0-9-]{2,})"#, "i").exec(text)
        .flatMap { $0[1]?.uppercased() }

    return VialLabel(peptideId: found?.id, candidates: candidates, strengthMg: strength, lot: lot, expiresAt: labelExpiry(text))
}

/// An expiry printed as a month and year in any of the usual ways. A full day-first
/// or month-first date is read only when the day cannot be a month.
func labelExpiry(_ text: String) -> Millis? {
    guard let m = JSRegex(#"\b(?:exp(?:iry|ires|\.)?|use\s*by|best\s*before|bb)\s*(?:date)?\s*[:.]?\s*([0-9][0-9./\- ]{3,10}[0-9])"#, "i").exec(text) else { return nil }
    let raw = m[1]!.trimmingCharacters(in: .whitespaces)
    let parts = raw.split(whereSeparator: { "./- ".contains($0) }).compactMap { Int($0) }
    var year: Int?, month: Int?
    switch parts.count {
    case 2:
        if parts[0] > 999 { year = parts[0]; month = parts[1] }            // 2027-05
        else { month = parts[0]; year = parts[1] < 100 ? 2000 + parts[1] : parts[1] } // 05/2027, 05/27
    case 3:
        if parts[0] > 999 { year = parts[0]; month = parts[1] }            // 2027-05-31
        else if parts[0] > 12 { month = parts[1]; year = parts[2] }        // 31/05/2027
        else if parts[1] > 12 { month = parts[0]; year = parts[2] }        // 05/31/2027
        else { return nil }                                                 // 05/06/2027: which?
        if let y = year, y < 100 { year = 2000 + y }
    default: return nil
    }
    guard let y = year, let mo = month, (1...12).contains(mo), (2000...2100).contains(y) else { return nil }
    var c = DateComponents(); c.year = y; c.month = mo; c.day = 1
    let cal = LocalTime.calendar
    guard let first = cal.date(from: c), let last = cal.date(byAdding: DateComponents(month: 1, day: -1), to: first) else { return nil }
    return last.millis
}
