import Foundation
import Testing
@testable import BenchCore

@Suite struct WeightGoalTests {
    /// Weigh-ins every few days along a line, plus a little scatter.
    func series(start: Double, perWeek: Double, days: Int, now: Millis, scatter: [Double] = []) -> [BodyMeasurement] {
        stride(from: days, through: 0, by: -3).enumerated().map { i, ago in
            let kg = start + perWeek * Double(days - ago) / 7 + (i < scatter.count ? scatter[i] : 0)
            return BodyMeasurement(id: "m\(i)", profileId: "", at: now - Double(ago) * DAY_MS, weightKg: kg)
        }
    }

    @Test func projectsAStraightLoss() throws {
        let now = local(2026, 10, 25, 9)
        let m = series(start: 90, perWeek: -0.5, days: 30, now: now)   // latest 87.857
        let p = weightGoalProgress(m, goal: WeightGoal(kg: 85, startKg: 90), now: now)
        guard case .onTrack(let rate, let at) = p else { Issue.record("\(p)"); return }
        #expect(abs(rate - -0.5) < 0.01)
        // 2.857 kg at 0.5 a week is about 40 days.
        #expect(abs((at - now) / DAY_MS - 40) < 2)
    }

    @Test func projectsAGainToo() {
        let now = local(2026, 10, 25, 9)
        let m = series(start: 70, perWeek: 0.4, days: 28, now: now)
        guard case .onTrack(let rate, _) = weightGoalProgress(m, goal: WeightGoal(kg: 75, startKg: 70), now: now) else { Issue.record("not on track"); return }
        #expect(rate > 0)
    }

    @Test func oneOddReadingDoesNotMoveItFar() {
        let now = local(2026, 10, 25, 9)
        let m = series(start: 90, perWeek: -0.5, days: 30, now: now, scatter: [0, 0.3, -0.3, 0.8, 0, 0, -0.4, 0, 0.3, 0, 0])
        guard case .onTrack(let rate, _) = weightGoalProgress(m, goal: WeightGoal(kg: 85, startKg: 90), now: now) else { Issue.record("not on track"); return }
        #expect(abs(rate - -0.5) < 0.2)
    }

    @Test func theOtherWayAndFlatAndSlowAndReached() {
        let now = local(2026, 10, 25, 9)
        let up = series(start: 88, perWeek: 0.3, days: 28, now: now)
        #expect({ if case .notHeadingThere(let r) = weightGoalProgress(up, goal: WeightGoal(kg: 80, startKg: 90), now: now) { r > 0 } else { false } }())
        let flat = series(start: 88, perWeek: 0, days: 28, now: now)
        #expect({ if case .notHeadingThere = weightGoalProgress(flat, goal: WeightGoal(kg: 80, startKg: 90), now: now) { true } else { false } }())
        let crawl = series(start: 88, perWeek: -0.02, days: 28, now: now)
        #expect({ if case .slow = weightGoalProgress(crawl, goal: WeightGoal(kg: 60, startKg: 88), now: now) { true } else { false } }())
        let done = series(start: 90, perWeek: -1, days: 28, now: now)   // ends at 86
        #expect(weightGoalProgress(done, goal: WeightGoal(kg: 87, startKg: 90), now: now) == .reached)
    }

    @Test func needsThreeWeighInsOverAWeek() {
        let now = local(2026, 10, 25, 9)
        let two = [BodyMeasurement(id: "a", profileId: "", at: now - 20 * DAY_MS, weightKg: 90), BodyMeasurement(id: "b", profileId: "", at: now, weightKg: 89)]
        #expect(weightGoalProgress(two, goal: WeightGoal(kg: 85, startKg: 90), now: now) == .needsData)
        let crowded = (0..<4).map { BodyMeasurement(id: "c\($0)", profileId: "", at: now - Double($0) * DAY_MS, weightKg: 90 - Double($0)) }
        #expect(weightGoalProgress(crowded, goal: WeightGoal(kg: 85, startKg: 91), now: now) == .needsData)
        #expect(weightGoalProgress([], goal: WeightGoal(kg: 85, startKg: 90), now: now) == .needsData)
    }

    @Test func goalIsKeptInExtraAndSurvivesABackup() throws {
        var d = AppData()
        d.settings.weightGoal = WeightGoal(kg: 82.5, startKg: 90)
        let back = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(d))
        #expect(back.settings.weightGoal == WeightGoal(kg: 82.5, startKg: 90))
        d.settings.weightGoal = nil
        #expect(d.settings.extra["iosWeightGoal"] == nil)
    }
}
