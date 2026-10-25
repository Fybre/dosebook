import Foundation

// A weight to see your trend against. It says nothing about what a good target is;
// it only draws the line you chose and, from the last month's weigh-ins, when the
// trend would cross it if it carried on. A trend, not a promise.

/// iOS only, kept in `Settings.extra`. `startKg` is the weight when the goal was
/// set, which is what says whether it is a loss or a gain.
public struct WeightGoal: Equatable, Sendable {
    public var kg: Double
    public var startKg: Double
    public init(kg: Double, startKg: Double) { self.kg = kg; self.startKg = startKg }
}

public extension Settings {
    var weightGoal: WeightGoal? {
        get {
            guard let o = extra["iosWeightGoal"]?.objectValue, let kg = o["kg"]?.numberValue, kg > 0 else { return nil }
            return WeightGoal(kg: kg, startKg: o["startKg"]?.numberValue ?? kg)
        }
        set {
            if let g = newValue { extra["iosWeightGoal"] = .object(["kg": .number(g.kg), "startKg": .number(g.startKg)]) }
            else { extra.removeValue(forKey: "iosWeightGoal") }
        }
    }
}

public enum GoalProgress: Equatable, Sendable {
    /// Fewer than three weigh-ins in the window, or all within a week.
    case needsData
    /// The latest weigh-in is at the goal or past it, the way it was heading.
    case reached
    /// Heading there: kg per week, and when the line would cross.
    case onTrack(perWeekKg: Double, reachedAt: Millis)
    /// Flat, or the other way, over the window.
    case notHeadingThere(perWeekKg: Double)
    /// Heading there, but more than two years out.
    case slow(perWeekKg: Double)
}

/// Where the last `windowDays` of weigh-ins put you against the goal.
public func weightGoalProgress(_ measurements: [BodyMeasurement], goal: WeightGoal, now: Millis, windowDays: Double = 30) -> GoalProgress {
    let all = weightSeries(measurements)
    guard let latest = all.last else { return .needsData }
    let losing = goal.kg < goal.startKg
    let gaining = goal.kg > goal.startKg
    if (losing && latest.kg <= goal.kg) || (gaining && latest.kg >= goal.kg) || abs(latest.kg - goal.kg) < 0.05 { return .reached }

    let points = all.filter { $0.at >= now - windowDays * DAY_MS }
    guard points.count >= 3, let first = points.first, latest.at - first.at >= 7 * DAY_MS else { return .needsData }

    // Least squares, weight against days since the first of them.
    let xs = points.map { ($0.at - first.at) / DAY_MS }, ys = points.map(\.kg)
    let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
    var sxy = 0.0, sxx = 0.0
    for i in xs.indices { sxy += (xs[i] - mx) * (ys[i] - my); sxx += (xs[i] - mx) * (xs[i] - mx) }
    guard sxx > 0 else { return .needsData }
    let perDay = sxy / sxx
    let perWeek = perDay * 7

    let needed = goal.kg - latest.kg
    // The right way, and at least 10 g a week: less is noise.
    guard needed * perDay > 0, abs(perWeek) >= 0.01 else { return .notHeadingThere(perWeekKg: perWeek) }
    let days = needed / perDay
    if days > 730 { return .slow(perWeekKg: perWeek) }
    return .onTrack(perWeekKg: perWeek, reachedAt: max(now, latest.at) + days * DAY_MS)
}
