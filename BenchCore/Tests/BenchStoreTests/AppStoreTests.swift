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

    @Test func aBurstOfRemoteChangesIsReadOnce() async throws {
        let (store, records, _) = try makeStore()
        // Another device's vial arrives behind the store's back, announced many times over.
        let other = AppStore(records: records, defaults: UserDefaults(suiteName: "bench-test-\(UUID().uuidString)")!, rescueURL: nil, clock: { 2_000_000 })
        other.mutate { $0.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .sealed)) }
        #expect(store.data.vials.isEmpty)
        for _ in 0..<50 { store.reloadSoon(quiet: 0.05, longest: 1) }
        #expect(store.data.vials.isEmpty)
        // Read once the burst has stopped; wait for it rather than for a fixed time.
        for _ in 0..<100 where store.data.vials.isEmpty { try await Task.sleep(for: .milliseconds(50)) }
        #expect(store.data.vials.count == 1)
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

@MainActor @Suite struct ReloadOrderTests {
    @Test func reloadKeepsProtocolOrder() throws {
        let (store, records, _) = try makeStoreForOrder()
        for name in ["zeta", "alpha", "mid"] {
            store.mutate { $0.addProtocol(DoseProtocol(id: "", profileId: "", peptideId: "bpc-157", name: name, startedAt: 0, doseMcg: 1, route: .subcutaneous, schedule: Schedule(kind: .daily))) }
        }
        // Force distinct, out-of-order ids as another device's import would have.
        var d = store.data
        let ids = ["zz", "aa", "mm"]
        for i in d.protocols.indices { d.protocols[i].id = ids[i] }
        try records.apply(envelopeDiff(from: store.data, to: d))
        store.reload()
        let first = store.data.protocols.map(\.name)
        var other = store.data
        other.addLog(DoseLog(id: "", profileId: "", peptideId: "kpv", at: 5, doseMcg: 1, route: .subcutaneous))
        try records.apply(envelopeDiff(from: store.data, to: other))
        store.reload()
        #expect(store.data.protocols.map(\.name) == first)
    }

    private func makeStoreForOrder() throws -> (AppStore, RecordStore, Void) {
        let records = try RecordStore(location: .memory)
        return (AppStore(records: records, defaults: UserDefaults(suiteName: "o-\(UUID().uuidString)")!, rescueURL: nil), records, ())
    }
}

@MainActor @Suite struct TwoDeviceVialTests {
    /// Two devices on one set of records: each logs a dose from the same vial before seeing the other's.
    @Test func bothDosesCountAfterTheMerge() throws {
        let (phone, records, _) = try makeStore()
        let vialId = phone.mutate { $0.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 2)) }
        let mac = AppStore(records: records, defaults: UserDefaults(suiteName: "bench-test-\(UUID().uuidString)")!, rescueURL: nil, clock: { 1_000_000 })
        func dose(_ day: Double) -> DoseLog {
            DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: 1_700_000_000_000 + day * DAY_MS, doseMcg: 250, route: .subcutaneous, vialId: vialId)
        }
        phone.mutate { $0.addLog(dose(0)) }
        mac.mutate { $0.addLog(dose(1)) }   // never saw the phone's dose
        #expect(mac.data.vials.first { $0.id == vialId }?.drawnMcg == 250, "the stale device's own total")

        // What arrives from the other device is a merge; reading it puts the total right on both.
        phone.reload()
        mac.reload()
        for store in [phone, mac] {
            #expect(store.data.logs.count == 2)
            #expect(store.data.vials.first { $0.id == vialId }?.drawnMcg == 500)
        }
        // And what is stored says the same, so it will not flip back.
        let stored = document(from: try records.loadEnvelopes(), activeProfileId: "me")
        #expect(stored.vials.first { $0.id == vialId }?.drawnMcg == 500)
    }
}

