import SwiftUI
import BenchCore
import BenchStore

private func evidenceTone(_ e: EvidenceLevel) -> Tone {
    switch e {
    case .approved: .leaf
    case .clinical: .sky
    case .preliminary, .preclinical: .tangerine
    default: .rose
    }
}

/// One compound: how it works, what it does in the body, doses, and sources.
struct PeptideDetailView: View {
    @Environment(AppStore.self) private var store
    var peptideId: String

    var body: some View {
        if let p = store.data.peptide(peptideId) {
            content(p)
        } else {
            ContentUnavailableView(t("pep_not_found", ["slug": .string(peptideId)]), systemImage: "questionmark.circle")
        }
    }

    private func content(_ p: Peptide) -> some View {
        let data = store.data
        let mine = data.halfLifeOverrides[p.id]
        let weekly = p.doseRanges.first?.perWeek ?? 0
        let intervalHours = weekly > 0 ? 7 * 24 / weekly : 0
        return ScrollViewReader { proxy in
        GroupedList {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Pill(text: p.category.label)
                    if !p.aka.isEmpty { Text(t("pep_also_known", ["names": .string(p.aka.joined(separator: ", "))])).font(.footnote).foregroundStyle(.secondary) }
                    Text(p.summary).font(.body).foregroundStyle(.secondary)
                }
            }

            if let banner = p.cautionBanner {
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        CalloutText(t("pep_read_first"), bold: true)
                        CalloutText(banner)
                    }
                    .font(.footnote).callout(.rose)
                }
            }

            Section(t("pep_how_it_works")) {
                Text(p.mechanism).font(.subheadline).foregroundStyle(.secondary)
                FlowLayout(spacing: 6) { ForEach(p.routes, id: \.self) { Pill(text: $0.label) } }
            }

            Section {
                if isBlend(p) {
                    blendContent(p)
                } else {
                    pkContent(p, mine: mine, intervalHours: intervalHours)
                    // Offered only where the library has no published human figure.
                    if p.halfLifeHours == nil { YourHalfLifeRow(peptideId: p.id, name: p.name) }
                }
                if let note = p.halfLifeNote { Text(note).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text(t("pep_in_the_body")).id("body") }

            Section(t("note_heading")) { CompoundNotesRow(peptideId: p.id, name: p.name) }

            if let timeline = p.timeline, !timeline.isEmpty {
                Section(t("pep_what_happens")) {
                    ForEach(timeline, id: \.fromHours) { phase in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            Text("\(formatDuration(phase.fromHours)), \(formatDuration(phase.toHours))")
                                .font(.caption.monospacedDigit()).foregroundStyle(Tone.tangerine.color).frame(width: 96, alignment: .leading)
                            Text(phase.label).font(.subheadline).foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Section(t("pep_doses")) {
                ForEach(Array(p.doseRanges.enumerated()), id: \.offset) { _, d in
                    VStack(alignment: .leading, spacing: 4) {
                        FlowLayout(spacing: 8) {
                            Text(d.lowMcg == d.highMcg ? formatDose(d.lowMcg) : "\(formatDose(d.lowMcg)), \(formatDose(d.highMcg))").font(.body.monospacedDigit())
                            Text(d.frequency).font(.subheadline).foregroundStyle(.secondary)
                            Pill(text: d.evidence.label, tone: evidenceTone(d.evidence))
                        }
                        Text(d.evidence.detail).font(.caption2).foregroundStyle(.tertiary)
                        if let note = d.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                    }
                }
            }

            ForEach(p.titrations ?? []) { plan in
                let starts = titrationStepStartWeeks(plan.steps)
                Section {
                    Text(t("pep_titration_meta", ["source": .string(plan.source), "weeks": .string(t("count_weeks", ["n": .number(titrationTotalWeeks(plan.steps))]))]))
                        .font(.caption).foregroundStyle(.secondary)
                    ForEach(Array(plan.steps.enumerated()), id: \.offset) { i, s in
                        HStack(alignment: .firstTextBaseline, spacing: 12) {
                            let first = jsNumberString(starts[i] + 1), last = jsNumberString(starts[i] + s.weeks)
                            Text(t("pep_week_abbrev", ["range": .string(s.weeks > 1 ? "\(first), \(last)" : first)]))
                                .font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 72, alignment: .leading)
                            Text(formatDose(s.doseMcg)).font(.subheadline.monospacedDigit()).foregroundStyle(Tone.tangerine.color).frame(width: 80, alignment: .leading)
                            Text(s.note ?? t("count_weeks", ["n": .number(s.weeks)])).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                    if let note = plan.note { Text(note).font(.footnote).foregroundStyle(.secondary) }
                } header: { Text(plan.name) }
            }

            if isBlend(p) { BlendPanel(blend: p) }

            if !p.vialSizesMg.isEmpty {
                Section(t("pep_vial_sizes")) {
                    FlowLayout(spacing: 6) { ForEach(p.vialSizesMg, id: \.self) { Pill(text: "\(jsNumberString($0)) mg", tone: .tangerine) } }
                    if let days = p.reconstitutedDays {
                        Text(t("pep_reconstituted", ["days": .string(t("count_days", ["n": .number(days)]))])).font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }

            Section(t("pep_side_effects")) {
                ForEach(p.sideEffects, id: \.self) { Label($0, systemImage: "circle.fill").labelStyle(BulletLabel(tone: nil)) }
            }
            Section(t("pep_cautions")) {
                ForEach(p.contraindications, id: \.self) { Label($0, systemImage: "circle.fill").labelStyle(BulletLabel(tone: .rose)) }
            }
            Section(t("pep_status")) { Text(p.status).font(.subheadline).foregroundStyle(.secondary) }
            Section(t("pep_sources")) {
                ForEach(p.citations, id: \.url) { c in
                    if let url = URL(string: c.url) {
                        Link(destination: url) { Label(c.label, systemImage: "arrow.up.right.square").font(.footnote) }
                    } else {
                        Text(c.label).font(.footnote)
                    }
                }
            }
            Section { Text(t("pep_disclaimer")).font(.caption).foregroundStyle(.secondary) }
        }
        .debugAnchor(proxy)
        }
        .navigationTitle(p.name)
    }

    @ViewBuilder private func pkContent(_ p: Peptide, mine: HalfLifeOverride?, intervalHours: Double) -> some View {
        let curve = curveFor(p, yours: mine)
        if let hl = p.halfLifeHours {
            Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 12) {
                GridRow {
                    StatView(label: t("pep_half_life"), value: formatHalfLife(hl))
                    if let tmax = p.tmaxHours { StatView(label: t("pep_time_to_peak"), value: formatDuration(tmax), tone: .tangerine) }
                }
                GridRow {
                    StatView(label: t("pep_ninety_gone"), value: formatDuration(hoursUntilFraction(0.1, hl)), tone: .sky)
                    if intervalHours > 0 {
                        VStack(alignment: .leading, spacing: 2) {
                            StatView(label: t("pep_builds_up"), value: "\(trim(accumulationRatio(intervalHours, hl), 2))×")
                            Text(t("pep_steady_hint", ["duration": .string(formatDuration(timeToSteadyState(hl))), "frequency": .string(p.doseRanges[0].frequency)]))
                                .font(.caption2).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if let curve { demoChart(p, curve) }
            Text(t("pep_single_dose_note")).font(.caption).foregroundStyle(.secondary)
        } else if let curve, curve.basis == .elsewhere, let est = p.halfLifeEstimate {
            // A shape without figures: the only measurement was in another species or route.
            demoChart(p, curve)
            VStack(alignment: .leading, spacing: 4) {
                Text("**\(t(estimateKey(est.evidence))).** \(describeHalfLifeEstimate(est))")
                if let url = URL(string: est.url) { Link(t("pep_check_yourself"), destination: url) }
                Text(t("pep_estimate_note"))
            }
            .font(.caption).foregroundStyle(est.evidence == .anecdotal ? Tone.tangerine.color : .secondary)
        } else if let curve, curve.basis == .yours, let mine {
            demoChart(p, curve)
            Text("**\(t("pep_your_figure"))** \(t("pep_your_figure_note", ["hours": .string(formatHalfLife(mine.hours)), "note": .string(mine.note.map { ", \($0)" } ?? "")]))")
                .font(.caption).foregroundStyle(Tone.tangerine.color)
        } else {
            Text(t("pep_no_curve")).font(.subheadline).foregroundStyle(.secondary)
        }
    }

    /// A blend has no curve of its own: one typical dose, split into its parts,
    /// each on its own half-life, and the parts that have none named as such.
    @ViewBuilder private func blendContent(_ p: Peptide) -> some View {
        let data = store.data
        let range = p.doseRanges.first
        let dose = range.map { jsRound(($0.lowMcg + $0.highMcg) / 2) } ?? 1000
        let parts = decomposeDose(p, dose, resolve: { data.peptide($0) })
        let now = nowMillis()
        let tones: [Tone] = [.tangerine, .sky, .grape, .leaf, .rose, .mint]
        let series: [PkSeries] = parts.enumerated().compactMap { i, part in
            guard let id = part.peptideId, let peptide = data.peptide(id), let curve = curveFor(peptide, yours: data.halfLifeOverrides[id]) else { return nil }
            return PkSeries(id: id, label: part.name, doses: [DoseEvent(at: now, amountMcg: part.mcg)], params: curve.params,
                            referenceMcg: part.mcg, basis: curve.basis, tone: tones[i % tones.count])
        }
        ForEach(Array(parts.enumerated()), id: \.offset) { i, part in
            let peptide = part.peptideId.flatMap { data.peptide($0) }
            HStack {
                Circle().fill(tones[i % tones.count].color).frame(width: 8, height: 8)
                Text(part.name).font(.subheadline)
                Spacer()
                Text("\(formatDose(part.mcg)) · \(t("pep_half_life")) \(formatHalfLife(peptide?.halfLifeHours))").font(.caption.monospacedDigit()).foregroundStyle(.secondary)
            }
        }
        if !series.isEmpty {
            let longest = series.map(\.params.halfLifeHours).max() ?? 24
            PkChartView(series: series, now: now, range: now...(now + min(longest * 5, 24 * 21) * HOUR_MS), compact: true)
            Text(t("ios_blend_curve_note", ["dose": .string(formatDose(dose))])).font(.caption).foregroundStyle(.secondary)
        }
    }

    /// One 1 mg dose, now, drawn to at most three weeks.
    private func demoChart(_ p: Peptide, _ curve: Curve) -> some View {
        let now = nowMillis()
        let span = min(curve.params.halfLifeHours * 5, 24 * 21)
        let series = PkSeries(id: p.id, label: p.name, doses: [DoseEvent(at: now, amountMcg: 1000)], params: curve.params,
                              referenceMcg: 1000, basis: curve.basis, tone: .tangerine)
        return PkChartView(series: [series], now: now, range: now...(now + span * HOUR_MS), compact: true)
    }
}

private struct BulletLabel: LabelStyle {
    var tone: Tone?
    func makeBody(configuration: Configuration) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Circle().fill(tone?.color ?? Color(.tertiaryLabel)).frame(width: 4, height: 4).alignmentGuide(.firstTextBaseline) { $0[.bottom] + 4 }
            configuration.title.font(.subheadline).foregroundStyle(.secondary)
        }
    }
}

/// What a blend holds, and what one dose of it delivers of each part.
private struct BlendPanel: View {
    @Environment(AppStore.self) private var store
    var blend: Peptide
    @State private var doseMcg: Double = 1000
    @State private var loaded = false

    var body: some View {
        Section(t("pep_whats_in_it")) {
            ForEach(blend.components ?? [], id: \.name) { c in
                HStack(spacing: 12) {
                    Text(c.mgPerVial.map { "\(jsNumberString($0)) mg" } ?? "n/a").font(.subheadline.monospacedDigit()).foregroundStyle(Tone.tangerine.color).frame(width: 64, alignment: .leading)
                    if let id = c.peptideId { NavigationLink(c.name, value: id) } else { Text(c.name) }
                }
            }
            AmountRow(label: t("pep_dose_delivers"), value: $doseMcg, range: 0...100_000_000)
            BlendBreakdownView(blend: blend, doseMcg: doseMcg, resolve: { store.data.peptide($0) })
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let r = blend.doseRanges.first { doseMcg = jsRound((r.lowMcg + r.highMcg) / 2) }
        }
    }
}

/// Your own half-life, for a compound with nothing published for people.
private struct YourHalfLifeRow: View {
    @Environment(AppStore.self) private var store
    var peptideId: String
    var name: String
    @State private var editing = false

    var body: some View {
        if let mine = store.data.halfLifeOverrides[peptideId] {
            VStack(alignment: .leading, spacing: 4) {
                Text("\(t("yhl_your_figure")) **\(formatHalfLife(mine.hours))**\(mine.note.map { ", \($0)" } ?? "")").font(.footnote)
                Text(t("yhl_set_on", ["date": .string(formatDate(mine.setAt))])).font(.caption).foregroundStyle(.secondary)
            }
            .swipeActions {
                Button(t("yhl_remove", ["name": .string(name)]), role: .destructive) { store.mutate { $0.setHalfLifeOverride(peptideId, hours: nil) } }
                Button(t("yhl_change", ["name": .string(name)])) { editing = true }
            }
            .contextMenu {
                Button { editing = true } label: { Label(t("yhl_change", ["name": .string(name)]), systemImage: "pencil") }
                Button(role: .destructive) { store.mutate { $0.setHalfLifeOverride(peptideId, hours: nil) } } label: { Label(t("yhl_remove", ["name": .string(name)]), systemImage: "trash") }
            }
            .sheet(isPresented: $editing) { NavigationStack { HalfLifeForm(peptideId: peptideId, name: name) } }
        } else {
            Button { editing = true } label: { Label(t("yhl_use_own"), systemImage: "pencil") }
                .sheet(isPresented: $editing) { NavigationStack { HalfLifeForm(peptideId: peptideId, name: name) } }
        }
    }
}

private struct HalfLifeForm: View {
    @Environment(AppStore.self) private var store
    var peptideId: String
    var name: String
    @State private var hours: Double?
    @State private var note = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                OptionalNumberRow(label: t("yhl_hours_label"), value: $hours, suffix: "h")
                TextField(t("yhl_source_label"), text: $note, prompt: Text(t("yhl_source_placeholder")))
                FooterRow { Text(t("yhl_intro", ["name": .string(name)])) }
            } footer: { FooterWrap { Text(t("yhl_intro", ["name": .string(name)])) }}
        }
        .formChrome(name, confirm: t("yhl_save"), disabled: !((hours ?? 0) > 0)) {
            let trimmed = note.trimmingCharacters(in: .whitespacesAndNewlines)
            store.mutate { $0.setHalfLifeOverride(peptideId, hours: hours, note: trimmed.isEmpty ? nil : trimmed) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let mine = store.data.halfLifeOverrides[peptideId]
            hours = mine?.hours; note = mine?.note ?? ""
        }
    }
}

/// Your own note on a compound, kept per profile.
private struct CompoundNotesRow: View {
    @Environment(AppStore.self) private var store
    var peptideId: String
    var name: String
    @State private var editing = false

    var body: some View {
        let mine = store.data.mine.compoundNotes.first { $0.peptideId == peptideId }
        Group {
            if let mine {
                VStack(alignment: .leading, spacing: 4) {
                    Text(t("note_written_on", ["date": .string(formatDate(mine.updatedAt))])).font(.caption).foregroundStyle(.secondary)
                    Text(mine.text).font(.subheadline)
                }
                .swipeActions {
                    Button(t("note_remove", ["name": .string(name)]), role: .destructive) { store.mutate { $0.setCompoundNote(peptideId, text: "") } }
                    Button(t("note_change", ["name": .string(name)])) { editing = true }
                }
                .contextMenu {
                    Button { editing = true } label: { Label(t("note_change", ["name": .string(name)]), systemImage: "pencil") }
                    Button(role: .destructive) { store.mutate { $0.setCompoundNote(peptideId, text: "") } } label: { Label(t("note_remove", ["name": .string(name)]), systemImage: "trash") }
                }
                Button(t("note_change", ["name": .string(name)])) { editing = true }.font(.footnote)
            } else {
                Button { editing = true } label: { Label(t("note_add"), systemImage: "pencil") }
            }
        }
        .sheet(isPresented: $editing) { NavigationStack { NoteForm(peptideId: peptideId, name: name, initial: mine?.text ?? "") } }
    }
}

private struct NoteForm: View {
    @Environment(AppStore.self) private var store
    var peptideId: String
    var name: String
    var initial: String
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        Form {
            Section {
                TextField(t("note_placeholder"), text: $text, axis: .vertical).lineLimit(5...)
                FooterRow { Text(t("note_intro", ["name": .string(name)])) }
            } footer: { FooterWrap { Text(t("note_intro", ["name": .string(name)])) }}
        }
        .formChrome(name, confirm: t("note_save")) { store.mutate { $0.setCompoundNote(peptideId, text: text) } }
        .onAppear { if !loaded { loaded = true; text = initial } }
    }
}
