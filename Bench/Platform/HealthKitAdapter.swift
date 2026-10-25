import Foundation
import HealthKit
import BenchCore
import BenchStore

/// Apple Health, read-only: weight, sleep and resting heart rate. Nothing is ever written back.
@MainActor
enum HealthKitAdapter {
    enum Availability { case unavailable, notAsked, asked }

    private static let store = HKHealthStore()
    private static var readTypes: Set<HKObjectType> {
        [HKQuantityType(.bodyMass), HKCategoryType(.sleepAnalysis), HKQuantityType(.restingHeartRate)]
    }

    /// Apple does not tell an app whether reading was allowed, only whether it has asked.
    static func availability() async -> Availability {
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        let status = try? await store.statusForAuthorizationRequest(toShare: [], read: readTypes)
        return status == .unnecessary ? .asked : .notAsked
    }

    static func requestPermissions() async -> Bool {
        guard HKHealthStore.isHealthDataAvailable() else { return false }
        do { try await store.requestAuthorization(toShare: [], read: readTypes); return true } catch { return false }
    }

    private static func samples(_ type: HKSampleType, since: Millis) async throws -> [HKSample] {
        let predicate = HKQuery.predicateForSamples(withStart: Date(millis: since), end: nil)
        return try await withCheckedThrowingContinuation { cont in
            let q = HKSampleQuery(sampleType: type, predicate: predicate, limit: HKObjectQueryNoLimit,
                                  sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]) { _, results, error in
                if let error { cont.resume(throwing: error) } else { cont.resume(returning: results ?? []) }
            }
            store.execute(q)
        }
    }

    static func readWeight(since: Millis) async throws -> [HealthSample] {
        try await samples(HKQuantityType(.bodyMass), since: since).compactMap { s in
            guard let q = s as? HKQuantitySample else { return nil }
            return HealthSample(externalId: "hk:\(s.uuid.uuidString)", at: s.startDate.millis, weightKg: q.quantity.doubleValue(for: .gramUnit(with: .kilo)))
        }
    }

    static func readSleep(since: Millis) async throws -> [SleepSegment] {
        try await samples(HKCategoryType(.sleepAnalysis), since: since).compactMap { s in
            guard let c = s as? HKCategorySample else { return nil }
            let state: String
            switch HKCategoryValueSleepAnalysis(rawValue: c.value) {
            case .inBed: state = "inBed"
            case .awake: state = "awake"
            case .asleepREM: state = "rem"
            case .asleepDeep: state = "deep"
            case .asleepCore: state = "light"
            default: state = "asleep"
            }
            return SleepSegment(externalId: "hk:\(s.uuid.uuidString)", startAt: s.startDate.millis, endAt: s.endDate.millis, state: state)
        }
    }

    static func readRestingHr(since: Millis) async throws -> [HeartRateSample] {
        let bpm = HKUnit.count().unitDivided(by: .minute())
        return try await samples(HKQuantityType(.restingHeartRate), since: since).compactMap { s in
            guard let q = s as? HKQuantitySample else { return nil }
            return HeartRateSample(externalId: "hk:\(s.uuid.uuidString)", at: s.startDate.millis, bpm: q.quantity.doubleValue(for: bpm))
        }
    }

    private static var pulling = false

    /// New weigh-ins since the newest one already brought in from Health (or the
    /// last year), added and linked by their Health record id. Nil when Health is
    /// not connected or another pull is under way. Read-only, as everything here is.
    ///
    /// From the newest Health reading, not the newest of any: a weight typed in at
    /// 8:00 would otherwise hide a scale's 7:00 reading that reached Health at 9:00.
    @discardableResult
    static func pullWeight(into store: AppStore, now: Millis = nowMillis()) async throws -> PullPlan? {
        // Claimed before the first await, so two pulls started together cannot both pass.
        guard !pulling else { return nil }
        pulling = true
        defer { pulling = false }
        guard await availability() == .asked else { return nil }
        let measurements = store.data.mine.measurements
        let newest = measurements.filter { $0.externalId?.hasPrefix("hk:") == true }.map(\.at).max() ?? 0
        let since = newest > 0 ? newest : now - 365 * DAY_MS
        let plan = planPull(measurements, try await readWeight(since: since))
        if !plan.toAdd.isEmpty || !plan.toLink.isEmpty {
            store.mutate { d in
                for s in plan.toAdd {
                    d.addMeasurement(BodyMeasurement(id: "", profileId: "", at: s.at, weightKg: s.weightKg, source: .healthConnect, externalId: s.externalId))
                }
                for l in plan.toLink { d.updateMeasurement(l.id) { $0.externalId = l.externalId } }
            }
        }
        return plan
    }

    /// Sleep and resting heart rate for the last month, onto each day's vitals.
    static func pullVitals(into store: AppStore, now: Millis = nowMillis()) async {
        guard await availability() == .asked else { return }
        let since = now - 30 * DAY_MS
        guard let sleep = try? await readSleep(since: since), let hr = try? await readRestingHr(since: since) else { return }
        var byDay = OrderedMap<Millis, (sleep: Double?, hr: Double?)>()
        for n in nightlySleep(sleep) { byDay[n.day] = (n.hours, nil) }
        for r in dailyRestingHr(hr) { byDay[r.day] = (byDay[r.day]?.sleep, r.bpm) }
        guard !byDay.isEmpty else { return }
        store.mutate { d in for (day, v) in byDay.entries { d.recordVitals(dayMs: day, sleepHours: v.sleep, restingHrBpm: v.hr) } }
    }
}
