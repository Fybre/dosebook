import Foundation
import Testing
@testable import BenchCore

// Ports of spray, tablet, phase and diluent tests.

private let NOW_SPRAY: Millis = 1_788_598_800_000 // Date.UTC(2026, 8, 5, 9)
private let NOW: Millis = 1_785_326_400_000 // Date.UTC(2026, 6, 29, 12)
private let DAY = DAY_MS

private func sv(_ id: String = "v1", peptideId: String = "bpc-157", state: VialState = .reconstituted, diluentMl: Double? = 1,
                drawnMcg: Double = 0, container: ContainerKind? = nil, mlPerSpray: Double? = nil, cost: Double? = nil,
                currency: String? = nil, orderId: String? = nil, diluent: DiluentKind = .saline) -> Vial {
    var v = vial(id, peptideId: peptideId, strengthMg: 5, state: state, diluentMl: diluentMl, drawnMcg: drawnMcg,
                 cost: cost, currency: currency, orderId: orderId, container: container, mlPerSpray: mlPerSpray)
    v.diluent = diluent
    return v
}

@Suite struct SprayTests {
    @Test func workedExample() {
        let plan = transferToSpray(sv(), addedMl: 4, mlPerSpray: 0.1, atMs: NOW_SPRAY)!
        #expect(plan.bottle.strengthMg == 5 && plan.bottle.diluentMl == 5)
        #expect(vialConcentration(plan.bottle) == 1000 && mcgPerSpray(plan.bottle) == 100)
        #expect(mcgForSprays(plan.bottle, 2) == 200 && isClose(mlForSprays(plan.bottle, 2), 0.2, digits: 10))
    }

    @Test func pumpFallbacks() {
        #expect(mlPerSpray(vial()) == DEFAULT_ML_PER_SPRAY)
        #expect(mlPerSpray(vial(mlPerSpray: 0)) == DEFAULT_ML_PER_SPRAY)
        #expect(mlPerSpray(vial(mlPerSpray: 0.05)) == 0.05)
        #expect(mcgPerSpray(vial(strengthMg: 5, mlPerSpray: 0.1)) == 0)
        #expect(mcgPerSpray(sv(diluentMl: 5, container: .spray, mlPerSpray: 0.05)) == 50)
    }

    @Test func pressesForDose() {
        let b = sv(diluentMl: 5, container: .spray, mlPerSpray: 0.1)
        #expect(spraysForDose(b, 200) == 2 && spraysForDose(b, 250) == 3 && spraysForDose(b, 240) == 2)
        #expect(spraysForDose(b, 333) == spraysForDose(b, 333).rounded())
        #expect(spraysForDose(b, -100) == 0)
        #expect(spraysForDose(vial(strengthMg: 5), 200) == 0)
    }

    @Test func pressesLeft() {
        #expect(spraysRemaining(sv(diluentMl: 5, container: .spray, mlPerSpray: 0.1)) == 50)
        #expect(spraysRemaining(sv(diluentMl: 5, drawnMcg: 2000, container: .spray, mlPerSpray: 0.1)) == 30)
        #expect(spraysRemaining(sv(diluentMl: 5, container: .spray, mlPerSpray: 0.3)) == 16)
        #expect(spraysRemaining(sv(diluentMl: 5, drawnMcg: 5000, container: .spray, mlPerSpray: 0.1)) == 0)
    }

