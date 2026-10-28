import Foundation
import Testing
@testable import BenchCore

// Ports of reminders.test.ts and ics.test.ts.

private let peptides = [Peptide(id: "bpc-157", name: "BPC-157", category: .repair)]

struct ReminderFixture {
    let NOW = local(2026, 1, 5, 6)
    func proto(id: String = "p1", peptideId: String = "bpc-157", name: String = "", active: Bool = true, startedAt: Millis? = nil,
               endedAt: Millis? = nil, doseMcg: Double = 250, schedule: Schedule = Schedule(kind: .daily, timesOfDay: ["07:00"]),
               phases: [ProtocolPhase]? = nil) -> DoseProtocol {
        makeProtocol(id: id, peptideId: peptideId, name: name, active: active, startedAt: startedAt ?? local(2026, 1, 1, 7),
                     endedAt: endedAt, doseMcg: doseMcg, schedule: schedule, phases: phases)
    }
    func log(_ at: Millis, peptideId: String = "bpc-157", protocolId: String = "p1", skipped: Bool? = nil) -> DoseLog {
        DoseLog(id: UUID().uuidString, profileId: "me", protocolId: protocolId, peptideId: peptideId, at: at, doseMcg: 250, route: .subcutaneous, skipped: skipped)
    }
    func on(leadMinutes: Double = 0, showCompound: Bool = false, calendarDays: Double = 90) -> RemindersSettings {
        RemindersSettings(enabled: true, leadMinutes: leadMinutes, showCompound: showCompound, calendarDays: calendarDays)
    }
}

@Suite struct RemindersTests {
    let f = ReminderFixture()
    func run(_ protocols: [DoseProtocol]? = nil, logs: [DoseLog] = [], settings: RemindersSettings? = nil, nowMs: Millis? = nil, horizon: Double = REMINDER_HORIZON_DAYS) -> [Reminder] {
        remindersFor(protocols: protocols ?? [f.proto()], logs: logs, peptides: peptides, settings: settings ?? f.on(), nowMs: nowMs ?? f.NOW, horizonDays: horizon)
    }

    @Test func off() {
        #expect(run(settings: DEFAULT_REMINDERS).isEmpty)
        #expect(!DEFAULT_REMINDERS.enabled && !DEFAULT_REMINDERS.showCompound)
    }

