import Foundation
import Testing
@testable import BenchCore

// Port of src/lib/calc/inventory.test.ts.

private let NOW: Millis = 1_785_326_400_000 // Date.UTC(2026, 6, 29, 12)
private let DAY = DAY_MS

@Suite struct VialMass {
    @Test func arithmetic() {
        #expect(vialCapacityMcg(vial(strengthMg: 80)) == 80_000)
        #expect(vialCapacityMcg(vial(strengthMg: 2.5)) == 2500)
        #expect(vialRemainingMcg(vial()) == 80_000 && vialFractionRemaining(vial()) == 1)
        let drawn = vial(drawnMcg: 20_000)
        #expect(vialRemainingMcg(drawn) == 60_000 && isClose(vialFractionRemaining(drawn), 0.75, digits: 12))
        #expect(vialRemainingMcg(vial(drawnMcg: 999_999)) == 0 && vialFractionRemaining(vial(drawnMcg: 999_999)) == 0)
        #expect(vialRemainingMl(vial()) == 0)
        let open = vial(state: .reconstituted, diluentMl: 4, drawnMcg: 20_000)
        #expect(vialConcentration(open) == 20_000 && isClose(vialRemainingMl(open), 3, digits: 12))
    }
}

@Suite struct VialUsableTests {
    @Test func cases() {
        #expect(vialUsable(vial(), NOW))
        #expect(!vialUsable(vial(state: .finished), NOW))
        #expect(!vialUsable(vial(state: .discarded), NOW))
        #expect(!vialUsable(vial(state: .reconstituted, drawnMcg: 80_000), NOW))
        let past = vial(state: .reconstituted, diluentMl: 4, budAt: NOW - DAY)
        #expect(vialExpired(past, NOW) && !vialUsable(past, NOW))
        #expect(!vialUsable(vial(expiresAt: NOW - DAY), NOW))
    }
}

@Suite struct PickVialForDose {
    @Test func basics() {
        #expect(pickVialForDose([], "klow", 4000, NOW) == nil)
        #expect(pickVialForDose([vial(peptideId: "bpc-157")], "klow", 4000, NOW) == nil)
        #expect(pickVialForDose([vial("sealed"), vial("open", state: .reconstituted, diluentMl: 4, budAt: NOW + 20 * DAY)], "klow", 4000, NOW)?.id == "open")
        #expect(pickVialForDose([vial("sealed")], "klow", 4000, NOW)?.id == "sealed")
        #expect(pickVialForDose([vial("later", state: .reconstituted, diluentMl: 4, budAt: NOW + 20 * DAY),
                                 vial("sooner", state: .reconstituted, diluentMl: 4, budAt: NOW + 3 * DAY)], "klow", 4000, NOW)?.id == "sooner")
    }

    @Test func coversWholeDose() {
        let vials = [vial("nearly-empty", state: .reconstituted, diluentMl: 4, drawnMcg: 79_000, budAt: NOW + 2 * DAY),
                     vial("full", state: .reconstituted, diluentMl: 4, budAt: NOW + 10 * DAY)]
        #expect(pickVialForDose(vials, "klow", 4000, NOW)?.id == "full")
        let partial = [vial("nearly-empty", state: .reconstituted, diluentMl: 4, drawnMcg: 79_000), vial("sealed")]
        #expect(pickVialForDose(partial, "klow", 4000, NOW)?.id == "nearly-empty")
    }

    @Test func openPastDate() {
        #expect(pickVialForDose([vial("expired", state: .reconstituted, diluentMl: 4, budAt: NOW - DAY), vial("sealed")], "klow", 4000, NOW)?.id == "expired")
        #expect(pickVialForDose([vial("expired", state: .reconstituted, diluentMl: 4, budAt: NOW - DAY),
                                 vial("fine", state: .reconstituted, diluentMl: 4, budAt: NOW + 10 * DAY)], "klow", 4000, NOW)?.id == "fine")
        #expect(pickVialForDose([vial("old", state: .reconstituted, diluentMl: 4, budAt: NOW - 30 * DAY),
                                 vial("recent", state: .reconstituted, diluentMl: 4, budAt: NOW - DAY)], "klow", 4000, NOW)?.id == "recent")
        #expect(pickVialForDose([vial("stale", expiresAt: NOW - DAY)], "klow", 4000, NOW) == nil)
        #expect(pickVialForDose([vial("drained", state: .reconstituted, diluentMl: 4, drawnMcg: 80_000, budAt: NOW - DAY), vial("sealed")], "klow", 4000, NOW)?.id == "sealed")
    }
}