    @Test func transfer() {
        let plan = transferToSpray(sv(), addedMl: 4, mlPerSpray: 0.1, atMs: NOW_SPRAY)!
        #expect(plan.source.state == .finished && vialRemainingMcg(plan.source) == 0 && plan.bottle.strengthMg * 1000 == 5000)
        let partial = transferToSpray(sv(drawnMcg: 1000), addedMl: 4, mlPerSpray: 0.1, atMs: NOW_SPRAY)!
        #expect(partial.bottle.strengthMg == 4 && isClose(partial.bottle.diluentMl!, 4.8, digits: 10))
        let money = transferToSpray(sv(cost: 42, currency: "EUR"), addedMl: 4, mlPerSpray: 0.1, atMs: NOW_SPRAY)!
        #expect(money.bottle.cost == 42 && money.bottle.currency == "EUR" && money.source.cost == nil)
        let ordered = transferToSpray(sv(orderId: "o1"), addedMl: 4, mlPerSpray: 0.1, atMs: NOW_SPRAY)!
        #expect(ordered.source.orderId == "o1" && ordered.bottle.orderId == nil)
        #expect(plan.bottle.reconstitutedAt == NOW_SPRAY && plan.bottle.budAt == nil)
        let src = transferToSpray(sv("src"), addedMl: 4, mlPerSpray: 0.1, atMs: NOW_SPRAY)!
        #expect(isSpray(src.bottle) && src.bottle.filledFromVialId == "src")
        #expect(transferToSpray(sv(peptideId: "kpv"), addedMl: 4, mlPerSpray: 0.1, atMs: NOW_SPRAY)!.bottle.peptideId == "kpv")
        #expect(transferToSpray(sv(), addedMl: 4, mlPerSpray: 0.1, diluentBottleId: "amp1", atMs: NOW_SPRAY)!.drawnMl == 4)
        #expect(plan.drawnMl == 0)
        #expect(transferToSpray(sv(diluent: .bacteriostatic), addedMl: 4, mlPerSpray: 0.1, diluent: .saline, atMs: NOW_SPRAY)!.bottle.diluent == .saline)
        #expect(transferToSpray(sv(drawnMcg: 5000), addedMl: 4, mlPerSpray: 0.1, atMs: NOW_SPRAY) == nil)
        #expect(transferToSpray(sv(state: .sealed, diluentMl: nil), addedMl: 0, mlPerSpray: 0.1, atMs: NOW_SPRAY) == nil)
        let pour = transferToSpray(sv(), addedMl: 0, mlPerSpray: 0.1, atMs: NOW_SPRAY)!
        #expect(pour.bottle.diluentMl == 1 && mcgPerSpray(pour.bottle) == 500)
        #expect(transferToSpray(sv(), addedMl: 4, mlPerSpray: 0, atMs: NOW_SPRAY)!.bottle.mlPerSpray == DEFAULT_ML_PER_SPRAY)
    }

    @Test func containersAndRoutes() {
        #expect(!isSpray(sv()) && !isSpray(vial(container: .vial)) && isSpray(vial(container: .spray)))
        let spray = sv("b", container: .spray), plain = sv("v")
        #expect(routeChoices([.subcutaneous], [plain], "bpc-157") == [.subcutaneous])
        #expect(routeChoices([.subcutaneous], [spray], "bpc-157") == [.subcutaneous, .intranasal])
        #expect(routeChoices([.subcutaneous], [spray], "kpv") == [.subcutaneous])
        #expect(routeChoices([.intranasal, .subcutaneous], [spray], "bpc-157") == [.intranasal, .subcutaneous])
        #expect(routeChoices([.subcutaneous, .intramuscular], [spray], "bpc-157") == [.subcutaneous, .intramuscular, .intranasal])
        #expect(routeChoices([], [], "bpc-157") == [.subcutaneous])
        #expect(routeChoices([.subcutaneous], [], "x", .tablet) == [.subcutaneous, .oral])
        #expect(defaultRoute(.tablet, false) == .oral && defaultRoute(nil, true) == .intranasal && defaultRoute(.powder, false) == .subcutaneous)
    }
}

private func pack(drawnMcg: Double? = nil, mgPerTablet: Double? = 10) -> Vial {
    vial("p1", peptideId: "slu-pp-332", strengthMg: 600, drawnMcg: drawnMcg, container: .pack, mgPerTablet: mgPerTablet)
}

@Suite struct TabletTests {
    @Test func pack_() {
        #expect(isPack(pack()) && !isPack(vial(container: .spray)) && !isPack(vial()))
        #expect(packStrengthMg(10, 60) == 600 && packStrengthMg(10, 60.7) == 600)
        #expect(packStrengthMg(-10, 60) == 0 && packStrengthMg(10, -1) == 0)
    }

    @Test func nameless() {
        let n = pack(mgPerTablet: nil)
        #expect(mgPerTablet(n) == 0 && mcgPerTablet(n) == 0 && tabletsRemaining(n) == 0 && tabletsForDose(n, 10_000) == 0)
        #expect(mgPerTablet(pack(mgPerTablet: 0)) == 0 && mgPerTablet(pack(mgPerTablet: -5)) == 0)
    }

