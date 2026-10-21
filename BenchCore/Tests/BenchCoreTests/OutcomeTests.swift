import Foundation
import Testing
@testable import BenchCore

// Ports of outcomes, labs, checkins and feeling tests.

private let NOW: Millis = 1_785_326_400_000 // Date.UTC(2026, 6, 29, 12)
private func m(_ daysAgo: Double, _ kg: Double? = nil, at: Millis? = nil, id: String? = nil) -> BodyMeasurement {
    BodyMeasurement(id: id ?? "m\(daysAgo)", profileId: "me", at: at ?? NOW - daysAgo * DAY_MS, weightKg: kg)
}
private func ol(_ at: Millis, feeling: Int? = nil, effects: [String]? = nil, skipped: Bool? = nil) -> DoseLog {
    DoseLog(id: UUID().uuidString, profileId: "me", peptideId: "x", at: at, doseMcg: 1, route: .subcutaneous,
            skipped: skipped, feeling: feeling, sideEffects: effects)
}

@Suite struct OutcomesTests {
    @Test func weight() {
        #expect(isClose(lbToKg(220.462), 100, digits: 3) && isClose(kgToLb(100), 220.462, digits: 3) && isClose(kgToLb(lbToKg(180)), 180, digits: 9))
        #expect(weightSeries([m(1, 90), m(10, 94), m(5, 92)]).map(\.kg) == [94, 92, 90])
        #expect(weightSeries([m(1), m(2, 90), m(3, 0)]).count == 1 && weightSeries([]).isEmpty)
        #expect(weightChange([]) == nil && weightChange([m(1, 90)]) == nil)
        let c = weightChange([m(28, 100), m(0, 94)])!
        #expect(isClose(c.deltaKg, -6, digits: 9) && isClose(c.deltaPercent, -6, digits: 9) && isClose(c.days, 28, digits: 6))
        #expect(isClose(weightChange([m(14, 80), m(0, 82)])!.deltaKg, 2, digits: 9))
        #expect(isClose(c.perWeekKg!, -1.5, digits: 6))
        let ex = weightChange([m(28, 100), m(14, 90), m(0, 96)])!
        #expect(ex.first.kg == 100 && ex.latest.kg == 96 && isClose(ex.deltaKg, -4, digits: 9))
        let all = [m(60, 110), m(28, 100), m(0, 94)]
        #expect(isClose(weightChange(all)!.deltaKg, -16, digits: 9) && isClose(weightChange(all, since: NOW - 30 * DAY_MS)!.deltaKg, -6, digits: 9))
        #expect(weightChange([m(0, 90), m(0, 89, at: NOW + 1000, id: "x")])!.perWeekKg == nil)
        #expect(latestWeightKg([m(10, 94), m(1, 90), m(5, 92)]) == 90 && latestWeightKg([]) == nil)
        #expect(toDisplayWeight(82.5, .kg) == 82.5 && fromDisplayWeight(82.5, .kg) == 82.5)
        #expect(isClose(toDisplayWeight(100, .lb), 220.462, digits: 3) && isClose(fromDisplayWeight(220.462, .lb), 100, digits: 3))
        for kg in [0, 0.5, 45, 82.3, 150] {
            #expect(isClose(fromDisplayWeight(toDisplayWeight(kg, .lb), .lb), kg, digits: 9) && fromDisplayWeight(toDisplayWeight(kg, .kg), .kg) == kg)
        }
        #expect(toDisplayWeight(70, .lb) == kgToLb(70) && fromDisplayWeight(154, .lb) == lbToKg(154))
    }

