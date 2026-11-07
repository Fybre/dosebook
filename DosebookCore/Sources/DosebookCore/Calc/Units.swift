import Foundation

// Port of src/lib/calc/units.ts. Growth hormone is counted in IU, which is a unit
// of activity, not mass; the app stores micrograms and converts at the edges.

public func mcgToIu(_ mcg: Double, _ iuPerMg: Double) -> Double {
    guard iuPerMg > 0, mcg.isFinite else { return .nan }
    return (mcg / MCG_PER_MG) * iuPerMg
}

public func iuToMcg(_ iu: Double, _ iuPerMg: Double) -> Double {
    guard iuPerMg > 0, iu.isFinite else { return .nan }
    return (iu / iuPerMg) * MCG_PER_MG
}

/// Whether this compound is one people count in IU.
public func isIuDosed(_ p: Peptide?) -> Bool { (p?.iuPerMg ?? 0) > 0 }

/// IU first for anything dosed that way, with the mass in brackets as the check.
public func formatDoseWithIu(_ p: Peptide?, _ mcg: Double) -> String {
    guard mcg.isFinite else { return "n/a" }
    if let iuPerMg = p?.iuPerMg, iuPerMg > 0 {
        return "\(jsNumberString(jsFixed(mcgToIu(mcg, iuPerMg), 2))) IU (\(jsNumberString(jsFixed(mcg / MCG_PER_MG, 3))) mg)"
    }
    return mcg < MCG_PER_MG
        ? "\(jsNumberString(jsFixed(mcg, 1))) mcg"
        : "\(jsNumberString(jsFixed(mcg / MCG_PER_MG, 3))) mg"
}

/// Concentration of a ready-made solution, mcg/mL. Same arithmetic as reconstitution.
public func concentrationFromFill(_ strengthMg: Double, _ fillMl: Double) -> Double {
    guard fillMl > 0, strengthMg > 0 else { return .nan }
    return (strengthMg * MCG_PER_MG) / fillMl
}

/// Label strength implied by a stated concentration and fill volume.
public func strengthFromConcentration(_ mgPerMl: Double, _ fillMl: Double) -> Double {
    guard mgPerMl > 0, fillMl > 0 else { return .nan }
    return mgPerMl * fillMl
}

/// True when the compound arrives ready to draw rather than as a powder.
public func isSolution(_ p: Peptide?) -> Bool { p?.preparation == .solution }
