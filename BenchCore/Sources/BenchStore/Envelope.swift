import Foundation
import BenchCore

// The document split into rows for storage, and put back together.
//
// Every row of every collection is one envelope: a kind, the row's own id, its
// owner, and its JSON exactly as a Bench export writes it (unknown fields
// included). CloudKit then syncs and resolves conflicts per row, last writer
// wins, and the domain schema can change without a CloudKit schema migration.

public enum EnvelopeKind: String, CaseIterable, Sendable {
    case profile, `protocol`, log, vial, measurement, lab, checkIn, customPeptide, order, diluent, compoundNote
    /// The settings singleton; recordId is always "settings".
    case settings
    /// One per compound; recordId is the peptide id.
    case halfLifeOverride
    /// A top-level field this build does not know; recordId is the key.
    case extra
    /// A row this build could not read; recordId is "collection#n".
    case raw
}

public struct EnvelopeKey: Hashable, Sendable {
    public var kind: String
    public var recordId: String
    public init(kind: String, recordId: String) { self.kind = kind; self.recordId = recordId }
}

public struct Envelope: Equatable, Sendable {
    public var kind: String
    public var recordId: String
    public var profileId: String?
    public var payload: Data
    public var updatedAt: Date
    public var key: EnvelopeKey { EnvelopeKey(kind: kind, recordId: recordId) }

    public init(kind: String, recordId: String, profileId: String?, payload: Data, updatedAt: Date) {
        self.kind = kind; self.recordId = recordId; self.profileId = profileId; self.payload = payload; self.updatedAt = updatedAt
    }
}

enum Codec {
    static let encoder: JSONEncoder = {
        let e = JSONEncoder()
        e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return e
    }()
}

/// What changed between two documents, as rows to write and rows to remove.
public struct EnvelopeDiff: Sendable {
    public var upserts: [Envelope] = []
    public var deletes: [EnvelopeKey] = []
    public var isEmpty: Bool { upserts.isEmpty && deletes.isEmpty }
}

private func rows<T: Row>(_ kind: EnvelopeKind, _ old: [T], _ new: [T], owner: (T) -> String?, at: Date, into diff: inout EnvelopeDiff) {
    var before: [String: T] = [:]
    for r in old { before[r.id] = r }
    var seen = Set<String>()
    for r in new {
        guard !seen.contains(r.id) else { continue }
        seen.insert(r.id)
        if before[r.id] == r { continue }
        if let data = try? r.lenientJSON(encoder: Codec.encoder) {
            diff.upserts.append(Envelope(kind: kind.rawValue, recordId: r.id, profileId: owner(r), payload: data, updatedAt: at))
        }
    }
    for id in before.keys where !seen.contains(id) { diff.deletes.append(EnvelopeKey(kind: kind.rawValue, recordId: id)) }
}

