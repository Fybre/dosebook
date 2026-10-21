import Foundation
import BenchCore
import BenchStore

/// Rotating backups in Documents/Bench, which the Files app shows under On My iPhone.
/// A second copy on the device, never uploaded by this app.
@MainActor
enum BackupFolder {
    struct Outcome { var ok: Bool; var name: String?; var pruned: Int }

    static var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?.appendingPathComponent(BACKUP_DIR, isDirectory: true)
    }

    static func list() -> [BackupFile] {
        guard let dir = url, let names = try? FileManager.default.contentsOfDirectory(atPath: dir.path) else { return [] }
        return listBackups(names.map { name in
            let size = (try? FileManager.default.attributesOfItem(atPath: dir.appendingPathComponent(name).path))?[.size] as? Int
            return (name, size)
        })
    }

    static func read(_ name: String) -> Data? { url.flatMap { try? Data(contentsOf: $0.appendingPathComponent(name)) } }

    /// Write a copy now, then prune to `keep`.
    static func run(_ store: AppStore, now: Millis = nowMillis()) -> Outcome {
        guard let dir = url, let data = try? store.exportBackup() else { return Outcome(ok: false, name: nil, pruned: 0) }
        let name = backupFileName(now)
        do {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try data.write(to: dir.appendingPathComponent(name), options: [.atomic, .completeFileProtection])
        } catch {
            return Outcome(ok: false, name: nil, pruned: 0)
        }
        let doomed = prunePlan(list().map { ($0.name, $0.size) }, keep: store.data.settings.backupKeep)
        var pruned = 0
        for n in doomed where (try? FileManager.default.removeItem(at: dir.appendingPathComponent(n))) != nil { pruned += 1 }
        store.markBackedUp()
        return Outcome(ok: true, name: name, pruned: pruned)
    }

    /// At launch and on return to the app, when one is due.
    static func runIfDue(_ store: AppStore) {
        let s = store.data.settings
        guard s.backupEnabled, !store.location.isMemory,
              backupDue(s.lastBackupAt, nowMillis(), intervalHours: s.backupIntervalHours) else { return }
        _ = run(store)
    }
}
