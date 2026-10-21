import Foundation

// Port of src/lib/calc/inventory.ts.
//
// Consumption is tracked in MICROGRAMS. Volume only exists once a vial is
// reconstituted, but a dose has a mass whatever state the vial is in.

/// Nominal mass the vial was labelled with.
public func vialCapacityMcg(_ v: Vial) -> Double { v.strengthMg * MCG_PER_MG }

/// Mass still in the vial.
public func vialRemainingMcg(_ v: Vial) -> Double { max(0, vialCapacityMcg(v) - (v.drawnMcg ?? 0)) }

public func vialFractionRemaining(_ v: Vial) -> Double {
    let cap = vialCapacityMcg(v)
    return cap > 0 ? vialRemainingMcg(v) / cap : 0
}

/// Concentration of a reconstituted vial, mcg/mL. NaN before reconstitution.
public func vialConcentration(_ v: Vial) -> Double {
    guard let d = v.diluentMl, d > 0 else { return .nan }
    return vialCapacityMcg(v) / d
}

/// Solution left, in millilitres. Zero for a sealed vial.
public func vialRemainingMl(_ v: Vial) -> Double {
    let conc = vialConcentration(v)
    guard conc.isFinite else { return 0 }
    return vialRemainingMcg(v) / conc
}

private let DEAD_STATES: [VialState] = [.finished, .discarded]
/// States that hold no drug you can reach today.
private let UNAVAILABLE_STATES: [VialState] = DEAD_STATES + [.onOrder]

public func vialUnavailableState(_ v: Vial) -> Bool { UNAVAILABLE_STATES.contains(v.state) }

/// Past its beyond-use date, or past the manufacturer's date while sealed.
public func vialExpired(_ v: Vial, _ nowMs: Millis) -> Bool {
    if let bud = v.budAt, bud < nowMs { return true }
    if v.state == .sealed, let exp = v.expiresAt, exp < nowMs { return true }
    return false
}

/// A vial that can still supply a dose.
public func vialUsable(_ v: Vial, _ nowMs: Millis) -> Bool {
    !UNAVAILABLE_STATES.contains(v.state) && !vialExpired(v, nowMs) && vialRemainingMcg(v) > 0
}

public func matchesContainer(_ v: Vial, _ want: ContainerKind = .vial) -> Bool {
    v.containerKind == want
}

/// Which container a dose of this compound comes out of. Route first, then preparation.
public func containerForDose(_ preparation: Preparation?, _ route: Route) -> ContainerKind {
    if route == .intranasal { return .spray }
    return preparation == .tablet ? .pack : .vial
}

/// Every container this dose could honestly come out of. An open vial past its
/// date is still offered; a sealed one past its date is not.
public func drawableVials(_ vials: [Vial], _ peptideId: String, _ nowMs: Millis, _ container: ContainerKind = .vial) -> [Vial] {
    vials.filter { v in
        v.peptideId == peptideId && matchesContainer(v, container) && !UNAVAILABLE_STATES.contains(v.state)
            && vialRemainingMcg(v) > 0 && (!vialExpired(v, nowMs) || v.state == .reconstituted)
    }
}

private func deadline(_ v: Vial) -> Double { v.budAt ?? v.expiresAt ?? .infinity }

/// Which vial a dose should come out of: open before sealed, soonest deadline
/// first, and an open vial past its date ahead of every sealed one.
public func pickVialForDose(_ vials: [Vial], _ peptideId: String, _ doseMcg: Double, _ nowMs: Millis,
                            _ container: ContainerKind = .vial) -> Vial? {
    let candidates = drawableVials(vials, peptideId, nowMs, container)
    if candidates.isEmpty { return nil }
    let byDeadline: (Vial, Vial) -> Bool = { deadline($0) < deadline($1) }
    let inDate = candidates.filter { !vialExpired($0, nowMs) }
    let open = inDate.filter { $0.state == .reconstituted }
    let fullEnough = open.filter { vialRemainingMcg($0) >= doseMcg - 1e-6 }
    if !fullEnough.isEmpty { return fullEnough.stableSorted(by: byDeadline).first }
    if !open.isEmpty { return open.stableSorted(by: byDeadline).first }
    let openPast = candidates.filter { $0.state == .reconstituted && vialExpired($0, nowMs) }
    if !openPast.isEmpty {
        return openPast.stableSorted { ($0.budAt ?? $0.expiresAt ?? 0) > ($1.budAt ?? $1.expiresAt ?? 0) }.first
    }
    let sealed = inDate.filter { $0.state == .sealed }
    if !sealed.isEmpty { return sealed.stableSorted(by: byDeadline).first }
    return inDate.stableSorted(by: byDeadline).first
}

/// A pack that has been opened. "reconstituted" is the in-use state for every container.
public func openPack(_ v: Vial, _ atMs: Millis) -> Vial {
    var out = v
    out.state = .reconstituted
    out.reconstitutedAt = v.reconstitutedAt ?? atMs
    return out
}

