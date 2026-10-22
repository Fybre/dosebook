import SwiftUI
import BenchCore
import BenchStore

/// Every dose, a day at a time, with how each day went beside the doses taken on it.
struct LogView: View {
    @Environment(AppStore.self) private var store
    @Environment(\.tabReselects) private var reselects
    @AppStorage("bench.logMode") private var mode = Mode.list
    @State private var filter = ""
    @State private var editing: LogEdit?
    @State private var ratingDay: RatingDay?
    @State private var pickingDay = false
    @State private var now = nowMillis()
    @State private var month = startOfLocalMonth(nowMillis())
    @State private var selectedDay: Millis? = startOfLocalDay(nowMillis())
    @State private var farDown = false
    @AppStorage("bench.log.showMissed") private var showMissed = true

    enum Mode: String { case list, calendar }
    struct LogEdit: Identifiable { var id: String; var logId: String? }
    struct RatingDay: Identifiable { var id: Millis }

    var body: some View {
        let data = store.data
        let mine = data.mine
        let logs = mine.logs
        let shown = filter.isEmpty ? logs : logs.filter { $0.peptideId == filter }
        let palette = assignColors(colorSubjects(mine.protocols.filter(\.active), resolve: { data.peptide($0) }, nowMs: now))
        // A check-in belongs to a day and not to a compound, so a filtered list leaves them out.
        let checkIns = filter.isEmpty ? mine.checkIns : []
        let logged = diaryDays(shown, at: \.at, checkIns)
        // Missed doses, at most 90 days back, for the compound shown.
        let missedByDay: [Millis: [MissedDose]] = showMissed ? Dictionary(uniqueKeysWithValues:
            missedDoses(mine.protocols, mine.logs, fromMs: max(now - 90 * DAY_MS, mine.protocols.map(\.startedAt).min() ?? now), nowMs: now)
                .map { ($0.day, $0.doses.filter { filter.isEmpty || $0.peptideId == filter }) }.filter { !$0.1.isEmpty }) : [:]
        let days = Set(logged.map(\.day)).union(missedByDay.keys).sorted(by: >).map { day in
            logged.first { $0.day == day } ?? DiaryDay(day: day, entries: [], checkIn: nil)
        }
        ScrollViewReader { proxy in
        List {
            Section {
                Picker(t("ios_log_view"), selection: $mode) {
                    Label(t("ios_log_list"), systemImage: "list.bullet").tag(Mode.list)
                    Label(t("ios_log_calendar"), systemImage: "calendar").tag(Mode.calendar)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }
            .id("top")

            let peptideIds = logs.map(\.peptideId).reduce(into: [String]()) { if !$0.contains($1) { $0.append($1) } }
            if mode == .calendar {
                if peptideIds.count > 1 { filterSection(data, peptideIds) }
                Section {
                    LogCalendarView(logs: shown, checkIns: checkIns, palette: palette, weekStartsOn: data.settings.weekStartsOn,
                                    now: now, month: $month, selected: $selectedDay, missedDays: Set(missedByDay.keys))
                }
                if let day = selectedDay {
                    let entry = days.first { $0.day == day } ?? DiaryDay(day: day, entries: [], checkIn: nil)
                    daySection(entry, missed: missedByDay[day] ?? [], data: data, palette: palette)
                }
            } else {
                if !logs.isEmpty { Section { stats(mine) } }

                if logs.contains(where: { $0.site != nil && routeHasSite($0.route) }) {
                    Section(t("log_site_rotation")) {
                        SiteMapView(logs: shown, nowMs: now).frame(maxWidth: .infinity)
                        let overused = overusedSites(shown, now)
                        if let first = overused.first {
                            Text("\(t("log_overused_line", ["sites": .string(overused.map { siteLabel($0.site) }.joined(separator: ", ")), "n": .number(Double(first.recentCount))])) \(t("log_overused_why"))")
                                .font(.footnote).foregroundStyle(Tone.tangerine.color)
                        }
                    }
                }

                if peptideIds.count > 1 { filterSection(data, peptideIds) }

                if days.isEmpty {
                    ContentUnavailableView {
                        Label(t("log_no_logs"), systemImage: "list.bullet.rectangle")
                    } description: {
                        Text(t("log_empty_desc"))
                    } actions: {
                        Button(t("log_first_dose_cta")) { editing = LogEdit(id: "new", logId: nil) }.buttonStyle(.borderedProminent)
                    }
                } else {
                    Color.clear.frame(height: 0).listRowBackground(Color.clear).id("diary")
                    ForEach(days, id: \.day) { day in daySection(day, missed: missedByDay[day.day] ?? [], data: data, palette: palette).id("day-\(Int(day.day))") }
                }
            }
        }
        .onScrollGeometryChange(for: Bool.self) { $0.contentOffset.y > 1500 } action: { _, far in
            withAnimation(.easeOut(duration: 0.2)) { farDown = far }
        }
        .overlay(alignment: .bottomTrailing) {
            if farDown && mode == .list {
                Button { withAnimation { proxy.scrollTo("top", anchor: .top) } } label: {
                    Image(systemName: "arrow.up").font(.headline).padding(14)
                }
                .buttonStyle(.borderedProminent)
                .buttonBorderShape(.circle)
                .shadow(radius: 4, y: 2)
                .padding(.trailing, 20).padding(.bottom, 16)
                .accessibilityLabel(t("ios_back_to_top"))
                .transition(.scale.combined(with: .opacity))
            }
        }
        // Tapping the Log tab while already on it goes back to the top.
        .onChange(of: reselects["log"] ?? 0) { _, _ in withAnimation { proxy.scrollTo("top", anchor: .top) } }
        .debugAnchor(proxy)
        }
        .navigationTitle(t("log_title"))
        .toolbar {
            ToolbarItem(placement: .secondaryAction) {
                Button { pickingDay = true } label: { Label(t("log_rate_another_day"), systemImage: "calendar.badge.plus") }
            }
            ToolbarItem(placement: .secondaryAction) {
                Toggle(isOn: $showMissed) { Label(t("ios_show_missed"), systemImage: "exclamationmark.circle") }
            }
            ToolbarItem(placement: .primaryAction) {
                Button { editing = LogEdit(id: "new", logId: nil) } label: { Label(t("log_new_dose"), systemImage: "plus") }
            }
        }
        .onAppear { now = nowMillis() }
        .sheet(item: $editing) { e in NavigationStack { LogDoseSheet(defaultPeptideId: nil, editId: e.logId) } }
        .sheet(item: $ratingDay) { d in NavigationStack { CheckInSheet(dayMs: d.id) } }
        .sheet(isPresented: $pickingDay) {
            RateDayPicker { picked in
                pickingDay = false
                if let day = ratableDay(picked.millis, nowMs: nowMillis()) {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { ratingDay = RatingDay(id: day) }
                }
            }
            .presentationDetents([.medium, .large])
        }
    }

    /// A dose that was due and never logged, with the two ways to settle it.
    private func missedRow(_ m: MissedDose, data: AppData, palette: Palette) -> some View {
        let p = data.peptide(m.peptideId)
        let tone = doseColor(palette, protocolId: m.protocolId, peptideId: m.peptideId)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(formatTime(m.at)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(Tone.rose.color).font(.caption)
                    Text(p?.name ?? m.peptideId).font(.subheadline.weight(.medium)).foregroundStyle(tone?.color ?? .primary)
                    Text(doseLabel(m.doseMcg, p)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                }
                HStack(spacing: 8) {
                    Pill(text: t("ios_missed"), tone: .rose)
                    Spacer()
                    Button(t("ios_missed_skip")) { store.mutate { _ = $0.logMissed(m, skipped: true) } }
                        .buttonStyle(.bordered).controlSize(.small)
                    Button(t("ios_missed_log")) { store.mutate { _ = $0.logMissed(m) } }
                        .buttonStyle(.borderedProminent).controlSize(.small)
                }
            }
        }
        .accessibilityElement(children: .contain)
        .accessibilityHint(t("ios_missed_hint"))
    }

