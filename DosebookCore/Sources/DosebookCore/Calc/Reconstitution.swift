import Foundation

// Port of src/lib/calc/reconstitution.ts.
//
// Mass in micrograms, volume in millilitres. An insulin syringe's marks are
// VOLUME graduations: U-100 is 100 marks per mL, U-40 is 40. Reading a U-40
// barrel as U-100 delivers 2.5x the intended volume. Nothing here assumes a
// scale; the caller must state one.

public func unitsPerMl(_ scale: SyringeScale) -> Double {
    scale == .u40 ? 40 : 100
}

/// Volume represented by a single unit on a given scale, in millilitres.
public func mlPerUnit(_ scale: SyringeScale) -> Double { 1 / unitsPerMl(scale) }

public struct SyringeSpec: Equatable, Sendable, Identifiable, Hashable {
    public var id: String
    public var scale: SyringeScale
    public var capacityMl: Double
    /// Spacing of the smallest printed mark in the barrel's own units. Stated, never inferred.
    public var graduationUnits: Double
    public var label: String
    public var note: String?

    public init(id: String, scale: SyringeScale, capacityMl: Double, graduationUnits: Double, label: String, note: String? = nil) {
        self.id = id; self.scale = scale; self.capacityMl = capacityMl
        self.graduationUnits = graduationUnits; self.label = label; self.note = note
    }
}

public func capacityUnits(_ spec: SyringeSpec) -> Double { spec.capacityMl * unitsPerMl(spec.scale) }
public func graduationMl(_ spec: SyringeSpec) -> Double { spec.graduationUnits * mlPerUnit(spec.scale) }

/// Syringes people actually buy. There is no 0.4 mL U-100 barrel; a "40 unit
/// syringe" is most likely a 1 mL U-40 veterinary barrel.
public let SYRINGES: [SyringeSpec] = [
    SyringeSpec(id: "u100-0.3-half", scale: .u100, capacityMl: 0.3, graduationUnits: 0.5,
                label: "0.3 mL U-100, half-unit marks", note: "Finest resolution available. Best for doses under 15 units."),
    SyringeSpec(id: "u100-0.3", scale: .u100, capacityMl: 0.3, graduationUnits: 1, label: "0.3 mL U-100, 1-unit marks"),
    SyringeSpec(id: "u100-0.5", scale: .u100, capacityMl: 0.5, graduationUnits: 1,
                label: "0.5 mL U-100, 1-unit marks", note: "The usual choice for peptide volumes."),
    SyringeSpec(id: "u100-1.0", scale: .u100, capacityMl: 1.0, graduationUnits: 2, label: "1 mL U-100, 2-unit marks",
                note: "Most 1 mL barrels step in 2 units. Check yours before trusting odd numbers."),
    SyringeSpec(id: "u100-1.0-fine", scale: .u100, capacityMl: 1.0, graduationUnits: 1, label: "1 mL U-100, 1-unit marks"),
    SyringeSpec(id: "u40-1.0", scale: .u40, capacityMl: 1.0, graduationUnits: 1, label: "1 mL U-40, 1-unit marks",
                note: "Veterinary scale, numbered 0-40. One mark is 0.025 mL, not 0.01 mL."),
    SyringeSpec(id: "u40-0.5", scale: .u40, capacityMl: 0.5, graduationUnits: 1, label: "0.5 mL U-40, 1-unit marks",
                note: "Veterinary scale. One mark is 0.025 mL."),
]

public func syringeById(_ id: String?) -> SyringeSpec? {
    guard let id else { return nil }
    return SYRINGES.first { $0.id == id }
}

/// The barrel a recorded dose was drawn with: the named one, else this person's
/// default if it is on the same scale, else the first of that scale. nil when
/// the record says nothing about a syringe.
public func syringeForLog(syringeId: String?, syringeScale: SyringeScale?, defaultId: String? = nil) -> SyringeSpec? {
    if let named = syringeById(syringeId) { return named }
    guard let scale = syringeScale else { return nil }
    if let preferred = syringeById(defaultId ?? ""), preferred.scale == scale { return preferred }
    return SYRINGES.first { $0.scale == scale }
}

public let MCG_PER_MG: Double = 1000
public func mgToMcg(_ mg: Double) -> Double { mg * MCG_PER_MG }
public func mcgToMg(_ mcg: Double) -> Double { mcg / MCG_PER_MG }

/// Draws below this many marks are not worth trusting.
public let MIN_RELIABLE_UNITS: Double = 5

