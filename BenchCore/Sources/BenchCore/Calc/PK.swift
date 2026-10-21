import Foundation
import Synchronization

// Port of src/lib/calc/pk.ts.
//
// One-compartment model with first-order absorption (the Bateman function):
//   C(t) = A · (e^(-ke·t) − e^(-ka·t))
// ke from the published half-life, ka solved from the published Tmax; without a
// Tmax, instant absorption. Every curve is NORMALISED so a single dose peaks at
// 1.0: a relative level, never an absolute ng/mL.

public let LN2 = M_LN2

public func eliminationRate(_ halfLifeHours: Double) -> Double { LN2 / halfLifeHours }

/// Fraction of a single dose still present after a given time.
public func fractionRemaining(_ hoursElapsed: Double, _ halfLifeHours: Double) -> Double {
    if hoursElapsed <= 0 { return 1 }
    guard halfLifeHours > 0 else { return 0 }
    return pow(2, -hoursElapsed / halfLifeHours)
}

/// Absorption rate implied by a time-to-peak, by bisection. A Tmax at or past
/// the model's limit (1/ke) is clamped just under it.
public func absorptionRate(_ tmaxHours: Double, _ halfLifeHours: Double) -> Double {
    let ke = eliminationRate(halfLifeHours)
    let limit = 1 / ke
    guard tmaxHours > 0 else { return ke * 1000 }
    let target = min(tmaxHours, limit * 0.999)
    let tmaxFor: (Double) -> Double = { ka in log(ka / ke) / (ka - ke) }
    var lo = ke * 1.000001
    var hi = ke * 1e6
    for _ in 0..<200 {
        let mid = (lo * hi).squareRoot()
        if tmaxFor(mid) > target { lo = mid } else { hi = mid }
    }
    return (lo * hi).squareRoot()
}

public struct CurveParams: Equatable, Hashable, Sendable {
    public var halfLifeHours: Double
    /// Time to peak; nil for instant absorption.
    public var tmaxHours: Double?
    public init(halfLifeHours: Double, tmaxHours: Double? = nil) {
        self.halfLifeHours = halfLifeHours; self.tmaxHours = tmaxHours
    }
}

struct CurveConstants: Sendable {
    var ke: Double
    var ka: Double?
    var peak: Double
    var degenerate: Bool
}

private struct CurveKey: Hashable { var halfLife: Double; var tmax: Double }
private let curveCache = Mutex<[CurveKey: CurveConstants]>([:])
private let CURVE_CACHE_LIMIT = 256

/// The constants a curve is built from, cached per compound (`ka` costs a bisection).
func curveConstants(_ halfLifeHours: Double, _ tmaxHours: Double?) -> CurveConstants {
    let key = CurveKey(halfLife: halfLifeHours, tmax: tmaxHours ?? 0)
    if let hit = curveCache.withLock({ $0[key] }) { return hit }
    let ke = eliminationRate(halfLifeHours)
    let value: CurveConstants
    if let tmax = tmaxHours, tmax > 0 {
        let ka = absorptionRate(tmax, halfLifeHours)
        if abs(ka - ke) < 1e-12 {
            value = CurveConstants(ke: ke, ka: ka, peak: 1 / M_E, degenerate: true)
        } else {
            let tmaxActual = log(ka / ke) / (ka - ke)
            value = CurveConstants(ke: ke, ka: ka, peak: exp(-ke * tmaxActual) - exp(-ka * tmaxActual), degenerate: false)
        }
    } else {
        value = CurveConstants(ke: ke, ka: nil, peak: 1, degenerate: false)
    }
    curveCache.withLock { cache in
        if cache.count >= CURVE_CACHE_LIMIT { cache.removeAll() }
        cache[key] = value
    }
    return value
}

/// Relative concentration from one dose, peak 1.0; 0 before the dose.
public func singleDoseLevel(_ hoursSinceDose: Double, _ params: CurveParams) -> Double {
    if hoursSinceDose < 0 { return 0 }
    guard params.halfLifeHours > 0 else { return 0 }
    let c = curveConstants(params.halfLifeHours, params.tmaxHours)
    guard let ka = c.ka else { return exp(-c.ke * hoursSinceDose) }
    if c.degenerate { return (c.ke * hoursSinceDose * exp(-c.ke * hoursSinceDose)) / c.peak }
    guard c.peak > 0 else { return 0 }
    return (exp(-c.ke * hoursSinceDose) - exp(-ka * hoursSinceDose)) / c.peak
}

/// Where the half-life behind a curve came from.
public enum CurveBasis: String, Sendable {
    /// Measured in people, taking it the way people take it.
    case published
    /// Measured, but in another species or by another route.
    case elsewhere
    /// Your own figure, for a compound the library has none for.
    case yours
}

public struct Curve: Equatable, Sendable {
    public var params: CurveParams
    public var basis: CurveBasis
}

/// Published human half-life, then yours, then another species', then nothing.
public func curveFor(halfLifeHours: Double?, tmaxHours: Double?, estimateHours: Double?, yours: Double?) -> Curve? {
    if let h = halfLifeHours { return Curve(params: CurveParams(halfLifeHours: h, tmaxHours: tmaxHours), basis: .published) }
    if let y = yours, y > 0 { return Curve(params: CurveParams(halfLifeHours: y, tmaxHours: tmaxHours), basis: .yours) }
    if let e = estimateHours { return Curve(params: CurveParams(halfLifeHours: e, tmaxHours: tmaxHours), basis: .elsewhere) }
    return nil
}

