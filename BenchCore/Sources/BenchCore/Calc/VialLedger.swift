import Foundation

// A vial's amount drawn is worked out from the doses logged against it, plus a starting
// amount for whatever the logs do not explain (a vial already in use when it was added,
// a correction to "amount left", an import).
//
//     drawn = start + the sum of its logged doses
//
// The stored `drawnMcg` stays, as a cache every screen reads and the web and Android apps
// understand. What it no longer is, is the thing two devices fight over: each dose is its
// own record, so after a sync merge both are there, and every device recomputes the same
// total from them. A running total on the vial itself would have kept only the last
// writer's.

extension Vial {
    /// iOS only, in `extra`: the part of the amount drawn that no logged dose accounts for.
    public var drawnStart: Double? {
        get { extra["iosDrawnStart"]?.numberValue }
        set { if let newValue { extra["iosDrawnStart"] = .number(newValue) } else { extra.removeValue(forKey: "iosDrawnStart") } }
    }
}

extension AppData {
    /// Mass logged against each vial: doses that took something from it, and no others.
    func loggedDrawByVial() -> [String: Double] {
        var out: [String: Double] = [:]
        for l in logs {
            let c = Consumption(l)
            if c.consumes, let id = c.vialId { out[id, default: 0] += c.doseMcg }
        }
        return out
    }

    /// After a change made here: whatever moved a vial's drawn total that its doses do not
    /// explain becomes its starting amount. A vial emptied to capacity is left alone, since
    /// the total stopped following the doses there.
    public mutating func settleDrawnStarts() {
        let logged = loggedDrawByVial()
        for i in vials.indices {
            let v = vials[i]
            let drawn = v.drawnMcg ?? 0
            if v.drawnStart != nil, drawn >= vialCapacityMcg(v) - 1e-6 { continue }
            let implied = drawn - (logged[v.id] ?? 0)
            if v.drawnStart.map({ abs($0 - implied) > 1e-6 }) ?? true { vials[i].drawnStart = implied }
        }
    }

    /// After reading from storage, which may hold the result of a merge: the drawn total
    /// follows the doses, and a vial they have emptied is finished. A vial with no starting
    /// amount yet (older data, or from another app) is given the one that keeps its total.
    @discardableResult
    public mutating func reconcileDrawn() -> Bool {
        let logged = loggedDrawByVial()
        var changed = false
        for i in vials.indices {
            let v = vials[i]
            let sum = logged[v.id] ?? 0
            guard let start = v.drawnStart else {
                vials[i].drawnStart = (v.drawnMcg ?? 0) - sum
                changed = true
                continue
            }
            let cap = vialCapacityMcg(v)
            let expected = min(cap, max(0, start + sum))
            if abs((v.drawnMcg ?? 0) - expected) > 1e-6 { vials[i].drawnMcg = expected; changed = true }
            if cap > 0, expected >= cap - 1e-6, [VialState.sealed, .reconstituted].contains(v.state) {
                vials[i].state = .finished; changed = true
            }
        }
        return changed
    }
}