/// Take mass out of a vial; never below empty, finished once empty. A sealed pack is opened.
public func drawFromVial(_ vials: [Vial], _ vialId: String, _ mcg: Double, _ atMs: Millis = nowMillis()) -> [Vial] {
    guard mcg > 0 else { return vials }
    return vials.map { v in
        guard v.id == vialId else { return v }
        let capacity = vialCapacityMcg(v)
        let drawnMcg = min(capacity, (v.drawnMcg ?? 0) + mcg)
        let emptied = drawnMcg >= capacity - 1e-6
        var opened = matchesContainer(v, .pack) && v.state == .sealed ? openPack(v, atMs) : v
        opened.drawnMcg = drawnMcg
        if emptied && v.state != .discarded { opened.state = .finished }
        return opened
    }
}

/// Put mass back, for when a logged dose is deleted. Reopens an auto-finished vial.
public func returnToVial(_ vials: [Vial], _ vialId: String, _ mcg: Double) -> [Vial] {
    guard mcg > 0 else { return vials }
    return vials.map { v in
        guard v.id == vialId else { return v }
        var out = v
        let drawnMcg = max(0, (v.drawnMcg ?? 0) - mcg)
        out.drawnMcg = drawnMcg
        if v.state == .finished && drawnMcg < vialCapacityMcg(v) - 1e-6 {
            out.state = ((v.diluentMl ?? 0) != 0 || matchesContainer(v, .pack)) ? .reconstituted : .sealed
        }
        return out
    }
}

/// What a logged dose takes out of stock.
public struct Consumption: Equatable, Sendable {
    public var vialId: String?
    public var doseMcg: Double
    public var skipped: Bool?
    public init(vialId: String?, doseMcg: Double, skipped: Bool? = nil) {
        self.vialId = vialId; self.doseMcg = doseMcg; self.skipped = skipped
    }
    public init(_ log: DoseLog) { self.init(vialId: log.vialId, doseMcg: log.doseMcg, skipped: log.skipped) }

    var consumes: Bool { skipped != true && !(vialId ?? "").isEmpty && doseMcg > 0 }
}

/// Undo the old draw, then apply the new one, so an edit on the same vial nets out.
public func reconcileVials(_ vials: [Vial], _ before: Consumption?, _ after: Consumption?) -> [Vial] {
    var out = vials
    if let b = before, b.consumes { out = returnToVial(out, b.vialId!, b.doseMcg) }
    if let a = after, a.consumes { out = drawFromVial(out, a.vialId!, a.doseMcg) }
    return out
}

// MARK: - Grouping identical vials

public struct VialGroup: Equatable, Sendable, Identifiable {
    public var key: String
    public var peptideId: String
    public var strengthMg: Double
    /// Oldest first.
    public var vials: [Vial]
    public var count: Int
    public var remainingMcg: Double
    public var expiresAt: Millis?
    /// nil when bought in more than one currency.
    public var cost: Double?
    public var currency: String?
    public var unpricedCount: Int
    /// Who it came from, when every vial agrees.
    public var supplier: String?
    public var id: String { key }
}

/// Collapse interchangeable (sealed) vials into one line each.
public func groupSealedVials(_ vials: [Vial]) -> [VialGroup] {
    groupVials(vials.filter { $0.state == .sealed }) { "\($0.peptideId):\(jsNumberString($0.strengthMg))" }
}

/// Stock in the post, grouped by the delivery it is coming in.
public func groupOnOrder(_ vials: [Vial]) -> [VialGroup] {
    groupVials(vials.filter { $0.state == .onOrder }) { "\($0.orderId ?? $0.id):\($0.peptideId):\(jsNumberString($0.strengthMg))" }
}

private func agreed(_ values: [String?]) -> String? {
    guard let first = values.first ?? nil, !first.isEmpty else { return nil }
    return values.allSatisfy { $0 == first } ? first : nil
}

private func groupVials(_ vials: [Vial], keyOf: (Vial) -> String) -> [VialGroup] {
    var order: [String] = []
    var bucket: [String: [Vial]] = [:]
    for v in vials {
        let key = keyOf(v)
        if bucket[key] == nil { bucket[key] = []; order.append(key) }
        bucket[key]!.append(v)
    }
    return order.map { key in
        let group = bucket[key]!.stableSorted { a, b in
            let da = a.acquiredAt ?? 0, db = b.acquiredAt ?? 0
            if da != db { return da < db }
            return a.id.localizedCompare(b.id) == .orderedAscending
        }
        let priced = group.filter { $0.cost != nil }
        let currencies = Set(priced.map { $0.currency ?? "" })
        let oneCurrency = currencies.count <= 1
        let expiries = group.compactMap(\.expiresAt)
        return VialGroup(
            key: key, peptideId: group[0].peptideId, strengthMg: group[0].strengthMg, vials: group,
            count: group.count, remainingMcg: group.reduce(0) { $0 + vialRemainingMcg($1) },
            expiresAt: expiries.min(),
            cost: !priced.isEmpty && oneCurrency ? priced.reduce(0) { $0 + $1.cost! } : nil,
            currency: !priced.isEmpty && oneCurrency ? priced[0].currency : nil,
            unpricedCount: group.count - priced.count,
            supplier: agreed(group.map(\.supplier))
        )
    }
}

