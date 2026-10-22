import Foundation

// Doses that were due and never logged, for the Log to show and fix. Built on
// `dayBreakdown`, so a dose counts as missed exactly when the week strip says so.

public struct MissedDose: Equatable, Sendable, Identifiable {
    public var protocolId: String
    public var peptideId: String
    /// When it was scheduled.
    public var at: Millis
    public var doseMcg: Double
    public var id: String { "\(protocolId)@\(jsNumberString(at))" }
}

/// Every missed dose from `fromMs` up to now, by local day, newest day first and
/// in time order within a day. Today counts only what is already past.
public func missedDoses(_ protocols: [DoseProtocol], _ logs: [DoseLog], fromMs: Millis, nowMs: Millis) -> [(day: Millis, doses: [MissedDose])] {
    var out: [(day: Millis, doses: [MissedDose])] = []
    var day = startOfLocalDay(nowMs)
    let first = startOfLocalDay(fromMs)
    let byId = Dictionary(protocols.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
    while day >= first {
        let missed = dayBreakdown(protocols, logs, day, nowMs: nowMs).protocols.flatMap { pd in
            pd.slots.filter { $0.slot == .missed }.map { s in
                MissedDose(protocolId: pd.protocolId, peptideId: pd.peptideId, at: s.at,
                           doseMcg: byId[pd.protocolId].map { scheduledDoseMcg($0, s.at) } ?? 0)
            }
        }.stableSorted { $0.at < $1.at }
        if !missed.isEmpty { out.append((day, missed)) }
        day = addLocalDays(day, -1)
    }
    return out
}

public extension AppData {
    /// A forgotten dose, recorded at the time it was scheduled: taken, from the
    /// vial and at the site it would have used then, or skipped on purpose.
    @discardableResult
    mutating func logMissed(_ m: MissedDose, skipped: Bool = false) -> String? {
        if skipped {
            guard let p = protocols.first(where: { $0.id == m.protocolId }) else { return nil }
            return addLog(DoseLog(id: "", profileId: "", protocolId: p.id, peptideId: p.peptideId, at: m.at,
                                  doseMcg: m.doseMcg, route: p.route, skipped: true))
        }
        return logFromReminder(protocolId: m.protocolId, doseAt: m.at, now: m.at)
    }
}
