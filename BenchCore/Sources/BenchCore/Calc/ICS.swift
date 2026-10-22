import Foundation

// Port of src/lib/calc/ics.ts. The dose schedule as a calendar file.
// Every dose is written out (no RRULE: a second implementation of the schedule
// would be a second answer), and times are FLOATING local time: no Z, no TZID,
// so a 07:00 dose stays at 07:00 across daylight-saving changes.

private let MAX_EVENTS = 2000
private let EVENT_MINUTES = 15

public func calendarFileName(_ atMs: Millis = nowMillis()) -> String {
    let f = ISO8601DateFormatter()
    f.formatOptions = [.withFullDate]
    return "bench-doses-\(f.string(from: Date(millis: atMs))).ics"
}

/// Escape a TEXT value; backslash first.
func escapeText(_ value: String) -> String {
    value.replacingOccurrences(of: "\\", with: "\\\\")
        .replacingOccurrences(of: ";", with: "\\;")
        .replacingOccurrences(of: ",", with: "\\,")
        .replacingOccurrences(of: "\r\n", with: "\\n")
        .replacingOccurrences(of: "\n", with: "\\n")
}

/// Fold a content line to 75 octets, never splitting a character.
public func foldLine(_ line: String) -> String {
    if line.utf8.count <= 75 { return line }
    var out: [String] = []
    var current = ""
    var width = 0
    var limit = 75
    for ch in line {
        let size = String(ch).utf8.count
        if width + size > limit {
            out.append(current)
            current = ""; width = 0; limit = 74
        }
        current.append(ch)
        width += size
    }
    out.append(current)
    return out.joined(separator: "\r\n ")
}

private func floating(_ ms: Millis) -> String {
    let c = LocalTime.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(millis: ms))
    return String(format: "%04d%02d%02dT%02d%02d%02d", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
}

private func utcStamp(_ ms: Millis) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    let c = cal.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(millis: ms))
    return String(format: "%04d%02d%02dT%02d%02d%02dZ", c.year!, c.month!, c.day!, c.hour!, c.minute!, c.second!)
}

/// The calendar file for a plan: doses from now to the horizon.
public func buildCalendar(protocols: [DoseProtocol], peptides: [Peptide], settings: RemindersSettings, nowMs: Millis,
                          days: Double? = nil) -> String {
    let span = max(1, days ?? settings.calendarDays)
    let until = nowMs + span * DAY_MS
    let byId = Dictionary(peptides.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    let seq = Int((nowMs / 60_000).rounded(.down))
    var lines = ["BEGIN:VCALENDAR", "VERSION:2.0", "PRODID:-//Bench//Dose schedule//EN", "CALSCALE:GREGORIAN",
                 "METHOD:PUBLISH", "X-WR-CALNAME:\(escapeText("Bench doses"))"]
    var count = 0
    for p in protocols {
        guard p.active, p.schedule.kind != .asNeeded else { continue }
        if let ended = p.endedAt, ended < nowMs { continue }
        for at in protocolDoseTimesBetween(p, nowMs, until) {
            if count >= MAX_EVENTS { break }
            count += 1
            let trimmed = p.name.trimmingCharacters(in: .whitespaces)
            let label = settings.showCompound ? (!trimmed.isEmpty ? trimmed : (byId[p.peptideId]?.name ?? "Dose")) : "Bench"
            let summary = settings.showCompound ? "\(label) \(doseLabel(scheduledDoseMcg(p, at), byId[p.peptideId]))" : "Bench: dose due"
            let trigger = settings.leadMinutes > 0 ? "-PT\(jsNumberString(jsRound(settings.leadMinutes)))M" : "PT0S"
            lines += ["BEGIN:VEVENT", "UID:\(p.id)-\(jsNumberString(at))@bench.app", "DTSTAMP:\(utcStamp(nowMs))",
                      "SEQUENCE:\(seq)", "DTSTART:\(floating(at))", "DURATION:PT\(EVENT_MINUTES)M",
                      "SUMMARY:\(escapeText(summary))", "TRANSP:TRANSPARENT", "BEGIN:VALARM", "ACTION:DISPLAY",
                      "TRIGGER:\(trigger)", "DESCRIPTION:\(escapeText(summary))", "END:VALARM", "END:VEVENT"]
        }
    }
    lines.append("END:VCALENDAR")
    return lines.map(foldLine).joined(separator: "\r\n") + "\r\n"
}

/// How many doses a file would carry.
public func calendarEventCount(_ ics: String) -> Int { ics.components(separatedBy: "BEGIN:VEVENT").count - 1 }
