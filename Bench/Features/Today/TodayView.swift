import SwiftUI
import Combine
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
    @State private var lastQuickLog: (id: String, name: String, dose: String, at: Millis)?
    @State private var logRequest: LogRequest?
    @State private var confirmEarly: String?
    @State private var addingVial: VialFor?
    @AppStorage(NowPanels.key) private var hiddenRaw = ""
    @AppStorage(NowPanels.orderKey) private var orderRaw = ""
    @Environment(\.logDoseRequests) private var logDoseRequests
    /// The last ⌘N request this screen has opened a sheet for.
    @State private var answeredLogDose = 0
    /// The screen's width: wide enough, and Now goes to two columns.
    @State private var width: CGFloat = 0
    private var wide: Bool { width >= 1000 }
    private let tick = Timer.publish(every: 60, on: .main, in: .common).autoconnect()

    /// Overdue and due-now doses, soonest first.
    private static func needsAttention(_ tracks: [Track]) -> [Track] {
        let due = tracks.filter { $0.due.state == .overdue || $0.due.state == .dueNow }
        return due.sorted { ($0.due.at ?? Double.infinity) < ($1.due.at ?? Double.infinity) }
    }

    /// Active protocols in the chosen order; by next dose, an overdue one comes first.
    private static func ordered(_ tracks: [Track], data: AppData, now: Millis) -> [Track] {
        let sort = data.settings.protocolSort
        let order = sortedProtocols(tracks.map(\.protocol_), by: sort, now: now) { data.peptide($0.peptideId)?.name ?? $0.name }.map(\.id)
        let rank = Dictionary(uniqueKeysWithValues: order.enumerated().map { ($1, $0) })
        let overdue = Dictionary(uniqueKeysWithValues: tracks.map { ($0.id, sort == .nextDose && $0.due.state == .overdue ? 0 : 1) })
        return tracks.sorted { (overdue[$0.id]!, rank[$0.id]!) < (overdue[$1.id]!, rank[$1.id]!) }
    }

    /// Everything a panel needs, worked out once per update.
    private struct NowContent {
        var data: AppData
        var tracks: [Track]
        var series: [PkSeries]
        var oneOffs: [OneOffCompound]
        var palette: Palette
        var attention: [Track]
        var hidden: Set<NowPanel>
        var mine: AppData { data.mine }
        var active: [DoseProtocol] { mine.protocols.filter(\.active) }
    }

    /// The notices and what is due, then the panels in the order chosen. Today stays first.
    @ViewBuilder private func leftColumn(_ c: NowContent, _ panels: [NowPanel]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            if !c.hidden.contains(.today) { TodayCard(protocols: c.mine.protocols, logs: c.mine.logs, now: now, earlyHours: c.data.settings.earlyHours) }
            RescueNotice()
            BackupNagCard(now: now)
            PauseBanner(now: now)
            EmptyVialCards(now: now)
            RemindersTipCard()
            noVialCards(c.tracks, data: c.data)
            if c.mine.protocols.isEmpty {
                HistoryWithoutPlanCard(now: now)
            } else {
                if let q = lastQuickLog {
                    // The track is looked up afresh each time, so its stock already counts the dose just logged.
                    let track = c.mine.logs.first { $0.id == q.id }.flatMap { l in c.tracks.first { $0.protocol_.id == l.protocolId } }
                    quickLogNote(q, track: track, data: c.data)
                }
                ForEach(c.attention) { attentionRow($0, logs: c.mine.logs) }
            }
            ForEach(panels.filter { !$0.isToday }, id: \.self) { panelView($0, c) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func rightColumn(_ c: NowContent, _ panels: [NowPanel]) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            ForEach(panels, id: \.self) { panelView($0, c) }
        }
    }

    @ViewBuilder private func panelView(_ panel: NowPanel, _ c: NowContent) -> some View {
        let data = c.data, mine = c.mine
        if !c.hidden.contains(panel) {
            switch panel {
            case .today: EmptyView()
            case .interactions:
                if !mine.protocols.isEmpty, c.active.count >= 2 { StackWarningsView(compact: true, nowMs: now).card() }
            case .laterToday:
                if !mine.protocols.isEmpty { laterToday(c.tracks, logs: mine.logs, attention: c.attention) }
            case .chart:
                if !c.series.isEmpty {
                    PkChartView(series: c.series, now: now,
                                weights: data.settings.plotWeightOnChart == true ? mine.measurements : [],
                                weightUnit: data.settings.weightUnit, describeVial: { describeVial($0, data) })
                        .card()
                        .id("chart")
                    notes(c.tracks, data: data)
                }
            case .protocols:
                if !mine.protocols.isEmpty {
                    Text(t("now_active_protocols").uppercased()).font(.caption.bold()).foregroundStyle(.secondary).id("protocols")
                    ForEach(Self.ordered(c.tracks, data: data, now: now)) { protocolCard($0, data: data).id("proto-\($0.protocol_.peptideId)") }
                }
            case .oneOffs: oneOffCard(c)
            case .weight: WeightCard(now: now).id("cards")
            case .checkIn: CheckInCard(now: now)
            case .bloodwork: LabsCard()
            case .trends:
                if !mine.protocols.isEmpty { InsightsView(tracks: c.tracks, logs: mine.logs, now: now) }
            case .worthSorting: worthSorting(c.tracks, data: data)
            }
        }
    }

    var body: some View {
        let data = store.data
        let mine = data.mine
        let active = mine.protocols.filter(\.active)
        let palette = TodayModel.palette(data, now: now)
        let tracks = TodayModel.tracks(data, now: now, palette: palette)
        let oneOffs = oneOffCompounds(data, nowMs: now)
        let series = TodayModel.series(tracks, palette: palette) + TodayModel.oneOffSeries(data, oneOffs, palette: palette)
        let attention = Self.needsAttention(tracks)
        let hidden = NowPanels.hidden(hiddenRaw)
        ScrollViewReader { proxy in
        ScrollView {
            let order = NowPanels.order(orderRaw)
            let content = NowContent(data: data, tracks: tracks, series: series, oneOffs: oneOffs, palette: palette, attention: attention, hidden: hidden)
            // Wide: the left column and a narrower right one. Narrow: one stack in the saved order.
            Group {
            if wide {
                HStack(alignment: .top, spacing: 20) {
                    leftColumn(content, order.filter(\.inLeftColumn))
                    rightColumn(content, order.filter { !$0.inLeftColumn }).frame(maxWidth: 420, alignment: .leading)
                }
            } else {
                VStack(alignment: .leading, spacing: 16) { leftColumn(content, order) }
            }
            }
            .padding()
            .pageWidth(width, limit: wide ? 1240 : READABLE_WIDTH)
        }
        // The scroll view fills the screen, so what is measured is the space there is.
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .debugAnchor(proxy)
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(t("nav_now"))
        .profileChip()
        .toolbar {
            ToolbarItem(placement: .primaryAction) { ProtocolSortMenu() }
            ToolbarItem(placement: .primaryAction) {
                Button { logRequest = LogRequest(peptideId: nil) } label: { Label(t("log_new_dose"), systemImage: "plus") }
            }
        }
        .onReceive(tick) { _ in now = nowMillis() }
        .task(id: lastQuickLog?.id) {
            guard let q = lastQuickLog else { return }
            do { try await Task.sleep(for: .milliseconds(max(0, q.at + 15_000 - nowMillis()))) }
            catch { return }
            if lastQuickLog?.id == q.id { lastQuickLog = nil }
        }
        .onChange(of: store.data.activeProfileId) { lastQuickLog = nil }
        .onChange(of: logDoseRequests) { _, _ in answerLogDoseRequest() }
        .onAppear {
            now = nowMillis()
            // ⌘N from another screen brings Now up for the first time: the request
            // came before this view did, so no change is seen; answer it here.
            answerLogDoseRequest()
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
        .sheet(item: $addingVial) { v in NavigationStack { AddVialForm(startingPeptideId: v.peptideId, alreadyMixed: v.mixed) } }
    }

    /// A part of a blend: its status, level and, if it has one, its timeline, as a single compound's card shows.
    private func partLevelBlock(_ part: PartLevel, tone: Tone) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                Text(part.name).font(.footnote.weight(.semibold))
                Pill(text: t(CURVE_KEY[part.snap.phase]!), tone: part.snap.phase == .cleared ? .neutral : .sky)
            }
            ProgressView(value: min(1, part.snap.level)).tint(tone.color)
            HStack {
                Text(t("now_percent_of_peak", ["pct": .string(jsToFixed(part.snap.percentOfPeak, 0))])).font(.footnote.weight(.semibold)).monospacedDigit()
                Text(t("curve_\(part.snap.phase.rawValue)_detail")).font(.footnote).foregroundStyle(.secondary)
            }
            if let phase = part.phase {
                VStack(alignment: .leading, spacing: 4) {
                    Text(phase.label).font(.footnote)
                    if let next = phase.hoursToNext { Text(t("now_phase_shifts", ["in": .string(formatDuration(next))])).font(.caption2).opacity(0.75) }
                }
                .foregroundStyle(tone.color)
                .padding(10).frame(maxWidth: .infinity, alignment: .leading)
                .background(tone.color.opacity(0.12), in: RoundedRectangle(cornerRadius: 10))
            }
        }
    }

    private func answerLogDoseRequest() {
        guard logDoseRequests > answeredLogDose else { return }
        answeredLogDose = logDoseRequests
        if logRequest == nil { logRequest = LogRequest(peptideId: nil) }
    }

    // MARK: Pieces

    private func describeVial(_ id: String, _ data: AppData) -> String? {
        guard let v = data.vials.first(where: { $0.id == id }) else { return nil }
        let conc = vialConcentration(v)
        let name = data.peptide(v.peptideId)?.name ?? v.peptideId
        return "\(t("now_vial_label", ["name": .string(name)])) \(conc.isFinite ? formatConcentration(conc) : t("now_not_reconstituted"))"
    }

    private func quickLogNote(_ q: (id: String, name: String, dose: String, at: Millis), track: Track?, data: AppData) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(t("now_quick_logged_note", ["name": .string(q.name)])).font(.subheadline)
                        Text("\(q.dose) · \(formatTime(q.at))").font(.caption).foregroundStyle(.secondary)
                        // Doses left at the protocol's current amount, in the same words as the compound's own card.
                        if let track, track.targetMcg > 0 {
                            (stockLine(track, low: stockIsLow(track.stock, supplyDays: track.supplyDays, data.settings)) + openVialPart(track.stock)).font(.caption)
                        }
                    }
                } icon: {
                    Image(systemName: "checkmark").foregroundStyle(Tone.leaf.color)
                }
                .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                Button { lastQuickLog = nil } label: {
                    Image(systemName: "xmark")
                        .frame(width: 44, height: 44)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(t("dismiss"))
            }
            Button {
                store.mutate { $0.removeLog(q.id) }
                lastQuickLog = nil
            } label: {
                Text(t("now_undo"))
                    .frame(minWidth: 72, minHeight: 44)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.bordered)
        }
        .card()
    }

    private func log(_ track: Track, site: InjectionSite?) {
        let p = track.protocol_
        let loggedAt = nowMillis()
        let id = store.mutate { d in
            d.addLog(DoseLog(id: "", profileId: "", protocolId: p.id, peptideId: p.peptideId, at: loggedAt, doseMcg: track.targetMcg,
                             route: p.route, site: routeHasSite(p.route) ? site : nil))
        }
        lastQuickLog = (id, track.name, doseLabel(track.targetMcg, track.peptide), loggedAt)
        now = nowMillis()
    }

    private func choices(_ track: Track, logs: [DoseLog]) -> [SiteUsage] {
        routeHasSite(track.protocol_.route)
            ? siteChoices(logs.filter { $0.peptideId == track.protocol_.peptideId }, now, allowed: store.data.allowedSites(for: track.protocol_))
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
                Text(doseLabel(track.targetMcg, track.peptide)).font(.subheadline.monospacedDigit())
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
                    Button { log(track, site: options.first?.site) } label: { Label(t("ios_now_log_now"), systemImage: "plus") }
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
                        Label(t("ios_now_log_now"), systemImage: "plus")
                    } primaryAction: {
                        log(track, site: options[0].site)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityHint(t("now_log_with_site", ["dose": .string(doseLabel(track.targetMcg, track.peptide))]))
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
                .map { (track: track, at: $0, key: "\(track.id):\($0)") }
        }.sorted { $0.at < $1.at }
        if !rows.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: t("now_later_today")).padding(.bottom, 8)
                // Keyed by protocol and time: two doses due at the same minute are two rows.
                ForEach(rows, id: \.key) { row in
                    let key = "\(row.track.id):\(row.at)"
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Text(formatTime(row.at)).font(.caption.monospacedDigit()).foregroundStyle(.secondary).frame(width: 64, alignment: .leading)
                            Circle().fill(row.track.tone.color).frame(width: 7, height: 7)
                            Text(row.track.name).font(.subheadline.weight(.medium)).foregroundStyle(row.track.tone.color)
                            Text(doseLabel(row.track.targetMcg, row.track.peptide)).font(.footnote.monospacedDigit())
                            Spacer()
                            if confirmEarly != key {
                                Button { confirmEarly = key } label: { Image(systemName: "plus.circle") }
                                    .accessibilityLabel(t("now_log_ahead_title", ["time": .string(formatTime(row.at))]))
                            }
                        }
                        if confirmEarly == key {
                            // A dose logged hours early is usually a misread row, so it asks.
                            Text(t("now_not_due_until", ["time": .string(formatTime(row.at)), "when": .string(relativeTime(row.at, nowMs: now))]))
                                .font(.caption).foregroundStyle(.secondary)
                            // What logging it here would do: where it goes and how much to draw.
                            let site = routeHasSite(row.track.protocol_.route)
                                ? suggestSite(logs.filter { $0.peptideId == row.track.protocol_.peptideId }, nowMillis(), allowed: store.data.allowedSites(for: row.track.protocol_)) : nil
                            HStack(spacing: 8) {
                                if let site { Text(t("now_at_site", ["site": .string(siteLabel(site))])) }
                                DoseMarksText(peptideId: row.track.protocol_.peptideId, doseMcg: row.track.targetMcg, route: row.track.protocol_.route, nowMs: now)
                            }
                            .font(.caption.weight(.medium))
                            HStack {
                                Button(t("now_yes_log_it")) {
                                    confirmEarly = nil
                                    log(row.track, site: site)
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

    /// Compounds taken recently with no protocol, so a one-off dose does not vanish from Now once logged.
    @ViewBuilder private func oneOffCard(_ c: NowContent) -> some View {
        if !c.oneOffs.isEmpty {
            VStack(alignment: .leading, spacing: 0) {
                CardHeader(title: t("ios_panel_oneoffs")).padding(.bottom, 8)
                ForEach(c.oneOffs) { o in
                    let tone = c.palette.byPeptide[o.peptideId] ?? .neutral
                    let peptide = c.data.peptide(o.peptideId)
                    let last = o.last
                    let curve = peptide.flatMap { isBlend($0) ? nil : curveFor($0, yours: c.data.halfLifeOverrides[o.peptideId]) }
                    let snap = curve.flatMap { cv in
                        isMeasuredInPeople(cv.basis)
                            ? snapshot(now, o.doses.map { DoseEvent(at: $0.at, amountMcg: $0.doseMcg, vialId: $0.vialId) }, cv.params, last.doseMcg) : nil
                    }
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 6) {
                            Circle().fill(tone.color).frame(width: 8, height: 8)
                            NavigationLink(value: o.peptideId) { Text(peptide?.name ?? o.peptideId).font(.subheadline.weight(.medium)) }.buttonStyle(.plain)
                            if let snap { Pill(text: t(CURVE_KEY[snap.phase]!), tone: snap.phase == .cleared ? .neutral : .sky) }
                            Spacer()
                            Button { logRequest = LogRequest(peptideId: o.peptideId) } label: { Label(t("now_log_short"), systemImage: "plus") }
                                .buttonStyle(.bordered).controlSize(.small)
                        }
                        HStack(spacing: 8) {
                            Text(t("now_last_dose") + " " + relativeTime(last.at, nowMs: now))
                            Text(doseLabel(last.doseMcg, peptide)).monospacedDigit()
                            if let u = last.units { Text(t("ios_units_count", ["n": .string(trim(u, 2))])).monospacedDigit() }
                            if let site = last.site, routeHasSite(last.route) { Text(siteLabel(site)) }
                        }
                        .font(.caption).foregroundStyle(.secondary)
                        if let snap {
                            ProgressView(value: min(1, snap.level)).tint(tone.color)
                            Text(t("now_percent_of_peak", ["pct": .string(jsToFixed(snap.percentOfPeak, 0))])).font(.footnote.weight(.semibold)).monospacedDigit()
                        }
                        if o.doses.filter({ $0.at >= now - 14 * DAY_MS }).count > 1 {
                            Text(t("count_doses", ["n": .number(Double(o.doses.filter { $0.at >= now - 14 * DAY_MS }.count))]) + " " + t("ios_oneoff_window"))
                                .font(.caption).foregroundStyle(.tertiary)
                        }
                    }
                    .padding(.vertical, 8)
                    if o.id != c.oneOffs.last?.id { Divider() }
                }
            }
            .card()
            .id("oneoffs")
        }
    }

    private func protocolCard(_ track: Track, data: AppData) -> some View {
        let yours = track.curve?.basis == .yours ? data.halfLifeOverrides[track.protocol_.peptideId]?.hours : nil
        let low = stockIsLow(track.stock, supplyDays: track.supplyDays, data.settings)
        return VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top) {
                Image(systemName: "syringe").foregroundStyle(track.tone.color).frame(width: 34, height: 34)
                    .background(track.tone.color.opacity(0.15), in: RoundedRectangle(cornerRadius: 9))
                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        NavigationLink(value: track.protocol_.peptideId) { Text(track.name).font(.headline) }.buttonStyle(.plain)
                        if let snap = track.snap { Pill(text: t(CURVE_KEY[snap.phase]!), tone: snap.phase == .cleared ? .neutral : .sky) }
                    }
                    if let contents = blendContents(track.peptide) { Text(contents).font(.caption).foregroundStyle(.secondary) }
                    if (track.due.state == .scheduled || track.due.state == .upcoming), let at = track.due.at {
                        Text(t("now_next_at", ["when": .string(relativeTime(at, nowMs: now))])).font(.caption).foregroundStyle(.secondary)
                    }
                    HStack(spacing: 6) {
                        Text(doseLabelPerDay(track.targetMcg, track.perDay, track.peptide))
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
            ForEach(track.partLevels) { part in partLevelBlock(part, tone: track.tone) }
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
                    + Text(" " + (!track.partLevels.isEmpty ? track.partLevels.map { "\($0.name) \(formatHalfLife($0.halfLifeHours))" }.joined(separator: " · ")
                                  : !track.blendParts.isEmpty ? t("now_per_component")
                                  : yours.map { t("now_half_life_yours", ["hours": .string(formatHalfLife($0)), "marker": .string(t("now_your_figure"))]) }
                                  ?? formatHalfLife(track.peptide?.halfLifeHours)))
                stockLine(track, low: low)
                if track.targetMcg > 0 {
                    switch supplyOutlook(track.stock, track.protocol_, now) {
                    case .runsOut(let at): Text(t("stock_runs_out_line", ["date": .string(formatDate(at, nowMs: now))]))
                    case .beyondHorizon: Text(t("stock_over_a_year"))
                    case .unknown: EmptyView()
                    }
                    if low {
                        Button { addingVial = VialFor(peptideId: track.protocol_.peptideId) } label: {
                            Label(t("stock_add_vial"), systemImage: "plus")
                        }.buttonStyle(.bordered)
                    }
                }
                if track.stock.needsReconstitution {
                    Text(t("now_record_reconstitution")).foregroundStyle(Tone.tangerine.color)
                }
            }
            .font(.caption)
        }
        .card()
    }

    /// " · 4 in the open vial", when there are sealed vials as well, so the total above is not read as one vial's worth.
    private func openVialPart(_ stock: Stock) -> Text {
        guard stock.openCount > 0, stock.dosesInOpenVials < stock.dosesRemaining else { return Text("") }
        return Text(" · " + t("ios_stock_in_open_vial", ["n": .number(stock.dosesInOpenVials)])).foregroundColor(.secondary)
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

    /// Never had a vial is not running low: near the top, with a way to add one.
    /// Running low stays under "worth sorting".
    @ViewBuilder private func noVialCards(_ tracks: [Track], data: AppData) -> some View {
        let noVial = tracks.filter { $0.targetMcg > 0 && !hasAnyVial(data, $0.protocol_.peptideId) }
            .reduce(into: [Track]()) { out, t in if !out.contains(where: { $0.protocol_.peptideId == t.protocol_.peptideId }) { out.append(t) } }
        if !noVial.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CalloutText(noVial.count == 1 ? t("ios_now_no_vial", ["name": .string(noVial[0].name)]) : t("ios_now_no_vial_many")).font(.footnote)
                ForEach(noVial) { track in
                    HStack(spacing: 8) {
                        if noVial.count > 1 { Text(track.name).font(.subheadline.weight(.medium)).lineLimit(1); Spacer(minLength: 4) }
                        Button { addingVial = VialFor(peptideId: track.protocol_.peptideId) } label: { Label(t("ios_now_add_vial"), systemImage: "plus") }
                            .buttonStyle(.bordered).controlSize(.small).fixedSize()
                        if routeHasSite(track.protocol_.route) {
                            Button(t("ios_now_add_mixed")) { addingVial = VialFor(peptideId: track.protocol_.peptideId, mixed: true) }
                                .buttonStyle(.bordered).controlSize(.small).fixedSize()
                        }
                    }
                }
            }
            .callout(.sky)
        }
    }

    @ViewBuilder private func worthSorting(_ tracks: [Track], data: AppData) -> some View {
        let low = tracks.filter { stockIsLow($0.stock, supplyDays: $0.supplyDays, data.settings) && $0.targetMcg > 0 && hasAnyVial(data, $0.protocol_.peptideId) }
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
