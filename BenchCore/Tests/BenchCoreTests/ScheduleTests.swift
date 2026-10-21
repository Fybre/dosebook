import Foundation
import Testing
@testable import BenchCore

// Port of src/lib/calc/schedule.test.ts. Run under TZ=America/New_York (tools/test.sh).

@Suite struct LocalDayArithmetic {
    @Test func snapsToLocalMidnight() {
        let d = startOfLocalDay(local(2026, 3, 15, 17, 42))
        #expect(hours(d) == 0 && minutes(d) == 0 && dayOfMonth(d) == 15)
    }

    @Test func countsWholeDays() {
        #expect(daysBetween(local(2026, 3, 1, 23, 0), local(2026, 3, 2, 1, 0)) == 1)
        #expect(daysBetween(local(2026, 3, 1), local(2026, 3, 1)) == 0)
        #expect(daysBetween(local(2026, 3, 8), local(2026, 3, 1)) == -7)
    }

    @Test func keepsWallClockAcrossDST() {
        let after = addLocalDays(local(2026, 3, 7, 9, 0), 2)
        #expect(hours(after) == 9)
        #expect(dayOfMonth(after) == 9)
    }

    @Test func dstDaysAreWholeDays() {
        #expect(daysBetween(local(2026, 3, 7), local(2026, 3, 9)) == 2)
        #expect(daysBetween(local(2026, 11, 1), local(2026, 11, 3)) == 2)
    }

    @Test func appliesTimeOfDay() {
        #expect(hours(atTimeOfDay(local(2026, 5, 4), "20:30")) == 20)
        #expect(minutes(atTimeOfDay(local(2026, 5, 4), "20:30")) == 30)
        #expect(hours(atTimeOfDay(local(2026, 5, 4))) == 9)
    }
}

@Suite struct IsDoseDay {
    let start = local(2026, 4, 1)

    @Test func daily() {
        for i in 0..<10 { #expect(isDoseDay(Schedule(kind: .daily), start, addLocalDays(start, Double(i)))) }
    }

    @Test func neverBeforeStart() {
        #expect(!isDoseDay(Schedule(kind: .daily), start, addLocalDays(start, -1)))
    }

    @Test func intervalsFromStart() {
        let s = Schedule(kind: .intervalDays, intervalDays: 3)
        #expect(isDoseDay(s, start, start))
        #expect(!isDoseDay(s, start, addLocalDays(start, 1)))
        #expect(isDoseDay(s, start, addLocalDays(start, 3)))
        #expect(isDoseDay(s, start, addLocalDays(start, 6)))
    }

    @Test func weeklyAcrossDST() {
        let march1 = local(2026, 3, 1)
        let s = Schedule(kind: .intervalDays, intervalDays: 7)
        for w in 0..<8 {
            let day = addLocalDays(march1, Double(w * 7))
            #expect(localWeekday(day) == 0)
            #expect(isDoseDay(s, march1, day))
        }
    }

    @Test func namedWeekdays() {
        let s = Schedule(kind: .daysOfWeek, daysOfWeek: [1, 4])
        let monday = local(2026, 4, 6)
        #expect(localWeekday(monday) == 1)
        #expect(isDoseDay(s, start, monday))
        #expect(!isDoseDay(s, start, addLocalDays(monday, 1)))
        #expect(isDoseDay(s, start, addLocalDays(monday, 3)))
    }

    @Test func asNeededNever() {
        #expect(!isDoseDay(Schedule(kind: .asNeeded), start, start))
    }
}

@Suite struct Cycling {
    let start = local(2026, 1, 5)

    @Test func continuousWithoutCycle() {
        #expect(isOnCycle(Schedule(kind: .daily), start, addLocalDays(start, 200)))
    }

    @Test func switchesOffAndOn() {
        let s = Schedule(kind: .daily, cycleWeeksOn: 4, cycleWeeksOff: 2)
        #expect(isOnCycle(s, start, start))
        #expect(isOnCycle(s, start, addLocalDays(start, 27)))
        #expect(!isOnCycle(s, start, addLocalDays(start, 28)))
        #expect(!isOnCycle(s, start, addLocalDays(start, 41)))
        #expect(isOnCycle(s, start, addLocalDays(start, 42)))
    }

