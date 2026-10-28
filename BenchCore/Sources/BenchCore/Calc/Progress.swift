import Foundation

// Port of src/lib/calc/progress.ts. Day-level progress and streaks, kept honest:
// a rest day is neither a win nor a miss, a skip leaves the day rather than
// staying owed, and an unfinished today never breaks a streak.

public struct DayProgress: Equatable, Sendable {
    public var day: Millis
    public var expected: Int
    public var taken: Int
    public var skipped: Int
    /// Scheduled less skipped.
    public var owed: Int
    /// taken / owed, or 1 when nothing is owed.
    public var fraction: Double
    public var restDay: Bool
    public var complete: Bool
}

/// What one protocol asked for on a day, and what answered it.
public struct ProtocolDay: Equatable, Sendable {
    public enum Slot: Equatable, Sendable {
        case taken(DoseLog)
        case skipped(DoseLog)
        /// Its time has passed with nothing logged.
        case missed
        /// Still ahead, later today.
        case due
    }
    public var protocolId: String
    public var peptideId: String
    /// Scheduled times, each with what became of it, in time order.
    public var slots: [(at: Millis, slot: Slot)]

    public static func == (a: ProtocolDay, b: ProtocolDay) -> Bool {
        a.protocolId == b.protocolId && a.peptideId == b.peptideId
            && a.slots.map(\.at) == b.slots.map(\.at) && a.slots.map(\.slot) == b.slots.map(\.slot)
    }
}

/// A day dose by dose: the same crediting `dayProgress` counts, laid out per
/// protocol, plus whatever was logged that no protocol asked for.
public struct DayBreakdown: Equatable, Sendable {
    public var day: Millis
    public var protocols: [ProtocolDay]
    public var unplanned: [DoseLog]
}

/// Each log is credited to the protocol it names, else by compound, and no
/// protocol past what it asked for. Within a protocol, logs answer the nearest
/// scheduled time; times left over are missed once passed, due before.
///
/// With `earlyHours`, a log in that many hours after midnight counts toward the
/// day before when the scheduled time it is nearest to was that night.
public func dayBreakdown(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ dayMs: Millis, nowMs: Millis = nowMillis(), earlyHours: Double = 0) -> DayBreakdown {
    let day = startOfLocalDay(dayMs)
    let end = endOfLocalDay(dayMs)
    let active = protocols.filter(\.active)
    let times = active.map { protocolDoseTimesBetween($0, day, end).sorted() }
    let onDay = logs.filter { $0.at >= day && $0.at <= end + earlyHours * HOUR_MS && creditDay($0, active, earlyHours: earlyHours) == day }
    var credited: [[DoseLog]] = Array(repeating: [], count: active.count)
    var claimed = Set<Int>()
    func room(_ i: Int) -> Int { times[i].count - credited[i].count }
    for (idx, l) in onDay.enumerated() {
        if let i = active.firstIndex(where: { l.protocolId == $0.id }), room(i) > 0 { credited[i].append(l); claimed.insert(idx) }
    }
    for (idx, l) in onDay.enumerated() where !claimed.contains(idx) {
        if let i = active.indices.first(where: { active[$0].peptideId == l.peptideId && room($0) > 0 }) { credited[i].append(l); claimed.insert(idx) }
    }
    let protocolDays = active.indices.compactMap { i -> ProtocolDay? in
        guard !times[i].isEmpty else { return nil }
        var open = Array(times[i].indices)
        var answered: [Int: DoseLog] = [:]
        for l in credited[i].stableSorted(by: { $0.at < $1.at }) {
            guard let best = open.min(by: { abs(times[i][$0] - l.at) < abs(times[i][$1] - l.at) }) else { break }
            answered[best] = l
            open.removeAll { $0 == best }
        }
        return ProtocolDay(protocolId: active[i].id, peptideId: active[i].peptideId, slots: times[i].indices.map { k in
            let at = times[i][k]
            if let l = answered[k] { return (at, l.isSkipped ? .skipped(l) : .taken(l)) }
            return (at, at <= nowMs ? .missed : .due)
        })
    }
    let unplanned = onDay.indices.filter { !claimed.contains($0) }.map { onDay[$0] }.stableSorted { $0.at < $1.at }
    return DayBreakdown(day: day, protocols: protocolDays, unplanned: unplanned)
}

