import Foundation

// Port of src/lib/calc/feeling.ts. Rough reads red, great reads green; a rating
// with no direction (physical hunger) stays neutral.

public let FEELING_TONE: [Int: Tone] = [1: .rose, 2: .tangerine, 3: .sky, 4: .mint, 5: .leaf]

public func ratingTone(_ rating: Double, _ higherIsBetter: Bool? = nil) -> Tone {
    guard let hib = higherIsBetter else { return .neutral }
    let s = scoreOf(rating, hib)
    guard s == s.rounded() else { return .neutral }
    return FEELING_TONE[Int(s)] ?? .neutral
}

/// The rating turned so that five is always the good end.
public func scoreOf(_ rating: Double, _ higherIsBetter: Bool) -> Double {
    higherIsBetter ? rating : Double(SYMPTOM_SCALE_MAX + 1) - rating
}

/// The worst directional rating of a day, as a tone; nil when nothing had a direction.
public func lowestRatedTone(_ ratings: [(rating: Double, higherIsBetter: Bool?)]) -> Tone? {
    let scored = ratings.compactMap { r in r.higherIsBetter.map { scoreOf(r.rating, $0) } }
    guard let worst = scored.min(), worst == worst.rounded() else { return nil }
    return FEELING_TONE[Int(worst)]
}
