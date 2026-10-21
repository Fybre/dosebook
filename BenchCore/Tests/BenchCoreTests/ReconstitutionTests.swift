import Foundation
import Testing
@testable import BenchCore

// Port of src/lib/calc/reconstitution.test.ts.

private let U100_1U = syringeById("u100-1.0-fine")!
private let U100_2U = syringeById("u100-1.0")!
private let U100_HALF = syringeById("u100-0.3-half")!
private let U100_05 = syringeById("u100-0.5")!
private let U40_1U = syringeById("u40-1.0")!

@Suite struct UnitConversion {
    @Test func basics() {
        #expect(mgToMcg(2.5) == 2500)
        #expect(mcgToMg(250) == 0.25)
        #expect(isClose(mlPerUnit(.u100), 0.01, digits: 12))
        #expect(isClose(mlPerUnit(.u40), 0.025, digits: 12))
        #expect(mlToUnits(1, .u100) == 100)
        #expect(isClose(mlToUnits(0.1, .u100), 10, digits: 10))
        #expect(isClose(unitsToMl(25, .u100), 0.25, digits: 10))
        #expect(mlToUnits(1, .u40) == 40)
        #expect(unitsToMl(40, .u40) == 1)
        #expect(isClose(unitsToMl(20, .u40), 0.5, digits: 12))
    }
}

@Suite struct TheU40Trap {
    @Test func scales() {
        #expect(isClose(convertBetweenScales(10, .u40, .u100), 25, digits: 10))
        #expect(isClose(convertBetweenScales(25, .u100, .u40), 10, digits: 10))
        #expect(isClose(unitsToMl(20, .u100), 0.2, digits: 12))
        #expect(isClose(unitsToMl(20, .u40), 0.5, digits: 12))
        #expect(isClose(unitsToMl(20, .u40) / unitsToMl(20, .u100), 2.5, digits: 12))
    }

    @Test func sameVolumeDifferentNumber() {
        let a = calculateDraw(vialMcg: mgToMcg(30), diluentMl: 3, doseMcg: mgToMcg(4), syringe: U100_1U)
        let b = calculateDraw(vialMcg: mgToMcg(30), diluentMl: 3, doseMcg: mgToMcg(4), syringe: U40_1U)
        #expect(isClose(a.volumeMl, b.volumeMl, digits: 12))
        #expect(isClose(a.units, 40, digits: 10))
        #expect(isClose(b.units, 16, digits: 10))
        #expect(isClose(capacityUnits(U40_1U), 40, digits: 10))
        #expect(isClose(capacityUnits(U100_1U), 100, digits: 10))
    }
}

@Suite struct SyringeSpecs {
    @Test func specs() {
        let grads = Set(SYRINGES.filter { $0.capacityMl == 1 && $0.scale == .u100 }.map(\.graduationUnits))
        #expect(grads.count > 1)
        #expect(!SYRINGES.contains { $0.capacityMl == 0.4 })
        #expect(isClose(graduationMl(U100_1U), 0.01, digits: 12))
        #expect(isClose(graduationMl(U100_2U), 0.02, digits: 12))
        #expect(isClose(graduationMl(U100_HALF), 0.005, digits: 12))
        #expect(isClose(graduationMl(U40_1U), 0.025, digits: 12))
        #expect(Set(SYRINGES.map(\.id)).count == SYRINGES.count)
    }
}

@Suite struct SyringeForLogTests {
    @Test func cases() {
        #expect(syringeForLog(syringeId: "u100-0.5", syringeScale: .u100, defaultId: "u100-1.0")?.id == "u100-0.5")
        #expect(syringeForLog(syringeId: "u100-0.3", syringeScale: .u100)?.capacityMl == 0.3)
        #expect(syringeForLog(syringeId: "u100-0.5", syringeScale: .u100)?.capacityMl == 0.5)
        #expect(syringeForLog(syringeId: nil, syringeScale: .u100, defaultId: "u100-0.5")?.id == "u100-0.5")
        #expect(syringeForLog(syringeId: nil, syringeScale: .u40, defaultId: "u100-0.5")?.scale == .u40)
        #expect(syringeForLog(syringeId: nil, syringeScale: .u100)?.scale == .u100)
        #expect(syringeForLog(syringeId: nil, syringeScale: .u40, defaultId: "")?.scale == .u40)
        #expect(syringeForLog(syringeId: "u100-9.9", syringeScale: .u100, defaultId: "u100-0.5")?.id == "u100-0.5")
        #expect(syringeForLog(syringeId: nil, syringeScale: nil, defaultId: "u100-0.5") == nil)
    }
}