@MainActor @Suite struct FirstLaunchWithICloudTests {
    /// A second device opening for the first time must not write factory settings that are newer
    /// than, and would replace, the ones still on their way from the first.
    @Test func nothingIsWrittenUntilSomethingChanges() throws {
        let records = try RecordStore(location: .memory)
        let store = AppStore(records: records, defaults: UserDefaults(suiteName: "bench-test-\(UUID().uuidString)")!, rescueURL: nil,
                             clock: { 1_000_000 }, holdDefaults: true)
        #expect(try records.loadEnvelopes().isEmpty)
        #expect(store.data.profiles == [DEFAULT_PROFILE])
        store.mutate { $0.settings.protocolSort = .alphabetical }
        let kinds = try records.loadEnvelopes().map(\.kind)
        let ids = try records.loadEnvelopes().map(\.recordId)
        #expect(Set(kinds) == ["setting"] && ids.contains("iosProtocolSort"), "only what was changed is written, one row per setting")
    }

    @Test func recordsThatArriveReplaceTheFactoryOnes() throws {
        let records = try RecordStore(location: .memory)
        // The new device opens first, before anything has reached it, and is used for a moment.
        let fresh = AppStore(records: records, defaults: UserDefaults(suiteName: "bench-test-\(UUID().uuidString)")!, rescueURL: nil,
                             clock: { 2_000 }, holdDefaults: true)
        // Meanwhile the first device's settings land in the records, with an older stamp than the new device's clock.
        let first = AppStore(records: records, defaults: UserDefaults(suiteName: "bench-test-\(UUID().uuidString)")!, rescueURL: nil, clock: { 500 })
        first.mutate { $0.settings.neverInjectSites = [.armL]; $0.settings.stockSort = .alphabetical }
        fresh.reload()
        #expect(fresh.data.settings.neverInjectSites == [.armL] && fresh.data.settings.stockSort == .alphabetical)
        let kept = document(from: try records.loadEnvelopes(), activeProfileId: "me")
        #expect(kept.settings.neverInjectSites == [.armL], "the first device's settings were never overwritten")
    }
}

@MainActor @Suite struct SettingRowTests {
    func store(_ records: RecordStore, at: Millis) -> AppStore {
        AppStore(records: records, defaults: UserDefaults(suiteName: "bench-test-\(UUID().uuidString)")!, rescueURL: nil, clock: { at })
    }

    /// Two devices each change a different setting before seeing the other's change.
    @Test func differentSettingsDoNotOverwriteEachOther() throws {
        let records = try RecordStore(location: .memory)
        let phone = store(records, at: 1_000)
        let mac = store(records, at: 2_000)
        phone.mutate { $0.settings.neverInjectSites = [.armL] }
        mac.mutate { $0.settings.protocolSort = .alphabetical }   // its copy has no idea of the phone's change
        phone.reload(); mac.reload()
        for s in [phone, mac] {
            #expect(s.data.settings.neverInjectSites == [.armL] && s.data.settings.protocolSort == .alphabetical)
        }
    }

    /// Settings saved as one row by an earlier build are converted, without losing any.
    @Test func theOldSingleRowBecomesOneRowEach() throws {
        let records = try RecordStore(location: .memory)
        var old = AppData()
        old.settings.currency = "EUR"
        old.settings.neverInjectSites = [.gluteL]
        let payload = try old.settings.lenientJSON(encoder: Codec.encoder)
        records.container.mainContext.insert(Record(kind: "settings", recordId: "settings", profileId: nil, payload: payload, updatedAt: Date(timeIntervalSince1970: 100)))
        try records.container.mainContext.save()
        let s = store(records, at: 5_000)
        #expect(s.data.settings.currency == "EUR" && s.data.settings.neverInjectSites == [.gluteL])
        let kinds = Set(try records.loadEnvelopes().map(\.kind))
        #expect(!kinds.contains("settings") && kinds.contains("setting"))
    }
}