@Suite struct OpenPastDateWithSpares {
    let open = vial("open", peptideId: "retatrutide", strengthMg: 10, state: .reconstituted, diluentMl: 2, drawnMcg: 4500, budAt: NOW - 2 * HOUR)
    var shelf: [Vial] { ["a", "b", "c", "d"].map { vial($0, peptideId: "retatrutide", strengthMg: 10) } + [open] }

    @Test func cases() {
        #expect(pickVialForDose(shelf, "retatrutide", 1500, NOW)?.id == "open")
        #expect(isClose(marksForDose(shelf, "retatrutide", 1500, .u100, NOW) ?? -1, 30, digits: 9))
        let ids = drawableVials(shelf, "retatrutide", NOW).map(\.id)
        #expect(ids.contains("open") && ids.count == 5)
        let s = stockFor(shelf, "retatrutide", 1500, NOW)
        #expect(!s.needsReconstitution && s.availableMcg == 40_000 && s.dosesExpired == 3)
    }
}

@Suite struct DrawAndReturn {
    @Test func draw() {
        let out = drawFromVial([vial()], "a", 4000)
        #expect(out[0].drawnMcg == 4000 && vialRemainingMcg(out[0]) == 76_000)
        var vials = [vial()]
        for _ in 0..<4 { vials = drawFromVial(vials, "a", 4000) }
        #expect(vials[0].drawnMcg == 16_000 && vialRemainingMcg(vials[0]) == 64_000)
        let emptied = drawFromVial([vial(strengthMg: 10, drawnMcg: 9500)], "a", 500)
        #expect(emptied[0].state == .finished && vialRemainingMcg(emptied[0]) == 0)
        let over = drawFromVial([vial(strengthMg: 10)], "a", 999_999)
        #expect(over[0].drawnMcg == 10_000 && vialRemainingMcg(over[0]) == 0)
        let input = [vial("a"), vial("b")]
        let two = drawFromVial(input, "a", 4000)
        #expect(two[1].drawnMcg == nil && input[0].drawnMcg == nil)
        #expect(drawFromVial(input, "a", 0) == input)
    }

    @Test func giveBack() {
        #expect(returnToVial([vial(drawnMcg: 8000)], "a", 4000)[0].drawnMcg == 4000)
        #expect(returnToVial([vial(strengthMg: 10, state: .finished, diluentMl: 2, drawnMcg: 10_000)], "a", 500)[0].state == .reconstituted)
        #expect(returnToVial([vial(strengthMg: 10, state: .finished, drawnMcg: 10_000)], "a", 500)[0].state == .sealed)
        #expect(returnToVial([vial(drawnMcg: 1000)], "a", 9999)[0].drawnMcg == 0)
        let start = [vial(strengthMg: 10, state: .reconstituted, diluentMl: 2)]
        let after = returnToVial(drawFromVial(start, "a", 2500), "a", 2500)
        #expect(after[0].drawnMcg == 0 && after[0].state == .reconstituted)
    }
}

@Suite struct StockForTests {
    @Test func basics() {
        let empty = stockFor([], "klow", 4000, NOW)
        #expect(empty.dosesRemaining == 0 && !empty.needsReconstitution)
        let s = stockFor([vial("a"), vial("b")], "klow", 4000, NOW)
        #expect(s.availableMcg == 160_000 && s.dosesRemaining == 40 && s.sealedCount == 2 && s.needsReconstitution)
    }