@Suite struct ConcentrationTests {
    @Test func divides() {
        #expect(concentration(mgToMcg(5), 2) == 2500)
        #expect(concentration(mgToMcg(10), 1) == 10000)
        #expect(concentration(mgToMcg(15), 3) == 5000)
        #expect(concentration(0, 2).isNaN && concentration(5000, 0).isNaN && concentration(-5000, 2).isNaN)
        #expect(isClose(doseVolumeMl(250, 2500), 0.1, digits: 12))
        #expect(isClose(doseVolumeMl(2500, 10000), 0.25, digits: 12))
    }
}

@Suite struct WorkedExamples {
    struct Row: Sendable { var vialMg, waterMl, doseMcg, concMgMl, volumeMl, u100, u40, mcgPerMark, dosesPerVial: Double }
    static let rows: [Row] = [
        Row(vialMg: 5, waterMl: 2, doseMcg: 250, concMgMl: 2.5, volumeMl: 0.1, u100: 10, u40: 4, mcgPerMark: 25, dosesPerVial: 20),
        Row(vialMg: 10, waterMl: 1, doseMcg: 2500, concMgMl: 10, volumeMl: 0.25, u100: 25, u40: 10, mcgPerMark: 100, dosesPerVial: 4),
        Row(vialMg: 15, waterMl: 3, doseMcg: 500, concMgMl: 5, volumeMl: 0.1, u100: 10, u40: 4, mcgPerMark: 50, dosesPerVial: 30),
        Row(vialMg: 10, waterMl: 2, doseMcg: 300, concMgMl: 5, volumeMl: 0.06, u100: 6, u40: 2.4, mcgPerMark: 50, dosesPerVial: 33),
        Row(vialMg: 5, waterMl: 3, doseMcg: 250, concMgMl: 5.0 / 3, volumeMl: 0.15, u100: 15, u40: 6, mcgPerMark: 50.0 / 3, dosesPerVial: 20),
        Row(vialMg: 30, waterMl: 3, doseMcg: 5000, concMgMl: 10, volumeMl: 0.5, u100: 50, u40: 20, mcgPerMark: 100, dosesPerVial: 6),
        Row(vialMg: 2, waterMl: 1, doseMcg: 100, concMgMl: 2, volumeMl: 0.05, u100: 5, u40: 2, mcgPerMark: 20, dosesPerVial: 20),
        Row(vialMg: 5, waterMl: 2, doseMcg: 333, concMgMl: 2.5, volumeMl: 0.1332, u100: 13.32, u40: 5.328, mcgPerMark: 25, dosesPerVial: 15),
    ]

    @Test(arguments: rows) func row(_ r: Row) {
        let u100 = calculateDraw(vialMcg: mgToMcg(r.vialMg), diluentMl: r.waterMl, doseMcg: r.doseMcg, syringe: U100_1U)
        #expect(isClose(u100.concentrationMgPerMl, r.concMgMl, digits: 9))
        #expect(isClose(u100.volumeMl, r.volumeMl, digits: 9))
        #expect(isClose(u100.units, r.u100, digits: 8))
        #expect(isClose(u100.mcgPerGraduation, r.mcgPerMark, digits: 8))
        #expect(u100.dosesPerVial == r.dosesPerVial)
        #expect(isClose(u100.mlPerUnit, 0.01, digits: 12))
        #expect(isClose(u100.units, (r.doseMcg * r.waterMl) / (r.vialMg * 10), digits: 8))
        #expect(isClose(u100.units * u100.mcgPerGraduation, r.doseMcg, digits: 6))
        let u40 = calculateDraw(vialMcg: mgToMcg(r.vialMg), diluentMl: r.waterMl, doseMcg: r.doseMcg, syringe: U40_1U)
        #expect(isClose(u40.units, r.u40, digits: 8))
        #expect(isClose(u40.volumeMl, r.volumeMl, digits: 9))
        #expect(isClose(u40.mlPerUnit, 0.025, digits: 12))
    }
}

