import Foundation
import Testing
@testable import BenchCore

private func find(_ lines: [String], _ id: String) -> LabCandidate? { parseLabReport(lines).candidates.first { $0.markerId == id } }

@Suite struct LabReportTests {
    @Test func readsALine() {
        let c = find(["HbA1c 5.4 %"], "hba1c")!
        #expect(c.value == 5.4 && c.unit == "%" && c.confidence == .exact)
        #expect(find(["Lipase 31 U/L"], "lipase")!.source == "Lipase 31 U/L")
        let alt = find(["ALT 22 U/L (Ref: 7 - 56)"], "alt")!
        #expect(alt.value == 22 && alt.refLow == 7 && alt.refHigh == 56)
        #expect(find(["Ferritin-like TSH 1.80 mIU/L 0.40 - 4.50"], "tsh")!.value == 1.8)
        let tg = find(["Triglycerides 88 mg/dL <150"], "triglycerides")!
        #expect(tg.value == 88 && tg.refHigh == 150 && tg.refLow == nil)
        let hdl = find(["HDL cholesterol 61 mg/dL >40"], "hdl")!
        #expect(hdl.value == 61 && hdl.refLow == 40)
        #expect(find(["14  0012345  Creatinine 0.98 mg/dL"], "creatinine")!.value == 0.98)
        #expect(find(["Creatinine 0,98 mg/dL"], "creatinine")!.value == 0.98)
        #expect(find(["IGF-1 1,200 ng/mL"], "igf1")!.value == 1200)
    }

    @Test func matchesTheRightAnalyte() {
        let both = parseLabReport(["HDL cholesterol 61 mg/dL", "LDL cholesterol 92 mg/dL"]).candidates
        #expect(both.first { $0.markerId == "hdl" }!.value == 61)
        #expect(both.first { $0.markerId == "ldl" }!.value == 92)
        #expect(find(["Hemoglobin A1c 5.6 %"], "hba1c")!.value == 5.6)
        #expect(find(["SGPT (ALT) 30 U/L"], "alt")!.value == 30)
        #expect(find(["Hematocrit 47.2 %"], "haematocrit")!.value == 47.2)
        #expect(find(["Thyrotropin 1.9 mIU/L"], "tsh")!.confidence == .loose)
        let repeated = parseLabReport(["ALT 22 U/L", "Summary: ALT 99 U/L"]).candidates
        #expect(repeated.filter { $0.markerId == "alt" }.count == 1 && repeated[0].value == 22)
        #expect(parseLabReport(["Reference ranges: ALT 7 - 56 U/L"]).candidates.isEmpty)
        #expect(parseLabReport(["Patient copy. Please discuss with your doctor."]).candidates.isEmpty)
        #expect(parseLabReport([]).candidates.isEmpty)
    }

    @Test func units() {
        #expect(find(["Lipase 31 u/l"], "lipase")!.confidence == .exact)
        #expect(find(["Fasting insulin 6.1 µIU/mL"], "insulin-fasting")!.confidence == .exact)
        #expect(find(["Fasting insulin 6.1 uIU/mL"], "insulin-fasting")!.confidence == .exact)
        let tg = find(["Triglycerides 1.0 mmol/L"], "triglycerides")!
        #expect(tg.confidence == .unitMismatch && tg.unit == "mmol/L" && tg.expectedUnit == "mg/dL")
        let hct = find(["Haematocrit 47.2"], "haematocrit")!
        #expect(hct.unit == nil && hct.confidence == .exact)
        #expect(find(["HbA1c 5.4 previously recorded as elevated"], "hba1c")!.unit == nil)
    }

    @Test func header() {
        #expect(parseLabReport(["Acme Pathology", "Collected: 2026-06-14", "ALT 22 U/L"]).collectedAt == local(2026, 6, 14))
        #expect(parseLabReport(["2026-06-14", "ALT 22 U/L"]).collectedAt != nil)
        #expect(parseLabReport(["ALT 22 U/L"]).collectedAt == nil)
        #expect(parseLabReport(["LabCorp Patient Report", "ALT 22 U/L"]).lab?.lowercased() == "labcorp")
    }

    static let REPORT = [
        "Quest Diagnostics",
        "Patient: A Kumar    Collected: 2026-06-14",
        "Test                    Result      Units        Reference",
        "Hemoglobin A1c          5.4         %            4.0 - 5.6",
        "Glucose, fasting        92          mg/dL        70 - 99",
        "Triglycerides           88          mg/dL        <150",
        "HDL cholesterol         61          mg/dL        >40",
        "LDL cholesterol         92          mg/dL        0 - 99",
        "ALT (SGPT)              22          U/L          7 - 56",
        "AST (SGOT)              19          U/L          10 - 40",
        "Hematocrit              47.2        %            38.5 - 50.0",
        "TSH                     1.80        mIU/L        0.40 - 4.50",
        "IGF-1                   210         ng/mL        83 - 233",
        "End of report",
    ]

    @Test func wholeReport() {
        let report = parseLabReport(Self.REPORT)
        #expect(report.candidates.map(\.markerId).sorted() == ["alt", "ast", "glucose-fasting", "haematocrit", "hba1c", "hdl", "igf1", "ldl", "triglycerides", "tsh"])
        let by = Dictionary(uniqueKeysWithValues: report.candidates.map { ($0.markerId, $0.value) })
        #expect(by == ["hba1c": 5.4, "glucose-fasting": 92, "triglycerides": 88, "hdl": 61, "ldl": 92, "alt": 22, "ast": 19, "haematocrit": 47.2, "tsh": 1.8, "igf1": 210])
        let alt = report.candidates.first { $0.markerId == "alt" }!
        #expect(alt.refLow == 7 && alt.refHigh == 56)
        #expect(report.lab?.lowercased() == "quest")
        #expect(report.collectedAt == local(2026, 6, 14))
    }

    @Test func rangePunctuation() {
        for sep in ["-", "to", "\u{2013}"] {
            let c = parseLabReport(["ALT 22 U/L 7 \(sep) 56"]).candidates[0]
            #expect(c.value == 22 && c.refLow == 7 && c.refHigh == 56, "\(sep)")
        }
    }
}
