import Foundation

/// A compound or protocol name for a crowded list: the qualifier in trailing brackets is dropped
/// ("Testosterone undecanoate (injectable)" becomes "Testosterone undecanoate"). The full name stays
/// wherever there is room, and is what is spoken.
public func shortName(_ name: String) -> String {
    var out = name.trimmingCharacters(in: .whitespaces)
    while out.hasSuffix(")"), let open = out.lastIndex(of: "("), open != out.startIndex {
        let head = out[..<open].trimmingCharacters(in: .whitespaces)
        if head.isEmpty { break }
        out = head
    }
    return out
}