    @Test func dropsPerDose() {
        var vials = [vial("a"), vial("b")]
        #expect(stockFor(vials, "klow", 4000, NOW).dosesRemaining == 40)
        for _ in 0..<4 { vials = drawFromVial(vials, pickVialForDose(vials, "klow", 4000, NOW)!.id, 4000) }
        #expect(stockFor(vials, "klow", 4000, NOW).dosesRemaining == 36)
    }

    @Test func emptiesThenMovesOn() {
        var vials = [vial("a", strengthMg: 10, state: .reconstituted, diluentMl: 2), vial("b", strengthMg: 10)]
        for _ in 0..<10 { vials = drawFromVial(vials, pickVialForDose(vials, "klow", 1000, NOW)!.id, 1000) }
        #expect(vials.first { $0.id == "a" }!.state == .finished)
        #expect(stockFor(vials, "klow", 1000, NOW).dosesRemaining == 10)
        #expect(pickVialForDose(vials, "klow", 1000, NOW)!.id == "b")
    }

    @Test func openVersusSealed() {
        let s = stockFor([vial("open", state: .reconstituted, diluentMl: 4, drawnMcg: 40_000), vial("sealed")], "klow", 4000, NOW)
        #expect(s.dosesInOpenVials == 10 && s.dosesRemaining == 30 && !s.needsReconstitution)
    }

    @Test func excludesAndRounds() {
        let vials = [vial("good"), vial("expired", state: .reconstituted, diluentMl: 4, budAt: NOW - DAY), vial("done", state: .finished)]
        #expect(stockFor(vials, "klow", 4000, NOW).dosesRemaining == 20)
        #expect(stockFor([vial(strengthMg: 10)], "klow", 3000, NOW).dosesRemaining == 3)
        #expect(stockFor([vial()], "klow", 0, NOW).dosesRemaining == 0)
    }
}

@Suite struct MarksForDoseTests {
    let open = vial("open", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 2)

    @Test func cases() {
        #expect(isClose(marksForDose([open], "bpc-157", 250, .u100, NOW)!, 10, digits: 9))
        #expect(isClose(marksForDose([open], "bpc-157", 250, .u40, NOW)!, 4, digits: 9))
        #expect(marksForDose([vial("sealed", peptideId: "bpc-157", strengthMg: 5)], "bpc-157", 250, .u100, NOW) == nil)
        #expect(marksForDose([open], "kpv", 250, .u100, NOW) == nil)
        #expect(marksForDose([], "bpc-157", 250, .u100, NOW) == nil)
        #expect(marksForDose([vial("x", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted)], "bpc-157", 250, .u100, NOW) == nil)
        let soon = vial("soon", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 1, budAt: NOW + 2 * DAY)
        #expect(isClose(marksForDose([open.with { $0.budAt = NOW + 20 * DAY }, soon], "bpc-157", 250, .u100, NOW)!, 5, digits: 9))
    }

    @Test func pastDate() {
        #expect(isClose(marksForDose([open.with { $0.budAt = NOW - DAY }], "bpc-157", 250, .u100, NOW)!, 10, digits: 9))
        let expired = open.with { $0.id = "expired"; $0.diluentMl = 1; $0.budAt = NOW - DAY }
        #expect(isClose(marksForDose([expired, open.with { $0.budAt = NOW + 20 * DAY }], "bpc-157", 250, .u100, NOW)!, 10, digits: 9))
        let old = open.with { $0.id = "old"; $0.diluentMl = 1; $0.budAt = NOW - 40 * DAY }
        let recent = open.with { $0.id = "recent"; $0.diluentMl = 2; $0.budAt = NOW - DAY }
        #expect(isClose(marksForDose([old, recent], "bpc-157", 250, .u100, NOW)!, 10, digits: 9))
        #expect(marksForDose([open.with { $0.budAt = NOW - DAY; $0.drawnMcg = 5000 }], "bpc-157", 250, .u100, NOW) == nil)
        #expect(marksForDose([open.with { $0.budAt = NOW - DAY; $0.state = .discarded }], "bpc-157", 250, .u100, NOW) == nil)
    }
}

