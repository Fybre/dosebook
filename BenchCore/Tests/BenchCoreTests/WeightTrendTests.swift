import Foundation
import Testing
@testable import BenchCore

private func dose(_ at: Millis, _ mcg: Double, _ peptide: String = "retatrutide", skipped: Bool = false) -> DoseLog {
    DoseLog(id: UUID().uuidString, profileId: "me", peptideId: peptide, at: at, doseMcg: mcg, route: .subcutaneous, skipped: skipped ? true : nil)
}
private func weigh(_ at: Millis, _ kg: Double) -> BodyMeasurement { BodyMeasurement(id: UUID().uuidString, profileId: "me", at: at, weightKg: kg) }

@Suite struct WeightTrendTests {
    let w = 7 * DAY_MS
    let start = local(2026, 9, 2, 9)
    var logs: [DoseLog] {
        [dose(start, 1000), dose(start + w, 1000), dose(start + 2 * w, 2000), dose(start + 3 * w, 2000, skipped: true),
         dose(start + 3 * w + DAY_MS, 2000), dose(start + 4 * w, 4000), dose(start + 2 * w, 250, "bpc-157")]
    }

    @Test func groupsByDose() {
        let now = start + 5 * w
        let steps = doseSteps(logs, peptideId: "retatrutide", now: now)
        #expect(steps.map(\.doseMcg) == [1000, 2000, 4000])
        #expect(steps.map(\.doses) == [2, 2, 1])
        #expect(steps[0].from == start && steps[0].to == start + 2 * w)
        #expect(steps[2].to == now)
    }

    @Test func weightPerStep() {
        let now = start + 5 * w
        let weights = [weigh(start, 90), weigh(start + 7 * DAY_MS, 89), weigh(start + 13 * DAY_MS, 88.4),
                       weigh(start + 15 * DAY_MS, 88), weigh(start + 2 * w + 7 * DAY_MS, 87),
                       weigh(start + 4 * w + DAY_MS, 86)]
        let per = weightDuring(doseSteps(logs, peptideId: "retatrutide", now: now), weights)
        #expect(per[0].points == 3)
        #expect(isClose(per[0].changeKg!, -1.6))
        // A straight-line fit through 90, 89, 88.4 over 13 days.
        #expect(isClose(per[0].perWeekKg!, -0.865, digits: 2))
        #expect(per[1].points == 2 && isClose(per[1].changeKg!, -1))
        // One weigh-in is not a trend.
        #expect(per[2].points == 1 && per[2].changeKg == nil && per[2].perWeekKg == nil)
    }

    @Test func readingsTooCloseGiveNoRate() {
        let steps = [DoseStep(doseMcg: 1000, from: start, to: start + w, doses: 1)]
        let per = weightDuring(steps, [weigh(start, 90), weigh(start + DAY_MS, 89)])
        #expect(per[0].changeKg == -1 && per[0].perWeekKg == nil)
    }

    @Test func picksTheMostTitrated() {
        #expect(mostTitratedCompound(logs, now: start + 5 * w) == "retatrutide")
        #expect(mostTitratedCompound([], now: start) == nil)
    }
}

@Suite struct VitalDoseComparisonTests {
    @Test func usesCalendarDaysAndStopsAtTheNextLoggedChange() {
        let first = local(2026, 6, 15, 9)
        let next = local(2026, 6, 22, 9)
        let now = local(2026, 6, 30, 18)
        let steps = doseSteps([dose(first, 1000), dose(next, 2000)], peptideId: "retatrutide", now: now)
        func vital(_ day: Int, _ sleep: Double?, _ hr: Double? = nil) -> BodyMeasurement {
            BodyMeasurement(id: UUID().uuidString, profileId: "me", at: local(2026, 6, day, 12),
                            sleepHours: sleep, restingHrBpm: hr)
        }
        let readings = [vital(11, 6, 60), vital(12, 7, 61), vital(13, 8, 62), vital(14, 9),
                        vital(14, 11), vital(15, 20, 100),
                        vital(16, 7, 65), vital(17, 7, 66), vital(18, 7, 67), vital(19, 7, 68),
                        vital(22, 20, 100), vital(23, 8, 70)]
        let comparisons = vitalsAroundDoseSteps(steps, readings, now: now)
        #expect(comparisons.count == 2)
        #expect(comparisons[0].sleepBefore.days == 4 && comparisons[0].sleepBefore.value == 7.75)
        #expect(comparisons[0].sleepAfter.days == 4 && comparisons[0].sleepAfter.value == 7)
        #expect(comparisons[0].sleepBefore.hasEnoughDays && comparisons[0].sleepAfter.hasEnoughDays)
        #expect(comparisons[0].heartRateBefore.days == 3 && !comparisons[0].heartRateBefore.hasEnoughDays)
        #expect(comparisons[0].afterTo == startOfLocalDay(next))
        #expect(comparisons[1].afterFrom == local(2026, 6, 23))
        #expect(comparisons[1].sleepAfter.days == 1 && comparisons[1].sleepAfter.value == 8)
    }

    @Test func emptyOrInvalidWindowsYieldNoComparison() {
        let at = local(2026, 6, 15)
        let step = DoseStep(doseMcg: 1000, from: at, to: at, doses: 1)
        #expect(vitalsAroundDoseSteps([], [], now: at).isEmpty)
        #expect(vitalsAroundDoseSteps([step], [], now: at, windowDays: 0).isEmpty)
        let result = vitalsAroundDoseSteps([step], [], now: at)[0]
        #expect(result.sleepBefore.value == nil && result.sleepAfter.value == nil)
        #expect(result.sleepBefore.days == 0 && result.sleepAfter.days == 0)
    }
}
