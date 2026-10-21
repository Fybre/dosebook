import Foundation
import Testing
@testable import BenchCore

// Ports of groundtruth.test.ts (hand-worked and closed-form checks across
// modules) and profiles.test.ts.

private let U100 = syringeById("u100-1.0")!
private let U40 = syringeById("u40-1.0")!

@Suite struct GroundTruthReconstitution {
    @Test func byHand() {
        let d = calculateDraw(vialMcg: 5000, diluentMl: 2, doseMcg: 250, syringe: U100)
        #expect(d.concentrationMcgPerMl == 2500 && isClose(d.volumeMl, 0.1, digits: 12) && isClose(d.units, 10, digits: 12))
        #expect(isClose(d.mcgPerGraduation, 50, digits: 12) && isClose(mcgPerUnitOfScale(2500, .u100), 25, digits: 12))
        #expect(d.dosesPerVial == 20 && isClose(d.roundingErrorMcg, 0, digits: 9))
        let b = calculateDraw(vialMcg: 5000, diluentMl: 2, doseMcg: 250, syringe: U40)
        #expect(isClose(b.volumeMl, d.volumeMl, digits: 12) && isClose(b.units, 4, digits: 12) && isClose(d.units / b.units, 2.5, digits: 12))
        #expect(isClose(convertBetweenScales(4, .u40, .u100), 10, digits: 12))
        let e = calculateDraw(vialMcg: 10_000, diluentMl: 1, doseMcg: 500, syringe: U100)
        #expect(isClose(e.units, 5, digits: 12) && isClose(e.mcgPerGraduation, 200, digits: 12) && e.dosesPerVial == 20)
        #expect(isClose(mcgPerUnitOfScale(10_000, .u100), 100, digits: 12))
    }

