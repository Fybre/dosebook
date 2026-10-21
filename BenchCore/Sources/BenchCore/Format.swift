import Foundation

// Port of src/lib/format.ts. Presentation only.

/// Trim trailing zeros: `Number(n.toFixed(maxDp)).toString()`.
public func trim(_ n: Double, _ maxDp: Int = 4) -> String {
    guard n.isFinite else { return "n/a" }
    return jsNumberString(jsFixed(n, maxDp))
}

/// A dose in whichever unit reads best: mcg below 1 mg, mg above.
public func formatDose(_ mcg: Double, force: DoseUnit? = nil) -> String {
    let p = formatDoseParts(mcg, force: force)
    return p.unit.isEmpty ? p.value : "\(p.value) \(p.unit)"
}

public func formatDoseParts(_ mcg: Double, force: DoseUnit? = nil) -> (value: String, unit: String) {
    guard mcg.isFinite else { return ("n/a", "") }
    let unit = force ?? (abs(mcg) >= 1000 ? .mg : .mcg)
    return unit == .mg ? (trim(mcg / 1000, 3), "mg") : (trim(mcg, 2), "mcg")
}

/// A plan's dose: the amount, and how many a dose day holds.
public func formatDosePerDay(_ doseMcg: Double, _ perDay: Int) -> String {
    perDay > 1 ? "\(formatDose(doseMcg)) × \(perDay)" : formatDose(doseMcg)
}

private let SITE_KEY: [String: String] = [
    "abdomen-ul": "site_abdomen_ul", "abdomen-um": "site_abdomen_um", "abdomen-ur": "site_abdomen_ur",
    "abdomen-ll": "site_abdomen_ll", "abdomen-lm": "site_abdomen_lm", "abdomen-lr": "site_abdomen_lr",
    "thigh-l": "site_thigh_l", "thigh-r": "site_thigh_r", "arm-l": "site_arm_l", "arm-r": "site_arm_r",
    "glute-l": "site_glute_l", "glute-r": "site_glute_r",
]

/// Which body part, in the reader's language (the raw id for one this build has never heard of).
public func siteLabel(_ site: InjectionSite) -> String {
    SITE_KEY[site.rawValue].map { t($0) } ?? site.rawValue
}

public func formatMl(_ ml: Double, dp: Int = 3) -> String { ml.isFinite ? "\(trim(ml, dp)) mL" : "n/a" }
public func formatUnits(_ units: Double) -> String { units.isFinite ? trim(units, 2) : "n/a" }

public func formatConcentration(_ mcgPerMl: Double) -> String {
    guard mcgPerMl.isFinite else { return "n/a" }
    let mgPerMl = mcgPerMl / 1000
    return mgPerMl >= 0.1 ? "\(trim(mgPerMl, 3)) mg/mL" : "\(trim(mcgPerMl, 1)) mcg/mL"
}

private func locale() -> Locale { I18n.lang.locale }

/// "in 3 hours", "2 days ago".
public func relativeTime(_ targetMs: Millis, nowMs: Millis = nowMillis()) -> String {
    let diffMin = jsRound((targetMs - nowMs) / 60000)
    if abs(diffMin) < 1 { return t("fmt_just_now") }
    let f = RelativeDateTimeFormatter()
    f.locale = locale()
    f.dateTimeStyle = .named
    f.unitsStyle = .full
    if abs(diffMin) < 60 { return f.localizedString(from: DateComponents(minute: Int(diffMin))) }
    let hours = jsRound(diffMin / 60)
    if abs(hours) < 24 { return f.localizedString(from: DateComponents(hour: Int(hours))) }
    let days = jsRound(diffMin / 1440)
    if abs(days) < 30 { return f.localizedString(from: DateComponents(day: Int(days))) }
    return f.localizedString(from: DateComponents(month: Int(jsRound(days / 30))))
}

/// "36 h", "4.5 d", "12 min".
public func formatDuration(_ hours: Double) -> String {
    guard hours.isFinite else { return "n/a" }
    if abs(hours) < 1 { return "\(jsNumberString(jsRound(hours * 60))) min" }
    if abs(hours) < 48 { return "\(trim(hours, 1)) h" }
    return "\(trim(hours / 24, 1)) d"
}

/// Half-lives in their natural unit.
public func formatHalfLife(_ hours: Double?) -> String {
    guard let hours else { return t("fmt_not_established") }
    if hours < 1 { return t("count_minutes", ["n": .number(jsRound(hours * 60))]) }
    if hours < 48 { return t("count_hours", ["n": .string(trim(hours, 1))]) }
    return t("count_days", ["n": .string(trim(hours / 24, 1))])
}

private func dateFormatter(_ template: String) -> DateFormatter {
    let f = DateFormatter()
    f.locale = locale()
    f.timeZone = LocalTime.calendar.timeZone
    f.calendar = LocalTime.calendar
    f.setLocalizedDateFormatFromTemplate(template)
    return f
}

/// A date, with the year only when it is not the current one.
public func formatDate(_ ms: Millis, nowMs: Millis = nowMillis()) -> String {
    let cal = LocalTime.calendar
    let same = cal.component(.year, from: Date(millis: ms)) == cal.component(.year, from: Date(millis: nowMs))
    return dateFormatter(same ? "MMMd" : "yMMMd").string(from: Date(millis: ms))
}

public func formatTime(_ ms: Millis) -> String { dateFormatter("jmm").string(from: Date(millis: ms)) }
public func formatWeekday(_ ms: Millis) -> String { dateFormatter("EEE").string(from: Date(millis: ms)) }
public func formatDateTime(_ ms: Millis, nowMs: Millis = nowMillis()) -> String { "\(formatDate(ms, nowMs: nowMs)), \(formatTime(ms))" }

public func percent(_ fraction: Double, dp: Int = 0) -> String {
    fraction.isFinite ? "\(jsToFixed(fraction * 100, dp))%" : "n/a"
}

/// How loudly to say where an estimate came from.
public func estimateKey(_ evidence: EvidenceLevel) -> String {
    switch evidence {
    case .preclinical: "estimate_animal"
    case .preliminary: "estimate_early_human"
    default: "estimate_anecdotal"
    }
}

/// One sentence on where an estimated half-life came from, shared by the chart and the library.
public func describeHalfLifeEstimate(_ e: HalfLifeEstimate) -> String {
    if e.evidence == .anecdotal {
        return t("estimate_claimed", ["hours": .string(formatHalfLife(e.hours)), "source": .string(e.source)])
    }
    return t("estimate_measured", [
        "hours": .string(formatHalfLife(e.hours)),
        "where": .string(e.species ?? t("estimate_unstated_species")),
        "how": .string(e.route.map { t("estimate_given_it", ["route": .string($0.label.lowercased())]) } ?? ""),
        "early": .string(e.evidence == .preliminary ? t("estimate_early_work") : ""),
        "source": .string(e.source),
    ])
}
