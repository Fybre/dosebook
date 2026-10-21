import Foundation
import Testing
@testable import BenchCore

// Ports of units, barrel, numberField and converter tests.

private let HGH: Peptide = { var p = Peptide(id: "hgh", name: "HGH", category: .growthHormone); p.iuPerMg = 3; return p }()
private let PLAIN = Peptide(id: "x", name: "X", category: .repair)

@Suite struct UnitsTests {
    @Test func conversion() {
        #expect(mcgToIu(1000, 3) == 3 && mcgToIu(2000, 3) == 6)
        #expect(isClose(iuToMcg(2, 3), 666.667, digits: 3))
        for iu in [0.5, 1, 2, 4, 8] { #expect(isClose(mcgToIu(iuToMcg(iu, 3), 3), iu, digits: 10)) }
        #expect(mcgToIu(1000, 2.6) == 2.6 && iuToMcg(2.6, 2.6) == 1000)
        #expect(mcgToIu(1000, 0).isNaN && mcgToIu(1000, -3).isNaN && iuToMcg(1, 0).isNaN && mcgToIu(.nan, 3).isNaN)
    }

    @Test func iuDosed() {
        #expect(isIuDosed(HGH) && !isIuDosed(PLAIN) && !isIuDosed(nil))
        var zero = PLAIN; zero.iuPerMg = 0
        #expect(!isIuDosed(zero))
    }

    @Test func formatting() {
        #expect(formatDoseWithIu(HGH, 666.667) == "2 IU (0.667 mg)")
        #expect(formatDoseWithIu(HGH, 1000) == "3 IU (1 mg)")
        #expect(formatDoseWithIu(PLAIN, 500) == "500 mcg")
        #expect(formatDoseWithIu(PLAIN, 10_000) == "10 mg")
        #expect(formatDoseWithIu(PLAIN, 2500) == "2.5 mg")
        #expect(formatDoseWithIu(HGH, .nan) == "n/a")
    }

    @Test func solutions() {
        #expect(concentrationFromFill(2500, 10) == 250_000 && strengthFromConcentration(250, 10) == 2500)
        #expect(concentrationFromFill(strengthFromConcentration(200, 10), 10) / 1000 == 200)
        #expect(concentrationFromFill(2500, 0).isNaN && concentrationFromFill(0, 10).isNaN && strengthFromConcentration(0, 10).isNaN)
        var sol = PLAIN; sol.preparation = .solution
        var pow = PLAIN; pow.preparation = .powder
        #expect(isSolution(sol) && !isSolution(pow) && !isSolution(PLAIN) && !isSolution(nil))
    }
}

private let HALF_03 = syringeById("u100-0.3-half")!
private let PLAIN_03 = syringeById("u100-0.3")!
private let HALF_ML = syringeById("u100-0.5")!
private let ONE_ML = syringeById("u100-1.0")!
private let ONE_ML_FINE = syringeById("u100-1.0-fine")!
private let VET_ML = syringeById("u40-1.0")!

private func spacing(_ spec: SyringeSpec, _ width: Double) -> Double {
    let t = barrelTicks(spec, width, allowMagnify: true).ticks
    return width * (t[1].fraction - t[0].fraction)
}

@Suite struct BarrelTests {
    @Test func majorEvery() {
        #expect(majorEveryFor(30) == 5 && majorEveryFor(50) == 5 && majorEveryFor(40) == 5 && majorEveryFor(100) == 10)
    }

    @Test func fullSize() {
        let t = barrelTicks(ONE_ML_FINE, 400).ticks
        #expect(t.count == 101 && t[0].units == 0 && t.last!.units == 100)
        #expect(barrelTicks(ONE_ML_FINE, 400).ticks.count == barrelTicks(ONE_ML, 400).ticks.count * 2 - 1)
        #expect(barrelTicks(VET_ML, 400).ticks.filter(\.major).map(\.units) == [0, 5, 10, 15, 20, 25, 30, 35, 40])
        let half = barrelTicks(HALF_ML, 300).ticks
        #expect(half[0].fraction == 0 && isClose(half.last!.fraction, 1, digits: 12))
        let narrow = barrelTicks(ONE_ML_FINE, 40)
        #expect(!narrow.magnified && narrow.shownUnits == capacityUnits(ONE_ML_FINE))
    }

