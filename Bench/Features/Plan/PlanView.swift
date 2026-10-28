import SwiftUI
import BenchCore
import BenchStore

struct PlanView: View {
    @Environment(AppStore.self) private var store
    @State private var editing: EditTarget?

    enum EditTarget: Identifiable {
        case new, existing(DoseProtocol), scan, startingWith(String)
        var id: String {
            switch self {
            case .new: "new"
            case .existing(let p): p.id
            case .scan: "scan"
            case .startingWith(let id): "start-" + id
            }
        }
    }

    /// The page's visible width, for `pageWidth`.
    @State private var width: CGFloat = 0
    @State private var pausing = false

    var body: some View {
        let now = nowMillis()
        let data = store.data
        let protocols = data.mine.protocols
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text(t("plan_subtitle")).font(.subheadline).foregroundStyle(.secondary)
                PauseBanner(now: now)
                if protocols.isEmpty {
                    ContentUnavailableView {
                        Label(t("plan_no_protocols"), systemImage: "checklist")
                    } description: { Text(t("plan_no_protocols_desc")) } actions: {
                        Button(t("plan_create_one")) { editing = .new }.buttonStyle(.borderedProminent)
                    }
                }
                StackWarningsView(nowMs: now).card()
                    .opacity(protocols.filter(\.active).count >= 2 ? 1 : 0)
                    .frame(height: protocols.filter(\.active).count >= 2 ? nil : 0)
                // Cards first: on a phone the fortnight list would push them a long way down.
                ForEach(sortedProtocols(protocols, by: data.settings.protocolSort, now: now) { data.peptide($0.peptideId)?.name ?? $0.name }) { p in
                    ProtocolCard(protocol_: p, nowMs: now, onEdit: { editing = .existing(p) })
                }
                if protocols.contains(where: \.active) { UpcomingView(nowMs: now) }
                PctPanelView(nowMs: now)
            }
            .padding()
            .pageWidth(width)
        }
        // The scroll view fills the screen, so what is measured is the space there is.
        .frame(maxWidth: .infinity)
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
        .scrollBounceBehavior(.basedOnSize, axes: .horizontal)
        .background(Color(.systemGroupedBackground))
        .navigationTitle(t("plan_title"))
        .profileChip()
        .peptideDestination()
        .toolbar {
            // Occasional actions, apart from the + that makes a protocol.
            ToolbarItem(placement: .secondaryAction) {
                Button { pausing = true } label: { Label(t("ios_pause_title"), systemImage: "pause.circle") }
                    .disabled(currentPause(protocols, now) != nil || !protocols.contains(where: \.active))
            }
            ToolbarItem(placement: .primaryAction) { ProtocolSortMenu() }
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { editing = .new } label: { Label(t("plan_new_protocol"), systemImage: "square.and.pencil") }
                    Button { editing = .scan } label: { Label(t("ios_scan_title"), systemImage: "camera.viewfinder") }
                } label: { Label(t("plan_new_protocol"), systemImage: "plus") }
            }
        }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if editing == nil, args.contains("-scanImage") { editing = .scan }
            // `-newProtocol <peptideId>`: the protocol form, started on that compound.
            if editing == nil, let i = args.firstIndex(of: "-newProtocol"), i + 1 < args.count { editing = .startingWith(args[i + 1]) }
        }
        #endif
        .sheet(isPresented: $pausing) { NavigationStack { PauseSheet() } }
        .sheet(item: $editing) { target in
            NavigationStack {
                switch target {
                case .new: ProtocolForm(initial: nil)
                case .existing(let p): ProtocolForm(initial: p)
                case .scan: ScanVialView { id in editing = .startingWith(id) }
                case .startingWith(let id): ProtocolForm(initial: nil, startingPeptideId: id)
                }
            }
        }
    }
}

struct ProtocolCard: View {
    @Environment(AppStore.self) private var store
    var protocol_: DoseProtocol
    var nowMs: Millis
    var onEdit: () -> Void
    @State private var confirmDelete = false

