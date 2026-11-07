import Foundation

// JavaScript number semantics the original relies on.

/// `Math.round`: half rounds towards +∞, so -2.5 → -2 (Swift's `.rounded()` gives -3).
@inlinable public func jsRound(_ x: Double) -> Double {
    guard x.isFinite else { return x }
    return (x + 0.5).rounded(.down)
}

/// `x.toFixed(dp)`.
///
/// toFixed rounds the exact binary value, and an exact tie goes away from zero
/// (2.5 → "3", 0.125 → "0.13"). `%.*f` would round ties to even, so the exact
/// expansion is printed long and rounded here by hand.
public func jsToFixed(_ x: Double, _ dp: Int) -> String {
    guard x.isFinite else { return x.isNaN ? "NaN" : (x > 0 ? "Infinity" : "-Infinity") }
    if abs(x) >= 1e21 { return jsNumberString(x) }
    let negative = x < 0
    let exact = String(format: "%.\(dp + 60)f", abs(x))
    let parts = exact.split(separator: ".", omittingEmptySubsequences: false)
    var intDigits = Array(parts[0])
    let frac = parts.count > 1 ? Array(parts[1]) : []
    var kept = Array(frac.prefix(dp))
    let next = frac.count > dp ? frac[dp] : "0"
    if next >= "5" {
        // Carry through the kept digits, then the integer part.
        var i = kept.count - 1
        var carry = true
        while carry && i >= 0 {
            if kept[i] == "9" { kept[i] = "0"; i -= 1 } else { kept[i] = Character(String(kept[i].wholeNumberValue! + 1)); carry = false }
        }
        var j = intDigits.count - 1
        while carry && j >= 0 {
            if intDigits[j] == "9" { intDigits[j] = "0"; j -= 1 } else { intDigits[j] = Character(String(intDigits[j].wholeNumberValue! + 1)); carry = false }
        }
        if carry { intDigits.insert("1", at: 0) }
    }
    var out = String(intDigits)
    if dp > 0 { out += "." + String(kept) }
    let isZero = !out.contains { $0 != "0" && $0 != "." }
    return (negative && !isZero ? "-" : "") + out
}

/// JS `String(n)` for the magnitudes this app deals in: shortest round-trip form,
/// no trailing ".0" on integers.
public func jsNumberString(_ n: Double) -> String {
    guard n.isFinite else { return n.isNaN ? "NaN" : (n > 0 ? "Infinity" : "-Infinity") }
    if n == 0 { return "0" }
    if n == n.rounded(), abs(n) < 1e15 { return String(format: "%.0f", n) }
    return "\(n)"
}

/// `Number(x.toFixed(dp))` as a Double.
public func jsFixed(_ x: Double, _ dp: Int) -> Double {
    Double(jsToFixed(x, dp)) ?? x
}

/// Epoch milliseconds for now.
public func nowMillis() -> Millis { Date().timeIntervalSince1970 * 1000 }

extension Date {
    public var millis: Millis { timeIntervalSince1970 * 1000 }
    public init(millis: Millis) { self.init(timeIntervalSince1970: millis / 1000) }
}

/// Short unique id, as the store's `uid()` makes them.
public func uid() -> String {
    let t = String(UInt64(nowMillis()), radix: 36)
    let r = String(UInt64.random(in: 0..<UInt64(36 * 36 * 36 * 36 * 36 * 36)), radix: 36)
    return t + r
}
