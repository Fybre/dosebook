import SwiftUI
import BenchCore
import BenchStore

/// Create a protocol, or edit one. Fields the form does not ask about
/// (`active`, `endedAt`, `notes`) are carried through untouched.
struct ProtocolForm: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var initial: DoseProtocol?

    enum PlanMode: String { case fixed, titration, phases }
    static let existingTitration = "__existing__"

    @State private var peptideId = ""
    @State private var name = ""
    @State private var doseMcg: Double = 500
    @State private var kind: ScheduleKind = .intervalDays
    @State private var intervalDays: Double = 7
    @State private var daysOfWeek: [Int] = [1]
    @State private var times: [String] = ["09:00"]
    @State private var startedAt: Date = Date()
    @State private var cycleOn: Double = 0
    @State private var cycleOff: Double = 0
    @State private var sites: [InjectionSite] = []
    @State private var planMode: PlanMode = .fixed
    @State private var phases: [ProtocolPhase] = []
    @State private var doseUnit: DoseUnit = .mcg
    @State private var titrationId = ""
    @State private var route: Route = .subcutaneous
    @State private var loaded = false
    @State private var addingCompound = false

    private var peptides: [Peptide] { store.data.allPeptides }
    private var peptide: Peptide? { store.data.peptide(peptideId) }
    private var titration: TitrationPlan? { peptide?.titrations?.first { $0.id == titrationId } }
    private var keepingExisting: Bool { planMode == .titration && titrationId == Self.existingTitration && !(initial?.titration ?? []).isEmpty }
    private var titrationSteps: [TitrationStep]? {
        guard planMode == .titration else { return nil }
        return titration?.steps ?? (keepingExisting ? initial?.titration : nil)
    }
    private var titrationAutoAdvance: Bool { titration != nil ? true : (keepingExisting ? initial?.titrationAutoAdvance ?? false : false) }
    private var lockedDose: Double? { planMode == .phases ? phases.first?.doseMcg : titrationSteps?.first?.doseMcg }
    private var routes: [Route] { routeChoices(peptide?.routes ?? [], store.data.mine.vials, peptideId, peptide?.preparation) }

    private var schedule: Schedule {
        let clean = Array(Set(times.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
        return Schedule(kind: kind,
                        intervalDays: kind == .intervalDays ? intervalDays : nil,
                        daysOfWeek: kind == .daysOfWeek ? daysOfWeek : nil,
                        timeOfDay: kind == .asNeeded ? nil : (clean.first ?? "09:00"),
                        timesOfDay: kind == .asNeeded || clean.count < 2 ? nil : clean,
                        cycleWeeksOn: cycleOn > 0 ? cycleOn : nil,
                        cycleWeeksOff: cycleOff > 0 ? cycleOff : nil)
    }

    private func sameSchedule(_ a: Schedule, _ b: Schedule) -> Bool {
        a.kind == b.kind && a.intervalDays == b.intervalDays && scheduleTimes(a) == scheduleTimes(b)
            && a.cycleWeeksOn == b.cycleWeeksOn && a.cycleWeeksOff == b.cycleWeeksOff && (a.daysOfWeek ?? []) == (b.daysOfWeek ?? [])
    }

    private func samePhases(_ a: [ProtocolPhase]?, _ b: [ProtocolPhase]?) -> Bool {
        let x = a ?? [], y = b ?? []
        guard x.count == y.count else { return false }
        return zip(x, y).allSatisfy { p, q in
            guard p.doseMcg == q.doseMcg, p.weeks == q.weeks else { return false }
            switch (p.schedule, q.schedule) {
            case (nil, nil): return true
            case let (s?, r?): return sameSchedule(s, r)
            default: return false
            }
        }
    }

    /// The one edit that reaches backwards: adherence replays the schedule over past dates.
    private var rewritesHistory: Bool {
        guard let initial else { return false }
        return !sameSchedule(schedule, initial.schedule) || startedAt.millis != initial.startedAt
            || !samePhases(planMode == .phases ? phases : nil, initial.phases)
    }

    private var draft: DoseProtocol {
        DoseProtocol(id: initial?.id ?? "draft", profileId: initial?.profileId ?? "draft", peptideId: peptideId,
                     name: name.isEmpty ? "draft" : name, active: initial?.active ?? true, startedAt: startedAt.millis,
                     doseMcg: lockedDose ?? doseMcg, route: route, schedule: schedule, titration: titrationSteps,
                     titrationAutoAdvance: titrationAutoAdvance, phases: planMode == .phases ? phases : nil)
    }

    var body: some View {
        Form {
            Section(t("plan_peptide")) {
                Picker(t("plan_peptide"), selection: Binding(get: { peptideId }, set: pick)) {
                    ForEach(peptides) { Text($0.name).tag($0.id) }
                }
                Button { addingCompound = true } label: { Label(t("add_compound_inline"), systemImage: "plus") }
                if routes.count > 1 {
                    Picker(t("plan_route"), selection: $route) { ForEach(routes, id: \.self) { Text($0.label).tag($0) } }
                    Text(route == .intranasal ? t("plan_route_hint_nasal") : t("plan_route_hint")).font(.caption).foregroundStyle(.secondary)
                }
            }

            Section {
                Picker(t("plan_dose_plan"), selection: $planMode) {
                    Text(t("plan_fixed_short")).tag(PlanMode.fixed)
                    Text(t("plan_titration_short")).tag(PlanMode.titration)
                    Text(t("plan_by_weeks")).tag(PlanMode.phases)
                }
                .pickerStyle(.segmented)
                if planMode == .titration {
                    if !(peptide?.titrations ?? []).isEmpty || keepingExisting {
                        Picker(t("plan_titration_plan"), selection: $titrationId) {
                            Text(t("plan_no_titration")).tag("")
                            if !(initial?.titration ?? []).isEmpty {
                                Text(t("plan_keep_existing", ["n": .number(Double(initial!.titration!.count))])).tag(Self.existingTitration)
                            }
                            ForEach(peptide?.titrations ?? []) { Text($0.name).tag($0.id) }
                        }
                        if let note = titration?.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                    } else {
                        Text(t("plan_no_published_titration", ["name": .string(peptide?.name ?? t("plan_this_compound"))])).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            } header: { Text(t("plan_how_dose_decided")) } footer: {
                Text(t(planMode == .phases ? "plan_mode_hint_phases" : planMode == .titration ? "plan_mode_hint_titration" : "plan_mode_hint_fixed"))
            }

            if planMode == .phases {
                Section(t("plan_week_by_week")) {
                    PhaseEditorView(phases: $phases, unit: $doseUnit, protocolSchedule: schedule)
                }
            }

            Section {
                if planMode != .phases {
                    if let locked = lockedDose {
                        LabeledContent(t("plan_starting_dose"), value: formatDose(locked))
                        Text(t("plan_dose_set_by_plan", ["dose": .string(formatDose(locked))])).font(.caption).foregroundStyle(.secondary)
                    } else {
                        AmountRow(label: t("plan_dose"), value: $doseMcg, range: 0...10_000_000)
                        if let r = peptide?.doseRanges.first {
                            Text(t("plan_dose_typical", ["low": .string(formatDose(r.lowMcg)), "high": .string(formatDose(r.highMcg))])).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                DatePicker(t("plan_start_date"), selection: $startedAt, displayedComponents: .date)
            }

            Section {
                Picker(t("plan_schedule_type"), selection: $kind) {
                    Text(t("plan_daily")).tag(ScheduleKind.daily)
                    Text(t("plan_every_n_days_short")).tag(ScheduleKind.intervalDays)
                    Text(t("plan_set_days")).tag(ScheduleKind.daysOfWeek)
                    Text(t("plan_as_needed")).tag(ScheduleKind.asNeeded)
                }
                .pickerStyle(.segmented)
                if kind == .intervalDays { NumberRow(label: t("plan_interval"), value: $intervalDays, suffix: t("days"), range: 1...90) }
                if kind == .daysOfWeek { WeekdayPicker(days: $daysOfWeek) }
                if kind != .asNeeded {
                    TimesOfDayEditor(times: $times, dailyMcg: lockedDose == nil ? doseMcg : nil)
                    NumberRow(label: t("plan_weeks_on"), value: $cycleOn, range: 0...52)
                    NumberRow(label: t("plan_weeks_off"), value: $cycleOff, range: 0...52)
                    Text(t("ios_plan_weeks_on_hint")).font(.caption).foregroundStyle(.secondary)
                }
            } header: { Text(t("plan_how_often")) } footer: { if planMode == .phases { Text(t("plan_how_often_hint")) } }

            if routeHasSite(route) {
                Section {
                    SiteMapView(logs: [], selected: Set(sites), multi: true, onSelect: toggleSite).frame(maxWidth: .infinity)
                    if !sites.isEmpty { Button(t("plan_clear_sites"), role: .destructive) { sites = [] } }
                } header: { Text(t("plan_sites_label")) } footer: {
                    Text(sites.isEmpty ? t("plan_sites_hint_empty") : t("plan_sites_pinned", ["n": .number(Double(sites.count))]))
                }
            }

            Section {
                TextField(peptide.map { t("plan_name_example", ["name": .string($0.name)]) } ?? t("plan_name_empty"), text: $name)
            } header: { Text(t("plan_name_it")) } footer: { Text(t("plan_name_hint")) }

            Section { ProjectionPreviewView(protocol_: draft, peptide: peptide) }

            if rewritesHistory {
                Section {
                    Text(t("plan_rewrite_title")).bold() + Text(" " + t("plan_rewrite_body"))
                }
                .font(.footnote)
            }
        }
        .navigationTitle(initial == nil ? t("plan_new_protocol_form") : t("plan_edit_protocol"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(initial == nil ? t("plan_create_protocol") : t("plan_save_changes"), action: save).disabled(peptideId.isEmpty)
            }
        }
        .sheet(isPresented: $addingCompound) {
            NavigationStack { CustomCompoundForm(onCreated: { pick($0.id) }) }
        }
        .onAppear(perform: load)
        .onChange(of: routes) { _, r in if !r.contains(route) { route = r.first ?? .subcutaneous } }
    }

    private func toggleSite(_ s: InjectionSite) {
        sites = sites.contains(s) ? sites.filter { $0 != s } : sites + [s]
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let p = initial else {
            if let first = peptides.first { pick(first.id) }
            phases = [ProtocolPhase(step: 1, doseMcg: 500, weeks: 4)]
            return
        }
        peptideId = p.peptideId; name = p.name; doseMcg = p.doseMcg; kind = p.schedule.kind
        intervalDays = p.schedule.intervalDays ?? 7; daysOfWeek = p.schedule.daysOfWeek ?? [1]
        times = scheduleTimes(p.schedule); startedAt = Date(millis: p.startedAt)
        cycleOn = p.schedule.cycleWeeksOn ?? 0; cycleOff = p.schedule.cycleWeeksOff ?? 0
        sites = p.sites ?? []; route = p.route
        planMode = !(p.phases ?? []).isEmpty ? .phases : !(p.titration ?? []).isEmpty ? .titration : .fixed
        phases = p.phases ?? [ProtocolPhase(step: 1, doseMcg: p.doseMcg, weeks: 4)]
        doseUnit = phases.contains { $0.doseMcg >= 1000 } ? .mg : .mcg
        if let steps = p.titration, !steps.isEmpty {
            titrationId = store.data.peptide(p.peptideId)?.titrations?.first { $0.steps == steps }?.id ?? Self.existingTitration
        }
    }

    /// A new compound brings its typical dose and frequency with it.
    private func pick(_ id: String) {
        peptideId = id
        titrationId = ""
        guard let range = store.data.peptide(id)?.doseRanges.first else { return }
        doseMcg = jsRound((range.lowMcg + range.highMcg) / 2)
        if range.perWeek >= 7 { kind = .daily }
        else if range.perWeek > 0 { kind = .intervalDays; intervalDays = max(1, jsRound(7 / range.perWeek)) }
    }

    /// Steps 1, 2, 3 on the way out, and each band's times tidied.
    private func renumbered(_ phases: [ProtocolPhase]) -> [ProtocolPhase] {
        phases.enumerated().map { i, p in
            var out = p
            out.step = i + 1
            if let ts = p.schedule?.timesOfDay {
                let clean = Array(Set(ts.map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })).sorted()
                out.schedule?.timeOfDay = clean.first ?? p.schedule?.timeOfDay ?? "09:00"
                out.schedule?.timesOfDay = clean.isEmpty ? nil : clean
            }
            return out
        }
    }

    private func save() {
        var p = initial ?? DoseProtocol(id: "", profileId: "", peptideId: peptideId, name: "", startedAt: 0, doseMcg: 0, route: route, schedule: schedule)
        let trimmed = name.trimmingCharacters(in: .whitespaces)
        p.peptideId = peptideId
        p.name = trimmed.isEmpty ? t("plan_name_example", ["name": .string(peptide?.name ?? t("plan_new_short"))]) : trimmed
        p.startedAt = startedAt.millis
        p.doseMcg = lockedDose ?? doseMcg
        p.route = route
        p.schedule = schedule
        // Stamped only when the timing moved, so a rename does not make the past unknowable.
        p.scheduleChangedAt = rewritesHistory ? nowMillis() : initial?.scheduleChangedAt
        p.titration = titrationSteps
        p.titrationAutoAdvance = titrationAutoAdvance
        p.phases = planMode == .phases ? renumbered(phases) : nil
        p.sites = sites.isEmpty ? nil : sites
        if let initial {
            store.mutate { $0.updateProtocol(initial.id) { $0 = p } }
        } else {
            store.mutate { $0.addProtocol(p) }
        }
        dismiss()
    }
}
