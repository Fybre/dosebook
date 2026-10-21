import Foundation

/// A dictionary that remembers insertion order, as a JS `Map` does. Several
/// ported functions report in the order a `Map` was filled, and that order is
/// visible on screen.
public struct OrderedMap<Key: Hashable, Value> {
    public private(set) var keys: [Key] = []
    private var storage: [Key: Value] = [:]

    public init() {}

    public subscript(key: Key) -> Value? {
        get { storage[key] }
        set {
            if let newValue {
                if storage.updateValue(newValue, forKey: key) == nil { keys.append(key) }
            } else if storage.removeValue(forKey: key) != nil {
                keys.removeAll { $0 == key }
            }
        }
    }

    public var values: [Value] { keys.map { storage[$0]! } }
    public var count: Int { keys.count }
    public var isEmpty: Bool { keys.isEmpty }
    public var entries: [(key: Key, value: Value)] { keys.map { ($0, storage[$0]!) } }
}
