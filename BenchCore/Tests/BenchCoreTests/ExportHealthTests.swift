import Foundation
import Testing
@testable import BenchCore

// Ports of dosecsv, palette and healthsync tests.

private let AT: Millis = 1_778_578_200_000 // Date.UTC(2026, 4, 12, 9, 30)
private func clog(id: String = "l1", at: Millis = AT, route: Route = .subcutaneous, units: Double? = nil, presses: Double? = nil,
                  skipped: Bool? = nil, notes: String? = nil, feeling: Int? = nil, sideEffects: [String]? = nil) -> DoseLog {
    DoseLog(id: id, profileId: "me", peptideId: "bpc-157", at: at, doseMcg: 500, route: route, units: units, presses: presses,
            skipped: skipped, notes: notes, feeling: feeling, sideEffects: sideEffects)
}
private func name(_ id: String) -> String { id == "bpc-157" ? "BPC-157" : id }
private func cells(_ row: String) -> [String] { row.components(separatedBy: ",") }

@Suite struct DoseCSVTests {
    @Test func escaping() {
        #expect(escapeCsv("nausea") == "nausea" && escapeCsv("500") == "500")
        #expect(escapeCsv("felt rough, then fine") == "\"felt rough, then fine\"")
        #expect(escapeCsv("he said \"fine\"") == "\"he said \"\"fine\"\"\"")
        #expect(escapeCsv("two\nlines") == "\"two\nlines\"" && escapeCsv("") == "")
    }

    @Test func rows() {
        #expect(doseCsv([clog(sideEffects: ["nausea", "headache"])], nameFor: name).text.contains("nausea; headache"))
        let r = doseCsv([clog(sideEffects: ["a", "b", "c"])], nameFor: name).rows[0]
        #expect(cells(r).count == DOSE_CSV_HEADER.count && r.contains("a; b; c"))
        let f = doseCsv([clog(feeling: 2)], nameFor: name).text
        #expect(f.contains("Off") && !f.contains(",2,"))
        let blank = cells(doseCsv([clog()], nameFor: name).rows[0])
        let fi = DOSE_CSV_HEADER.firstIndex(of: "feeling")!
        #expect(blank[fi] == "" && blank[fi + 1] == "")
        let nasal = cells(doseCsv([clog(route: .intranasal, presses: 2)], nameFor: name).rows[0])
        #expect(nasal[DOSE_CSV_HEADER.firstIndex(of: "presses")!] == "2" && nasal[DOSE_CSV_HEADER.firstIndex(of: "units")!] == "")
        let syr = cells(doseCsv([clog(units: 12)], nameFor: name).rows[0])
        #expect(syr[DOSE_CSV_HEADER.firstIndex(of: "presses")!] == "" && syr[DOSE_CSV_HEADER.firstIndex(of: "units")!] == "12")
        #expect(doseCsv([clog(notes: "sore, but fine")], nameFor: name).rows[0].contains("\"sore, but fine\""))
        #expect(doseCsv([clog(skipped: true, feeling: 1)], nameFor: name).rows[0].contains(",yes,Rough,"))
        let ordered = doseCsv([clog(id: "b", at: AT + DAY_MS), clog(id: "a")], nameFor: name).rows
        #expect(ordered[0] < ordered[1])
        #expect(Set(DOSE_CSV_HEADER).count == DOSE_CSV_HEADER.count && doseCsv([], nameFor: name).text == DOSE_CSV_HEADER.joined(separator: ","))
        let first = cells(doseCsv([clog()], nameFor: name).rows[0])
        #expect(first[2] == "BPC-157" && first[3] == "500" && first[4] == "0.5" && first[0].count == 10 && first[1].count == 5)
    }
}

@Suite struct PaletteTests {
    let C = SERIES_TONES

    @Test func assignment() {
        let a = assignColors([ColorSubject(protocolId: "a"), ColorSubject(protocolId: "b")])
        #expect(a.byKey["a"] == C[0] && a.byKey["b"] == C[1])
        let blend = assignColors([ColorSubject(protocolId: "blend", componentKeys: ["cjc", "ipa"]), ColorSubject(protocolId: "after")])
        #expect(blend.byKey["blend:cjc"] == C[0] && blend.byKey["blend:ipa"] == C[1] && blend.byKey["after"] == C[2])
        #expect(assignColors([ColorSubject(protocolId: "blend", componentKeys: ["cjc", "ipa"])]).byProtocol["blend"] == C[0])
        let reserve = assignColors([ColorSubject(protocolId: "unplottable"), ColorSubject(protocolId: "next")])
        #expect(reserve.byProtocol["unplottable"] == C[0] && reserve.byProtocol["next"] == C[1])
        let empty = assignColors([ColorSubject(protocolId: "a", componentKeys: [])])
        #expect(empty.byKey["a"] == C[0] && empty.byProtocol["a"] == C[0])
        let many = assignColors((0..<(C.count + 2)).map { ColorSubject(protocolId: "p\($0)") })
        #expect(many.byProtocol.count == C.count + 2 && many.byProtocol["p\(C.count)"] == C[0] && many.byProtocol["p\(C.count + 1)"] == C[1])
        let distinct = assignColors([ColorSubject(protocolId: "a", componentKeys: ["x", "y"]), ColorSubject(protocolId: "b"), ColorSubject(protocolId: "c")])
        #expect(Set(distinct.byKey.values).count == distinct.byKey.count)
        #expect(a.byProtocol["missing"] == nil && a.byKey["missing"] == nil)
        let subjects = [ColorSubject(protocolId: "a", componentKeys: ["x"]), ColorSubject(protocolId: "b")]
        #expect(assignColors(subjects) == assignColors(subjects))
        #expect(a.byProtocol["a"] == .mint && a.byProtocol["b"] == .grape)
    }

