import Foundation
import Testing
@testable import BenchCore

// Ports of project.test.ts and stack.test.ts.

@Suite struct ProjectTests {
    let START = local(2026, 1, 5, 9)
    func proto(schedule: Schedule = Schedule(kind: .intervalDays, intervalDays: 7), doseMcg: Double = 250_000,
               endedAt: Millis? = nil, titration: [TitrationStep]? = nil, auto: Bool = false) -> DoseProtocol {
        makeProtocol(id: "p", peptideId: "testosterone-enanthate", name: "test", startedAt: START, endedAt: endedAt,
                     doseMcg: doseMcg, route: .intramuscular, schedule: schedule, titration: titration, titrationAutoAdvance: auto)
    }

    @Test func curve() {
        let p = project(proto(), halfLifeHours: 108, days: 60, steps: 100)
        #expect(p.series.count == 100 && p.series[0].t == START && p.series[99].t == START + 60 * DAY_MS)
        #expect(project(proto(), halfLifeHours: 108, days: 28).doseTimes.count == 5)
        let climb = project(proto(), halfLifeHours: 108, days: 60, steps: 400)
        let firstWeekPeak = climb.series.filter { $0.t < START + 7 * DAY_MS }.map(\.level).max()!
        #expect(climb.steadyPeak! > firstWeekPeak)
        #expect(isClose(project(proto(), halfLifeHours: 108, days: 60).accumulation!, accumulationRatio(168, 108), digits: 10))
        let weekly = project(proto(), halfLifeHours: 108, days: 60, steps: 600)
        #expect(weekly.swing! > 1)
        let twice = project(proto(schedule: Schedule(kind: .intervalDays, intervalDays: 3)), halfLifeHours: 108, days: 60, steps: 600)
        #expect(twice.swing! < weekly.swing!)
        #expect(isClose(project(proto(), halfLifeHours: 4, days: 60).accumulation!, 1, digits: 5))
        let asNeeded = project(proto(schedule: Schedule(kind: .asNeeded)), halfLifeHours: 108, days: 30)
        #expect(asNeeded.accumulation == nil && asNeeded.swing == nil && asNeeded.doseTimes.isEmpty)
        #expect(project(proto(endedAt: START + 14 * DAY_MS), halfLifeHours: 108, days: 60).doseTimes.max()! <= START + 14 * DAY_MS)
        let ladder = project(proto(doseMcg: 1000, titration: [TitrationStep(step: 1, doseMcg: 1000, weeks: 4), TitrationStep(step: 2, doseMcg: 4000, weeks: 4)], auto: true),
                             halfLifeHours: 108, days: 56, steps: 400)
        let early = ladder.series.filter { $0.t < START + 21 * DAY_MS }.map(\.level).max()!
        let late = ladder.series.filter { $0.t > START + 42 * DAY_MS }.map(\.level).max()!
        #expect(late > early * 2)
        #expect(project(proto(), halfLifeHours: 108, days: 0).series.isEmpty)
    }

    @Test func window() {
        #expect(defaultWindowDays(108, proto()) == 37)
        #expect(defaultWindowDays(2, proto()) >= 14)
        #expect(defaultWindowDays(2, proto(schedule: Schedule(kind: .daily))) == 14)
        #expect(defaultWindowDays(30 * 24, proto()) <= 180)
    }

    @Test func describe() {
        #expect(describeAccumulation(nil) == nil)
        #expect(describeAccumulation(1.02)!.contains("do not build"))
        #expect(describeAccumulation(2.4)!.contains("not representative"))
        #expect(describeAccumulation(5)!.contains("several times higher"))
    }
}

private let NOW: Millis = 1_785_398_400_000 // Date.UTC(2026, 6, 30, 8)
private func sp(_ id: String, _ peptideId: String, name: String? = nil, active: Bool = true, doseMcg: Double = 1000,
                schedule: Schedule = Schedule(kind: .daysOfWeek, daysOfWeek: [1])) -> DoseProtocol {
    makeProtocol(id: id, peptideId: peptideId, name: name ?? peptideId, active: active, startedAt: NOW - 30 * DAY_MS,
                 doseMcg: doseMcg, schedule: schedule)
}
private func run(_ ps: [DoseProtocol]) -> [StackIssue] { stackIssues(ps, resolve: { Library.byId[$0] }, nowMs: NOW) }

@Suite struct StackTests {
    @Test func silence() {
        #expect(run([sp("a", "semaglutide")]).isEmpty && run([]).isEmpty)
        #expect(run([sp("a", "semaglutide"), sp("b", "bpc-157")]).isEmpty)
        #expect(run([sp("a", "semaglutide"), sp("b", "tirzepatide", active: false)]).isEmpty)
        #expect(run([sp("a", "cjc-1295-no-dac"), sp("b", "ipamorelin")]).isEmpty)
    }

