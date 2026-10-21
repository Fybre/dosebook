import Foundation
import Testing
import BenchCore
@testable import BenchStore

@MainActor
private func makeStore() throws -> (AppStore, RecordStore, URL) {
    let records = try RecordStore(location: .memory)
    let defaults = UserDefaults(suiteName: "bench-test-\(UUID().uuidString)")!
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("rescue-\(UUID().uuidString).json")
    return (AppStore(records: records, defaults: defaults, rescueURL: url, clock: { 1_000_000 }), records, url)
}

@MainActor @Suite struct AppStoreTests {
    @Test func freshInstallWritesDefaults() throws {
        let (store, records, _) = try makeStore()
        #expect(store.data.profiles == [DEFAULT_PROFILE])
        #expect(try records.loadEnvelopes().contains { $0.kind == "profile" })
    }

    @Test func mutatePersistsAndStamps() throws {
        let (store, records, _) = try makeStore()
        store.mutate { $0.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .sealed)) }
        #expect(store.data.settings.dataChangedAt == 1_000_000)
        let back = document(from: try records.loadEnvelopes(), activeProfileId: "me")
        #expect(back.vials.count == 1)
    }

    @Test func bookkeepingDoesNotStamp() throws {
        let (store, _, _) = try makeStore()
        store.markBackedUp()
        #expect(store.data.settings.lastBackupAt == 1_000_000 && store.data.settings.dataChangedAt == nil)
    }

    @Test func emptyingACollectionKeepsARescue() throws {
        let (store, _, url) = try makeStore()
        store.mutate { d in for _ in 0..<3 { d.addDiluent(DiluentBottle(id: "", profileId: "", kind: .bacteriostatic, volumeMl: 30, state: .sealed)) } }
        #expect(store.rescue == nil)
        store.mutate { $0.diluents = [] }
        #expect(store.rescue?.losses == [Loss(key: .diluents, from: 3, to: 0)])
        #expect(FileManager.default.fileExists(atPath: url.path))
        #expect(AppStore.readRescue(url)?.document.diluents.count == 3)
        store.putRecordsBack()
        #expect(store.data.diluents.count == 3 && store.rescue == nil)
    }

    @Test func importAndExport() throws {
        let (store, _, _) = try makeStore()
        let json = #"{"version":1,"protocols":[],"logs":[{"id":"l1","peptideId":"kpv","at":1,"doseMcg":100,"route":"subcutaneous"}],"vials":[]}"#
        try store.importBackup(Data(json.utf8))
        #expect(store.data.logs.count == 1 && store.data.logs[0].profileId == "me")
        let out = try JSONDecoder().decode(JSONValue.self, from: store.exportBackup())
        #expect(out["logs"]?.arrayValue?.count == 1 && out["version"] == .number(Double(DATA_VERSION)))
        #expect(throws: AppStore.ImportError.self) { try store.importBackup(Data(#"{"hello":1}"#.utf8)) }
    }

    @Test func activeProfileIsRemembered() throws {
        let records = try RecordStore(location: .memory)
        let defaults = UserDefaults(suiteName: "bench-test-\(UUID().uuidString)")!
        let store = AppStore(records: records, defaults: defaults, rescueURL: nil)
        let id = store.mutate { $0.addProfile(name: "B") }
        let again = AppStore(records: records, defaults: defaults, rescueURL: nil)
        #expect(again.data.activeProfileId == id)
    }

    @Test func reloadSeesOtherDevicesWrites() throws {
        let (store, records, _) = try makeStore()
        var other = store.data
        other.addLog(DoseLog(id: "", profileId: "", peptideId: "kpv", at: 5, doseMcg: 100, route: .subcutaneous))
        try records.apply(envelopeDiff(from: store.data, to: other))
        store.reload()
        #expect(store.data.logs.count == 1)
    }
}