    /// Upstream issue #11: weeks on alone is a course that ends, not a cycle that restarts.
    @Test func weeksOnAloneIsACourse() {
        let weekly = Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "09:00", cycleWeeksOn: 4)
        let doses = protocolDoseTimesBetween(makeProtocol(startedAt: start, schedule: weekly), start, addLocalDays(start, 120))
        #expect(doses.count == 4)
        #expect(doses.last.map { startOfLocalDay($0) } == addLocalDays(start, 21))
        let daily = Schedule(kind: .daily, cycleWeeksOn: 2, cycleWeeksOff: 0)
        #expect(isOnCycle(daily, start, addLocalDays(start, 13)))
        #expect(!isOnCycle(daily, start, addLocalDays(start, 14)))
        #expect(!isOnCycle(daily, start, addLocalDays(start, 300)))
        #expect(!isOnCycle(daily, start, addLocalDays(start, -1)))
    }

    @Test func suppressesOffWeek() {
        let s = Schedule(kind: .daily, cycleWeeksOn: 1, cycleWeeksOff: 1)
        #expect(isDoseDay(s, start, addLocalDays(start, 3)))
        #expect(!isDoseDay(s, start, addLocalDays(start, 10)))
    }
}

@Suite struct DoseTimesBetween {
    let start = local(2026, 6, 1)

    @Test func everyDailyDose() {
        let times = doseTimesBetween(Schedule(kind: .daily, timeOfDay: "08:00"), start, start, endOfLocalDay(addLocalDays(start, 6)))
        #expect(times.count == 7)
        #expect(hours(times[0]) == 8)
        #expect(dayOfMonth(times[6]) == 7)
    }

    @Test func onlyInsideWindow() {
        let noon = local(2026, 6, 1, 12, 0)
        let times = doseTimesBetween(Schedule(kind: .daily, timeOfDay: "08:00"), start, noon, endOfLocalDay(addLocalDays(noon, 2)))
        #expect(times.count == 2)
        #expect(dayOfMonth(times[0]) == 2)
    }

    @Test func stopsAtEnd() {
        let times = doseTimesBetween(Schedule(kind: .daily), start, start, endOfLocalDay(addLocalDays(start, 30)),
                                     endOfLocalDay(addLocalDays(start, 4)))
        #expect(times.count == 5)
    }

    @Test func asNeededAndInverted() {
        #expect(doseTimesBetween(Schedule(kind: .asNeeded), start, start, addLocalDays(start, 30)).isEmpty)
        #expect(doseTimesBetween(Schedule(kind: .daily), start, addLocalDays(start, 5), start).isEmpty)
    }

    @Test func everyTimeInOrder() {
        let times = doseTimesBetween(Schedule(kind: .daily, timesOfDay: ["22:00", "07:00"]), start, start, endOfLocalDay(addLocalDays(start, 1)))
        #expect(times == [local(2026, 6, 1, 7), local(2026, 6, 1, 22), local(2026, 6, 2, 7), local(2026, 6, 2, 22)])
    }

    @Test func severalTimesOnDoseDays() {
        let times = doseTimesBetween(Schedule(kind: .intervalDays, intervalDays: 2, timesOfDay: ["08:00", "20:00"]),
                                     start, start, endOfLocalDay(addLocalDays(start, 3)))
        #expect(times.map(dayOfMonth) == [1, 1, 3, 3])
    }

    @Test func weeklyOverAYear() {
        let times = doseTimesBetween(Schedule(kind: .intervalDays, intervalDays: 7), start, start, endOfLocalDay(addLocalDays(start, 364)))
        #expect(times.count == 53)
        for i in 1..<times.count { #expect(daysBetween(times[i - 1], times[i]) == 7) }
    }
}

@Suite struct NextAndPrevious {
    let start = local(2026, 6, 1)
    let schedule = Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "10:00")

    @Test func next() {
        #expect(nextDoseTime(schedule, start, local(2026, 6, 1, 12)) == local(2026, 6, 8, 10))
        let now = local(2026, 6, 8, 10)
        #expect(nextDoseTime(schedule, start, now) == now)
    }

    @Test func previous() {
        #expect(previousDoseTime(schedule, start, local(2026, 6, 10, 12)) == local(2026, 6, 8, 10))
        #expect(previousDoseTime(schedule, start, local(2026, 5, 20)) == nil)
    }

