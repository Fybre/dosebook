import SwiftUI
import BenchCore
import BenchStore

private let DUE_KEY: [DueLabel: String] = [.paused: "due_paused", .dueNow: "due_now", .overdue: "due_overdue", .none: "due_none", .dueToday: "due_today", .scheduled: "due_scheduled"]
private let CURVE_KEY: [PhaseId: String] = [.cleared: "curve_cleared", .peak: "curve_peak", .absorbing: "curve_absorbing", .active: "curve_active", .trailing: "curve_trailing"]

struct LogRequest: Identifiable {
    var peptideId: String?
    var anySite = false
    var id: String { "\(peptideId ?? "-")\(anySite)" }
}

struct TodayView: View {
    @Environment(AppStore.self) private var store
    @State private var now = nowMillis()
    @State private var lastQuickLog: (id: String, name: String)?
    @State private var logRequest: LogRequest?
    @State private var confirmEarly: String?
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    var body: some View {
        let data = store.data
        let mine = data.mine
        let active = mine.protocols.filter(\.active)
        let palette = assignColors(colorSubjects(active, resolve: { data.peptide($0) }, nowMs: now))
        let tracks = TodayModel.tracks(data, now: now, palette: palette)
        let series = TodayModel.series(tracks, palette: palette)
        let attention = tracks.filter { $0.due.state == .overdue || $0.due.state == .dueNow }
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                TodayCard(protocols: mine.protocols, logs: mine.logs, now: now)
                RescueNotice()
                BackupNagCard(now: now)
                if mine.protocols.isEmpty {
                    HistoryWithoutPlanCard(now: now)
                } else {
                    if active.count >= 2 { StackWarningsView(compact: true, nowMs: now).card() }
                    if let q = lastQuickLog { quickLogNote(q) }
                    ForEach(attention) { attentionRow($0, logs: mine.logs) }
                    laterToday(tracks, logs: mine.logs, attention: attention)
                    if !series.isEmpty {
                        PkChartView(series: series, now: now,
                                    weights: data.settings.plotWeightOnChart == true ? mine.measurements : [],
                                    weightUnit: data.settings.weightUnit, describeVial: { describeVial($0, data) })
                            .card()
                            .id("chart")
                        notes(tracks, data: data)
                    }
                    Text(t("now_active_protocols").uppercased()).font(.caption.bold()).foregroundStyle(.secondary).id("protocols")
                    ForEach(tracks) { protocolCard($0, data: data) }
                }
                WeightCard(now: now).id("cards")
                CheckInCard(now: now)
                LabsCard()
                if !mine.protocols.isEmpty { InsightsView(tracks: tracks, logs: mine.logs, now: now) }
                worthSorting(tracks, data: data)
            }
            .padding()
        }
        .debugAnchor(proxy)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(t("nav_now"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { logRequest = LogRequest(peptideId: nil) } label: { Label(t("log_new_dose"), systemImage: "plus") }
            }
        }
        .onReceive(tick) { _ in now = nowMillis() }
        .onAppear {
            now = nowMillis()
            #if DEBUG
            if let i = ProcessInfo.processInfo.arguments.firstIndex(of: "-log"), logRequest == nil {
                let rest = ProcessInfo.processInfo.arguments.dropFirst(i + 1).first
                logRequest = LogRequest(peptideId: rest.flatMap { $0.hasPrefix("-") ? nil : $0 })
            }
            #endif
        }
        .sheet(item: $logRequest) { req in
            NavigationStack { LogDoseSheet(defaultPeptideId: req.peptideId, anySite: req.anySite) }
        }
    }

    // MARK: Pieces

    private func describeVial(_ id: String, _ data: AppData) -> String? {
        guard let v = data.vials.first(where: { $0.id == id }) else { return nil }
        let conc = vialConcentration(v)
        let name = data.peptide(v.peptideId)?.name ?? v.peptideId
        return "\(t("now_vial_label", ["name": .string(name)])) \(conc.isFinite ? formatConcentration(conc) : t("now_not_reconstituted"))"
    }

    private func quickLogNote(_ q: (id: String, name: String)) -> some View {
        HStack {
            Image(systemName: "checkmark").foregroundStyle(Tone.leaf.color)
            Text(t("now_quick_logged_note", ["name": .string(q.name)])).font(.subheadline)
            Spacer()
            Button(t("now_undo")) { store.mutate { $0.removeLog(q.id) }; lastQuickLog = nil }
            Button { lastQuickLog = nil } label: { Image(systemName: "xmark") }.accessibilityLabel(t("dismiss"))
        }
        .buttonStyle(.borderless)
        .card()
    }

    private func log(_ track: Track, site: InjectionSite?) {
        let p = track.protocol_
        let id = store.mutate { d in
            d.addLog(DoseLog(id: "", profileId: "", protocolId: p.id, peptideId: p.peptideId, at: nowMillis(), doseMcg: track.targetMcg,
                             route: p.route, site: routeHasSite(p.route) ? site : nil))
        }
        lastQuickLog = (id, track.name)
        now = nowMillis()
    }

    private func choices(_ track: Track, logs: [DoseLog]) -> [SiteUsage] {
        routeHasSite(track.protocol_.route)
            ? siteChoices(logs.filter { $0.peptideId == track.protocol_.peptideId }, now, allowed: track.protocol_.sites)
            : []
    }

    private func attentionRow(_ track: Track, logs: [DoseLog]) -> some View {
        let overdue = track.due.state == .overdue
        let options = choices(track, logs: logs)
        return VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 6) {
                Pill(text: t(DUE_KEY[track.due.label] ?? "due_now"), tone: overdue ? .rose : .tangerine)
                Circle().fill(track.tone.color).frame(width: 7, height: 7)
                Text(track.name).font(.subheadline.weight(.semibold)).foregroundStyle(track.tone.color)
                Text(formatDose(track.targetMcg)).font(.subheadline.monospacedDigit())
                DoseMarksText(peptideId: track.protocol_.peptideId, doseMcg: track.targetMcg, route: track.protocol_.route, nowMs: now)
                    .font(.caption).foregroundStyle(.secondary)
            }
            if let at = track.due.at {
                Text((overdue ? t("now_was_due", ["when": .string(relativeTime(at, nowMs: now))]) : t("now_scheduled_at", ["when": .string(relativeTime(at, nowMs: now))]))
                     + (options.first.map { " · " + t("now_at_site", ["site": .string(siteLabel($0.site))]) } ?? ""))
                    .font(.caption).foregroundStyle(.secondary)
            }
            HStack {
                if options.count < 2 {
                    Button { log(track, site: options.first?.site) } label: { Label(t("now_logged"), systemImage: "checkmark") }
                        .buttonStyle(.borderedProminent)
                } else {
                    Menu {
                        Section(t("now_site_hint")) {
                            ForEach(options) { c in
                                Button {
                                    log(track, site: c.site)
                                } label: {
                                    Text(siteLabel(c.site))
                                    Text(c.site == options[0].site ? t("now_site_suggested") : c.lastUsedAt.map { relativeTime($0, nowMs: now) } ?? t("site_never_used"))
                                }
                            }
                        }
                        Button(t("now_site_all")) { logRequest = LogRequest(peptideId: track.protocol_.peptideId, anySite: true) }
                    } label: {
                        Label(t("now_logged"), systemImage: "checkmark")
                    } primaryAction: {
                        log(track, site: options[0].site)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(t("now_log_with_site", ["dose": .string(formatDose(track.targetMcg))]))
                }
                Button(t("now_details")) { logRequest = LogRequest(peptideId: track.protocol_.peptideId) }.buttonStyle(.bordered)
            }
        }
        .card()
        .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder((overdue ? Tone.rose : Tone.tangerine).color.opacity(0.45)))
    }

    @ViewBuilder private func laterToday(_ tracks: [Track], logs: [DoseLog], attention: [Track]) -> some View {
        let shown = Set(attention.compactMap { t in t.due.at.map { "\(t.id):\($0)" } })
        let rows = tracks.flatMap { track in
            unloggedDoseTimes(track.protocol_, logsForProtocol(track.protocol_, logs), now, endOfLocalDay(now))
                .filter { !shown.contains("\(track.id):\($0)") }
                .map { (track: track, at: $0) }
        }.sorted { $0.at < $1.at }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: t("now_later_today")).padding(.bottom, 8)
                ForEach(rows, id: \.at) { row in
                    let key = "\(row.track.id):\(row.at)"
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(formatTime(row.at)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                            Circle().fill(row.track.tone.color).frame(width: 7, height: 7)
                            Text(row.track.name).font(.subheadline.weight(.medium)).foregroundStyle(row.track.tone.color)
                            Text(formatDose(row.track.targetMcg)).font(.footnote.monospacedDigit())
                            Spacer()
                            if confirmEarly != key {
                                Button { confirmEarly = key } label: { Image(systemName: "checkmark.circle") }
                                    .accessibilityLabel(t("now_log_ahead_title", ["time": .string(formatTime(row.at))]))
                            }
                        }
                        if confirmEarly == key {
                            // A dose logged hours early is usually a misread row, so it asks.
                            Text(t("now_not_due_until", ["time": .string(formatTime(row.at)), "when": .string(relativeTime(row.at, nowMs: now))]))
                                .font(.caption).foregroundStyle(.secondary)
                            HStack {
                                Button(t("now_yes_log_it")) {
                                    confirmEarly = nil
                                    log(row.track, site: suggestSite(logs.filter { $0.peptideId == row.track.protocol_.peptideId }, nowMillis(), allowed: row.track.protocol_.sites))
                                }.buttonStyle(.borderedProminent)
                                Button(t("now_details")) { confirmEarly = nil; logRequest = LogRequest(peptideId: row.track.protocol_.peptideId) }.buttonStyle(.bordered)
                                Button(t("cancel")) { confirmEarly = nil }
                            }
                        }
                    }
                    .padding(.vertical, 8)
                    Divider()
                }
            }
            .buttonStyle(.borderless)
            .card()
        }
    }

    @ViewBuilder private func notes(_ tracks: [Track], data: AppData) -> some View {
        let estimated = tracks.compactMap { track -> (String, Bool)? in
            guard let curve = track.curve, !isMeasuredInPeople(curve.basis), let p = track.peptide else { return nil }
            if curve.basis == .yours, let mine = data.halfLifeOverrides[p.id] {
                return (t("now_drawn_from_yours", ["name": .string(p.name), "hours": .string(formatHalfLife(mine.hours)), "note": .string(mine.note.map { " (\($0))" } ?? "")]), true)
            }
            guard let e = p.halfLifeEstimate else { return nil }
            return (t("now_estimate_line", ["name": .string(p.name), "detail": .string(describeHalfLifeEstimate(e))]), e.evidence == .anecdotal)
        }
        var unplotted: [String] = []
        let _ = tracks.forEach { track in
            for part in track.blendParts where part.peptide.flatMap({ curveFor($0, yours: data.halfLifeOverrides[$0.id]) }) == nil {
                if !unplotted.contains(part.name) { unplotted.append(part.name) }
            }
            if track.blendParts.isEmpty, track.peptide != nil, track.curve == nil, !unplotted.contains(track.name) { unplotted.append(track.name) }
        }
        if !estimated.isEmpty {
            (Text(t("now_dashed_line") + " ") + estimated.reduce(Text("")) { $0 + Text($1.0 + " ").foregroundColor($1.1 ? Tone.tangerine.color : nil) }
             + Text(t("now_no_pk_figures", ["n": .number(Double(estimated.count))])))
                .font(.caption).foregroundStyle(.secondary)
        }
        if !unplotted.isEmpty {
            (Text(unplotted.joined(separator: ", ")).bold() + Text(" " + t("now_unplotted", ["n": .number(Double(unplotted.count))])))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    private func protocolCard(_ track: Track, data: AppData) -> some View {
        let yours = track.curve?.basis == .yours ? data.halfLifeOverrides[track.protocol_.peptideId]?.hours : nil
        let low = track.stock.dosesRemaining <= data.settings.lowStockDoses
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "syringe").foregroundStyle(track.tone.color).frame(width: 34, height: 34)
                    .background(track.tone.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        NavigationLink(value: track.protocol_.peptideId) { Text(track.name).font(.headline) }.buttonStyle(.plain)
                        if let snap = track.snap { Pill(text: t(CURVE_KEY[snap.phase]!), tone: snap.phase == .cleared ? .neutral : .sky) }
                    }
                    if (track.due.state == .scheduled || track.due.state == .upcoming), let at = track.due.at {
                        Text(t("now_next_at", ["when": .string(relativeTime(at, nowMs: now))])).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(formatDosePerDay(track.targetMcg, track.perDay))
                        DoseMarksText(peptideId: track.protocol_.peptideId, doseMcg: track.targetMcg, route: track.protocol_.route, nowMs: now).foregroundStyle(.tertiary)
                        Text("· \(track.protocol_.name)").lineLimit(1)
                    }
                    .font(.footnote).foregroundStyle(.secondary)
                }
                Spacer()
                Button { logRequest = LogRequest(peptideId: track.protocol_.peptideId) } label: { Label(t("now_log_short"), systemImage: "plus") }
                    .buttonStyle(.bordered).controlSize(.small)
            }
            if let snap = track.snap {
                ProgressView(value: min(1, snap.level)).tint(track.tone.color)
                HStack {
                    Text(t("now_percent_of_peak", ["pct": .string(jsToFixed(snap.percentOfPeak, 0))])).font(.footnote.weight(.semibold)).monospacedDigit()
                    Text(t("curve_\(snap.phase.rawValue)_detail")).font(.footnote).foregroundStyle(.secondary)
                }
            } else if track.blendParts.isEmpty {
                Text(t("now_no_half_life") + " " + (track.peptide?.halfLifeNote ?? "")).font(.footnote).foregroundStyle(.secondary)
            }
            if !track.blendParts.isEmpty, let peptide = track.peptide {
                Text(t("now_one_dose_delivers", ["dose": .string(formatDose(track.targetMcg))])).font(.caption).foregroundStyle(.secondary)
                BlendBreakdownView(blend: peptide, doseMcg: track.targetMcg, resolve: { data.peptide($0) }, dosesPerWeek: protocolDosesPerWeek(track.protocol_, now))
            }
            if let phase = track.phase {
                VStack(alignment: .leading, spacing: 4) {
                    Label(t("now_right_now_since", ["since": .string(formatDuration(hoursSince(track.lastLoggedAt, now) ?? 0))]), systemImage: "sparkles").font(.caption.bold())
                    Text(phase.label).font(.footnote)
                    if let next = phase.hoursToNext { Text(t("now_phase_shifts", ["in": .string(formatDuration(next))])).font(.caption2).opacity(0.75) }
                }
                .foregroundStyle(track.tone.color)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(track.tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
            Divider()
            VStack(alignment: .leading, spacing: 4) {
                Text(t("now_last_dose")).foregroundStyle(.secondary)
                    + Text(" " + (track.lastLoggedAt.map { relativeTime($0, nowMs: now) } ?? t("now_never")))
                    + Text(track.lastLog.flatMap { l in l.site.flatMap { routeHasSite(l.route) ? " · " + siteLabel($0) : nil } } ?? "")
                Text(t("library_half_life")).foregroundStyle(.secondary)
                    + Text(" " + (!track.blendParts.isEmpty ? t("now_per_component")
                                  : yours.map { t("now_half_life_yours", ["hours": .string(formatHalfLife($0)), "marker": .string(t("now_your_figure"))]) }
                                  ?? formatHalfLife(track.peptide?.halfLifeHours)))
                stockLine(track, low: low)
                if track.stock.needsReconstitution {
                    Text(t("now_record_reconstitution")).foregroundStyle(Tone.tangerine.color)
                }
            }
            .font(.caption)
        }
        .card()
    }

    private func stockLine(_ track: Track, low: Bool) -> Text {
        let pastDate = track.stock.dosesRemaining == 0 && track.stock.dosesExpired > 0
        var line = Text(t("now_stock_label") + " ").foregroundColor(low ? Tone.rose.color : .secondary)
            + Text(t("count_doses", ["n": .number(pastDate ? track.stock.dosesExpired : track.stock.dosesRemaining)])).foregroundColor(low ? Tone.rose.color : nil)
        if pastDate { line = line + Text(" · " + t("now_stock_past_date")).foregroundColor(Tone.rose.color) }
        if let days = track.supplyDays, track.stock.dosesRemaining > 0 {
            line = line + Text(" " + t("now_about_left", ["duration": .string(formatDuration(days * 24))])).foregroundColor(.secondary)
        }
        return line
    }

    @ViewBuilder private func worthSorting(_ tracks: [Track], data: AppData) -> some View {
        let low = tracks.filter { $0.stock.dosesRemaining <= data.settings.lowStockDoses && $0.targetMcg > 0 }
        let expiring = data.mine.vials.filter { $0.state == .reconstituted && $0.budAt.map { $0 - now < data.settings.budWarningDays * DAY_MS } == true }
        if !low.isEmpty || !expiring.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text(t("now_worth_sorting").uppercased()).font(.caption.bold()).foregroundStyle(.secondary)
                ForEach(low) { track in
                    let past = track.stock.dosesRemaining == 0 && track.stock.dosesExpired > 0
                    CalloutText(past
                             ? t("now_all_past_date", ["name": .string(track.name), "doses": .string(t("count_doses", ["n": .number(track.stock.dosesExpired)]))])
                             : t("now_low_stock", ["name": .string(track.name), "doses": .string(t("count_doses", ["n": .number(track.stock.dosesRemaining)])),
                                                   "open": .number(Double(track.stock.openCount)), "sealed": .string(t("count_vials", ["n": .number(Double(track.stock.sealedCount))]))]))
                        .font(.footnote).callout(.tangerine)
                }
                ForEach(expiring) { v in
                    let days = ((v.budAt! - now) / DAY_MS).rounded(.up)
                    CalloutText("\(t("now_vial_named", ["name": .string(data.peptide(v.peptideId)?.name ?? v.peptideId), "mg": .number(v.strengthMg)])) \(days <= 0 ? t("now_vial_past_bud") : t("now_vial_bud_in", ["n": .number(days)])) \(t("now_bud_is_hygiene"))")
                        .font(.footnote).callout(days <= 0 ? .rose : .tangerine)
                }
            }
        }
    }
}

extension View {
    /// The original's `Callout`: a tinted panel. Text inside takes the tone; controls keep their own colours.
    func callout(_ tone: Tone) -> some View {
        environment(\.calloutTone, tone)
            .padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// The original's `Rich`: `**bold**` spans inside translated copy.
struct RichText: View {
    var text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text((try? AttributedString(markdown: text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(text))
    }
}

private struct CalloutToneKey: EnvironmentKey { static let defaultValue: Tone? = nil }
extension EnvironmentValues {
    var calloutTone: Tone? {
        get { self[CalloutToneKey.self] }
        set { self[CalloutToneKey.self] = newValue }
    }
}

/// Text in a callout's tone.
struct CalloutText: View {
    @Environment(\.calloutTone) private var tone
    var text: String
    var bold = false
    init(_ text: String, bold: Bool = false) { self.text = text; self.bold = bold }
    var body: some View {
        RichText(text).fontWeight(bold ? .bold : nil).foregroundStyle(tone?.color ?? .primary)
    }
}
