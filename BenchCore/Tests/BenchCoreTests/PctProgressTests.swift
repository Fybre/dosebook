import Foundation
import Testing
@testable import BenchCore

// Ports of pct.test.ts and progress.test.ts.

private let NOW_PCT: Millis = 1_785_412_800_000 // Date.UTC(2026, 6, 30, 12)
private func resolve(_ id: String) -> Peptide? { Library.byId[id] }
private func plog(_ peptideId: String, _ daysAgo: Double, skipped: Bool = false) -> DoseLog {
    DoseLog(id: UUID().uuidString, profileId: "me", peptideId: peptideId, at: NOW_PCT - daysAgo * DAY_MS, doseMcg: 1,
            route: .intramuscular, skipped: skipped)
}
private func plan(_ logs: [DoseLog]) -> PctPlan { pctPlan(logs, resolve: resolve, nowMs: NOW_PCT) }

@Suite struct PctTests {
    @Test func clearing() {
        #expect(isClose(hoursToClear(24) / 24, log2(1 / CLEARED_FRACTION), digits: 10))
        #expect(isClose(fractionRemaining(hoursToClear(108), 108), CLEARED_FRACTION, digits: 10))
        #expect(hoursToClear(0) == 0 && hoursToClear(-5) == 0)
    }

    @Test func plans() {
        let none = plan([plog("bpc-157", 2), plog("semaglutide", 5)])
        #expect(none.compounds.isEmpty && none.earliestStart == nil && !none.clear)
        let te = plan([plog("testosterone-enanthate", 3), plog("testosterone-enanthate", 10)])
        #expect(te.compounds.count == 1 && te.compounds[0].lastDoseAt == NOW_PCT - 3 * DAY_MS)
        #expect(te.compounds[0].clearedAt == te.compounds[0].lastDoseAt + hoursToClear(108) * HOUR_MS)
        let two = plan([plog("testosterone-propionate", 1), plog("testosterone-enanthate", 1)])
        #expect(two.earliestStart == two.compounds.first { $0.peptideId == "testosterone-enanthate" }!.clearedAt)
        let tren = plan([plog("trenbolone-acetate", 2)])
        #expect(tren.earliestStart == nil && tren.blockedBy == ["Trenbolone acetate"] && tren.compounds[0].clearedAt == nil)
        #expect(!(tren.compounds[0].unknownReason ?? "").isEmpty)
        let mixed = plan([plog("testosterone-enanthate", 1), plog("trenbolone-enanthate", 1)])
        #expect(mixed.earliestStart == nil && mixed.blockedBy.contains("Trenbolone enanthate"))
        #expect(plan([plog("testosterone-enanthate", 1, skipped: true), plog("testosterone-enanthate", 20)]).compounds[0].lastDoseAt == NOW_PCT - 20 * DAY_MS)
        #expect(plan([plog("testosterone-enanthate", 1), plog("bpc-157", 0)]).compounds.map(\.peptideId) == ["testosterone-enanthate"])
        #expect(plan([plog("testosterone-propionate", 30)]).clear)
        #expect(!plan([plog("testosterone-enanthate", 1)]).clear)
        #expect(!plan([plog("trenbolone-acetate", 400)]).clear)
        #expect(plan([plog("testosterone-enanthate", 20), plog("oxandrolone", 1)]).compounds[0].peptideId == "oxandrolone")
        #expect(plan([plog("not-a-real-compound", 1)]).compounds.isEmpty)
    }

    @Test func remaining() {
        #expect(isClose(remainingFraction(plan([plog("testosterone-enanthate", 0)]).compounds[0], nowMs: NOW_PCT)!, 1, digits: 6))
        #expect(isClose(remainingFraction(plan([plog("testosterone-enanthate", 4.5)]).compounds[0], nowMs: NOW_PCT)!, 0.5, digits: 6))
        #expect(remainingFraction(plan([plog("testosterone-enanthate", -10)]).compounds[0], nowMs: NOW_PCT) == 1)
        #expect(remainingFraction(plan([plog("trenbolone-acetate", 2)]).compounds[0], nowMs: NOW_PCT) == nil)
    }