    @Test func effects() {
        let logs = [ol(NOW - DAY_MS, effects: ["Nausea", "Fatigue"]), ol(NOW - 2 * DAY_MS, effects: ["Nausea"]),
                    ol(NOW - 3 * DAY_MS, effects: []), ol(NOW - 4 * DAY_MS, effects: ["Nausea", "Headache"])]
        let t = sideEffectTally(logs)
        #expect(t.total == 4 && t.effects[0].effect == "Nausea" && t.effects[0].count == 3 && isClose(t.effects[0].rate, 0.75, digits: 9))
        let counts = t.effects.map(\.count)
        #expect(counts == counts.sorted(by: >))
        let withSkip = sideEffectTally(logs + [ol(NOW - 5 * DAY_MS, effects: ["Nausea"], skipped: true)])
        #expect(withSkip.total == 4 && withSkip.effects[0].count == 3)
        let none = sideEffectTally([ol(NOW), ol(NOW)])
        #expect(none.total == 2 && none.effects.isEmpty)
        #expect(averageFeeling([ol(NOW, feeling: 4), ol(NOW, feeling: 2), ol(NOW)]) == 3)
        #expect(averageFeeling([ol(NOW), ol(NOW)]) == nil)
        #expect(averageFeeling([ol(NOW, feeling: 5), ol(NOW, feeling: 1, skipped: true)]) == 5)
    }

    @Test func tolerance() {
        let steps = [TitrationStep(step: 1, doseMcg: 2000, weeks: 4), TitrationStep(step: 2, doseMcg: 4000, weeks: 4), TitrationStep(step: 3, doseMcg: 8000, weeks: 4)]
        let startedAt = NOW - 70 * DAY_MS
        func at(_ w: Double) -> Millis { startedAt + w * 7 * DAY_MS }
        let logs = [ol(at(1), feeling: 4, effects: []), ol(at(2), feeling: 5, effects: []), ol(at(5), feeling: 3, effects: ["Nausea"]),
                    ol(at(6), feeling: 3, effects: []), ol(at(9), feeling: 2, effects: ["Nausea", "Fatigue"]), ol(at(10), feeling: 1, effects: ["Nausea"])]
        let rows = toleranceByStep(logs, steps, startedAt)
        #expect(rows.map(\.stepIndex) == [0, 1, 2] && rows.map(\.doses) == [2, 2, 2] && rows.map(\.doseMcg) == [2000, 4000, 8000])
        #expect(rows[0].averageFeeling == 4.5 && rows[1].averageFeeling == 3 && rows[2].averageFeeling == 1.5)
        #expect(rows[0].sideEffectRate == 0 && rows[1].sideEffectRate == 0.5 && rows[2].sideEffectRate == 1)
        #expect(rows[2].topEffects[0].effect == "Nausea" && rows[2].topEffects[0].count == 2)
        #expect(toleranceByStep([ol(at(1), feeling: 4)], steps, startedAt).map(\.stepIndex) == [0])
        #expect(toleranceByStep(logs, [], startedAt).isEmpty)
        #expect(toleranceByStep([ol(startedAt - 10 * DAY_MS, feeling: 5)], steps, startedAt).isEmpty)
        let unrated = toleranceByStep([ol(at(1), effects: ["Nausea"])], steps, startedAt)
        #expect(unrated[0].averageFeeling == nil && unrated[0].sideEffectRate == 1)
    }
}

private let LNOW: Millis = 1_785_398_400_000 // Date.UTC(2026, 6, 30, 8)
private func res(_ id: String, _ markerId: String, _ value: Double, refLow: Double? = nil, refHigh: Double? = nil, at: Millis = LNOW) -> LabResult {
    LabResult(id: id, profileId: "me", at: at, markerId: markerId, value: value, refLow: refLow, refHigh: refHigh)
}
private func marker(_ id: String) -> LabMarker? { Library.marker(id) }

