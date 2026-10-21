import Foundation

// Port of src/lib/calc/schedule.ts.
//
// Turning a protocol's schedule into concrete dose times. All reasoning happens
// in local time, because "every Monday at 8am" means the user's Monday. Dates go
// through the calendar rather than adding fixed millisecond offsets, so
// daylight-saving shifts keep a dose at the same wall-clock time.

public enum LocalTime {
    /// The calendar all local-time maths uses. Tests bind a fixed time zone.
    @TaskLocal public static var calendar: Calendar = .autoupdatingCurrent
}

public let DAY_MS: Double = 86_400_000
public let HOUR_MS: Double = 3_600_000

/// Midnight local time on the day containing `ms`.
public func startOfLocalDay(_ ms: Millis) -> Millis {
    LocalTime.calendar.startOfDay(for: Date(millis: ms)).millis
}

/// The last instant of the local day containing `ms`.
public func endOfLocalDay(_ ms: Millis) -> Millis {
    let cal = LocalTime.calendar
    let start = cal.startOfDay(for: Date(millis: ms))
    let next = cal.date(byAdding: .day, value: 1, to: start) ?? start.addingTimeInterval(86_400)
    return next.millis - 1
}

/// Add whole days in local time, keeping the wall-clock time across DST.
public func addLocalDays(_ ms: Millis, _ days: Double) -> Millis {
    let cal = LocalTime.calendar
    let d = Date(millis: ms)
    let whole = Int(days.rounded(.towardZero))
    return (cal.date(byAdding: .day, value: whole, to: d, wrappingComponents: false) ?? d).millis
}

/// Whole local days between two instants, ignoring time of day.
public func daysBetween(_ fromMs: Millis, _ toMs: Millis) -> Double {
    jsRound((startOfLocalDay(toMs) - startOfLocalDay(fromMs)) / DAY_MS)
}

/// Local weekday, 0 = Sunday … 6 = Saturday (JS `getDay`).
public func localWeekday(_ ms: Millis) -> Int {
    LocalTime.calendar.component(.weekday, from: Date(millis: ms)) - 1
}

private func parseHM(_ raw: String) -> (Double?, Double?) {
    let parts = raw.split(separator: ":", omittingEmptySubsequences: false).map { jsNumber(String($0)) }
    let h = parts.count > 0 ? parts[0] : nil
    let m = parts.count > 1 ? parts[1] : nil
    return (h, m)
}

/// JS `Number(s)` where only finite results matter: trimmed, empty is 0, unreadable is nil.
func jsNumber(_ s: String) -> Double? {
    let t = s.trimmingCharacters(in: .whitespacesAndNewlines)
    if t.isEmpty { return 0 }
    guard let d = Double(t), d.isFinite else { return nil }
    return d
}

/// Apply "HH:MM" to a day, defaulting to 09:00 when unset.
public func atTimeOfDay(_ dayMs: Millis, _ timeOfDay: String? = nil) -> Millis {
    let (h, m) = parseHM(timeOfDay ?? "09:00")
    let hour = h ?? 9
    let minute = m ?? 0
    let cal = LocalTime.calendar
    let start = cal.startOfDay(for: Date(millis: dayMs))
    if (0...23).contains(Int(hour)), (0...59).contains(Int(minute)),
       let d = cal.date(bySettingHour: Int(hour), minute: Int(minute), second: 0, of: start,
                        matchingPolicy: .nextTimePreservingSmallerComponents, repeatedTimePolicy: .first, direction: .forward) {
        return d.millis
    }
    // Out-of-range parts roll over, as Date.setHours does.
    let shifted = cal.date(byAdding: DateComponents(hour: Int(hour), minute: Int(minute)), to: start) ?? start
    return shifted.millis
}

/// "7:5" and "07:05" are the same time. Anything unreadable is nine o'clock.
func normalizeTime(_ raw: String) -> String {
    let (h, m) = parseHM(raw)
    let hh = h.map { min(23, max(0, $0.rounded(.towardZero))) } ?? 9
    let mm = m.map { min(59, max(0, $0.rounded(.towardZero))) } ?? 0
    return String(format: "%02d:%02d", Int(hh), Int(mm))
}