    @Test func noneAfterEndOrAsNeeded() {
        #expect(nextDoseTime(schedule, start, local(2026, 6, 10), local(2026, 6, 5)) == nil)
        #expect(nextDoseTime(Schedule(kind: .asNeeded), start, start) == nil)
        #expect(previousDoseTime(Schedule(kind: .asNeeded), start, start) == nil)
    }

    @Test func walksTimesWithinADay() {
        let twice = Schedule(kind: .daily, timesOfDay: ["07:00", "22:00"])
        let midday = local(2026, 6, 8, 12)
        #expect(nextDoseTime(twice, start, midday) == local(2026, 6, 8, 22))
        #expect(previousDoseTime(twice, start, midday) == local(2026, 6, 8, 7))
    }

    @Test func crossesMidnight() {
        let twice = Schedule(kind: .daily, timesOfDay: ["07:00", "22:00"])
        #expect(nextDoseTime(twice, start, local(2026, 6, 8, 23, 30)) == local(2026, 6, 9, 7))
        #expect(previousDoseTime(twice, start, local(2026, 6, 9, 6)) == local(2026, 6, 8, 22))
    }

    @Test func skipsOffCycle() {
        let s = Schedule(kind: .daily, timeOfDay: "09:00", cycleWeeksOn: 1, cycleWeeksOff: 1)
        #expect(nextDoseTime(s, start, addLocalDays(start, 8)) == atTimeOfDay(addLocalDays(start, 14), "09:00"))
    }
}

@Suite struct DosesPerWeek {
    @Test func counts() {
        #expect(dosesPerWeek(Schedule(kind: .daily)) == 7)
        #expect(dosesPerWeek(Schedule(kind: .intervalDays, intervalDays: 7)) == 1)
        #expect(dosesPerWeek(Schedule(kind: .intervalDays, intervalDays: 2)) == 3.5)
        #expect(dosesPerWeek(Schedule(kind: .daysOfWeek, daysOfWeek: [1, 3, 5])) == 3)
        #expect(dosesPerWeek(Schedule(kind: .asNeeded)) == 0)
        #expect(isClose(dosesPerWeek(Schedule(kind: .daily, cycleWeeksOn: 5, cycleWeeksOff: 2)), 5, digits: 10))
    }

    @Test func injectionsNotDays() {
        #expect(dosesPerWeek(Schedule(kind: .daily, timesOfDay: ["07:00", "22:00"])) == 14)
        #expect(dosesPerWeek(Schedule(kind: .daysOfWeek, daysOfWeek: [1, 4], timesOfDay: ["08:00", "20:00"])) == 4)
    }
}

@Suite struct ScheduleTimes {
    @Test func fallbacks() {
        #expect(scheduleTimes(Schedule(kind: .daily, timeOfDay: "07:00")) == ["07:00"])
        #expect(scheduleTimes(Schedule(kind: .daily)) == ["09:00"])
    }

    @Test func prefersList() {
        #expect(scheduleTimes(Schedule(kind: .daily, timeOfDay: "07:00", timesOfDay: ["08:00", "20:00"])) == ["08:00", "20:00"])
        #expect(scheduleTimes(Schedule(kind: .daily, timeOfDay: "07:00", timesOfDay: [])) == ["07:00"])
    }

    @Test func sortsPadsDedupes() {
        #expect(scheduleTimes(Schedule(kind: .daily, timesOfDay: ["22:00", "7:5", "07:05"])) == ["07:05", "22:00"])
    }

    @Test func unreadable() {
        #expect(scheduleTimes(Schedule(kind: .daily, timesOfDay: ["nonsense"])) == ["09:00"])
    }
}

@Suite struct SplittingADay {
    let start = local(2026, 6, 1, 7)
    var base: DoseProtocol {
        makeProtocol(peptideId: "bpc-157", startedAt: start, doseMcg: 500, schedule: Schedule(kind: .daily, timesOfDay: ["07:00", "22:00"]))
    }

    @Test func halves() {
        #expect(scheduledDailyMcg(base, start) == 500)
        #expect(scheduledDoseMcg(base, start) == 250)
    }

    @Test func singleTime() {
        var once = base
        once.schedule = Schedule(kind: .daily, timeOfDay: "07:00")
        #expect(scheduledDoseMcg(once, start) == 500)
    }