@Suite struct LabsTests {
    @Test func catalogue() {
        let ids = Library.labMarkers.map(\.id)
        #expect(Set(ids).count == ids.count)
        for mk in Library.labMarkers {
            if mk.guideline == nil { #expect(!(mk.rangeNote ?? "").isEmpty, "\(mk.id) needs a rangeNote") }
            if let g = mk.guideline {
                #expect(!g.source.isEmpty)
                for i in 0...4000 {
                    let v = Double(i) / 10
                    #expect(g.bands.filter { inBand($0, v) }.count == 1, "\(mk.id) at \(v)")
                }
            }
        }
    }

    @Test func ownRange() {
        let v = verdictFor(marker("igf1"), res("a", "igf1", 180, refLow: 80, refHigh: 250))
        #expect(v.status == .inRange && v.basis == "your lab's range")
        #expect(verdictFor(marker("igf1"), res("a", "igf1", 300, refLow: 80, refHigh: 250)).status == .above)
        #expect(verdictFor(marker("igf1"), res("b", "igf1", 40, refLow: 80, refHigh: 250)).status == .below)
        #expect(verdictFor(marker("triglycerides"), res("a", "triglycerides", 90, refHigh: 150)).status == .inRange)
        #expect(verdictFor(marker("triglycerides"), res("b", "triglycerides", 200, refHigh: 150)).status == .above)
        #expect(marker("hdl")?.higherIsBetter == true)
        #expect(verdictFor(marker("hdl"), res("a", "hdl", 30, refLow: 40)).tone == .rose)
        #expect(verdictFor(marker("hdl"), res("b", "hdl", 95, refHigh: 90)).tone == .tangerine)
        let both = verdictFor(marker("hba1c"), res("a", "hba1c", 6.0, refLow: 4, refHigh: 6.2))
        #expect(both.status == .inRange && both.basis == "your lab's range")
    }

    @Test func guidelines() {
        func at(_ id: String, _ v: Double) -> LabVerdict { verdictFor(marker(id), res("x", id, v)) }
        #expect(at("hba1c", 5.2).label == "Normal" && at("hba1c", 5.7).label == "Prediabetes range")
        #expect(at("hba1c", 6.4).label == "Prediabetes range" && at("hba1c", 6.5).label == "Diabetes range")
        #expect(at("hba1c", 5.2).basis == "ADA diagnostic criteria")
        #expect(at("glucose-fasting", 88).label == "Normal" && at("glucose-fasting", 100).label == "Prediabetes range" && at("glucose-fasting", 126).label == "Diabetes range")
        #expect(at("bp-systolic", 115).label == "Normal" && at("bp-systolic", 124).label == "Elevated")
        #expect(at("bp-systolic", 135).label == "Stage 1 hypertension" && at("bp-systolic", 150).label == "Stage 2 hypertension")
        let unknown = at("igf1", 180)
        #expect(unknown.status == .unknown && unknown.basis == nil)
        #expect(verdictFor(nil, res("a", "nope", 1)).status == .unknown)
        #expect(verdictFor(marker("hba1c"), res("a", "hba1c", .nan)).status == .unknown)
    }

    @Test func series() {
        let labs = [res("c", "hba1c", 5.4), res("a", "hba1c", 6.8, at: LNOW - 180 * DAY_MS), res("b", "hba1c", 6.0, at: LNOW - 90 * DAY_MS), res("d", "ldl", 120)]
        #expect(labSeries(labs, "hba1c").map(\.id) == ["a", "b", "c"] && labSeries(labs, "ldl").count == 1)
        let t = labTrend(labs, "hba1c")!
        #expect(t.first.value == 6.8 && t.latest.value == 5.4 && isClose(t.delta, -1.4, digits: 10))
        #expect(isClose(t.percent!, (-1.4 / 6.8) * 100, digits: 8) && isClose(t.days, 180, digits: 6))
        #expect(labTrend(labs, "ldl") == nil && labTrend([], "hba1c") == nil)
        #expect(labTrend([res("a", "hba1c", 0, at: LNOW - DAY_MS), res("b", "hba1c", 5)], "hba1c")!.percent == nil)
        #expect(latestResult(labs, "hba1c")?.id == "c" && latestResult(labs, "tsh") == nil)
        #expect(trackedMarkerIds(labs) == ["hba1c", "ldl"])
    }

    @Test func suggestions() {
        let glp = suggestedMarkerIds([LabCompoundTraits(category: "metabolic", mechanismClass: ["glp1-agonist"])])
        #expect(glp.contains("lipase") && glp.contains("resting-hr") && glp.contains("hba1c"))
        let gh = suggestedMarkerIds([LabCompoundTraits(category: "growth-hormone")])
        #expect(gh.contains("igf1") && gh.contains("glucose-fasting") && !gh.contains("lipase"))
        let ana = suggestedMarkerIds([LabCompoundTraits(category: "anabolic")])
        #expect(ana.contains("haematocrit") && ana.contains("hdl") && ana.contains("bp-systolic") && !ana.contains("alt"))
        let oral = suggestedMarkerIds([LabCompoundTraits(category: "anabolic", c17AlphaAlkylated: true)])
        #expect(oral.contains("alt") && oral.contains("ast"))
        #expect(suggestedMarkerIds([LabCompoundTraits(category: "repair")]).isEmpty)
        let two = suggestedMarkerIds([LabCompoundTraits(category: "metabolic", mechanismClass: ["glp1-agonist"]),
                                      LabCompoundTraits(category: "metabolic", mechanismClass: ["glp1-agonist", "gip-agonist"])])
        #expect(Set(two).count == two.count)
        for id in suggestedMarkerIds([LabCompoundTraits(category: "metabolic", mechanismClass: ["glp1-agonist", "gip-agonist"]),
                                      LabCompoundTraits(category: "growth-hormone", mechanismClass: ["ghrh-analogue"])]) {
            #expect(marker(id) != nil, "\(id)")
        }
        let missing = missingMarkerIds([res("a", "hba1c", 5.4)], [LabCompoundTraits(category: "metabolic", mechanismClass: ["glp1-agonist"])])
        #expect(!missing.contains("hba1c") && missing.contains("lipase"))
    }
}

@Suite struct CheckInTests {
    let NOW = local(2026, 7, 30, 14, 30)
    var TODAY: Millis { startOfLocalDay(NOW) }
    func at(_ d: Double) -> Millis { addLocalDays(TODAY, -d) }
    func ci(_ d: Double, _ ratings: [String: Double]) -> CheckIn { CheckIn(id: "c\(jsNumberString(d))", profileId: "me", at: at(d), ratings: ratings) }

