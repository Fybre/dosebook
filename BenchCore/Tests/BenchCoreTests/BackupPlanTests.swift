import Foundation
import Testing
@testable import BenchCore

private func named(_ names: String...) -> [(name: String, size: Int?)] { names.map { ($0, nil) } }

@Suite struct BackupPlanTests {
    @Test func namesRoundTrip() {
        let at = local(2026, 7, 30, 2, 45, 12)
        let name = backupFileName(at)
        #expect(name == "bench-backup-2026-07-30-024512.json")
        #expect(parseBackupName(name) == at)
        let early = backupFileName(local(2026, 1, 5, 9, 8, 7)), later = backupFileName(local(2026, 11, 25, 21, 8, 7))
        #expect(early == "bench-backup-2026-01-05-090807.json")
        #expect([later, early].sorted() == [early, later])
    }

    @Test func refusesOthers() {
        for name in ["notes.txt", "bench-backup.json", "bench-backup-2026-07-30.json", "bench-backup-2026-07-30-0245.json",
                     "bench-export-2026-07-30-024512.json", "bench-backup-2026-07-30-024512.json.bak", "",
                     "bench-backup-2026-02-31-000000.json", "bench-backup-2026-13-01-000000.json"] {
            #expect(parseBackupName(name) == nil, "\(name)")
        }
    }

    @Test func lists() {
        let files = listBackups(named("bench-backup-2026-07-28-100000.json", "shopping-list.json", "bench-backup-2026-07-30-100000.json", "bench-backup-2026-07-29-100000.json"))
        #expect(files.map(\.name) == ["bench-backup-2026-07-30-100000.json", "bench-backup-2026-07-29-100000.json", "bench-backup-2026-07-28-100000.json"])
        #expect(listBackups([]).isEmpty)
        #expect(listBackups([("bench-backup-2026-07-30-100000.json", 4096)])[0].size == 4096)
    }

    @Test func prunes() {
        let three = named("bench-backup-2026-07-28-100000.json", "bench-backup-2026-07-29-100000.json", "bench-backup-2026-07-30-100000.json")
        #expect(prunePlan(three, keep: 5).isEmpty)
        #expect(prunePlan(three, keep: 3).isEmpty)
        #expect(prunePlan(three, keep: 2) == ["bench-backup-2026-07-28-100000.json"])
        #expect(prunePlan(three, keep: 1) == ["bench-backup-2026-07-29-100000.json", "bench-backup-2026-07-28-100000.json"])
        let doomed = prunePlan(three + named("my-notes.json", "bench-export-2026-01-01.json", "photo.jpg"), keep: 1)
        #expect(!doomed.contains("my-notes.json") && !doomed.contains("bench-export-2026-01-01.json") && !doomed.contains("photo.jpg"))
        #expect(doomed.count == 2)
        for keep in [0, -1, -100, 0.4] { #expect(prunePlan(three, keep: keep).count == 2, "keep=\(keep)") }
        #expect(prunePlan(three, keep: 2.9).count == 1)
        let gone = Set(prunePlan(three, keep: 2))
        #expect(prunePlan(three.filter { !gone.contains($0.name) }, keep: 2).isEmpty)
    }

    @Test func due() {
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 30; c.hour = 8
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let NOW = utc.date(from: c)!.millis
        #expect(backupDue(nil, NOW, intervalHours: 24))
        #expect(!backupDue(NOW - 23 * HOUR, NOW, intervalHours: 24))
        #expect(backupDue(NOW - 24 * HOUR, NOW, intervalHours: 24))
        #expect(backupDue(NOW - 100 * HOUR, NOW, intervalHours: 24))
        #expect(backupDue(NOW + 500 * HOUR, NOW, intervalHours: 24))
        #expect(!backupDue(nil, NOW, intervalHours: 0))
        #expect(!backupDue(NOW - 1000 * HOUR, NOW, intervalHours: -5))
    }

    @Test func exportName() {
        var c = DateComponents(); c.year = 2026; c.month = 7; c.day = 30; c.hour = 8
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        #expect(exportFileName(utc.date(from: c)!.millis) == "bench-export-2026-07-30.json")
    }
}
