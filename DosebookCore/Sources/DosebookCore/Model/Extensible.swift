import Foundation

/// A record that keeps the fields it does not recognise.
///
/// `migrateAppData` in the original spreads every row, so a field written by a
/// newer build travels through an older one untouched. Naming the fields would
/// drop the rest on the way in and saving would drop them for good. Here the
/// unknown keys are held in `extra` and written back out beside the known ones.
///
/// Conformers declare `CodingKeys: CaseIterable` and give `extra` a default, so
/// the compiler still synthesises the typed half of the coding.
public protocol Extensible: Codable, Equatable, Sendable {
    var extra: JSONObject { get set }
    static var knownKeys: Set<String> { get }
}

/// An `Extensible` record that belongs to a collection, keyed by `id`.
public protocol Row: Extensible, Identifiable where ID == String {
    var id: String { get set }
}

/// Coding wrapper that fills and writes `extra`.
public struct Lenient<T: Extensible>: Codable, Sendable {
    public var value: T

    public init(_ value: T) { self.value = value }

    public init(from decoder: Decoder) throws {
        var v = try T(from: decoder)
        let raw = try decoder.singleValueContainer().decode(JSONObject.self)
        v.extra = raw.filter { !T.knownKeys.contains($0.key) }
        value = v
    }

    public func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
        guard !value.extra.isEmpty else { return }
        var c = encoder.container(keyedBy: AnyCodingKey.self)
        for (k, v) in value.extra where !T.knownKeys.contains(k) {
            try c.encode(v, forKey: AnyCodingKey(k))
        }
    }
}

extension Extensible {
    /// Encode this record, unknown fields included, to JSON data.
    public func lenientJSON(encoder: JSONEncoder = JSONEncoder()) throws -> Data {
        try encoder.encode(Lenient(self))
    }

    /// Decode a record, keeping unknown fields.
    public static func lenient(from data: Data) throws -> Self {
        try JSONDecoder().decode(Lenient<Self>.self, from: data).value
    }

    public static func lenient(from json: JSONValue) throws -> Self {
        try json.decode(Lenient<Self>.self).value
    }

    public func lenientValue() throws -> JSONValue {
        try JSONValue.from(Lenient(self))
    }
}

extension CaseIterable where Self: RawRepresentable, RawValue == String {
    static var rawNames: Set<String> { Set(allCases.map(\.rawValue)) }
}