    @Test func bandInForce() {
        var banded = base
        banded.phases = [ProtocolPhase(step: 1, doseMcg: 250, weeks: 4), ProtocolPhase(step: 2, doseMcg: 500, weeks: 4)]
        #expect(scheduledDoseMcg(banded, addLocalDays(start, 7)) == 125)
        #expect(scheduledDoseMcg(banded, addLocalDays(start, 28)) == 250)
    }

    @Test func bandsOwnTimes() {
        var banded = base
        banded.schedule = Schedule(kind: .daily, timeOfDay: "07:00")
        banded.phases = [
            ProtocolPhase(step: 1, doseMcg: 500, weeks: 4, schedule: Schedule(kind: .daily, timesOfDay: ["07:00", "22:00"])),
            ProtocolPhase(step: 2, doseMcg: 500, weeks: 4),
        ]
        #expect(scheduledDoseMcg(banded, addLocalDays(start, 7)) == 250)
        #expect(scheduledDoseMcg(banded, addLocalDays(start, 28)) == 500)
    }

    @Test func asNeededNotDivided() {
        var p = base
        p.schedule = Schedule(kind: .asNeeded, timesOfDay: ["07:00", "22:00"])
        #expect(scheduledDoseMcg(p, start) == 500)
    }
}

@Suite struct Titration {
    let steps = [
        TitrationStep(step: 1, doseMcg: 2000, weeks: 4), TitrationStep(step: 2, doseMcg: 4000, weeks: 4),
        TitrationStep(step: 3, doseMcg: 8000, weeks: 4), TitrationStep(step: 4, doseMcg: 12000, weeks: 12),
    ]
    let start = local(2026, 1, 5)

    @Test func stepStarts() {
        #expect(titrationStepStartWeeks(steps) == [0, 4, 8, 12])
        #expect(titrationTotalWeeks(steps) == 24)
    }

    @Test func stepForDate() {
        #expect(titrationStepAt(steps, start, start)?.index == 0)
        #expect(titrationStepAt(steps, start, addLocalDays(start, 27))?.index == 0)
        #expect(titrationStepAt(steps, start, addLocalDays(start, 28))?.index == 1)
        #expect(titrationStepAt(steps, start, addLocalDays(start, 56))?.index == 2)
        #expect(titrationStepAt(steps, start, addLocalDays(start, 84))?.index == 3)
        let late = titrationStepAt(steps, start, addLocalDays(start, 400))
        #expect(late?.index == 3 && late?.step.doseMcg == 12000)
        #expect(titrationStepAt(steps, start, addLocalDays(start, -1)) == nil)
        #expect(titrationStepAt([], start, start) == nil)
    }

    func protocolWith(titration: [TitrationStep]?, auto: Bool) -> DoseProtocol {
        makeProtocol(peptideId: "retatrutide", startedAt: start, schedule: Schedule(kind: .intervalDays, intervalDays: 7),
                     titration: titration, titrationAutoAdvance: auto)
    }

    @Test func autoAdvance() {
        #expect(scheduledDoseMcg(protocolWith(titration: steps, auto: true), addLocalDays(start, 30)) == 4000)
        #expect(scheduledDoseMcg(protocolWith(titration: steps, auto: false), addLocalDays(start, 30)) == 1000)
        #expect(scheduledDoseMcg(protocolWith(titration: nil, auto: true), start) == 1000)
    }
}

