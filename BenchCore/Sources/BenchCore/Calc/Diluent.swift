import Foundation

// Port of src/lib/calc/diluent.ts. Bottles of water, in millilitres, kept apart
// from `Vial` so no mass-based figure can ever count one.

public let OPEN_BOTTLE_STATES: [BottleState] = [.open]
private let DEAD_BOTTLE_STATES: [BottleState] = [.finished, .discarded]

public func bottleRemainingMl(_ b: DiluentBottle) -> Double { max(0, b.volumeMl - (b.drawnMl ?? 0)) }

public func bottleFractionRemaining(_ b: DiluentBottle) -> Double {
    b.volumeMl > 0 ? bottleRemainingMl(b) / b.volumeMl : 0
}

/// Past its beyond-use date, or past the printed date while still sealed.
public func bottleExpired(_ b: DiluentBottle, _ nowMs: Millis) -> Bool {
    if let bud = b.budAt, bud < nowMs { return true }
    if b.state == .sealed, let exp = b.expiresAt, exp < nowMs { return true }
    return false
}

public func bottleUsable(_ b: DiluentBottle, _ nowMs: Millis) -> Bool {
    !DEAD_BOTTLE_STATES.contains(b.state) && !bottleExpired(b, nowMs) && bottleRemainingMl(b) > 0
}

private func bottleDeadline(_ b: DiluentBottle) -> Double { b.budAt ?? b.expiresAt ?? .infinity }

/// Which bottle to suggest: open before sealed, enough before not, soonest deadline first.
public func pickBottle(_ bottles: [DiluentBottle], _ kind: DiluentKind, _ ml: Double, _ nowMs: Millis) -> DiluentBottle? {
    let candidates = bottles.filter { $0.kind == kind && bottleUsable($0, nowMs) }
    if candidates.isEmpty { return nil }
    let byDeadline: (DiluentBottle, DiluentBottle) -> Bool = { bottleDeadline($0) < bottleDeadline($1) }
    let open = candidates.filter { OPEN_BOTTLE_STATES.contains($0.state) }
    let enough = open.filter { bottleRemainingMl($0) >= ml - 1e-9 }
    if !enough.isEmpty { return enough.stableSorted(by: byDeadline).first }
    if !open.isEmpty { return open.stableSorted(by: byDeadline).first }
    return candidates.stableSorted(by: byDeadline).first
}

/// The shelf in the order a person would reach along it (the same preference as `pickBottle`).
public func shelfOrder(_ bottles: [DiluentBottle], _ nowMs: Millis) -> [DiluentBottle] {
    let rank: (DiluentBottle) -> Int = { b in
        if !bottleUsable(b, nowMs) { return 2 }
        return OPEN_BOTTLE_STATES.contains(b.state) ? 0 : 1
    }
    return bottles.stableSorted { a, b in
        if rank(a) != rank(b) { return rank(a) < rank(b) }
        let da = bottleDeadline(a), db = bottleDeadline(b)
        if da != db { return da < db }
        return a.id.localizedCompare(b.id) == .orderedAscending
    }
}

public struct ShelfRow: Equatable, Sendable, Identifiable {
    public var key: String
    /// The one the buttons act on.
    public var bottle: DiluentBottle
    public var bottles: [DiluentBottle]
    public var count: Int
    public var id: String { key }
}

/// The shelf as rows; only sealed, usable bottles of one kind and size collapse.
public func shelfRows(_ bottles: [DiluentBottle], _ nowMs: Millis, grouped: Bool) -> [ShelfRow] {
    let ordered = shelfOrder(bottles, nowMs)
    if !grouped { return ordered.map { ShelfRow(key: $0.id, bottle: $0, bottles: [$0], count: 1) } }
    var rows: [ShelfRow] = []
    var index: [String: Int] = [:]
    for b in ordered {
        guard b.state == .sealed && bottleUsable(b, nowMs) else {
            rows.append(ShelfRow(key: b.id, bottle: b, bottles: [b], count: 1))
            continue
        }
        let key = "\(b.kind.rawValue):\(jsNumberString(b.volumeMl))"
        if let i = index[key] {
            rows[i].bottles.append(b); rows[i].count += 1
        } else {
            index[key] = rows.count
            rows.append(ShelfRow(key: key, bottle: b, bottles: [b], count: 1))
        }
    }
    return rows
}

/// Open a bottle without taking anything out; its 28-day clock starts now.
public func openBottle(_ bottles: [DiluentBottle], _ id: String, _ nowMs: Millis) -> [DiluentBottle] {
    bottles.map { b in
        guard b.id == id, b.state == .sealed else { return b }
        var out = b
        out.state = .open; out.openedAt = nowMs; out.budAt = beyondUseDate(nowMs)
        return out
    }
}

/// Take water out; opens a sealed bottle, finishes an emptied one, never past empty.
public func drawFromBottle(_ bottles: [DiluentBottle], _ id: String, _ ml: Double, _ nowMs: Millis) -> [DiluentBottle] {
    guard ml > 0 else { return bottles }
    return bottles.map { b in
        guard b.id == id else { return b }
        var out = b
        let drawnMl = min(b.volumeMl, (b.drawnMl ?? 0) + ml)
        let emptied = drawnMl >= b.volumeMl - 1e-9
        let wasSealed = b.state == .sealed
        out.drawnMl = drawnMl
        out.openedAt = b.openedAt ?? (wasSealed ? nowMs : nil)
        out.budAt = b.budAt ?? (wasSealed ? beyondUseDate(nowMs) : nil)
        out.state = emptied && b.state != .discarded ? .finished : (wasSealed ? .open : b.state)
        return out
    }
}

/// Put water back, for when a reconstitution is corrected or undone.
public func returnToBottle(_ bottles: [DiluentBottle], _ id: String, _ ml: Double) -> [DiluentBottle] {
    guard ml > 0 else { return bottles }
    return bottles.map { b in
        guard b.id == id else { return b }
        var out = b
        let drawnMl = max(0, (b.drawnMl ?? 0) - ml)
        out.drawnMl = drawnMl
        if b.state == .finished && drawnMl < b.volumeMl - 1e-9 { out.state = .open }
        return out
    }
}

public struct DiluentStock: Equatable, Sendable {
    public var remainingMl: Double
    public var bottles: Int
    public var openBottles: Int
}

/// What is on the shelf of one kind of water.
public func diluentStock(_ bottles: [DiluentBottle], _ kind: DiluentKind, _ nowMs: Millis) -> DiluentStock {
    let usable = bottles.filter { $0.kind == kind && bottleUsable($0, nowMs) }
    return DiluentStock(remainingMl: usable.reduce(0) { $0 + bottleRemainingMl($1) }, bottles: usable.count,
                        openBottles: usable.filter { OPEN_BOTTLE_STATES.contains($0.state) }.count)
}