@Suite struct DaysOfSupplyFlat {
    @Test func cases() {
        let s = stockFor([vial(strengthMg: 80)], "klow", 4000, NOW)
        #expect(s.dosesRemaining == 20)
        #expect(isClose(daysOfSupply(s, 7)!, 20, digits: 10) && isClose(daysOfSupply(s, 1)!, 140, digits: 10))
        #expect(daysOfSupply(stockFor([], "klow", 4000, NOW), 0) == nil)
    }
}

@Suite struct ReconcileVialsTests {
    func open(_ id: String, _ drawn: Double = 0) -> Vial { vial(id, strengthMg: 10, state: .reconstituted, diluentMl: 2, drawnMcg: drawn) }
    func c(_ vialId: String?, _ dose: Double, skipped: Bool? = nil) -> Consumption { Consumption(vialId: vialId, doseMcg: dose, skipped: skipped) }

    @Test func cases() {
        #expect(reconcileVials([open("a", 2000)], c("a", 500), c("a", 500))[0].drawnMcg == 2000)
        #expect(reconcileVials([open("a", 2000)], c("a", 500), c("a", 750))[0].drawnMcg == 2250)
        #expect(reconcileVials([open("a", 2000)], c("a", 500), c("a", 250))[0].drawnMcg == 1750)
        let moved = reconcileVials([open("a", 2000), open("b", 1000)], c("a", 500), c("b", 500))
        #expect(moved.first { $0.id == "a" }!.drawnMcg == 1500 && moved.first { $0.id == "b" }!.drawnMcg == 1500)
        #expect(reconcileVials([open("a", 2000)], c("a", 500), c("a", 500, skipped: true))[0].drawnMcg == 1500)
        #expect(reconcileVials([open("a", 1500)], c("a", 500, skipped: true), c("a", 500))[0].drawnMcg == 2000)
        #expect(reconcileVials([open("a", 2000)], c("a", 500), c(nil, 500))[0].drawnMcg == 1500)
        #expect(reconcileVials([open("a", 2000)], c(nil, 500), c("a", 500))[0].drawnMcg == 2500)
        #expect(reconcileVials([open("a", 2000)], nil, c("a", 500))[0].drawnMcg == 2500)
        #expect(reconcileVials([open("a", 2000)], c("a", 500), nil)[0].drawnMcg == 1500)
    }

    @Test func states() {
        let reopened = reconcileVials([vial(strengthMg: 10, state: .finished, diluentMl: 2, drawnMcg: 10_000)], c("a", 2000), c("a", 500))
        #expect(reopened[0].drawnMcg == 8500 && reopened[0].state == .reconstituted)
        let finished = reconcileVials([open("a", 9000)], c("a", 500), c("a", 1500))
        #expect(finished[0].drawnMcg == 10_000 && finished[0].state == .finished)
        #expect(reconcileVials([open("a", 100)], c("a", 9999), nil)[0].drawnMcg == 0)
    }

    @Test func roundTripsAndConserves() {
        let start = [open("a", 3000), open("b", 500)]
        let edited = reconcileVials(start, c("a", 500), c("b", 750))
        let back = reconcileVials(edited, c("b", 750), c("a", 500))
        #expect(back.first { $0.id == "a" }!.drawnMcg == 3000 && back.first { $0.id == "b" }!.drawnMcg == 500)
        let pair = [open("a", 2000), open("b", 1000)]
        let total: ([Vial]) -> Double = { $0.reduce(0) { $0 + vialRemainingMcg($1) } }
        #expect(total(reconcileVials(pair, c("a", 500), c("b", 500))) == total(pair))
    }
}

private func stockOf(_ mcg: Double) -> Stock {
    Stock(availableMcg: mcg, sealedCount: 1, openCount: 0, dosesRemaining: 0, dosesInOpenVials: 0, needsReconstitution: false, dosesExpired: 0)
}

