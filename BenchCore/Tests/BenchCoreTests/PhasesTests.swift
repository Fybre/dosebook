import Foundation
import Testing
@testable import BenchCore

// Port of src/lib/calc/phases.test.ts.

struct PhaseFixture {
    let start = local(2026, 1, 5, 9)
    let ladder = [ProtocolPhase(step: 1, doseMcg: 1000, weeks: 3), ProtocolPhase(step: 2, doseMcg: 2000, weeks: 3),
                  ProtocolPhase(step: 3, doseMcg: 3000, weeks: 1), ProtocolPhase(step: 4, doseMcg: 4000, weeks: 1)]
    func proto(startedAt: Millis? = nil, endedAt: Millis? = nil, doseMcg: Double = 1000,
               schedule: Schedule = Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "09:00"),
               titration: [TitrationStep]? = nil, auto: Bool = false, phases: [ProtocolPhase]? = nil) -> DoseProtocol {
        makeProtocol(peptideId: "retatrutide", name: "Test", startedAt: startedAt ?? start, endedAt: endedAt, doseMcg: doseMcg,
                     schedule: schedule, titration: titration, titrationAutoAdvance: auto, phases: phases)
    }
}

@Suite struct PhaseListTests {
    let f = PhaseFixture()

    @Test func protocolPhasesCases() {
        #expect(protocolPhases(f.proto()) == nil)
        let t = f.proto(titration: [TitrationStep(step: 1, doseMcg: 2000, weeks: 4), TitrationStep(step: 2, doseMcg: 4000, weeks: 4)], auto: true)
        #expect(protocolPhases(t)?.map(\.doseMcg) == [2000, 4000])
        #expect(protocolPhases(f.proto(titration: [TitrationStep(step: 1, doseMcg: 2000, weeks: 4)], auto: false)) == nil)
        #expect(protocolPhases(f.proto(titration: [TitrationStep(step: 1, doseMcg: 9000, weeks: 4)], auto: true, phases: f.ladder))?[0].doseMcg == 1000)
    }

    @Test func spans() {
        let plain = phaseSpans(f.proto())
        #expect(plain.count == 1 && plain[0].anchor == f.start && plain[0].to == .infinity)
        let s = phaseSpans(f.proto(phases: f.ladder))
        #expect(s[0].anchor == f.start)
        #expect(s[1].anchor == addLocalDays(local(2026, 1, 5), 21) && s[2].anchor == addLocalDays(local(2026, 1, 5), 42) && s[3].anchor == addLocalDays(local(2026, 1, 5), 49))
        #expect(s.last!.to == .infinity)
        for i in 1..<s.count { #expect(s[i].from == s[i - 1].to + 1) }
    }

    @Test func doses() {
        let p = f.proto(phases: f.ladder)
        #expect(scheduledDoseMcg(p, f.start) == 1000 && scheduledDoseMcg(p, addLocalDays(f.start, 20)) == 1000)
        #expect(scheduledDoseMcg(p, addLocalDays(f.start, 21)) == 2000 && scheduledDoseMcg(p, addLocalDays(f.start, 42)) == 3000)
        #expect(scheduledDoseMcg(p, addLocalDays(f.start, 49)) == 4000 && scheduledDoseMcg(p, addLocalDays(f.start, 400)) == 4000)
        let stepped = f.proto(doseMcg: 9999, phases: [ProtocolPhase(step: 1, doseMcg: 1000, weeks: 3), ProtocolPhase(step: 2, doseMcg: 2000, weeks: 3)])
        #expect(scheduledDoseMcg(stepped, addLocalDays(f.start, -1)) == 1000)
        let before = phaseSpanAt(p, addLocalDays(f.start, -2))
        #expect(before?.index == 0 && before?.phase.step == 1)
        #expect(phaseSpanAt(p, addLocalDays(f.start, 22))?.index == 1)
    }

    @Test func perPhaseFrequency() {
        let mixed = [ProtocolPhase(step: 1, doseMcg: 500, weeks: 2, schedule: Schedule(kind: .intervalDays, intervalDays: 3, timeOfDay: "09:00")),
                     ProtocolPhase(step: 2, doseMcg: 1000, weeks: 4, schedule: Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "09:00"))]
        let p = f.proto(phases: mixed)
        #expect(protocolDoseTimesBetween(p, f.start, addLocalDays(f.start, 13)).map(dayOfMonth) == [5, 8, 11, 14, 17])
        #expect(protocolDoseTimesBetween(p, addLocalDays(f.start, 14), addLocalDays(f.start, 30)).map(dayOfMonth) == [19, 26, 2])
        #expect(isClose(protocolDosesPerWeek(p, addLocalDays(f.start, 3)), 7.0 / 3, digits: 5) && protocolDosesPerWeek(p, addLocalDays(f.start, 20)) == 1)
        let gap = f.proto(phases: [ProtocolPhase(step: 1, doseMcg: 500, weeks: 2, schedule: Schedule(kind: .asNeeded)), ProtocolPhase(step: 2, doseMcg: 1000, weeks: 4)])
        let next = protocolNextDoseTime(gap, f.start)
        #expect(next != nil && next! >= addLocalDays(f.start, 14))
        let times = protocolDoseTimesBetween(p, f.start, addLocalDays(f.start, 40))
        #expect(times.sorted() == times && Set(times).count == times.count)
    }

