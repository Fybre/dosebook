import Foundation

// Injectly (iPhone) exports one CSV per kind: medications, logs, weight and
// profile. Logs and weight are history and go through the ordinary import plan.
// The medications file is the setup: what each medication is, how it is made
// up and when it is taken. This turns it into compounds, blends and protocols,
// leaving anything uncertain for the person to settle before it is saved.

/// One row of Injectly's medications file.
public struct InjectlyMedication: Equatable, Sendable {
    public struct Part: Equatable, Sendable { public var name: String; public var amountMg: Double?; public var primary: Bool }
    public struct Reminder: Equatable, Sendable { public var frequency: String; public var time: String?; public var days: [Int]? }
    public var name: String
    public var route: Route
    public var vialMg: Double?
    public var bacMl: Double?
    public var doseMcg: Double?
    /// Primary part first.
    public var parts: [Part]
    public var reminders: [Reminder]
    public var createdAt: Millis?
}

/// The kinds of file an Injectly export holds, told apart by their headers.
public enum InjectlyFileKind: Sendable { case medications, logs, weight, profile }

public func injectlyFileKind(_ headers: [String]) -> InjectlyFileKind? {
    let seen = Set(headers.map(normaliseHeader))
    if seen.isSuperset(of: ["medication name", "vial mg", "bac ml"]) { return .medications }
    if seen.isSuperset(of: ["medication name", "dose in mcg", "time logged"]) { return .logs }
    if seen.isSuperset(of: ["weight", "measured at"]) { return .weight }
    if seen == ["field", "value"] { return .profile }
    return nil
}

private func injectlyRoute(_ s: String?) -> Route {
    switch (s ?? "").lowercased().replacingOccurrences(of: " ", with: "") {
    case "im", "intramuscular": .intramuscular
    case "oral": .oral
    case "nasal", "intranasal": .intranasal
    case "topical": .topical
    case "iv", "intravenous": .intravenous
    default: .subcutaneous
    }
}

private func jsonArray(_ cell: String?) -> [[(String, OrderedJSON)]] {
    guard let cell, !isBlank(cell), case .array(let items)? = OrderedJSON.parse(cell) else { return [] }
    return items.compactMap { if case .object(let o) = $0 { o } else { nil } }
}

private func field(_ o: [(String, OrderedJSON)], _ key: String) -> OrderedJSON? { o.first { $0.0 == key }?.1 }
private func str(_ v: OrderedJSON?) -> String? { if case .string(let s)? = v { s } else { nil } }
private func num(_ v: OrderedJSON?) -> Double? { if case .number(let n)? = v { n } else { nil } }

public func parseInjectlyMedications(_ table: ImportTable) -> [InjectlyMedication] {
    table.records.compactMap { r in
        guard let name = r["Medication Name"]?.trimmingCharacters(in: .whitespacesAndNewlines), !name.isEmpty else { return nil }
        let parts = jsonArray(r["Blend Constituents (JSON)"]).compactMap { o -> InjectlyMedication.Part? in
            guard let n = str(field(o, "medicationName")) else { return nil }
            var primary = false
            if case .bool(let b)? = field(o, "isPrimary") { primary = b }
            return .init(name: n, amountMg: num(field(o, "amountMg")), primary: primary)
        }
        let reminders = jsonArray(r["Reminders (JSON)"]).map { o in
            InjectlyMedication.Reminder(frequency: str(field(o, "frequency")) ?? "", time: str(field(o, "time")),
                                        days: { if case .array(let a)? = field(o, "specificDays") { return a.compactMap(num).map { Int($0) } }; return nil }())
        }
        return InjectlyMedication(name: name, route: injectlyRoute(r["Route"]), vialMg: parseNumber(r["Vial mg"]),
                                  bacMl: parseNumber(r["BAC ml"]), doseMcg: parseNumber(r["Dose mcg"]),
                                  parts: parts.filter(\.primary) + parts.filter { !$0.primary }, reminders: reminders,
                                  createdAt: parseDate(r["Created At"]))
    }
}

