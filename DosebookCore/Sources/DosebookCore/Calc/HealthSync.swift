import Foundation

// Port of src/lib/calc/healthsync.ts. Readings from the platform health store
// (HealthKit on iOS) come in; nothing goes back out. A sample already seen, by
// id or by closely matching a typed reading, is never added twice.

public struct HealthSample: Equatable, Sendable {
    public var externalId: String
    public var at: Millis
    public var weightKg: Double
    public init(externalId: String, at: Millis, weightKg: Double) {
        self.externalId = externalId; self.at = at; self.weightKg = weightKg
    }
}

public let MATCH_WINDOW_MS: Double = 5 * 60_000
public let MATCH_WEIGHT_KG = 0.15

private func isSameReading(_ m: BodyMeasurement, _ s: HealthSample) -> Bool {
    guard let kg = m.weightKg else { return false }
    return abs(m.at - s.at) <= MATCH_WINDOW_MS && abs(kg - s.weightKg) <= MATCH_WEIGHT_KG
}

public struct HealthLink: Equatable, Sendable { public var id: String; public var externalId: String }

public struct PullPlan: Equatable, Sendable {
    public var toAdd: [HealthSample]
    /// Typed readings that match a platform sample adopt its id.
    public var toLink: [HealthLink]
    public var skipped: Int
}

public func planPull(_ existing: [BodyMeasurement], _ incoming: [HealthSample]) -> PullPlan {
    let known = Set(existing.compactMap(\.externalId).filter { !$0.isEmpty })
    var toAdd: [HealthSample] = [], toLink: [HealthLink] = []
    var claimed = Set<String>()
    var skipped = 0
    for s in incoming {
        if known.contains(s.externalId) { skipped += 1; continue }
        if let match = existing.first(where: { ($0.externalId ?? "").isEmpty && !claimed.contains($0.id) && isSameReading($0, s) }) {
            claimed.insert(match.id)
            toLink.append(HealthLink(id: match.id, externalId: s.externalId))
        } else {
            toAdd.append(s)
        }
    }
    return PullPlan(toAdd: toAdd, toLink: toLink, skipped: skipped)
}

/// The newest usable sample, whatever order they came in.
public func newestSample(_ samples: [HealthSample]) -> HealthSample? {
    var best: HealthSample?
    for s in samples where s.weightKg > 0 { if best == nil || s.at > best!.at { best = s } }
    return best
}

public func sampleToMeasurement(_ s: HealthSample, profileId: String, id: String) -> BodyMeasurement {
    BodyMeasurement(id: id, profileId: profileId, at: s.at, weightKg: s.weightKg, source: .healthConnect, externalId: s.externalId)
}

public struct SyncSummary: Equatable, Sendable { public var added: Int; public var linked: Int; public var skipped: Int }

public func summarise(_ plan: PullPlan) -> SyncSummary {
    SyncSummary(added: plan.toAdd.count, linked: plan.toLink.count, skipped: plan.skipped)
}

public struct SleepSegment: Equatable, Sendable {
    public var externalId: String
    public var startAt: Millis
    public var endAt: Millis
    /// asleep, rem, deep, light, awake, inBed.
    public var state: String?
    public init(externalId: String, startAt: Millis, endAt: Millis, state: String? = nil) {
        self.externalId = externalId; self.startAt = startAt; self.endAt = endAt; self.state = state
    }
}

public struct NightSleep: Equatable, Sendable {
    /// Local midnight of the day woken on.
    public var day: Millis
    public var hours: Double
    public var segments: Int
}

public struct Span: Equatable, Sendable { public var startAt: Millis; public var endAt: Millis }

/// Merge overlapping intervals, so a session and its stages are not counted twice.
public func mergeIntervals(_ spans: [Span]) -> [Span] {
    var out: [Span] = []
    for s in spans.filter({ $0.endAt > $0.startAt }).stableSorted(by: { $0.startAt < $1.startAt }) {
        if let last = out.last, s.startAt <= last.endAt { out[out.count - 1].endAt = max(last.endAt, s.endAt) }
        else { out.append(s) }
    }
    return out
}

/// Total sleep per night, credited to the day woken on, newest first.
public func nightlySleep(_ segments: [SleepSegment], startOfDay: (Millis) -> Millis = startOfLocalDay) -> [NightSleep] {
    var byDay = OrderedMap<Millis, [Span]>()
    for s in segments where s.endAt > s.startAt {
        if let st = s.state?.lowercased(), st == "awake" || st == "inbed" { continue }
        let day = startOfDay(s.endAt)
        byDay[day] = (byDay[day] ?? []) + [Span(startAt: s.startAt, endAt: s.endAt)]
    }
    return byDay.entries.map { day, spans in
        let merged = mergeIntervals(spans)
        return NightSleep(day: day, hours: merged.reduce(0) { $0 + ($1.endAt - $1.startAt) } / HOUR_MS, segments: merged.count)
    }.stableSorted { $0.day > $1.day }
}

public struct HeartRateSample: Equatable, Sendable {
    public var externalId: String
    public var at: Millis
    public var bpm: Double
    public init(externalId: String, at: Millis, bpm: Double) { self.externalId = externalId; self.at = at; self.bpm = bpm }
}

public struct DayRate: Equatable, Sendable { public var day: Millis; public var bpm: Double }

/// The lowest resting reading of each day, newest first.
public func dailyRestingHr(_ samples: [HeartRateSample], startOfDay: (Millis) -> Millis = startOfLocalDay) -> [DayRate] {
    var byDay = OrderedMap<Millis, Double>()
    for s in samples where s.bpm > 0 {
        let day = startOfDay(s.at)
        if let seen = byDay[day] { if s.bpm < seen { byDay[day] = s.bpm } } else { byDay[day] = s.bpm }
    }
    return byDay.entries.map { DayRate(day: $0.key, bpm: $0.value) }.stableSorted { $0.day > $1.day }
}

/// A sentence for the settings screen.
public func describeSync(_ s: SyncSummary) -> String {
    var bits: [String] = []
    if s.added > 0 { bits.append("\(s.added) brought in") }
    if s.linked > 0 { bits.append("\(s.linked) matched to yours") }
    return bits.isEmpty ? "Already up to date." : "\(bits.joined(separator: ", "))."
}
