import Foundation
import Testing
@testable import BenchCore

@Suite struct OneOffTests {
    let now = local(2026, 7, 20, 12)

    func dose(_ pid: String, daysAgo: Double, mcg: Double = 250, skipped: Bool? = nil) -> DoseLog {
        DoseLog(id: "", profileId: "", peptideId: pid, at: now - daysAgo * DAY_MS, doseMcg: mcg, route: .subcutaneous, skipped: skipped)
    }

    @Test func aCompoundWithNoProtocolIsOneOff() {
        var d = AppData()
        d.addLog(dose("aod-9604", daysAgo: 0.1))
        d.addLog(dose("aod-9604", daysAgo: 3))
        let found = oneOffCompounds(d, nowMs: now)
        #expect(found.count == 1 && found[0].peptideId == "aod-9604" && found[0].doses.count == 2)
        #expect(found[0].last.at > found[0].doses[1].at)
    }

    @Test func aCompoundWithAnActiveProtocolIsNot() {
        var d = AppData()
        _ = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), schedule: Schedule(kind: .daily, timeOfDay: "08:00")))
        d.addLog(dose("bpc-157", daysAgo: 0.1))
        #expect(oneOffCompounds(d, nowMs: now).isEmpty)
        // Stopped, it is just a compound taken recently.
        d.updateProtocol(d.protocols[0].id) { $0.active = false }
        #expect(oneOffCompounds(d, nowMs: now).map(\.peptideId) == ["bpc-157"])
    }

    @Test func oldSkippedAndEmptyDosesDoNotCount() {
        var d = AppData()
        d.addLog(dose("a", daysAgo: 20))
        d.addLog(dose("b", daysAgo: 1, skipped: true))
        d.addLog(dose("c", daysAgo: 1, mcg: 0))
        d.addLog(dose("d", daysAgo: -2))   // not yet happened
        #expect(oneOffCompounds(d, nowMs: now).isEmpty)
    }

    @Test func mostRecentFirstAndColoursComeAfterTheProtocols() {
        var d = AppData()
        _ = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), schedule: Schedule(kind: .daily, timeOfDay: "08:00")))
        d.addLog(dose("x", daysAgo: 5))
        d.addLog(dose("y", daysAgo: 1))
        let found = oneOffCompounds(d, nowMs: now)
        #expect(found.map(\.peptideId) == ["y", "x"])
        let protocolOnly = assignColors(colorSubjects(d.protocols, resolve: { d.peptide($0) }, nowMs: now))
        let both = assignColors(colorSubjects(d.protocols, resolve: { d.peptide($0) }, nowMs: now) + oneOffColorSubjects(found, resolve: { d.peptide($0) }))
        #expect(both.byProtocol[d.protocols[0].id] == protocolOnly.byProtocol[d.protocols[0].id], "no protocol's colour moves")
        #expect(both.byKey["oneoff:y"] != nil && both.byPeptide["y"] != nil)
    }
}