    @Test func byCompound() {
        let p = assignColors([ColorSubject(protocolId: "a", peptideId: "bpc-157"), ColorSubject(protocolId: "b", peptideId: "tb-500")])
        #expect(p.byPeptide["bpc-157"] == p.byProtocol["a"] && p.byPeptide["tb-500"] == p.byProtocol["b"])
        #expect(assignColors([ColorSubject(protocolId: "k", peptideId: "klow", componentKeys: ["x", "y"])]).byPeptide["klow"] == C[0])
        let two = assignColors([ColorSubject(protocolId: "morning", peptideId: "bpc-157"), ColorSubject(protocolId: "evening", peptideId: "bpc-157")])
        #expect(two.byPeptide["bpc-157"] == nil && two.byProtocol["morning"] == C[0] && two.byProtocol["evening"] == C[1])
        #expect(assignColors([ColorSubject(protocolId: "a")]).byPeptide.isEmpty)
        #expect(doseColor(p, protocolId: "b", peptideId: "tb-500") == C[1])
        #expect(doseColor(p, protocolId: nil, peptideId: "bpc-157") == C[0])
        #expect(doseColor(p, protocolId: "deleted", peptideId: "bpc-157") == C[0])
        #expect(doseColor(p, protocolId: nil, peptideId: "retatrutide") == nil)
        #expect(doseColor(two, protocolId: "evening", peptideId: "bpc-157") == C[1] && doseColor(two, protocolId: nil, peptideId: "bpc-157") == nil)
    }

    @Test func subjects() {
        let now: Millis = 1_785_326_400_000
        func proto(_ id: String, _ pid: String, dose: Double = 4000) -> DoseProtocol {
            makeProtocol(id: id, peptideId: pid, name: id, startedAt: now - 30 * DAY_MS, doseMcg: dose, schedule: Schedule(kind: .intervalDays, intervalDays: 7))
        }
        let resolve: (String) -> Peptide? = { Library.byId[$0] }
        let s = colorSubjects([proto("p", "bpc-157")], resolve: resolve, nowMs: now)[0]
        #expect(s.protocolId == "p" && s.peptideId == "bpc-157" && s.componentKeys.isEmpty)
        #expect(colorSubjects([proto("p", "cagrisema")], resolve: resolve, nowMs: now)[0].componentKeys == ["cagrilintide", "semaglutide"])
        #expect(colorSubjects([proto("p", "klow")], resolve: resolve, nowMs: now)[0].componentKeys == ["bpc-157"])
        #expect(colorSubjects([proto("p", "cagrisema", dose: 100)], resolve: resolve, nowMs: now)[0].componentKeys
            == colorSubjects([proto("p", "cagrisema", dose: 8000)], resolve: resolve, nowMs: now)[0].componentKeys)
        let unknown = colorSubjects([proto("p", "not-a-compound")], resolve: resolve, nowMs: now)[0]
        #expect(unknown.protocolId == "p" && unknown.componentKeys.isEmpty)
    }
}

private let HNOW: Millis = 1_785_398_400_000
private func hm(_ id: String, at: Millis = HNOW, kg: Double? = 89.7, externalId: String? = nil, waist: Double? = nil) -> BodyMeasurement {
    BodyMeasurement(id: id, profileId: "me", at: at, weightKg: kg, waistCm: waist, externalId: externalId)
}
private func hs(_ ext: String, at: Millis = HNOW, kg: Double = 89.7) -> HealthSample { HealthSample(externalId: ext, at: at, weightKg: kg) }

