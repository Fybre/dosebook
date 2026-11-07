import Foundation

// Port of src/lib/calc/blend.ts. A blend dose split into what each component
// delivers, compared against that component's own standalone range.

public func isBlend(_ p: Peptide?) -> Bool { !(p?.components ?? []).isEmpty }

public func blendDosing(_ p: Peptide) -> BlendDosing { p.blendDosing ?? .split }

public enum RelativeToTypical: String, Sendable { case below, within, above, unknown }
public enum ComparedOn: String, Sendable { case weekly, perDose = "per-dose", none }

public struct ComponentDose: Equatable, Sendable {
    public var peptideId: String?
    public var name: String
    public var mcg: Double
    /// Share of the blend's mass; 1 for per-component dosing.
    public var fraction: Double
    public var typicalLowMcg: Double?
    public var typicalHighMcg: Double?
    public var typicalPerWeek: Double?
    public var typicalFrequency: String?
    public var weeklyMcg: Double?
    public var typicalWeeklyLowMcg: Double?
    public var typicalWeeklyHighMcg: Double?
    public var relativeToTypical: RelativeToTypical
    public var comparedOn: ComparedOn
    public var peptide: Peptide?
}

/// Split a blend dose into per-component amounts. `mgPerVial` sets the ratio;
/// without it the mass is divided equally. Supplying `dosesPerWeek` compares weekly.
public func decomposeDose(_ blend: Peptide, _ doseMcg: Double, resolve: ((String) -> Peptide?)? = nil,
                          dosesPerWeek: Double? = nil) -> [ComponentDose] {
    let components = blend.components ?? []
    if components.isEmpty { return [] }
    let mode = blendDosing(blend)
    let masses = components.map { $0.mgPerVial ?? 0 }
    let total = masses.reduce(0, +)
    let weekly = (dosesPerWeek ?? 0) != 0 ? dosesPerWeek : nil

    return components.enumerated().map { i, c in
        let fraction = mode == .perComponent ? 1 : (total > 0 ? masses[i] / total : 1 / Double(components.count))
        let mcg = max(0, doseMcg) * fraction
        let peptide = c.peptideId.flatMap { id in resolve?(id) }
        let range = peptide?.doseRanges.first
        let low = range?.lowMcg, high = range?.highMcg, perWeek = range?.perWeek
        let canCompareWeekly = low != nil && high != nil && (perWeek ?? 0) > 0 && weekly != nil
        let weeklyMcg = weekly.map { mcg * $0 }
        let weeklyLow = canCompareWeekly ? low! * perWeek! : nil
        let weeklyHigh = canCompareWeekly ? high! * perWeek! : nil
        let (value, lo, hi, basisIf): (Double?, Double?, Double?, ComparedOn) =
            canCompareWeekly ? (weeklyMcg, weeklyLow, weeklyHigh, .weekly) : (mcg, low, high, .perDose)

        var relative = RelativeToTypical.unknown
        var basis = ComparedOn.none
        if let lo, let hi, let value, value > 0 {
            basis = basisIf
            relative = value < lo ? .below : (value > hi ? .above : .within)
        }
        return ComponentDose(peptideId: c.peptideId, name: c.name, mcg: mcg, fraction: fraction,
                             typicalLowMcg: low, typicalHighMcg: high, typicalPerWeek: perWeek,
                             typicalFrequency: range?.frequency, weeklyMcg: weeklyMcg,
                             typicalWeeklyLowMcg: weeklyLow, typicalWeeklyHighMcg: weeklyHigh,
                             relativeToTypical: relative, comparedOn: basis, peptide: peptide)
    }
}

/// The blend dose at which a chosen component lands on a target amount.
public func blendDoseForComponent(_ blend: Peptide, _ componentId: String, _ targetMcg: Double) -> Double {
    guard let part = decomposeDose(blend, 1000).first(where: { $0.peptideId == componentId }),
          part.fraction > 0, targetMcg > 0 else { return .nan }
    return targetMcg / part.fraction
}

/// Components with a published half-life.
public func modellableComponents(_ parts: [ComponentDose]) -> [ComponentDose] {
    parts.filter { $0.peptide?.halfLifeHours != nil }
}

/// One line naming components outside their usual standalone range.
public func describeBlendDose(_ parts: [ComponentDose]) -> String? {
    let above = parts.filter { $0.relativeToTypical == .above }
    let below = parts.filter { $0.relativeToTypical == .below }
    let basis = parts.first { $0.comparedOn != .none }?.comparedOn ?? .perDose
    let per = basis == .weekly ? "for a week" : "at this dose"
    if !above.isEmpty {
        return "\(above.map(\.name).joined(separator: " and ")) \(above.count == 1 ? "is" : "are") above the usual standalone amount \(per)."
    }
    if below.count == parts.count { return "Every component lands below its usual standalone dose." }
    if !below.isEmpty {
        return "\(below.map(\.name).joined(separator: " and ")) \(below.count == 1 ? "is" : "are") below the usual standalone amount \(per)."
    }
    return nil
}
