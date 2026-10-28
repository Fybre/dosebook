import SwiftUI
import Charts
import BenchCore
import BenchStore

private let LOSS_KEY: [RecordKey: String] = [
    .profiles: "count_profiles", .protocols: "count_protocols", .logs: "count_doses", .vials: "count_vials",
    .measurements: "count_measurements", .labs: "count_results", .checkIns: "count_ratings", .customPeptides: "count_compounds",
    .orders: "count_orders", .diluents: "count_bottles", .compoundNotes: "count_notes",
]

/// Shown when a write emptied a collection: the rows can be unioned back in.
struct RescueNotice: View {
    @Environment(AppStore.self) private var store
    @State private var done: String?

    var body: some View {
        if let done {
            CalloutText(done).font(.footnote).callout(.leaf)
        } else if let rescue = store.rescue, !rescue.losses.isEmpty {
            let missing = recoverable(store.data, rescue)
            let describe: (Loss) -> String = { t(LOSS_KEY[$0.key]!, ["n": .number(Double(abs(lostCount($0))))]) }
            VStack(alignment: .leading, spacing: 10) {
                Label(t("rescue_title"), systemImage: "lifepreserver").font(.caption.bold()).foregroundStyle(Tone.tangerine.color)
                CalloutText(t("rescue_lost", ["what": .string(rescue.losses.map(describe).joined(separator: ", ")), "when": .string(formatDateTime(rescue.at))])).font(.footnote)
                CalloutText(missing.isEmpty ? t("rescue_already") : t("rescue_partial")).font(.footnote)
                HStack {
                    if !missing.isEmpty {
                        Button { store.putRecordsBack(); done = t("rescue_done", ["what": .string(missing.map(describe).joined(separator: ", "))]) } label: {
                            Label(t("rescue_put_back"), systemImage: "arrow.uturn.backward")
                        }.buttonStyle(.borderedProminent)
                    }
                    Button(missing.isEmpty ? t("rescue_dismiss") : t("rescue_meant_to")) { store.clearRescue() }.buttonStyle(.bordered)
                }
                Text(t("rescue_footnote")).font(.caption2).foregroundStyle(.secondary)
            }
            .callout(.tangerine)
        }
    }
}

/// A reminder to export, only when the data is not already in iCloud.
struct BackupNagCard: View {
    @Environment(AppStore.self) private var store
    var now: Millis
    @State private var exporting = false

    var body: some View {
        let mine = store.data.mine
        let stamps = mine.logs.map(\.at) + mine.measurements.map(\.at) + mine.labs.map(\.at)
        let manual: Bool = { if case .cloud = store.location { return false }; return true }()
        let verdict = backupNag(manualBackupOnly: manual, recordCount: stamps.count, oldestRecordAt: stamps.min(),
                                lastBackupAt: store.data.settings.lastBackupAt, dismissedAt: store.data.settings.backupNagDismissedAt, nowMs: now)
        if verdict.show {
            VStack(alignment: .leading, spacing: 10) {
                CalloutText(t("nag_nothing_backed_up"), bold: true).font(.subheadline)
                CalloutText(verdict.reason == .never ? t("ios_nag_never", ["n": .number(Double(stamps.count))]) : t("ios_nag_stale", ["days": .number(Double(verdict.daysSinceBackup ?? 0))]))
                    .font(.footnote)
                HStack {
                    Button { exporting = true } label: { Label(t("nag_export_copy"), systemImage: "square.and.arrow.down") }.buttonStyle(.borderedProminent)
                    Button(t("later")) { store.mutate { $0.settings.backupNagDismissedAt = nowMillis() } }.buttonStyle(.bordered)
                }
            }
            .callout(.tangerine)
            .backupExporter(isPresented: $exporting)
        }
    }
}

