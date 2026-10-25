import Foundation

// What is in your vial, for a library blend that names its parts but not how much
// of each (Wolverine is sold as 5 + 5, 10 + 10 and more). Once set, the blend
// behaves like one whose amounts were always known: doses split per part, the
// vial's strength follows, the Library page shows them. iOS only, kept in
// `AppData.extra` so backups stay readable by the web app.

let BLEND_AMOUNTS_KEY = "iosBlendAmounts"

public extension AppData {
    /// Milligrams per part, in the blend's own part order, by compound id.
    var blendAmounts: [String: [Double]] {
        guard let map = extra[BLEND_AMOUNTS_KEY]?.objectValue else { return [:] }
        var out: [String: [Double]] = [:]
        for (id, v) in map {
            if let mg = v.arrayValue?.compactMap(\.numberValue), !mg.isEmpty { out[id] = mg }
        }
        return out
    }

    /// Sets or, with nil, clears your amounts for a blend.
    mutating func setBlendAmounts(_ id: String, mg: [Double]?) {
        var map = extra[BLEND_AMOUNTS_KEY]?.objectValue ?? [:]
        if let mg, !mg.isEmpty { map[id] = .array(mg.map { .number($0) }) } else { map.removeValue(forKey: id) }
        if map.isEmpty { extra.removeValue(forKey: BLEND_AMOUNTS_KEY) } else { extra[BLEND_AMOUNTS_KEY] = .object(map) }
    }
}

/// Whether a blend is missing the amount of any part, so a dose cannot be split.
public func blendNeedsAmounts(_ p: Peptide?) -> Bool {
    guard let p, isBlend(p) else { return false }
    return (p.components ?? []).contains { ($0.mgPerVial ?? 0) <= 0 }
}

/// The blend with your amounts in place, when there is one for every part. Its
/// vial size is their total, offered first.
public func withBlendAmounts(_ p: Peptide, _ mg: [Double]?) -> Peptide {
    guard let mg, var parts = p.components, parts.count == mg.count, mg.allSatisfy({ $0 > 0 }) else { return p }
    for i in parts.indices { parts[i].mgPerVial = mg[i] }
    var out = p
    out.components = parts
    let total = jsFixed(mg.reduce(0, +), 6)
    out.vialSizesMg = [total] + p.vialSizesMg.filter { $0 != total }
    return out
}

/// What a blend holds, for beside its name: "GHK-Cu 50 · BPC-157 10 · TB-500 10 · KPV 10 mg"
/// when every amount is known, else just the parts, "BPC-157 + TB-500". Nil for anything
/// that is not a blend.
public func blendContents(_ p: Peptide?) -> String? {
    guard let p, isBlend(p) else { return nil }
    let parts = p.components ?? []
    if parts.allSatisfy({ ($0.mgPerVial ?? 0) > 0 }) {
        return parts.map { "\($0.name) \(jsNumberString($0.mgPerVial!))" }.joined(separator: " · ") + " mg"
    }
    return parts.map(\.name).joined(separator: " + ")
}
