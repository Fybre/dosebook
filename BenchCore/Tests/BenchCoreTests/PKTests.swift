import Foundation
import Testing
@testable import BenchCore

// Port of src/lib/calc/pk.test.ts.

private func P(_ h: Double, _ t: Double? = nil) -> CurveParams { CurveParams(halfLifeHours: h, tmaxHours: t) }
private func D(_ at: Millis, _ mcg: Double, _ vial: String? = nil) -> DoseEvent { DoseEvent(at: at, amountMcg: mcg, vialId: vial) }
private let now: Millis = 1_768_046_400_000 // Date.UTC(2026, 0, 10, 12)

@Suite struct PKHalfLife {
    @Test func arithmetic() {
        #expect(fractionRemaining(0, 24) == 1)
        #expect(isClose(fractionRemaining(24, 24), 0.5, digits: 12) && isClose(fractionRemaining(48, 24), 0.25, digits: 12))
        #expect(isClose(fractionRemaining(120, 24), 0.03125, digits: 12))
        #expect(isClose(exp(-eliminationRate(6) * 6), 0.5, digits: 12))
        #expect(isClose(hoursUntilFraction(0.5, 24), 24, digits: 10) && isClose(hoursUntilFraction(0.25, 24), 48, digits: 10))
        #expect(isClose(fractionRemaining(hoursUntilFraction(0.1, 165), 165), 0.1, digits: 10))
    }

    @Test func absorption() {
        for (tmax, hl) in [(4.0, 24.0), (24, 120), (48, 165), (0.5, 2)] {
            let ka = absorptionRate(tmax, hl), ke = eliminationRate(hl)
            #expect(isClose(log(ka / ke) / (ka - ke), tmax, digits: 6))
        }
        #expect(absorptionRate(10, 12) > eliminationRate(12))
        let ka = absorptionRate(5 / eliminationRate(4), 4)
        #expect(ka.isFinite && ka > eliminationRate(4))
    }
}