    @Test func magnifies() {
        let m = barrelTicks(ONE_ML_FINE, 120, allowMagnify: true)
        #expect(m.magnified && m.shownUnits < 100 && Double(m.ticks.count) == m.shownUnits / ONE_ML_FINE.graduationUnits + 1)
        #expect(m.shownUnits.truncatingRemainder(dividingBy: m.majorEvery) == 0)
        for spec in SYRINGES {
            let t = barrelTicks(spec, 120, minSpacingPx: 2.5, allowMagnify: true).ticks
            #expect(120 * (t[1].fraction - t[0].fraction) >= 2.5, "\(spec.id)")
        }
    }

    @Test func finerNeverCoarser() {
        for width in [260.0, 300, 330, 400] {
            #expect(!barrelTicks(ONE_ML_FINE, width, allowMagnify: true).magnified)
            #expect(spacing(HALF_03, width) <= spacing(PLAIN_03, width) + 1e-9)
            #expect(spacing(ONE_ML_FINE, width) <= spacing(ONE_ML, width) + 1e-9)
        }
    }

    @Test func declaresItself() {
        for spec in SYRINGES {
            for width in [60.0, 90, 120, 200, 300, 500] {
                let s = barrelTicks(spec, width, allowMagnify: true)
                #expect(s.magnified == (s.shownUnits < capacityUnits(spec)), "\(spec.id) at \(width)")
            }
            #expect(!barrelTicks(spec, 260, minSpacingPx: 2, allowMagnify: true).magnified, "\(spec.id)")
        }
        #expect(barrelTicks(ONE_ML_FINE, 120, minSpacingPx: 2, allowMagnify: true).magnified)
        #expect(!barrelTicks(HALF_03, 120, minSpacingPx: 2, allowMagnify: true).magnified)
    }
}

@Suite struct NumberFieldTests {
    @Test func cases() {
        #expect(shownValue(nil, 250) == "250" && shownValue(nil, nil) == "")
        #expect(shownValue("", 0) == "")
        #expect(shownValue("250", 250) == "250" && shownValue("0.5", 0.5) == "0.5" && shownValue("2.", 2) == "2.")
        #expect(shownValue("250", 0.25) == "0.25")
        #expect(shownValue("-5", 0) == "0")
        #expect(shownValue("", nil) == "" && shownValue("7", nil) == "")
    }
}

@Suite struct ConverterTests {
    @Test func cases() {
        let url = converterUrl(60, "USD", "EUR")!.absoluteString
        #expect(url.removingPercentEncoding!.contains("60 USD to EUR"))
        #expect(url.contains("60%20USD%20to%20EUR"))
        #expect(converterUrl(200.0 / 3, "USD", "EUR")!.absoluteString.removingPercentEncoding!.contains("66.67 USD"))
        #expect(converterUrl(0, "USD", "EUR") == nil && converterUrl(-5, "USD", "EUR") == nil)
        #expect(converterUrl(60, "EUR", "EUR") == nil && converterUrl(60, "", "EUR") == nil && converterUrl(60, "EUR", "") == nil)
        #expect(url.hasPrefix("https://"))
    }
}

@Suite struct JSSemantics {
    @Test func toFixed() {
        #expect(jsToFixed(2.5, 0) == "3")
        #expect(jsToFixed(0.125, 2) == "0.13")
        #expect(jsToFixed(1.005, 2) == "1.00")
        #expect(jsToFixed(-2.5, 0) == "-3")
        #expect(jsToFixed(0.1 + 0.2, 4) == "0.3000")
        #expect(jsToFixed(9.995, 2) == "9.99")
        #expect(jsToFixed(99.5, 0) == "100")
        #expect(jsNumberString(jsFixed(0.1 + 0.2, 4)) == "0.3")
        #expect(jsNumberString(2) == "2" && jsNumberString(0.25) == "0.25")
    }

    @Test func round() {
        #expect(jsRound(-2.5) == -2 && jsRound(2.5) == 3 && jsRound(-0.4) == 0 && jsRound(1.4999) == 1)
    }
}
