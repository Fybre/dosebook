import Foundation

// Port of src/lib/import/values.ts. Turning cell text into typed values. Every
// function refuses rather than guesses: ambiguous input returns nil and the row
// is reported as unreadable instead.

/// Blank means "not recorded", which is not the same as zero.
public func isBlank(_ v: String?) -> Bool {
    v == nil || v!.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}

/// A number, or nil. Tolerates thousands separators and a trailing unit.
public func parseNumber(_ v: String?) -> Double? {
    guard !isBlank(v), let v else { return nil }
    let cleaned = JSRegex(#"(\d),(?=\d{3}(\D|$))"#).replaceAll(v, "$1")
    guard let m = JSRegex(#"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"#).exec(cleaned) else { return nil }
    let n = m[0]!.jsNumber
    return n.isFinite ? n : nil
}

public struct Clock: Equatable, Sendable {
    public var h: Int, mi: Int, s: Int
}

/// A date in an unambiguous year-first form, local time. A bare dd/mm or mm/dd is refused.
/// `time` applies when the date carries none of its own.
public func parseDate(_ v: String?, _ time: String? = nil) -> Millis? {
    guard !isBlank(v), let v else { return nil }
    let text = v.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let m = JSRegex(#"^(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})(?:[T ](\d{1,2}):(\d{2})(?::(\d{2}))?)?"#).exec(text) else { return nil }
    let clock: Clock? = m[4] != nil
        ? Clock(h: Int(m[4]!)!, mi: Int(m[5]!)!, s: Int(m[6] ?? "0")!)
        : parseClock(time)
    let year = Int(m[1]!)!, month = Int(m[2]!)!, day = Int(m[3]!)!
    guard (1...12).contains(month), (1...31).contains(day) else { return nil }
    let cal = LocalTime.calendar
    var c = DateComponents()
    c.year = year; c.month = month; c.day = day
    c.hour = clock?.h ?? 0; c.minute = clock?.mi ?? 0; c.second = clock?.s ?? 0
    guard let date = cal.date(from: c) else { return nil }
    // Reject a date that rolled over: 31 February would otherwise become 3 March.
    let back = cal.dateComponents([.year, .month, .day], from: date)
    guard back.year == year, back.month == month, back.day == day else { return nil }
    return date.millis
}

/// `HH:MM`, `H:MM:SS`, or a 12-hour form with am/pm.
public func parseClock(_ v: String?) -> Clock? {
    guard !isBlank(v), let v else { return nil }
    let text = v.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let m = JSRegex(#"^(\d{1,2}):(\d{2})(?::(\d{2}))?\s*(am|pm)?$"#, "i").exec(text) else { return nil }
    var h = Int(m[1]!)!
    let mi = Int(m[2]!)!, s = Int(m[3] ?? "0")!
    let suffix = m[4]?.lowercased()
    if suffix == "pm" && h < 12 { h += 12 }
    if suffix == "am" && h == 12 { h = 0 }
    guard h <= 23, mi <= 59, s <= 59 else { return nil }
    return Clock(h: h, mi: mi, s: s)
}

/// A mass in micrograms from text that may name its unit. No unit means mg;
/// syringe units and unknown units are nil, never a guess.
public func parseDoseMcg(_ v: String?) -> Double? {
    guard !isBlank(v), let v else { return nil }
    let text = v.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let n = parseNumber(text), n >= 0 else { return nil }
    let raw = JSRegex(#"[\d.]\s*([a-zµμ]+)"#, "i").exec(text)?[1] ?? ""
    let unit = raw.lowercased().replacingOccurrences(of: "µ", with: "u").replacingOccurrences(of: "μ", with: "u")
    if unit.isEmpty { return n * 1000 }
    if ["mcg", "ug", "microgram", "micrograms"].contains(unit) { return n }
    if ["mg", "milligram", "milligrams"].contains(unit) { return n * 1000 }
    if ["g", "gram", "grams"].contains(unit) { return n * 1_000_000 }
    return nil
}

/// The yes-ish spellings exporters use.
public func parseBoolean(_ v: String?) -> Bool? {
    guard !isBlank(v), let v else { return nil }
    let t = v.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    if ["1", "true", "yes", "y", "on"].contains(t) { return true }
    if ["0", "false", "no", "n", "off"].contains(t) { return false }
    return nil
}
