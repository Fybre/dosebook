import Foundation

// Port of src/lib/calc/barrel.ts. Where the printed marks go on a drawn barrel.
//
// A barrel too fine for its width is MAGNIFIED (the first whole numbered
// divisions that fit, at true spacing, flagged), never thinned: thinning draws
// the finer instrument coarser than the blunter one beside it.

public struct BarrelTick: Equatable, Sendable {
    /// Units from the needle end.
    public var units: Double
    /// 0 at the needle, 1 at the far end of the drawn stretch.
    public var fraction: Double
    /// Numbered marks, drawn longer.
    public var major: Bool
}

public struct BarrelScale: Equatable, Sendable {
    public var ticks: [BarrelTick]
    /// Units the drawing covers: the capacity, unless magnified.
    public var shownUnits: Double
    public var magnified: Bool
    public var majorEvery: Double
}

/// 0.3 and 0.5 mL barrels (and U-40 0–40) are numbered every 5; 1 mL U-100 every 10.
public func majorEveryFor(_ capacity: Double) -> Double { capacity <= 50 ? 5 : 10 }

/// `widthPx` is the width the barrel really occupies on screen, in points.
public func barrelTicks(_ spec: SyringeSpec, _ widthPx: Double, minSpacingPx: Double = 2.5, allowMagnify: Bool = false) -> BarrelScale {
    let capacity = capacityUnits(spec)
    let majorEvery = majorEveryFor(capacity)
    let step = spec.graduationUnits
    let spacingFor: (Double) -> Double = { $0 > 0 ? (widthPx * step) / $0 : .infinity }

    var shownUnits = capacity
    var magnified = false
    if allowMagnify && capacity > 0 && spacingFor(capacity) < minSpacingPx {
        let fits = ((widthPx * step) / minSpacingPx).rounded(.down)
        let divisions = max(1, (fits / majorEvery).rounded(.down))
        shownUnits = min(capacity, divisions * majorEvery)
        magnified = shownUnits < capacity
    }

    var ticks: [BarrelTick] = []
    var u = 0.0
    while u <= shownUnits + 1e-9 {
        let units = jsRound(u * 1000) / 1000
        ticks.append(BarrelTick(units: units, fraction: shownUnits > 0 ? units / shownUnits : 0,
                                major: abs(units.truncatingRemainder(dividingBy: majorEvery)) < 1e-9))
        u += step
    }
    return BarrelScale(ticks: ticks, shownUnits: shownUnits, magnified: magnified, majorEvery: majorEvery)
}
