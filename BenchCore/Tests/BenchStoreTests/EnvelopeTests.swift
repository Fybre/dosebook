import Foundation
import Testing
import BenchCore
@testable import BenchStore

private func sample() -> AppData {
    var d = AppData()
    d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 2))
    d.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: 1_000_000, doseMcg: 250, route: .subcutaneous))
    d.setHalfLifeOverride("kpv", hours: 2, now: 5)
    d.settings.currency = "EUR"
    d.extra["futureThing"] = .array([.string("x")])
    d.unreadable["logs"] = [.object(["id": .string("broken")])]
    d.logs[0].extra["futureField"] = .bool(true)
    return d
}

@Suite struct EnvelopeTests {
    @Test func roundTrip() {
        let d = sample()
        let diff = envelopeDiff(from: nil, to: d)
        let back = document(from: diff.upserts, activeProfileId: "me")
        #expect(back == migrateAppData(d))
        #expect(back.logs[0].extra["futureField"] == .bool(true) && back.extra["futureThing"] != nil && back.unreadable["logs"]?.count == 1)
    }

    @Test func diffOnlyTouchesWhatChanged() {
        let a = sample()
        var b = a
        b.updateLog(b.logs[0].id) { $0.notes = "x" }
        let diff = envelopeDiff(from: a, to: b)
        #expect(Set(diff.upserts.map(\.kind)) == ["log"] && diff.deletes.isEmpty)
        var c = b
        c.removeLog(c.logs[0].id)
        let del = envelopeDiff(from: b, to: c)
        #expect(del.deletes.map(\.kind) == ["log"] && del.upserts.map(\.kind) == ["vial"])
        var e = c
        e.setHalfLifeOverride("kpv", hours: nil)
        #expect(envelopeDiff(from: c, to: e).deletes == [EnvelopeKey(kind: "halfLifeOverride", recordId: "kpv")])
        #expect(envelopeDiff(from: e, to: e).isEmpty)
    }

    @Test func dedupeKeepsNewest() {
        let old = Envelope(kind: "profile", recordId: "me", profileId: nil, payload: Data(#"{"id":"me","name":"Old","tone":"mint","createdAt":0}"#.utf8), updatedAt: Date(timeIntervalSince1970: 1))
        let new = Envelope(kind: "profile", recordId: "me", profileId: nil, payload: Data(#"{"id":"me","name":"New","tone":"mint","createdAt":0}"#.utf8), updatedAt: Date(timeIntervalSince1970: 2))
        let (kept, dupes) = dedupe([old, new])
        #expect(kept == [new] && dupes == [old])
        #expect(document(from: kept, activeProfileId: nil).profiles.map(\.name) == ["New"])
    }

    @Test func emptyStoreIsAFreshDocument() {
        let d = document(from: [], activeProfileId: nil)
        #expect(d.profiles == [DEFAULT_PROFILE] && d.activeProfileId == "me" && d.logs.isEmpty)
    }

    @Test func activeProfileIsPerDevice() {
        var d = AppData()
        let p = d.addProfile(name: "B")
        let ups = envelopeDiff(from: nil, to: d).upserts
        #expect(document(from: ups, activeProfileId: p).activeProfileId == p)
        #expect(document(from: ups, activeProfileId: "gone").activeProfileId == "me")
    }

    @MainActor @Test func swiftDataRoundTrip() throws {
        let store = try RecordStore(location: .memory)
        let d = sample()
        try store.apply(envelopeDiff(from: nil, to: d))
        var next = d
        next.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: 2_000_000, doseMcg: 250, route: .subcutaneous))
        try store.apply(envelopeDiff(from: d, to: next))
        let back = document(from: try store.loadEnvelopes(), activeProfileId: "me")
        #expect(back.logs.count == 2 && back.vials[0].drawnMcg == 500)
        // A duplicate written by another device is removed on load.
        store.container.mainContext.insert(Record(kind: "setting", recordId: "currency", profileId: nil, payload: Data("\"USD\"".utf8), updatedAt: .distantPast))
        try store.container.mainContext.save()
        #expect(try store.loadEnvelopes().filter { $0.kind == "setting" && $0.recordId == "currency" }.count == 1)
        #expect(document(from: try store.loadEnvelopes(), activeProfileId: "me").settings.currency == "EUR")
    }
}
