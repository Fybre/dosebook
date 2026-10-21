import Foundation
import Testing
@testable import BenchCore

private func log(_ at: Millis, _ peptide: String, protocolId: String? = nil, skipped: Bool = false) -> DoseLog {
    DoseLog(id: UUID().uuidString, profileId: "me", protocolId: protocolId, peptideId: peptide, at: at, doseMcg: 250, route: .subcutaneous, skipped: skipped ? true : nil)
}

@Suite struct LogCalendarTests {
    @Test func oneMarkPerCompoundPerDay() {
        let marks = marksByDay([log(local(2026, 7, 6, 20), "bpc-157"), log(local(2026, 7, 6, 8), "bpc-157"),
                                log(local(2026, 7, 6, 9), "tirzepatide", protocolId: "t"), log(local(2026, 7, 7, 8), "bpc-157")])
        let day = marks[local(2026, 7, 6)]!
        #expect(day.map(\.peptideId) == ["bpc-157", "tirzepatide"])
        #expect(day[0].count == 2 && day[1].protocolId == "t")
        #expect(marks[local(2026, 7, 7)]?.count == 1)
        #expect(marks.count == 2)
    }

    @Test func skips() {
        var marks = marksByDay([log(local(2026, 7, 6, 8), "bpc-157", skipped: true)])
        #expect(marks[local(2026, 7, 6)]![0].skippedOnly)
        marks = marksByDay([log(local(2026, 7, 6, 8), "bpc-157", protocolId: "a", skipped: true), log(local(2026, 7, 6, 20), "bpc-157", protocolId: "b")])
        #expect(!marks[local(2026, 7, 6)]![0].skippedOnly)
        #expect(marks[local(2026, 7, 6)]![0].protocolId == "b")
    }

    @Test func gridStartsOnTheChosenDay() {
        // 1 July 2026 is a Wednesday.
        let july = startOfLocalMonth(local(2026, 7, 19, 15))
        #expect(july == local(2026, 7, 1))
        let monday = monthGrid(july, weekStartsOn: 1)
        #expect(monday[0].prefix(2).allSatisfy { $0 == nil } && monday[0][2] == local(2026, 7, 1))
        let sunday = monthGrid(july, weekStartsOn: 0)
        #expect(sunday[0].prefix(3).allSatisfy { $0 == nil } && sunday[0][3] == local(2026, 7, 1))
        for grid in [monday, sunday] {
            #expect(grid.allSatisfy { $0.count == 7 })
            #expect(grid.flatMap { $0 }.compactMap { $0 }.count == 31)
            #expect(grid.flatMap { $0 }.compactMap { $0 }.last == local(2026, 7, 31))
        }
        #expect(weekdayOrder(weekStartsOn: 1) == [1, 2, 3, 4, 5, 6, 0])
    }

    @Test func monthsAcrossDaylightSaving() {
        // Every cell is local midnight, whichever side of a clock change it falls.
        for m in [3, 4, 10, 11] {
            let start = local(2026, m, 1)
            for d in monthGrid(start, weekStartsOn: 1).flatMap({ $0 }).compactMap({ $0 }) {
                #expect(hours(d) == 0 && minutes(d) == 0)
            }
            #expect(addMonths(start, 1) == local(2026, m + 1, 1))
        }
        #expect(addMonths(local(2026, 1, 1), -1) == local(2025, 12, 1))
        #expect(monthGrid(local(2028, 2, 1), weekStartsOn: 1).flatMap { $0 }.compactMap { $0 }.count == 29)
    }
}