@Suite struct SupplyWalk {
    let start = local(2026, 1, 5, 9)
    func protocolWith(phases: [ProtocolPhase]? = nil, schedule: Schedule? = nil) -> DoseProtocol {
        makeProtocol(peptideId: "klow", startedAt: start, schedule: schedule ?? Schedule(kind: .intervalDays, intervalDays: 7, timeOfDay: "09:00"), phases: phases)
    }
    let ladder = [ProtocolPhase(step: 1, doseMcg: 1000, weeks: 4), ProtocolPhase(step: 2, doseMcg: 2000, weeks: 4)]

    @Test func daysOfSupplyForProtocolCases() {
        #expect(jsRound(daysOfSupplyForProtocol(stockOf(10_000), protocolWith(), start)!) == 70)
        #expect(jsRound(daysOfSupplyForProtocol(stockOf(10_000), protocolWith(phases: ladder), start)!) == 49)
        #expect(daysOfSupplyForProtocol(stockOf(10_000), protocolWith(phases: ladder), start)! < daysOfSupplyForProtocol(stockOf(10_000), protocolWith(), start)!)
        #expect(daysOfSupplyForProtocol(stockOf(10_000), protocolWith(schedule: Schedule(kind: .asNeeded)), start) == nil)
        #expect(isClose(daysOfSupplyForProtocol(stockOf(0), protocolWith(), start)!, 0, digits: 5))
        #expect(daysOfSupplyForProtocol(stockOf(10_000_000), protocolWith(), start, horizonDays: 365) == 365)
    }

    @Test func outlook() {
        guard case .runsOut(let at) = supplyOutlook(stockOf(10_000), protocolWith(), start) else { Issue.record("expected a date"); return }
        #expect(jsRound((at - start) / DAY) == 70)
        let days = daysOfSupplyForProtocol(stockOf(10_000), protocolWith(), start, horizonDays: 365)!
        #expect(isClose(at, start + days * DAY, digits: 3))
        #expect(supplyOutlook(stockOf(10_000_000), protocolWith(), start) == .beyondHorizon)
        #expect(supplyOutlook(stockOf(10_000), protocolWith(schedule: Schedule(kind: .asNeeded)), start) == .unknown)
        #expect(supplyOutlook(stockOf(0), protocolWith(), start) == .unknown)
        guard case .runsOut(let stepped) = supplyOutlook(stockOf(10_000), protocolWith(phases: ladder), start) else { Issue.record("expected"); return }
        #expect(stepped < at)
    }
}

@Suite struct OnOrder {
    let ordered = vial("post", strengthMg: 10, state: .onOrder, cost: 40)
    let here = vial("fridge", strengthMg: 10, state: .sealed, cost: 40)

    @Test func cases() {
        #expect(!vialUsable(ordered, NOW) && vialUsable(here, NOW))
        #expect(pickVialForDose([ordered], "klow", 1000, NOW) == nil)
        #expect(pickVialForDose([ordered, here], "klow", 1000, NOW)?.id == "fridge")
        let without = stockFor([here], "klow", 1000, NOW), with = stockFor([here, ordered], "klow", 1000, NOW)
        #expect(with.availableMcg == without.availableMcg && with.dosesRemaining == without.dosesRemaining && with.sealedCount == without.sealedCount)
        let only = stockFor([ordered], "klow", 1000, NOW)
        #expect(only.availableMcg == 0 && only.dosesRemaining == 0 && !only.needsReconstitution)
        let spend = totalSpend([here, ordered], fallbackCurrency: "EUR")
        #expect(spend.byCurrency == [CurrencyTotal(currency: "EUR", total: 80, vials: 2)] && spend.pricedVials == 2)
        let groups = groupSealedVials([here, ordered])
        #expect(groups.count == 1 && groups[0].count == 1 && groups[0].vials[0].id == "fridge")
        let arrived = ordered.with { $0.state = .sealed }
        #expect(vialUsable(arrived, NOW) && stockFor([arrived], "klow", 1000, NOW).availableMcg == 10_000)
    }
}

