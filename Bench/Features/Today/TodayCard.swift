import SwiftUI
import BenchCore
import BenchStore

/// Today's ring, the greeting, the streak and the week strip.
struct TodayCard: View {
    var protocols: [DoseProtocol]
    var logs: [DoseLog]
    var now: Millis
    @State private var detailDay: DetailDay?

    struct DetailDay: Identifiable { var id: Millis }

    var body: some View {
        let today = todayProgress(protocols, logs, now)
        let streak = currentStreak(protocols, logs, now)
        let week = recentDays(protocols, logs, now, days: 7)
        let tone: Tone = today.complete ? .leaf : today.taken > 0 ? .mint : .neutral
        VStack(spacing: 18) {
            HStack(spacing: 18) {
                ZStack {
                    Circle().stroke(Color(.systemFill), lineWidth: 9)
                    Circle().trim(from: 0, to: today.fraction).stroke(tone.color, style: StrokeStyle(lineWidth: 9, lineCap: .round)).rotationEffect(.degrees(-90))
                    if today.restDay {
                        Text(t("now_rest")).font(.caption2.bold()).foregroundStyle(.secondary)
                    } else if today.owed == 0 {
                        Text(t("log_skipped")).font(.caption2.bold()).foregroundStyle(.secondary)
                    } else {
                        VStack(spacing: 0) {
                            Text("\(today.taken)").font(.title2.weight(.heavy)).monospacedDigit()
                            Text("\(t("plan_of")) \(today.owed)").font(.caption2.weight(.semibold)).foregroundStyle(.secondary)
                        }
                    }
                }
                .frame(width: 84, height: 84)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(t("now_done_today", ["taken": .number(Double(today.taken)), "expected": .number(Double(today.owed))]))
                VStack(alignment: .leading, spacing: 4) {
                    Text(greeting).font(.title2.weight(.heavy))
                    Text(today.restDay ? t("now_nothing_scheduled") : today.complete ? t("now_all_logged") : t("now_left_to_log", ["n": .number(Double(today.owed - today.taken))]))
                        .font(.subheadline).foregroundStyle(.secondary)
                    if streak > 0 {
                        Label(t("now_streak_days", ["n": .number(Double(streak))]), systemImage: "flame.fill")
                            .font(.footnote.bold()).foregroundStyle(Tone.tangerine.color)
                            .padding(.horizontal, 10).padding(.vertical, 4)
                            .background(Tone.tangerine.color.opacity(0.15), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }
            HStack(alignment: .bottom, spacing: 6) {
                ForEach(week, id: \.day) { d in
                    let isToday = d.day == startOfLocalDay(now)
                    let idle = d.owed == 0
                    // Doses were due and none were logged: worth seeing at a glance.
                    let missed = !isToday && !idle && d.taken == 0
                    Button { detailDay = DetailDay(id: d.day) } label: {
                        VStack(spacing: 5) {
                            ZStack(alignment: .bottom) {
                                RoundedRectangle(cornerRadius: 8)
                                    .fill(idle || isToday || d.complete || d.taken == 0 ? Color(.systemFill) : Tone.tangerine.color)
                                    .opacity(idle ? 0.5 : 1)
                                if (isToday || d.complete) && !idle && d.fraction > 0 {
                                    GeometryReader { g in
                                        RoundedRectangle(cornerRadius: 8).fill(Tone.leaf.color)
                                            .frame(height: g.size.height * d.fraction).frame(maxHeight: .infinity, alignment: .bottom)
                                    }
                                }
                                if isToday { RoundedRectangle(cornerRadius: 8).strokeBorder(Color.secondary, lineWidth: 1.5) }
                                if missed { RoundedRectangle(cornerRadius: 8).strokeBorder(Tone.rose.color, lineWidth: 2) }
                            }
                            .frame(height: 36)
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            Text(String(formatWeekday(d.day).prefix(2))).font(.system(size: 10, weight: .semibold))
                                .foregroundStyle(isToday ? .primary : missed ? Tone.rose.color : .secondary)
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(formatWeekday(d.day)): " + (d.restDay ? t("now_nothing_scheduled_day") : missed ? t("ios_day_missed") : idle ? t("now_day_skipped")
                        : t(isToday ? "now_day_partial" : "now_day_logged", ["taken": .number(Double(d.taken)), "expected": .number(Double(d.owed))])))
                    .accessibilityAddTraits(.isButton)
                }
            }
        }
        .card()
        #if DEBUG
        .onAppear {
            // `-dayDetail <n>` opens the day n days ago, for screenshots.
            let args = ProcessInfo.processInfo.arguments
            if detailDay == nil, let i = args.firstIndex(of: "-dayDetail"), i + 1 < args.count, let n = Double(args[i + 1]) {
                let day = startOfLocalDay(addLocalDays(now, -n))
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { detailDay = DetailDay(id: day) }
            }
        }
        #endif
        .sheet(item: $detailDay) { d in NavigationStack { DayDetailSheet(day: d.id, now: now) }.presentationDetents([.medium, .large]) }
    }

    private var greeting: String {
        let h = LocalTime.calendar.component(.hour, from: Date(millis: now))
        return t(h < 12 ? "greeting_morning" : h < 18 ? "greeting_afternoon" : "greeting_evening")
    }
}

/// One day, dose by dose: what each protocol asked for and what became of it,
/// then anything logged that no protocol asked for.
struct DayDetailSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    var day: Millis
    var now: Millis

    var body: some View {
        let data = store.data
        let mine = data.mine
        let breakdown = dayBreakdown(mine.protocols, mine.logs, day, nowMs: now)
        let progress = dayProgress(mine.protocols, mine.logs, day)
        let palette = assignColors(colorSubjects(mine.protocols.filter(\.active), resolve: { data.peptide($0) }, nowMs: now))
        List {
            if breakdown.protocols.isEmpty {
                Section { Text(t("ios_day_rest")).foregroundStyle(.secondary) }
            } else {
                Section {
                    Text(t("ios_day_summary", ["taken": .number(Double(progress.taken)), "owed": .number(Double(progress.owed))]))
                        .font(.subheadline.weight(.semibold))
                }
            }
            ForEach(breakdown.protocols, id: \.protocolId) { p in
                let proto = mine.protocols.first { $0.id == p.protocolId }
                let tone = doseColor(palette, protocolId: p.protocolId, peptideId: p.peptideId)
                Section {
                    ForEach(Array(p.slots.enumerated()), id: \.offset) { _, s in
                        slotRow(s.at, s.slot, dose: proto.map { scheduledDoseMcg($0, s.at) })
                    }
                } header: {
                    HStack(spacing: 6) {
                        Circle().fill(tone?.color ?? .secondary).frame(width: 8, height: 8)
                        Text(proto?.name ?? data.peptide(p.peptideId)?.name ?? p.peptideId)
                    }
                }
            }
            if !breakdown.unplanned.isEmpty {
                Section(t("ios_day_unplanned")) {
                    ForEach(breakdown.unplanned) { l in
                        HStack {
                            Text(formatTime(l.at)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary).frame(width: 76, alignment: .leading)
                            Text(data.peptide(l.peptideId)?.name ?? l.peptideId).font(.subheadline)
                            Spacer()
                            Text(l.isSkipped ? t("ios_day_skipped") : formatDose(l.doseMcg)).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                        }
                    }
                }
            }
        }
        .navigationTitle(startOfLocalDay(day) == startOfLocalDay(now) ? t("checkin_today") : "\(formatWeekday(day)), \(formatDate(day, nowMs: now))")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .confirmationAction) { Button(t("done")) { dismiss() } } }
    }

