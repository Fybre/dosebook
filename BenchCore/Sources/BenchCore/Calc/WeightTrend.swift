import Foundation

// Weight set against dose changes: a compound's history split into steps where
// the dose held steady, and how weight moved during each. Not in the original.

/// A run of doses at one amount.
public struct DoseStep: Equatable, Sendable {
    public var doseMcg: Double
    /// The first dose at this amount.
    public var from: Millis
    /// The first dose at the next amount, or now for the step still running.
    public var to: Millis
    public var doses: Int
}

/// Consecutive doses of one compound grouped by amount. A one-off different dose
/// still starts a step, since that is what was taken.
public func doseSteps(_ logs: [DoseLog], peptideId: String, now: Millis) -> [DoseStep] {
    let taken = logs.filter { $0.peptideId == peptideId && !$0.isSkipped && $0.doseMcg > 0 }.stableSorted { $0.at < $1.at }
    var steps: [DoseStep] = []
    for l in taken {
        if let last = steps.last, abs(last.doseMcg - l.doseMcg) <= max(0.5, last.doseMcg * 0.01) {
            steps[steps.count - 1].doses += 1
        } else {
            if !steps.isEmpty { steps[steps.count - 1].to = l.at }
            steps.append(DoseStep(doseMcg: l.doseMcg, from: l.at, to: max(now, l.at), doses: 1))
        }
    }
    return steps
}

public struct StepWeight: Equatable, Sendable {
    public var step: DoseStep
    /// Weigh-ins inside the step.
    public var points: Int
    /// Last weigh-in less the first, inside the step.
    public var changeKg: Double?
    /// The trend through every weigh-in in the step, per week. Needs two readings
    /// at least three days apart, or a slope would be noise.
    public var perWeekKg: Double?
}

/// How weight moved during each step.
public func weightDuring(_ steps: [DoseStep], _ measurements: [BodyMeasurement]) -> [StepWeight] {
    let series = weightSeries(measurements)
    return steps.map { step in
        let inside = series.filter { $0.at >= step.from && $0.at < step.to }
        guard inside.count >= 2, let first = inside.first, let last = inside.last else {
            return StepWeight(step: step, points: inside.count, changeKg: nil, perWeekKg: nil)
        }
        let span = last.at - first.at
        var slope: Double?
        if span >= 3 * DAY_MS {
            let xs = inside.map { ($0.at - first.at) / DAY_MS }, ys = inside.map(\.kg)
            let mx = xs.reduce(0, +) / Double(xs.count), my = ys.reduce(0, +) / Double(ys.count)
            let sxx = zip(xs, xs).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - mx) }
            let sxy = zip(xs, ys).reduce(0) { $0 + ($1.0 - mx) * ($1.1 - my) }
            if sxx > 0 { slope = sxy / sxx * 7 }
        }
        return StepWeight(step: step, points: inside.count, changeKg: last.kg - first.kg, perWeekKg: slope)
    }
}

/// The compound whose dose has changed most often, to show first.
public func mostTitratedCompound(_ logs: [DoseLog], now: Millis) -> String? {
    let ids = logs.filter { !$0.isSkipped }.map(\.peptideId).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
    return ids.max { doseSteps(logs, peptideId: $0, now: now).count < doseSteps(logs, peptideId: $1, now: now).count }
}
