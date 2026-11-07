import Foundation

// Port of src/lib/calc/backupnag.ts. When to remind someone to export, without
// becoming noise. On iOS this applies when the data is not in iCloud.

public let MIN_RECORDS = 5
public let MIN_HISTORY_DAYS: Double = 7
public let BACKUP_FRESH_DAYS: Double = 45
public let SNOOZE_DAYS: Double = 21

public enum NagReason: String, Sendable { case never, stale }

public struct NagVerdict: Equatable, Sendable {
    public var show: Bool
    public var reason: NagReason?
    public var daysSinceBackup: Int?
}

private let QUIET = NagVerdict(show: false, reason: nil, daysSinceBackup: nil)

/// A future date proves nothing was done, so it is ignored.
private func elapsedIfTrustworthy(_ since: Millis?, _ now: Millis) -> Double? {
    guard let since else { return nil }
    let gap = now - since
    return gap < 0 ? nil : gap
}

/// For measuring how long a history is: a future date means no history yet.
private func elapsedClamped(_ since: Millis?, _ now: Millis) -> Double? {
    guard let since else { return nil }
    return max(0, now - since)
}

public func backupNag(manualBackupOnly: Bool, recordCount: Int, oldestRecordAt: Millis?, lastBackupAt: Millis?,
                      dismissedAt: Millis?, nowMs: Millis) -> NagVerdict {
    guard manualBackupOnly, recordCount >= MIN_RECORDS else { return QUIET }
    guard let history = elapsedClamped(oldestRecordAt, nowMs), history >= MIN_HISTORY_DAYS * DAY_MS else { return QUIET }
    if let s = elapsedIfTrustworthy(dismissedAt, nowMs), s < SNOOZE_DAYS * DAY_MS { return QUIET }
    guard let since = elapsedIfTrustworthy(lastBackupAt, nowMs) else {
        return NagVerdict(show: true, reason: .never, daysSinceBackup: nil)
    }
    let days = Int((since / DAY_MS).rounded(.down))
    if since >= BACKUP_FRESH_DAYS * DAY_MS { return NagVerdict(show: true, reason: .stale, daysSinceBackup: days) }
    return NagVerdict(show: false, reason: nil, daysSinceBackup: days)
}
