import SwiftUI
import DosebookCore

/// "3w 5d", or "5d" under a week.
func runLengthText(_ days: Int) -> String {
    let (w, d) = runLengthParts(days)
    return w > 0 ? t("ios_run_wd", ["w": .number(Double(w)), "d": .number(Double(d))]) : t("ios_run_d", ["d": .number(Double(d))])
}

/// The short badge: where it sits in the cycle, or the day number when there is no cycle.
func runBadgeText(_ r: RunProgress) -> String {
    guard let c = r.cycle else { return t("ios_run_day", ["n": .number(Double(r.day))]) }
    switch c.phase {
    case .on: return t("ios_run_on_week", ["n": .number(Double(c.week)), "total": .number(Double(c.weeks))])
    case .off: return t("ios_run_off_week", ["n": .number(Double(c.week)), "total": .number(Double(c.weeks))])
    case .finished: return t("ios_run_finished")
    }
}

/// How long it has run, less any pause: "3w 1d on · 9 days paused", or "3w 5d in" when nothing was paused.
func runLengthLine(_ r: RunProgress) -> String {
    r.daysPaused > 0
        ? t("ios_run_on_paused", ["length": .string(runLengthText(r.daysOn)), "n": .number(Double(r.daysPaused))])
        : t("ios_run_in", ["length": .string(runLengthText(r.day))])
}

/// A thin bar across the weeks of the current on or off stretch, and what comes next.
struct CycleBar: View {
    var cycle: CycleProgress
    var tone: Color = .accentColor
    var body: some View {
        if cycle.phase != .finished {
            VStack(alignment: .leading, spacing: 4) {
                GeometryReader { g in
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color(.systemFill))
                        Capsule().fill(cycle.phase == .on ? tone : Color.secondary)
                            .frame(width: g.size.width * min(1, Double(cycle.week) / Double(max(1, cycle.weeks))))
                    }
                }.frame(height: 6)
                if let at = cycle.changesAt {
                    Text(cycle.phase == .on && cycle.weeksOff > 0
                         ? t("ios_run_then_off", ["n": .number(Double(cycle.weeksOff)), "date": .string(formatDate(at))])
                         : cycle.phase == .on ? t("ios_run_course_ends", ["date": .string(formatDate(at))])
                         : t("ios_run_back_on", ["date": .string(formatDate(at))]))
                        .font(.caption2).foregroundStyle(.secondary)
                }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(Text(t("ios_run_on_week", ["n": .number(Double(cycle.week)), "total": .number(Double(cycle.weeks))])))
        }
    }
}
