import Foundation
import Testing
@testable import BenchCore

@Suite struct ReminderLogTests {
    func setup() -> (AppData, String) {
        var d = AppData()
        let id = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 250,
                                            schedule: Schedule(kind: .daily, timesOfDay: ["08:00", "20:00"]), sites: [.abdomenUL, .abdomenUR]))
        d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, reconstitutedAt: local(2026, 7, 1), diluentMl: 2))
        return (d, id)
    }

    @Test func logsTheScheduledDose() throws {
        var (d, pid) = setup()
        let logged = d.logFromReminder(protocolId: pid, doseAt: local(2026, 7, 6, 8), now: local(2026, 7, 6, 8, 5))
        let id = try #require(logged)
        let log = try #require(d.logs.first { $0.id == id })
        // The day's 250 mcg split across its two times.
        #expect(log.doseMcg == 125 && log.at == local(2026, 7, 6, 8, 5) && log.protocolId == pid)
        #expect([InjectionSite.abdomenUL, .abdomenUR].contains(log.site!))
        // Drawn from the vial, with its marks read off.
        #expect(log.vialId != nil && log.units == 5)
        #expect(d.vials[0].drawnMcg == 125)
    }

    @Test func aSecondTapDoesNotLogTwice() {
        var (d, pid) = setup()
        #expect(d.logFromReminder(protocolId: pid, doseAt: local(2026, 7, 6, 8), now: local(2026, 7, 6, 8, 5)) != nil)
        #expect(d.logFromReminder(protocolId: pid, doseAt: local(2026, 7, 6, 8), now: local(2026, 7, 6, 8, 9)) == nil)
        // The evening dose is its own.
        #expect(d.logFromReminder(protocolId: pid, doseAt: local(2026, 7, 6, 20), now: local(2026, 7, 6, 20, 1)) != nil)
        #expect(d.logs.count == 2)
    }

    @Test func aDoseLoggedInTheAppAlreadyCounts() {
        var (d, pid) = setup()
        d.addLog(DoseLog(id: "", profileId: "", protocolId: pid, peptideId: "bpc-157", at: local(2026, 7, 6, 7, 40), doseMcg: 250, route: .subcutaneous))
        #expect(d.logFromReminder(protocolId: pid, doseAt: local(2026, 7, 6, 8), now: local(2026, 7, 6, 8, 5)) == nil)
    }

    @Test func aRemovedProtocolLogsNothing() {
        var (d, _) = setup()
        #expect(d.logFromReminder(protocolId: "gone", doseAt: local(2026, 7, 6, 8)) == nil)
        #expect(d.logs.isEmpty)
    }
}