/// Once there is a plan and reminders are off: a one-time suggestion to turn
/// them on. Reminders stay off by default, so they are never switched on unasked.
struct RemindersTipCard: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    /// Per device, as notifications are.
    @AppStorage("bench.remindersTipDismissed") private var dismissed = false
    @State private var refused = false

    var body: some View {
        let data = store.data
        let enabled = data.settings.reminders?.enabled == true
        if !dismissed, !enabled, data.mine.protocols.contains(where: \.active) {
            VStack(alignment: .leading, spacing: 10) {
                CalloutText(t("ios_tip_reminders_title"), bold: true).font(.subheadline)
                CalloutText(refused ? t("ios_reminders_refused") : t("ios_tip_reminders_body")).font(.footnote)
                HStack {
                    if refused {
                        Button(t("ios_open_settings")) { if let url = notificationSettingsURL { openURL(url) } }
                            .buttonStyle(.borderedProminent)
                    } else {
                        Button { Task { await turnOn() } } label: { Label(t("ios_tip_reminders_on"), systemImage: "bell") }.buttonStyle(.borderedProminent)
                    }
                    Button(t("later")) { dismissed = true }.buttonStyle(.bordered)
                }
            }
            .callout(.sky)
        }
    }

    private func turnOn() async {
        var ok = await ReminderScheduler.availability() == .available
        if !ok { ok = await ReminderScheduler.requestPermission() }
        guard ok else { refused = true; return }
        store.mutate { d in
            var r = d.settings.reminders ?? DEFAULT_REMINDERS
            r.enabled = true
            d.settings.reminders = r
        }
    }
}

/// History with no plan: offer the protocols the history implies.
struct HistoryWithoutPlanCard: View {
    @Environment(AppStore.self) private var store
    var now: Millis
    @State private var created: [String] = []

    var body: some View {
        let data = store.data
        let logs = data.mine.logs
        if logs.isEmpty {
            ContentUnavailableView {
                Label(t("hwp_empty_title"), systemImage: "flask")
            } description: { Text(t("hwp_empty_body")) }
        } else {
            let suggestions = inferAllProtocols(logs, resolve: { data.peptide($0) })
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: t("hwp_title"))
                Text(t("hwp_body", ["doses": .string(t("count_doses", ["n": .number(Double(logs.count))]))])).font(.footnote).foregroundStyle(.secondary)
                ForEach(suggestions, id: \.peptideId) { s in
                    let done = created.contains(s.peptideId)
                    VStack(alignment: .leading, spacing: 6) {
                        HStack {
                            Text(s.summary).font(.footnote)
                            if s.confidence == .rough { Pill(text: t("hwp_worth_checking"), tone: .tangerine) }
                        }
                        Text(t("hwp_span", ["from": .string(formatDate(s.startedAt)), "last": .string(formatDate(s.lastAt))])
                             + (s.sites.isEmpty ? "" : " · " + s.sites.map(siteLabel).joined(separator: ", ")))
                            .font(.caption).foregroundStyle(.secondary)
                        Button { create(s) } label: { Label(t("hwp_create"), systemImage: "calendar.badge.plus") }
                            .buttonStyle(.borderedProminent).disabled(done)
                    }
                    .padding(10)
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(done ? Tone.leaf.color : Color(.separator)))
                }
            }
            .card()
        }
    }

    private func create(_ s: InferredProtocol) {
        store.mutate {
            $0.addProtocol(DoseProtocol(id: "", profileId: "", peptideId: s.peptideId, name: t("plan_name_example", ["name": .string(s.peptideName)]),
                                        startedAt: s.startedAt, doseMcg: s.doseMcg, route: .subcutaneous, schedule: s.schedule,
                                        sites: s.sites.isEmpty ? nil : s.sites))
        }
        created.append(s.peptideId)
    }
}

/// Weight against the doses: the trend, the change, and the rate.
struct WeightCard: View {
    @Environment(AppStore.self) private var store
    var now: Millis
    @State private var adding = false
    @State private var trend = false

