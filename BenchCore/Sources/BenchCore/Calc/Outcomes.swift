import Foundation

// Port of src/lib/calc/outcomes.ts. Weight against the dose staircase ("is it
// working") and side effects against the titration step ("can I tolerate going up").

public let KG_PER_LB = 0.45359237
public func lbToKg(_ lb: Double) -> Double { lb * KG_PER_LB }
public func kgToLb(_ kg: Double) -> Double { kg / KG_PER_LB }

/// Weight is stored in kilograms. Use both of these at a field's edges, or neither.
public func toDisplayWeight(_ kg: Double, _ unit: WeightUnit) -> Double { unit == .lb ? kgToLb(kg) : kg }
public func fromDisplayWeight(_ value: Double, _ unit: WeightUnit) -> Double { unit == .lb ? lbToKg(value) : value }

public struct WeightPoint: Equatable, Sendable {
    public var at: Millis
    public var kg: Double
}

/// Weight entries with a value, oldest first.
public func weightSeries(_ measurements: [BodyMeasurement]) -> [WeightPoint] {
    measurements.compactMap { m in m.weightKg.flatMap { $0 > 0 ? WeightPoint(at: m.at, kg: $0) : nil } }
        .stableSorted { $0.at < $1.at }
}

public struct WeightChange: Equatable, Sendable {
    public var first: WeightPoint
    public var latest: WeightPoint
    /// Negative means loss.
    public var deltaKg: Double
    public var deltaPercent: Double
    public var days: Double
    public var perWeekKg: Double?
}

/// Earliest to latest in a window; nil with fewer than two readings.
public func weightChange(_ measurements: [BodyMeasurement], since: Millis? = nil) -> WeightChange? {
    let all = weightSeries(measurements)
    let series = since.map { s in all.filter { $0.at >= s } } ?? all
    guard series.count >= 2 else { return nil }
    let first = series[0], latest = series[series.count - 1]
    let delta = latest.kg - first.kg
    let days = (latest.at - first.at) / DAY_MS
    return WeightChange(first: first, latest: latest, deltaKg: delta,
                        deltaPercent: first.kg > 0 ? (delta / first.kg) * 100 : 0, days: days,
                        perWeekKg: days >= 1 ? (delta / days) * 7 : nil)
}

public func latestWeightKg(_ measurements: [BodyMeasurement]) -> Double? { weightSeries(measurements).last?.kg }

public struct SideEffectCount: Equatable, Sendable {
    public var effect: String
    public var count: Int
    public var rate: Double
}

public struct SideEffectTally: Equatable, Sendable {
    public var total: Int
    public var effects: [SideEffectCount]
}

/// Side effects across a set of doses, most frequent first.
public func sideEffectTally(_ logs: [DoseLog]) -> SideEffectTally {
    let dosed = logs.filter { !$0.isSkipped }
    var counts = OrderedMap<String, Int>()
    for l in dosed { for e in l.sideEffects ?? [] { counts[e] = (counts[e] ?? 0) + 1 } }
    let effects = counts.entries.map { SideEffectCount(effect: $0.key, count: $0.value, rate: dosed.isEmpty ? 0 : Double($0.value) / Double(dosed.count)) }
        .stableSorted { a, b in a.count != b.count ? a.count > b.count : a.effect.localizedCompare(b.effect) == .orderedAscending }
    return SideEffectTally(total: dosed.count, effects: effects)
}

/// Mean of the 1–5 ratings that were filled in.
public func averageFeeling(_ logs: [DoseLog]) -> Double? {
    let rated = logs.filter { !$0.isSkipped }.compactMap(\.feeling)
    guard !rated.isEmpty else { return nil }
    return Double(rated.reduce(0, +)) / Double(rated.count)
}

public struct StepTolerance: Equatable, Sendable {
    public var stepIndex: Int
    public var doseMcg: Double
    public var doses: Int
    public var averageFeeling: Double?
    public var sideEffectRate: Double
    public var topEffects: [SideEffectCount]
}

/// How each titration step went.
public func toleranceByStep(_ logs: [DoseLog], _ titration: [TitrationStep], _ startedAt: Millis) -> [StepTolerance] {
    guard !titration.isEmpty else { return [] }
    var buckets: [Int: [DoseLog]] = [:]
    for l in logs where !l.isSkipped {
        guard let step = titrationStepAt(titration, startedAt, l.at) else { continue }
        buckets[step.index, default: []].append(l)
    }
    return buckets.keys.sorted().map { i in
        let rows = buckets[i]!
        let withEffects = rows.filter { !($0.sideEffects ?? []).isEmpty }.count
        return StepTolerance(stepIndex: i, doseMcg: titration[i].doseMcg, doses: rows.count, averageFeeling: averageFeeling(rows),
                             sideEffectRate: rows.isEmpty ? 0 : Double(withEffects) / Double(rows.count),
                             topEffects: Array(sideEffectTally(rows).effects.prefix(3)))
    }
}
