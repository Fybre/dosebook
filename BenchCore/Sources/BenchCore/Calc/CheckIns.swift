import Foundation

// Port of src/lib/calc/checkins.ts. Daily subjective ratings, put side by side
// with the day counts behind them. Deliberately no correlation coefficient.

/// Fewer days than this and a period is not worth calling a trend.
public let MIN_DAYS_FOR_TREND = 4

public struct SymptomAverage: Equatable, Sendable {
    public var id: SymptomId
    public var label: String
    public var mean: Double?
    public var days: Int
    public var higherIsBetter: Bool?
}

public func averages(_ checkIns: [CheckIn]) -> [SymptomAverage] {
    SYMPTOMS.map { s in
        let values = checkIns.compactMap { $0.rating(s.id) }.filter(\.isFinite)
        return SymptomAverage(id: s.id, label: s.label, mean: values.isEmpty ? nil : values.reduce(0, +) / Double(values.count),
                              days: values.count, higherIsBetter: s.higherIsBetter)
    }
}

/// Check-ins inside [from, to).
public func inWindow(_ checkIns: [CheckIn], _ fromMs: Millis, _ toMs: Millis) -> [CheckIn] {
    checkIns.filter { $0.at >= fromMs && $0.at < toMs }
}

public struct SymptomShift: Equatable, Sendable {
    public var id: SymptomId
    public var label: String
    public var before: Double?
    public var after: Double?
    public var delta: Double?
    public var daysBefore: Int
    public var daysAfter: Int
    public var higherIsBetter: Bool?
}

/// Ratings either side of a moment, each side bounded by the window and the
/// forward side capped at today.
public func shiftAround(_ checkIns: [CheckIn], _ atMs: Millis, windowDays: Double = 28, nowMs: Millis = nowMillis()) -> [SymptomShift] {
    let pivot = startOfLocalDay(atMs)
    let span = windowDays * DAY_MS
    let before = averages(inWindow(checkIns, pivot - span, pivot))
    let after = averages(inWindow(checkIns, pivot, min(pivot + span, nowMs + DAY_MS)))
    return SYMPTOMS.enumerated().map { i, s in
        let b = before[i].mean, a = after[i].mean
        return SymptomShift(id: s.id, label: s.label, before: b, after: a, delta: (b != nil && a != nil) ? a! - b! : nil,
                            daysBefore: before[i].days, daysAfter: after[i].days, higherIsBetter: s.higherIsBetter)
    }
}

public func isTrendworthy(_ shift: SymptomShift) -> Bool {
    shift.delta != nil && shift.daysBefore >= MIN_DAYS_FOR_TREND && shift.daysAfter >= MIN_DAYS_FOR_TREND
}

/// The check-in covering a given day.
public func checkInFor(_ checkIns: [CheckIn], _ dayMs: Millis) -> CheckIn? {
    let day = startOfLocalDay(dayMs)
    return checkIns.first { $0.at == day }
}

public struct CheckInStreak: Equatable, Sendable {
    /// Consecutive days ending today, or yesterday if today is not rated yet.
    public var current: Int
    public var last30: Int
}

public func checkInStreak(_ checkIns: [CheckIn], nowMs: Millis = nowMillis()) -> CheckInStreak {
    let rated = Set(checkIns.map { startOfLocalDay($0.at) })
    let today = startOfLocalDay(nowMs)
    var cursor = rated.contains(today) ? today : addLocalDays(today, -1)
    var current = 0
    while rated.contains(cursor) { current += 1; cursor = addLocalDays(cursor, -1) }
    let last30 = (0..<30).filter { rated.contains(addLocalDays(today, Double(-$0))) }.count
    return CheckInStreak(current: current, last30: last30)
}

public struct RatingPoint: Equatable, Sendable {
    public var at: Millis
    public var value: Double
}

/// One symptom's ratings, oldest first.
public func ratingSeries(_ checkIns: [CheckIn], _ id: SymptomId) -> [RatingPoint] {
    checkIns.compactMap { c in c.rating(id).map { RatingPoint(at: c.at, value: $0) } }.stableSorted { $0.at < $1.at }
}

/// The day a rating would belong to, or nil when that day has not happened.
public func ratableDay(_ at: Millis, nowMs: Millis = nowMillis()) -> Millis? {
    let day = startOfLocalDay(at)
    return day > startOfLocalDay(nowMs) ? nil : day
}

public struct DiaryDay<T> {
    public var day: Millis
    public var entries: [T]
    public var checkIn: CheckIn?
}

/// A day at a time: what was taken and how the day went, newest first. Days
/// with only a rating are kept.
public func diaryDays<T>(_ entries: [T], at: (T) -> Millis, _ checkIns: [CheckIn]) -> [DiaryDay<T>] {
    var days = OrderedMap<Millis, DiaryDay<T>>()
    for e in entries {
        let key = startOfLocalDay(at(e))
        var d = days[key] ?? DiaryDay(day: key, entries: [], checkIn: nil)
        d.entries.append(e)
        days[key] = d
    }
    for c in checkIns {
        let key = startOfLocalDay(c.at)
        var d = days[key] ?? DiaryDay(day: key, entries: [], checkIn: nil)
        d.checkIn = c
        days[key] = d
    }
    return days.values.stableSorted { $0.day > $1.day }
}