    var body: some View {
        let data = store.data
        let unit = data.settings.weightUnit
        let measurements = data.mine.measurements
        let series = weightSeries(measurements)
        let change = weightChange(measurements)
        let change30 = weightChange(measurements, since: now - 30 * DAY_MS)
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                CardHeader(title: t("weight_title"), systemImage: "scalemass")
                Button(data.settings.plotWeightOnChart == true ? t("weight_on_chart") : t("weight_chart_toggle")) {
                    store.mutate { $0.settings.plotWeightOnChart = !($0.settings.plotWeightOnChart ?? false) }
                }
                .font(.caption).buttonStyle(.bordered).controlSize(.mini)
                .accessibilityLabel(data.settings.plotWeightOnChart == true ? t("weight_hide_on_chart") : t("weight_show_on_chart"))
                Button { trend = true } label: { Label(t("ios_trend_button"), systemImage: "chart.xyaxis.line") }.font(.caption).buttonStyle(.bordered).controlSize(.mini)
                    .disabled(series.count < 2)
                Button { adding = true } label: { Label(t("add"), systemImage: "plus") }.font(.caption).buttonStyle(.bordered).controlSize(.mini)
            }
            if series.isEmpty {
                Text(t("ios_weight_none_yet_neutral")).font(.footnote).foregroundStyle(.secondary)
            } else {
                HStack(spacing: 8) {
                    stat(t("weight_latest"), trim(toDisplayWeight(series.last!.kg, unit), 1), unit.rawValue, nil, nil)
                    if let c = change {
                        let losing = c.deltaKg < 0
                        stat(t("weight_since_start"), (c.deltaKg > 0 ? "+" : "") + trim(toDisplayWeight(c.deltaKg, unit), 1), unit.rawValue, losing ? .leaf : .tangerine,
                             t("weight_change_hint", ["percent": .string(trim(c.deltaPercent, 1)), "days": .string(t("count_days", ["n": .number(jsRound(c.days))]))]))
                    }
                    if let rate = change30?.perWeekKg {
                        stat(t("weight_rate_30"), (rate > 0 ? "+" : "−") + trim(abs(toDisplayWeight(rate, unit)), 2), "\(unit.rawValue)/wk", rate < 0 ? .leaf : .tangerine, nil)
                    }
                }
                let doses = data.mine.logs.filter { !$0.isSkipped }.map(\.at)
                Chart {
                    ForEach(Array(series.enumerated()), id: \.offset) { _, p in
                        LineMark(x: .value("t", Date(millis: p.at)), y: .value("w", toDisplayWeight(p.kg, unit))).foregroundStyle(Tone.leaf.color)
                        PointMark(x: .value("t", Date(millis: p.at)), y: .value("w", toDisplayWeight(p.kg, unit))).foregroundStyle(Tone.leaf.color).symbolSize(16)
                    }
                    ForEach(doses.filter { $0 >= series.first!.at }, id: \.self) { d in
                        RuleMark(x: .value("dose", Date(millis: d))).foregroundStyle(Color.accentColor.opacity(0.15))
                    }
                    if let goal = data.settings.weightGoal {
                        RuleMark(y: .value("goal", toDisplayWeight(goal.kg, unit)))
                            .foregroundStyle(Tone.sky.color).lineStyle(StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                    }
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 120)
                .contentShape(Rectangle())
                .onTapGesture { trend = true }
            }
            if !series.isEmpty { WeightGoalRow(now: now) }
        }
        .card()
        .sheet(isPresented: $adding) { NavigationStack { WeightEntry() } }
        .sheet(isPresented: $trend) { NavigationStack { WeightTrendView(now: now) } }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-weightTrend") { DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { trend = true } } }
        #endif
    }

    private func stat(_ label: String, _ value: String, _ unit: String, _ tone: Tone?, _ hint: String?) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label.uppercased()).font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
            HStack(alignment: .firstTextBaseline, spacing: 2) {
                Text(value).font(.headline.monospacedDigit()).foregroundStyle(tone?.color ?? .primary)
                Text(unit).font(.caption2).foregroundStyle(.secondary)
            }
            if let hint { Text(hint).font(.system(size: 9)).foregroundStyle(.secondary) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(8).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
    }
}