@Suite struct GuardRails {
    @Test func exceedsBarrel() {
        let r = calculateDraw(vialMcg: mgToMcg(10), diluentMl: 5, doseMcg: mgToMcg(5), syringe: U100_1U)
        #expect(isClose(r.volumeMl, 2.5, digits: 12) && r.warnings.contains(.exceedsBarrel) && !r.measurable)
        let full = calculateDraw(vialMcg: mgToMcg(5), diluentMl: 1, doseMcg: mgToMcg(5), syringe: U100_1U)
        #expect(isClose(full.volumeMl, 1, digits: 12) && !full.warnings.contains(.exceedsBarrel))
    }

    @Test func belowGraduation() {
        let r = calculateDraw(vialMcg: mgToMcg(10), diluentMl: 1, doseMcg: 50, syringe: U100_1U)
        #expect(isClose(r.volumeMl, 0.005, digits: 12) && r.warnings.contains(.belowGraduation) && !r.measurable)
        let half = calculateDraw(vialMcg: mgToMcg(10), diluentMl: 1, doseMcg: 50, syringe: U100_HALF)
        #expect(!half.warnings.contains(.belowGraduation) && isClose(half.unitsRounded, 0.5, digits: 10) && half.measurable)
    }

    @Test func offGraduation() {
        let r = calculateDraw(vialMcg: mgToMcg(5), diluentMl: 2, doseMcg: 333, syringe: U100_1U)
        #expect(isClose(r.units, 13.32, digits: 8) && r.warnings.contains(.offGraduation))
        #expect(isClose(r.unitsRounded, 13, digits: 10) && isClose(r.deliveredMcg, 325, digits: 6))
        #expect(isClose(r.roundingErrorMcg, -8, digits: 6) && isClose(r.roundingErrorPercent, -2.402, digits: 2))
    }

    @Test func lowVolumeAndQuiet() {
        let r = calculateDraw(vialMcg: mgToMcg(10), diluentMl: 1, doseMcg: 200, syringe: U100_1U)
        #expect(isClose(r.units, 2, digits: 10) && r.warnings.contains(.lowVolume))
        let ok = calculateDraw(vialMcg: mgToMcg(5), diluentMl: 2, doseMcg: 250, syringe: U100_1U)
        #expect(ok.warnings.isEmpty && ok.measurable)
    }

    @Test func twoUnitMarks() {
        let r = calculateDraw(vialMcg: mgToMcg(10), diluentMl: 2, doseMcg: 1250, syringe: U100_2U)
        #expect(isClose(r.units, 25, digits: 10) && isClose(r.unitsRounded, 26, digits: 10))
        #expect(r.warnings.contains(.offGraduation) && isClose(r.deliveredMcg, 1300, digits: 6))
    }

    @Test func u40Spacing() {
        let exact = calculateDraw(vialMcg: mgToMcg(10), diluentMl: 1, doseMcg: 1000, syringe: U40_1U)
        #expect(isClose(exact.unitsRounded, 4, digits: 10) && !exact.warnings.contains(.offGraduation))
        let off = calculateDraw(vialMcg: mgToMcg(10), diluentMl: 1, doseMcg: 1100, syringe: U40_1U)
        #expect(isClose(off.unitsRounded, 4, digits: 10) && isClose(off.deliveredMcg, 1000, digits: 6) && off.warnings.contains(.offGraduation))
    }

    @Test func exceedsVial() {
        #expect(calculateDraw(vialMcg: mgToMcg(5), diluentMl: 0.3, doseMcg: mgToMcg(6), syringe: U100_1U).warnings.contains(.exceedsVial))
    }
}

@Suite struct DiluentInverse {
    @Test func targetUnits() {
        let ml = diluentForTargetUnits(mgToMcg(5), 250, 10, .u100)
        #expect(isClose(ml, 2, digits: 12))
        #expect(isClose(calculateDraw(vialMcg: mgToMcg(5), diluentMl: ml, doseMcg: 250, syringe: U100_1U).units, 10, digits: 10))
        let cases: [(Double, Double, Double, SyringeScale, SyringeSpec)] = [
            (10, 500, 20, .u100, U100_1U), (15, 2000, 30, .u100, U100_1U), (2, 100, 5, .u100, U100_1U),
            (50, 5000, 20, .u40, U40_1U), (30, 4000, 16, .u40, U40_1U),
        ]
        for (vialMg, dose, target, scale, spec) in cases {
            let ml = diluentForTargetUnits(mgToMcg(vialMg), dose, target, scale)
            #expect(isClose(calculateDraw(vialMcg: mgToMcg(vialMg), diluentMl: ml, doseMcg: dose, syringe: spec).units, target, digits: 9))
        }
        #expect(diluentForTargetUnits(0, 250, 10, .u100).isNaN)
        #expect(diluentForTargetUnits(mgToMcg(5), 0, 10, .u100).isNaN)
    }