@Suite struct TopUp {
    let ghk = vial(strengthMg: 50, diluentMl: 2.5, drawnMcg: 4_000)
    func concAfter(_ v: Vial, _ added: Double) -> Double { vialConcentration(v.with { $0.diluentMl = diluentAfterTopUp(v, added)! }) }

    @Test func cases() {
        #expect(isClose(concAfter(ghk, 0.5), 16_428.57, digits: 1))
        #expect(!isClose(concAfter(ghk, 0.5), 16_666.67, digits: 1))
        let after = ghk.with { $0.diluentMl = diluentAfterTopUp(ghk, 0.5)! }
        #expect(vialRemainingMcg(after) == vialRemainingMcg(ghk))
        #expect(isClose(vialRemainingMl(after), vialRemainingMl(ghk) + 0.5, digits: 9))
        let fresh = vial(strengthMg: 50, diluentMl: 2.5, drawnMcg: 0)
        #expect(isClose(diluentAfterTopUp(fresh, 0.5)!, 3, digits: 9) && isClose(concAfter(fresh, 0.5), 16_666.67, digits: 1))
        #expect(isClose(concAfter(vial(strengthMg: 50, diluentMl: 2.5, drawnMcg: 40_000), 0.5), 10_000, digits: 6))
        let once = ghk.with { $0.diluentMl = diluentAfterTopUp(ghk, 0.5)! }
        let twice = once.with { $0.diluentMl = diluentAfterTopUp(once, 0.5)! }
        #expect(isClose(vialRemainingMl(twice), vialRemainingMl(ghk) + 1, digits: 9) && vialRemainingMcg(twice) == vialRemainingMcg(ghk))
        #expect(diluentAfterTopUp(vial(strengthMg: 50, drawnMcg: 0), 0.5) == nil)
        #expect(diluentAfterTopUp(vial(strengthMg: 50, diluentMl: 2.5, drawnMcg: 50_000), 0.5) == nil)
        #expect(diluentAfterTopUp(ghk, 0) == nil && diluentAfterTopUp(ghk, -1) == nil && diluentAfterTopUp(ghk, .nan) == nil)
    }
}

@Suite struct SpraysAndSyringes {
    let now: Millis = 1_788_598_800_000 // Date.UTC(2026, 8, 5, 9)
    var shelf: [Vial] {
        [vial("v", strengthMg: 5, state: .reconstituted, diluentMl: 2),
         vial("spray", strengthMg: 5, state: .reconstituted, diluentMl: 5, container: .spray, mlPerSpray: 0.1)]
    }

    @Test func cases() {
        #expect(matchesContainer(vial()) && matchesContainer(vial(container: .vial)))
        #expect(!matchesContainer(vial(container: .spray)) && matchesContainer(vial(container: .spray), .spray))
        #expect(pickVialForDose(shelf, "klow", 250, now)!.id == "v")
        #expect(pickVialForDose(shelf, "klow", 250, now, .spray)!.id == "spray")
        #expect(pickVialForDose([shelf[1]], "klow", 250, now) == nil)
        #expect(stockFor(shelf, "klow", 250, now).availableMcg == 5000)
        #expect(stockFor(shelf, "klow", 250, now, .spray).availableMcg == 5000)
        #expect(marksForDose([shelf[1]], "klow", 250, .u100, now) == nil)
    }
}

@Suite struct HeldBackByDate {
    let inDate = vial("in", peptideId: "kpv", strengthMg: 10, state: .reconstituted, diluentMl: 2, budAt: NOW + DAY)
    var past: Vial { inDate.with { $0.id = "past"; $0.budAt = NOW - DAY } }

