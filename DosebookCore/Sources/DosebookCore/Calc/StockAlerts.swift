import Foundation

/// What "running low" is counted in.
public enum LowStockUnit: String, Codable, Sendable { case doses, days }

extension Settings {
    /// iOS only, in `extra`: whether the low-stock line is in doses (the original's) or days left.
    public var lowStockUnit: LowStockUnit {
        get { extra["iosLowStockUnit"]?.stringValue.flatMap(LowStockUnit.init(rawValue:)) ?? .doses }
        set { if newValue == .doses { extra.removeValue(forKey: "iosLowStockUnit") } else { extra["iosLowStockUnit"] = .string(newValue.rawValue) } }
    }

    /// The warning point when counting in days.
    public var lowStockDays: Double {
        get { extra["iosLowStockDays"]?.numberValue ?? 7 }
        set { extra["iosLowStockDays"] = .number(newValue) }
    }

    /// A notification when stock runs low. On unless turned off; it still needs reminders switched on.
    public var lowStockNotify: Bool {
        get { if case .bool(let b)? = extra["iosLowStockNotify"] { b } else { true } }
        set { extra["iosLowStockNotify"] = .bool(newValue) }
    }

    /// A notification when a vial is used up.
    public var emptyVialNotify: Bool {
        get { if case .bool(let b)? = extra["iosEmptyVialNotify"] { b } else { true } }
        set { extra["iosEmptyVialNotify"] = .bool(newValue) }
    }
}

/// Whether a compound's stock is at or under the warning point.
public func stockIsLow(_ stock: Stock, supplyDays: Double?, _ settings: Settings) -> Bool {
    switch settings.lowStockUnit {
    case .doses: stock.dosesRemaining <= settings.lowStockDoses
    case .days: stock.dosesRemaining <= 0 || (supplyDays.map { $0 <= settings.lowStockDays } ?? false)
    }
}

/// A "running low" notification to send, worked out from the plan.
public struct LowStockAlert: Equatable, Sendable {
    public var peptideId: String
    public var name: String
    /// When to send it.
    public var fireAt: Millis
    /// Already at or under the warning point now, not just heading there.
    public var lowNow: Bool
    public var dosesLeft: Double
}

/// The hour low-stock notices go out, so one never lands in the night.
public let LOW_STOCK_HOUR = "09:00"

/// One alert per compound that is low, or will be: at 9am today or tomorrow if it
/// already is, and otherwise on the morning of the day the dose that takes it to the
/// warning point is due. Compounds with no vial at all are the "add a vial" prompt's business.
public func lowStockAlerts(_ data: AppData, nowMs: Millis) -> [LowStockAlert] {
    let mine = data.mine
    let settings = data.settings
    var out: [String: LowStockAlert] = [:]
    for p in mine.protocols where p.active && p.schedule.kind != .asNeeded {
        if let ended = p.endedAt, ended < nowMs { continue }
        guard mine.vials.contains(where: { $0.peptideId == p.peptideId }) else { continue }
        let peptide = data.peptide(p.peptideId)
        let target = scheduledDoseMcg(p, nowMs)
        guard target > 0 else { continue }
        let stock = stockFor(mine.vials, p.peptideId, target, nowMs, containerForDose(peptide?.preparation, p.route))
        let limit = settings.lowStockUnit == .doses ? settings.lowStockDoses : protocolDosesPerWeek(p, nowMs) * settings.lowStockDays / 7
        let name = peptide?.name ?? p.peptideId
        let alert: LowStockAlert?
        if stock.dosesRemaining <= limit {
            alert = LowStockAlert(peptideId: p.peptideId, name: name, fireAt: nextHour(nowMs), lowNow: true, dosesLeft: stock.dosesRemaining)
        } else {
            var left = stock.availableMcg
            var found: LowStockAlert?
            for at in protocolDoseTimesBetween(p, nowMs, nowMs + 730 * DAY_MS) {
                let dose = scheduledDoseMcg(p, at)
                guard dose > 0 else { continue }
                left -= dose
                let remaining = (left / dose).rounded(.down)
                if remaining <= limit {
                    let morning = atTimeOfDay(startOfLocalDay(at), LOW_STOCK_HOUR)
                    let fire = morning > nowMs ? morning : max(at + 10 * 60_000, nowMs + 60_000)
                    found = LowStockAlert(peptideId: p.peptideId, name: name, fireAt: fire, lowNow: false, dosesLeft: max(0, remaining))
                    break
                }
            }
            alert = found
        }
        if let alert, out[p.peptideId].map({ alert.fireAt < $0.fireAt }) ?? true { out[p.peptideId] = alert }
    }
    return out.values.sorted { $0.fireAt != $1.fireAt ? $0.fireAt < $1.fireAt : $0.name < $1.name }
}

/// The next 9am after now.
private func nextHour(_ nowMs: Millis) -> Millis {
    let today = atTimeOfDay(startOfLocalDay(nowMs), LOW_STOCK_HOUR)
    return today > nowMs ? today : atTimeOfDay(addLocalDays(startOfLocalDay(nowMs), 1), LOW_STOCK_HOUR)
}

/// A vial that has been used up by doses, as opposed to one marked finished by hand.
public func vialUsedUp(_ v: Vial) -> Bool {
    v.state == .finished && (v.drawnMcg ?? 0) > 0 && vialRemainingMcg(v) <= 0
}

/// How many more of this compound's containers are in stock and usable, for the empty-vial notice.
public func vialsLeftInStock(_ data: AppData, like v: Vial, nowMs: Millis) -> Int {
    data.mine.vials.filter { $0.id != v.id && $0.peptideId == v.peptideId && matchesContainer($0, v.containerKind) && vialUsable($0, nowMs) }.count
}