/// Whether a list of time fields is finished being typed.
public func everyTimeFilled(_ times: [String]) -> Bool {
    !times.isEmpty && times.allSatisfy { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
}

/// Every time a dose day carries, in order, deduplicated. The one place
/// `timesOfDay` and `timeOfDay` are reconciled; nothing else reads either.
public func scheduleTimes(_ schedule: Schedule) -> [String] {
    let listed = (schedule.timesOfDay ?? []).filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
    let raw = listed.isEmpty ? [schedule.timeOfDay ?? "09:00"] : listed
    return Array(Set(raw.map(normalizeTime))).sorted()
}

/// How many injections a dose day asks for. Never zero.
public func dosesPerDoseDay(_ schedule: Schedule) -> Int {
    schedule.kind == .asNeeded ? 1 : scheduleTimes(schedule).count
}

/// Whether a cycling protocol is in an "on" week. No cycle means always on.
public func isOnCycle(_ schedule: Schedule, _ startedAt: Millis, _ dayMs: Millis) -> Bool {
    let on = schedule.cycleWeeksOn ?? 0
    let off = schedule.cycleWeeksOff ?? 0
    if on <= 0 || off <= 0 { return true }
    let days = daysBetween(startedAt, dayMs)
    if days < 0 { return false }
    let period = (on + off) * 7
    return days.truncatingRemainder(dividingBy: period) < on * 7
}

/// Whether a dose is scheduled on a given local day.
public func isDoseDay(_ schedule: Schedule, _ startedAt: Millis, _ dayMs: Millis) -> Bool {
    let day = startOfLocalDay(dayMs)
    if day < startOfLocalDay(startedAt) { return false }
    if !isOnCycle(schedule, startedAt, day) { return false }
    switch schedule.kind {
    case .daily:
        return true
    case .intervalDays:
        let n = schedule.intervalDays ?? 1
        if n < 1 { return false }
        return daysBetween(startedAt, day).truncatingRemainder(dividingBy: n) == 0
    case .daysOfWeek:
        return (schedule.daysOfWeek ?? []).contains(localWeekday(day))
    default:
        return false
    }
}

/// Scheduled dose times within a window, inclusive of both ends.
public func doseTimesBetween(_ schedule: Schedule, _ startedAt: Millis, _ fromMs: Millis, _ toMs: Millis,
                             _ endedAt: Millis? = nil) -> [Millis] {
    if schedule.kind == .asNeeded { return [] }
    var out: [Millis] = []
    let limit = endedAt ?? .infinity
    var day = startOfLocalDay(max(fromMs, startedAt))
    let last = startOfLocalDay(toMs)
    var guardCount = 0
    let times = scheduleTimes(schedule)
    while day <= last && guardCount < 4000 {
        guardCount += 1
        if isDoseDay(schedule, startedAt, day) {
            for time in times {
                let t = atTimeOfDay(day, time)
                if t >= fromMs && t <= toMs && t <= limit { out.append(t) }
            }
        }
        day = addLocalDays(day, 1)
    }
    return out
}

/// The next scheduled dose at or after `fromMs`.
public func nextDoseTime(_ schedule: Schedule, _ startedAt: Millis, _ fromMs: Millis, _ endedAt: Millis? = nil) -> Millis? {
    if schedule.kind == .asNeeded { return nil }
    let times = scheduleTimes(schedule)
    var day = startOfLocalDay(max(fromMs, startedAt))
    for _ in 0..<400 {
        if isDoseDay(schedule, startedAt, day) {
            for time in times {
                let t = atTimeOfDay(day, time)
                if t >= fromMs && (endedAt == nil || t <= endedAt!) { return t }
            }
        }
        day = addLocalDays(day, 1)
    }
    return nil
}

/// The most recent scheduled dose at or before `fromMs`.
public func previousDoseTime(_ schedule: Schedule, _ startedAt: Millis, _ fromMs: Millis) -> Millis? {
    if schedule.kind == .asNeeded { return nil }
    let times = Array(scheduleTimes(schedule).reversed())
    var day = startOfLocalDay(fromMs)
    let floor = startOfLocalDay(startedAt)
    var i = 0
    while i < 400 && day >= floor {
        if isDoseDay(schedule, startedAt, day) {
            for time in times {
                let t = atTimeOfDay(day, time)
                if t <= fromMs { return t }
            }
        }
        day = addLocalDays(day, -1)
        i += 1
    }
    return nil
}

/// Scheduled injections per week, for burn-rate and inventory maths.
public func dosesPerWeek(_ schedule: Schedule) -> Double {
    var base: Double
    switch schedule.kind {
    case .daily: base = 7
    case .intervalDays: base = 7 / max(1, schedule.intervalDays ?? 1)
    case .daysOfWeek: base = Double((schedule.daysOfWeek ?? []).count)
    default: return 0
    }
    base *= Double(scheduleTimes(schedule).count)
    let on = schedule.cycleWeeksOn ?? 0
    let off = schedule.cycleWeeksOff ?? 0
    if on > 0 && off > 0 { base *= on / (on + off) }
    return base
}

// MARK: - Titration

/// Cumulative week at which each titration step begins.
public func titrationStepStartWeeks(_ steps: [TitrationStep]) -> [Double] {
    var starts: [Double] = []
    var acc = 0.0
    for s in steps {
        starts.append(acc)
        acc += max(0, s.weeks)
    }
    return starts
}

public func titrationTotalWeeks(_ steps: [TitrationStep]) -> Double {
    steps.reduce(0) { $0 + max(0, $1.weeks) }
}

public struct TitrationPosition: Equatable, Sendable {
    public var index: Int
    public var step: TitrationStep
}

/// Which titration step applies. Past the end, the final step holds indefinitely.
public func titrationStepAt(_ steps: [TitrationStep], _ startedAt: Millis, _ atMs: Millis) -> TitrationPosition? {
    guard !steps.isEmpty else { return nil }
    let days = daysBetween(startedAt, atMs)
    if days < 0 { return nil }
    let week = (days / 7).rounded(.down)
    var acc = 0.0
    for (i, s) in steps.enumerated() {
        acc += max(0, s.weeks)
        if week < acc { return TitrationPosition(index: i, step: s) }
    }
    return TitrationPosition(index: steps.count - 1, step: steps[steps.count - 1])
}

// MARK: - Phases

/// A phase placed on the calendar.
public struct PhaseSpan: Equatable, Sendable {
    public var index: Int
    public var phase: ProtocolPhase
    /// The frequency in force, the phase's own merged over the protocol's.
    public var schedule: Schedule
    /// What interval and cycle maths count from: each phase counts from its own beginning.
    public var anchor: Millis
    public var from: Millis
    /// Last instant covered; infinity for the final phase, which runs on.
    public var to: Millis
}

/// The phase list governing a protocol, or nil. An auto-advancing titration is
/// read as a phase list with no frequency of its own.
public func protocolPhases(_ p: DoseProtocol) -> [ProtocolPhase]? {
    if let phases = p.phases, !phases.isEmpty { return phases }
    if let t = p.titration, !t.isEmpty, p.titrationAutoAdvance {
        return t.map { ProtocolPhase(step: $0.step, doseMcg: $0.doseMcg, weeks: $0.weeks, note: $0.note) }
    }
    return nil
}

/// A band overrides only what it names (`{ ...protocol, ...band }`).
public func bandSchedule(_ base: Schedule, _ band: Schedule?) -> Schedule {
    guard let band else { return base }
    return Schedule(
        kind: band.kind,
        intervalDays: band.intervalDays ?? base.intervalDays,
        daysOfWeek: band.daysOfWeek ?? base.daysOfWeek,
        timeOfDay: band.timeOfDay ?? base.timeOfDay,
        timesOfDay: band.timesOfDay ?? base.timesOfDay,
        cycleWeeksOn: band.cycleWeeksOn ?? base.cycleWeeksOn,
        cycleWeeksOff: band.cycleWeeksOff ?? base.cycleWeeksOff
    )
}

/// Phases resolved onto the calendar. Without phases, one span covering all time.
public func phaseSpans(_ p: DoseProtocol) -> [PhaseSpan] {
    guard let phases = protocolPhases(p) else {
        return [PhaseSpan(index: 0, phase: ProtocolPhase(step: 1, doseMcg: p.doseMcg, weeks: 0),
                          schedule: p.schedule, anchor: p.startedAt, from: p.startedAt, to: .infinity)]
    }
    let dayZero = startOfLocalDay(p.startedAt)
    var spans: [PhaseSpan] = []
    var weeksSoFar = 0.0
    for (i, phase) in phases.enumerated() {
        let last = i == phases.count - 1
        let anchor = i == 0 ? p.startedAt : addLocalDays(dayZero, weeksSoFar * 7)
        weeksSoFar += max(0, phase.weeks)
        let to = last ? Double.infinity : addLocalDays(dayZero, weeksSoFar * 7) - 1
        spans.append(PhaseSpan(index: i, phase: phase, schedule: bandSchedule(p.schedule, phase.schedule),
                               anchor: anchor, from: anchor, to: to))
    }
    return spans
}

/// Whether a protocol has begun, by the local day.
public func hasStarted(_ p: DoseProtocol, _ atMs: Millis) -> Bool {
    atMs >= startOfLocalDay(p.startedAt)
}

/// The phase in force at a moment; before the start, the first phase.
public func phaseSpanAt(_ p: DoseProtocol, _ atMs: Millis) -> PhaseSpan? {
    let spans = phaseSpans(p)
    if !hasStarted(p, atMs) { return spans.first }
    for span in spans where atMs <= span.to { return span }
    return spans.last
}

/// Scheduled dose times for a protocol, phase by phase, sorted.
public func protocolDoseTimesBetween(_ p: DoseProtocol, _ fromMs: Millis, _ toMs: Millis) -> [Millis] {
    var out: [Millis] = []
    for span in phaseSpans(p) {
        let lo = max(fromMs, span.from)
        let hi = min(toMs, span.to)
        if lo > hi { continue }
        let limit = min(p.endedAt ?? .infinity, span.to)
        out.append(contentsOf: doseTimesBetween(span.schedule, span.anchor, lo, hi, limit.isFinite ? limit : nil))
    }
    return out
}

/// The next scheduled dose for a protocol at or after `fromMs`.
public func protocolNextDoseTime(_ p: DoseProtocol, _ fromMs: Millis) -> Millis? {
    for span in phaseSpans(p) {
        if span.to < fromMs { continue }
        let limit = min(p.endedAt ?? .infinity, span.to)
        if limit < fromMs { continue }
        if let t = nextDoseTime(span.schedule, span.anchor, max(fromMs, span.from), limit.isFinite ? limit : nil) {
            return t
        }
    }
    return nil
}

/// The most recent scheduled dose for a protocol at or before `fromMs`.
public func protocolPreviousDoseTime(_ p: DoseProtocol, _ fromMs: Millis) -> Millis? {
    let spans = phaseSpans(p)
    for span in spans.reversed() {
        if span.from > fromMs { continue }
        if let t = previousDoseTime(span.schedule, span.anchor, min(fromMs, span.to)), t >= startOfLocalDay(span.from) {
            return t
        }
    }
    return nil
}

/// Doses per week as the protocol stands now (the current phase, not an average).
public func protocolDosesPerWeek(_ p: DoseProtocol, _ atMs: Millis) -> Double {
    dosesPerWeek(phaseSpanAt(p, atMs)?.schedule ?? p.schedule)
}

/// The dose a protocol calls for on a dose day, before it is split across times.
public func scheduledDailyMcg(_ p: DoseProtocol, _ atMs: Millis) -> Double {
    if let phases = p.phases, !phases.isEmpty, let span = phaseSpanAt(p, atMs) {
        return span.phase.doseMcg
    }
    if let t = p.titration, !t.isEmpty, p.titrationAutoAdvance, let current = titrationStepAt(t, p.startedAt, atMs) {
        return current.step.doseMcg
    }
    return p.doseMcg
}

/// The dose for one injection: the day's dose divided by the times that day carries.
public func scheduledDoseMcg(_ p: DoseProtocol, _ atMs: Millis) -> Double {
    let span = phaseSpanAt(p, atMs)
    let per = dosesPerDoseDay(span?.schedule ?? p.schedule)
    let daily = scheduledDailyMcg(p, atMs)
    return per > 1 ? daily / Double(per) : daily
}

// MARK: - Adherence

public struct AdherenceWindow: Equatable, Sendable {
    public var expected: Int
    public var taken: Int
    public var skipped: Int
    public var missed: Int
    /// Taken as a share of expected. 1 when nothing was expected.
    public var rate: Double
}

/// Anything with a time and an optional skip flag.
public protocol LogLike {
    var at: Millis { get }
    var isSkipped: Bool { get }
}

extension DoseLog: LogLike {}

public struct LogStamp: LogLike, Sendable {
    public var at: Millis
    public var skipped: Bool?
    public init(at: Millis, skipped: Bool? = nil) { self.at = at; self.skipped = skipped }
    public var isSkipped: Bool { skipped == true }
}

/// The doses belonging to a protocol. Use this rather than filtering by hand.
public func logsForProtocol(_ p: DoseProtocol, _ logs: [DoseLog]) -> [DoseLog] {
    logs.filter { $0.protocolId == p.id || $0.peptideId == p.peptideId }
}

/// Compare scheduled doses against what was logged. `logs` must already be
/// narrowed to this protocol via `logsForProtocol`.
///
/// Each scheduled dose takes the *earliest* log it can still reach, not the
/// nearest; nearest steals the next dose's log and cascades into false misses.
public func adherence<L: LogLike>(_ p: DoseProtocol, _ logs: [L], _ fromMs: Millis, _ toMs: Millis,
                                  toleranceHours: Double = 36) -> AdherenceWindow {
    let scheduled = protocolDoseTimesBetween(p, fromMs, toMs)
    let tolerance = toleranceHours * HOUR_MS
    let order = logs.enumerated()
        .filter { $0.element.at >= fromMs - tolerance && $0.element.at <= toMs + tolerance }
        .map { (at: $0.element.at, skipped: $0.element.isSkipped, i: $0.offset) }
        .sorted { $0.at != $1.at ? $0.at < $1.at : $0.i < $1.i }

    var taken = 0, skipped = 0, windowStart = 0
    for time in scheduled {
        while windowStart < order.count && order[windowStart].at < time - tolerance { windowStart += 1 }
        if windowStart < order.count, order[windowStart].at <= time + tolerance {
            if order[windowStart].skipped { skipped += 1 } else { taken += 1 }
            windowStart += 1
        }
    }
    let expected = scheduled.count
    return AdherenceWindow(expected: expected, taken: taken, skipped: skipped,
                           missed: expected - taken - skipped,
                           rate: expected > 0 ? Double(taken) / Double(expected) : 1)
}

/// The doses in a window that nothing has been logged against (a skip counts).
/// `logs` must already be narrowed to this protocol.
public func unloggedDoseTimes<L: LogLike>(_ p: DoseProtocol, _ logs: [L], _ fromMs: Millis, _ toMs: Millis,
                                          toleranceHours: Double = 12) -> [Millis] {
    let tolerance = toleranceHours * HOUR_MS
    return protocolDoseTimesBetween(p, fromMs, toMs).filter { at in
        if !slotIsKnowable(p, at) { return false }
        let before = protocolPreviousDoseTime(p, at - 1)
        let early = earlyWindowMs(before.map { at - $0 }, tolerance)
        return !logs.contains { $0.at >= at - early && $0.at <= at }
    }
}

/// Whether the app has any standing to say a dose at this moment was missed:
/// not for slots before the schedule was last moved.
public func slotIsKnowable(_ p: DoseProtocol, _ atMs: Millis) -> Bool {
    guard let changed = p.scheduleChangedAt else { return true }
    return atMs >= changed
}

public enum DueState: String, Sendable {
    case overdue, dueNow = "due-now", upcoming, scheduled, none
}

public enum DueLabel: String, Sendable {
    case paused, dueNow = "due-now", overdue, none, dueToday = "due-today", scheduled
}

public struct DueStatus: Equatable, Sendable {
    public var state: DueState
    public var at: Millis?
    /// Hours until due; negative when overdue.
    public var hoursAway: Double
    public var label: DueLabel
}

public struct DueOptions: Sendable {
    /// When the most recent dose was logged, skipped logs included.
    public var lastLoggedAt: Millis?
    public var graceHours: Double = 4
    public var toleranceHours: Double = 12
    public init(lastLoggedAt: Millis? = nil, graceHours: Double = 4, toleranceHours: Double = 12) {
        self.lastLoggedAt = lastLoggedAt; self.graceHours = graceHours; self.toleranceHours = toleranceHours
    }
}

/// Whether a log taken before a scheduled dose was that dose.
func loggedEarlyFor(_ next: Millis, _ prev: Millis?, _ lastLoggedAt: Millis, _ graceMs: Double) -> Bool {
    let early = next - lastLoggedAt
    if early < 0 || early > graceMs { return false }
    guard let prev else { return true }
    return early < lastLoggedAt - prev
}

/// How long before a scheduled dose a log can be and still be that dose:
/// a quarter of the gap to the dose before, capped.
func earlyWindowMs(_ gapMs: Double?, _ capMs: Double) -> Double {
    guard let gapMs else { return capMs }
    return min(capMs, gapMs / 4)
}

/// How a protocol's next dose should be presented.
public func dueStatus(_ p: DoseProtocol, _ nowMs: Millis, _ options: DueOptions = DueOptions()) -> DueStatus {
    let lastLoggedAt = options.lastLoggedAt
    let graceHours = options.graceHours
    if !p.active { return DueStatus(state: .none, at: nil, hoursAway: 0, label: .paused) }

    let grace = graceHours * HOUR_MS
    let tolerance = options.toleranceHours * HOUR_MS
    let prev = protocolPreviousDoseTime(p, nowMs)
    let before = prev.flatMap { protocolPreviousDoseTime(p, $0 - 1) }
    let early = earlyWindowMs(prev != nil && before != nil ? prev! - before! : nil, tolerance)
    let prevCovered = prev != nil && lastLoggedAt != nil && lastLoggedAt! >= prev! - early

    if let prev, !prevCovered, slotIsKnowable(p, prev), p.endedAt == nil || prev <= p.endedAt! {
        let hoursAway = (prev - nowMs) / HOUR_MS
        if nowMs - prev <= grace {
            return DueStatus(state: .dueNow, at: prev, hoursAway: hoursAway, label: .dueNow)
        }
        return DueStatus(state: .overdue, at: prev, hoursAway: hoursAway, label: .overdue)
    }

    var next = protocolNextDoseTime(p, nowMs)
    if let n = next, let last = lastLoggedAt, loggedEarlyFor(n, prev, last, grace) {
        next = protocolNextDoseTime(p, n + 1)
    }
    guard let next else { return DueStatus(state: .none, at: nil, hoursAway: 0, label: .none) }
    let hours = (next - nowMs) / HOUR_MS
    if hours <= graceHours { return DueStatus(state: .dueNow, at: next, hoursAway: hours, label: .dueNow) }
    if next <= endOfLocalDay(nowMs) { return DueStatus(state: .upcoming, at: next, hoursAway: hours, label: .dueToday) }
    return DueStatus(state: .scheduled, at: next, hoursAway: hours, label: .scheduled)
}
