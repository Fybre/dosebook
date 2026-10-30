import SwiftUI
import Charts
import BenchCore
import BenchStore

/// "Every 7 days, 4 weeks on / 2 off, at 07:00 and 19:00". Silent about the
/// hour when the schedule never named one.
func describeSchedule(_ s: Schedule) -> String {
    var base: String
    switch s.kind {
    case .daily: base = t("plan_every_day")
    case .intervalDays:
        let n = s.intervalDays ?? 0
        base = n == 7 ? t("plan_weekly") : n == 1 ? t("plan_every_day") : t("plan_every_n_days", ["n": .number(n)])
    case .daysOfWeek:
        let days = (s.daysOfWeek ?? []).filter { (0...6).contains($0) }.map { t(WEEKDAY_KEYS[$0]) }.joined(separator: ", ")
        base = days.isEmpty ? t("plan_no_days") : days
    default: base = t("plan_as_needed")
    }
    if let on = s.cycleWeeksOn, on > 0, (s.cycleWeeksOff ?? 0) <= 0 {
        base += ", " + t("plan_band_weeks", ["n": .number(on)])
    } else if let on = s.cycleWeeksOn, let off = s.cycleWeeksOff, on > 0, off > 0 {
        base += ", " + t("plan_cycle", ["on": .number(on), "off": .number(off)])
    }
    if s.kind != .asNeeded, !(s.timesOfDay ?? []).isEmpty || s.timeOfDay != nil {
        base += " " + t("plan_at_times", ["times": .string(scheduleTimes(s).joined(separator: " \(t("plan_and")) "))])
    }
    return base
}

/// Marks, presses or tablets for a dose, from what is on this profile's shelf.
struct DoseMarksText: View {
    @Environment(AppStore.self) private var store
    var peptideId: String
    var doseMcg: Double
    var route: Route?
    var nowMs: Millis = nowMillis()

    var body: some View {
        if let text { Text(text).monospacedDigit() }
    }

    private var text: String? {
        drawAmountText(store.data, peptideId: peptideId, doseMcg: doseMcg, route: route, nowMs: nowMs)
    }
}

/// Collisions in what is running together. Quiet unless something collides.
struct StackWarningsView: View {
    @Environment(AppStore.self) private var store
    var compact = false
    var nowMs: Millis = nowMillis()

    var body: some View {
        let data = store.data
        let active = data.mine.protocols.filter(\.active)
        let issues = stackIssues(active, resolve: { data.peptide($0) }, nowMs: nowMs)
        if active.count >= 2 {
            if issues.isEmpty {
                Label(t("stack_all_clear", ["protocols": .string(String(active.count))]), systemImage: "checkmark.shield")
                    .font(.footnote.weight(.medium)).foregroundStyle(Tone.leaf.color)
            } else if compact {
                let high = issues.contains { $0.severity == .high }
                Label {
                    Text(t("stack_compact", ["things": .string(t("count_things", ["n": .number(Double(issues.count))]))])).bold()
                    + Text(" " + t("stack_see_plan", ["title": .string(issues[0].title)]))
                } icon: { Image(systemName: "exclamationmark.shield") }
                    .font(.footnote).foregroundStyle((high ? Tone.rose : Tone.tangerine).color)
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    CardHeader(title: t("warnings_title"))
                    ForEach(Array(issues.enumerated()), id: \.offset) { _, issue in
                        let tone: Tone = issue.severity == .high ? .rose : .tangerine
                        Label {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(issue.title).font(.subheadline.bold())
                                Text(issue.detail).font(.footnote)
                            }
                        } icon: { Image(systemName: "exclamationmark.shield") }
                            .foregroundStyle(tone.color)
                            .padding(10)
                            .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                    }
                    Text(t("stack_footnote")).font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }
}

/// When suppressive compounds clear, and the published recovery protocols.
struct PctPanelView: View {
    @Environment(AppStore.self) private var store
    var nowMs: Millis = nowMillis()
    @State private var open: String?

