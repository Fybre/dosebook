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

/// How a single day went. Each log is credited to the protocol it names, else
/// by compound, and no protocol past what it asked for.
public func dayProgress(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ dayMs: Millis) -> DayProgress {
    let day = startOfLocalDay(dayMs)
    let end = endOfLocalDay(dayMs)
    let active = protocols.filter(\.active)
    let slots = active.map { protocolDoseTimesBetween($0, day, end).count }
    let expected = slots.reduce(0, +)
    let onDay = logs.filter { $0.at >= day && $0.at <= end }
    var taken = Array(repeating: 0, count: active.count)
    var skipped = Array(repeating: 0, count: active.count)
    var claimed = Set<Int>()
    func room(_ i: Int) -> Int { slots[i] - taken[i] - skipped[i] }
    func credit(_ i: Int, _ l: DoseLog, _ idx: Int) {
        if l.isSkipped { skipped[i] += 1 } else { taken[i] += 1 }
        claimed.insert(idx)
    }
    for (idx, l) in onDay.enumerated() {
        if let i = active.firstIndex(where: { l.protocolId == $0.id }), room(i) > 0 { credit(i, l, idx) }
    }
    for (idx, l) in onDay.enumerated() where !claimed.contains(idx) {
        if let i = active.indices.first(where: { active[$0].peptideId == l.peptideId && room($0) > 0 }) { credit(i, l, idx) }
    }
    let t = taken.reduce(0, +), s = skipped.reduce(0, +)
    let owed = expected - s
    return DayProgress(day: day, expected: expected, taken: t, skipped: s, owed: owed,
                       fraction: owed == 0 ? 1 : min(1, Double(t) / Double(owed)),
                       restDay: expected == 0, complete: t >= owed)
}

public func todayProgress(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ nowMs: Millis) -> DayProgress {
    dayProgress(protocols, logs, nowMs)
}

/// Consecutive days where every scheduled dose was taken or skipped.
public func currentStreak(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ nowMs: Millis, maxLookbackDays: Int = 400) -> Int {
    var streak = 0
    var cursor = startOfLocalDay(nowMs)
    for i in 0..<maxLookbackDays {
        let d = dayProgress(protocols, logs, cursor)
        if i == 0 && !d.complete { cursor = addLocalDays(cursor, -1); continue }
        if !d.complete { break }
        if d.owed > 0 { streak += 1 }
        cursor = addLocalDays(cursor, -1)
    }
    return streak
}

/// The last N days, oldest first.
public func recentDays(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ nowMs: Millis, days: Int = 7) -> [DayProgress] {
    stride(from: days - 1, through: 0, by: -1).map { dayProgress(protocols, logs, addLocalDays(nowMs, Double(-$0))) }
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