/// Injectly's reminders as one schedule. Days are 1 Monday to 7 Sunday, as Injectly
/// numbers them (weekdays are 1 to 5); the app counts Sunday as 0. A schedule it
/// cannot read is left as needed, with a note, rather than guessed.
public func injectlySchedule(_ reminders: [InjectlyMedication.Reminder]) -> (schedule: Schedule, note: String?) {
    let times = Array(Set(reminders.compactMap(\.time).filter { parseClock($0) != nil })).sorted()
    guard !reminders.isEmpty, !times.isEmpty else {
        return (Schedule(kind: .asNeeded), reminders.isEmpty ? nil : "Injectly gave no reminder times, so this is set as needed. Set its days and times in Plan.")
    }
    let kinds = Set(reminders.map { $0.frequency.lowercased() })
    let days = Set(reminders.flatMap { $0.days ?? [] }.map { $0 % 7 }).sorted()
    let timed: (Schedule) -> Schedule = { s in var s = s; if times.count == 1 { s.timeOfDay = times[0] } else { s.timesOfDay = times }; return s }
    if kinds == ["daily"] { return (timed(Schedule(kind: .daily)), nil) }
    if !days.isEmpty, kinds.isSubset(of: ["weekly", "weekdays", "specificdays", "specific_days", "custom", "daily"]) {
        return (timed(Schedule(kind: .daysOfWeek, daysOfWeek: days)), nil)
    }
    if kinds == ["weekdays"] { return (timed(Schedule(kind: .daysOfWeek, daysOfWeek: [1, 2, 3, 4, 5])), nil) }
    return (Schedule(kind: .asNeeded), "Injectly's schedule \"\(reminders.map(\.frequency).joined(separator: ", "))\" is not one the app reads yet, so this is set as needed. Set its days and times in Plan.")
}

/// Library compounds a name could mean: an exact match, else every compound whose
/// name or alias begins with it ("CJC-1295" could be either CJC-1295 entry).
public func candidatePeptides(_ label: String, _ peptides: [Peptide]) -> [Peptide] {
    if let p = resolvePeptide(label, peptides) { return [p] }
    let clean = label.lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    guard clean.u16Count >= 3 else { return [] }
    return peptides.filter { p in
        !isBlend(p) && ([p.name] + p.aka).map { $0.lowercased() }.contains { $0.hasPrefix(clean + " ") || $0 == clean }
    }
}

/// What importing one medication would do, before it is saved.
public struct InjectlyItem: Equatable, Sendable {
    public struct Part: Equatable, Sendable {
        public var name: String
        public var mgPerVial: Double?
        public var candidates: [String]
        /// The library compound this part is, or nil to keep it as a name only.
        public var chosen: String?
    }
    public enum Compound: Equatable, Sendable {
        /// Already in the library or among your own compounds.
        case existing(String)
        /// A blend to add to your own compounds.
        case newBlend([Part])
        /// A single compound the library does not have, unless one is chosen.
        case newCompound(candidates: [String], chosen: String?)
    }
    public var medication: InjectlyMedication
    public var compound: Compound
    public var schedule: Schedule
    /// The day's total, as a protocol holds it: Injectly's per-injection dose times the
    /// day's injections, and for a blend the whole blend rather than its first part.
    public var doseMcg: Double
    public var notes: [String]
    /// Already planned with an active protocol here, so off by default.
    public var alreadyPlanned: Bool
}