@Suite struct Adherence {
    let start = local(2026, 2, 2, 9)
    var p: DoseProtocol { makeProtocol(startedAt: start, schedule: Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "09:00")) }
    var windowEnd: Millis { addLocalDays(start, 27) }

    @Test func perfect() {
        let logs = [0, 7, 14, 21].map { LogStamp(at: atTimeOfDay(addLocalDays(start, Double($0)), "09:00")) }
        let a = adherence(p, logs, start, windowEnd)
        #expect(a.expected == 4 && a.taken == 4 && a.rate == 1)
    }

    @Test func laterSameDay() {
        let a = adherence(p, [LogStamp(at: atTimeOfDay(start, "09:00") + 9 * HOUR)], start, addLocalDays(start, 6))
        #expect(a.taken == 1 && a.missed == 0)
    }

    @Test func missed() {
        let logs = [0, 14, 21].map { LogStamp(at: atTimeOfDay(addLocalDays(start, Double($0)), "09:00")) }
        let a = adherence(p, logs, start, windowEnd)
        #expect(a.taken == 3 && a.missed == 1 && isClose(a.rate, 0.75, digits: 10))
    }

    @Test func skipVersusMiss() {
        let logs = [LogStamp(at: atTimeOfDay(start, "09:00")), LogStamp(at: atTimeOfDay(addLocalDays(start, 7), "09:00"), skipped: true)]
        let a = adherence(p, logs, start, addLocalDays(start, 13))
        #expect(a.taken == 1 && a.skipped == 1 && a.missed == 0)
    }

    @Test func oneLogOneDose() {
        var daily = p
        daily.schedule = Schedule(kind: .daily, timeOfDay: "09:00")
        let a = adherence(daily, [LogStamp(at: atTimeOfDay(start, "09:00"))], start, addLocalDays(start, 2))
        #expect(a.expected == 3 && a.taken == 1 && a.missed == 2)
    }

    @Test func nothingScheduled() {
        var asNeeded = p
        asNeeded.schedule = Schedule(kind: .asNeeded)
        let a = adherence(asNeeded, [LogStamp](), start, windowEnd)
        #expect(a.expected == 0 && a.rate == 1)
    }
}

@Suite struct DueStatusTests {
    let start = local(2026, 9, 7, 9)
    var p: DoseProtocol { makeProtocol(startedAt: start, schedule: Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "09:00")) }
    func loggedOn(_ day: Double) -> Millis { atTimeOfDay(addLocalDays(start, day), "09:00") }
    var morning: DoseProtocol { var m = p; m.schedule = Schedule(kind: .daily, timeOfDay: "07:00"); return m }
    var twice: DoseProtocol { var m = p; m.schedule = Schedule(kind: .daily, timesOfDay: ["07:00", "22:00"]); return m }

    @Test func basics() {
        var paused = p; paused.active = false
        #expect(dueStatus(paused, start).state == .none)
        #expect(dueStatus(p, local(2026, 9, 7, 9)).state == .dueNow)
        #expect(dueStatus(p, local(2026, 9, 7, 12)).state == .dueNow)
        #expect(dueStatus(p, local(2026, 9, 7, 20)).state == .overdue)
    }

    @Test func coveredThenScheduled() {
        let s = dueStatus(p, local(2026, 9, 7, 20), DueOptions(lastLoggedAt: loggedOn(0)))
        #expect(s.state == .scheduled && s.at == loggedOn(7))
    }

    @Test func dueToday() {
        let s = dueStatus(p, local(2026, 9, 14, 2), DueOptions(lastLoggedAt: loggedOn(0)))
        #expect(s.state == .upcoming && isClose(s.hoursAway, 7, digits: 6))
    }

    @Test func daysAway() {
        let s = dueStatus(p, local(2026, 9, 10, 9), DueOptions(lastLoggedAt: loggedOn(0)))
        #expect(s.state == .scheduled && isClose(s.hoursAway, 96, digits: 6))
    }

    @Test func oldLogDoesNotCover() {
        let s = dueStatus(p, local(2026, 9, 21, 20), DueOptions(lastLoggedAt: loggedOn(0)))
        #expect(s.state == .overdue && s.at == loggedOn(14))
    }

    @Test func quietBetweenDailyDoses() {
        var daily = p; daily.schedule = Schedule(kind: .daily, timeOfDay: "09:00")
        #expect(dueStatus(daily, local(2026, 9, 7, 18), DueOptions(lastLoggedAt: loggedOn(0))).state == .scheduled)
    }

    @Test func earlyLogClears() {
        let at = local(2026, 9, 8, 6, 30)
        let s = dueStatus(morning, at, DueOptions(lastLoggedAt: at))
        #expect(s.state == .scheduled && s.at == local(2026, 9, 9, 7))
    }

    @Test func stillAsksWhenNothingThisMorning() {
        let s = dueStatus(morning, local(2026, 9, 8, 6, 30), DueOptions(lastLoggedAt: local(2026, 9, 7, 7)))
        #expect(s.state == .dueNow && s.at == local(2026, 9, 8, 7))
    }

    @Test func lateEveningDoesNotCancelTomorrow() {
        let at = local(2026, 9, 8, 20)
        let s = dueStatus(morning, at, DueOptions(lastLoggedAt: at))
        #expect(s.state == .scheduled && s.at == local(2026, 9, 9, 7))
    }

    @Test func lastNightDoesNotCoverThisMorning() {
        let s = dueStatus(morning, local(2026, 9, 9, 8), DueOptions(lastLoggedAt: local(2026, 9, 8, 23, 32)))
        #expect(s.state == .dueNow && s.at == local(2026, 9, 9, 7))
    }

    @Test func couplHoursEarly() {
        #expect(dueStatus(morning, local(2026, 9, 9, 8), DueOptions(lastLoggedAt: local(2026, 9, 9, 2))).state == .scheduled)
    }

    @Test func weeklyFullTolerance() {
        let s = dueStatus(p, local(2026, 9, 14, 10), DueOptions(lastLoggedAt: local(2026, 9, 13, 22)))
        #expect(s.state == .scheduled && s.at == loggedOn(14))
    }

    @Test func bothHalves() {
        let evening = local(2026, 9, 8, 22, 30)
        let s = dueStatus(twice, evening, DueOptions(lastLoggedAt: local(2026, 9, 8, 7, 5)))
        #expect(s.state == .dueNow && s.at == local(2026, 9, 8, 22))
        #expect(dueStatus(twice, evening, DueOptions(lastLoggedAt: evening)).at == local(2026, 9, 9, 7))
    }

    @Test func morningIsNotEveningEarly() {
        let s = dueStatus(twice, local(2026, 9, 8, 23), DueOptions(lastLoggedAt: local(2026, 9, 8, 7)))
        #expect(s.state == .dueNow && s.at == local(2026, 9, 8, 22))
    }

    @Test func justAfterIsNotNext() {
        let s = dueStatus(morning, local(2026, 9, 8, 7, 20), DueOptions(lastLoggedAt: local(2026, 9, 8, 7, 5)))
        #expect(s.state == .scheduled && s.at == local(2026, 9, 9, 7))
    }

    @Test func earlyWeekly() {
        let at = local(2026, 9, 14, 7, 30)
        let s = dueStatus(p, at, DueOptions(lastLoggedAt: at))
        #expect(s.state == .scheduled && s.at == loggedOn(14))
    }

    @Test func asNeededNone() {
        var a = p; a.schedule = Schedule(kind: .asNeeded)
        let s = dueStatus(a, start)
        #expect(s.state == .none && s.at == nil)
    }
}