@Suite struct HealthSyncTests {
    @Test func pull() {
        let a = planPull([], [hs("hc-1")])
        #expect(a.toAdd.count == 1 && a.toLink.isEmpty && a.skipped == 0)
        let s = planPull([hm("a", externalId: "hc-1")], [hs("hc-1")])
        #expect(s.toAdd.isEmpty && s.skipped == 1)
        let link = planPull([hm("a")], [hs("hc-1", at: HNOW + 60_000, kg: 89.72)])
        #expect(link.toAdd.isEmpty && link.toLink == [HealthLink(id: "a", externalId: "hc-1")])
        let far = planPull([hm("a")], [hs("hc-1", at: HNOW + MATCH_WINDOW_MS + 1000)])
        #expect(far.toAdd.count == 1 && far.toLink.isEmpty)
        #expect(planPull([hm("a")], [hs("hc-1", kg: 89.7 + MATCH_WEIGHT_KG + 0.1)]).toAdd.count == 1)
        let once = planPull([hm("a")], [hs("hc-1"), hs("hc-2", at: HNOW + 1000)])
        #expect(once.toLink.count == 1 && once.toAdd.count == 1)
        let old = planPull([hm("a", externalId: "hc-old")], [hs("hc-new")])
        #expect(old.toLink.isEmpty && old.toAdd.count == 1)
        let noWeight = planPull([hm("a", kg: nil, waist: 90)], [hs("hc-1")])
        #expect(noWeight.toAdd.count == 1 && noWeight.toLink.isEmpty)
        let samples = [hs("hc-1"), hs("hc-2", at: HNOW + DAY_MS)]
        let stored = planPull([], samples).toAdd.enumerated().map { sampleToMeasurement($1, profileId: "me", id: "m\($0)") }
        let second = planPull(stored, samples)
        #expect(second.toAdd.isEmpty && second.toLink.isEmpty && second.skipped == 2)
        #expect(planPull([], []) == PullPlan(toAdd: [], toLink: [], skipped: 0))
    }

    @Test func samples() {
        let m = sampleToMeasurement(hs("hc-1"), profileId: "me", id: "m1")
        #expect(m.source == .healthConnect && m.externalId == "hc-1" && m.profileId == "me" && m.weightKg == 89.7)
        #expect(newestSample([]) == nil)
        let n = newestSample([hs("old", at: HNOW - 2 * DAY_MS, kg: 91), hs("new", kg: 89.4), hs("mid", at: HNOW - DAY_MS, kg: 90.2)])
        #expect(n?.externalId == "new" && n?.weightKg == 89.4)
        #expect(newestSample([hs("a", kg: 0)]) == nil)
        #expect(newestSample([hs("good", at: HNOW - 1000, kg: 88), hs("empty", kg: 0)])?.externalId == "good")
        let sum = summarise(planPull([hm("a")], [hs("hc-1"), hs("hc-2", at: HNOW + DAY_MS)]))
        #expect(sum == SyncSummary(added: 1, linked: 1, skipped: 0))
        #expect(describeSync(SyncSummary(added: 0, linked: 0, skipped: 4)) == "Already up to date.")
        #expect(describeSync(SyncSummary(added: 2, linked: 1, skipped: 0)) == "2 brought in, 1 matched to yours.")
    }

    @Test func sleepAndHeart() {
        func span(_ a: Double, _ b: Double) -> Span { Span(startAt: a, endAt: b) }
        #expect(mergeIntervals([span(0, 10), span(20, 30)]) == [span(0, 10), span(20, 30)])
        #expect(mergeIntervals([span(0, 20), span(10, 30)]) == [span(0, 30)])
        #expect(mergeIntervals([span(0, 100), span(20, 40)]) == [span(0, 100)])
        #expect(mergeIntervals([span(10, 30), span(0, 20)]) == [span(0, 30)])
        #expect(mergeIntervals([span(10, 10), span(30, 20)]).isEmpty)
        func night(_ d: Int, _ from: Int, _ to: Int, _ state: String? = nil) -> SleepSegment {
            SleepSegment(externalId: "s\(d)-\(from)", startAt: local(2026, 6, d, from), endAt: local(2026, 6, d, to), state: state)
        }
        let one = nightlySleep([night(14, 1, 8)])
        #expect(one.count == 1 && one[0].hours == 7)
        let over = nightlySleep([SleepSegment(externalId: "o", startAt: local(2026, 6, 14, 23), endAt: local(2026, 6, 15, 7))])
        #expect(over[0].day == local(2026, 6, 15) && over[0].hours == 8)
        #expect(nightlySleep([night(14, 1, 8, "asleep"), night(14, 8, 9, "awake"), night(14, 0, 1, "inBed")])[0].hours == 7)
        var stage = night(14, 2, 4, "deep"); stage.externalId = "stage"
        #expect(nightlySleep([night(14, 1, 8, "asleep"), stage])[0].hours == 7)
        let split = nightlySleep([night(14, 1, 3), night(14, 5, 8)])
        #expect(split[0].segments == 2 && split[0].hours == 5)
        #expect(nightlySleep([night(14, 1, 8), night(16, 1, 8), night(15, 1, 8)]).map { dayOfMonth($0.day) } == [16, 15, 14])
        #expect(nightlySleep([]).isEmpty)
        func r(_ d: Int, _ h: Int, _ bpm: Double) -> HeartRateSample { HeartRateSample(externalId: "r\(d)-\(h)", at: local(2026, 6, d, h), bpm: bpm) }
        #expect(dailyRestingHr([r(14, 3, 58), r(14, 9, 64)]) == [DayRate(day: local(2026, 6, 14), bpm: 58)])
        #expect(dailyRestingHr([r(14, 3, 58), r(15, 3, 61)]).count == 2 && dailyRestingHr([r(14, 3, 0)]).isEmpty)
        #expect(dayOfMonth(dailyRestingHr([r(14, 3, 58), r(16, 3, 60)])[0].day) == 16)
    }
}
