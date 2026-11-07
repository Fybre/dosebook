import Foundation

// A blend's dose said per part. The app stores the whole blend drawn, which is
// what the syringe and stock work from, but "500 mcg" of a 10 + 10 blend reads as
// 500 of each to anyone who thinks of it, as most do, as 250 of each.

/// The parts a dose of this compound splits into, or nil for a single compound or
/// a blend whose parts cannot be weighed against each other.
public func blendParts(_ p: Peptide?, _ doseMcg: Double, resolve: ((String) -> Peptide?)? = nil) -> [ComponentDose]? {
    guard let p, isBlend(p), blendDosing(p) == .split else { return nil }
    let parts = p.components ?? []
    guard parts.allSatisfy({ ($0.mgPerVial ?? 0) > 0 }) else { return nil }
    return decomposeDose(p, doseMcg, resolve: resolve)
}

/// Every part at the same strength, so "each" says it all.
func evenParts(_ parts: [ComponentDose]) -> Bool {
    guard let first = parts.first else { return false }
    return parts.allSatisfy { abs($0.fraction - first.fraction) < 1e-9 }
}

/// The dose as a person would say it: "250 mcg each" for an even blend,
/// "125 mcg CJC-1295 + 375 mcg Ipamorelin" for an uneven one, else the plain amount.
public func doseLabel(_ doseMcg: Double, _ p: Peptide?, resolve: ((String) -> Peptide?)? = nil) -> String {
    guard let parts = blendParts(p, doseMcg, resolve: resolve), !parts.isEmpty else { return formatDose(doseMcg) }
    if evenParts(parts) { return "\(formatDose(parts[0].mcg)) each" }
    return parts.map { "\(formatDose($0.mcg)) \($0.name)" }.joined(separator: " + ")
}

/// The blend total, for beside `doseLabel`: "500 mcg blend". nil for anything else.
public func blendTotalLabel(_ doseMcg: Double, _ p: Peptide?) -> String? {
    blendParts(p, doseMcg) == nil ? nil : "\(formatDose(doseMcg)) blend"
}

/// For entering a blend dose by one part: the share of the blend that part is.
/// 0.5 for either part of a 10 + 10 blend. nil for anything that is not a blend.
public func firstPartShare(_ p: Peptide?) -> Double? {
    blendParts(p, 1000).flatMap { $0.first?.fraction }
}

/// `doseLabel` for a dose taken several times a day: "250 mcg each × 2".
public func doseLabelPerDay(_ doseMcg: Double, _ perDay: Int, _ p: Peptide?) -> String {
    perDay > 1 ? "\(doseLabel(doseMcg, p)) × \(perDay)" : doseLabel(doseMcg, p)
}