    private func filterSection(_ data: AppData, _ peptideIds: [String]) -> some View {
        Section {
            Picker(t("log_filter_by_peptide"), selection: $filter) {
                Text(t("log_all_peptides")).tag("")
                ForEach(peptideIds, id: \.self) { Text(data.peptide($0)?.name ?? $0).tag($0) }
            }
        }
    }

    /// One day: its doses, then how it went. Shared by the list and the calendar.
    private func daySection(_ day: DiaryDay<DoseLog>, missed: [MissedDose], data: AppData, palette: Palette) -> some View {
        Section(day.day == startOfLocalDay(now) ? t("checkin_today") : "\(formatWeekday(day.day)), \(formatDate(day.day, nowMs: now))") {
            ForEach(missed) { m in missedRow(m, data: data, palette: palette) }
            if day.entries.isEmpty && day.checkIn == nil && missed.isEmpty && mode == .calendar {
                Text(t("ios_calendar_nothing")).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(day.entries) { l in
                Button { editing = LogEdit(id: l.id, logId: l.id) } label: { LogRow(log: l, name: data.peptide(l.peptideId)?.name ?? l.peptideId, tone: doseColor(palette, protocolId: l.protocolId, peptideId: l.peptideId), peptide: data.peptide(l.peptideId)) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("log_edit_dose", ["when": .string(formatDateTime(l.at, nowMs: now))]))
            }
            if let c = day.checkIn {
                Button { ratingDay = RatingDay(id: day.day) } label: { DayRatingRow(checkIn: c) }
                    .buttonStyle(.plain)
                    .accessibilityLabel(t("log_edit_day", ["date": .string(formatDate(day.day, nowMs: now))]))
            } else if ratableDay(day.day, nowMs: now) != nil {
                Button(t("log_rate_this_day")) { ratingDay = RatingDay(id: day.day) }
                    .font(.footnote).foregroundStyle(.secondary)
            }
        }
    }

    private func stats(_ mine: AppData) -> some View {
        let day = 86_400_000.0
        let recent = mine.logs.filter { $0.at > now - 30 * day }
        let rates = mine.protocols.filter(\.active).map { p in adherence(p, logsForProtocol(p, mine.logs), max(p.startedAt, now - 30 * day), now) }
        let expected = rates.reduce(0) { $0 + $1.expected }, taken = rates.reduce(0) { $0 + $1.taken }
        let rate: Double? = expected > 0 ? Double(taken) / Double(expected) : nil
        let skipped = recent.filter(\.isSkipped).count
        let rateTone: Tone = rate.map { $0 >= 0.9 ? .leaf : $0 >= 0.7 ? .tangerine : .rose } ?? .neutral
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .top) {
                StatView(label: t("log_doses_30_days"), value: String(recent.count - skipped))
                StatView(label: t("now_skipped"), value: String(skipped), tone: skipped > 0 ? .rose : .neutral)
                StatView(label: t("log_adherence"), value: rate.map { percent($0) } ?? t("checkin_na"), tone: rateTone)
            }
            Text(t("log_adherence_hint")).font(.caption2).foregroundStyle(.secondary)
        }
    }
}

