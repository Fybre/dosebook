import Foundation
import Testing
@testable import BenchCore

@Suite struct PauseTests {
    func setup() -> (AppData, String) {
        var d = AppData()
        let id = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 500,
                                            schedule: Schedule(kind: .daily, timesOfDay: ["08:00", "20:00"])))
        return (d, id)
    }

    @Test func dosesInThePauseAreNotScheduled() {
        var (d, _) = setup()
        d.pauseAll(until: local(2026, 7, 6), now: local(2026, 7, 3, 12))
        let p = d.protocols[0]
        let times = protocolDoseTimesBetween(p, local(2026, 7, 2), local(2026, 7, 7))
        // Before the pause: the 2nd and the 3rd's morning. After: from the 6th.
        #expect(times.first == local(2026, 7, 2, 8))
        #expect(times.contains(local(2026, 7, 3, 8)) && !times.contains(local(2026, 7, 3, 20)))
        #expect(!times.contains(local(2026, 7, 5, 8)))
        #expect(times.contains(local(2026, 7, 6, 8)))
        #expect(protocolNextDoseTime(p, local(2026, 7, 3, 13)) == local(2026, 7, 6, 8))
        #expect(protocolPreviousDoseTime(p, local(2026, 7, 5, 12)) == local(2026, 7, 3, 8))
    }

    @Test func nothingIsMissedOrOwedForAPausedDayEvenAfterwards() {
        var (d, _) = setup()
        d.pauseAll(until: local(2026, 7, 6), now: local(2026, 7, 3, 12))
        let now = local(2026, 7, 8, 12)
        let missed = missedDoses(d.protocols, d.logs, fromMs: local(2026, 7, 4), nowMs: now)
        #expect(missed.map(\.day).sorted() == [local(2026, 7, 6), local(2026, 7, 7), local(2026, 7, 8)])
        #expect(dayProgress(d.protocols, d.logs, local(2026, 7, 4)).restDay)
        #expect(dayProgress(d.protocols, d.logs, local(2026, 7, 7)).expected == 2)
    }

    @Test func openEndedUntilResumed() {
        var (d, _) = setup()
        let start = local(2026, 7, 3, 12)
        d.pauseAll(until: nil, now: start)
        #expect(currentPause(d.protocols, local(2026, 7, 10)) == PauseState(until: nil, protocols: 1))
        #expect(protocolNextDoseTime(d.protocols[0], local(2026, 7, 4)) == nil)
        #expect(dueStatus(d.protocols[0], local(2026, 7, 10)).label == .paused)
        d.resumeAll(now: local(2026, 7, 10, 9))
        #expect(currentPause(d.protocols, local(2026, 7, 10, 10)) == nil)
        #expect(protocolNextDoseTime(d.protocols[0], local(2026, 7, 10, 10)) == local(2026, 7, 10, 20))
        // The days it covered stay clear.
        #expect(dayProgress(d.protocols, d.logs, local(2026, 7, 6)).restDay)
    }

    @Test func stateAndEarlyResume() {
        var (d, _) = setup()
        d.pauseAll(until: local(2026, 7, 6), now: local(2026, 7, 3, 12))
        #expect(currentPause(d.protocols, local(2026, 7, 4)) == PauseState(until: local(2026, 7, 6), protocols: 1))
        #expect(currentPause(d.protocols, local(2026, 7, 6, 1)) == nil)
        d.resumeAll(now: local(2026, 7, 4, 9))
        #expect(protocolNextDoseTime(d.protocols[0], local(2026, 7, 4, 10)) == local(2026, 7, 4, 20))
        // Survives a backup.
        d.pauseAll(until: local(2026, 7, 9), now: local(2026, 7, 5))
        let back = try? JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(d))
        #expect(back?.protocols[0].pauses == d.protocols[0].pauses)
    }

    @Test func pausedProtocolsOnlyAreTheRunningOnesOfTheActiveProfile() {
        var (d, _) = setup()
        var stopped = makeProtocol(peptideId: "kpv", startedAt: local(2026, 7, 1), doseMcg: 100, schedule: Schedule(kind: .daily, timesOfDay: ["09:00"]))
        stopped.active = false
        d.addProtocol(stopped)
        d.pauseAll(until: nil, now: local(2026, 7, 3))
        #expect(d.protocols.filter { !$0.pauses.isEmpty }.count == 1)
    }
}