    private func slotRow(_ at: Millis, _ slot: ProtocolDay.Slot, dose: Double?) -> some View {
        let (icon, tone, text): (String, Tone, String) = {
            switch slot {
            case .taken(let l): return ("checkmark.circle.fill", .leaf, t("ios_day_logged_at", ["time": .string(formatTime(l.at))]))
            case .skipped: return ("arrow.uturn.right.circle", .neutral, t("ios_day_skipped"))
            case .missed: return ("xmark.circle.fill", .rose, t("ios_day_missed"))
            case .due: return ("clock", .sky, t("ios_day_due"))
            }
        }()
        let amount: String? = { if case .taken(let l) = slot { return formatDose(l.doseMcg) }; return dose.map { formatDose($0) } }()
        return HStack(spacing: 10) {
            Image(systemName: icon).foregroundStyle(tone.color).font(.body)
            VStack(alignment: .leading, spacing: 2) {
                Text(formatTime(at)).font(.subheadline.monospacedDigit())
                Text(text).font(.caption).foregroundStyle(tone == .neutral ? .secondary : tone.color)
            }
            Spacer()
            if let amount { Text(amount).font(.subheadline.monospacedDigit()).foregroundStyle(.secondary) }
        }
        .accessibilityElement(children: .combine)
    }
}
