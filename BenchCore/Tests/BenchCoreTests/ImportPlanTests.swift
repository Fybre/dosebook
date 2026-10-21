import Foundation
import Testing
@testable import BenchCore

private let shotsyCsv = String(decoding: fixture("shotsy.csv"), as: UTF8.self)
private let NOW = local(2026, 7, 26, 9, 32)
private let DAY: Double = 86_400_000

private func planOf(_ records: [CanonicalRecord], logs: [(at: Millis, peptideId: String)] = [], measurements: [(at: Millis, weightKg: Double?)] = []) -> ImportPlan {
    buildImportPlan(records: records, problems: [], peptides: Library.peptides, existingLogs: logs, existingMeasurements: measurements)
}
private func dose(at: Millis = NOW, label: String = "Mounjaro", doseMcg: Double? = 10_000, row: Int = 2) -> CanonicalRecord {
    .dose(at: at, label: label, doseMcg: doseMcg, site: nil, notes: nil, sourceRow: row)
}
private func weight(at: Millis = NOW, kg: Double = 85.6, row: Int = 2) -> CanonicalRecord { .weight(at: at, weightKg: kg, sourceRow: row) }

private func shotsyPlan(logs: [(at: Millis, peptideId: String)] = [], measurements: [(at: Millis, weightKg: Double?)] = []) -> ImportPlan {
    let t = toTable(parseDelimited(shotsyCsv))
    let read = shotsyProfile.read(t.records, t.headers)
    return buildImportPlan(records: read.records, problems: read.problems, peptides: Library.peptides, existingLogs: logs, existingMeasurements: measurements)
}

@Suite struct ImportPlanTests {
    @Test func resolvesBrand() {
        let plan = planOf([dose()])
        #expect(plan.doses.count == 1)
        #expect(plan.doses[0].peptideId == "tirzepatide" && plan.doses[0].peptideName == "Tirzepatide")
    }

    @Test func collectsUnresolved() {
        let plan = planOf([dose(label: "Insulin glargine", row: 4), dose(label: "Insulin glargine", row: 9)])
        #expect(plan.doses.isEmpty)
        #expect(plan.unresolved.map(\.label) == ["Insulin glargine"])
        #expect(plan.unresolved.map(\.rows) == [[4, 9]])
    }

    @Test func unreadableDose() {
        let plan = planOf([dose(doseMcg: nil, row: 5)])
        #expect(plan.doses.isEmpty)
        #expect(plan.problems.count == 1 && plan.problems[0].sourceRow == 5)
        #expect(plan.problems[0].reason.contains("No readable dose for Tirzepatide"))
    }

    @Test func oldestFirst() {
        let plan = planOf([dose(at: NOW, row: 4), dose(at: NOW - 7 * DAY, row: 3), dose(at: NOW - 14 * DAY, row: 2)])
        #expect(plan.doses.map(\.sourceRow) == [2, 3, 4])
    }

    @Test func duplicates() {
        var plan = planOf([dose()], logs: [(NOW, "tirzepatide")])
        #expect(plan.doses.isEmpty && plan.duplicateDoses == 1)
        #expect(planOf([dose()], logs: [(NOW + 30_000, "tirzepatide")]).duplicateDoses == 1)
        plan = planOf([dose()], logs: [(NOW, "semaglutide")])
        #expect(plan.doses.count == 1 && plan.duplicateDoses == 0)
        #expect(planOf([dose()], logs: [(NOW - 7 * DAY, "tirzepatide")]).doses.count == 1)
        plan = planOf([dose(row: 2), dose(row: 3)])
        #expect(plan.doses.count == 1 && plan.duplicateDoses == 1)
        plan = planOf([weight()], measurements: [(NOW - 3_600_000, 85.6)])
        #expect(plan.weights.isEmpty && plan.duplicateWeights == 1)
        #expect(planOf([weight(kg: 85.6)], measurements: [(NOW, 87.2)]).weights.count == 1)
        #expect(planOf([weight()], measurements: [(NOW, nil)]).weights.count == 1)
    }

