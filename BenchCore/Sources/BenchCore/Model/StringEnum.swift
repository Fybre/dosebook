import Foundation

/// A closed set of string values that still decodes values it has never seen.
///
/// The original is TypeScript, where an unknown string in a union type is just a
/// string. A Swift `enum` would fail the whole import on one unrecognised value,
/// so these are structs that carry the raw string and round-trip it untouched.
/// Known values are static constants and `switch` still matches them.
public protocol StringEnum: RawRepresentable, Codable, Hashable, Sendable, ExpressibleByStringLiteral
where RawValue == String {
    init(rawValue: String)
    static var allCases: [Self] { get }
}

extension StringEnum {
    public init(stringLiteral value: String) { self.init(rawValue: value) }

    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        self.init(rawValue: try c.decode(String.self))
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        try c.encode(rawValue)
    }

    /// Whether this build knows the value.
    public var isKnown: Bool { Self.allCases.contains(self) }
}