    @Test func templates() {
        for t in PCT_TEMPLATES {
            for id in t.compoundIds { #expect(Library.byId[id] != nil, "\(t.id) references \(id)") }
            #expect(t.source.count > 20 && t.citationUrl.hasPrefix("https://"))
            #expect(t.weeks.map(\.week) == Array(1...t.weeks.count))
        }
        #expect(retestAfter(NOW_PCT) == NOW_PCT + 28 * DAY_MS)
    }
}

@Suite struct ProgressTests {
    let NOW = local(2026, 7, 29, 18)
    let START = local(2026, 7, 1, 0)
    func proto(id: String = "p1", peptideId: String = "klow", active: Bool = true,
               schedule: Schedule = Schedule(kind: .daily, timeOfDay: "09:00")) -> DoseProtocol {
        makeProtocol(id: id, peptideId: peptideId, name: "Daily", active: active, startedAt: START, schedule: schedule)
    }
    func dose(_ daysAgo: Double, peptideId: String = "klow", protocolId: String? = "p1", skipped: Bool? = nil, at: Millis? = nil) -> DoseLog {
        DoseLog(id: UUID().uuidString, profileId: "me", protocolId: protocolId, peptideId: peptideId,
                at: at ?? atTimeOfDay(addLocalDays(NOW, -daysAgo), "09:00"), doseMcg: 1000, route: .subcutaneous, skipped: skipped)
    }

    @Test func day() {
        let d = dayProgress([proto()], [], NOW)
        #expect(d.expected == 1 && d.taken == 0 && !d.complete && d.fraction == 0)
        let done = dayProgress([proto()], [dose(0)], NOW)
        #expect(done.taken == 1 && done.fraction == 1 && done.complete)
        let two = dayProgress([proto(), proto(id: "p2", peptideId: "bpc-157")], [dose(0)], NOW)
        #expect(two.expected == 2 && two.taken == 1 && isClose(two.fraction, 0.5, digits: 10) && !two.complete)
        let paused = dayProgress([proto(active: false)], [], NOW)
        #expect(paused.expected == 0 && paused.restDay)
        let rest = dayProgress([proto(schedule: Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "09:00"))], [], addLocalDays(NOW, -1))
        #expect(rest.expected == 0 && rest.restDay && rest.complete && rest.fraction == 1)
        let skip = dayProgress([proto()], [dose(0, skipped: true)], NOW)
        #expect(skip.taken == 0 && skip.skipped == 1 && skip.expected == 1 && skip.owed == 0 && skip.fraction == 1 && skip.complete && !skip.restDay)
    }

    @Test func skipsAndAttribution() {
        let pair = [proto(id: "bpc", peptideId: "bpc-157"), proto(id: "mounjaro", peptideId: "tirzepatide")]
        let a = dayProgress(pair, [dose(0, peptideId: "bpc-157", protocolId: "bpc"), dose(0, peptideId: "tirzepatide", protocolId: "mounjaro", skipped: true)], NOW)
        #expect(a.owed == 1 && a.taken == 1 && a.complete)
        let b = dayProgress(pair, [dose(0, peptideId: "tirzepatide", protocolId: "mounjaro", skipped: true)], NOW)
        #expect(b.owed == 1 && b.taken == 0 && !b.complete)
        #expect(dayProgress([proto()], [dose(1)], NOW).taken == 0)
        let extra = dayProgress([proto()], [dose(0), dose(0, at: dose(0).at + HOUR)], NOW)
        #expect(extra.taken == 1 && extra.fraction == 1 && extra.complete)
        let bk = [proto(id: "bpc", peptideId: "bpc-157"), proto(id: "kpv", peptideId: "kpv")]
        let twice = dayProgress(bk, [dose(0, peptideId: "kpv", protocolId: "kpv"), dose(0, peptideId: "kpv", protocolId: "kpv", at: dose(0).at + HOUR)], NOW)
        #expect(twice.expected == 2 && twice.taken == 1 && !twice.complete)
        #expect(dayProgress(bk, [dose(0, peptideId: "bpc-157", protocolId: nil)], NOW).taken == 1)
        let stray = dayProgress([proto()], [dose(0, peptideId: "tb-500", protocolId: nil)], NOW)
        #expect(stray.taken == 0 && !stray.complete)
        #expect(dayProgress([proto()], [], NOW).day == startOfLocalDay(NOW))
        #expect(todayProgress([proto()], [dose(0)], NOW) == dayProgress([proto()], [dose(0)], NOW))
    }