    @Test func cases() {
        #expect(stockFor([past], "kpv", 250, NOW).dosesRemaining == 0)
        #expect(stockFor([past], "kpv", 250, NOW).dosesExpired == 40)
        let s = stockFor([inDate], "kpv", 250, NOW)
        #expect(s.dosesRemaining > 0 && s.dosesExpired == 0)
        #expect(stockFor([past.with { $0.state = .finished }], "kpv", 250, NOW).dosesExpired == 0)
    }
}

@Suite struct ContainerForDoseTests {
    @Test func cases() {
        #expect(containerForDose(nil, .subcutaneous) == .vial)
        #expect(containerForDose(.powder, .intramuscular) == .vial)
        #expect(containerForDose(.solution, .subcutaneous) == .vial)
        #expect(containerForDose(.tablet, .oral) == .pack)
        #expect(containerForDose(.tablet, .subcutaneous) == .pack)
        #expect(containerForDose(.solution, .oral) == .vial)
        #expect(containerForDose(nil, .oral) == .vial)
        #expect(containerForDose(nil, .intranasal) == .spray)
        #expect(containerForDose(.powder, .intranasal) == .spray)
        #expect(containerForDose(.tablet, .intranasal) == .spray)
    }
}

@Suite struct OpeningAPack {
    func pack(_ id: String = "p", strengthMg: Double = 600, reconstitutedAt: Millis? = nil) -> Vial {
        vial(id, strengthMg: strengthMg, container: .pack, mgPerTablet: 10, reconstitutedAt: reconstitutedAt)
    }

    @Test func cases() {
        let out = openPack(pack(), NOW)
        #expect(out.state == .reconstituted && out.reconstitutedAt == NOW && out.budAt == nil)
        #expect(openPack(pack(reconstitutedAt: NOW - DAY), NOW).reconstitutedAt == NOW - DAY)
        let first = drawFromVial([pack()], "p", 10_000, NOW)[0]
        #expect(first.state == .reconstituted && first.reconstitutedAt == NOW && first.drawnMcg == 10_000)
        #expect(drawFromVial([pack()], "p", 10_000, NOW - 3 * DAY)[0].reconstitutedAt == NOW - 3 * DAY)
        let sealedVial = drawFromVial([vial("v")], "v", 10_000, NOW)[0]
        #expect(sealedVial.state == .sealed && sealedVial.reconstitutedAt == nil)
        #expect(drawFromVial([pack(strengthMg: 10)], "p", 10_000, NOW)[0].state == .finished)
        #expect(returnToVial(drawFromVial([pack(strengthMg: 10)], "p", 10_000, NOW), "p", 10_000)[0].state == .reconstituted)
        #expect(returnToVial(drawFromVial([vial("v", strengthMg: 10)], "v", 10_000, NOW), "v", 10_000)[0].state == .sealed)
        let started = openPack(pack("started"), NOW).with { $0.drawnMcg = 100_000 }
        #expect(pickVialForDose([pack("sealed"), started], "klow", 10_000, NOW, .pack)?.id == "started")
    }
}

@Suite struct StockAndContainer {
    let pack = vial("p", strengthMg: 600, container: .pack, mgPerTablet: 10)

    @Test func cases() {
        #expect(stockFor([pack], "klow", 10_000, NOW).dosesRemaining == 0)
        let s = stockFor([pack], "klow", 10_000, NOW, .pack)
        #expect(s.dosesRemaining == 60 && s.availableMcg == 600_000 && !s.needsReconstitution)
        #expect(stockFor([vial("v")], "klow", 10_000, NOW).needsReconstitution)
        let both = [pack, vial("v", strengthMg: 10)]
        #expect(stockFor(both, "klow", 10_000, NOW, .pack).dosesRemaining == 60)
        #expect(stockFor(both, "klow", 10_000, NOW).dosesRemaining == 1)
    }
}

@Suite struct ChoosingContainer {
    let pack = vial("pack", peptideId: "slu-pp-332", strengthMg: 600, container: .pack, mgPerTablet: 10)