@Suite struct UnloggedDoseTimes {
    let start = local(2026, 9, 7, 7)
    var twice: DoseProtocol {
        makeProtocol(peptideId: "bpc-157", startedAt: start, doseMcg: 500, schedule: Schedule(kind: .daily, timesOfDay: ["07:00", "19:00"]))
    }
    func day(_ h: Int, _ m: Int = 0) -> Millis { local(2026, 9, 8, h, m) }
    func rest(_ from: Millis, _ logs: [LogStamp]) -> [Millis] { unloggedDoseTimes(twice, logs, from, local(2026, 9, 8, 23, 59)) }

    @Test func cases() {
        #expect(rest(day(8), []) == [day(19)])
        #expect(rest(day(19, 30), [LogStamp(at: day(19, 4))]).isEmpty)
        #expect(rest(day(17, 45), [LogStamp(at: day(17, 30))]).isEmpty)
        #expect(rest(day(8), [LogStamp(at: day(7, 5))]) == [day(19)])
        #expect(rest(day(12), [LogStamp(at: day(19), skipped: true)]).isEmpty)
        #expect(rest(day(20), []).isEmpty)
    }

    @Test func weeklySkippedNotOverdue() {
        var weekly = twice
        weekly.schedule = Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "07:00")
        let skippedAt = local(2026, 9, 7, 10, 58)
        #expect(dueStatus(weekly, local(2026, 9, 8, 9), DueOptions(lastLoggedAt: skippedAt)).state == .scheduled)
        #expect(dueStatus(weekly, local(2026, 9, 8, 9), DueOptions(lastLoggedAt: nil)).state == .overdue)
    }

    @Test func notBeforeScheduleMoved() {
        var moved = twice
        moved.scheduleChangedAt = day(12)
        #expect(unloggedDoseTimes(moved, [LogStamp](), day(6), local(2026, 9, 8, 23, 59)) == [day(19)])
    }
}

