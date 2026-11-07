import Foundation

// Port of src/lib/calc/converter.ts. A link, not a request: nothing leaves the
// device until somebody chooses to open it.

public func converterUrl(_ amount: Double, _ from: String, _ to: String) -> URL? {
    guard amount > 0, !from.isEmpty, !to.isEmpty, from != to else { return nil }
    let rounded = jsRound(amount * 100) / 100
    let query = "\(jsNumberString(rounded)) \(from) to \(to)"
    var allowed = CharacterSet.alphanumerics
    allowed.insert(charactersIn: "-_.!~*'()")
    let encoded = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
    return URL(string: "https://www.google.com/search?q=\(encoded)")
}