    @Test func mcgPerUnit() {
        let ml = diluentForMcgPerUnit(mgToMcg(5), 25, U100_1U)
        #expect(isClose(ml, 2, digits: 12))
        #expect(isClose(calculateDraw(vialMcg: mgToMcg(5), diluentMl: ml, doseMcg: 250, syringe: U100_1U).mcgPerGraduation, 25, digits: 9))
        #expect(isClose(diluentForMcgPerUnit(mgToMcg(10), 50, U40_1U) / diluentForMcgPerUnit(mgToMcg(10), 50, U100_1U), 2.5, digits: 10))
    }
}

@Suite struct SuggestDiluentsTests {
    @Test func ranking() {
        let s = suggestDiluents(mgToMcg(5), 250, U100_1U)
        #expect(!s.isEmpty && s[0].landsOnMark && s[0].units >= 5)
        for c in suggestDiluents(mgToMcg(5), mgToMcg(2), U100_05) { #expect(c.volumeMl <= U100_05.capacityMl + 1e-9) }
        for c in suggestDiluents(mgToMcg(10), 750, U100_2U) where c.landsOnMark {
            let marks = c.volumeMl / graduationMl(U100_2U)
            #expect(abs(marks - jsRound(marks)) < 1e-9)
        }
        let u40 = suggestDiluents(mgToMcg(10), 1000, U40_1U)
        #expect(!u40.isEmpty && u40.allSatisfy { $0.volumeMl <= U40_1U.capacityMl + 1e-9 })
        #expect(suggestDiluents(0, 250, U100_1U).isEmpty)
        #expect(suggestDiluents(mgToMcg(5), 0, U100_1U).isEmpty)
        #expect(suggestDiluents(mgToMcg(5), mgToMcg(5), U100_HALF).isEmpty)
    }
}

@Suite struct RemainingAndBUD {
    @Test func remaining() {
        let r = remainingInVial(mgToMcg(10), 2, 0.5)
        #expect(isClose(r.remainingMl, 1.5, digits: 12) && isClose(r.remainingMcg, 7500, digits: 9) && isClose(r.fractionRemaining, 0.75, digits: 12))
        let over = remainingInVial(mgToMcg(10), 2, 3)
        #expect(over.remainingMl == 0 && over.remainingMcg == 0)
        let sealed = remainingInVial(mgToMcg(10), 0, 0)
        #expect(sealed.remainingMcg == 0 && sealed.fractionRemaining == 0)
    }

    @Test func bud() {
        let punctured: Millis = 1_767_225_600_000 // Date.UTC(2026, 0, 1)
        #expect(beyondUseDate(punctured) == punctured + 28 * DAY_MS)
        #expect(beyondUseDate(punctured, days: 14) == punctured + 14 * DAY_MS)
    }
}

@Suite struct TwoWayConversion {
    let conc = concentration(mgToMcg(10), 2)

    @Test func both() {
        #expect(isClose(doseFromUnits(10, conc, .u100), 500, digits: 9))
        #expect(isClose(doseFromUnits(10, conc, .u40), 1250, digits: 9))
        #expect(isClose(unitsFromDose(500, conc, .u100), 10, digits: 9))
        #expect(isClose(unitsFromDose(500, conc, .u40), 4, digits: 9))
        for mcg in [50.0, 250, 500, 1000, 2500] {
            for scale in [SyringeScale.u100, .u40] {
                #expect(isClose(doseFromUnits(unitsFromDose(mcg, conc, scale), conc, scale), mcg, digits: 6))
            }
        }
        let r = calculateDraw(vialMcg: mgToMcg(10), diluentMl: 2, doseMcg: 500, syringe: syringeById("u100-1.0-fine")!)
        #expect(isClose(unitsFromDose(500, conc, .u100), r.units, digits: 9))
        #expect(isClose(doseFromUnits(20, conc, .u40) / doseFromUnits(20, conc, .u100), 2.5, digits: 10))
        #expect(doseFromUnits(0, conc, .u100) == 0 && doseFromUnits(-5, conc, .u100) == 0)
        #expect(doseFromUnits(10, .nan, .u100) == 0 && unitsFromDose(500, 0, .u100) == 0)
    }
}
