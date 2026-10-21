import Foundation

/// The whole document, as one backup file holds it.
public struct AppData: Equatable, Sendable {
    public var version: Int = DATA_VERSION
    public var profiles: [Profile] = [DEFAULT_PROFILE]
    public var measurements: [BodyMeasurement] = []
    public var labs: [LabResult] = []
    public var activeProfileId: String = DEFAULT_PROFILE_ID
    public var protocols: [DoseProtocol] = []
    public var logs: [DoseLog] = []
    public var vials: [Vial] = []
    public var settings: Settings = DEFAULT_SETTINGS
    public var customPeptides: [Peptide] = []
    public var checkIns: [CheckIn] = []
    public var halfLifeOverrides: [String: HalfLifeOverride] = [:]
    public var compoundNotes: [CompoundNote] = []
    public var orders: [Order] = []
    public var diluents: [DiluentBottle] = []

    /// Top-level fields this build does not recognise, written back out untouched.
    public var extra: JSONObject = [:]
    /// Rows that could not be read as their type, per collection key. Kept and
    /// re-exported rather than dropped: a row nobody here can read is still somebody's data.
    public var unreadable: [String: [JSONValue]] = [:]

    public init() {}

    public static let empty = AppData()

    static let knownKeys: Set<String> = [
        "version", "profiles", "measurements", "labs", "activeProfileId", "protocols", "logs", "vials",
        "settings", "customPeptides", "checkIns", "halfLifeOverrides", "compoundNotes", "orders", "diluents",
    ]
}

// MARK: - Coding

extension AppData: Codable {
    public init(from decoder: Decoder) throws {
        let raw = try decoder.singleValueContainer().decode(JSONObject.self)
        self.init(json: raw, fillDefaults: false)
    }

    /// Build from a raw object without failing. Missing collections are empty;
    /// unreadable rows go to `unreadable`. `fillDefaults` false keeps an absent
    /// `profiles` empty so migration can tell "absent" from "present".
    init(json raw: JSONObject, fillDefaults: Bool) {
        var unreadable: [String: [JSONValue]] = [:]
        func rows<T: Extensible>(_ key: String, _: T.Type) -> [T] {
            guard let arr = raw[key]?.arrayValue else { return [] }
            var out: [T] = []
            for item in arr {
                if let v = try? T.lenient(from: item) { out.append(v) }
                else if item != .null { unreadable[key, default: []].append(item) }
            }
            return out
        }
        version = raw["version"]?.numberValue.map { Int($0) } ?? 0
        profiles = rows("profiles", Profile.self)
        if fillDefaults && profiles.isEmpty { profiles = [DEFAULT_PROFILE] }
        measurements = rows("measurements", BodyMeasurement.self)
        labs = rows("labs", LabResult.self)
        activeProfileId = raw["activeProfileId"]?.stringValue ?? ""
        protocols = rows("protocols", DoseProtocol.self)
        logs = rows("logs", DoseLog.self)
        vials = rows("vials", Vial.self)
        if let s = raw["settings"], let decoded = try? Settings.lenient(from: s) { settings = decoded }
        customPeptides = rows("customPeptides", Peptide.self)
        checkIns = rows("checkIns", CheckIn.self)
        if let map = raw["halfLifeOverrides"]?.objectValue {
            halfLifeOverrides = Self.rawOverrides(map)
        }
        compoundNotes = rows("compoundNotes", CompoundNote.self)
        orders = rows("orders", Order.self)
        diluents = rows("diluents", DiluentBottle.self)
        extra = raw.filter { !Self.knownKeys.contains($0.key) }
        self.unreadable = unreadable
    }

    /// Overrides read loosely; `saneOverrides` in migration does the real filtering.
    /// A non-numeric hours value becomes NaN so it is dropped there.
    static func rawOverrides(_ map: JSONObject) -> [String: HalfLifeOverride] {
        var out: [String: HalfLifeOverride] = [:]
        for (id, value) in map {
            guard let o = value.objectValue else { continue }
            let hours = o["hours"]?.numberValue ?? .nan
            let setAt = o["setAt"]?.numberValue ?? .nan
            out[id] = HalfLifeOverride(hours: hours, setAt: setAt, note: o["note"]?.stringValue)
        }
        return out
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        for (k, v) in extra where !Self.knownKeys.contains(k) { try c.encode(v, forKey: AnyCodingKey(k)) }
        func rows<T: Extensible>(_ key: String, _ items: [T]) throws {
            var all = try items.map { try $0.lenientValue() }
            all.append(contentsOf: unreadable[key] ?? [])
            try c.encode(all, forKey: AnyCodingKey(key))
        }
        try c.encode(version, forKey: AnyCodingKey("version"))
        try rows("profiles", profiles)
        try rows("measurements", measurements)
        try rows("labs", labs)
        try c.encode(activeProfileId, forKey: AnyCodingKey("activeProfileId"))
        try rows("protocols", protocols)
        try rows("logs", logs)
        try rows("vials", vials)
        try c.encode(Lenient(settings), forKey: AnyCodingKey("settings"))
        try rows("customPeptides", customPeptides)
        try rows("checkIns", checkIns)
        try c.encode(halfLifeOverrides, forKey: AnyCodingKey("halfLifeOverrides"))
        try rows("compoundNotes", compoundNotes)
        try rows("orders", orders)
        try rows("diluents", diluents)
    }
}

extension AppData {
    /// Read any Bench export or backup, migrating it to the current shape.
    public static func load(_ data: Data) throws -> AppData {
        let value = try JSONDecoder().decode(JSONValue.self, from: data)
        return migrateAppData(value)
    }

    /// Pretty JSON in the original's export shape.
    public func exportJSON() throws -> Data {
        let e = JSONEncoder()
        e.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        return try e.encode(self)
    }
}
