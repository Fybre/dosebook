import Foundation
import Testing
@testable import BenchCore

/// The day count as it was before `dayBreakdown`, kept to prove the rewrite changes nothing.
private func referenceProgress(_ protocols: [DoseProtocol], _ logs: [DoseLog], _ dayMs: Millis) -> (expected: Int, taken: Int, skipped: Int) {
    let day = startOfLocalDay(dayMs), end = endOfLocalDay(dayMs)
    let active = protocols.filter(\.active)
    let slots = active.map { protocolDoseTimesBetween($0, day, end).count }
    let onDay = logs.filter { $0.at >= day && $0.at <= end }
    var taken = Array(repeating: 0, count: active.count), skipped = Array(repeating: 0, count: active.count)
    var claimed = Set<Int>()
    func room(_ i: Int) -> Int { slots[i] - taken[i] - skipped[i] }
    func credit(_ i: Int, _ l: DoseLog, _ idx: Int) { if l.isSkipped { skipped[i] += 1 } else { taken[i] += 1 }; claimed.insert(idx) }
    for (idx, l) in onDay.enumerated() { if let i = active.firstIndex(where: { l.protocolId == $0.id }), room(i) > 0 { credit(i, l, idx) } }
    for (idx, l) in onDay.enumerated() where !claimed.contains(idx) {
        if let i = active.indices.first(where: { active[$0].peptideId == l.peptideId && room($0) > 0 }) { credit(i, l, idx) }
    }
    return (slots.reduce(0, +), taken.reduce(0, +), skipped.reduce(0, +))
}

private func dose(_ at: Millis, _ peptide: String = "bpc-157", protocolId: String? = nil, skipped: Bool = false) -> DoseLog {
    DoseLog(id: UUID().uuidString, profileId: "me", protocolId: protocolId, peptideId: peptide, at: at, doseMcg: 250, route: .subcutaneous, skipped: skipped ? true : nil)
}

@Suite struct DayBreakdownTests {
    let start = local(2026, 7, 1)
    var twiceDaily: DoseProtocol {
        makeProtocol(id: "bpc", peptideId: "bpc-157", startedAt: start, doseMcg: 250, schedule: Schedule(kind: .daily, timesOfDay: ["08:00", "20:00"]))
    }
    var weekly: DoseProtocol {
        makeProtocol(id: "tirz", peptideId: "tirzepatide", startedAt: start, doseMcg: 5000, schedule: Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "09:00"))
    }

    @Test func laysOutEachScheduledDose() {
        let day = local(2026, 7, 6)
        let b = dayBreakdown([twiceDaily], [dose(local(2026, 7, 6, 20, 15), protocolId: "bpc")], day, nowMs: local(2026, 7, 7))
        #expect(b.protocols.count == 1)
        let slots = b.protocols[0].slots
        #expect(slots.map(\.at) == [local(2026, 7, 6, 8), local(2026, 7, 6, 20)])
        #expect(slots[0].slot == .missed)
        if case .taken(let l) = slots[1].slot { #expect(l.at == local(2026, 7, 6, 20, 15)) } else { Issue.record("evening dose not matched") }
        #expect(b.unplanned.isEmpty)
    }

    @Test func laterTodayIsDueNotMissed() {
        let b = dayBreakdown([twiceDaily], [], local(2026, 7, 6), nowMs: local(2026, 7, 6, 12))
        #expect(b.protocols[0].slots.map(\.slot) == [.missed, .due])
    }

    @Test func skipsAndUnplanned() {
        let b = dayBreakdown([twiceDaily], [dose(local(2026, 7, 6, 8), skipped: true), dose(local(2026, 7, 6, 21)), dose(local(2026, 7, 6, 22)),
                                            dose(local(2026, 7, 6, 12), "tb-500")], local(2026, 7, 6), nowMs: local(2026, 7, 7))
        #expect(b.protocols[0].slots.map(\.slot).count == 2)
        if case .skipped = b.protocols[0].slots[0].slot {} else { Issue.record("morning should be skipped") }
        // A third BPC dose has no slot left, and TB-500 has no protocol.
        #expect(b.unplanned.map(\.peptideId) == ["tb-500", "bpc-157"])
    }

    @Test func restDayHasNothingScheduled() {
        let b = dayBreakdown([weekly], [], local(2026, 7, 3), nowMs: local(2026, 7, 10))
        #expect(b.protocols.isEmpty)
    }

    @Test func agreesWithTheOriginalCount() {
        var rng = LCG(7)
        let peptides = ["bpc-157", "tirzepatide", "tb-500"]
        for _ in 0..<300 {
            var logs: [DoseLog] = []
            for _ in 0..<Int(rng.next() * 8) {
                let at = local(2026, 7, 6) + rng.next() * DAY_MS
                let named = rng.next() < 0.5
                let pep = peptides[Int(rng.next() * 3)]
                logs.append(dose(at, pep, protocolId: named ? (pep == "bpc-157" ? "bpc" : pep == "tirzepatide" ? "tirz" : "zzz") : nil, skipped: rng.next() < 0.2))
            }
            let ref = referenceProgress([twiceDaily, weekly], logs, local(2026, 7, 6))
            let now = dayProgress([twiceDaily, weekly], logs, local(2026, 7, 6))
            #expect(now.expected == ref.expected && now.taken == ref.taken && now.skipped == ref.skipped)
        }
    }
}