@Suite struct MovingASchedule {
    var evening: DoseProtocol {
        makeProtocol(peptideId: "ghk-cu", startedAt: local(2026, 8, 27, 7), doseMcg: 2000, schedule: Schedule(kind: .daily, timeOfDay: "22:30"))
    }
    let yesterdayMorning = local(2026, 9, 6, 7, 5)
    let thisMorning = local(2026, 9, 7, 7, 43)
    var moved: DoseProtocol { var m = evening; m.scheduleChangedAt = local(2026, 9, 7, 7, 30); return m }

    @Test func reproducesWithoutFix() {
        let s = dueStatus(evening, thisMorning, DueOptions(lastLoggedAt: yesterdayMorning))
        #expect(s.state == .overdue && s.at == local(2026, 9, 6, 22, 30) && isClose(s.hoursAway, -9.2, digits: 1))
    }

    @Test func silentBeforeChange() {
        let s = dueStatus(moved, thisMorning, DueOptions(lastLoggedAt: yesterdayMorning))
        #expect(s.state == .upcoming && s.at == local(2026, 9, 7, 22, 30))
    }

    @Test func reportsAfterChange() {
        let s = dueStatus(moved, local(2026, 9, 9, 7), DueOptions(lastLoggedAt: yesterdayMorning))
        #expect(s.state == .overdue && s.at == local(2026, 9, 8, 22, 30))
    }

    @Test func clearsOnFirstLog() {
        #expect(dueStatus(evening, local(2026, 9, 7, 22, 40), DueOptions(lastLoggedAt: local(2026, 9, 7, 22, 35))).state == .scheduled)
    }

    @Test func unedited() {
        #expect(dueStatus(evening, local(2026, 9, 9, 7), DueOptions(lastLoggedAt: yesterdayMorning)).state == .overdue)
        #expect(slotIsKnowable(evening, 0))
    }
}

@Suite struct LogsForProtocol {
    @Test func filters() {
        let p = makeProtocol(peptideId: "semaglutide", startedAt: 0, schedule: Schedule(kind: .daily))
        let rows = [
            DoseLog(id: "a", profileId: "me", protocolId: "p1", peptideId: "semaglutide", at: 1, doseMcg: 1, route: .subcutaneous),
            DoseLog(id: "b", profileId: "me", peptideId: "semaglutide", at: 2, doseMcg: 1, route: .subcutaneous),
            DoseLog(id: "c", profileId: "me", protocolId: "p2", peptideId: "tirzepatide", at: 3, doseMcg: 1, route: .subcutaneous),
            DoseLog(id: "d", profileId: "me", protocolId: "p1", peptideId: "tirzepatide", at: 4, doseMcg: 1, route: .subcutaneous),
        ]
        #expect(logsForProtocol(p, rows).map(\.id) == ["a", "b", "d"])
    }

    @Test func zeroForOtherCompound() {
        let p = makeProtocol(id: "ai", peptideId: "anastrozole", startedAt: local(2026, 6, 1), doseMcg: 250, route: .oral,
                             schedule: Schedule(kind: .intervalDays, intervalDays: 3))
        let other = [local(2026, 6, 1), local(2026, 6, 8), local(2026, 6, 15)].map {
            DoseLog(id: "\($0)", profileId: "me", peptideId: "testosterone-enanthate", at: $0, doseMcg: 1, route: .intramuscular)
        }
        let a = adherence(p, logsForProtocol(p, other), local(2026, 6, 1), local(2026, 6, 20))
        #expect(a.expected > 0 && a.taken == 0)
    }
}

@Suite struct AdherenceNextMorning {
    let start = local(2026, 8, 27, 22, 30)
    var p: DoseProtocol { makeProtocol(peptideId: "ghk-cu", startedAt: start, doseMcg: 2000, schedule: Schedule(kind: .daily, timeOfDay: "22:30")) }
    var logs: [LogStamp] { (0..<11).map { LogStamp(at: atTimeOfDay(addLocalDays(local(2026, 8, 28), Double($0)), "07:05")) } }

    @Test func creditsEveryDose() {
        let a = adherence(p, logs, start, local(2026, 9, 7, 7, 43))
        #expect(a.expected == 11 && a.taken == 11 && a.missed == 0 && a.rate == 1)
    }

    @Test func realGap() {
        let gap = logs.enumerated().filter { $0.offset != 4 }.map(\.element)
        let a = adherence(p, gap, start, local(2026, 9, 7, 7, 43))
        #expect(a.expected == 11 && a.taken == 10 && a.missed == 1)
    }
}

