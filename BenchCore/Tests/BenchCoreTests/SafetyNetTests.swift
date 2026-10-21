import Foundation
import Testing
@testable import BenchCore

// Ports of rescue, backupnag and document tests.

private func lg(_ id: String) -> DoseLog { DoseLog(id: id, profileId: "me", peptideId: "x", at: 1, doseMcg: 1, route: .subcutaneous) }
private func vl(_ id: String) -> Vial { vial(id) }
private func bt(_ id: String, drawnMl: Double? = nil) -> DiluentBottle {
    DiluentBottle(id: id, profileId: "me", kind: .bacteriostatic, volumeMl: 30, drawnMl: drawnMl, state: .sealed)
}
private func doc(logs: [DoseLog] = [], vials: [Vial] = [], diluents: [DiluentBottle] = []) -> AppData {
    var d = AppData(); d.logs = logs; d.vials = vials; d.diluents = diluents; return d
}

@Suite struct RescueTests {
    @Test func counting() {
        let c = countRecords(doc(logs: [lg("a"), lg("b")]))
        #expect(c[.logs] == 2 && c[.diluents] == 0 && Set(c.keys) == Set(RecordKey.allCases))
        #expect(countRecords(nil)[.logs] == 0)
    }

    @Test func alarming() {
        #expect(isAlarming(Loss(key: .diluents, from: 3, to: 0)))
        #expect(!isAlarming(Loss(key: .vials, from: 16, to: 15)) && !isAlarming(Loss(key: .logs, from: 103, to: 102)))
        #expect(!isAlarming(Loss(key: .logs, from: 103, to: 98)) && isAlarming(Loss(key: .logs, from: 103, to: 40)))
        #expect(!isAlarming(Loss(key: .protocols, from: 2, to: 1)) && !isAlarming(Loss(key: .protocols, from: 3, to: 2)))
        #expect(losses(countRecords(doc()), countRecords(doc(logs: [lg("a")]))).isEmpty)
        #expect(losses(countRecords(doc()), countRecords(doc())).isEmpty)
        #expect(!isAlarming(Loss(key: .diluents, from: 0, to: 0)) && alarmingLosses(countRecords(doc()), countRecords(doc())).isEmpty)
    }

    @Test func incident() {
        let before = doc(logs: (0..<91).map { lg("l\($0)") }, vials: (0..<16).map { vl("v\($0)") },
                         diluents: [bt("rQ_E1DyD43"), bt("xtc0_viz9N"), bt("YxDoMT6Fnd")])
        let after = doc(logs: (0..<103).map { lg("l\($0)") }, vials: (0..<16).map { vl("v\($0)") })
        #expect(alarmingLosses(countRecords(before), countRecords(after)) == [Loss(key: .diluents, from: 3, to: 0)])
        #expect(lostCount(Loss(key: .diluents, from: 3, to: 0)) == 3 && lostCount(Loss(key: .logs, from: 103, to: 40)) == 63)
        let rescue = Rescue(at: 1, losses: [Loss(key: .diluents, from: 3, to: 0)], document: before)
        let fixed = restoreLost(after, rescue)
        #expect(fixed.diluents.count == 3 && fixed.logs.count == 103 && fixed.vials.count == 16)
        #expect(recoverable(after, rescue) == [Loss(key: .diluents, from: 0, to: 3)])
    }

    @Test func restoring() {
        let saved = doc(diluents: [bt("a"), bt("b")])
        let out = restoreLost(doc(diluents: [bt("a", drawnMl: 9)]), Rescue(at: 1, losses: [Loss(key: .diluents, from: 2, to: 1)], document: saved))
        #expect(out.diluents.count == 2 && out.diluents.first { $0.id == "a" }?.drawnMl == 9)
        let only = restoreLost(doc(logs: [lg("kept")]), Rescue(at: 1, losses: [Loss(key: .diluents, from: 2, to: 0)],
                                                             document: doc(logs: [lg("kept"), lg("gone-on-purpose")], diluents: [bt("a")])))
        #expect(only.diluents.count == 1 && only.logs.count == 1)
        let full = doc(diluents: [bt("a"), bt("b")])
        let r = Rescue(at: 1, losses: [Loss(key: .diluents, from: 2, to: 2)], document: saved)
        #expect(restoreLost(full, r).diluents.count == 2 && recoverable(full, r).isEmpty)
        #expect(restoreLost(doc(), Rescue(at: 1, losses: [Loss(key: .diluents, from: 1, to: 0)], document: doc(diluents: [bt("")]))).diluents.isEmpty)
    }
}

@Suite struct BackupNagTests {
    let NOW: Millis = 1_785_499_200_000
    func ago(_ d: Double) -> Millis { NOW - d * DAY_MS }
    func nag(manual: Bool = true, count: Int = 30, oldest: Millis?? = nil, last: Millis? = nil, dismissed: Millis? = nil) -> NagVerdict {
        backupNag(manualBackupOnly: manual, recordCount: count, oldestRecordAt: oldest ?? ago(60), lastBackupAt: last, dismissedAt: dismissed, nowMs: NOW)
    }

    @Test func quiet() {
        #expect(!nag(manual: false).show)
        #expect(!nag(count: MIN_RECORDS - 1).show && !nag(count: 0).show)
        #expect(!nag(oldest: ago(MIN_HISTORY_DAYS - 1)).show)
        #expect(!nag(count: 0, oldest: .some(nil)).show)
        #expect(!nag(last: ago(1)).show && !nag(last: ago(BACKUP_FRESH_DAYS - 1)).show)
        #expect(!nag(dismissed: ago(1)).show && !nag(dismissed: ago(SNOOZE_DAYS - 1)).show)
    }

    @Test func speaks() {
        let v = nag()
        #expect(v.show && v.reason == .never && v.daysSinceBackup == nil)
        let stale = nag(last: ago(90))
        #expect(stale.show && stale.reason == .stale && stale.daysSinceBackup == 90)
        #expect(nag(dismissed: ago(SNOOZE_DAYS + 1)).show)
        #expect(nag(count: MIN_RECORDS).show && nag(oldest: ago(MIN_HISTORY_DAYS)).show && nag(last: ago(BACKUP_FRESH_DAYS)).show)
    }

    @Test func movedClocks() {
        #expect(nag(dismissed: NOW + 400 * DAY_MS).show)
        let future = nag(last: NOW + 400 * DAY_MS)
        #expect(future.show && future.reason == .never)
        #expect(!nag(oldest: NOW + 10 * DAY_MS).show)
    }
}

@Suite struct DocumentTests {
    @Test func changed() {
        let a = AppData()
        #expect(!documentChanged(a, a))
        #expect(documentChanged(doc(logs: [lg("a")]), a))
        var p = a; p.activeProfileId = "other"; #expect(documentChanged(p, a))
        var s = a; s.settings.currency = "EUR"; #expect(documentChanged(s, a))
        var stamp = a; stamp.settings.dataChangedAt = 123; #expect(!documentChanged(stamp, a))
        var backed = a; backed.settings.lastBackupAt = 456; #expect(!documentChanged(backed, a))
        var version = a; version.version = 99; #expect(!documentChanged(version, a))
        var sync = a; sync.settings.extra["sync"] = .object(["url": .string("x")]); #expect(!documentChanged(sync, a))
    }

    @Test func dirty() {
        #expect(!backupDirty(nil, nil) && backupDirty(1000, nil) && backupDirty(2000, 1000))
        #expect(!backupDirty(1000, 2000) && !backupDirty(1000, 1000))
    }
}
