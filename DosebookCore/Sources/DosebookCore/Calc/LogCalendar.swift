import Foundation

// The Log's month view: a grid of local days, and one mark per compound per day.
// Not in the original; built here for the iOS Log.

/// One compound on one day.
public struct DayMark: Equatable, Sendable {
    public var peptideId: String
    /// The protocol of the first dose actually taken that day, for its colour.
    public var protocolId: String?
    /// Every entry for this compound that day was a skip.
    public var skippedOnly: Bool
    public var count: Int
}

/// Marks per local day, compounds in the order they were first taken that day.
public func marksByDay(_ logs: [DoseLog]) -> [Millis: [DayMark]] {
    var out: [Millis: [DayMark]] = [:]
    for l in logs.stableSorted(by: { $0.at < $1.at }) {
        let day = startOfLocalDay(l.at)
        var marks = out[day] ?? []
        if let i = marks.firstIndex(where: { $0.peptideId == l.peptideId }) {
            marks[i].count += 1
            if !l.isSkipped {
                if marks[i].skippedOnly { marks[i].protocolId = l.protocolId }
                marks[i].skippedOnly = false
            }
        } else {
            marks.append(DayMark(peptideId: l.peptideId, protocolId: l.protocolId, skippedOnly: l.isSkipped, count: 1))
        }
        out[day] = marks
    }
    return out
}

/// The first local day of the month holding `ms`.
public func startOfLocalMonth(_ ms: Millis) -> Millis {
    let cal = LocalTime.calendar
    let c = cal.dateComponents([.year, .month], from: Date(millis: ms))
    return cal.date(from: c)!.millis
}

/// The first day of the month `months` away, keeping local midnight across DST.
public func addMonths(_ monthStart: Millis, _ months: Int) -> Millis {
    LocalTime.calendar.date(byAdding: .month, value: months, to: Date(millis: monthStart))!.millis
}

/// The month as weeks of seven cells: nil before the first and after the last day.
/// `weekStartsOn` is 0 for Sunday, 1 for Monday, as the settings store it.
public func monthGrid(_ monthStart: Millis, weekStartsOn: Int) -> [[Millis?]] {
    let cal = LocalTime.calendar
    let first = Date(millis: monthStart)
    let days = cal.range(of: .day, in: .month, for: first)!.count
    let weekday = cal.component(.weekday, from: first) - 1
    let lead = ((weekday - weekStartsOn) % 7 + 7) % 7
    var cells: [Millis?] = Array(repeating: nil, count: lead)
    for d in 0..<days { cells.append(cal.date(byAdding: .day, value: d, to: first)!.millis) }
    while cells.count % 7 != 0 { cells.append(nil) }
    return stride(from: 0, to: cells.count, by: 7).map { Array(cells[$0..<($0 + 7)]) }
}

/// Weekday indexes (0 Sunday) in the order the grid's columns show them.
public func weekdayOrder(weekStartsOn: Int) -> [Int] { (0..<7).map { (($0 + weekStartsOn) % 7 + 7) % 7 } }