    var body: some View {
        let data = store.data
        let plan = pctPlan(data.mine.logs, resolve: { data.peptide($0) }, nowMs: nowMs)
        if !plan.compounds.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                CardHeader(title: t("pct_recovery_timing"), systemImage: "calendar.badge.clock",
                           badge: plan.clear ? (t("pct_cleared_badge"), .leaf) : !plan.blockedBy.isEmpty ? (t("pct_not_computable_badge"), .tangerine) : (t("pct_still_clearing_badge"), .grape))
                ForEach(plan.compounds, id: \.peptideId) { c in
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(c.name).font(.subheadline.bold())
                            Spacer()
                            Text(t("pct_last_dose", ["date": .string(formatDate(c.lastDoseAt))])).font(.caption).foregroundStyle(.secondary)
                        }
                        if let cleared = c.clearedAt {
                            let left = remainingFraction(c, nowMs: nowMs) ?? 0
                            ProgressView(value: min(1, max(0.02, left))).tint(Tone.grape.color)
                            Text(cleared <= nowMs ? t("pct_cleared_line") : t("pct_left_line", [
                                "percent": .number(jsRound(left * 100)), "date": .string(formatDate(cleared)),
                                "duration": .string(formatDuration((cleared - nowMs) / HOUR_MS)),
                            ])).font(.caption).foregroundStyle(.secondary)
                        } else {
                            Text(c.unknownReason ?? "").font(.footnote).foregroundStyle(Tone.tangerine.color)
                        }
                    }
                    .padding(10).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
                }
                if !plan.blockedBy.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("pct_no_date_title")).bold()
                        Text(t("pct_no_date_body", ["names": .string(plan.blockedBy.joined(separator: ", "))]))
                    }
                    .font(.footnote).foregroundStyle(Tone.tangerine.color)
                } else if let start = plan.earliestStart {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(plan.clear ? t("pct_androgen_cleared") : t("pct_earliest_start", ["date": .string(formatDate(start))])).bold()
                        Text(t("pct_five_half_lives", ["percent": .number(jsRound(CLEARED_FRACTION * 100))]))
                    }
                    .font(.footnote).foregroundStyle(Tone.sky.color)
                    .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(Tone.sky.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
                }
                Text(t("pct_published").uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(PCT_TEMPLATES) { template in
                    DisclosureGroup(isExpanded: Binding(get: { open == template.id }, set: { open = $0 ? template.id : nil })) {
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(template.weeks, id: \.week) { w in
                                HStack(alignment: .top) {
                                    Text(t("pep_week_abbrev", ["range": .number(Double(w.week))])).font(.caption.monospaced().bold()).foregroundStyle(.secondary).frame(width: 44, alignment: .leading)
                                    Text(w.detail).font(.footnote)
                                }
                            }
                            if let start = plan.earliestStart {
                                let ends = start + Double(template.weeks.count) * 7 * DAY_MS
                                Text(t("pct_ends_around", ["ends": .string(formatDate(ends)), "retest": .string(formatDate(retestAfter(ends)))])).font(.caption).foregroundStyle(.secondary)
                            }
                            Text(template.source).font(.caption2).foregroundStyle(.secondary)
                            if let url = URL(string: template.citationUrl) { Link(t("pct_source"), destination: url).font(.caption2) }
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text(template.name).font(.subheadline.bold()); Spacer(); Text(t("count_weeks", ["n": .number(Double(template.weeks.count))])).font(.caption).foregroundStyle(.secondary) }
                            Text(template.summary).font(.caption).foregroundStyle(.secondary)
                        }
                    }
                }
                Text(t("pct_footer")).font(.caption2).foregroundStyle(.secondary)
            }
            .card()
        }
    }
}

/// What a protocol would do, while it is still being chosen.
struct ProjectionPreviewView: View {
    var protocol_: DoseProtocol
    var peptide: Peptide?
    /// For a blend's parts, each of which has its own curve.
    var resolve: (String) -> Peptide? = { _ in nil }

