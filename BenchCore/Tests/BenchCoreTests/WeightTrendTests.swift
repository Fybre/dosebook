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