    @Test func doses() {
        #expect(tabletsForDose(pack(), 10_000) == 1 && tabletsForDose(pack(), 15_000) == 1.5)
        #expect(tabletsForDose(pack(mgPerTablet: 25), 12_500) == 0.5 && tabletsForDose(pack(), -10_000) == 0)
        #expect(isClose(mcgForTablets(pack(), tabletsForDose(pack(), 15_000)), 15_000, digits: 6))
        #expect(tabletsRemaining(pack()) == 60 && tabletsRemaining(pack(drawnMcg: 100_000)) == 50)
        #expect(tabletsRemaining(pack(drawnMcg: 555_000)) == 4 && tabletsRemaining(pack(drawnMcg: 700_000)) == 0)
    }

    @Test func blister() {
        #expect(blisterDots(1, 10) == 10 && blisterDots(0, 10) == 0)
        #expect(blisterDots(0.5, 10) == 5 && blisterDots(0.25, 10) == 3 && blisterDots(0.7, 10) == 7)
        #expect(blisterDots(1.0 / 60, 10) == 1 && blisterDots(0.0001, 10) == 1)
        #expect(blisterDots(59.0 / 60, 10) == 9 && blisterDots(0.9999, 10) == 9)
        #expect(blisterDots(.nan, 10) == 0 && blisterDots(-1, 10) == 0 && blisterDots(2, 10) == 10)
    }
}

@Suite struct PhaseTests {
    let reta = Library.byId["retatrutide"]!
    let tirz = Library.byId["tirzepatide"]!
    var bare: Peptide { var p = reta; p.id = "bare"; p.timeline = nil; return p }

    @Test func windows() {
        #expect(timelinePhaseAt(reta, 6)?.label.contains("Absorbing") == true)
        #expect(timelinePhaseAt(reta, 24)?.label.contains("Peak") == true)
        #expect(timelinePhaseAt(reta, 100)?.label.contains("Past peak") == true)
        #expect(timelinePhaseAt(reta, 12)?.fromHours == 12)
        #expect(isClose(timelinePhaseAt(reta, 30)!.progress, 0.5, digits: 6))
        #expect(isClose(timelinePhaseAt(reta, 40)!.hoursToNext!, 8, digits: 6))
        let last = reta.timeline!.last!
        #expect(timelinePhaseAt(reta, last.fromHours + 1)!.hoursToNext == nil)
        #expect(timelinePhaseAt(reta, last.toHours + 1) == nil)
        #expect(timelinePhaseAt(reta, -1) == nil && timelinePhaseAt(bare, 5) == nil)
        #expect(timelinePhaseAt(reta, 0)?.fromHours == 0 && timelinePhaseAt(reta, 0)?.progress == 0)
        #expect(timelinePhaseAt(tirz, 20)?.label.contains("Peak") == true)
        for p in [reta, tirz] {
            let end = p.timeline!.last!.toHours
            var h = 0.0
            while h < end {
                #expect(p.timeline!.filter { h >= $0.fromHours && h < $0.toHours }.count == 1, "\(p.id) at \(h)")
                h += 0.5
            }
        }
    }

    @Test func current() {
        let rows = timelineWithCurrent(reta, 24)
        #expect(rows.filter(\.current).count == 1 && rows.first(where: \.current)?.fromHours == 12)
        let later = timelineWithCurrent(reta, 100)
        #expect(later[0].past && later[1].past && later[2].current)
        #expect(timelineWithCurrent(reta, nil).allSatisfy { !$0.current && !$0.past })
        #expect(timelineWithCurrent(bare, 5).isEmpty)
    }

    @Test func since() {
        #expect(isClose(hoursSince(NOW - 6 * HOUR, NOW)!, 6, digits: 9))
        #expect(hoursSince(nil, NOW) == nil && hoursSince(NOW + HOUR, NOW) == 0)
    }
}

private func bottle(_ id: String, kind: DiluentKind = .bacteriostatic, volumeMl: Double = 30, state: BottleState = .sealed,
                    drawnMl: Double? = nil, budAt: Millis? = nil, expiresAt: Millis? = nil, openedAt: Millis? = nil) -> DiluentBottle {
    DiluentBottle(id: id, profileId: "me", kind: kind, volumeMl: volumeMl, drawnMl: drawnMl, state: state,
                  openedAt: openedAt, expiresAt: expiresAt, budAt: budAt)
}

