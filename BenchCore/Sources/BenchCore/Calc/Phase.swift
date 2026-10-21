import Foundation

// Port of src/lib/calc/phase.ts. What a compound is doing right now, in words,
// from the library's per-compound timeline.

public struct TimelinePhase: Equatable, Sendable {
    public var fromHours: Double
    public var toHours: Double
    public var label: String
    /// How far through this window, 0 to 1.
    public var progress: Double
    /// Hours until the next window begins; nil on the final one.
    public var hoursToNext: Double?
}

/// The window covering a number of hours since the last dose; nil before the
/// dose, without a timeline, or past its end.
public func timelinePhaseAt(_ peptide: Peptide, _ hoursSinceDose: Double) -> TimelinePhase? {
    guard let timeline = peptide.timeline, !timeline.isEmpty, hoursSinceDose >= 0 else { return nil }
    for (i, w) in timeline.enumerated() where hoursSinceDose >= w.fromHours && hoursSinceDose < w.toHours {
        let span = w.toHours - w.fromHours
        return TimelinePhase(fromHours: w.fromHours, toHours: w.toHours, label: w.label,
                             progress: span > 0 ? (hoursSinceDose - w.fromHours) / span : 1,
                             hoursToNext: i == timeline.count - 1 ? nil : w.toHours - hoursSinceDose)
    }
    return nil
}

public struct TimelineRow: Equatable, Sendable {
    public var fromHours: Double
    public var toHours: Double
    public var label: String
    public var current: Bool
    public var past: Bool
}

/// Every window, flagged with which one is current.
public func timelineWithCurrent(_ peptide: Peptide, _ hoursSinceDose: Double?) -> [TimelineRow] {
    (peptide.timeline ?? []).map { w in
        TimelineRow(fromHours: w.fromHours, toHours: w.toHours, label: w.label,
                    current: hoursSinceDose.map { $0 >= w.fromHours && $0 < w.toHours } ?? false,
                    past: hoursSinceDose.map { $0 >= w.toHours } ?? false)
    }
}

/// Hours since a dose, floored at zero; nil when nothing has been logged.
public func hoursSince(_ lastDoseAt: Millis?, _ nowMs: Millis) -> Double? {
    guard let lastDoseAt else { return nil }
    return max(0, (nowMs - lastDoseAt) / HOUR_MS)
}