    @Test func bandOverrides() {
        let base = Schedule(kind: .daily, timeOfDay: "07:00", timesOfDay: ["07:00", "19:00"])
        let banded = f.proto(schedule: base, phases: [ProtocolPhase(step: 1, doseMcg: 500, weeks: 4, schedule: Schedule(kind: .daily, timeOfDay: "07:00")),
                                                       ProtocolPhase(step: 2, doseMcg: 1000, weeks: 4, schedule: Schedule(kind: .daily, timeOfDay: "07:00"))])
        let day = startOfLocalDay(addLocalDays(f.start, 3))
        #expect(protocolDoseTimesBetween(banded, day, addLocalDays(day, 1) - 1).map(hours) == [7, 19])
        #expect(scheduledDoseMcg(banded, addLocalDays(f.start, 3)) == 250)
        let own = f.proto(schedule: base, phases: [ProtocolPhase(step: 1, doseMcg: 500, weeks: 4, schedule: Schedule(kind: .daily, timesOfDay: ["12:00"]))])
        #expect(protocolDoseTimesBetween(own, day, addLocalDays(day, 1) - 1).map(hours) == [12] && scheduledDoseMcg(own, day) == 500)
        let weekly = f.proto(schedule: Schedule(kind: .daily, timeOfDay: "07:00"), phases: [ProtocolPhase(step: 1, doseMcg: 500, weeks: 4, schedule: Schedule(kind: .intervalDays, intervalDays: 7))])
        #expect(protocolDosesPerWeek(weekly, addLocalDays(f.start, 3)) == 1)
    }

    @Test func noPhasesUnchanged() {
        let cases: [(Schedule, Millis?)] = [
            (Schedule(kind: .daily, timeOfDay: "08:00"), nil), (Schedule(kind: .intervalDays, intervalDays: 3, timeOfDay: "09:00"), nil),
            (Schedule(kind: .daysOfWeek, daysOfWeek: [1, 4], timeOfDay: "20:00"), nil), (Schedule(kind: .asNeeded), nil),
            (Schedule(kind: .daily, timeOfDay: "09:00", cycleWeeksOn: 2, cycleWeeksOff: 1), nil),
            (Schedule(kind: .daily, timeOfDay: "09:00"), addLocalDays(f.start, 10)),
        ]
        for (schedule, ended) in cases {
            let p = f.proto(endedAt: ended, schedule: schedule)
            let to = addLocalDays(f.start, 60)
            #expect(protocolDoseTimesBetween(p, f.start, to) == doseTimesBetween(p.schedule, p.startedAt, f.start, to, p.endedAt))
            let from = addLocalDays(f.start, 5)
            #expect(protocolNextDoseTime(p, from) == nextDoseTime(p.schedule, p.startedAt, from, p.endedAt))
            let back = addLocalDays(f.start, 20)
            #expect(protocolPreviousDoseTime(p, back) == previousDoseTime(p.schedule, p.startedAt, back))
        }
    }

    @Test func figures() {
        let p = f.proto(phases: f.ladder)
        #expect(adherence(p, [LogStamp](), f.start, addLocalDays(f.start, 55)).expected == 8)
        #expect(dueStatus(p, addLocalDays(f.start, 21) + 60_000).state == .dueNow)
    }

    @Test func notStartedYet() {
        let inAWeek = addLocalDays(f.start, 7)
        let band = Schedule(kind: .daysOfWeek, daysOfWeek: [1, 2, 3, 4, 5], timeOfDay: "06:30", timesOfDay: ["06:30"])
        let r = f.proto(startedAt: inAWeek, doseMcg: 250, schedule: Schedule(kind: .intervalDays, intervalDays: 4, timeOfDay: "09:00"),
                        phases: [ProtocolPhase(step: 1, doseMcg: 250, weeks: 1, schedule: band), ProtocolPhase(step: 2, doseMcg: 500, weeks: 4, schedule: band)])
        let span = phaseSpanAt(r, f.start)
        #expect(span?.schedule.kind == .daysOfWeek && span?.schedule.daysOfWeek == [1, 2, 3, 4, 5])
        #expect(scheduleTimes(span!.schedule) == ["06:30"])
        #expect(protocolDosesPerWeek(r, f.start) == 5 && scheduledDoseMcg(r, f.start) == 250)
        #expect(protocolDoseTimesBetween(r, f.start, addLocalDays(f.start, 6)).isEmpty)
        #expect(protocolNextDoseTime(r, f.start)! >= inAWeek)
    }
}