/// Concentration of the reconstituted vial, mcg/mL. Displacement is ignored.
public func concentration(_ vialMcg: Double, _ diluentMl: Double) -> Double {
    guard vialMcg > 0, diluentMl > 0 else { return .nan }
    return vialMcg / diluentMl
}

public func doseVolumeMl(_ doseMcg: Double, _ concentrationMcgPerMl: Double) -> Double {
    guard doseMcg > 0, concentrationMcgPerMl > 0 else { return .nan }
    return doseMcg / concentrationMcgPerMl
}

public func mlToUnits(_ ml: Double, _ scale: SyringeScale) -> Double { ml * unitsPerMl(scale) }
public func unitsToMl(_ units: Double, _ scale: SyringeScale) -> Double { units / unitsPerMl(scale) }

/// The same liquid volume as it reads on two barrel scales.
public func convertBetweenScales(_ units: Double, _ from: SyringeScale, _ to: SyringeScale) -> Double {
    unitsToMl(units, from) * unitsPerMl(to)
}

/// Mass delivered by a single printed mark (per mark, not per unit).
public func mcgPerGraduation(_ concentrationMcgPerMl: Double, _ spec: SyringeSpec) -> Double {
    concentrationMcgPerMl * graduationMl(spec)
}

/// Mass in one barrel unit, whatever the mark spacing.
public func mcgPerUnitOfScale(_ concentrationMcgPerMl: Double, _ scale: SyringeScale) -> Double {
    concentrationMcgPerMl * mlPerUnit(scale)
}

public enum DrawWarning: String, Sendable {
    case exceedsBarrel = "exceeds-barrel"
    case belowGraduation = "below-graduation"
    case offGraduation = "off-graduation"
    case lowVolume = "low-volume"
    case exceedsVial = "exceeds-vial"
}

public struct DrawResult: Equatable, Sendable {
    public var concentrationMcgPerMl: Double
    public var concentrationMgPerMl: Double
    /// Exact volume to draw. The primary answer.
    public var volumeMl: Double
    public var units: Double
    public var unitsRounded: Double
    public var volumeRoundedMl: Double
    public var deliveredMcg: Double
    public var roundingErrorMcg: Double
    public var roundingErrorPercent: Double
    public var mlPerUnit: Double
    public var mcgPerGraduation: Double
    public var dosesPerVial: Double
    public var warnings: [DrawWarning]
    public var measurable: Bool
}

public func calculateDraw(vialMcg: Double, diluentMl: Double, doseMcg: Double, syringe: SyringeSpec) -> DrawResult {
    let conc = concentration(vialMcg, diluentMl)
    let volumeMl = doseVolumeMl(doseMcg, conc)
    let units = mlToUnits(volumeMl, syringe.scale)
    let gradMl = graduationMl(syringe)
    let volumeRoundedMl = jsRound(volumeMl / gradMl) * gradMl
    let unitsRounded = mlToUnits(volumeRoundedMl, syringe.scale)
    let deliveredMcg = volumeRoundedMl * conc

    var warnings: [DrawWarning] = []
    if volumeMl > syringe.capacityMl + 1e-9 { warnings.append(.exceedsBarrel) }
    if volumeMl > 0 && volumeMl < gradMl - 1e-12 { warnings.append(.belowGraduation) }
    else if abs(volumeMl - volumeRoundedMl) > 1e-9 { warnings.append(.offGraduation) }
    if units > 0 && units < MIN_RELIABLE_UNITS { warnings.append(.lowVolume) }
    if volumeMl > diluentMl + 1e-9 { warnings.append(.exceedsVial) }

    return DrawResult(
        concentrationMcgPerMl: conc,
        concentrationMgPerMl: conc / MCG_PER_MG,
        volumeMl: volumeMl,
        units: units,
        unitsRounded: unitsRounded,
        volumeRoundedMl: volumeRoundedMl,
        deliveredMcg: deliveredMcg,
        roundingErrorMcg: deliveredMcg - doseMcg,
        roundingErrorPercent: doseMcg > 0 ? ((deliveredMcg - doseMcg) / doseMcg) * 100 : 0,
        mlPerUnit: mlPerUnit(syringe.scale),
        mcgPerGraduation: mcgPerGraduation(conc, syringe),
        dosesPerVial: (vialMcg / doseMcg).rounded(.down),
        warnings: warnings,
        measurable: volumeMl.isFinite && !warnings.contains(.exceedsBarrel) && !warnings.contains(.belowGraduation)
    )
}

