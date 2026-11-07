import Foundation

/// What to draw, press or take for a dose, from what is on your shelf: "10 units"
/// (with "(U-40)" on that barrel), "2 presses" or "1.5 tablets". Nil when there is
/// nothing to say it with: no mixed vial, no filled spray, no opened pack.
/// One place for the Now and Plan screens and for reminders, so they agree.
public func drawAmountText(_ data: AppData, peptideId: String, doseMcg: Double, route: Route?, nowMs: Millis) -> String? {
    let vials = data.mine.vials
    if route == .intranasal {
        guard let bottle = pickVialForDose(vials, peptideId, doseMcg, nowMs, .spray), mcgPerSpray(bottle) > 0 else { return nil }
        return t("count_presses", ["n": .number(spraysForDose(bottle, doseMcg))])
    }
    if let pack = pickVialForDose(vials, peptideId, doseMcg, nowMs, .pack), mcgPerTablet(pack) > 0 {
        return t("count_tablets", ["n": .string(trim(tabletsForDose(pack, doseMcg), 2))])
    }
    let scale = (syringeById(data.settings.defaultSyringeId) ?? SYRINGES[2]).scale
    guard let marks = marksForDose(vials, peptideId, doseMcg, scale, nowMs) else { return nil }
    return t("ios_units_count", ["n": .string(trim(marks, 2))]) + (scale == .u40 ? " (U-40)" : "")
}