@Suite struct DiluentTests {
    @Test func arithmeticAndUsable() {
        #expect(bottleRemainingMl(bottle("a")) == 30 && bottleFractionRemaining(bottle("a")) == 1)
        #expect(bottleRemainingMl(bottle("a", drawnMl: 12)) == 18 && bottleRemainingMl(bottle("a", drawnMl: 999)) == 0)
        #expect(bottleUsable(bottle("a"), NOW))
        #expect(!bottleUsable(bottle("a", state: .finished), NOW) && !bottleUsable(bottle("a", state: .discarded), NOW))
        #expect(!bottleUsable(bottle("a", state: .open, drawnMl: 30), NOW))
        let past = bottle("a", state: .open, budAt: NOW - DAY)
        #expect(bottleExpired(past, NOW) && !bottleUsable(past, NOW))
        #expect(!bottleUsable(bottle("a", expiresAt: NOW - DAY), NOW))
    }

    @Test func pick() {
        #expect(pickBottle([], .bacteriostatic, 2, NOW) == nil)
        #expect(pickBottle([bottle("saline", kind: .saline)], .bacteriostatic, 2, NOW) == nil)
        #expect(pickBottle([bottle("sealed"), bottle("open", state: .open, drawnMl: 10)], .bacteriostatic, 2, NOW)?.id == "open")
        #expect(pickBottle([bottle("nearly-empty", state: .open, drawnMl: 29, budAt: NOW + 2 * DAY),
                            bottle("fuller", state: .open, drawnMl: 5, budAt: NOW + 10 * DAY)], .bacteriostatic, 2, NOW)?.id == "fuller")
        #expect(pickBottle([bottle("nearly-empty", state: .open, drawnMl: 29), bottle("sealed")], .bacteriostatic, 2, NOW)?.id == "nearly-empty")
        #expect(pickBottle([bottle("later", state: .open, budAt: NOW + 20 * DAY), bottle("sooner", state: .open, budAt: NOW + 3 * DAY)],
                           .bacteriostatic, 2, NOW)?.id == "sooner")
    }

    @Test func open() {
        let out = openBottle([bottle("a")], "a", NOW)
        #expect(out[0].state == .open && out[0].openedAt == NOW && out[0].drawnMl == nil && out[0].budAt == NOW + 28 * DAY)
        #expect(drawFromBottle([bottle("a")], "a", 2, NOW)[0].budAt == out[0].budAt)
        let already = bottle("a", state: .open, budAt: 9, openedAt: 5)
        #expect(openBottle([already], "a", NOW)[0] == already)
        #expect(openBottle([bottle("a", state: .finished, drawnMl: 30)], "a", NOW)[0].state == .finished)
    }

    @Test func draw() {
        let out = drawFromBottle([bottle("a")], "a", 2, NOW)
        #expect(out[0].drawnMl == 2 && bottleRemainingMl(out[0]) == 28 && out[0].state == .open && out[0].openedAt == NOW)
        #expect(drawFromBottle(out, "a", 2, NOW + DAY)[0].openedAt == NOW)
        let emptied = drawFromBottle([bottle("a", state: .open, drawnMl: 28)], "a", 2, NOW)
        #expect(emptied[0].state == .finished && bottleRemainingMl(emptied[0]) == 0)
        let over = drawFromBottle([bottle("a")], "a", 999, NOW)
        #expect(over[0].drawnMl == 30 && bottleRemainingMl(over[0]) == 0)
        let shelf = [bottle("a"), bottle("b")]
        #expect(drawFromBottle(shelf, "a", 2, NOW)[1].drawnMl == nil && shelf[0].drawnMl == nil)
        #expect(drawFromBottle(shelf, "a", 0, NOW) == shelf)
    }

    @Test func giveBack() {
        let back = returnToBottle(drawFromBottle([bottle("a")], "a", 30, NOW), "a", 5)
        #expect(back[0].state == .open && bottleRemainingMl(back[0]) == 5)
        #expect(returnToBottle(drawFromBottle([bottle("a")], "a", 2.5, NOW), "a", 2.5)[0].drawnMl == 0)
    }

    @Test func stock() {
        let shelf = [bottle("a", state: .open, drawnMl: 10), bottle("b"), bottle("gone", state: .finished, drawnMl: 30), bottle("other", kind: .saline)]
        #expect(diluentStock(shelf, .bacteriostatic, NOW) == DiluentStock(remainingMl: 50, bottles: 2, openBottles: 1))
        #expect(diluentStock([], .bacteriostatic, NOW) == DiluentStock(remainingMl: 0, bottles: 0, openBottles: 0))
    }

    @Test func order() {
        let ids: ([DiluentBottle]) -> [String] = { $0.map(\.id) }
        #expect(ids(shelfOrder([bottle("open-1", state: .open, budAt: NOW + 20 * DAY), bottle("sealed"),
                                bottle("open-2", state: .open, budAt: NOW + 10 * DAY)], NOW)) == ["open-2", "open-1", "sealed"])
        let agree = [bottle("sealed", expiresAt: NOW + 5 * DAY), bottle("open-late", state: .open, budAt: NOW + 25 * DAY),
                     bottle("open-soon", state: .open, budAt: NOW + 3 * DAY)]
        #expect(shelfOrder(agree, NOW)[0].id == pickBottle(agree, .bacteriostatic, 1, NOW)!.id)
        #expect(ids(shelfOrder([bottle("later", state: .open, budAt: NOW + 20 * DAY), bottle("sooner", state: .open, budAt: NOW + 2 * DAY)], NOW)) == ["sooner", "later"])
        let sink = ids(shelfOrder([bottle("expired", state: .open, budAt: NOW - DAY), bottle("empty", state: .open, drawnMl: 30, budAt: NOW + DAY),
                                   bottle("good", state: .open, budAt: NOW + 10 * DAY), bottle("sealed")], NOW))
        #expect(Array(sink.prefix(2)) == ["good", "sealed"] && sink.suffix(2).sorted() == ["empty", "expired"])
        let undated = [bottle("b", state: .open), bottle("a", state: .open)]
        #expect(ids(shelfOrder(undated, NOW)) == ["a", "b"] && ids(shelfOrder(shelfOrder(undated, NOW), NOW)) == ["a", "b"])
        #expect(shelfOrder([], NOW).isEmpty)
    }

    @Test func rows() {
        let three = [bottle("a"), bottle("b"), bottle("c")]
        #expect(shelfRows(three, NOW, grouped: false).map(\.count) == [1, 1, 1])
        #expect(shelfRows(three, NOW, grouped: false).map(\.key) == ["a", "b", "c"])
        let four = shelfRows([bottle("a"), bottle("b"), bottle("c"), bottle("d")], NOW, grouped: true)
        #expect(four.count == 1 && four[0].count == 4 && four[0].bottles.map(\.id) == ["a", "b", "c", "d"])
        let mixed = shelfRows([bottle("bac-30"), bottle("bac-30-b"), bottle("sal-10", kind: .saline, volumeMl: 10), bottle("bac-10", volumeMl: 10)], NOW, grouped: true)
        #expect(mixed.count == 3)
        #expect(mixed.first { $0.key == "bacteriostatic:30" }?.count == 2)
        #expect(mixed.first { $0.key == "bacteriostatic:10" }?.count == 1)
        #expect(mixed.first { $0.key == "saline:10" }?.count == 1)
        #expect(shelfRows([bottle("open-1", state: .open, budAt: NOW + 10 * DAY), bottle("open-2", state: .open, budAt: NOW + 20 * DAY)], NOW, grouped: true).map(\.count) == [1, 1])
        let exp = shelfRows([bottle("good-1"), bottle("good-2"), bottle("expired", expiresAt: NOW - DAY)], NOW, grouped: true)
        #expect(exp.count == 2 && exp[0].count == 2 && exp[1].bottle.id == "expired")
        let first = shelfRows([bottle("open", state: .open, budAt: NOW + 5 * DAY), bottle("sealed-1"), bottle("sealed-2")], NOW, grouped: true)
        #expect(first[0].bottle.id == "open" && first[1].count == 2)
        let reach = [bottle("later", expiresAt: NOW + 40 * DAY), bottle("sooner", expiresAt: NOW + 4 * DAY)]
        let r = shelfRows(reach, NOW, grouped: true)
        #expect(r[0].count == 2 && r[0].bottle.id == pickBottle(reach, .bacteriostatic, 1, NOW)!.id)
        #expect(shelfRows([], NOW, grouped: true).isEmpty)
    }
}
