import Foundation

// How long a protocol has been going: days since the start, days actually on
// (calendar days less any recorded pause), and where it sits in a weeks-on /
// weeks-off cycle. Worked from the start date, schedule and recorded pauses,
// so nothing new is stored. The cycle follows the calendar from the start, the
// same as `isOnCycle`, so pausing does not move it.

public enum CyclePhase: Equatable, Sendable { case on, off, finished }

public struct CycleProgress: Equatable, Sendable {
    public var phase: CyclePhase
    /// 1-based week within the current on or off stretch.
    public var week: Int
    /// Weeks in the current stretch.
    public var weeks: Int
    /// The day the next stretch starts; nil for a course that has finished.
    public var changesAt: Millis?
    /// Weeks off that follow an on stretch; 0 for a course.
    public var weeksOff: Int
}

public struct RunProgress: Equatable, Sendable {
    /// 1 on the start day.
    public var day: Int
    /// Calendar days since the start that were not inside a recorded pause.
    public var daysOn: Int
    public var daysPaused: Int
    public var cycle: CycleProgress?
}

/// Nil before the start, or once the protocol has an end date in the past.
public func runProgress(_ p: DoseProtocol, _ now: Millis) -> RunProgress? {
    guard hasStarted(p, now) else { return nil }
    let start = startOfLocalDay(p.startedAt)
    let today = startOfLocalDay(now)
    if let end = p.endedAt, startOfLocalDay(end) < today { return nil }
    let day = Int(daysBetween(start, today)) + 1

    // Whole days of pause that fall between the start and now, windows merged so overlaps count once.
    var paused = 0
    var cursor = start
    for w in p.pauses.sorted(by: { $0.from < $1.from }) {
        let from = max(startOfLocalDay(w.from), start, cursor)
        let until = min(w.until.map(startOfLocalDay) ?? today + DAY_MS, today + DAY_MS)
        if until > from { paused += Int(jsRound((until - from) / DAY_MS)); cursor = until }
    }
    paused = min(paused, day)

    return RunProgress(day: day, daysOn: day - paused, daysPaused: paused, cycle: cycleProgress(p.schedule, start, today))
}

func cycleProgress(_ schedule: Schedule, _ start: Millis, _ today: Millis) -> CycleProgress? {
    let on = schedule.cycleWeeksOn ?? 0
    let off = schedule.cycleWeeksOff ?? 0
    guard on > 0 else { return nil }
    let days = daysBetween(start, today)
    let onDays = on * 7
    let onWeeks = Int(on.rounded(.up)), offWeeks = Int(max(0, off).rounded(.up))
    if off <= 0 {
        if days >= onDays { return CycleProgress(phase: .finished, week: onWeeks, weeks: onWeeks, changesAt: nil, weeksOff: 0) }
        return CycleProgress(phase: .on, week: Int(days / 7) + 1, weeks: onWeeks, changesAt: start + onDays * DAY_MS, weeksOff: 0)
    }
    let period = (on + off) * 7
    let into = days.truncatingRemainder(dividingBy: period)
    let cycleStart = start + (days - into) * DAY_MS
    if into < onDays {
        return CycleProgress(phase: .on, week: Int(into / 7) + 1, weeks: onWeeks, changesAt: cycleStart + onDays * DAY_MS, weeksOff: offWeeks)
    }
    return CycleProgress(phase: .off, week: Int((into - onDays) / 7) + 1, weeks: offWeeks, changesAt: cycleStart + period * DAY_MS, weeksOff: offWeeks)
}

/// "3 weeks 5 days" for the run so far; days alone under a week.
public func runLengthParts(_ days: Int) -> (weeks: Int, days: Int) { (days / 7, days % 7) }
