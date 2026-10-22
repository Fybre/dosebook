import Foundation
import Testing
@testable import BenchCore

/// Shaped like Injectly's exports, with invented rows.
private let LOGS = """
Medication Name,Dose in mcg,Time logged,Timezone,Route,Injection Site,Notes
CJC-1295 & Ipamorelin,250,2026-10-22T09:00:00.000,Australia/Sydney,SubQ,,
Retatrutide,"5,000",2026-10-21T09:15:00.000,Australia/Sydney,SubQ,Left Thigh,felt fine
BPC-157,500,2026-10-20T23:55:00.000,America/New_York,SubQ,,
"""
private let WEIGHT = """
Weight (kg),Measured At,Source,Linked Log Id,Created At
86.5,2026-10-16T00:55:00.000,settings,,2026-10-16T00:56:07.791652
"""
private let MEDICATIONS = """
Medication Name,Brand Names,Form,Route,Vial mg,BAC ml,Dose mcg,Units per Dose,Syringe,mcg per IU,Cycle Config (JSON),Titration Config (JSON),Blend Constituents (JSON),Reminders (JSON),Created At
BPC-157,,reconstituted,SubQ,10.0,2.0,500.0,10,u30,,,,,,2026-10-10T20:01:47.040092
"""

private func cjcIpa(_ cjc: Double = 10, _ ipa: Double = 10) -> Peptide {
    var d = CustomDraft(name: "CJC-1295 & Ipamorelin", category: .blend)
    d.components = [BlendComponent(peptideId: "cjc-1295-no-dac", name: "CJC-1295 without DAC", mgPerVial: cjc),
                    BlendComponent(peptideId: "ipamorelin", name: "Ipamorelin", mgPerVial: ipa)]
    return draftToPeptide(d)
}

private func plan(_ csv: String, _ peptides: [Peptide] = Library.peptides) throws -> (String, ImportPlan) {
    guard case .table(_, let profile, _, let plan) = try readImportFile(name: "export.csv", bytes: Array(csv.utf8),
        options: ImportOptions(peptides: peptides, existingLogs: [], existingMeasurements: [])) else { throw ImportError(message: "not a table") }
    return (profile.id, plan)
}

private func wallClock(_ ms: Millis, _ zone: String) -> String {
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: zone)!
    let c = cal.dateComponents([.month, .day, .hour, .minute], from: Date(millis: ms))
    return String(format: "%02d-%02d %02d:%02d", c.month!, c.day!, c.hour!, c.minute!)
}

@Suite struct InjectlyImportTests {
    @Test func readsLogs() throws {
        let (profile, p) = try plan(LOGS, Library.peptides + [cjcIpa()])
        #expect(profile == "injectly")
        #expect(p.problems.isEmpty && p.unresolved.isEmpty)
        let reta = p.doses.first { $0.peptideId == "retatrutide" }!
        // Micrograms, as the column says, with the thousands separator read.
        #expect(reta.doseMcg == 5000)
        #expect(reta.site == .thighL && reta.notes == "felt fine")
        // Each time is read where it was written, whatever zone the phone is in now.
        #expect(wallClock(reta.at, "Australia/Sydney") == "10-21 09:15")
        #expect(wallClock(p.doses.first { $0.peptideId == "bpc-157" }!.at, "America/New_York") == "10-20 23:55")
    }

    @Test func aBlendDoseIsItsFirstPart() throws {
        // 250 mcg of each part of a 10 + 10 vial is 500 mcg of the blend.
        var blend = try plan(LOGS, Library.peptides + [cjcIpa()]).1.doses.first { isCustomId($0.peptideId) }!
        #expect(blend.doseMcg == 500)
        // An uneven vial scales by the whole over the first part.
        blend = try plan(LOGS, Library.peptides + [cjcIpa(5, 15)]).1.doses.first { isCustomId($0.peptideId) }!
        #expect(blend.doseMcg == 1000)
        let parts = decomposeDose(cjcIpa(), 500, resolve: { Library.byId[$0] })
        #expect(parts.map(\.mcg) == [250, 250])
    }

    @Test func aMixWithNoBlendIsLeftUnresolved() throws {
        let p = try plan(LOGS).1
        #expect(p.unresolved.map(\.label) == ["CJC-1295 & Ipamorelin"])
        #expect(!p.doses.contains { $0.peptideId == "ipamorelin" })
    }

    @Test func readsWeights() throws {
        let (profile, p) = try plan(WEIGHT)
        #expect(profile == "injectly" && p.weights.map(\.weightKg) == [86.5])
    }

    @Test func explainsTheOtherFiles() {
        for (csv, expected) in [(MEDICATIONS, "list of medications"), ("Field,Value\nWeight (kg),86.5", "profile settings")] {
            do { _ = try plan(csv); Issue.record("should refuse") } catch let e as ImportError { #expect(e.message.contains(expected)) } catch {}
        }
    }
}

@Suite struct ImportHeaderUnitTests {
    @Test func doseColumnUnits() {
        #expect(doseUnitFromHeader("Dose in mcg") == .mcg)
        #expect(doseUnitFromHeader("Dose (µg)") == .mcg)
        #expect(doseUnitFromHeader("dose_mg") == nil || doseUnitFromHeader("Dose (mg)") == .mg)
        #expect(doseUnitFromHeader("Dose (mg)") == .mg)
        #expect(doseUnitFromHeader("Dose") == nil)
    }

    @Test func genericReaderHonoursTheHeader() throws {
        let p = try plan("Date,Medication,Dose (mcg)\n2026-07-26,BPC-157,250\n2026-07-27,BPC-157,0.5 mg").1
        #expect(p.doses.map(\.doseMcg) == [250, 500])
    }

    @Test func joinedNamesAreMixes() {
        #expect(resolvePeptide("CJC-1295 & Ipamorelin", Library.peptides) == nil)
        // A mix the library knows by that name is the blend itself.
        #expect(resolvePeptide("BPC-157 + TB-500", Library.peptides)?.id == "wolverine")
        #expect(resolvePeptide("TB-500 + Ipamorelin", Library.peptides) == nil)
        #expect(resolvePeptide("Ipamorelin", Library.peptides)?.id == "ipamorelin")
        #expect(resolvePeptide("Mounjaro (tirzepatide)", Library.peptides)?.id == "tirzepatide")
    }
}
