import Foundation

// Port of src/lib/migrate.ts.
//
// The guarantee: updating the app never costs anyone a record, and restored
// records are *visible*. Every screen filters by `profileId`, so a row with no
// owner, or an owner that no longer exists, is adopted rather than left unseen.
//
// Shared by persistence (loading this device's own store) and import (restoring
// a backup). Every step checks the data rather than trusting `version`, and
// running it twice gives the same result as running it once.

/// Migrate a raw payload from any version.
public func migrateAppData(_ value: JSONValue?) -> AppData {
    guard let raw = value?.objectValue else { return AppData() }
    return migrateAppData(AppData(json: raw, fillDefaults: false), rawSettings: raw["settings"] != nil)
}

/// Migrate an already-decoded document (idempotent).
public func migrateAppData(_ data: AppData) -> AppData {
    migrateAppData(data, rawSettings: true)
}

func migrateAppData(_ input: AppData, rawSettings _: Bool) -> AppData {
    var data = input
    let logs = data.logs

    // v3: profiles. Everything that existed before belonged to one person.
    let profiles = data.profiles.isEmpty ? [DEFAULT_PROFILE] : data.profiles
    let ownerId = !data.activeProfileId.isEmpty && profiles.contains { $0.id == data.activeProfileId }
        ? data.activeProfileId
        : profiles[0].id
    let live = Set(profiles.map(\.id))
    func own<T: Owned>(_ rows: [T]) -> [T] {
        rows.map { r in
            guard isOrphaned(r.ownerId, live) else { return r }
            var copy = r
            copy.ownerId = ownerId
            return copy
        }
    }

    // v2: vial consumption measured as mass, not volume. v1's `drawnMl` is not a
    // field of the current type, so it arrives in `extra`.
    let vials = data.vials.map { v -> Vial in
        if v.drawnMcg != nil { return v }
        var out = v
        if let drawnMl = v.extra["drawnMl"]?.numberValue, let diluentMl = v.diluentMl, diluentMl != 0 {
            let conc = vialCapacityMcg(v) / diluentMl
            out.drawnMcg = min(vialCapacityMcg(v), drawnMl * conc)
            return out
        }
        // No volume recorded: rebuild consumption from the dose history instead.
        let logged = logs.filter { $0.vialId == v.id && !$0.isSkipped }.reduce(0) { $0 + $1.doseMcg }
        out.drawnMcg = min(vialCapacityMcg(v), logged)
        return out
    }

    data.version = DATA_VERSION
    data.profiles = profiles
    data.activeProfileId = ownerId
    data.protocols = own(data.protocols)
    data.logs = own(logs).stableSorted { $0.at > $1.at }
    data.vials = own(vials)
    data.measurements = own(data.measurements).stableSorted { $0.at > $1.at }
    data.labs = own(data.labs).stableSorted { $0.at > $1.at }
    data.checkIns = dedupeByDay(own(data.checkIns))
    // Settings defaults are filled field by field when decoding (Settings.init(from:)).
    if data.settings.reminders == nil { data.settings.reminders = DEFAULT_REMINDERS }
    data.halfLifeOverrides = saneOverrides(data.halfLifeOverrides)
    data.orders = saneOrders(own(data.orders))
    data.diluents = saneBottles(own(data.diluents))
    data.compoundNotes = dedupeByCompound(own(data.compoundNotes))
    return data
}

/// A row that belongs to a profile. `CompoundNote.profileId` is optional in the type.
protocol Owned {
    var ownerId: String? { get set }
}

extension DoseProtocol: Owned { var ownerId: String? { get { profileId } set { profileId = newValue ?? "" } } }
extension DoseLog: Owned { var ownerId: String? { get { profileId } set { profileId = newValue ?? "" } } }
extension Vial: Owned { var ownerId: String? { get { profileId } set { profileId = newValue ?? "" } } }
extension BodyMeasurement: Owned { var ownerId: String? { get { profileId } set { profileId = newValue ?? "" } } }
extension LabResult: Owned { var ownerId: String? { get { profileId } set { profileId = newValue ?? "" } } }
extension CheckIn: Owned { var ownerId: String? { get { profileId } set { profileId = newValue ?? "" } } }
extension Order: Owned { var ownerId: String? { get { profileId } set { profileId = newValue ?? "" } } }
extension DiluentBottle: Owned { var ownerId: String? { get { profileId } set { profileId = newValue ?? "" } } }
extension CompoundNote: Owned { var ownerId: String? { get { profileId } set { profileId = newValue } } }

/// Keep only overrides that could produce a curve.
func saneOverrides(_ raw: [String: HalfLifeOverride]) -> [String: HalfLifeOverride] {
    var out: [String: HalfLifeOverride] = [:]
    for (id, value) in raw {
        guard value.hours.isFinite, value.hours > 0 else { continue }
        out[id] = HalfLifeOverride(hours: value.hours, setAt: value.setAt.isFinite ? value.setAt : nowMillis(), note: value.note)
    }
    return out
}

/// Keep only bottles that could hold anything.
func saneBottles(_ rows: [DiluentBottle]) -> [DiluentBottle] {
    rows.filter { !$0.id.isEmpty && $0.volumeMl.isFinite && $0.volumeMl > 0 }
}

/// Keep the orders that are orders, dropping a shipping figure that is not one.
func saneOrders(_ rows: [Order]) -> [Order] {
    rows.filter { !$0.id.isEmpty }.map { o in
        guard let cost = o.shippingCost, cost.isFinite, cost > 0 else {
            var copy = o
            copy.shippingCost = nil
            return copy
        }
        return o
    }
}

/// At most one note per profile per compound, newest kept; empty notes dropped.
func dedupeByCompound(_ rows: [CompoundNote]) -> [CompoundNote] {
    var byCompound: [String: CompoundNote] = [:]
    var order: [String] = []
    for row in rows {
        guard !row.peptideId.isEmpty, !row.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { continue }
        let at = row.updatedAt.isFinite ? row.updatedAt : 0
        let key = "\(row.profileId ?? "undefined"):\(row.peptideId)"
        if let seen = byCompound[key] {
            if at >= seen.updatedAt { var r = row; r.updatedAt = at; byCompound[key] = r }
        } else {
            var r = row; r.updatedAt = at; byCompound[key] = r; order.append(key)
        }
    }
    return order.compactMap { byCompound[$0] }.stableSorted { $0.updatedAt > $1.updatedAt }
}

/// At most one check-in per profile per day, newest kept, stamped at local midnight.
func dedupeByDay(_ rows: [CheckIn]) -> [CheckIn] {
    var byDay: [String: CheckIn] = [:]
    var order: [String] = []
    for row in rows {
        let day = startOfLocalDay(row.at)
        let key = "\(row.profileId):\(day)"
        if let seen = byDay[key] {
            if row.at >= seen.at { var r = row; r.at = day; byDay[key] = r }
        } else {
            var r = row; r.at = day; byDay[key] = r; order.append(key)
        }
    }
    return order.compactMap { byDay[$0] }.stableSorted { $0.at > $1.at }
}

/// Whether a payload looks like one of this app's exports at all. Deliberately loose.
public func looksLikeAppData(_ value: JSONValue) -> Bool {
    value["logs"]?.arrayValue != nil && value["protocols"]?.arrayValue != nil
}

extension Array {
    /// JS `Array.prototype.sort` is stable; Swift's `sorted` is not guaranteed to be.
    public func stableSorted(by areInIncreasingOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if areInIncreasingOrder(a.element, b.element) { return true }
            if areInIncreasingOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}
