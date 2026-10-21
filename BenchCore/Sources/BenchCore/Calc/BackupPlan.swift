import Foundation

// Port of src/lib/backup/plan.ts, plus `exportFileName` from download.ts.
// Rotating backups: names that sort by time, and a prune that never touches a
// file it does not recognise and never empties the folder.

public let BACKUP_DIR = "Bench"

private func pad(_ n: Int) -> String { n < 10 ? "0\(n)" : String(n) }

/// `bench-backup-YYYY-MM-DD-HHMMSS.json`, local time.
public func backupFileName(_ atMs: Millis) -> String {
    let c = LocalTime.calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: Date(millis: atMs))
    return "bench-backup-\(c.year!)-\(pad(c.month!))-\(pad(c.day!))-\(pad(c.hour!))\(pad(c.minute!))\(pad(c.second!)).json"
}

/// The moment a backup name stands for, or nil for anything that is not exactly one of ours.
public func parseBackupName(_ name: String) -> Millis? {
    guard let m = JSRegex(#"^bench-backup-(\d{4})-(\d{2})-(\d{2})-(\d{2})(\d{2})(\d{2})\.json$"#).exec(name) else { return nil }
    var c = DateComponents()
    c.year = Int(m[1]!); c.month = Int(m[2]!); c.day = Int(m[3]!); c.hour = Int(m[4]!); c.minute = Int(m[5]!); c.second = Int(m[6]!)
    guard let date = LocalTime.calendar.date(from: c) else { return nil }
    let ms = date.millis
    return backupFileName(ms) == name ? ms : nil
}

public struct BackupFile: Equatable, Sendable {
    public var name: String
    public var at: Millis
    public var size: Int?
}

/// Only our files, newest first.
public func listBackups(_ names: [(name: String, size: Int?)]) -> [BackupFile] {
    names.compactMap { f in parseBackupName(f.name).map { BackupFile(name: f.name, at: $0, size: f.size) } }
        .stableSorted { $0.at > $1.at }
}

/// The names to delete so `keep` remain; at least one always stays.
public func prunePlan(_ names: [(name: String, size: Int?)], keep: Double) -> [String] {
    let backups = listBackups(names)
    let limit = max(1, keep.isFinite ? Int(keep.rounded(.down)) : 1)
    return backups.count <= limit ? [] : backups.dropFirst(limit).map(\.name)
}

public func backupDue(_ lastAtMs: Millis?, _ nowMs: Millis, intervalHours: Double) -> Bool {
    guard intervalHours > 0 else { return false }
    guard let last = lastAtMs else { return true }
    if last > nowMs { return true }
    return nowMs - last >= intervalHours * HOUR_MS
}

/// The name a manual export is saved under: the UTC date, as the web app writes it.
public func exportFileName(_ atMs: Millis = nowMillis()) -> String {
    "bench-export-\(isoString(atMs).prefix(10)).json"
}