    @Test func averagesAndWindows() {
        let rows = averages([ci(0, ["energy": 4, "mood": 5]), ci(1, ["energy": 2, "mood": 3])])
        #expect(rows.first { $0.id == .energy }!.mean == 3 && rows.first { $0.id == .energy }!.days == 2)
        let lib = averages([ci(0, ["energy": 4])]).first { $0.id == .libido }!
        #expect(lib.mean == nil && lib.days == 0)
        let mixed = averages([ci(0, ["energy": 4, "sleep": 2]), ci(1, ["energy": 2]), ci(2, [:])])
        #expect(mixed.first { $0.id == .energy }!.days == 2 && mixed.first { $0.id == .sleep }!.days == 1)
        #expect(averages([]).count == SYMPTOMS.count && averages([]).allSatisfy { $0.mean == nil })
        #expect(averages([]).first { $0.id == .energy }!.higherIsBetter == true && averages([]).first { $0.id == .appetite }!.higherIsBetter == nil)
        let w = inWindow([ci(0, ["energy": 1]), ci(1, ["energy": 2]), ci(2, ["energy": 3])], at(2), at(0))
        #expect(w.compactMap { $0.ratings["energy"] }.sorted() == [2, 3])
    }

    @Test func shifts() {
        let before = [5, 6, 7, 8, 9].map { ci(Double($0), ["energy": 2, "appetite": 4]) }
        let after = [0, 1, 2, 3].map { ci(Double($0), ["energy": 4, "appetite": 2]) }
        let rows = shiftAround(before + after, at(4), nowMs: NOW)
        let e = rows.first { $0.id == .energy }!
        #expect(e.before == 2 && e.after == 4 && e.delta == 2 && e.daysBefore == 5 && e.daysAfter == 4)
        let a = rows.first { $0.id == .appetite }!
        #expect(a.delta == -2 && a.higherIsBetter == nil)
        let one = shiftAround(after, at(4), nowMs: NOW).first { $0.id == .energy }!
        #expect(one.before == nil && one.delta == nil)
        #expect(shiftAround([ci(400, ["energy": 1])] + before + after, at(4), nowMs: NOW).first { $0.id == .energy }!.before == 2)
        #expect(shiftAround(before + after, addLocalDays(TODAY, 10), nowMs: NOW).first { $0.id == .energy }!.after == nil)
        let base = SymptomShift(id: .energy, label: "Energy", before: 2, after: 4, delta: 2, daysBefore: 5, daysAfter: 5)
        #expect(isTrendworthy(base))
        var thin = base; thin.daysAfter = 1; #expect(!isTrendworthy(thin))
        thin = base; thin.daysBefore = 1; #expect(!isTrendworthy(thin))
        thin = base; thin.delta = nil; #expect(!isTrendworthy(thin))
    }

