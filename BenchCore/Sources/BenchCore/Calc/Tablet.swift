import Foundation

// Port of src/lib/calc/tablet.ts. A pack is a `Vial` with `container: "pack"`;
// `strengthMg` is the whole pack, `mgPerTablet` the unit it is counted in.
// No default tablet size: a pack with none recorded counts as nothing.

public func isPack(_ v: Vial) -> Bool { v.container == .pack }

public func mgPerTablet(_ v: Vial) -> Double {
    if let mg = v.mgPerTablet, mg.isFinite, mg > 0 { return mg }
    return 0
}

public func mcgPerTablet(_ v: Vial) -> Double { mgPerTablet(v) * MCG_PER_MG }
public func mcgForTablets(_ v: Vial, _ tablets: Double) -> Double { mcgPerTablet(v) * max(0, tablets) }

/// Exact tablets for a dose, fractions kept (a scored tablet really is half a dose).
public func tabletsForDose(_ v: Vial, _ doseMcg: Double) -> Double {
    let per = mcgPerTablet(v)
    return per > 0 ? max(0, doseMcg / per) : 0
}

/// Whole tablets left, floored.
public func tabletsRemaining(_ v: Vial) -> Double {
    let per = mcgPerTablet(v)
    return per > 0 ? (vialRemainingMcg(v) / per).rounded(.down) : 0
}

/// The mass a pack of this many tablets holds.
public func packStrengthMg(_ mgEach: Double, _ tablets: Double) -> Double {
    max(0, mgEach) * max(0, tablets.rounded(.down))
}

/// Slots of a fixed blister glyph still full; never empty while anything is left,
/// never full once anything is gone.
public func blisterDots(_ fraction: Double, _ slots: Int) -> Int {
    let f = fraction.isFinite ? max(0, min(1, fraction)) : 0
    if f <= 0 { return 0 }
    if f >= 1 { return slots }
    return min(slots - 1, max(1, Int(jsRound(f * Double(slots)))))
}
