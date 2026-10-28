import Foundation

/// What has come out of one vial, and how long what is left would last.
public struct VialHistory: Equatable, Sendable {
    /// Doses taken from this vial, newest first. Skipped ones never draw anything.
    public var doses: [DoseLog]
    public var firstAt: Millis?
    public var lastAt: Millis?
    public var drawnMcg: Double
    public var remainingMcg: Double
    /// Average dose, in mcg.
    public var averageMcg: Double
    /// Days the rest would last at the current plan if nothing else were used; nil with no plan or nothing left.
    public var daysLeft: Double?
    /// When it would run out at that rate.
    public var emptyAt: Millis?
}

public func vialHistory(_ data: AppData, _ v: Vial, nowMs: Millis) -> VialHistory {
    let mine = data.mine
    let doses = mine.logs.filter { $0.vialId == v.id && !$0.isSkipped }.stableSorted { $0.at > $1.at }
    let remaining = vialRemainingMcg(v)
    let daily = mine.protocols.filter { $0.active && $0.peptideId == v.peptideId }.reduce(0) { $0 + scheduledDailyMcg($1, nowMs) }
    let usable = v.state == .sealed || v.state == .reconstituted
    let days: Double? = usable && daily > 0 && remaining > 0 ? remaining / daily : nil
    return VialHistory(
        doses: doses, firstAt: doses.last?.at, lastAt: doses.first?.at,
        drawnMcg: doses.reduce(0) { $0 + $1.doseMcg }, remainingMcg: remaining,
        averageMcg: doses.isEmpty ? 0 : doses.reduce(0) { $0 + $1.doseMcg } / Double(doses.count),
        daysLeft: days, emptyAt: days.map { nowMs + $0 * DAY_MS })
}