/// The day a log counts toward: its own, unless it falls in the early hours and
/// the scheduled time it is nearest to was the night before.
func creditDay(_ l: DoseLog, _ active: [DoseProtocol], earlyHours: Double) -> Millis {
    let own = startOfLocalDay(l.at)
    guard earlyHours > 0, l.at < own + earlyHours * HOUR_MS,
          let p = active.first(where: { $0.id == l.protocolId }) ?? active.first(where: { $0.peptideId == l.peptideId }),
          let nearest = protocolDoseTimesBetween(p, l.at - DAY_MS, l.at + DAY_MS).min(by: { abs($0 - l.at) < abs($1 - l.at) }),
          nearest < own else { return own }
    return startOfLocalDay(nearest)
}

/// The earlier day an early-morning dose counts toward, or nil when it counts for its own.
public func earlyCreditDay(_ l: DoseLog, _ protocols: [DoseProtocol], earlyHours: Double) -> Millis? {
    let day = creditDay(l, protocols.filter(\.active), earlyHours: earlyHours)
    return day == startOfLocalDay(l.at) ? nil : day
}

/// How a single day went, counted from the same crediting as `dayBreakdown`.
public func dayProgress(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ dayMs: Millis, earlyHours: Double = 0) -> DayProgress {
    let breakdown = dayBreakdown(protocols, logs, dayMs, nowMs: .infinity, earlyHours: earlyHours)
    let slots = breakdown.protocols.flatMap { $0.slots.map(\.slot) }
    let expected = slots.count
    let t = slots.filter { if case .taken = $0 { true } else { false } }.count
    let s = slots.filter { if case .skipped = $0 { true } else { false } }.count
    let owed = expected - s
    return DayProgress(day: breakdown.day, expected: expected, taken: t, skipped: s, owed: owed,
                       fraction: owed == 0 ? 1 : min(1, Double(t) / Double(owed)),
                       restDay: expected == 0, complete: t >= owed)
}

public func todayProgress(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ nowMs: Millis, earlyHours: Double = 0) -> DayProgress {
    dayProgress(protocols, logs, nowMs, earlyHours: earlyHours)
}

/// Consecutive days where every scheduled dose was taken or skipped.
public func currentStreak(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ nowMs: Millis, maxLookbackDays: Int = 400, earlyHours: Double = 0) -> Int {
    var streak = 0
    var cursor = startOfLocalDay(nowMs)
    for i in 0..<maxLookbackDays {
        let d = dayProgress(protocols, logs, cursor, earlyHours: earlyHours)
        if i == 0 && !d.complete { cursor = addLocalDays(cursor, -1); continue }
        if !d.complete { break }
        if d.owed > 0 { streak += 1 }
        cursor = addLocalDays(cursor, -1)
    }
    return streak
}

/// The last N days, oldest first.
public func recentDays(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ nowMs: Millis, days: Int = 7, earlyHours: Double = 0) -> [DayProgress] {
    stride(from: days - 1, through: 0, by: -1).map { dayProgress(protocols, logs, addLocalDays(nowMs, Double(-$0)), earlyHours: earlyHours) }
}

public struct WeekExposure: Equatable, Sendable {
    public var weekStart: Millis
    public var totalMcg: Double
    public var doses: Int
}

/// Total mass taken per trailing seven days, oldest first.
public func weeklyExposure(_ logs: [DoseLog], _ nowMs: Millis, weeks: Int = 8, peptideId: String? = nil) -> [WeekExposure] {
    let relevant = logs.filter { !$0.isSkipped && (peptideId == nil || $0.peptideId == peptideId) }
    return stride(from: weeks - 1, through: 0, by: -1).map { i in
        let anchor = addLocalDays(nowMs, Double(-i * 7))
        let start = startOfLocalDay(addLocalDays(anchor, -6))
        let end = endOfLocalDay(anchor)
        let inWeek = relevant.filter { $0.at >= start && $0.at <= end }
        return WeekExposure(weekStart: start, totalMcg: inWeek.reduce(0) { $0 + $1.doseMcg }, doses: inWeek.count)
    }
}

public struct SteadyStateProgress: Equatable, Sendable {
    public var fraction: Double
    public var hoursElapsed: Double
    public var hoursNeeded: Double
}

/// How far along the climb to steady state (five half-lives) a compound is.
public func steadyStateProgress(_ halfLifeHours: Double?, _ firstDoseAt: Millis?, _ nowMs: Millis) -> SteadyStateProgress? {
    guard let h = halfLifeHours, h > 0, let first = firstDoseAt else { return nil }
    let needed = h * 5
    let elapsed = max(0, (nowMs - first) / HOUR_MS)
    return SteadyStateProgress(fraction: min(1, elapsed / needed), hoursElapsed: elapsed, hoursNeeded: needed)
}
