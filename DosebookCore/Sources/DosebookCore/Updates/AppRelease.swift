import Foundation

/// Published app versions use numeric tags such as v1.0.10. Reject preview and malformed tags.
public struct AppVersion: Comparable, Sendable {
    private let components: [Int]

    public init?(_ text: String) {
        let value = text.hasPrefix("v") ? String(text.dropFirst()) : text
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var numbers: [Int] = []
        for part in parts {
            guard !part.isEmpty, part.allSatisfy({ $0.isASCII && $0.isNumber }), let n = Int(part) else { return nil }
            numbers.append(n)
        }
        components = numbers + Array(repeating: 0, count: 3 - numbers.count)
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.components.lexicographicallyPrecedes(rhs.components)
    }
}

public struct AppRelease: Decodable, Sendable {
    public let tag_name: String
    public let draft: Bool
    public let prerelease: Bool
    public let assets: [Asset]

    public struct Asset: Decodable, Sendable {
        public let name: String
        public let state: String
    }

    public func isUpdate(for installed: String) -> Bool {
        guard !draft, !prerelease,
              assets.contains(where: { $0.name == "Dosebook.dmg" && $0.state == "uploaded" }),
              let latest = AppVersion(tag_name), let current = AppVersion(installed) else { return false }
        return latest > current
    }

    public var version: String { tag_name.hasPrefix("v") ? String(tag_name.dropFirst()) : tag_name }
    public var url: URL {
        URL(string: "https://github.com/Fybre/dosebook/releases/tag/")!.appendingPathComponent(tag_name)
    }
}
