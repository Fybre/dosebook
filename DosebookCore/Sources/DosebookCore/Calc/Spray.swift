import Foundation

// Port of src/lib/calc/spray.ts. A spray bottle is a `Vial` with
// `container: "spray"`. No beyond-use date is ever asserted for one, and
// presses remaining is an estimate and is named as one.

/// What a pump delivers when nobody has measured it.
public let DEFAULT_ML_PER_SPRAY: Double = 0.1

public let MEASURE_A_PRESS = "Pull the plunger out of a syringe and spray once into the open barrel. What collects is what one press delivers. Cheap bottles vary, calibrated ones state it on the box."

public func isSpray(_ v: Vial) -> Bool { v.container == .spray }

/// The volume one press delivers, falling back to the usual pump.
public func mlPerSpray(_ v: Vial) -> Double {
    if let ml = v.mlPerSpray, ml.isFinite, ml > 0 { return ml }
    return DEFAULT_ML_PER_SPRAY
}

/// The mass one press delivers; zero when the bottle has no volume recorded.
public func mcgPerSpray(_ v: Vial) -> Double {
    let perMl = vialConcentration(v)
    return perMl > 0 ? perMl * mlPerSpray(v) : 0
}

public func mcgForSprays(_ v: Vial, _ sprays: Double) -> Double { mcgPerSpray(v) * max(0, sprays) }
public func mlForSprays(_ v: Vial, _ sprays: Double) -> Double { mlPerSpray(v) * max(0, sprays) }

/// Whole presses for a dose (rounded: half a press is a failed dose).
public func spraysForDose(_ v: Vial, _ doseMcg: Double) -> Double {
    let per = mcgPerSpray(v)
    return per > 0 ? max(0, jsRound(doseMcg / per)) : 0
}

/// Roughly how many presses are left. Floored; will read high.
public func spraysRemaining(_ v: Vial) -> Double {
    let ml = vialRemainingMl(v)
    return ml > 0 ? (ml / mlPerSpray(v)).rounded(.down) : 0
}

public struct TransferPlan: Equatable, Sendable {
    /// The vial, emptied and closed.
    public var source: Vial
    /// The bottle as it should be created; `id` and `profileId` are left empty for the caller.
    public var bottle: Vial
    /// Saline that has to come out of tracked stock, if a bottle was named.
    public var drawnMl: Double
}

/// Empty a made-up vial into a pump bottle and make it up with more saline.
/// The mass and the money move whole; the order stays behind; no BUD is set.
public func transferToSpray(_ source: Vial, addedMl: Double, mlPerSpray: Double, diluent: DiluentKind? = nil,
                            diluentBottleId: String? = nil, atMs: Millis) -> TransferPlan? {
    let remainingMcg = vialRemainingMcg(source)
    guard remainingMcg > 0 else { return nil }
    let carriedMl = vialRemainingMl(source)
    let added = max(0, addedMl)
    let totalMl = carriedMl + added
    guard totalMl > 0 else { return nil }

    var bottle = Vial(id: "", profileId: "", peptideId: source.peptideId, strengthMg: remainingMcg / MCG_PER_MG,
                      state: .reconstituted)
    bottle.container = .spray
    bottle.mlPerSpray = mlPerSpray > 0 ? mlPerSpray : DEFAULT_ML_PER_SPRAY
    bottle.diluentMl = totalMl
    bottle.diluent = diluent ?? source.diluent
    bottle.diluentBottleId = diluentBottleId
    bottle.drawnMcg = 0
    bottle.reconstitutedAt = atMs
    bottle.filledFromVialId = source.id
    bottle.supplier = source.supplier
    bottle.lot = source.lot
    bottle.cost = source.cost
    bottle.currency = source.currency
    bottle.acquiredAt = source.acquiredAt
    bottle.notes = source.notes

    var emptied = source
    emptied.drawnMcg = (source.drawnMcg ?? 0) + remainingMcg
    emptied.state = .finished
    emptied.cost = nil

    return TransferPlan(source: emptied, bottle: bottle, drawnMl: (diluentBottleId ?? "").isEmpty ? 0 : added)
}

/// The saline a transfer will use: only what is added afterwards.
public func salineForTransfer(_ addedMl: Double) -> Double { max(0, addedMl) }

/// The routes a person can record: the library's, plus intranasal once a bottle
/// of the compound exists, plus oral for a tablet.
public func routeChoices(_ declared: [Route], _ vials: [Vial], _ peptideId: String, _ preparation: Preparation? = nil) -> [Route] {
    let hasSpray = vials.contains { $0.peptideId == peptideId && isSpray($0) }
    var out = declared.isEmpty ? [Route.subcutaneous] : declared
    if hasSpray && !out.contains(.intranasal) { out.append(.intranasal) }
    if preparation == .tablet && !out.contains(.oral) { out.append(.oral) }
    return out
}

/// The route a dose starts on when no protocol says.
public func defaultRoute(_ preparation: Preparation?, _ onlySpray: Bool) -> Route {
    if onlySpray { return .intranasal }
    return preparation == .tablet ? .oral : .subcutaneous
}
