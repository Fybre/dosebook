import SwiftUI
import BenchCore

/// A month of the Log: a dot per compound per day in its chart colour, hollow
/// for a skip, and a bar under any day that was rated. Swipe or use the arrows
/// to move between months; tap a day to see it below.
struct LogCalendarView: View {
    var logs: [DoseLog]
    var checkIns: [CheckIn]
    var palette: Palette
    var weekStartsOn: Int
    var now: Millis
    @Binding var month: Millis
    @Binding var selected: Millis?

    var body: some View {
        let marks = marksByDay(logs)
        let rated = Dictionary(checkIns.map { (startOfLocalDay($0.at), $0) }, uniquingKeysWith: { a, _ in a })
        let today = startOfLocalDay(now)
        let earliest = startOfLocalMonth(logs.map(\.at).min() ?? now)
        let thisMonth = startOfLocalMonth(now)
        VStack(spacing: 10) {
            HStack {
                Button { month = addMonths(month, -1) } label: { Image(systemName: "chevron.left") }
                    .disabled(month <= earliest)
                    .accessibilityLabel(t("ios_prev_month"))
                Spacer()
                Text(monthTitle(month)).font(.headline)
                Spacer()
                Button { month = addMonths(month, 1) } label: { Image(systemName: "chevron.right") }
                    .disabled(month >= thisMonth)
                    .accessibilityLabel(t("ios_next_month"))
            }
            .buttonStyle(.borderless)
            HStack(spacing: 0) {
                ForEach(weekdayOrder(weekStartsOn: weekStartsOn), id: \.self) { wd in
                    Text(t(WEEKDAY_KEYS[wd]).prefix(2)).font(.caption2.weight(.semibold)).foregroundStyle(.secondary).frame(maxWidth: .infinity)
                }
            }
            .accessibilityHidden(true)
            ForEach(Array(monthGrid(month, weekStartsOn: weekStartsOn).enumerated()), id: \.offset) { _, week in
                HStack(spacing: 0) {
                    ForEach(Array(week.enumerated()), id: \.offset) { _, day in
                        if let day {
                            cell(day, marks: marks[day] ?? [], checkIn: rated[day], isToday: day == today, future: day > today)
                        } else {
                            Color.clear.frame(maxWidth: .infinity, minHeight: 48)
                        }
                    }
                }
            }
            if month != thisMonth || selected != today {
                Button(t("checkin_today")) { month = thisMonth; selected = today }.font(.footnote).buttonStyle(.borderless)
            }
        }
        .contentShape(Rectangle())
        .gesture(DragGesture(minimumDistance: 30).onEnded { g in
            guard abs(g.translation.width) > abs(g.translation.height) else { return }
            if g.translation.width < 0, month < thisMonth { month = addMonths(month, 1) }
            if g.translation.width > 0, month > earliest { month = addMonths(month, -1) }
        })
    }

    private func cell(_ day: Millis, marks: [DayMark], checkIn: CheckIn?, isToday: Bool, future: Bool) -> some View {
        let isSelected = selected == day
        let tone = checkIn.flatMap { c in
            lowestRatedTone(SYMPTOMS.filter { c.ratings[$0.id.rawValue] != nil }.map { (c.ratings[$0.id.rawValue]!, $0.higherIsBetter) })
        }
        return Button { selected = day } label: {
            VStack(spacing: 3) {
                Text(String(LocalTime.calendar.component(.day, from: Date(millis: day))))
                    .font(.subheadline.weight(isToday ? .bold : .regular).monospacedDigit())
                    .foregroundStyle(isSelected ? Color.white : future ? Color.secondary.opacity(0.5) : isToday ? Color.accentColor : Color.primary)
                    .frame(width: 30, height: 30)
                    .background(isSelected ? Color.accentColor : .clear, in: Circle())
                HStack(spacing: 2) {
                    ForEach(Array(marks.prefix(4).enumerated()), id: \.offset) { _, m in
                        let color = doseColor(palette, protocolId: m.protocolId, peptideId: m.peptideId)?.color ?? Color.secondary
                        if m.skippedOnly {
                            Circle().strokeBorder(color, lineWidth: 1.2).frame(width: 6, height: 6)
                        } else {
                            Circle().fill(color).frame(width: 6, height: 6)
                        }
                    }
                    if marks.count > 4 { Text("+").font(.system(size: 8, weight: .bold)).foregroundStyle(.secondary) }
                }
                .frame(height: 6)
                Capsule().fill(tone?.color ?? .clear).frame(width: 14, height: 2)
            }
            .frame(maxWidth: .infinity, minHeight: 48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(future)
        .accessibilityLabel(dayLabel(day, marks: marks, rated: checkIn != nil))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func dayLabel(_ day: Millis, marks: [DayMark], rated: Bool) -> String {
        let doses = marks.reduce(0) { $0 + ($1.skippedOnly ? 0 : $1.count) }
        var parts = [formatDate(day, nowMs: now)]
        if doses > 0 { parts.append(t("count_doses", ["n": .number(Double(doses))])) }
        if rated { parts.append(t("log_how_day_went")) }
        return parts.joined(separator: ", ")
    }

    private func monthTitle(_ ms: Millis) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: I18n.lang.rawValue)
        f.calendar = LocalTime.calendar
        f.timeZone = LocalTime.calendar.timeZone
        f.setLocalizedDateFormatFromTemplate("LLLLyyyy")
        return f.string(from: Date(millis: ms))
    }
}