struct StatView: View {
    var label: String
    var value: String
    var tone: Tone = .neutral
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title2.weight(.bold).monospacedDigit()).foregroundStyle(tone == .neutral ? Color.primary : tone.color)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

private struct LogRow: View {
    var log: DoseLog
    var name: String
    var tone: Tone?
    var peptide: Peptide? = nil

    var body: some View {
        let l = log
        // Only a dose that went into tissue shows a site; old records carry one whatever the route.
        let site = l.site.flatMap { !l.isSkipped && routeHasSite(l.route) ? siteLabel($0) : nil }
        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(formatTime(l.at)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    if let tone { Circle().fill(tone.color).frame(width: 8, height: 8) }
                    Text(name).font(.subheadline.weight(.medium)).foregroundStyle(tone?.color ?? .primary)
                    if l.isSkipped { Pill(text: t("log_skipped"), tone: .rose) }
                    else { Text(doseLabel(l.doseMcg, peptide)).font(.subheadline.monospacedDigit()) }
                }
                let amount: String? = l.isSkipped ? nil
                    : l.tablets.map { t("count_tablets", ["n": .string(trim($0, 2))]) }
                    ?? (l.route == .intranasal ? l.presses.map { t("count_presses", ["n": .number($0)]) }
                        : l.units.map { "\(trim($0, 2)) \(t("stock_marks"))\(l.syringeScale == .u40 ? " (U-40)" : "")" })
                if amount != nil || site != nil {
                    HStack(spacing: 10) {
                        if let amount { Text(amount).monospacedDigit() }
                        if let site { Text(site).fontWeight(.medium).foregroundStyle(.primary) }
                    }
                    .font(.caption).foregroundStyle(.secondary)
                }
                if l.feeling != nil || !(l.sideEffects ?? []).isEmpty {
                    FlowLayout(spacing: 4) {
                        if let f = l.feeling { Pill(text: FEELING_LABELS[f] ?? t("log_feeling_n", ["n": .number(Double(f))]), tone: FEELING_TONE[f] ?? .neutral) }
                        ForEach(l.sideEffects ?? [], id: \.self) { Pill(text: $0) }
                    }
                }
                if let notes = l.notes { Text(notes).font(.caption).foregroundStyle(.secondary) }
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
    }
}

/// How the day went, quieter than a dose, edged in the day's worst rating.
private struct DayRatingRow: View {
    var checkIn: CheckIn
    var body: some View {
        let rated = SYMPTOMS.filter { checkIn.ratings[$0.id.rawValue] != nil }
        let tone = lowestRatedTone(rated.map { (checkIn.ratings[$0.id.rawValue]!, $0.higherIsBetter) })
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 1.5).fill(tone?.color ?? Color(.separator)).frame(width: 3)
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(t("log_how_day_went").uppercased()).font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                    Spacer()
                    Image(systemName: "pencil").font(.caption2).foregroundStyle(.tertiary)
                }
                FlowLayout(spacing: 4) {
                    ForEach(rated) { s in
                        let r = checkIn.ratings[s.id.rawValue]!
                        Pill(text: "\(s.label) \(jsNumberString(r))/\(SYMPTOM_SCALE_MAX)", tone: ratingTone(r, s.higherIsBetter))
                    }
                }
                if let n = checkIn.notes { Text(n).font(.caption) }
            }
        }
        .contentShape(Rectangle())
    }
}

/// Reaches any past day, since a day with no dose and no rating has no row to tap.
private struct RateDayPicker: View {
    var onPick: (Date) -> Void
    @State private var date = Date()
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            DatePicker(t("log_rate_by_date"), selection: $date, in: ...Date(), displayedComponents: .date)
                .datePickerStyle(.graphical)
                .padding()
                .navigationTitle(t("log_rate_another_day"))
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) { Button(t("ios_continue")) { onPick(date) } }
                }
        }
    }
}
