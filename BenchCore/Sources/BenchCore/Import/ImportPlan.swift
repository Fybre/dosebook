import Foundation

// Port of src/lib/import/plan.ts. Canonical records into a plan to inspect
// before committing: what would be added, what is already there, what failed.

/// Two doses of one compound within a minute are the same event.
public let DOSE_MATCH_MS: Double = 60_000
/// Weights compare by day, since a bare date sits at midnight.
public let WEIGHT_MATCH_MS: Double = 12 * 60 * 60_000
public let WEIGHT_MATCH_KG: Double = 0.05

public struct PlannedDose: Equatable, Sendable {
    public var at: Millis
    public var peptideId: String
    public var peptideName: String
    public var doseMcg: Double
    public var site: InjectionSite?
    public var notes: String?
    public var sourceRow: Int
}

public struct PlannedWeight: Equatable, Sendable {
    public var at: Millis
    public var weightKg: Double
    public var sourceRow: Int
}

public struct ImportPlan: Equatable, Sendable {
    public var doses: [PlannedDose]
    public var weights: [PlannedWeight]
    public var duplicateDoses: Int
    public var duplicateWeights: Int
    public var problems: [RowProblem]
    /// Names in the file that no library entry matched, with their rows.
    public var unresolved: [(label: String, rows: [Int])]

    public static func == (a: ImportPlan, b: ImportPlan) -> Bool {
        a.doses == b.doses && a.weights == b.weights && a.duplicateDoses == b.duplicateDoses && a.duplicateWeights == b.duplicateWeights
            && a.problems == b.problems && a.unresolved.map(\.label) == b.unresolved.map(\.label) && a.unresolved.map(\.rows) == b.unresolved.map(\.rows)
    }
}

public func buildImportPlan(records: [CanonicalRecord], problems: [RowProblem], peptides: [Peptide],
                            existingLogs: [(at: Millis, peptideId: String)], existingMeasurements: [(at: Millis, weightKg: Double?)]) -> ImportPlan {
    var doses: [PlannedDose] = [], weights: [PlannedWeight] = []
    var allProblems = problems
    var unresolved = OrderedMap<String, [Int]>()
    var duplicateDoses = 0, duplicateWeights = 0

    func doseExists(_ at: Millis, _ id: String) -> Bool {
        existingLogs.contains { $0.peptideId == id && abs($0.at - at) <= DOSE_MATCH_MS }
            || doses.contains { $0.peptideId == id && abs($0.at - at) <= DOSE_MATCH_MS }
    }
    func weightExists(_ at: Millis, _ kg: Double) -> Bool {
        existingMeasurements.contains { m in m.weightKg.map { abs(m.at - at) <= WEIGHT_MATCH_MS && abs($0 - kg) <= WEIGHT_MATCH_KG } ?? false }
            || weights.contains { abs($0.at - at) <= WEIGHT_MATCH_MS && abs($0.weightKg - kg) <= WEIGHT_MATCH_KG }
    }

    for record in records {
        switch record {
        case .weight(let at, let kg, let row):
            if weightExists(at, kg) { duplicateWeights += 1; continue }
            weights.append(PlannedWeight(at: at, weightKg: kg, sourceRow: row))
        case .dose(let at, let label, let doseMcg, let site, let notes, let row):
            guard let peptide = resolvePeptide(label, peptides) else {
                unresolved[label] = (unresolved[label] ?? []) + [row]
                continue
            }
            guard let dose = doseMcg, dose > 0 else {
                allProblems.append(RowProblem(sourceRow: row, reason: "No readable dose for \(peptide.name). A dose in mg or mcg is needed, syringe units cannot be converted without the vial's concentration."))
                continue
            }
            if doseExists(at, peptide.id) { duplicateDoses += 1; continue }
            doses.append(PlannedDose(at: at, peptideId: peptide.id, peptideName: peptide.name, doseMcg: dose, site: site, notes: notes, sourceRow: row))
        }
    }
    return ImportPlan(doses: doses.stableSorted { $0.at < $1.at }, weights: weights.stableSorted { $0.at < $1.at },
                      duplicateDoses: duplicateDoses, duplicateWeights: duplicateWeights,
                      problems: allProblems.stableSorted { $0.sourceRow < $1.sourceRow },
                      unresolved: unresolved.entries.map { ($0.key, $0.value) })
}

public func planIsEmpty(_ plan: ImportPlan) -> Bool { plan.doses.isEmpty && plan.weights.isEmpty }

/// One-line English summary, as the original's.
public func describePlan(_ plan: ImportPlan) -> String {
    var bits: [String] = []
    if !plan.doses.isEmpty { bits.append("\(plan.doses.count) dose\(plan.doses.count == 1 ? "" : "s")") }
    if !plan.weights.isEmpty { bits.append("\(plan.weights.count) weight\(plan.weights.count == 1 ? "" : "s")") }
    return bits.isEmpty ? "Nothing new to import." : bits.joined(separator: " and ")
}

/// The date range the plan covers.
public func planSpan(_ plan: ImportPlan) -> (from: Millis, to: Millis)? {
    let times = plan.doses.map(\.at) + plan.weights.map(\.at)
    guard let lo = times.min(), let hi = times.max() else { return nil }
    return (lo, hi)
}