    @Test func streaksAndLookup() {
        #expect(checkInStreak([0, 1, 2].map { ci(Double($0), ["energy": 3]) }, nowMs: NOW).current == 3)
        #expect(checkInStreak([1, 2, 3].map { ci(Double($0), ["energy": 3]) }, nowMs: NOW).current == 3)
        #expect(checkInStreak([0, 1, 3, 4].map { ci(Double($0), ["energy": 3]) }, nowMs: NOW).current == 2)
        #expect(checkInStreak([ci(10, ["energy": 3])], nowMs: NOW).current == 0)
        #expect(checkInStreak([0, 5, 10, 29, 40].map { ci(Double($0), ["energy": 3]) }, nowMs: NOW).last30 == 4)
        #expect(checkInStreak([], nowMs: NOW) == CheckInStreak(current: 0, last30: 0))
        #expect(checkInFor([ci(1, ["energy": 3])], at(1) + 20 * HOUR)?.id == "c1")
        #expect(checkInFor([ci(1, ["energy": 3])], at(2)) == nil)
        #expect(ratingSeries([ci(0, ["energy": 5]), ci(1, ["sleep": 2]), ci(2, ["energy": 1])], .energy) == [RatingPoint(at: at(2), value: 1), RatingPoint(at: at(0), value: 5)])
    }

    @Test func diary() {
        struct E { var at: Millis; var id: String = "" }
        func check(_ at: Millis, _ notes: String? = nil) -> CheckIn { CheckIn(id: "c-\(at)", profileId: "me", at: startOfLocalDay(at), ratings: ["energy": 3], notes: notes) }
        let only = diaryDays([E(at: local(2026, 8, 20, 7))], at: \.at, [check(local(2026, 8, 20, 12), "rough night")])
        #expect(only.count == 1 && only[0].entries.count == 1 && only[0].checkIn?.notes == "rough night")
        let rated = diaryDays([E](), at: \.at, [check(local(2026, 8, 21, 12), "woke at three")])
        #expect(rated.count == 1 && rated[0].entries.isEmpty && rated[0].checkIn?.notes == "woke at three")
        let dosed = diaryDays([E(at: local(2026, 8, 22, 8))], at: \.at, [])
        #expect(dosed.count == 1 && dosed[0].checkIn == nil)
        let order = diaryDays([E(at: local(2026, 8, 20, 12)), E(at: local(2026, 8, 22, 12))], at: \.at, [check(local(2026, 8, 21, 12))])
        #expect(order.map { dayOfMonth($0.day) } == [22, 21, 20])
        #expect(diaryDays([local(2026, 8, 23, 7), local(2026, 8, 23, 22), local(2026, 8, 24, 7)].map { E(at: $0) }, at: \.at, []).map(\.entries.count) == [1, 2])
        #expect(diaryDays([E(at: local(2026, 8, 25, 22), id: "b"), E(at: local(2026, 8, 25, 7), id: "a")], at: \.at, [])[0].entries.map(\.id) == ["b", "a"])
        #expect(diaryDays([E](), at: \.at, []).isEmpty)
    }