    @Test func cases() {
        #expect(pickVialForDose([pack], "slu-pp-332", 10_000, NOW, containerForDose(.tablet, .oral))?.id == "pack")
        #expect(pickVialForDose([pack], "slu-pp-332", 10_000, NOW) == nil)
        let v = vial("v", state: .reconstituted, diluentMl: 2)
        #expect(pickVialForDose([v], "klow", 10_000, NOW, containerForDose(.powder, .subcutaneous))?.id == "v")
        let bottle = vial("b", state: .reconstituted, diluentMl: 5, container: .spray)
        #expect(pickVialForDose([v, bottle], "klow", 1000, NOW, containerForDose(.powder, .intranasal))?.id == "b")
    }
}

@Suite struct GroupOnOrderTests {
    func coming(_ id: String, orderId: String? = nil, peptideId: String = "klow", strengthMg: Double = 80,
                cost: Double? = nil, currency: String? = nil, supplier: String? = nil) -> Vial {
        vial(id, peptideId: peptideId, strengthMg: strengthMg, state: .onOrder, cost: cost, currency: currency, orderId: orderId, supplier: supplier)
    }

    @Test func cases() {
        let one = groupOnOrder([coming("a", orderId: "o1"), coming("b", orderId: "o1"), coming("c", orderId: "o1")])
        #expect(one.count == 1 && one[0].count == 3 && one[0].vials.map(\.id) == ["a", "b", "c"])
        #expect(groupOnOrder([coming("a", orderId: "o1"), coming("b", orderId: "o2")]).map(\.count) == [1, 1])
        let split = groupOnOrder([coming("a", orderId: "o1"), coming("b", orderId: "o1", peptideId: "bpc-157")])
        #expect(split.map(\.peptideId) == ["klow", "bpc-157"])
        #expect(groupOnOrder([coming("a", orderId: "o1", strengthMg: 10), coming("b", orderId: "o1", strengthMg: 5)]).map(\.strengthMg) == [10, 5])
        #expect(groupOnOrder([coming("a"), coming("b")]).map(\.count) == [1, 1])
        #expect(groupOnOrder([vial("s"), vial("o", state: .reconstituted)]).isEmpty)
        let priced = groupOnOrder([coming("a", orderId: "o1", strengthMg: 10, cost: 30, currency: "EUR"),
                                   coming("b", orderId: "o1", strengthMg: 10, cost: 30, currency: "EUR")])
        #expect(priced[0].remainingMcg == 20_000 && priced[0].cost == 60 && priced[0].currency == "EUR")
    }

    @Test func supplier() {
        #expect(groupSealedVials([vial("a", supplier: "Peptide Sciences"), vial("b", supplier: "Peptide Sciences")])[0].supplier == "Peptide Sciences")
        #expect(groupSealedVials([vial("a", supplier: "One"), vial("b", supplier: "Two")])[0].supplier == nil)
        #expect(groupSealedVials([vial("a", supplier: "One"), vial("b")])[0].supplier == nil)
        #expect(groupSealedVials([vial("a")])[0].supplier == nil)
        let g = groupOnOrder([coming("a", orderId: "o1", supplier: "Peptide Sciences"), coming("b", orderId: "o1", supplier: "Peptide Sciences")])
        #expect(g[0].supplier == "Peptide Sciences" && g[0].count == 2)
    }
}

@Suite struct SetVialRemainingTests {
    @Test func setsWhatIsLeft() {
        var d = AppData()
        let id = d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 10, state: .sealed))
        d.reconstituteVial(id, diluentMl: 2, diluent: .bacteriostatic)
        d.setVialRemaining(id, remainingMcg: 4000)
        let v = d.vials[0]
        #expect(v.drawnMcg == 6000 && vialRemainingMcg(v) == 4000 && abs(vialRemainingMl(v) - 0.8) < 1e-9)
        // Never past full or below empty.
        d.setVialRemaining(id, remainingMcg: 50_000)
        #expect(d.vials[0].drawnMcg == 0)
        d.setVialRemaining(id, remainingMcg: -5)
        #expect(vialRemainingMcg(d.vials[0]) == 0)
    }
}
