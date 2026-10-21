import Foundation

// Port of src/lib/calc/rescue.ts. Noticing that records have gone, and putting
// them back. Never refuses a write; keeps the prior document aside when a write
// looks like an accident, and restores by union so nothing since is lost.

public enum RecordKey: String, CaseIterable, Sendable, Codable {
    case profiles, protocols, logs, vials, measurements, labs, checkIns, customPeptides, orders, diluents, compoundNotes
}

public typealias RecordCounts = [RecordKey: Int]

extension AppData {
    func count(_ key: RecordKey) -> Int {
        switch key {
        case .profiles: profiles.count
        case .protocols: protocols.count
        case .logs: logs.count
        case .vials: vials.count
        case .measurements: measurements.count
        case .labs: labs.count
        case .checkIns: checkIns.count
        case .customPeptides: customPeptides.count
        case .orders: orders.count
        case .diluents: diluents.count
        case .compoundNotes: compoundNotes.count
        }
    }
}

public func countRecords(_ doc: AppData?) -> RecordCounts {
    var out: RecordCounts = [:]
    for k in RecordKey.allCases { out[k] = doc?.count(k) ?? 0 }
    return out
}

public struct Loss: Equatable, Sendable, Codable {
    public var key: RecordKey
    public var from: Int
    public var to: Int
    public init(key: RecordKey, from: Int, to: Int) { self.key = key; self.from = from; self.to = to }
}

/// Which collections lost rows, and how many.
public func losses(_ before: RecordCounts, _ after: RecordCounts) -> [Loss] {
    RecordKey.allCases.compactMap { k in
        let b = before[k] ?? 0, a = after[k] ?? 0
        return a < b ? Loss(key: k, from: b, to: a) : nil
    }
}

/// A collection emptying, or losing most of itself (more than one row) at once.
public func isAlarming(_ loss: Loss) -> Bool {
    if loss.from == 0 { return false }
    if loss.to == 0 { return true }
    let gone = loss.from - loss.to
    return gone > 1 && Double(gone) / Double(loss.from) >= 0.5
}

public func alarmingLosses(_ before: RecordCounts, _ after: RecordCounts) -> [Loss] {
    losses(before, after).filter(isAlarming)
}

/// The rows kept aside, stored beside the document rather than inside it.
public struct Rescue: Equatable, Sendable {
    public var at: Millis
    public var losses: [Loss]
    public var document: AppData
    public init(at: Millis, losses: [Loss], document: AppData) { self.at = at; self.losses = losses; self.document = document }
}

private func union<T: Row>(_ live: [T], _ saved: [T]) -> [T] {
    let have = Set(live.map(\.id).filter { !$0.isEmpty })
    let missing = saved.filter { !$0.id.isEmpty && !have.contains($0.id) }
    return missing.isEmpty ? live : live + missing
}

/// Put missing rows back by id; rows the current document has win.
public func restoreLost(_ current: AppData, _ rescue: Rescue) -> AppData {
    var out = current
    let saved = rescue.document
    for loss in rescue.losses {
        switch loss.key {
        case .profiles: out.profiles = union(current.profiles, saved.profiles)
        case .protocols: out.protocols = union(current.protocols, saved.protocols)
        case .logs: out.logs = union(current.logs, saved.logs)
        case .vials: out.vials = union(current.vials, saved.vials)
        case .measurements: out.measurements = union(current.measurements, saved.measurements)
        case .labs: out.labs = union(current.labs, saved.labs)
        case .checkIns: out.checkIns = union(current.checkIns, saved.checkIns)
        case .customPeptides: out.customPeptides = union(current.customPeptides, saved.customPeptides)
        case .orders: out.orders = union(current.orders, saved.orders)
        case .diluents: out.diluents = union(current.diluents, saved.diluents)
        case .compoundNotes: out.compoundNotes = union(current.compoundNotes, saved.compoundNotes)
        }
    }
    return out
}

/// How many rows `restoreLost` would bring back, per collection (as gains).
public func recoverable(_ current: AppData, _ rescue: Rescue) -> [Loss] {
    let before = countRecords(current)
    let after = countRecords(restoreLost(current, rescue))
    return RecordKey.allCases.compactMap { k in
        (after[k] ?? 0) > (before[k] ?? 0) ? Loss(key: k, from: before[k] ?? 0, to: after[k] ?? 0) : nil
    }
}

public func lostCount(_ loss: Loss) -> Int { loss.from - loss.to }