    @Test func streaks() {
        #expect(currentStreak([proto()], [], NOW) == 0)
        #expect(currentStreak([proto()], [0, 1, 2, 3].map { dose($0) }, NOW) == 4)
        #expect(currentStreak([proto()], [1, 2, 3].map { dose($0) }, NOW) == 3)
        #expect(currentStreak([proto()], [0, 1, 3, 4].map { dose($0) }, NOW) == 2)
        #expect(currentStreak([proto()], [dose(0), dose(1, skipped: true), dose(2)], NOW) == 2)
        let weekly = proto(schedule: Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "09:00"))
        #expect(currentStreak([weekly], [0, 7, 14, 21].map { dose(0, at: atTimeOfDay(addLocalDays(START, Double($0)), "09:00")) }, NOW) == 4)
        let cycled = proto(schedule: Schedule(kind: .daily, timeOfDay: "09:00", cycleWeeksOn: 1, cycleWeeksOff: 1))
        var logs: [DoseLog] = []
        for d in 0...28 {
            let day = addLocalDays(START, Double(d))
            if dayProgress([cycled], [], day).expected > 0 { logs.append(dose(0, at: atTimeOfDay(day, "09:00"))) }
        }
        #expect(currentStreak([cycled], logs, NOW) >= 14)
        #expect(currentStreak([proto()], (0..<30).map { dose(Double($0)) }, NOW, maxLookbackDays: 10) <= 10)
        #expect(currentStreak([], [], NOW) == 0)
    }

    @Test func recent() {
        let days = recentDays([proto()], [], NOW, days: 7)
        #expect(days.count == 7 && days[6].day == startOfLocalDay(NOW))
        for i in 1..<days.count { #expect(days[i].day > days[i - 1].day) }
        #expect(recentDays([proto()], [0, 1, 4].map { dose($0) }, NOW, days: 7).map(\.complete) == [false, false, true, false, false, true, true])
    }

    @Test func exposure() {
        func l(_ at: Millis, _ mcg: Double, _ pid: String, _ skipped: Bool = false) -> DoseLog {
            DoseLog(id: UUID().uuidString, profileId: "me", peptideId: pid, at: at, doseMcg: mcg, route: .subcutaneous, skipped: skipped)
        }
        let logs = [l(addLocalDays(NOW, -1), 1000, "klow"), l(addLocalDays(NOW, -2), 1000, "klow"), l(addLocalDays(NOW, -9), 500, "klow"),
                    l(addLocalDays(NOW, -3), 4000, "reta"), l(addLocalDays(NOW, -4), 9999, "klow", true)]
        let w = weeklyExposure(logs, NOW, weeks: 4)
        #expect(w.count == 4)
        for i in 1..<w.count { #expect(w[i].weekStart > w[i - 1].weekStart) }
        #expect(w[3].totalMcg == 6000 && w[3].doses == 3 && w[2].totalMcg == 500)
        #expect(weeklyExposure([l(NOW, 1000, "klow", true)], NOW, weeks: 1)[0].totalMcg == 0)
        let reta = weeklyExposure(logs, NOW, weeks: 4, peptideId: "reta")
        #expect(reta[3].totalMcg == 4000 && reta[3].doses == 1)
        #expect(weeklyExposure([], NOW, weeks: 3).allSatisfy { $0.totalMcg == 0 && $0.doses == 0 })
    }

    @Test func steady() {
        #expect(steadyStateProgress(nil, NOW, NOW) == nil && steadyStateProgress(144, nil, NOW) == nil && steadyStateProgress(0, NOW, NOW) == nil)
        #expect(steadyStateProgress(144, NOW, NOW)!.fraction == 0)
        #expect(isClose(steadyStateProgress(144, NOW - 144 * 5 * HOUR, NOW)!.fraction, 1, digits: 10))
        #expect(isClose(steadyStateProgress(144, NOW - 144 * 2.5 * HOUR, NOW)!.fraction, 0.5, digits: 10))
        #expect(steadyStateProgress(144, NOW - 144 * 50 * HOUR, NOW)!.fraction == 1)
        let s = steadyStateProgress(24, NOW - 48 * HOUR, NOW)!
        #expect(isClose(s.hoursElapsed, 48, digits: 6) && s.hoursNeeded == 120)
    }
}
