import Foundation
import Testing
@testable import BenchCore

@Suite struct StockAlertTests {
    /// Ten 500 mcg doses in one sealed vial, one dose a day at 8am.
    func setup(vialMg: Double = 5) -> AppData {
        var d = AppData()
        _ = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 500,
                                       schedule: Schedule(kind: .daily, timeOfDay: "08:00")))
        d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: vialMg, state: .sealed))
        return d
    }
    let now = local(2026, 7, 3, 12)

    @Test func warnsTheMorningTheDoseThatCrossesTheLineIsDue() {
        let alerts = lowStockAlerts(setup(), nowMs: now)
        // 10 doses, low at 4: the 6th dose from now is the 9th, so 9am that day.
        #expect(alerts.count == 1)
        #expect(alerts[0].fireAt == local(2026, 7, 9, 9))
        #expect(!alerts[0].lowNow)
        #expect(alerts[0].dosesLeft == 4)
    }

    @Test func daysCountedAgainstThePlan() {
        var d = setup()
        d.settings.lowStockUnit = .days
        d.settings.lowStockDays = 3
        // Three days is three doses: reached after the 7th.
        #expect(lowStockAlerts(d, nowMs: now)[0].fireAt == local(2026, 7, 10, 9))
    }

    @Test func alreadyLowGoesAtTheNextNineAm() {
        var d = setup()
        d.settings.lowStockDoses = 12
        let a = lowStockAlerts(d, nowMs: now)
        #expect(a.count == 1 && a[0].lowNow && a[0].fireAt == local(2026, 7, 4, 9))
        #expect(lowStockAlerts(d, nowMs: local(2026, 7, 4, 7))[0].fireAt == local(2026, 7, 4, 9))
    }

    @Test func plentyOfStockOrNoVialGivesNothing() {
        #expect(lowStockAlerts(setup(vialMg: 500), nowMs: now).isEmpty)
        var d = AppData()
        _ = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 500, schedule: Schedule(kind: .daily, timeOfDay: "08:00")))
        #expect(lowStockAlerts(d, nowMs: now).isEmpty)
    }

    @Test func lowFollowsTheChosenUnit() {
        var d = setup()
        let stock = stockFor(d.vials, "bpc-157", 500, now)
        #expect(!stockIsLow(stock, supplyDays: 10, d.settings))
        d.settings.lowStockDoses = 10
        #expect(stockIsLow(stock, supplyDays: 10, d.settings))
        d.settings.lowStockUnit = .days
        d.settings.lowStockDays = 7
        #expect(!stockIsLow(stock, supplyDays: 10, d.settings))
        #expect(stockIsLow(stock, supplyDays: 6.5, d.settings))
    }

    @Test func aVialUsedUpIsNotOneMarkedFinishedByHand() {
        var v = Vial(id: "a", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .finished)
        #expect(!vialUsedUp(v))
        v.drawnMcg = 5000
        #expect(vialUsedUp(v))
        v.state = .reconstituted
        #expect(!vialUsedUp(v))
    }

    @Test func countsWhatIsLeftToOpen() {
        var d = setup()
        d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .sealed))
        let used = Vial(id: "u", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .finished, drawnMcg: 5000)
        #expect(vialsLeftInStock(d, like: used, nowMs: now) == 2)
        #expect(vialsLeftInStock(AppData(), like: used, nowMs: now) == 0)
    }
}