    @Test func armed() {
        let out = run()
        #expect(out.count >= 14 && out.count <= 15 && out[0].doseAt == local(2026, 1, 5, 7))
        let later = run(nowMs: local(2026, 1, 5, 7, 30))
        #expect(later.allSatisfy { $0.at > local(2026, 1, 5, 7, 30) } && later[0].doseAt == local(2026, 1, 6, 7))
        #expect(run([f.proto(active: false)]).isEmpty)
        #expect(run([f.proto(schedule: Schedule(kind: .asNeeded))]).isEmpty)
        #expect(run([f.proto(endedAt: f.NOW - DAY_MS)]).isEmpty)
        let twice = run([f.proto(schedule: Schedule(kind: .daily, timesOfDay: ["07:00", "19:00"]))])
        #expect(twice.count >= 28 && twice[0].doseAt == local(2026, 1, 5, 7) && twice[1].doseAt == local(2026, 1, 5, 19))
        let alt = run([f.proto(schedule: Schedule(kind: .intervalDays, intervalDays: 2, timesOfDay: ["07:00"]))])
        for i in 1..<alt.count { #expect(alt[i].doseAt - alt[i - 1].doseAt == 2 * DAY_MS) }
    }

    @Test func taken() {
        let first = local(2026, 1, 5, 7)
        #expect(!run(logs: [f.log(first)]).contains { $0.doseAt == first })
        #expect(!run(logs: [f.log(first - 30 * 60_000)]).contains { $0.doseAt == first })
        #expect(!run(logs: [f.log(first - 30 * 60_000, skipped: true)]).contains { $0.doseAt == first })
        #expect(run(logs: [f.log(first, peptideId: "tb-500", protocolId: "p2")]).contains { $0.doseAt == first })
    }

    @Test func lead() {
        let out = run(settings: f.on(leadMinutes: 15))
        #expect(out[0].doseAt == local(2026, 1, 5, 7) && out[0].at == out[0].doseAt - 15 * 60_000)
        #expect(run(settings: f.on(leadMinutes: 10), nowMs: local(2026, 1, 5, 6, 45))[0].at == local(2026, 1, 5, 6, 50))
        let neg = run(settings: f.on(leadMinutes: -30))
        #expect(neg[0].at == neg[0].doseAt)
    }

    @Test func wording() {
        let first = run()[0]
        #expect(first.title == "Dosebook" && first.body == "A dose is due." && !"\(first.title) \(first.body)".contains("BPC"))
        let named = run(settings: f.on(showCompound: true))[0]
        #expect(named.title == "BPC-157" && named.body == "250 mcg due.")
        #expect(run([f.proto(name: "Morning healing")], settings: f.on(showCompound: true))[0].title == "Morning healing")
        #expect(run([f.proto(doseMcg: 500, schedule: Schedule(kind: .daily, timesOfDay: ["07:00", "19:00"]))], settings: f.on(showCompound: true))[0].body == "250 mcg due.")
        let phased = run([f.proto(phases: [ProtocolPhase(step: 1, doseMcg: 250, weeks: 1), ProtocolPhase(step: 2, doseMcg: 500, weeks: 4)])], settings: f.on(showCompound: true))
        func bodyOn(_ d: Int) -> String? { phased.first { $0.doseAt == local(2026, 1, d, 7) }?.body }
        #expect(bodyOn(5) == "250 mcg due." && bodyOn(7) == "250 mcg due." && bodyOn(8) == "500 mcg due.")
    }

    @Test func identity() {
        #expect(run()[0].id == run()[0].id && run()[0].key == "p1:\(jsNumberString(local(2026, 1, 5, 7)))")
        let out = run()
        #expect(Set(out.map(\.id)).count == out.count)
        #expect(out.allSatisfy { $0.id >= 0 && $0.id < 2_147_483_647 } && reminderId("") >= 0)
        let order = run([f.proto(id: "evening", schedule: Schedule(kind: .daily, timesOfDay: ["19:00"])),
                         f.proto(id: "morning", peptideId: "tb-500", schedule: Schedule(kind: .daily, timesOfDay: ["07:00"]))])
        for i in 1..<order.count { #expect(order[i].at >= order[i - 1].at) }
        #expect(order[0].protocolId == "morning")
    }

    @Test func dst() {
        let out = run([f.proto(startedAt: local(2026, 2, 1, 7))], nowMs: local(2026, 3, 1, 6), horizon: 30)
        for r in out { #expect(hours(r.doseAt) == 7 && minutes(r.doseAt) == 0) }
        #expect(Set(out.map(\.at)).count == out.count)
        for i in 1..<out.count {
            let gap = out[i].doseAt - out[i - 1].doseAt
            #expect(gap >= 23 * HOUR && gap <= 25 * HOUR)
        }
    }

    /// The original's FNV hash, computed by hand, so a notification id matches across platforms.
    @Test func hashMatchesOriginal() {
        #expect(reminderId("") == Int((UInt32(0x811c9dc5) >> 1) % 2_000_000_000))
    }
}

@Suite struct ICSTests {
    let f = ReminderFixture()
    func build(_ protocols: [DoseProtocol]? = nil, settings: RemindersSettings? = nil, nowMs: Millis? = nil, days: Double? = 7) -> String {
        buildCalendar(protocols: protocols ?? [f.proto()], peptides: peptides,
                      settings: settings ?? RemindersSettings(), nowMs: nowMs ?? f.NOW, days: days)
    }
    func lines(_ s: String) -> [String] { s.components(separatedBy: "\r\n") }

    @Test func shape() {
        let l = lines(build())
        #expect(l[0] == "BEGIN:VCALENDAR" && l.contains("VERSION:2.0") && l.filter { !$0.isEmpty }.last == "END:VCALENDAR")
        let ics = build()
        #expect(ics.hasSuffix("\r\n") && !ics.contains("\n\n") && !ics.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
        #expect(ics.components(separatedBy: "BEGIN:VEVENT").count == ics.components(separatedBy: "END:VEVENT").count)
        #expect(ics.components(separatedBy: "BEGIN:VALARM").count == ics.components(separatedBy: "END:VALARM").count)
        for field in ["UID:", "DTSTAMP:", "DTSTART:", "SUMMARY:"] { #expect(ics.contains(field)) }
        #expect(calendarFileName(f.NOW).range(of: "^dosebook-doses-2026-01-0\\d\\.ics$", options: .regularExpression) != nil)
    }

    @Test func doses() {
        #expect(calendarEventCount(build()) == 7)
        #expect(calendarEventCount(build([f.proto(schedule: Schedule(kind: .daily, timesOfDay: ["07:00", "19:00"]))])) == 14)
        #expect(!build().contains("DTSTART:20260104") && build().contains("DTSTART:20260105T070000"))
        for d in [7.0, 14, 21, 30, 60, 90, 180] {
            let c = calendarEventCount(build(days: d))
            #expect(Double(c) >= d && Double(c) <= d + 1, "\(d) days")
        }
        let fromSettings = calendarEventCount(build(settings: RemindersSettings(calendarDays: 14), days: nil))
        #expect(fromSettings >= 14 && fromSettings <= 15)
        #expect(calendarEventCount(build([f.proto(active: false)])) == 0)
        #expect(calendarEventCount(build([f.proto(endedAt: f.NOW - DAY_MS)])) == 0)
        #expect(calendarEventCount(build([f.proto(schedule: Schedule(kind: .asNeeded))])) == 0)
        let cycled = build([f.proto(schedule: Schedule(kind: .daily, timesOfDay: ["07:00"], cycleWeeksOn: 3, cycleWeeksOff: 1))], days: 40)
        #expect(cycled.contains("DTSTART:20260120T070000") && !cycled.contains("DTSTART:20260123T070000"))
    }

    @Test func wording() {
        let ics = build()
        #expect(ics.contains("SUMMARY:Dosebook: dose due") && !ics.contains("BPC") && !ics.contains("mcg"))
        #expect(build(settings: RemindersSettings(showCompound: true)).contains("SUMMARY:BPC-157 250 mcg"))
        let phased = build([f.proto(phases: [ProtocolPhase(step: 1, doseMcg: 250, weeks: 1), ProtocolPhase(step: 2, doseMcg: 500, weeks: 8)])],
                           settings: RemindersSettings(showCompound: true), days: 14)
        #expect(phased.contains("SUMMARY:BPC-157 250 mcg") && phased.contains("SUMMARY:BPC-157 500 mcg"))
        #expect(build().contains("TRIGGER:PT0S") && build(settings: RemindersSettings(leadMinutes: 15)).contains("TRIGGER:-PT15M"))
        #expect(build().contains("TRANSP:TRANSPARENT"))
    }

    @Test func reimport() {
        let uid: (String) -> String? = { s in s.components(separatedBy: "\r\n").first { $0.hasPrefix("UID:") } }
        #expect(uid(build()) == uid(build(nowMs: f.NOW + HOUR)))
        let seq: (String) -> Int = { s in Int(s.components(separatedBy: "\r\n").first { $0.hasPrefix("SEQUENCE:") }!.dropFirst(9))! }
        #expect(seq(build(nowMs: f.NOW + HOUR)) > seq(build()) && seq(build()) < 2_147_483_647)
        let uids = lines(build([f.proto(), f.proto(id: "p2", peptideId: "tb-500")])).filter { $0.hasPrefix("UID:") }
        #expect(Set(uids).count == uids.count)
    }

    @Test func clocks() {
        let ics = build([f.proto(startedAt: local(2026, 2, 1, 7))], nowMs: local(2026, 3, 1, 6), days: 40)
        let starts = lines(ics).filter { $0.hasPrefix("DTSTART:") }
        #expect(starts.count > 30 && starts.allSatisfy { $0.hasSuffix("T070000") })
        for s in lines(build()).filter({ $0.hasPrefix("DTSTART") }) { #expect(!s.contains("Z") && !s.contains("TZID")) }
        #expect(lines(build()).first { $0.hasPrefix("DTSTAMP:") }!.hasSuffix("Z"))
    }

    @Test func escaping() {
        #expect(build([f.proto(name: #"Morning; healing, phase\one"#)], settings: RemindersSettings(showCompound: true)).contains(#"SUMMARY:Morning\; healing\, phase\\one"#))
        #expect(foldLine("SUMMARY:Bench") == "SUMMARY:Bench")
        let parts = foldLine("SUMMARY:" + String(repeating: "a", count: 200)).components(separatedBy: "\r\n")
        #expect(parts.count > 1 && parts[0].count <= 75 && parts.dropFirst().allSatisfy { $0.hasPrefix(" ") })
        let accent = foldLine("SUMMARY:" + String(repeating: "é", count: 80))
        #expect(accent.components(separatedBy: "\r\n").allSatisfy { $0.utf8.count <= 75 })
        #expect(accent.replacingOccurrences(of: "\r\n ", with: "") == "SUMMARY:" + String(repeating: "é", count: 80))
    }
}

@Suite struct ReminderDrawTests {
    @Test func theAmountToDrawJoinsTheNamedTextOnly() {
        var d = AppData()
        d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 250,
                                   schedule: Schedule(kind: .daily, timesOfDay: ["08:00"])))
        let draw: (DoseProtocol, Millis, Double) -> String? = { _, _, _ in "10 units" }
        let now = local(2026, 7, 6, 12)
        let named = remindersFor(protocols: d.protocols, logs: [], peptides: d.allPeptides,
                                 settings: RemindersSettings(enabled: true, showCompound: true), nowMs: now, drawText: draw)
        #expect(named.first?.body == "250 mcg due. 10 units.")
        // Discreet stays discreet, whatever there is to draw.
        let quiet = remindersFor(protocols: d.protocols, logs: [], peptides: d.allPeptides,
                                 settings: RemindersSettings(enabled: true, showCompound: false), nowMs: now, drawText: draw)
        #expect(quiet.first?.title == "Dosebook" && quiet.first?.body == "A dose is due.")
        // Nothing to draw from: the text is as it was.
        let none = remindersFor(protocols: d.protocols, logs: [], peptides: d.allPeptides,
                                settings: RemindersSettings(enabled: true, showCompound: true), nowMs: now, drawText: { _, _, _ in nil })
        #expect(none.first?.body == "250 mcg due.")
    }

    @Test func drawAmountFollowsTheVialOnTheShelf() {
        var d = AppData()
        let pid = d.addProtocol(makeProtocol(peptideId: "bpc-157", startedAt: local(2026, 7, 1), doseMcg: 250,
                                             schedule: Schedule(kind: .daily, timesOfDay: ["08:00"])))
        let at = local(2026, 7, 6, 8)
        #expect(drawAmountText(d, peptideId: "bpc-157", doseMcg: 250, route: .subcutaneous, nowMs: at) == nil)
        let v = d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .sealed))
        d.reconstituteVial(v, diluentMl: 2, diluent: .bacteriostatic, at: local(2026, 7, 5))
        // 5 mg in 2 mL is 2500 mcg/mL: 250 mcg is 0.1 mL, ten units on a U-100 barrel.
        #expect(drawAmountText(d, peptideId: "bpc-157", doseMcg: 250, route: .subcutaneous, nowMs: at) == "10 units")
        _ = pid
    }
}