    @Test func grid() {
        for vialMg in [2.0, 5, 10, 15, 30] {
            for water in [0.5, 1, 2, 3, 5] {
                for dose in [100.0, 250, 500, 1000, 2500] {
                    for s in [U100, U40] {
                        let d = calculateDraw(vialMcg: vialMg * 1000, diluentMl: water, doseMcg: dose, syringe: s)
                        #expect(isClose(d.units, (dose * unitsPerMl(s.scale) * water) / (vialMg * 1000), digits: 9))
                    }
                }
            }
        }
        for conc in [500, 2500, 10_000, 66_666.7] {
            for dose in [50.0, 250, 1000, 5000] {
                for scale in [SyringeScale.u100, .u40] { #expect(isClose(doseFromUnits(unitsFromDose(dose, conc, scale), conc, scale), dose, digits: 6)) }
            }
        }
    }

    @Test func edges() {
        let water = diluentForTargetUnits(5000, 250, 20, .u100)
        #expect(isClose(water, 4, digits: 12) && isClose(calculateDraw(vialMcg: 5000, diluentMl: water, doseMcg: 250, syringe: U100).units, 20, digits: 9))
        let r = calculateDraw(vialMcg: 5000, diluentMl: 2, doseMcg: 260, syringe: U100)
        #expect(r.unitsRounded == 10 && isClose(r.deliveredMcg, 250, digits: 9) && isClose(r.roundingErrorMcg, -10, digits: 9))
        #expect(isClose(r.roundingErrorPercent, (-10.0 / 260) * 100, digits: 9) && r.warnings.contains(.offGraduation))
        let big = calculateDraw(vialMcg: 1000, diluentMl: 5, doseMcg: 900, syringe: U100)
        #expect(isClose(big.volumeMl, 4.5, digits: 12) && big.warnings.contains(.exceedsBarrel) && !big.measurable)
        let zero = calculateDraw(vialMcg: 5000, diluentMl: 0, doseMcg: 250, syringe: U100)
        #expect(zero.concentrationMcgPerMl.isNaN && !zero.measurable)
        #expect(isClose(mcgPerGraduation(2500, U100), 50, digits: 12) && isClose(mcgPerGraduation(2500, U40), 62.5, digits: 12))
        #expect(isClose(mcgPerUnitOfScale(2500, .u40), 62.5, digits: 12) && isClose(mcgPerGraduation(2500, syringeById("u100-1.0-fine")!), 25, digits: 12))
    }
}

@Suite struct GroundTruthPK {
    @Test func closedForms() {
        for hl in [0.5, 4, 12, 108, 720] {
            #expect(isClose(fractionRemaining(hl, hl), 0.5, digits: 12) && isClose(fractionRemaining(2 * hl, hl), 0.25, digits: 12))
            #expect(isClose(fractionRemaining(10 * hl, hl), 1.0 / 1024, digits: 12))
        }
        for hl in [6.0, 108] { for f in [0.9, 0.5, 0.1, 0.03] { #expect(isClose(fractionRemaining(hoursUntilFraction(f, hl), hl), f, digits: 10)) } }
        #expect(isClose(timeToSteadyState(24) / 24, log2(1 / 0.03), digits: 10))
        for (hl, interval) in [(24.0, 24.0), (108, 168), (12, 24), (168, 84)] {
            let ke = eliminationRate(hl)
            var simulated = 0.0
            for k in 0..<4000 { simulated += exp(-ke * Double(k) * interval) }
            #expect(isClose(accumulationRatio(interval, hl), simulated, digits: 8))
        }
        #expect(isClose(accumulationRatio(48, 24), 4.0 / 3, digits: 12))
        for (tmax, hl) in [(1.0, 6.0), (4, 24), (48, 108)] {
            let p = CurveParams(halfLifeHours: hl, tmaxHours: tmax)
            let peak = singleDoseLevel(tmax, p)
            #expect(singleDoseLevel(tmax * 0.8, p) < peak && singleDoseLevel(tmax * 1.2, p) < peak)
            #expect(absorptionRate(tmax, hl) > eliminationRate(hl))
        }
        let p = CurveParams(halfLifeHours: 108, tmaxHours: 48)
        let single = levelAt(0, [DoseEvent(at: -24 * HOUR, amountMcg: 100)], p, 100)
        #expect(isClose(levelAt(0, [DoseEvent(at: -24 * HOUR, amountMcg: 300)], p, 100), single * 3, digits: 10))
        let a = DoseEvent(at: -24 * HOUR, amountMcg: 250), b = DoseEvent(at: -168 * HOUR, amountMcg: 250)
        #expect(isClose(levelAt(0, [a, b], p, 250), levelAt(0, [a], p, 250) + levelAt(0, [b], p, 250), digits: 10))
    }

    @Test func unitsCostClearance() {
        #expect(isClose(iuToMcg(10, 3), 3333.333, digits: 3))
        for iu in [3.0, 1000, 0.5] { for mcg in [100.0, 1000, 5000] { #expect(isClose(iuToMcg(mcgToIu(mcg, iu), iu), mcg, digits: 6)) } }
        #expect(isClose(unitsFromDose(250_000, 250_000, .u100), 100, digits: 9))
        let v10 = vial(strengthMg: 10, cost: 100), v20 = vial(strengthMg: 20, cost: 100)
        #expect(isClose(costPerDose(v10, 250)!, 2.5, digits: 12) && isClose(costPerDose(v10, 1000)!, 10, digits: 12))
        #expect(isClose(costPerDose(v10, 500)!, costPerDose(v20, 1000)!, digits: 12))
        for hl in [24.0, 108, 336] {
            #expect(isClose(hoursToClear(hl) / hl, log2(1 / CLEARED_FRACTION), digits: 12))
            #expect(isClose(fractionRemaining(hoursToClear(hl), hl), CLEARED_FRACTION, digits: 12))
        }
        #expect(isClose(hoursToClear(108), hoursUntilFraction(CLEARED_FRACTION, 108), digits: 10))
    }

    @Test func projection() {
        func proto(_ interval: Double, _ dose: Double = 250_000) -> DoseProtocol {
            makeProtocol(id: "p", peptideId: "testosterone-enanthate", name: "t", startedAt: local(2026, 1, 5, 9), doseMcg: dose,
                         route: .intramuscular, schedule: Schedule(kind: .intervalDays, intervalDays: interval))
        }
        let p = project(proto(7), halfLifeHours: 108, days: 200, steps: 4000)
        let firstPeak = p.series.filter { $0.t <= p.series[0].t + 7 * DAY_MS }.map(\.level).max()!
        #expect(isClose(p.steadyPeak! / firstPeak, accumulationRatio(168, 108), digits: 1))
        let s = project(proto(7), halfLifeHours: 108, days: 220, steps: 6000)
        #expect(s.swing! > 1 && s.swing! < exp(eliminationRate(108) * 168) * 1.2)
        let full = project(proto(7, 250_000), halfLifeHours: 108, days: 90, steps: 900)
        let half = project(proto(7, 125_000), halfLifeHours: 108, days: 90, steps: 900)
        #expect(isClose(half.accumulation!, full.accumulation!, digits: 12) && isClose(half.swing!, full.swing!, digits: 6))
    }
}

@Suite struct ProfilesTests {
    @Test func isolation() {
        let mine = vial("mine"), theirs = vial("theirs").with { $0.profileId = "you" }
        let all = [mine, theirs]
        func forProfile(_ id: String) -> [Vial] { all.filter { $0.profileId == id } }
        #expect(stockFor(forProfile("me"), "klow", 4000, 0).dosesRemaining == 20 && stockFor(forProfile("you"), "klow", 4000, 0).dosesRemaining == 20)
        #expect(stockFor(all, "klow", 4000, 0).dosesRemaining == 40)
        #expect(pickVialForDose(forProfile("me"), "klow", 4000, 0)?.id == "mine" && pickVialForDose(forProfile("you"), "klow", 4000, 0)?.id == "theirs")
        #expect(stockFor(forProfile("nobody"), "klow", 4000, 0).dosesRemaining == 0 && pickVialForDose(forProfile("nobody"), "klow", 4000, 0) == nil)
        #expect(Set(ProfileTone.allCases).count == ProfileTone.allCases.count && ProfileTone.allCases.count >= 6)
    }

    @Test func everyKeyAccountedFor() {
        let all = Set(PROFILE_OWNED_KEYS).union(SHARED_KEYS.keys)
        #expect(all == AppData.knownKeys)
    }

    @Test func removal() {
        var d = AppData()
        for who in ["me", "you"] {
            d.protocols.append(makeProtocol(id: "p-\(who)", profileId: who, startedAt: 0, schedule: Schedule(kind: .daily)))
            d.logs.append(DoseLog(id: "l-\(who)", profileId: who, peptideId: "x", at: 0, doseMcg: 1, route: .subcutaneous))
            d.vials.append(vial("v-\(who)").with { $0.profileId = who })
            d.measurements.append(BodyMeasurement(id: "m-\(who)", profileId: who, at: 0))
            d.labs.append(LabResult(id: "lab-\(who)", profileId: who, at: 0, markerId: "igf1", value: 1))
            d.checkIns.append(CheckIn(id: "c-\(who)", profileId: who, at: 0, ratings: [:]))
            d.orders.append(Order(id: "o-\(who)", profileId: who, placedAt: 0))
            d.diluents.append(DiluentBottle(id: "b-\(who)", profileId: who, kind: .bacteriostatic, volumeMl: 30, state: .sealed))
            d.compoundNotes.append(CompoundNote(id: "n-\(who)", profileId: who, peptideId: "x", text: "t", updatedAt: 0))
        }
        let left = withoutProfile(d, "you")
        #expect(left.protocols.map(\.id) == ["p-me"] && left.logs.map(\.id) == ["l-me"] && left.vials.map(\.id) == ["v-me"])
        #expect(left.measurements.map(\.id) == ["m-me"] && left.labs.map(\.id) == ["lab-me"] && left.checkIns.map(\.id) == ["c-me"])
        #expect(left.orders.map(\.id) == ["o-me"] && left.diluents.map(\.id) == ["b-me"] && left.compoundNotes.map(\.id) == ["n-me"])
        let none = withoutProfile(d, "nobody")
        #expect(none.logs.count == 2 && none.compoundNotes.count == 2)
        #expect(isOrphaned(nil, ["me"]) && isOrphaned("gone", ["me"]) && !isOrphaned("me", ["me", "you"]))
    }

    @Test func strandedRowsAdopted() {
        let json = #"{"version":8,"profiles":[{"id":"me","name":"Me","tone":"mint","createdAt":0}],"activeProfileId":"me","logs":[],"diluents":[{"id":"b1","profileId":"deleted","kind":"bacteriostatic","volumeMl":30,"state":"open"}],"orders":[{"id":"o1","profileId":"deleted","shippingCost":12,"placedAt":0}],"vials":[{"id":"v1","profileId":"deleted","peptideId":"klow","strengthMg":10,"state":"sealed"}]}"#
        let out = try! AppData.load(Data(json.utf8))
        #expect(out.diluents.map(\.profileId) == ["me"] && out.orders.map(\.profileId) == ["me"] && out.vials.map(\.profileId) == ["me"])
        let two = json.replacingOccurrences(of: #""profiles":[{"id":"me","name":"Me","tone":"mint","createdAt":0}]"#,
                                            with: #""profiles":[{"id":"me","name":"Me","tone":"mint","createdAt":0},{"id":"you","name":"You","tone":"sky","createdAt":0}]"#)
            .replacingOccurrences(of: #""profileId":"deleted","kind""#, with: #""profileId":"you","kind""#)
        #expect(try! AppData.load(Data(two.utf8)).diluents[0].profileId == "you")
    }
}
