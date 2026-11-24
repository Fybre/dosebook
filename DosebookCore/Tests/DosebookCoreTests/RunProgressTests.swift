import Foundation
import Testing
@testable import DosebookCore

@Suite struct RunProgressTests {
    @Test func dayCountAndNoCycle() {
        let p = makeProtocol(startedAt: local(2026, 7, 1), schedule: Schedule(kind: .daily))
        #expect(runProgress(p, local(2026, 7, 1, 9))?.day == 1)
        let r = runProgress(p, local(2026, 7, 27, 9))
        #expect(r?.day == 27 && r?.daysOn == 27 && r?.daysPaused == 0 && r?.cycle == nil)
        #expect(runProgress(p, local(2026, 6, 30)) == nil)
    }

    @Test func cycleWeeks() {
        var s = Schedule(kind: .daily); s.cycleWeeksOn = 8; s.cycleWeeksOff = 4
        let p = makeProtocol(startedAt: local(2026, 7, 1), schedule: s)
        let c = runProgress(p, local(2026, 7, 29, 9))?.cycle   // day 29: week 5
        #expect(c?.phase == .on && c?.week == 5 && c?.weeks == 8 && c?.weeksOff == 4)
        #expect(c?.changesAt == local(2026, 8, 26))
        let off = runProgress(p, local(2026, 8, 27, 9))?.cycle  // 57 days in: first off week
        #expect(off?.phase == .off && off?.week == 1 && off?.weeks == 4 && off?.changesAt == local(2026, 9, 23))
        let again = runProgress(p, local(2026, 9, 23, 9))?.cycle
        #expect(again?.phase == .on && again?.week == 1)
    }

    @Test func courseFinishes() {
        var s = Schedule(kind: .daily); s.cycleWeeksOn = 4
        let p = makeProtocol(startedAt: local(2026, 7, 1), schedule: s)
        #expect(runProgress(p, local(2026, 7, 10))?.cycle?.phase == .on)
        #expect(runProgress(p, local(2026, 7, 29, 9))?.cycle?.phase == .finished)
    }

    @Test func pausedDaysAreTakenOff() {
        var p = makeProtocol(startedAt: local(2026, 7, 1), schedule: Schedule(kind: .daily))
        p.pauses = [PauseWindow(from: local(2026, 7, 10), until: local(2026, 7, 14)),
                    PauseWindow(from: local(2026, 7, 12), until: local(2026, 7, 16))]
        let r = runProgress(p, local(2026, 7, 30, 9))   // day 30; paused 10th to 15th = 6 days, overlap counted once
        #expect(r?.day == 30 && r?.daysPaused == 6 && r?.daysOn == 24)
        // A pause still running counts up to today.
        p.pauses = [PauseWindow(from: local(2026, 7, 28))]
        let open = runProgress(p, local(2026, 7, 30, 9))
        #expect(open?.daysPaused == 3)
    }
}