    var body: some View {
        if let peptide {
            // A blend has no half-life of its own: one projection per part that has one.
            // The figures are ratios, so the same whatever share of the dose a part is.
            let parts = (peptide.components ?? []).compactMap { c in c.peptideId.flatMap(resolve).flatMap { $0.halfLifeHours != nil ? $0 : nil } }
            if isBlend(peptide), !parts.isEmpty {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(parts, id: \.id) { part in
                        let p = project(protocol_, halfLifeHours: part.halfLifeHours!, tmaxHours: part.tmaxHours)
                        if p.series.count >= 2 { chart(p, part, partName: part.name) }
                    }
                }
            } else if let h = peptide.halfLifeHours {
                let p = project(protocol_, halfLifeHours: h, tmaxHours: peptide.tmaxHours)
                if p.series.count >= 2 { chart(p, peptide) }
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    CardHeader(title: t("projection_label"), systemImage: "chart.line.uptrend.xyaxis")
                    Text(t("projection_no_curve", ["name": .string(peptide.name)]) + (peptide.halfLifeNote.map { " \($0)" } ?? ""))
                        .font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
    }

    private func chart(_ p: Projection, _ peptide: Peptide, partName: String? = nil) -> some View {
        let from = p.series[0].t
        return VStack(alignment: .leading, spacing: 10) {
            CardHeader(title: t("projection_header"), systemImage: "chart.line.uptrend.xyaxis")
            if let partName { Text(partName).font(.subheadline.weight(.semibold)) }
            Chart {
                ForEach(p.series, id: \.t) { s in
                    AreaMark(x: .value("t", Date(millis: s.t)), y: .value("level", s.level))
                        .foregroundStyle(LinearGradient(colors: [Color.accentColor.opacity(0.28), .clear], startPoint: .top, endPoint: .bottom))
                    LineMark(x: .value("t", Date(millis: s.t)), y: .value("level", s.level)).foregroundStyle(Color.accentColor)
                }
                if p.hoursToSteady * HOUR_MS < p.series.last!.t - from {
                    RuleMark(x: .value("steady", Date(millis: from + p.hoursToSteady * HOUR_MS)))
                        .foregroundStyle(.secondary).lineStyle(StrokeStyle(lineWidth: 1, dash: [3, 3]))
                }
            }
            .chartYAxis(.hidden)
            .frame(height: 110).chartWhenActive(height: 110)
            .accessibilityLabel(t("projection_chart_label", ["name": .string(peptide.name), "days": .string(t("count_days", ["n": .number(jsRound((p.series.last!.t - from) / DAY_MS))]))]))
            HStack(spacing: 8) {
                figure(t("projection_settle"), formatDuration(p.hoursToSteady), t("projection_from_first"))
                figure(t("projection_steady_vs_first"), p.accumulation.map { "\(trim($0, 1))x" } ?? t("projection_na"), t("projection_same_dose"))
                figure(t("projection_peak_trough"), p.swing.map { "\(trim($0, 1))x" } ?? t("projection_na"), t("projection_between_doses"))
            }
            if let d = describeAccumulation(p.accumulation) { Text(d).font(.footnote).foregroundStyle(.secondary) }
            Text(t("projection_model_note")).font(.caption2).foregroundStyle(.secondary)
        }
    }

    private func figure(_ label: String, _ value: String, _ hint: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary).lineLimit(2)
            Text(value).font(.headline.monospacedDigit())
            Text(hint).font(.system(size: 9)).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }
}

/// Protocols in the order chosen in Settings: by next dose (soonest first, paused after,
/// stopped last), by name, or as stored. Ties keep their stored order.
func sortedProtocols(_ protocols: [DoseProtocol], by sort: ProtocolSort, now: Millis, name: (DoseProtocol) -> String) -> [DoseProtocol] {
    func rank(_ p: DoseProtocol) -> Int { !p.active ? 2 : isPaused(p, now) ? 1 : 0 }
    func next(_ p: DoseProtocol) -> Millis { protocolNextDoseTime(p, now) ?? Double.infinity }
    switch sort {
    case .dateAdded: return protocols
    case .alphabetical:
        return protocols.enumerated().sorted { a, b in
            let c = name(a.element).localizedCaseInsensitiveCompare(name(b.element))
            return c != .orderedSame ? c == .orderedAscending : a.offset < b.offset
        }.map(\.element)
    case .nextDose:
        return protocols.enumerated().sorted { a, b in
            let (ra, rb) = (rank(a.element), rank(b.element))
            if ra != rb { return ra < rb }
            let (na, nb) = (next(a.element), next(b.element))
            return na != nb ? na < nb : a.offset < b.offset
        }.map(\.element)
    }
}

/// The sort menu on Now and Plan; one choice for both.
struct ProtocolSortMenu: View {
    @Environment(AppStore.self) private var store
    var body: some View {
        Menu {
            Picker(t("ios_protocol_sort"), selection: Binding(get: { store.data.settings.protocolSort }, set: { value in
                store.mutate { $0.settings.protocolSort = value }
            })) {
                Text(t("ios_protocol_sort_next")).tag(ProtocolSort.nextDose)
                Text(t("ios_protocol_sort_alpha")).tag(ProtocolSort.alphabetical)
                Text(t("ios_protocol_sort_added")).tag(ProtocolSort.dateAdded)
            }
        } label: { Label(t("ios_protocol_sort"), systemImage: "arrow.up.arrow.down") }
    }
}