struct WeightEntry: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var value: Double?
    @State private var at = Date()
    /// The newest reading from Apple Health, offered as the starting value.
    @State private var prefilled: HealthSample?

    var body: some View {
        let unit = store.data.settings.weightUnit
        Form {
            OptionalNumberRow(label: t("weight_title"), value: Binding(get: { value }, set: { value = $0; prefilled = nil }), suffix: unit.rawValue)
            DatePicker(t("weight_when"), selection: Binding(get: { at }, set: { at = $0; prefilled = nil }))
        }
        .navigationTitle(t("weight_title")).inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(t("save")) {
                    guard let v = value, v > 0 else { return }
                    if let p = prefilled {
                        // Untouched: the platform's exact value and record id, not the rounded one shown.
                        store.mutate { $0.addMeasurement(BodyMeasurement(id: "", profileId: "", at: p.at, weightKg: p.weightKg, source: .healthConnect, externalId: p.externalId)) }
                    } else {
                        store.mutate { $0.addMeasurement(BodyMeasurement(id: "", profileId: "", at: at.millis, weightKg: fromDisplayWeight(v, unit), source: .manual)) }
                    }
                    dismiss()
                }.disabled((value ?? 0) <= 0)
            }
        }
        .task {
            guard await HealthKitAdapter.availability() == .asked,
                  let sample = newestSample((try? await HealthKitAdapter.readWeight(since: nowMillis() - 30 * DAY_MS)) ?? []),
                  value == nil,
                  !store.data.mine.measurements.contains(where: { $0.externalId == sample.externalId }) else { return }
            value = jsRound(toDisplayWeight(sample.weightKg, unit) * 10) / 10
            at = Date(millis: sample.at)
            prefilled = sample
        }
    }
}

/// One to five per symptom, plus a note; the shared editor for today and any past day.
struct CheckInEditor: View {
    @Binding var ratings: [String: Double]
    @Binding var notes: String
    var vitals: BodyMeasurement?
    var notePlaceholder: String

    var body: some View {
        ForEach(SYMPTOMS) { s in
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(s.label).font(.subheadline.weight(.semibold))
                    Spacer()
                    if let r = ratings[s.id.rawValue] { Text("\(Int(r))").font(.subheadline.monospacedDigit()).foregroundStyle(ratingTone(r, s.higherIsBetter).color) }
                }
                HStack(spacing: 6) {
                    Text(s.low).font(.caption2).foregroundStyle(.secondary)
                    ForEach(1...SYMPTOM_SCALE_MAX, id: \.self) { n in
                        let on = ratings[s.id.rawValue] == Double(n)
                        Button {
                            ratings[s.id.rawValue] = on ? nil : Double(n)
                        } label: {
                            Text("\(n)").font(.footnote.bold()).frame(maxWidth: .infinity, minHeight: 30)
                                .background(on ? ratingTone(Double(n), s.higherIsBetter).color.opacity(0.85) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 7))
                                .foregroundStyle(on ? Color.white : Color.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("\(s.label) \(n) of \(SYMPTOM_SCALE_MAX)")
                    }
                    Text(s.high).font(.caption2).foregroundStyle(.secondary)
                }
                if let hint = s.hint { Text(hint).font(.caption2).foregroundStyle(.secondary) }
            }
        }
        if let v = vitals, v.sleepHours != nil || v.restingHrBpm != nil {
            let bits = [v.sleepHours.map { t("checkin_phone_sleep", ["n": .string(trim($0, 1))]) }, v.restingHrBpm.map { t("checkin_phone_pulse", ["n": .number(jsRound($0))]) }].compactMap { $0 }
            Text(t("checkin_phone_recorded", ["details": .string(bits.joined(separator: ", "))])).font(.caption).foregroundStyle(.secondary)
        }
        TextField(notePlaceholder, text: $notes, axis: .vertical)
    }
}

/// How today felt, and what the last fortnight of ratings says.
struct CheckInCard: View {
    @Environment(AppStore.self) private var store
    var now: Millis
    @State private var editing = false
    @State private var showingVitalsTrend = false

