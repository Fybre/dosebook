import SwiftUI
import BenchCore

/// Today's ring, the greeting, the streak and the week strip.
struct TodayCard: View {
    var protocols: [DoseProtocol]
    var logs: [DoseLog]
    var now: Millis

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
                        }
                        .frame(height: 36)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                        Text(String(formatWeekday(d.day).prefix(2))).font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(isToday ? .primary : .secondary)
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("\(formatWeekday(d.day)): " + (d.restDay ? t("now_nothing_scheduled_day") : idle ? t("now_day_skipped")
                        : t(isToday ? "now_day_partial" : "now_day_logged", ["taken": .number(Double(d.taken)), "expected": .number(Double(d.owed))])))
                }
            }
        }
        .card()
    }

    private var greeting: String {
        let h = LocalTime.calendar.component(.hour, from: Date(millis: now))
        return t(h < 12 ? "greeting_morning" : h < 18 ? "greeting_afternoon" : "greeting_evening")
    }
}