/// Mass sitting in a given number of barrel marks.
public func doseFromUnits(_ units: Double, _ concentrationMcgPerMl: Double, _ scale: SyringeScale) -> Double {
    guard units > 0, concentrationMcgPerMl > 0 else { return 0 }
    return unitsToMl(units, scale) * concentrationMcgPerMl
}

/// Marks a given mass occupies on the barrel.
public func unitsFromDose(_ doseMcg: Double, _ concentrationMcgPerMl: Double, _ scale: SyringeScale) -> Double {
    guard doseMcg > 0, concentrationMcgPerMl > 0 else { return 0 }
    return mlToUnits(doseVolumeMl(doseMcg, concentrationMcgPerMl), scale)
}

/// Diluent volume that makes a dose land on a chosen barrel reading.
public func diluentForTargetUnits(_ vialMcg: Double, _ doseMcg: Double, _ targetUnits: Double, _ scale: SyringeScale) -> Double {
    guard vialMcg > 0, doseMcg > 0, targetUnits > 0 else { return .nan }
    return (targetUnits * vialMcg) / (unitsPerMl(scale) * doseMcg)
}

/// Diluent volume that makes one mark represent a round mass.
public func diluentForMcgPerUnit(_ vialMcg: Double, _ targetMcgPerUnit: Double, _ spec: SyringeSpec) -> Double {
    guard vialMcg > 0, targetMcgPerUnit > 0 else { return .nan }
    return (vialMcg * graduationMl(spec)) / targetMcgPerUnit
}

public struct DiluentSuggestion: Equatable, Sendable {
    public var diluentMl: Double
    public var units: Double
    public var volumeMl: Double
    public var concentrationMgPerMl: Double
    public var mcgPerGraduation: Double
    public var landsOnMark: Bool
    public var score: Double
}

/// Reconstitution volumes worth offering, ranked by how cleanly the dose reads.
public func suggestDiluents(_ vialMcg: Double, _ doseMcg: Double, _ syringe: SyringeSpec,
                            candidates: [Double] = [0.5, 1, 1.5, 2, 2.5, 3, 4, 5]) -> [DiluentSuggestion] {
    guard vialMcg > 0, doseMcg > 0 else { return [] }
    let gradMl = graduationMl(syringe)
    return candidates.map { diluentMl -> DiluentSuggestion in
        let conc = concentration(vialMcg, diluentMl)
        let volumeMl = doseVolumeMl(doseMcg, conc)
        let units = mlToUnits(volumeMl, syringe.scale)
        let marks = volumeMl / gradMl
        let landsOnMark = abs(marks - jsRound(marks)) < 1e-9
        let fill = volumeMl / syringe.capacityMl
        var score = 0.0
        if landsOnMark { score += 5 }
        if units >= MIN_RELIABLE_UNITS { score += 3 } else { score -= 4 }
        if fill >= 0.15 && fill <= 0.85 { score += 2 }
        if volumeMl > syringe.capacityMl { score -= 20 }
        return DiluentSuggestion(diluentMl: diluentMl, units: units, volumeMl: volumeMl,
                                 concentrationMgPerMl: conc / MCG_PER_MG,
                                 mcgPerGraduation: mcgPerGraduation(conc, syringe),
                                 landsOnMark: landsOnMark, score: score)
    }
    .filter { $0.volumeMl <= syringe.capacityMl + 1e-9 }
    .stableSorted { $0.score != $1.score ? $0.score > $1.score : $0.diluentMl < $1.diluentMl }
}

public struct RemainingInVial: Equatable, Sendable {
    public var remainingMl: Double
    public var remainingMcg: Double
    public var fractionRemaining: Double
}

/// Solution left in a vial after some volume has been drawn out.
public func remainingInVial(_ vialMcg: Double, _ diluentMl: Double, _ drawnMl: Double) -> RemainingInVial {
    let conc = concentration(vialMcg, diluentMl)
    let remainingMl = max(0, diluentMl - drawnMl)
    return RemainingInVial(remainingMl: remainingMl,
                           remainingMcg: conc.isFinite ? remainingMl * conc : 0,
                           fractionRemaining: diluentMl > 0 ? remainingMl / diluentMl : 0)
}

/// CDC / USP <797> limit for a punctured multi-dose container. About the
/// container, not a statement that the peptide inside is still potent.
public let MULTI_DOSE_VIAL_BUD_DAYS: Double = 28

public func beyondUseDate(_ firstPunctureMs: Millis, days: Double = MULTI_DOSE_VIAL_BUD_DAYS) -> Millis {
    firstPunctureMs + days * DAY_MS
}
