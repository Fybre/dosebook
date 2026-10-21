import Foundation
import SwiftData
import BenchCore

/// One stored row. CloudKit-friendly: every attribute defaulted, no unique
/// constraints, no relationships.
@Model
public final class Record {
    public var kind: String = ""
    public var recordId: String = ""
    public var profileId: String?
    public var payload: Data = Data()
    public var updatedAt: Date = Date.distantPast

    public init(kind: String, recordId: String, profileId: String?, payload: Data, updatedAt: Date) {
        self.kind = kind; self.recordId = recordId; self.profileId = profileId; self.payload = payload; self.updatedAt = updatedAt
    }

    var envelope: Envelope { Envelope(kind: kind, recordId: recordId, profileId: profileId, payload: payload, updatedAt: updatedAt) }
}

/// Where the rows live.
public enum StoreLocation: Sendable {
    /// Synced through the user's private CloudKit database.
    case cloud(containerId: String)
    /// This device only: no iCloud account, no entitlement, or an unsigned build.
    case local
    /// Tests and previews.
    case memory
}

/// Reads and writes envelopes through SwiftData.
@MainActor
public final class RecordStore {
    public let container: ModelContainer
    public let location: StoreLocation
    private var context: ModelContext { container.mainContext }
    private var index: [EnvelopeKey: Record] = [:]

    public init(location: StoreLocation) throws {
        self.location = location
        let schema = Schema([Record.self])
        let config: ModelConfiguration
        switch location {
        case .cloud(let id): config = ModelConfiguration("Bench", schema: schema, cloudKitDatabase: .private(id))
        case .local: config = ModelConfiguration("Bench", schema: schema, cloudKitDatabase: .none)
        case .memory: config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        }
        container = try ModelContainer(for: schema, configurations: [config])
    }

    /// Everything stored, deduplicated (extra copies are deleted).
    public func loadEnvelopes() throws -> [Envelope] {
        let all = try context.fetch(FetchDescriptor<Record>())
        var best: [EnvelopeKey: Record] = [:]
        var removed = false
        for r in all {
            let key = EnvelopeKey(kind: r.kind, recordId: r.recordId)
            if let seen = best[key] {
                if r.updatedAt > seen.updatedAt { context.delete(seen); best[key] = r } else { context.delete(r) }
                removed = true
            } else {
                best[key] = r
            }
        }
        if removed { try context.save() }
        index = best
        return best.values.map(\.envelope)
    }

    public func apply(_ diff: EnvelopeDiff) throws {
        guard !diff.isEmpty else { return }
        for key in diff.deletes {
            if let r = index.removeValue(forKey: key) { context.delete(r) }
        }
        for e in diff.upserts {
            if let r = index[e.key] {
                r.payload = e.payload; r.profileId = e.profileId; r.updatedAt = e.updatedAt
            } else {
                let r = Record(kind: e.kind, recordId: e.recordId, profileId: e.profileId, payload: e.payload, updatedAt: e.updatedAt)
                context.insert(r)
                index[e.key] = r
            }
        }
        try context.save()
    }
}