@Suite struct PKSingleDose {
    @Test func shape() {
        #expect(singleDoseLevel(-1, P(24, 4)) == 0)
        #expect(isClose(singleDoseLevel(0, P(165, 48)), 0, digits: 10) && isClose(singleDoseLevel(48, P(165, 48)), 1, digits: 6))
        var t = 0.0
        while t <= 600 { #expect(singleDoseLevel(t, P(120, 24)) <= 1 + 1e-9); t += 0.5 }
        t = 0.5
        while t <= 12 { #expect(singleDoseLevel(t, P(72, 12)) > singleDoseLevel(t - 0.5, P(72, 12))); t += 0.5 }
        t = 12.5
        while t <= 200 { #expect(singleDoseLevel(t, P(72, 12)) < singleDoseLevel(t - 0.5, P(72, 12))); t += 0.5 }
        #expect(isClose(singleDoseLevel(124, P(24, 2)) / singleDoseLevel(100, P(24, 2)), 0.5, digits: 4))
        #expect(isClose(singleDoseLevel(0, P(10)), 1, digits: 12) && isClose(singleDoseLevel(10, P(10)), 0.5, digits: 12))
        #expect(isClose(singleDoseLevel(20, P(10)), 0.25, digits: 12) && singleDoseLevel(5, P(0)) == 0)
    }
}

@Suite struct PKLevelAt {
    let params = P(24, 4)

    @Test func superposition() {
        #expect(levelAt(now, [D(now + 5 * HOUR, 1000)], params, 1000) == 0)
        let single = levelAt(now, [D(now - 4 * HOUR, 1000)], params, 1000)
        #expect(isClose(levelAt(now, [D(now - 4 * HOUR, 2000)], params, 1000), single * 2, digits: 10))
        #expect(isClose(levelAt(now, [D(now - 4 * HOUR, 500)], params, 500), 1, digits: 6))
        let doses = [D(now - 4 * HOUR, 1000), D(now - 28 * HOUR, 1000)]
        let combined = levelAt(now, doses, params, 1000)
        #expect(isClose(combined, levelAt(now, [doses[0]], params, 1000) + levelAt(now, [doses[1]], params, 1000), digits: 10))
        #expect(combined > levelAt(now, [doses[0]], params, 1000))
        #expect(levelAt(now, [D(now - 400 * HOUR, 1000)], params, 1000) == 0)
        #expect(levelAt(now, [D(now - HOUR, 100)], params, 0) == 0)
    }

    @Test func accumulates() {
        let doses = (0..<40).map { D(now - Double(39 - $0) * 168 * HOUR, 1000) }
        let steady = levelAt(now + 48 * HOUR, doses, P(165, 48), 1000)
        let expected = accumulationRatio(168, 165)
        #expect(steady > expected * 0.92 && steady < expected * 1.08)
    }

    @Test func ratios() {
        #expect(isClose(accumulationRatio(24, 24), 2, digits: 12) && isClose(accumulationRatio(240, 6), 1, digits: 6))
        #expect(accumulationRatio(24, 165) > accumulationRatio(168, 165))
        #expect(isClose(timeToSteadyState(24, fraction: 0.97) / 24, 5.06, digits: 1))
        #expect(isClose(timeToSteadyState(10, fraction: 0.9375), 40, digits: 8))
    }

    @Test func series() {
        let s = levelSeries(now, now + 24 * HOUR, 5, [], P(12), 1000)
        #expect(s.count == 5 && s[0].t == now && s[4].t == now + 24 * HOUR)
        #expect(levelSeries(now, now - HOUR, 10, [], P(12), 1000).isEmpty && levelSeries(now, now + HOUR, 1, [], P(12), 1000).isEmpty)
    }

    @Test func snapshots() {
        let p = P(24, 6)
        let up = snapshot(now, [D(now - 2 * HOUR, 1000)], p, 1000)
        #expect(up.rising && up.phase == .absorbing)
        let peak = snapshot(now, [D(now - 6 * HOUR, 1000)], p, 1000)
        #expect(peak.phase == .peak && peak.percentOfPeak > 99)
        let active = snapshot(now, [D(now - 20 * HOUR, 1000)], p, 1000)
        #expect(!active.rising && active.phase == .active)
        #expect(snapshot(now, [D(now - 200 * HOUR, 1000)], p, 1000).phase == .cleared)
        #expect(snapshot(now, [], p, 1000).phase == .cleared)
        let mid = snapshot(now, [D(now - 10 * HOUR, 1000)], p, 1000)
        #expect(isClose(mid.percentOfPeak, mid.level * 100, digits: 10))
    }
}

@Suite struct PKCache {
    @Test func caching() {
        let p = P(108, 48)
        let first = (0..<50).map { singleDoseLevel(Double($0 * 4), p) }
        #expect((0..<50).map { singleDoseLevel(Double($0 * 4), p) } == first)
        let fast = singleDoseLevel(6, P(6, 1)), slow = singleDoseLevel(6, P(108, 48))
        #expect(!isClose(fast, slow, digits: 3) && singleDoseLevel(6, P(6, 1)) == fast)
        #expect(!isClose(singleDoseLevel(4, P(24, 2)), singleDoseLevel(4, P(24, 12)), digits: 6))
        let without = singleDoseLevel(10, P(24))
        #expect(!isClose(singleDoseLevel(10, P(24, 4)), without, digits: 6) && isClose(without, pow(2, -10.0 / 24), digits: 12))
        for (tmax, hl) in [(2.0, 12.0), (48, 108)] {
            let atPeak = singleDoseLevel(tmax, P(hl, tmax))
            #expect(singleDoseLevel(tmax * 0.85, P(hl, tmax)) < atPeak && singleDoseLevel(tmax * 1.15, P(hl, tmax)) < atPeak)
            #expect(isClose(atPeak, 1, digits: 6))
        }
        let before = singleDoseLevel(72, p)
        for i in 0..<400 { _ = singleDoseLevel(10, P(10 + Double(i) * 0.5, 3)) }
        #expect(singleDoseLevel(72, p) == before)
    }
}

@Suite struct PKBreakdown {
    let params = P(24, 2)
    let t0: Millis = 1_700_000_000_000

    @Test func cases() {
        let three = [D(t0, 1000), D(t0 + 24 * HOUR, 1000), D(t0 + 48 * HOUR, 1000)]
        #expect(isClose(breakdownAt(t0 + 50 * HOUR, three, params, 1000).total, levelAt(t0 + 50 * HOUR, three, params, 1000), digits: 12))
        let c = breakdownAt(t0 + 26 * HOUR, [D(t0, 1000), D(t0 + 24 * HOUR, 1000)], params, 1000).contributions
        #expect(c.count == 2 && c[0].dose.at == t0 + 24 * HOUR && c[0].level > c[1].level)
        let lone = breakdownAt(t0 + 6 * HOUR, [D(t0, 500)], params, 500).contributions
        #expect(lone.count == 1 && isClose(lone[0].share, 1, digits: 12))
        let tail = [D(t0, 1000), D(t0 + 120 * HOUR, 1000)]
        let b = breakdownAt(t0 + 122 * HOUR, tail, params, 1000)
        #expect(b.contributions.count == 1 && b.contributions.reduce(0) { $0 + $1.level } < b.total)
        #expect(isClose(b.total, levelAt(t0 + 122 * HOUR, tail, params, 1000), digits: 12))
        #expect(breakdownAt(t0, [D(t0 + HOUR, 1000)], params, 1000) == LevelBreakdown(total: 0, contributions: []))
        #expect(breakdownAt(t0 + 3 * HOUR, [D(t0, 1000, "v1")], params, 1000).contributions[0].dose.vialId == "v1")
        #expect(breakdownAt(t0 + HOUR, [D(t0, 1000)], params, 0) == LevelBreakdown(total: 0, contributions: []))
    }
}

@Suite struct CurveForTests {
    @Test func preference() {
        #expect(curveFor(halfLifeHours: 12, tmaxHours: 2, estimateHours: 4, yours: 99) == Curve(params: P(12, 2), basis: .published))
        #expect(curveFor(halfLifeHours: nil, tmaxHours: nil, estimateHours: 4, yours: 2) == Curve(params: P(2), basis: .yours))
        #expect(curveFor(halfLifeHours: nil, tmaxHours: 1, estimateHours: 4, yours: nil) == Curve(params: P(4, 1), basis: .elsewhere))
        let y = curveFor(halfLifeHours: nil, tmaxHours: nil, estimateHours: nil, yours: 1.5)
        #expect(y?.basis == .yours && y?.params.halfLifeHours == 1.5)
        #expect(curveFor(halfLifeHours: nil, tmaxHours: nil, estimateHours: nil, yours: 0) == nil)
        #expect(curveFor(halfLifeHours: nil, tmaxHours: nil, estimateHours: nil, yours: -3) == nil)
        #expect(curveFor(halfLifeHours: nil, tmaxHours: nil, estimateHours: nil, yours: nil) == nil)
        #expect(isMeasuredInPeople(.published) && !isMeasuredInPeople(.yours) && !isMeasuredInPeople(.elsewhere))
    }
}