/// Read the medications into items. `logs` give each protocol its true start.
public func planInjectlySetup(_ meds: [InjectlyMedication], peptides: [Peptide], activeProtocols: [DoseProtocol],
                              logs: [CanonicalRecord] = []) -> [InjectlyItem] {
    meds.map { m in
        var notes: [String] = []
        let compound: InjectlyItem.Compound
        if let p = resolvePeptide(m.name, peptides), m.parts.isEmpty || isBlend(p) {
            compound = .existing(p.id)
        } else if !m.parts.isEmpty {
            compound = .newBlend(m.parts.map { part in
                let c = candidatePeptides(part.name, peptides).map(\.id)
                return .init(name: part.name, mgPerVial: part.amountMg, candidates: c, chosen: c.count == 1 ? c[0] : nil)
            })
        } else {
            let c = candidatePeptides(m.name, peptides).map(\.id)
            compound = .newCompound(candidates: c, chosen: c.count == 1 ? c[0] : nil)
        }
        let (schedule, note) = injectlySchedule(m.reminders)
        if let note { notes.append(note) }
        var dose = m.doseMcg ?? 0
        // Injectly's blend dose is its first part; the app's is the whole blend.
        let masses = m.parts.compactMap(\.amountMg)
        if !m.parts.isEmpty, masses.count == m.parts.count, let first = masses.first, first > 0 {
            dose = jsFixed(dose * masses.reduce(0, +) / first, 6)
        }
        // Injectly's dose is one injection; a protocol's is the day, split across its times.
        if schedule.kind != .asNeeded { dose = jsFixed(dose * Double(max(1, scheduleTimes(schedule).count)), 6) }
        let id: String? = { if case .existing(let id) = compound { return id }; return nil }()
        let planned = id.map { pid in activeProtocols.contains { $0.peptideId == pid } } ?? false
        return InjectlyItem(medication: m, compound: compound, schedule: schedule, doseMcg: dose, notes: notes, alreadyPlanned: planned)
    }
}

/// The compounds an item adds, and its protocol, ready to save. The protocol
/// starts at the medication's first logged dose, else when Injectly made it.
public func injectlyResult(_ item: InjectlyItem, peptides: [Peptide], logs: [CanonicalRecord], now: Millis = nowMillis())
    -> (newPeptide: Peptide?, protocol_: DoseProtocol) {
    let m = item.medication
    var newPeptide: Peptide?
    let peptideId: String
    switch item.compound {
    case .existing(let id):
        peptideId = id
    case .newCompound(_, let chosen?):
        peptideId = chosen
    case .newCompound(_, nil):
        var d = CustomDraft(name: m.name, routes: [m.route], vialSizeMg: m.vialMg)
        d.notes = "Brought across from Injectly."
        newPeptide = draftToPeptide(d)
        peptideId = newPeptide!.id
    case .newBlend(let parts):
        var d = CustomDraft(name: m.name, category: .blend, routes: [m.route])
        d.components = parts.map { p in
            BlendComponent(peptideId: p.chosen, name: p.chosen.flatMap { id in peptides.first { $0.id == id }?.name } ?? p.name, mgPerVial: p.mgPerVial)
        }
        newPeptide = draftToPeptide(d)
        peptideId = newPeptide!.id
    }
    let first = logs.compactMap { r -> Millis? in if case .dose(let at, let label, _, _, _, _) = r, label == m.name { return at }; return nil }.min()
    let start = startOfLocalDay(first ?? m.createdAt ?? now)
    let p = DoseProtocol(id: "", profileId: "", peptideId: peptideId, name: m.name, startedAt: start, doseMcg: item.doseMcg,
                         route: m.route, schedule: item.schedule, notes: "Brought across from Injectly.")
    return (newPeptide, p)
}

/// The vial a medication was being drawn from, as Injectly describes it: the
/// whole vial (every part of a blend, as Bench doses blends whole) and the water
/// in it. Nil without both, or for a route with no vial to draw from.
public func injectlyInUseVial(_ m: InjectlyMedication) -> (strengthMg: Double, waterMl: Double)? {
    guard routeHasSite(m.route), let water = m.bacMl, water > 0 else { return nil }
    let amounts = m.parts.compactMap(\.amountMg)
    let strength = m.parts.count > 1 && amounts.count == m.parts.count ? amounts.reduce(0, +) : m.vialMg
    guard let strength, strength > 0 else { return nil }
    return (strength, water)
}