public struct Stock: Equatable, Sendable {
    public var availableMcg: Double
    public var sealedCount: Int
    public var openCount: Int
    public var dosesRemaining: Double
    public var dosesInOpenVials: Double
    /// Stock exists but nothing has been made up, so no marks can be read.
    public var needsReconstitution: Bool
    /// Doses in vials excluded only because they are past a date.
    public var dosesExpired: Double
}

public func stockFor(_ vials: [Vial], _ peptideId: String, _ doseMcg: Double, _ nowMs: Millis,
                     _ container: ContainerKind = .vial) -> Stock {
    let mine = vials.filter { $0.peptideId == peptideId && matchesContainer($0, container) }
    let usable = mine.filter { vialUsable($0, nowMs) }
    let expiredMcg = mine
        .filter { !UNAVAILABLE_STATES.contains($0.state) && vialExpired($0, nowMs) && vialRemainingMcg($0) > 0 }
        .reduce(0) { $0 + vialRemainingMcg($1) }
    let openPastDate = mine.contains { $0.state == .reconstituted && vialExpired($0, nowMs) && vialRemainingMcg($0) > 0 }

    var availableMcg = 0.0, openMcg = 0.0
    var sealedCount = 0, openCount = 0
    for v in usable {
        let remaining = vialRemainingMcg(v)
        availableMcg += remaining
        if v.state == .reconstituted { openMcg += remaining; openCount += 1 }
        else if v.state == .sealed { sealedCount += 1 }
    }
    let per: (Double) -> Double = { doseMcg > 0 ? ($0 / doseMcg).rounded(.down) : 0 }
    return Stock(
        availableMcg: availableMcg, sealedCount: sealedCount, openCount: openCount,
        dosesRemaining: per(availableMcg), dosesInOpenVials: per(openMcg),
        needsReconstitution: container == .vial && openCount == 0 && sealedCount > 0 && !openPastDate,
        dosesExpired: per(expiredMcg)
    )
}

/// The barrel reading for a dose, from the vial it would come out of. Vials only.
public func marksForDose(_ vials: [Vial], _ peptideId: String, _ doseMcg: Double, _ scale: SyringeScale, _ nowMs: Millis) -> Double? {
    marksFromVial(pickVialForDose(vials, peptideId, doseMcg, nowMs, .vial), doseMcg, scale)
}

/// The same reading, for a vial already in hand. nil unless it has been made up.
public func marksFromVial(_ vial: Vial?, _ doseMcg: Double, _ scale: SyringeScale) -> Double? {
    guard let vial, vial.state == .reconstituted else { return nil }
    let conc = vialConcentration(vial)
    guard conc.isFinite, conc > 0 else { return nil }
    let units = unitsFromDose(doseMcg, conc, scale)
    return units > 0 ? units : nil
}

public func daysOfSupply(_ stock: Stock, _ dosesPerWeek: Double) -> Double? {
    guard dosesPerWeek > 0 else { return nil }
    return (stock.dosesRemaining / dosesPerWeek) * 7
}

/// Days of supply, spending the stock against the actual plan (titration included).
public func daysOfSupplyForProtocol(_ stock: Stock, _ p: DoseProtocol, _ nowMs: Millis, horizonDays: Double = 730) -> Double? {
    let times = protocolDoseTimesBetween(p, nowMs, nowMs + horizonDays * DAY_MS)
    if times.isEmpty { return nil }
    var left = stock.availableMcg
    for at in times {
        let dose = scheduledDoseMcg(p, at)
        if dose <= 0 { continue }
        if left < dose { return (at - nowMs) / DAY_MS }
        left -= dose
    }
    return horizonDays
}

public enum SupplyOutlook: Equatable, Sendable {
    case runsOut(at: Millis)
    case beyondHorizon
    case unknown
}

/// The same walk, reported as a date.
public func supplyOutlook(_ stock: Stock, _ p: DoseProtocol, _ nowMs: Millis, horizonDays: Double = 365) -> SupplyOutlook {
    if stock.availableMcg <= 0 { return .unknown }
    guard let days = daysOfSupplyForProtocol(stock, p, nowMs, horizonDays: horizonDays) else { return .unknown }
    if days >= horizonDays { return .beyondHorizon }
    return .runsOut(at: nowMs + days * DAY_MS)
}

/// The `diluentMl` that makes the existing formula right after topping up an
/// open vial: capacity × (remaining mL + added) / remaining mcg.
public func diluentAfterTopUp(_ v: Vial, _ addedMl: Double) -> Double? {
    guard addedMl.isFinite, addedMl > 0 else { return nil }
    let remainingMcg = vialRemainingMcg(v)
    guard remainingMcg > 0 else { return nil }
    let remainingMl = vialRemainingMl(v)
    guard remainingMl > 0 else { return nil }
    return vialCapacityMcg(v) * ((remainingMl + addedMl) / remainingMcg)
}
