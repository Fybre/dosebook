import Foundation
import Observation
import BenchCore

/// The app's single source of truth, mirroring the original's Zustand store.
///
/// Every change goes through `mutate`, which is the one point every write passes
/// through, so the rules on a write hold whichever screen made it:
/// - `settings.dataChangedAt` is stamped when something a person would notice changed;
/// - a write that empties a collection, or takes most of it, sets the previous
///   document aside as a rescue copy (never refusing the write);
/// - only the rows that changed are written to storage.
///
/// Reloads (an iCloud change arriving from another device) go through the same
/// rescue check, since a sync is exactly how a collection could vanish unasked.
@MainActor
@Observable
public final class AppStore {
    public private(set) var data: AppData
    /// The set-aside copy, if a write has destroyed records since it was cleared.
    public private(set) var rescue: Rescue?
    public private(set) var lastError: String?
    public var location: StoreLocation { records.location }

    @ObservationIgnored private let records: RecordStore
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let rescueURL: URL?
    @ObservationIgnored private let clock: () -> Millis

    static let activeProfileKey = "bench.activeProfileId"

    public init(records: RecordStore, defaults: UserDefaults = .standard, rescueURL: URL? = AppStore.defaultRescueURL,
                clock: @escaping () -> Millis = nowMillis) {
        self.records = records
        self.defaults = defaults
        self.rescueURL = rescueURL
        self.clock = clock
        self.data = AppData()
        self.rescue = Self.readRescue(rescueURL)
        load()
    }

    public static var defaultRescueURL: URL? {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first?
            .appendingPathComponent("rescue.json")
    }

    // MARK: Reading

    /// Read everything from storage. On first launch, write the fresh document down.
    public func load() {
        do {
            let envelopes = try records.loadEnvelopes()
            var doc = document(from: envelopes, activeProfileId: defaults.string(forKey: Self.activeProfileKey))
            if envelopes.isEmpty {
                try records.apply(envelopeDiff(from: nil, to: doc))
            } else {
                try settleDrawn(&doc)
            }
            data = doc
        } catch {
            lastError = "\(error)"
        }
    }

    /// Re-read after a change arrived from another device.
    public func reload() {
        do {
            var read = document(from: try records.loadEnvelopes(), activeProfileId: data.activeProfileId)
            try settleDrawn(&read)
            let next = preservingOrder(read, from: data)
            guard next != data else { return }
            keepRescue(previous: data, next: next)
            data = next
        } catch {
            lastError = "\(error)"
        }
    }

    /// What came from storage may be a merge of two devices' changes, in which a vial's stored
    /// total is only one writer's. Recompute it from the doses, and write the correction down so
    /// every device ends on the same figure.
    private func settleDrawn(_ doc: inout AppData) throws {
        let stored = doc
        guard doc.reconcileDrawn() else { return }
        try records.apply(envelopeDiff(from: stored, to: doc, at: Date(millis: clock())))
    }

    // MARK: Writing

    /// Apply a change to the document and persist the rows it touched.
    public func mutate(_ change: (inout AppData) -> Void) {
        var next = data
        change(&next)
        commit(next)
    }

    /// The same, for an action that returns something (an id).
    @discardableResult
    public func mutate<T>(_ change: (inout AppData) -> T) -> T {
        var next = data
        let result = change(&next)
        commit(next)
        return result
    }

    private func commit(_ proposed: AppData) {
        var next = proposed
        next.settleDrawnStarts()
        if documentChanged(next, data) { next.settings.dataChangedAt = clock() }
        guard next != data else { return }
        keepRescue(previous: data, next: next)
        do {
            try records.apply(envelopeDiff(from: data, to: next, at: Date(millis: clock())))
        } catch {
            lastError = "\(error)"
        }
        if next.activeProfileId != data.activeProfileId { defaults.set(next.activeProfileId, forKey: Self.activeProfileKey) }
        data = next
    }

    // MARK: Rescue

    private func keepRescue(previous: AppData, next: AppData) {
        let lost = alarmingLosses(countRecords(previous), countRecords(next))
        guard !lost.isEmpty else { return }
        let r = Rescue(at: clock(), losses: lost, document: previous)
        rescue = r
        Self.writeRescue(r, rescueURL)
    }

    /// Union the lost rows back in.
    public func putRecordsBack() {
        guard let r = rescue else { return }
        mutate { $0.putRecordsBack(r) }
        clearRescue()
    }

    /// Forget the copy, for when the loss was meant.
    public func clearRescue() {
        rescue = nil
        if let url = rescueURL { try? FileManager.default.removeItem(at: url) }
    }

    struct StoredRescue: Codable {
        var at: Millis
        var losses: [Loss]
        var document: AppData
    }

    static func readRescue(_ url: URL?) -> Rescue? {
        guard let url, let raw = try? Data(contentsOf: url),
              let s = try? JSONDecoder().decode(StoredRescue.self, from: raw) else { return nil }
        return Rescue(at: s.at, losses: s.losses, document: migrateAppData(s.document))
    }

    /// Encrypted at rest on iPhone. macOS refuses file protection on an atomic
    /// write, and protects the disk as a whole anyway.
    static var rescueWriteOptions: Data.WritingOptions {
        #if os(iOS)
        [.atomic, .completeFileProtection]
        #else
        [.atomic]
        #endif
    }

    static func writeRescue(_ r: Rescue, _ url: URL?) {
        guard let url else { return }
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        if let raw = try? JSONEncoder().encode(StoredRescue(at: r.at, losses: r.losses, document: r.document)) {
            try? raw.write(to: url, options: rescueWriteOptions)
        }
    }

    // MARK: Files

    /// A backup in the original's export format, readable by the web and Android apps.
    public func exportBackup() throws -> Data {
        try data.exportDocument.exportJSON()
    }

    /// Restore a Bench backup, through the same migration as stored data.
    public func importBackup(_ raw: Data) throws {
        let value = try JSONDecoder().decode(JSONValue.self, from: raw)
        guard looksLikeAppData(value) else { throw ImportError.notABenchFile }
        let incoming = migrateAppData(value)
        mutate { $0.importData(incoming) }
    }

    /// Stamp a saved backup, so the backup button and nag know it happened.
    public func markBackedUp() { mutate { $0.settings.lastBackupAt = clock() } }

    public enum ImportError: Error { case notABenchFile }
}