@Suite struct AdherenceReference {
    func reference(_ p: DoseProtocol, _ logs: [LogStamp], _ from: Millis, _ to: Millis, _ toleranceHours: Double) -> (Int, Int, Int) {
        let scheduled = doseTimesBetween(p.schedule, p.startedAt, from, to, p.endedAt)
        let tol = toleranceHours * HOUR
        let byTime = logs.enumerated().filter { $0.element.at >= from - tol && $0.element.at <= to + tol }
            .map { (l: $0.element, i: $0.offset) }
            .sorted { $0.l.at != $1.l.at ? $0.l.at < $1.l.at : $0.i < $1.i }
        var used = Set<Int>()
        var taken = 0, skipped = 0
        for time in scheduled {
            for (i, entry) in byTime.enumerated() where !used.contains(i) && abs(entry.l.at - time) <= tol {
                used.insert(i)
                if entry.l.isSkipped { skipped += 1 } else { taken += 1 }
                break
            }
        }
        return (scheduled.count, taken, skipped)
    }

    @Test func randomisedHistories() {
        var rand = LCG(20260731)
        let schedules = [
            Schedule(kind: .daily), Schedule(kind: .intervalDays, intervalDays: 2), Schedule(kind: .intervalDays, intervalDays: 7),
            Schedule(kind: .daysOfWeek, daysOfWeek: [1, 4]),
            Schedule(kind: .intervalDays, intervalDays: 3, cycleWeeksOn: 4, cycleWeeksOff: 2),
        ]
        for n in 0..<300 {
            let start = local(2026, 1, 1)
            let days = 20 + Int(rand.next() * 120)
            let to = start + Double(days) * DAY_MS
            let p = makeProtocol(startedAt: start, doseMcg: 100, schedule: schedules[Int(rand.next() * Double(schedules.count))])
            var logs: [LogStamp] = []
            let count = Int(rand.next() * 60)
            for _ in 0..<count {
                let at = start + (rand.next() * Double(days)).rounded(.down) * DAY_MS + ((rand.next() - 0.5) * 90 * HOUR).rounded(.down)
                logs.append(LogStamp(at: at, skipped: rand.next() < 0.15))
                if rand.next() < 0.1 { logs.append(LogStamp(at: at, skipped: rand.next() < 0.5)) }
            }
            // Deterministic shuffle, standing in for the original's random comparator.
            for i in stride(from: logs.count - 1, to: 0, by: -1) { logs.swapAt(i, Int(rand.next() * Double(i + 1))) }
            let tolerance = [12.0, 36, 72][Int(rand.next() * 3)]
            let got = adherence(p, logs, start, to, toleranceHours: tolerance)
            let want = reference(p, logs, start, to, tolerance)
            #expect(got.expected == want.0 && got.taken == want.1 && got.skipped == want.2, "case \(n)")
        }
    }

    @Test func oneLogConsumedOnce() {
        let p = makeProtocol(startedAt: local(2026, 1, 1), doseMcg: 100, schedule: Schedule(kind: .daily))
        let a = adherence(p, [LogStamp(at: local(2026, 1, 3))], local(2026, 1, 1), local(2026, 1, 5), toleranceHours: 72)
        #expect(a.expected > 1 && a.taken == 1 && a.skipped == 0 && a.missed == a.expected - 1)
    }
}

@Suite struct EveryTimeFilledTests {
    @Test func cases() {
        #expect(everyTimeFilled(["06:30"]))
        #expect(everyTimeFilled(["06:30", "20:00"]))
        #expect(!everyTimeFilled(["06:30", ""]))
        #expect(!everyTimeFilled(["  "]))
        #expect(!everyTimeFilled([]))
    }
}

@Suite struct HasStartedTests {
    let p = makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 9, 14, 9), doseMcg: 250, schedule: Schedule(kind: .daily, timeOfDay: "06:30"))

    @Test func boundaries() {
        #expect(!hasStarted(p, local(2026, 9, 8, 12)))
        #expect(hasStarted(p, local(2026, 9, 14, 0)))
        #expect(hasStarted(p, local(2026, 9, 14, 8)))
        #expect(!hasStarted(p, local(2026, 9, 13, 23, 59, 59)))
    }
}
