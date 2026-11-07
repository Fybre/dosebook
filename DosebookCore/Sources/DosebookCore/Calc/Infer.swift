import Foundation

// Port of src/lib/calc/infer.ts. Reading the plan back out of a logged history,
// as a proposal with a stated confidence, never applied on its own.

private let MIN_GAP_MS: Double = 6 * 60 * 60_000
private let DAY_TOLERANCE = 0.35

public enum InferConfidence: String, Sendable { case clear, rough }

public struct InferredProtocol: Equatable, Sendable {
    public var peptideId: String
    public var peptideName: String
    public var doseMcg: Double
    public var schedule: Schedule
    public var sites: [InjectionSite]
    public var startedAt: Millis
    public var lastAt: Millis
    public var doseCount: Int
    public var summary: String
    public var confidence: InferConfidence
}

private func median(_ xs: [Double]) -> Double {
    let s = xs.sorted()
    let mid = s.count / 2
    return s.count % 2 == 1 ? s[mid] : (s[mid - 1] + s[mid]) / 2
}

/// The most common value, ties broken by the earliest seen.
private func mode<T: Hashable>(_ xs: [T]) -> T? {
    var counts = OrderedMap<T, Int>()
    for x in xs { counts[x] = (counts[x] ?? 0) + 1 }
    var best: T?
    var bestCount = 0
    for (v, c) in counts.entries where c > bestCount { best = v; bestCount = c }
    return best
}

/// The usual time of day to the nearest half hour; a modal midnight means the
/// file carried only a date, and yields no time.
private func modalTimeOfDay(_ times: [Millis]) -> String? {
    guard !times.isEmpty else { return nil }
    let cal = LocalTime.calendar
    let slots = times.map { t -> Int in
        let c = cal.dateComponents([.hour, .minute], from: Date(millis: t))
        return (c.hour ?? 0) * 2 + ((c.minute ?? 0) >= 30 ? 1 : 0)
    }
    guard let slot = mode(slots), slot != 0 else { return nil }
    return String(format: "%02d:%02d", slot / 2, slot % 2 == 1 ? 30 : 0)
}

private func scheduleFrom(_ times: [Millis]) -> (Schedule, InferConfidence) {
    let sorted = times.sorted()
    let timeOfDay = modalTimeOfDay(sorted)
    guard sorted.count >= 2 else {
        return (Schedule(kind: .daysOfWeek, daysOfWeek: [localWeekday(sorted[0])], timeOfDay: timeOfDay), .rough)
    }
    var gaps: [Double] = []
    for i in 1..<sorted.count {
        let gap = sorted[i] - sorted[i - 1]
        if gap >= MIN_GAP_MS { gaps.append(gap / DAY_MS) }
    }
    guard !gaps.isEmpty else { return (Schedule(kind: .daily, timeOfDay: timeOfDay), .rough) }
    let typical = median(gaps)
    let agreeing = gaps.filter { abs($0 - typical) <= DAY_TOLERANCE }.count
    let confidence: InferConfidence = Double(agreeing) / Double(gaps.count) >= 0.7 ? .clear : .rough
    if abs(typical - 1) <= DAY_TOLERANCE { return (Schedule(kind: .daily, timeOfDay: timeOfDay), confidence) }
    if abs(typical - 7) <= DAY_TOLERANCE {
        let weekday = mode(sorted.map(localWeekday)) ?? localWeekday(sorted[0])
        return (Schedule(kind: .daysOfWeek, daysOfWeek: [weekday], timeOfDay: timeOfDay), confidence)
    }
    return (Schedule(kind: .intervalDays, intervalDays: max(1, jsRound(typical)), timeOfDay: timeOfDay), confidence)
}

private let WEEKDAYS = ["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"]

private func describeSchedule(_ s: Schedule) -> String {
    switch s.kind {
    case .daily: return "every day"
    case .daysOfWeek:
        guard let d = s.daysOfWeek?.first, (0...6).contains(d) else { return "weekly" }
        return "every \(WEEKDAYS[d])"
    case .intervalDays:
        return s.intervalDays == 1 ? "every day" : "every \(jsNumberString(s.intervalDays ?? 1)) days"
    default: return "as needed"
    }
}

/// Propose a protocol from the compound taken most recently.
public func inferProtocol(_ logs: [DoseLog], resolve: (String) -> Peptide?, siteWindow: Int = 10) -> InferredProtocol? {
    let usable = logs.filter { !$0.isSkipped && $0.doseMcg > 0 }
    guard let first = usable.first else { return nil }
    let newest = usable.reduce(first) { $1.at > $0.at ? $1 : $0 }
    guard let peptide = resolve(newest.peptideId) else { return nil }
    let mine = usable.filter { $0.peptideId == newest.peptideId }.stableSorted { $0.at < $1.at }
    let times = mine.map(\.at)
    let (schedule, confidence) = scheduleFrom(times)
    var sites: [InjectionSite] = []
    for s in mine.suffix(siteWindow).compactMap(\.site) where !sites.contains(s) { sites.append(s) }
    let doseMcg = mine[mine.count - 1].doseMcg
    let doseMg = jsNumberString(jsFixed(doseMcg / 1000, 3))
    let plural = mine.count == 1 ? "" : "s"
    let rotating = sites.isEmpty ? "" : " rotating through \(sites.count) site\(sites.count == 1 ? "" : "s")"
    return InferredProtocol(peptideId: peptide.id, peptideName: peptide.name, doseMcg: doseMcg, schedule: schedule, sites: sites,
                            startedAt: times[0], lastAt: times[times.count - 1], doseCount: mine.count,
                            summary: "\(doseMg) mg of \(peptide.name) \(describeSchedule(schedule)), from \(mine.count) logged dose\(plural)\(rotating).",
                            confidence: confidence)
}

/// Every compound in the history that could become its own protocol, newest first.
public func inferAllProtocols(_ logs: [DoseLog], resolve: (String) -> Peptide?, siteWindow: Int = 10) -> [InferredProtocol] {
    var ids: [String] = []
    for l in logs where !l.isSkipped && l.doseMcg > 0 && !ids.contains(l.peptideId) { ids.append(l.peptideId) }
    return ids.compactMap { id in inferProtocol(logs.filter { $0.peptideId == id }, resolve: resolve, siteWindow: siteWindow) }
        .stableSorted { $0.lastAt > $1.lastAt }
}