    var body: some View {
        let mine = store.data.mine
        let existing = checkInFor(mine.checkIns, now)
        let coverage = checkInStreak(mine.checkIns, nowMs: now)
        let means = averages(Array(mine.checkIns.prefix(14)))
        let newest = mine.protocols.max { $0.startedAt < $1.startedAt }
        let shifts = newest.map { shiftAround(mine.checkIns, $0.startedAt, nowMs: now).filter(isTrendworthy) } ?? []
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                CardHeader(title: t("checkin_how_you_feel"), systemImage: "heart.text.square")
                Button { editing = true } label: { Label(existing != nil ? t("checkin_rated") : t("checkin_rate_today"), systemImage: existing != nil ? "checkmark" : "plus") }
                    .font(.caption).buttonStyle(.bordered).controlSize(.mini)
                Button { showingVitalsTrend = true } label: { Label(t("ios_vitals_button"), systemImage: "chart.xyaxis.line") }
                    .font(.caption).buttonStyle(.bordered).controlSize(.mini)
            }
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 96), spacing: 8)], spacing: 8) {
                ForEach(means, id: \.id.rawValue) { m in
                    VStack(alignment: .leading, spacing: 2) {
                        Text(m.label).font(.caption2).foregroundStyle(.secondary).lineLimit(1)
                        Text(m.mean.map { trim($0, 1) } ?? t("checkin_na")).font(.headline.monospacedDigit())
                            .foregroundStyle(m.mean.map { ratingTone(jsRound($0), m.higherIsBetter).color } ?? .secondary)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(8).background(Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                }
            }
            Text(coverage.last30 == 0 ? t("checkin_nothing_rated")
                 : t("checkin_average", ["rated": .number(Double(coverage.last30)), "run": .string(coverage.current > 1 ? t("checkin_in_a_row", ["n": .number(Double(coverage.current))]) : "")]))
                .font(.caption).foregroundStyle(.secondary)
            ForEach(shifts, id: \.id.rawValue) { s in
                HStack {
                    Text(s.label).font(.caption.weight(.semibold))
                    Text(t("checkin_shift", ["before": .string(trim(s.before ?? 0, 1)), "after": .string(trim(s.after ?? 0, 1))])).font(.caption.monospacedDigit())
                    Text(t("checkin_days_split", ["before": .number(Double(s.daysBefore)), "after": .number(Double(s.daysAfter))])).font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .card()
        .sheet(isPresented: $editing) { NavigationStack { CheckInSheet(dayMs: now) } }
        .sheet(isPresented: $showingVitalsTrend) { NavigationStack { VitalsTrendView(now: now) } }
        #if DEBUG
        .onAppear { if ProcessInfo.processInfo.arguments.contains("-vitalsTrend") { showingVitalsTrend = true } }
        #endif
        // Sleep and resting heart rate from Apple Health, onto each day's vitals.
        .task(id: startOfLocalDay(now)) { await HealthKitAdapter.pullVitals(into: store) }
    }
}

/// Rate any day that has happened, from Today or the Log.
struct CheckInSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var dayMs: Millis
    @State private var ratings: [String: Double] = [:]
    @State private var notes = ""
    @State private var loaded = false
    @State private var confirmDelete = false

    var body: some View {
        let mine = store.data.mine
        let existing = checkInFor(mine.checkIns, dayMs)
        let allowed = ratableDay(dayMs) != nil
        let day = startOfLocalDay(dayMs)
        Form {
            if allowed {
                CheckInEditor(ratings: $ratings, notes: $notes, vitals: mine.measurements.first { $0.externalId == "hc-vitals:\(jsNumberString(day))" },
                              notePlaceholder: startOfLocalDay(dayMs) == startOfLocalDay(nowMillis()) ? t("checkin_note_placeholder") : t("checkin_note_this_day"))
                if existing != nil {
                    Button(t("checkin_delete_rating"), role: .destructive) { confirmDelete = true }
                }
            } else {
                Text(t("checkin_not_yet")).foregroundStyle(.secondary)
            }
        }
        .navigationTitle(t("checkin_how_went", ["date": .string(formatDate(dayMs))])).inlineTitle()
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(ratings.isEmpty ? t("checkin_save_blank") : t("checkin_save_count", ["rated": .number(Double(ratings.count)), "total": .number(Double(SYMPTOMS.count))])) {
                    let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    store.mutate { $0.saveCheckIn(at: dayMs, ratings: ratings, notes: trimmed.isEmpty ? nil : trimmed) }
                    dismiss()
                }.disabled(!allowed)
            }
        }
        .confirmationDialog(t("checkin_delete_confirm"), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(t("checkin_delete_it"), role: .destructive) {
                if let e = existing { store.mutate { $0.removeCheckIn(e.id) } }
                dismiss()
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            if let e = existing { ratings = e.ratings; notes = e.notes ?? "" }
        }
    }
}

