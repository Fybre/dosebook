import Foundation
import Testing
@testable import BenchCore

@Suite struct MissedDoseTests {
    func setup() -> (AppData, String) {
        var d = AppData()
        let id = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 500,
                                            schedule: Schedule(kind: .daily, timesOfDay: ["08:00", "20:00"])))
        d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, reconstitutedAt: local(2026, 7, 1), diluentMl: 2))
        return (d, id)
    }

    @Test func findsWhatWasNotLogged() {
        var (d, pid) = setup()
        d.addLog(DoseLog(id: "", profileId: "", protocolId: pid, peptideId: "bpc-157", at: local(2026, 7, 2, 8, 10), doseMcg: 250, route: .subcutaneous))
        let now = local(2026, 7, 3, 12)
        let missed = missedDoses(d.protocols, d.logs, fromMs: local(2026, 7, 1), nowMs: now)
        // Today's morning is past; its evening is not yet due.
        #expect(missed.map(\.day) == [local(2026, 7, 3), local(2026, 7, 2), local(2026, 7, 1)])
        #expect(missed[0].doses.map(\.at) == [local(2026, 7, 3, 8)])
        #expect(missed[1].doses.map(\.at) == [local(2026, 7, 2, 20)])
        #expect(missed[2].doses.count == 2)
        #expect(missed[2].doses[0].doseMcg == 250)
    }

    @Test func loggingOneAtItsTime() throws {
        var (d, pid) = setup()
        let now = local(2026, 7, 3, 12)
        let m = missedDoses(d.protocols, d.logs, fromMs: local(2026, 7, 2), nowMs: now)[0].doses[0]
        let logged = d.logMissed(m)
        let log = try #require(d.logs.first { $0.id == logged })
        #expect(log.at == local(2026, 7, 3, 8) && log.doseMcg == 250 && log.protocolId == pid && log.vialId != nil)
        #expect(missedDoses(d.protocols, d.logs, fromMs: local(2026, 7, 3), nowMs: now).isEmpty)
        // Not twice.
        #expect(d.logMissed(m) == nil)
    }

    @Test func skippingOneAnswersIt() {
        var (d, _) = setup()
        let now = local(2026, 7, 3, 12)
        let m = missedDoses(d.protocols, d.logs, fromMs: local(2026, 7, 3), nowMs: now)[0].doses[0]
        d.logMissed(m, skipped: true)
        #expect(d.logs.first?.isSkipped == true && d.vials[0].drawnMcg ?? 0 == 0)
        #expect(missedDoses(d.protocols, d.logs, fromMs: local(2026, 7, 3), nowMs: now).isEmpty)
    }

    @Test func lateNightDoseOnTheNextDayDoesNotBlockIt() throws {
        // The evening's dose taken after midnight belongs to the next day, so the
        // evening is missed, and logging it must work rather than count that dose.
        var (d, pid) = setup()
        d.addLog(DoseLog(id: "", profileId: "", protocolId: pid, peptideId: "bpc-157", at: local(2026, 7, 3, 1, 20), doseMcg: 250, route: .subcutaneous))
        let now = local(2026, 7, 3, 12)
        let m = try #require(missedDoses(d.protocols, d.logs, fromMs: local(2026, 7, 2), nowMs: now).first { $0.day == local(2026, 7, 2) }?.doses.last)
        #expect(m.at == local(2026, 7, 2, 20))
        #expect(d.logMissed(m) != nil)
        #expect(missedDoses(d.protocols, d.logs, fromMs: local(2026, 7, 2), nowMs: now).allSatisfy { $0.day != local(2026, 7, 2) || !$0.doses.contains { $0.at == m.at } })
    }

    @Test func earlyHoursCountForTheNightBefore() {
        var d = AppData()
        let pid = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 500,
                                             schedule: Schedule(kind: .daily, timesOfDay: ["23:00"])))
        d.addLog(DoseLog(id: "", profileId: "", protocolId: pid, peptideId: "bpc-157", at: local(2026, 7, 3, 1, 20), doseMcg: 500, route: .subcutaneous))
        let now = local(2026, 7, 3, 12)
        // Off: the 1:20 dose is the 3rd's, so the 2nd's evening is missed.
        #expect(dayProgress(d.protocols, d.logs, local(2026, 7, 2)).taken == 0)
        #expect(dayProgress(d.protocols, d.logs, local(2026, 7, 3)).taken == 1)
        // On: it answers the 2nd's 11 pm dose, and the 3rd's is still to come.
        #expect(dayProgress(d.protocols, d.logs, local(2026, 7, 2), earlyHours: 4).taken == 1)
        #expect(dayProgress(d.protocols, d.logs, local(2026, 7, 3), earlyHours: 4).taken == 0)
        #expect(missedDoses(d.protocols, d.logs, fromMs: local(2026, 7, 2), nowMs: now, earlyHours: 4).isEmpty)
    }

    @Test func earlyHoursKeepADoseScheduledThen() {
        // A 2 am dose taken at 2:10 is that day's, not the night before's.
        var d = AppData()
        let pid = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 500,
                                             schedule: Schedule(kind: .daily, timesOfDay: ["02:00"])))
        d.addLog(DoseLog(id: "", profileId: "", protocolId: pid, peptideId: "bpc-157", at: local(2026, 7, 3, 2, 10), doseMcg: 500, route: .subcutaneous))
        #expect(dayProgress(d.protocols, d.logs, local(2026, 7, 3), earlyHours: 4).taken == 1)
        #expect(dayProgress(d.protocols, d.logs, local(2026, 7, 2), earlyHours: 4).taken == 0)
    }

    @Test func nothingBeforeAPlanStarted() {
        let (d, _) = setup()
        #expect(missedDoses(d.protocols, d.logs, fromMs: local(2026, 6, 1), nowMs: local(2026, 7, 1, 7)).isEmpty)
    }
}