    var body: some View {
        let p = protocol_
        let peptide = store.data.peptide(p.peptideId)
        let bands = protocolPhases(p)
        let current = bands != nil ? phaseSpanAt(p, nowMs) : nil
        let showSchedule = current?.schedule ?? p.schedule
        let next = p.active ? protocolNextDoseTime(p, nowMs) : nil
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    HStack(spacing: 6) {
                        NavigationLink(value: p.peptideId) { Text(peptide?.name ?? p.peptideId).font(.headline) }
                            .buttonStyle(.plain)
                        if !p.active || isPaused(p, nowMs) { Pill(text: t("plan_paused")) }
                        if let bands, let current {
                            Pill(text: "\(p.phases?.isEmpty == false ? t("plan_week_band") : t("plan_step")) \(current.index + 1) \(t("plan_of")) \(bands.count)", tone: .sky)
                        }
                    }
                    Text(p.name).font(.subheadline).foregroundStyle(.secondary)
                    if let contents = blendContents(peptide) { Text(contents).font(.caption).foregroundStyle(.secondary) }
                }
                Spacer()
                Menu {
                    Button(action: onEdit) { Label(t("plan_edit_protocol"), systemImage: "pencil") }
                    Button { store.mutate { $0.updateProtocol(p.id) { $0.active.toggle() } } } label: {
                        Label(p.active ? t("plan_pause_protocol") : t("plan_resume_protocol"), systemImage: p.active ? "pause" : "play")
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Label(t("plan_delete_named", ["name": .string(p.name)]), systemImage: "trash") }
                } label: { Image(systemName: "ellipsis.circle").font(.title3) }
            }
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 12) { figures(p, showSchedule, next) }
                VStack(alignment: .leading, spacing: 2) { figures(p, showSchedule, next) }
            }
            .font(.footnote)
            Text("\(hasStarted(p, nowMs) ? t("plan_started") : t("plan_starts")) \(formatDate(p.startedAt))"
                 + ((p.sites?.isEmpty == false) ? " · " + t("plan_rotating_sites", ["n": .number(Double(p.sites!.count))]) : ""))
                .font(.caption).foregroundStyle(.secondary)
            if let bands, !bands.isEmpty {
                Divider()
                HStack(spacing: 3) {
                    ForEach(bands.indices, id: \.self) { i in
                        Capsule().fill(current.map { i <= $0.index } == true ? Tone.tangerine.color : Color(.systemFill)).frame(height: 6)
                    }
                }
                Text(p.phases?.isEmpty == false ? t("plan_own_plan_bands", ["n": .number(Double(bands.count))]) : t("plan_dose_advances"))
                    .font(.caption).foregroundStyle(.secondary)
            } else if !(p.titration ?? []).isEmpty {
                Divider()
                Text(t("plan_fixed_dose_reference")).font(.caption).foregroundStyle(.secondary)
            }
        }
        .card()
        .opacity(p.active ? 1 : 0.6)
        .confirmationDialog(t("plan_delete_named", ["name": .string(p.name)]), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(t("plan_delete_named", ["name": .string(p.name)]), role: .destructive) { store.mutate { $0.removeProtocol(p.id) } }
        }
    }

    @ViewBuilder private func figures(_ p: DoseProtocol, _ s: Schedule, _ next: Millis?) -> some View {
        Text(doseLabelPerDay(scheduledDoseMcg(p, nowMs), dosesPerDoseDay(s), store.data.peptide(p.peptideId))).monospacedDigit().foregroundStyle(Tone.tangerine.color)
        Text(describeSchedule(s)).foregroundStyle(.secondary)
        Text("\(trim(protocolDosesPerWeek(p, nowMs), 2)) \(t("plan_per_week"))").foregroundStyle(.tertiary)
        if let next { Text("\(t("plan_next")) \(relativeTime(next, nowMs: nowMs))").foregroundStyle(.secondary) }
    }
}

/// The next fortnight of doses across every active protocol, by day.
struct UpcomingView: View {
    @Environment(AppStore.self) private var store
    var nowMs: Millis
    @State private var showAll = false
    /// Wide enough for "11:00 PM" at the user's text size, so it never breaks.
    @ScaledMetric(relativeTo: .caption) private var timeWidth: CGFloat = 70

    /// The days shown before "show more".
    private static let firstDays = 3

    private struct Row: Identifiable { var id: String; var at: Millis; var protocolId: String; var peptideId: String; var name: String; var route: Route; var doseMcg: Double }

    var body: some View {
        let data = store.data
        let active = data.mine.protocols.filter(\.active)
        let palette = assignColors(colorSubjects(active, resolve: { data.peptide($0) }, nowMs: nowMs))
        let to = endOfLocalDay(nowMs + 13 * DAY_MS)
        let rows = active.flatMap { p in
            protocolDoseTimesBetween(p, nowMs, to).map {
                Row(id: "\(p.id)-\($0)", at: $0, protocolId: p.id, peptideId: p.peptideId, name: data.peptide(p.peptideId)?.name ?? p.peptideId, route: p.route, doseMcg: scheduledDoseMcg(p, $0))
            }
        }.sorted { $0.at < $1.at }
        let days = Dictionary(grouping: rows) { startOfLocalDay($0.at) }.sorted { $0.key < $1.key }
        let shown = showAll ? days : Array(days.prefix(Self.firstDays))
        if !days.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                CardHeader(title: t("plan_next_two_weeks"))
                ForEach(Array(shown.enumerated()), id: \.element.key) { index, entry in
                    if index > 0 { Divider() }
                    dayBlock(entry.key, entry.value, data: data, palette: palette)
                }
                if days.count > Self.firstDays {
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) { showAll.toggle() }
                    } label: {
                        Text(showAll ? t("ios_upcoming_fewer") : t("ios_upcoming_more", ["days": .string(t("count_days", ["n": .number(Double(days.count - Self.firstDays))]))]))
                            .font(.footnote.weight(.medium))
                    }
                    .padding(.top, 2)
                }
            }
            .card()
        }
    }

    /// A day: its heading, then each time with what is taken at it.
    private func dayBlock(_ day: Millis, _ rows: [Row], data: AppData, palette: Palette) -> some View {
        // Doses at the same moment share one time.
        let times = Dictionary(grouping: rows) { $0.at }.sorted { $0.key < $1.key }
        return VStack(alignment: .leading, spacing: 8) {
            Text("\(formatWeekday(day)) \(formatDate(day))").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(times, id: \.key) { at, group in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(formatTime(at)).font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .lineLimit(1).fixedSize().frame(width: timeWidth, alignment: .leading)
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(group) { r in
                            let tone = palette.byProtocol[r.protocolId]
                            let peptide = data.peptide(r.peptideId)
                            VStack(alignment: .leading, spacing: 1) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    if let tone { Circle().fill(tone.color).frame(width: 7, height: 7) }
                                    Text(r.name).font(.footnote.weight(.medium)).foregroundStyle(tone?.color ?? .primary)
                                }
                                HStack(spacing: 6) {
                                    Text(doseLabel(r.doseMcg, peptide, resolve: { data.peptide($0) })).monospacedDigit()
                                    DoseMarksText(peptideId: r.peptideId, doseMcg: r.doseMcg, route: r.route, nowMs: nowMs)
                                }
                                .font(.caption).foregroundStyle(.secondary)
                                .padding(.leading, tone == nil ? 0 : 13)
                            }
                        }
                    }
                }
            }
        }
    }
}
