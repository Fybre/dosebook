import Foundation
import Testing
import BenchCore
@testable import BenchStore

/// Three years of heavy use: two daily compounds and one weekly, with weights and check-ins.
@MainActor
func largeDocument() -> AppData {
    var d = AppData()
    let day: Double = 86_400_000
    let start: Double = 1_700_000_000_000
    for i in 0..<(3 * 365) {
        let at = start + Double(i) * day
        for p in ["bpc-157", "tb-500"] {
            _ = d.addLog(DoseLog(id: "", profileId: "", peptideId: p, at: at + 8 * 3_600_000, doseMcg: 250, route: .subcutaneous, site: .abdomenUL))
        }
        if i % 7 == 0 { _ = d.addLog(DoseLog(id: "", profileId: "", peptideId: "tirzepatide", at: at, doseMcg: 5000, route: .subcutaneous)) }
        _ = d.addMeasurement(BodyMeasurement(id: "", profileId: "", at: at, weightKg: 90 - Double(i) / 100))
        _ = d.saveCheckIn(at: at, ratings: ["energy": 4, "mood": 3], notes: nil, now: start + 4 * 365 * day)
    }
    return d
}

@MainActor @Suite struct PerformanceTests {
    @Test func mutationOnALargeHistoryStaysFast() throws {
        let records = try RecordStore(location: .memory)
        let store = AppStore(records: records, defaults: UserDefaults(suiteName: "bench-perf-\(UUID().uuidString)")!, rescueURL: nil)
        let big = largeDocument()
        var t0 = Date()
        store.mutate { $0 = big }
        let initial = Date().timeIntervalSince(t0)
        t0 = Date()
        for _ in 0..<5 {
            store.mutate { _ = $0.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: 1_800_000_000_000, doseMcg: 250, route: .subcutaneous)) }
        }
        let perTap = Date().timeIntervalSince(t0) / 5
        print("rows: \(big.logs.count) logs, \(big.measurements.count) weights, \(big.checkIns.count) check-ins; first write \(initial)s, then \(perTap)s per change")
        #expect(perTap < 0.25)
        t0 = Date()
        store.reload()
        print("reload \(Date().timeIntervalSince(t0))s")
    }
}

@Suite struct ChartPerformanceTests {
    @Test func threeWeekChartOverThreeYearsOfDoses() {
        let day: Double = 86_400_000, now: Double = 1_800_000_000_000
        let doses = (0..<1100).map { DoseEvent(at: now - Double($0) * day, amountMcg: 250) }
        let params = CurveParams(halfLifeHours: 4, tmaxHours: 0.5)
        let t0 = Date()
        for _ in 0..<3 { _ = levelSeries(now - 14 * day, now + 7 * day, 1500, doses, params, 250) }
        let per = Date().timeIntervalSince(t0) / 3
        print("one 1500-point series over 1100 doses: \(per)s")
        #expect(per < 0.1)
    }
}