public func curveFor(_ p: Peptide, yours: HalfLifeOverride? = nil) -> Curve? {
    curveFor(halfLifeHours: p.halfLifeHours, tmaxHours: p.tmaxHours, estimateHours: p.halfLifeEstimate?.hours, yours: yours?.hours)
}

/// Whether anything derived from a curve may be stated as a figure.
public func isMeasuredInPeople(_ basis: CurveBasis) -> Bool { basis == .published }

public struct DoseEvent: Equatable, Sendable {
    public var at: Millis
    public var amountMcg: Double
    public var vialId: String?
    public init(at: Millis, amountMcg: Double, vialId: String? = nil) {
        self.at = at; self.amountMcg = amountMcg; self.vialId = vialId
    }
}

/// Combined level by superposition, scaled by dose relative to `referenceMcg`.
public func levelAt(_ atMs: Millis, _ doses: [DoseEvent], _ params: CurveParams, _ referenceMcg: Double) -> Double {
    guard referenceMcg > 0 else { return 0 }
    var total = 0.0
    for dose in doses where dose.at <= atMs {
        let hours = (atMs - dose.at) / HOUR_MS
        if hours > params.halfLifeHours * 10 { continue }
        total += singleDoseLevel(hours, params) * (dose.amountMcg / referenceMcg)
    }
    return total
}

public struct DoseContribution: Equatable, Sendable {
    public var dose: DoseEvent
    public var level: Double
    public var share: Double
}

public struct LevelBreakdown: Equatable, Sendable {
    /// The whole level, including doses too small to be listed.
    public var total: Double
    /// The doses worth naming, largest first.
    public var contributions: [DoseContribution]
}

/// The same level, split exactly into the doses that make it up.
public func breakdownAt(_ atMs: Millis, _ doses: [DoseEvent], _ params: CurveParams, _ referenceMcg: Double,
                        minShare: Double = 0.05) -> LevelBreakdown {
    guard referenceMcg > 0 else { return LevelBreakdown(total: 0, contributions: []) }
    var parts: [DoseContribution] = []
    var total = 0.0
    for dose in doses where dose.at <= atMs {
        let hours = (atMs - dose.at) / HOUR_MS
        if hours > params.halfLifeHours * 10 { continue }
        let level = singleDoseLevel(hours, params) * (dose.amountMcg / referenceMcg)
        if level <= 0 { continue }
        total += level
        parts.append(DoseContribution(dose: dose, level: level, share: 0))
    }
    guard total > 0 else { return LevelBreakdown(total: 0, contributions: []) }
    let contributions = parts.map { var p = $0; p.share = p.level / total; return p }
        .filter { $0.share >= minShare }
        .stableSorted { $0.level > $1.level }
    return LevelBreakdown(total: total, contributions: contributions)
}

public struct SeriesPoint: Equatable, Sendable {
    public var t: Millis
    public var level: Double
}

/// Sample the combined curve across a window, for plotting.
public func levelSeries(_ fromMs: Millis, _ toMs: Millis, _ steps: Int, _ doses: [DoseEvent], _ params: CurveParams,
                        _ referenceMcg: Double) -> [SeriesPoint] {
    let span = toMs - fromMs
    guard span > 0, steps >= 2 else { return [] }
    return (0..<steps).map { i in
        let t = fromMs + (span * Double(i)) / Double(steps - 1)
        return SeriesPoint(t: t, level: levelAt(t, doses, params, referenceMcg))
    }
}

/// Steady-state peak over first-dose peak at a fixed interval.
public func accumulationRatio(_ intervalHours: Double, _ halfLifeHours: Double) -> Double {
    guard intervalHours > 0, halfLifeHours > 0 else { return 1 }
    return 1 / (1 - exp(-eliminationRate(halfLifeHours) * intervalHours))
}

/// Hours to reach a fraction of steady state. Five half-lives ≈ 97%.
public func timeToSteadyState(_ halfLifeHours: Double, fraction: Double = 0.97) -> Double {
    guard halfLifeHours > 0 else { return 0 }
    return -halfLifeHours * log2(1 - fraction)
}

/// How long until a single dose decays to a given fraction of its peak.
public func hoursUntilFraction(_ fraction: Double, _ halfLifeHours: Double) -> Double {
    guard fraction > 0, fraction < 1 else { return 0 }
    return halfLifeHours * log2(1 / fraction)
}

public enum PhaseId: String, Sendable { case absorbing, peak, active, trailing, cleared }

/// Where a compound sits on its curve.
public func describePhase(_ level: Double, rising: Bool, nearPeak: Bool) -> PhaseId {
    if level < 0.05 { return .cleared }
    if nearPeak { return .peak }
    if rising { return .absorbing }
    if level >= 0.4 { return .active }
    return .trailing
}

public struct LevelSnapshot: Equatable, Sendable {
    public var level: Double
    public var rising: Bool
    public var nearPeak: Bool
    public var phase: PhaseId
    /// Percentage of a single reference-dose peak.
    public var percentOfPeak: Double
}

/// Everything the dashboard needs about one compound at one instant.
public func snapshot(_ atMs: Millis, _ doses: [DoseEvent], _ params: CurveParams, _ referenceMcg: Double) -> LevelSnapshot {
    let level = levelAt(atMs, doses, params, referenceMcg)
    let step = 6 * 60 * 1000.0
    let before = levelAt(atMs - step, doses, params, referenceMcg)
    let after = levelAt(atMs + step, doses, params, referenceMcg)
    let rising = after > level
    let nearPeak = level > 0.05 && after <= level && before <= level
    return LevelSnapshot(level: level, rising: rising, nearPeak: nearPeak,
                         phase: describePhase(level, rising: rising, nearPeak: nearPeak), percentOfPeak: level * 100)
}