    @Test func idempotent() {
        let first = shotsyPlan()
        #expect(!first.doses.isEmpty)
        let second = shotsyPlan(logs: first.doses.map { ($0.at, $0.peptideId) }, measurements: first.weights.map { ($0.at, $0.weightKg) })
        #expect(second.doses.isEmpty && second.weights.isEmpty)
        #expect(second.duplicateDoses == first.doses.count)
        #expect(second.duplicateWeights == first.weights.count)
    }

    @Test func shotsyEndToEnd() {
        let plan = shotsyPlan()
        #expect(plan.doses.count == 25 && plan.weights.count == 14)
        #expect(plan.problems.isEmpty && plan.unresolved.isEmpty)
        #expect(Set(plan.doses.map(\.peptideId)) == ["tirzepatide"])
        let span = planSpan(plan)!
        #expect(year(span.from) == 2025 && month(span.from) == 11)
        #expect(year(span.to) == 2026 && month(span.to) == 7)
        #expect(plan.weights.map(\.weightKg).min() == 85)
        #expect(plan.weights.map(\.weightKg).max() == 94.5)
        #expect(describePlan(plan) == "25 doses and 14 weights")
        #expect(!planIsEmpty(plan))
    }

    @Test func describes() {
        let empty = planOf([])
        #expect(planIsEmpty(empty))
        #expect(describePlan(empty) == "Nothing new to import.")
        #expect(planSpan(empty) == nil)
        #expect(describePlan(planOf([dose(), weight()])) == "1 dose and 1 weight")
        #expect(describePlan(planOf([weight()])) == "1 weight")
        #expect(describePlan(planOf([dose()])) == "1 dose")
    }
}

@Suite struct ImportPipelineTests {
    let options = ImportOptions(peptides: Library.peptides, existingLogs: [], existingMeasurements: [])

    private func read(_ name: String, _ body: String) throws -> ReadResult {
        try readImportFile(name: name, bytes: Array(body.utf8), options: options)
    }
    private func plan(_ r: ReadResult) -> ImportPlan? { if case .table(_, _, _, let p) = r { p } else { nil } }

    @Test func shotsyCsvFile() throws {
        guard case .table(let format, let profile, _, let plan) = try read("shotsy_export.csv", shotsyCsv) else { Issue.record("not a table"); return }
        #expect(format == .csv && profile.id == "shotsy")
        #expect(plan.doses.count == 25 && plan.weights.count == 14)
    }

    @Test func delimitedVariants() throws {
        let tsv = try plan(read("log.tsv", "Date\tMedication\tDose\n2026-07-26\tOzempic\t1 mg"))!
        #expect(tsv.doses[0].peptideId == "semaglutide" && tsv.doses[0].doseMcg == 1000)
        #expect(try plan(read("log.txt", "Date;Medication;Dose\n2026-07-26;Ozempic;1 mg"))!.doses.count == 1)
    }

    @Test func ownExport() throws {
        guard case .benchExport(let data) = try read("bench-export.json", #"{"version":5,"logs":[],"protocols":[],"vials":[],"profiles":[],"settings":{}}"#) else {
            Issue.record("not recognised"); return
        }
        #expect(!data.isEmpty)
    }

    @Test func jsonRows() throws {
        let rows = #"[{"Date":"2026-07-26","Medication":"Ozempic","Dose":"1 mg"},{"Date":"2026-08-02","Medication":"Ozempic","Dose":"1 mg"}]"#
        #expect(try plan(read("export.json", rows))!.doses.count == 2)
        let wrapped = #"{"exportedAt":"2026-07-26","entries":[{"Date":"2026-07-26","Medication":"Ozempic","Dose":"1 mg"}]}"#
        #expect(try plan(read("export.json", wrapped))!.doses.count == 1)
        let sparse = #"[{"Date":"2026-07-26","Medication":"Ozempic","Dose":"1 mg"},{"Date":"2026-08-02","Medication":"Ozempic","Dose":"1 mg","Weight":"85.4"}]"#
        guard case .table(_, _, let table, let p) = try read("export.json", sparse) else { Issue.record("not a table"); return }
        #expect(table.headers.contains("Weight"))
        #expect(p.weights.count == 1)
        #expect(table.headers == ["Date", "Medication", "Dose", "Weight"])
    }

