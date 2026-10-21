import Foundation
import Testing
@testable import BenchCore

private let shotsyCsv = String(decoding: fixture("shotsy.csv"), as: UTF8.self)
private func tableOf(_ csv: String) -> ImportTable { toTable(parseDelimited(csv)) }

@Suite struct MapSiteTests {
    @Test func shotsyPositions() {
        #expect(mapSite("Stomach - Upper Left") == .abdomenUL)
        #expect(mapSite("Stomach - Upper Mid") == "abdomen-um")
        #expect(mapSite("Stomach - Upper Right") == .abdomenUR)
        #expect(mapSite("Stomach - Lower Left") == .abdomenLL)
        #expect(mapSite("Stomach - Lower Mid") == "abdomen-lm")
        #expect(mapSite("Stomach - Lower Right") == .abdomenLR)
        #expect(mapSite("Left Arm") == .armL)
    }

    @Test func otherWordings() {
        #expect(mapSite("abdomen upper left") == .abdomenUL)
        #expect(mapSite("Belly (lower right)") == .abdomenLR)
        #expect(mapSite("L thigh") == .thighL)
        #expect(mapSite("right quad") == .thighR)
        #expect(mapSite("Left delt") == .armL)
        #expect(mapSite("right buttock") == .gluteR)
        #expect(mapSite("Stomach - Left") == .abdomenUL)
    }

    @Test func noGuessing() {
        for t in ["Stomach", "thigh", "", "somewhere"] { #expect(mapSite(t) == nil) }
    }

    @Test func onlyKnownSites() {
        let known = Set(INJECTION_SITES.map(\.id))
        for t in ["Stomach - Upper Left", "Stomach - Upper Mid", "Stomach - Lower Mid", "Left Arm", "right glute", "L thigh"] {
            #expect(mapSite(t).map(known.contains) == true, "\(t)")
        }
    }
}

@Suite struct LabelAndPeptideTests {
    @Test func splitsDose() {
        #expect(splitLabelAndDose("Mounjaro® 10.0 mg") == ("Mounjaro", 10_000))
        #expect(splitLabelAndDose("Mounjaro® 2.5 mg") == ("Mounjaro", 2500))
        #expect(splitLabelAndDose("BPC-157 500mcg") == ("BPC-157", 500))
        #expect(splitLabelAndDose("Retatrutide") == ("Retatrutide", nil))
        #expect(splitLabelAndDose("TB-500").name == "TB-500")
        #expect(splitLabelAndDose("CJC-1295 2 mg") == ("CJC-1295", 2000))
    }

    @Test func resolves() {
        let r = { (n: String) in resolvePeptide(n, Library.peptides)?.id }
        #expect(r("Mounjaro") == "tirzepatide")
        #expect(r("Zepbound") == "tirzepatide")
        #expect(r("Ozempic") == "semaglutide")
        #expect(r("Wegovy") == "semaglutide")
        #expect(r("Saxenda") == "liraglutide")
        #expect(r("tirzepatide") == "tirzepatide")
        #expect(r("RETATRUTIDE") == "retatrutide")
        #expect(r("Reta") == "retatrutide")
        #expect(r("  Mounjaro®  ") == "tirzepatide")
        #expect(r("Semaglutide") == "semaglutide")
        #expect(r("CagriSema") == "cagrisema")
        #expect(r("Insulin glargine") == nil)
        #expect(r("") == nil)
        #expect(r("xyz") == nil)
    }

    @Test func weightUnits() {
        #expect(weightUnitFromHeader("Weight (kg)") == .kg)
        #expect(weightUnitFromHeader("Recorded Weight (kg)") == .kg)
        #expect(weightUnitFromHeader("Weight (lb)") == .lb)
        #expect(weightUnitFromHeader("Weight in lbs") == .lb)
        #expect(weightUnitFromHeader("Body weight pounds") == .lb)
        #expect(weightUnitFromHeader("Weight") == nil)
        #expect(weightUnitFromHeader("Mass") == nil)
    }

    @Test func detects() {
        let t = tableOf(shotsyCsv)
        #expect(detectProfile(t.headers)?.id == "shotsy")
        #expect(detectProfile(tableOf("Date,Medication,Dose,Weight\n2026-07-26,Ozempic,1 mg,85").headers)?.id == "generic")
        #expect(genericProfile.score(t.headers) > 0)
        #expect(shotsyProfile.score(t.headers) > genericProfile.score(t.headers))
        #expect(detectProfile(["colour", "size"]) == nil)
        #expect(detectProfile(["date"]) == nil)
        #expect(detectProfile([]) == nil)
    }
}

@Suite struct ShotsyExportTests {
    let result: ProfileResult
    let doses: [CanonicalRecord]
    let weights: [CanonicalRecord]