/// The rows that differ between `old` and `new`. Pass `AppData?.none` as old to write everything.
public func envelopeDiff(from old: AppData?, to new: AppData, at: Date = Date()) -> EnvelopeDiff {
    var d = EnvelopeDiff()
    let o = old ?? AppData.blankForDiff
    rows(.profile, o.profiles, new.profiles, owner: { _ in nil }, at: at, into: &d)
    rows(.protocol, o.protocols, new.protocols, owner: { $0.profileId }, at: at, into: &d)
    rows(.log, o.logs, new.logs, owner: { $0.profileId }, at: at, into: &d)
    rows(.vial, o.vials, new.vials, owner: { $0.profileId }, at: at, into: &d)
    rows(.measurement, o.measurements, new.measurements, owner: { $0.profileId }, at: at, into: &d)
    rows(.lab, o.labs, new.labs, owner: { $0.profileId }, at: at, into: &d)
    rows(.checkIn, o.checkIns, new.checkIns, owner: { $0.profileId }, at: at, into: &d)
    rows(.customPeptide, o.customPeptides, new.customPeptides, owner: { _ in nil }, at: at, into: &d)
    rows(.order, o.orders, new.orders, owner: { $0.profileId }, at: at, into: &d)
    rows(.diluent, o.diluents, new.diluents, owner: { $0.profileId }, at: at, into: &d)
    rows(.compoundNote, o.compoundNotes, new.compoundNotes, owner: { $0.profileId }, at: at, into: &d)

    if old == nil || o.settings != new.settings, let data = try? new.settings.lenientJSON(encoder: Codec.encoder) {
        d.upserts.append(Envelope(kind: EnvelopeKind.settings.rawValue, recordId: "settings", profileId: nil, payload: data, updatedAt: at))
    }
    for (id, value) in new.halfLifeOverrides where old == nil || o.halfLifeOverrides[id] != value {
        if let data = try? Codec.encoder.encode(value) {
            d.upserts.append(Envelope(kind: EnvelopeKind.halfLifeOverride.rawValue, recordId: id, profileId: nil, payload: data, updatedAt: at))
        }
    }
    for id in o.halfLifeOverrides.keys where new.halfLifeOverrides[id] == nil {
        d.deletes.append(EnvelopeKey(kind: EnvelopeKind.halfLifeOverride.rawValue, recordId: id))
    }
    for (k, value) in new.extra where old == nil || o.extra[k] != value {
        if let data = try? Codec.encoder.encode(value) {
            d.upserts.append(Envelope(kind: EnvelopeKind.extra.rawValue, recordId: k, profileId: nil, payload: data, updatedAt: at))
        }
    }
    for k in o.extra.keys where new.extra[k] == nil { d.deletes.append(EnvelopeKey(kind: EnvelopeKind.extra.rawValue, recordId: k)) }

    // Unreadable rows only change on import, so they are rewritten wholesale.
    if old == nil || o.unreadable != new.unreadable {
        for (collection, items) in o.unreadable {
            for i in items.indices { d.deletes.append(EnvelopeKey(kind: EnvelopeKind.raw.rawValue, recordId: "\(collection)#\(i)")) }
        }
        for (collection, items) in new.unreadable {
            for (i, item) in items.enumerated() {
                if let data = try? Codec.encoder.encode(item) {
                    d.upserts.append(Envelope(kind: EnvelopeKind.raw.rawValue, recordId: "\(collection)#\(i)", profileId: nil, payload: data, updatedAt: at))
                }
            }
        }
        let written = Set(d.upserts.map(\.key))
        d.deletes.removeAll { written.contains($0) }
    }
    return d
}

extension AppData {
    /// A document with nothing in it, so a first write sends every row.
    static var blankForDiff: AppData {
        var d = AppData()
        d.profiles = []
        return d
    }
}

/// Keep the newest of each (kind, recordId); report the rest so they can be deleted.
/// Two devices creating the same singleton, or the default profile "me", produce these.
public func dedupe(_ envelopes: [Envelope]) -> (kept: [Envelope], duplicates: [Envelope]) {
    var best: [EnvelopeKey: Envelope] = [:]
    var dupes: [Envelope] = []
    for e in envelopes {
        if let seen = best[e.key] {
            if e.updatedAt > seen.updatedAt { dupes.append(seen); best[e.key] = e } else { dupes.append(e) }
        } else {
            best[e.key] = e
        }
    }
    return (Array(best.values), dupes)
}

/// Rebuild the document from stored rows, then migrate it, exactly as an import would be.
/// `activeProfileId` is per device and passed in.
public func document(from envelopes: [Envelope], activeProfileId: String?) -> AppData {
    var obj: JSONObject = [:]
    var collections: [String: [JSONValue]] = [:]
    let collectionKey: [String: String] = [
        "profile": "profiles", "protocol": "protocols", "log": "logs", "vial": "vials", "measurement": "measurements",
        "lab": "labs", "checkIn": "checkIns", "customPeptide": "customPeptides", "order": "orders",
        "diluent": "diluents", "compoundNote": "compoundNotes",
    ]
    var overrides: JSONObject = [:]
    let decoder = JSONDecoder()
    for e in envelopes.sorted(by: { $0.recordId < $1.recordId }) {
        guard let value = try? decoder.decode(JSONValue.self, from: e.payload) else { continue }
        if let key = collectionKey[e.kind] {
            collections[key, default: []].append(value)
        } else if e.kind == EnvelopeKind.settings.rawValue {
            obj["settings"] = value
        } else if e.kind == EnvelopeKind.halfLifeOverride.rawValue {
            overrides[e.recordId] = value
        } else if e.kind == EnvelopeKind.extra.rawValue {
            obj[e.recordId] = value
        } else if e.kind == EnvelopeKind.raw.rawValue, let collection = e.recordId.split(separator: "#").first {
            collections[String(collection), default: []].append(value)
        }
    }
    for (k, v) in collections { obj[k] = .array(v) }
    obj["halfLifeOverrides"] = .object(overrides)
    if let active = activeProfileId { obj["activeProfileId"] = .string(active) }
    obj["version"] = .number(Double(DATA_VERSION))
    return migrateAppData(.object(obj))
}
