import Foundation

// Port of src/lib/calc/reminders.ts. Which reminders should exist right now: a
// pure function of plan, log and settings. The platform adapter cancels every
// pending notification and re-arms this whole list; never reconcile one by one.

/// How far ahead alarms are placed.
public let REMINDER_HORIZON_DAYS: Double = 14

public struct Reminder: Equatable, Sendable, Identifiable {
    /// Derived, stable within one re-arm.
    public var id: Int
    /// The readable form of the id.
    public var key: String
    /// When it fires, already offset by the lead time.
    public var at: Millis
    /// When the dose itself is due.
    public var doseAt: Millis
    public var protocolId: String
    public var title: String
    public var body: String
}

/// FNV-1a over UTF-16 code units, 31 bits, as the original computes it.
public func reminderId(_ key: String) -> Int {
    var h: UInt32 = 0x811c9dc5
    for unit in key.utf16 {
        h ^= UInt32(unit)
        h = h &* 0x01000193
    }
    return Int((h >> 1) % 2_000_000_000)
}

/// Discreet by default: "Bench" / "A dose is due." names nothing on a lock screen.
private func reminderText(_ p: DoseProtocol, _ name: String?, _ doseMcg: Double, _ settings: RemindersSettings) -> (String, String) {
    guard settings.showCompound else { return ("Bench", "A dose is due.") }
    let trimmed = p.name.trimmingCharacters(in: .whitespaces)
    let label = !trimmed.isEmpty ? trimmed : (name ?? "Dose")
    return (label, "\(formatDose(doseMcg)) due.")
}

/// Every reminder that should be armed, soonest first. Goes through
/// `unloggedDoseTimes`, so a notification and the Today screen cannot disagree.
public func remindersFor(protocols: [DoseProtocol], logs: [DoseLog], peptides: [Peptide], settings: RemindersSettings,
                         nowMs: Millis, horizonDays: Double = REMINDER_HORIZON_DAYS) -> [Reminder] {
    guard settings.enabled else { return [] }
    let until = nowMs + horizonDays * DAY_MS
    let lead = max(0, settings.leadMinutes) * 60_000
    let names = Dictionary(peptides.map { ($0.id, $0.name) }, uniquingKeysWith: { a, _ in a })
    var out: [Reminder] = []
    for p in protocols {
        guard p.active, p.schedule.kind != .asNeeded else { continue }
        if let ended = p.endedAt, ended < nowMs { continue }
        let mine = logsForProtocol(p, logs)
        for doseAt in unloggedDoseTimes(p, mine, nowMs - lead, until) {
            let at = doseAt - lead
            if at <= nowMs { continue }
            let key = "\(p.id):\(jsNumberString(doseAt))"
            let (title, body) = reminderText(p, names[p.peptideId], scheduledDoseMcg(p, doseAt), settings)
            out.append(Reminder(id: reminderId(key), key: key, at: at, doseAt: doseAt, protocolId: p.id, title: title, body: body))
        }
    }
    return out.stableSorted { $0.at != $1.at ? $0.at < $1.at : $0.key.localizedCompare($1.key) == .orderedAscending }
}