    @Test func ratable() {
        let now = local(2026, 6, 10, 14)
        func day(_ d: Int, _ h: Int = 0) -> Millis { local(2026, 6, d, h) }
        #expect(ratableDay(day(8, 23), nowMs: now) == day(8) && ratableDay(day(8), nowMs: now) == day(8))
        #expect(ratableDay(day(10), nowMs: now) == day(10) && ratableDay(day(10, 23), nowMs: now) == day(10) && ratableDay(now, nowMs: now) == day(10))
        #expect(ratableDay(local(2021, 1, 1), nowMs: now) == local(2021, 1, 1))
        #expect(ratableDay(day(11), nowMs: now) == nil && ratableDay(day(11, 23), nowMs: now) == nil)
        #expect(ratableDay(local(2062, 6, 10), nowMs: now) == nil)
    }

    @Test func axes() {
        #expect(SYMPTOMS.first { $0.id == .appetite }?.label == "Physical hunger")
        #expect(SYMPTOMS.first { $0.id == .foodNoise }?.higherIsBetter == false)
        let ids = SYMPTOMS.map(\.id)
        #expect(ids.firstIndex(of: .foodNoise)! == ids.firstIndex(of: .appetite)! + 1)
        #expect(SYMPTOMS.filter { $0.hint != nil }.map(\.id.rawValue).sorted() == ["appetite", "foodNoise"])
        let rows = averages([ci(0, ["appetite": 4])])
        #expect(rows.first { $0.id == .appetite }!.mean == 4 && rows.first { $0.id == .foodNoise }!.mean == nil)
        #expect(checkInStreak([ci(0, ["appetite": 4])], nowMs: NOW).current == 1)
    }
}

@Suite struct FeelingTests {
    @Test func tones() {
        for r in 1...5 { #expect(ratingTone(Double(r), true) == FEELING_TONE[r]) }
        #expect(ratingTone(1) == .neutral && ratingTone(5) == .neutral && ratingTone(3, nil) == .neutral)
        #expect(ratingTone(1, false) == .leaf && ratingTone(2, false) == .mint && ratingTone(3, false) == .sky)
        #expect(ratingTone(4, false) == .tangerine && ratingTone(5, false) == .rose)
        for r in 1...5 { #expect(ratingTone(Double(r), false) == ratingTone(Double(SYMPTOM_SCALE_MAX + 1 - r), true)) }
        #expect(ratingTone(0, true) == .neutral && ratingTone(9, true) == .neutral)
        let hunger = SYMPTOMS.first { $0.id == .appetite }!, sleep = SYMPTOMS.first { $0.id == .sleep }!, noise = SYMPTOMS.first { $0.id == .foodNoise }!
        #expect(ratingTone(2, hunger.higherIsBetter) == .neutral && ratingTone(2, sleep.higherIsBetter) == .tangerine && ratingTone(2, noise.higherIsBetter) == .mint)
    }

    @Test func lowest() {
        #expect(lowestRatedTone([(5, true), (1, true), (4, true)]) == .rose)
        #expect(lowestRatedTone([(4, true), (1, nil)]) == .mint)
        #expect(lowestRatedTone([(1, nil)]) == nil)
        #expect(lowestRatedTone([(5, true), (5, false)]) == .rose)
        #expect(lowestRatedTone([(3, true), (1, false)]) == .sky)
        #expect(lowestRatedTone([(5, true), (1, false)]) == .leaf)
        #expect(lowestRatedTone([]) == nil)
        #expect(lowestRatedTone([(5, true)]) == .leaf)
    }
}