    @Test func xlsx() throws {
        let bytes = zipOf([
            ("xl/workbook.xml", "<workbook/>"),
            ("xl/sharedStrings.xml", "<sst><si><t>Date</t></si><si><t>Medication</t></si><si><t>Dose</t></si><si><t>2026-07-26</t></si><si><t>Ozempic</t></si><si><t>1 mg</t></si></sst>"),
            ("xl/worksheets/sheet1.xml", "<worksheet><sheetData>"
                + #"<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c></row>"#
                + #"<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2" t="s"><v>4</v></c><c r="C2" t="s"><v>5</v></c></row>"#
                + "</sheetData></worksheet>"),
        ])
        guard case .table(let format, _, _, let p) = try readImportFile(name: "log.xlsx", bytes: bytes, options: options) else { Issue.record("not a table"); return }
        #expect(format == .xlsx)
        #expect(p.doses[0].peptideId == "semaglutide" && p.doses[0].doseMcg == 1000)
    }

    @Test func refusals() {
        let cases: [(String, String, String)] = [
            ("old.xls", "anything", "save as .xlsx or .csv"),
            ("broken.json", "{nope", "not valid JSON"),
            ("empty.json", "{}", "no list of records"),
            ("empty.csv", "", "appears to be empty"),
            ("wrong.csv", "colour,size\nred,large", "colour, size"),
            ("fake.xlsx", "Date,Weight\n2026-07-26,85", "not an .xlsx file"),
        ]
        for (name, body, expected) in cases {
            do {
                _ = try read(name, body)
                Issue.record("\(name) should have failed")
            } catch let e as ImportError {
                #expect(e.message.lowercased().contains(expected.lowercased()), "\(name): \(e.message)")
            } catch {
                Issue.record("\(name): wrong error \(error)")
            }
        }
    }

    @Test func respectsExisting() throws {
        let first = try plan(read("shotsy.csv", shotsyCsv))!
        let opts = ImportOptions(peptides: Library.peptides, existingLogs: first.doses.map { ($0.at, $0.peptideId) },
                                 existingMeasurements: first.weights.map { ($0.at, $0.weightKg) })
        guard case .table(_, _, _, let second) = try readImportFile(name: "shotsy.csv", bytes: Array(shotsyCsv.utf8), options: opts) else { return }
        #expect(second.doses.isEmpty && second.weights.isEmpty && second.duplicateDoses == 25)
    }
}

@Suite struct InferFromShotsyTests {
    let logs: [DoseLog]
    let inferred: InferredProtocol

    init() {
        let t = toTable(parseDelimited(shotsyCsv))
        let read = shotsyProfile.read(t.records, t.headers)
        let plan = buildImportPlan(records: read.records, problems: read.problems, peptides: Library.peptides, existingLogs: [], existingMeasurements: [])
        logs = plan.doses.map { DoseLog(id: "", profileId: "", peptideId: $0.peptideId, at: $0.at, doseMcg: $0.doseMcg, route: .subcutaneous, site: $0.site) }
        inferred = inferProtocol(logs, resolve: { Library.byId[$0] })!
    }

    @Test func weeklyTirzepatide() {
        #expect(inferred.peptideId == "tirzepatide")
        #expect(inferred.schedule.kind == .daysOfWeek)
        #expect(inferred.confidence == .clear)
        // Every jab in the file is a Sunday.
        #expect(inferred.schedule.daysOfWeek == [0])
        #expect(inferred.doseMcg == 10_000)
    }

    @Test func recentRotation() {
        #expect(inferred.sites.map(\.rawValue).sorted() == ["abdomen-ll", "abdomen-lr", "abdomen-ul", "abdomen-ur", "arm-l"])
        let wide = inferProtocol(logs, resolve: { Library.byId[$0] }, siteWindow: 25)!
        #expect(wide.sites.contains("abdomen-um") && wide.sites.contains("abdomen-lm"))
        #expect(wide.sites.count == 7)
    }

    @Test func startAndSummary() {
        #expect(month(inferred.startedAt) == 2 && dayOfMonth(inferred.startedAt) == 8)
        #expect(inferred.doseCount == 25)
        #expect(inferred.summary.hasPrefix("10 mg of Tirzepatide every Sunday, from 25 logged doses"))
    }
}