/// The latest of each tracked marker, and what is worth checking.
struct LabsCard: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let data = store.data
        let labs = data.mine.labs
        let compounds = data.mine.protocols.filter(\.active).compactMap { data.peptide($0.peptideId) }.map(LabCompoundTraits.init)
        let tracked = Array(trackedMarkerIds(labs).prefix(4))
        let missing = missingMarkerIds(labs, compounds)
        if !labs.isEmpty || !missing.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                HStack {
                    CardHeader(title: t("labs_card_title"), systemImage: "drop")
                    NavigationLink { LabsView() } label: { Text(labs.isEmpty ? t("labs_card_add_results") : t("labs_card_all_results")).font(.caption) }
                }
                ForEach(tracked, id: \.self) { id in
                    if let marker = Library.marker(id), let result = latestResult(labs, id) {
                        let verdict = verdictFor(marker, result)
                        let trend = labTrend(labs, id)
                        HStack {
                            Text(marker.name).font(.subheadline.weight(.medium))
                            if verdict.status != .unknown { Pill(text: verdict.label, tone: verdict.tone == .muted ? .neutral : verdict.tone) }
                            Spacer()
                            Text(trim(result.value, marker.decimals)).font(.subheadline.monospacedDigit().bold())
                            Text(marker.unit).font(.caption2).foregroundStyle(.secondary)
                            if let tr = trend {
                                Text((tr.delta > 0 ? "+" : "−") + trim(abs(tr.delta), marker.decimals)).font(.caption2.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                if !missing.isEmpty {
                    (Text(t("labs_card_worth_checking") + " ") + Text(missing.map { Library.marker($0)?.name ?? $0 }.joined(separator: ", ")).bold() + Text("."))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            .card()
        }
    }
}

/// Weekly exposure and the climb to steady state.
struct InsightsView: View {
    var tracks: [Track]
    var logs: [DoseLog]
    var now: Millis

    var body: some View {
        let weeks = weeklyExposure(logs, now)
        if !tracks.isEmpty, weeks.contains(where: { $0.totalMcg > 0 }) {
            Text(t("now_trends").uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 8) {
                HStack { Text(t("now_weekly_exposure")).font(.subheadline.bold()); Spacer(); Text(t("now_last_8_weeks")).font(.caption).foregroundStyle(.secondary) }
                Text(t("now_weekly_desc")).font(.caption).foregroundStyle(.secondary)
                Chart(Array(weeks.enumerated()), id: \.offset) { i, w in
                    BarMark(x: .value("week", "\(LocalTime.calendar.component(.day, from: Date(millis: w.weekStart)))"), y: .value("mcg", w.totalMcg))
                        .foregroundStyle(Color.accentColor.opacity(i == weeks.count - 1 ? 1 : 0.4))
                        .accessibilityLabel(t("now_week_tooltip", ["date": .string(formatDate(w.weekStart)), "total": .string(formatDose(w.totalMcg)), "doses": .string(t("count_doses", ["n": .number(Double(w.doses))]))]))
                }
                .chartYAxis(.hidden)
                .frame(height: 110)
                (Text(t("now_this_week") + " ") + Text(formatDose(weeks.last!.totalMcg)).bold()
                 + Text(" " + t("now_across_doses", ["doses": .string(t("count_doses", ["n": .number(Double(weeks.last!.doses))]))])))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            .card()
            VStack(alignment: .leading, spacing: 10) {
                Text(t("now_building_steady")).font(.subheadline.bold())
                Text(t("now_steady_desc")).font(.caption).foregroundStyle(.secondary)
                ForEach(tracks) { track in
                    let ss = steadyStateProgress(track.peptide?.halfLifeHours, track.doses.map(\.at).min(), now)
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(track.name).font(.footnote.weight(.semibold))
                            Spacer()
                            Text(ss == nil ? t("library_no_half_life") : ss!.fraction >= 1 ? t("now_at_steady")
                                 : t("now_to_go", ["duration": .string(formatDuration(ss!.hoursNeeded - ss!.hoursElapsed))]))
                                .font(.caption).foregroundStyle(.secondary)
                        }
                        ProgressView(value: ss?.fraction ?? 0).tint(ss == nil ? .secondary : track.tone.color)
                    }
                }
            }
            .card()
        }
    }
}
