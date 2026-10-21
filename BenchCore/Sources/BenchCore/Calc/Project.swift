import Foundation

// Port of src/lib/calc/project.ts. What a protocol will do before you run it:
// time to steady state, peak/trough swing, and accumulation. Nothing here
// recommends a dose; it reports what a schedule implies.

public struct Projection: Equatable, Sendable {
    public var series: [SeriesPoint]
    public var doseTimes: [Millis]
    /// Steady-state peak over first-dose peak; nil without a fixed interval.
    public var accumulation: Double?
    public var hoursToSteady: Double
    public var steadyPeak: Double?
    public var steadyTrough: Double?
    /// Peak over trough at steady state.
    public var swing: Double?
}

/// Model a protocol forward. The caller supplies the PK, so a blend can be
/// projected per component.
public func project(_ p: DoseProtocol, halfLifeHours: Double, tmaxHours: Double? = nil, fromMs: Millis? = nil,
                    days: Double? = nil, steps: Int = 240) -> Projection {
    let from = fromMs ?? p.startedAt
    let window = days ?? defaultWindowDays(halfLifeHours, p)
    let to = from + window * DAY_MS
    let doseTimes = protocolDoseTimesBetween(p, from, to)
    let doses = doseTimes.map { DoseEvent(at: $0, amountMcg: scheduledDoseMcg(p, $0)) }
    let first = doses.first?.amountMcg ?? 0
    let reference = first != 0 ? first : (p.doseMcg != 0 ? p.doseMcg : 1)
    let series = levelSeries(from, to, steps, doses, CurveParams(halfLifeHours: halfLifeHours, tmaxHours: tmaxHours), reference)

    let perWeek = protocolDosesPerWeek(p, from)
    let intervalHours = perWeek > 0 ? (7 * 24) / perWeek : 0
    let accumulation = intervalHours > 0 ? accumulationRatio(intervalHours, halfLifeHours) : nil

    var steadyPeak: Double?, steadyTrough: Double?, swing: Double?
    if intervalHours > 0 && !series.isEmpty {
        let tail = series.filter { $0.t >= to - intervalHours * HOUR_MS }
        if tail.count > 1 {
            let peak = tail.map(\.level).max()!, trough = tail.map(\.level).min()!
            steadyPeak = peak; steadyTrough = trough
            swing = trough > 0 ? peak / trough : nil
        }
    }
    return Projection(series: series, doseTimes: doseTimes, accumulation: accumulation,
                      hoursToSteady: timeToSteadyState(halfLifeHours), steadyPeak: steadyPeak,
                      steadyTrough: steadyTrough, swing: swing)
}

/// Five half-lives plus two intervals, clamped to 14–180 days.
public func defaultWindowDays(_ halfLifeHours: Double, _ p: DoseProtocol) -> Double {
    let perWeek = protocolDosesPerWeek(p, p.startedAt)
    let intervalDays = perWeek > 0 ? 7 / perWeek : 7
    let toSteadyDays = timeToSteadyState(halfLifeHours) / 24
    return min(180, max(14, (toSteadyDays + intervalDays * 2).rounded(.up)))
}

public func describeAccumulation(_ accumulation: Double?) -> String? {
    guard let a = accumulation else { return nil }
    if a < 1.15 { return "Each dose has essentially cleared before the next, so levels do not build." }
    if a < 1.75 { return "Levels build modestly over the first few doses before settling." }
    if a < 3 {
        return "Levels roughly double or more between the first dose and steady state. The early doses are not representative of where this settles."
    }
    return "Steady state sits several times higher than the first dose. Dosing this frequently relative to the half-life is what drives that, not the dose size."
}
