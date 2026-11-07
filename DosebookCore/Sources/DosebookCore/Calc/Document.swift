import Foundation

// Port of src/lib/calc/document.ts. Whether the document changed, and whether
// it has changed since it was last written to a file.

/// Settings the app writes about itself; never a person making a change.
let BOOKKEEPING_SETTINGS: Set<String> = ["sync", "dataChangedAt", "lastBackupAt", "backupNagDismissedAt"]

public func meaningfulSettingsChange(_ a: Settings, _ b: Settings) -> Bool {
    if a == b { return false }
    func strip(_ s: Settings) -> Settings {
        var c = s
        c.dataChangedAt = nil; c.lastBackupAt = nil; c.backupNagDismissedAt = nil
        c.extra.removeValue(forKey: "sync")
        return c
    }
    return strip(a) != strip(b)
}

/// Whether anything that ends up in the file changed.
public func documentChanged(_ next: AppData, _ prev: AppData) -> Bool {
    if next.profiles != prev.profiles || next.activeProfileId != prev.activeProfileId || next.protocols != prev.protocols
        || next.logs != prev.logs || next.vials != prev.vials || next.measurements != prev.measurements
        || next.labs != prev.labs || next.checkIns != prev.checkIns || next.customPeptides != prev.customPeptides
        || next.halfLifeOverrides != prev.halfLifeOverrides || next.orders != prev.orders
        || next.diluents != prev.diluents || next.compoundNotes != prev.compoundNotes { return true }
    return meaningfulSettingsChange(next.settings, prev.settings)
}

/// Work that no file holds yet. A fresh install that changed nothing is quiet.
public func backupDirty(_ dataChangedAt: Millis?, _ lastBackupAt: Millis?) -> Bool {
    guard let changed = dataChangedAt else { return false }
    guard let backed = lastBackupAt else { return true }
    return changed > backed
}