    @Test func shared() {
        let glp = run([sp("a", "semaglutide", name: "Sema"), sp("b", "tirzepatide", name: "Tirz")])
            .first { $0.kind == .sharedMechanism && $0.title.contains("GLP-1") }
        #expect(glp?.severity == .high && glp?.protocolIds.sorted() == ["a", "b"] && glp?.compounds.contains("Semaglutide") == true)
        let ghrelin = run([sp("a", "ghrp-6"), sp("b", "ipamorelin")])
        #expect(ghrelin.count == 1 && ghrelin[0].kind == .sharedMechanism && ghrelin[0].severity == .medium)
        let two = run([sp("a", "retatrutide"), sp("b", "tirzepatide")]).filter { $0.kind == .sharedMechanism }
        #expect(two.count == 2 && two.contains { $0.title.contains("GLP-1") } && two.contains { $0.title.contains("GIP") })
        #expect(run([sp("a", "cagrisema"), sp("b", "semaglutide")]).contains { $0.kind == .sharedMechanism && $0.title.contains("GLP-1") })
        #expect(run([sp("a", "cagrisema"), sp("b", "cagrilintide")]).contains { $0.title.contains("amylin") })
    }

    @Test func duplicate() {
        let issues = run([sp("a", "semaglutide", name: "Morning"), sp("b", "semaglutide", name: "Evening")])
        let dup = issues.first { $0.kind == .duplicateCompound }
        #expect(dup?.severity == .high && dup?.detail.contains("Morning") == true && dup?.detail.contains("Evening") == true)
        #expect(run([sp("a", "semaglutide"), sp("b", "semaglutide")]).filter { $0.kind == .sharedMechanism }.isEmpty)
    }

    @Test func overlap() {
        let o = run([sp("a", "klow", name: "KLOW", doseMcg: 2000), sp("b", "bpc-157", name: "BPC solo", doseMcg: 500)])
            .first { $0.kind == .componentOverlap }
        #expect(o?.compounds == ["BPC-157"] && o?.protocolIds.sorted() == ["a", "b"])
        #expect(run([sp("a", "klow", doseMcg: 2000)]).filter { $0.kind == .componentOverlap }.isEmpty)
        let over = run([sp("a", "bpc-157", name: "Daily", doseMcg: 500, schedule: Schedule(kind: .daily)),
                        sp("b", "klow", name: "KLOW daily", doseMcg: 8000, schedule: Schedule(kind: .daily))])
            .first { $0.kind == .componentOverlap }
        #expect(over?.severity == .high && over?.title.contains("above its usual range") == true)
    }

    @Test func orals() {
        let daily = Schedule(kind: .daily)
        let liver = run([sp("a", "oxandrolone", doseMcg: 20_000, schedule: daily), sp("b", "stanozolol", doseMcg: 30_000, schedule: daily)])
            .first { $0.title.contains("17-alpha-alkylated") }
        #expect(liver?.severity == .high && liver?.protocolIds.sorted() == ["a", "b"])
        #expect(run([sp("a", "oxandrolone", doseMcg: 20_000, schedule: daily), sp("b", "testosterone-enanthate", doseMcg: 100_000)])
            .filter { $0.title.contains("17-alpha-alkylated") }.isEmpty)
        #expect(run([sp("a", "testosterone-enanthate", doseMcg: 200_000), sp("b", "nandrolone-decanoate", doseMcg: 200_000)]).isEmpty)
    }

    @Test func ordering() {
        let issues = run([sp("a", "ghrp-6"), sp("b", "ipamorelin"), sp("c", "semaglutide"), sp("d", "tirzepatide")])
        #expect(issues.count > 1 && issues[0].severity == .high)
        let sev = issues.map(\.severity)
        #expect(sev.firstIndex(of: .medium)! > sev.lastIndex(of: .high)!)
    }

    @Test func ancillaries() {
        #expect(run([sp("a", "anastrozole"), sp("b", "exemestane")]).contains { $0.title.lowercased().contains("aromatase inhibitor") })
        #expect(run([sp("a", "tamoxifen"), sp("b", "clomiphene")]).contains { $0.title.lowercased().contains("modulator") })
        let tren = run([sp("a", "anastrozole"), sp("b", "trenbolone-acetate")]).first { $0.title.contains("nothing that aromatises") }
        #expect(tren?.severity == .high && tren?.detail.lowercased().contains("trenbolone") == true)
        #expect(!run([sp("a", "anastrozole"), sp("b", "testosterone-enanthate")]).contains { $0.title.contains("nothing that aromatises") })
        #expect(!run([sp("a", "anastrozole"), sp("b", "trenbolone-acetate"), sp("c", "testosterone-propionate")]).contains { $0.title.contains("nothing that aromatises") })
        #expect(!run([sp("a", "anastrozole"), sp("b", "bpc-157")]).contains { $0.title.contains("nothing that aromatises") })
        #expect(run([sp("a", "hcg"), sp("b", "testosterone-cypionate")]).isEmpty)
    }
}