    init() {
        let t = tableOf(shotsyCsv)
        result = shotsyProfile.read(t.records, t.headers)
        doses = result.records.filter(\.isDose)
        weights = result.records.filter { !$0.isDose }
    }

    @Test func readsEverything() {
        #expect(result.problems.isEmpty)
        #expect(doses.count == 25)
        #expect(weights.count == 14)
    }

    @Test func firstInjection() {
        let first = doses[0]
        #expect(first.label == "Mounjaro")
        #expect(first.doseMcg == 2500)
        #expect(first.site == .abdomenUL)
        #expect(year(first.at) == 2026 && month(first.at) == 2 && dayOfMonth(first.at) == 8)
        #expect(hours(first.at) == 11 && minutes(first.at) == 54)
    }

    @Test func titration() {
        #expect(doses.prefix(4).map(\.doseMcg) == [2500, 5000, 7500, 10_000])
        let april12 = doses.first { month($0.at) == 4 && dayOfMonth($0.at) == 12 }
        #expect(april12?.doseMcg == 5000)
    }

    @Test func allTirzepatide() {
        for d in doses { #expect(resolvePeptide(d.label!, Library.peptides)?.id == "tirzepatide", "\(d.label!)") }
    }

    @Test func sites() {
        let sites = doses.map(\.site)
        #expect(!sites.contains(nil))
        #expect(sites.contains("abdomen-um"))
        #expect(sites.contains("abdomen-lm"))
        #expect(sites.contains(.armL))
    }

    @Test func weightsAndSymptomRows() {
        #expect(weights[0].weightKg == 94.2)
        #expect(year(weights[0].at) == 2025)
        #expect(result.records.filter { month($0.at) == 2 && dayOfMonth($0.at) == 11 }.isEmpty)
    }
}

@Suite struct GenericProfileTests {
    private func read(_ csv: String) -> ProfileResult {
        let t = tableOf(csv)
        return genericProfile.read(t.records, t.headers)
    }

    @Test func medicationLog() {
        let r = read("Date,Time,Medication,Dose,Site,Notes\n2026-07-26,09:30,Ozempic,1 mg,left thigh,felt fine")
        #expect(r.problems.isEmpty)
        let d = r.records[0]
        #expect(d.label == "Ozempic" && d.doseMcg == 1000 && d.site == .thighL && d.notes == "felt fine")
    }

    @Test func doseColumnWins() {
        #expect(read("Date,Product,Dose\n2026-07-26,Ozempic 0.25 mg,1 mg").records[0].doseMcg == 1000)
    }

    @Test func weightOnly() {
        let r = read("Date,Body Weight\n2026-07-26,85.4")
        #expect(r.records.count == 1)
        #expect(r.records[0].weightKg == 85.4 && r.records[0].sourceRow == 2)
    }

    @Test func ambiguousDate() {
        let r = read("Date,Medication\n26/07/2026,Ozempic")
        #expect(r.records.isEmpty)
        #expect(r.problems[0].reason.contains("lead with the year"))
    }

    @Test func weightUnits() {
        var r = read("Date,Weight (lb)\n2026-07-26,188")
        #expect(r.problems.isEmpty)
        #expect(isClose(r.records[0].weightKg!, 85.28, digits: 2))
        #expect(read("Date,Weight (kg)\n2026-07-26,85.4").records[0].weightKg == 85.4)
        r = read("Date,Weight\n2026-07-26,85.4")
        #expect(r.problems.isEmpty && r.records[0].weightKg == 85.4)
        r = read("Date,Weight\n2026-07-26,400")
        #expect(r.records.isEmpty)
        #expect(r.problems[0].reason.contains("too high to be kilograms"))
    }

    @Test func blankDateSkipped() {
        let r = read("Date,Medication\n,Ozempic\n2026-07-26,Ozempic")
        #expect(r.records.count == 1 && r.problems.isEmpty)
    }

    @Test func humanRowNumbers() {
        #expect(read("Date,Medication\n2026-07-26,Ozempic\n2026-07-27,Ozempic").records.map(\.sourceRow) == [2, 3])
    }
}
