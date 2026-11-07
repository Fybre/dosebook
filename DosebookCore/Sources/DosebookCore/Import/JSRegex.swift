import Foundation

/// A JavaScript-flavoured regular expression over UTF-16, so match positions
/// mean what they meant in the original: offsets into a JS string.
struct JSRegex: @unchecked Sendable {
    struct Match {
        /// UTF-16 offset of the whole match.
        var index: Int
        var length: Int
        /// Group 0 is the whole match; nil where a group did not participate.
        var groups: [String?]
        var end: Int { index + length }
        subscript(_ i: Int) -> String? { i < groups.count ? groups[i] : nil }
    }

    let re: NSRegularExpression

    /// `flags` takes the JS letters that matter here: `i` and `m`.
    init(_ pattern: String, _ flags: String = "") {
        var options: NSRegularExpression.Options = []
        if flags.contains("i") { options.insert(.caseInsensitive) }
        if flags.contains("m") { options.insert(.anchorsMatchLines) }
        re = try! NSRegularExpression(pattern: pattern, options: options)
    }

    func exec(_ s: String, from: Int = 0) -> Match? {
        let ns = s as NSString
        guard from <= ns.length, let m = re.firstMatch(in: s, range: NSRange(location: from, length: ns.length - from)) else { return nil }
        return Self.match(m, ns)
    }

    func test(_ s: String) -> Bool { exec(s) != nil }

    func all(_ s: String) -> [Match] {
        let ns = s as NSString
        return re.matches(in: s, range: NSRange(location: 0, length: ns.length)).map { Self.match($0, ns) }
    }

    /// Every occurrence replaced; the template uses `$1`, and `$0` for the whole match.
    func replaceAll(_ s: String, _ template: String) -> String {
        re.stringByReplacingMatches(in: s, range: NSRange(location: 0, length: (s as NSString).length), withTemplate: template)
    }

    /// The first occurrence replaced, as JS `replace` without the g flag.
    func replaceFirst(_ s: String, _ template: String) -> String {
        guard let m = re.firstMatch(in: s, range: NSRange(location: 0, length: (s as NSString).length)) else { return s }
        let replacement = re.replacementString(for: m, in: s, offset: 0, template: template)
        return (s as NSString).replacingCharacters(in: m.range, with: replacement)
    }

    /// Every occurrence replaced by what `transform` makes of it.
    func replaceAll(_ s: String, _ transform: (Match) -> String) -> String {
        let ns = s as NSString
        var out = "", last = 0
        for m in re.matches(in: s, range: NSRange(location: 0, length: ns.length)) {
            out += ns.substring(with: NSRange(location: last, length: m.range.location - last))
            out += transform(Self.match(m, ns))
            last = m.range.location + m.range.length
        }
        return out + ns.substring(from: last)
    }

    private static func match(_ m: NSTextCheckingResult, _ ns: NSString) -> Match {
        Match(index: m.range.location, length: m.range.length, groups: (0..<m.numberOfRanges).map { i in
            let r = m.range(at: i)
            return r.location == NSNotFound ? nil : ns.substring(with: r)
        })
    }
}

extension String {
    /// Length and slicing in UTF-16 units, as a JS string measures them.
    var u16Count: Int { (self as NSString).length }
    func u16Slice(_ from: Int, _ to: Int? = nil) -> String {
        let ns = self as NSString
        let a = max(0, min(from, ns.length)), b = max(a, min(to ?? ns.length, ns.length))
        return ns.substring(with: NSRange(location: a, length: b - a))
    }
    /// JS `Number(text)`: whitespace-trimmed, empty is 0, anything else unparseable is NaN.
    var jsNumber: Double {
        let t = trimmingCharacters(in: .whitespacesAndNewlines)
        if t.isEmpty { return 0 }
        if JSRegex(#"^[-+]?(\d+\.?\d*|\.\d+)([eE][-+]?\d+)?$"#).test(t) { return Double(t) ?? .nan }
        if t == "Infinity" || t == "+Infinity" { return .infinity }
        if t == "-Infinity" { return -.infinity }
        return .nan
    }
}
