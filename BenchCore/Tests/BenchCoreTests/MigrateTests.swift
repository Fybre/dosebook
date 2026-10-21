import Foundation
import Testing
@testable import BenchCore

// Port of src/lib/migrate.test.ts. Fixtures are JSON as old builds wrote them.

private let NOW: Double = 1_785_499_200_000 // Date.UTC(2026, 6, 31, 12)
private let D: Double = 86_400_000

private func json(_ s: String) -> JSONValue { try! JSONDecoder().decode(JSONValue.self, from: Data(s.utf8)) }
private func migrate(_ s: String) -> AppData { migrateAppData(json(s)) }

private let protocolsV1 = """
[{"id":"p1","peptideId":"bpc-157","name":"BPC daily","active":true,"startedAt":\(NOW - 60 * D),"doseMcg":500,
  "route":"subcutaneous","schedule":{"kind":"daily"},"titrationAutoAdvance":false}]
"""
private let logsV1 = """
[{"id":"l1","peptideId":"bpc-157","at":\(NOW - D),"doseMcg":500,"route":"subcutaneous","vialId":"v1"},
 {"id":"l2","peptideId":"bpc-157","at":\(NOW - 2 * D),"doseMcg":500,"route":"subcutaneous","vialId":"v1"}]
"""
private let settingsV1 = #"{"doseUnit":"mcg","budWarningDays":5}"#

private func v1(vials: String = #"[{"id":"v1","peptideId":"bpc-157","strengthMg":5,"state":"reconstituted","diluentMl":2,"drawnMl":0.4}]"#,
                logs: String = logsV1, version: Int = 1) -> String {
    #"{"version":\#(version),"protocols":\#(protocolsV1),"logs":\#(logs),"vials":\#(vials),"settings":\#(settingsV1)}"#
}
private let V1 = v1()
private let V2 = #"{"version":2,"protocols":\#(protocolsV1),"logs":\#(logsV1),"vials":[{"id":"v1","peptideId":"bpc-157","strengthMg":5,"state":"reconstituted","diluentMl":2,"drawnMcg":1000}],"settings":\#(settingsV1)}"#

private func owned(_ arr: String) -> String {
    var v = try! JSONDecoder().decode([JSONObject].self, from: Data(arr.utf8))
    for i in v.indices { v[i]["profileId"] = .string("arun") }
    return String(data: try! JSONEncoder().encode(v), encoding: .utf8)!
}
private let V3 = #"{"version":3,"profiles":[{"id":"arun","name":"Arun","tone":"grape","createdAt":\#(NOW - 90 * D)}],"activeProfileId":"arun","protocols":\#(owned(protocolsV1)),"logs":\#(owned(logsV1)),"vials":\#(owned(#"[{"id":"v1","peptideId":"bpc-157","strengthMg":5,"state":"reconstituted","diluentMl":2,"drawnMcg":1000}]"#)),"settings":\#(settingsV1)}"#
private let V4: String = {
    var o = json(V3).objectValue!
    o["version"] = .number(4)
    o["measurements"] = json(#"[{"id":"m1","profileId":"arun","at":\#(NOW - 5 * D),"weightKg":88.2}]"#)
    return String(data: try! JSONEncoder().encode(o), encoding: .utf8)!
}()

@Suite struct NothingIsEverLost {
    @Test(arguments: [V1, V2, V3, V4]) func keepsAndOwnsEverything(_ payload: String) {
        let out = migrate(payload)
        let raw = json(payload)
        #expect(out.protocols.count == raw["protocols"]!.arrayValue!.count)
        #expect(out.logs.count == raw["logs"]!.arrayValue!.count)
        #expect(out.vials.count == raw["vials"]!.arrayValue!.count)
        #expect(out.version == DATA_VERSION)
        let ids = Set(out.profiles.map(\.id))
        #expect(ids.contains(out.activeProfileId))
        let owners = out.protocols.map(\.profileId) + out.logs.map(\.profileId) + out.vials.map(\.profileId)
            + out.measurements.map(\.profileId) + out.labs.map(\.profileId)
        for o in owners { #expect(!o.isEmpty && ids.contains(o)) }
    }
}

@Suite struct VolumeBecomesMass {
    @Test func convertsWithConcentration() { #expect(migrate(V1).vials[0].drawnMcg == 1000) }

    @Test func neverExceedsVial() {
        #expect(migrate(v1(vials: #"[{"id":"v1","peptideId":"bpc-157","strengthMg":5,"state":"reconstituted","diluentMl":2,"drawnMl":99}]"#)).vials[0].drawnMcg == 5000)
    }

    @Test func rebuildsFromHistory() {
        #expect(migrate(v1(vials: #"[{"id":"v1","peptideId":"bpc-157","strengthMg":5,"state":"sealed"}]"#)).vials[0].drawnMcg == 1000)
    }

    @Test func leavesConverted() { #expect(migrate(V2).vials[0].drawnMcg == 1000) }

    @Test func ignoresSkipped() {
        let logs = logsV1.dropLast() + #",{"id":"l3","peptideId":"bpc-157","at":\#(NOW),"doseMcg":500,"route":"subcutaneous","vialId":"v1","skipped":true}]"#
        #expect(migrate(v1(vials: #"[{"id":"v1","peptideId":"bpc-157","strengthMg":5,"state":"sealed"}]"#, logs: String(logs))).vials[0].drawnMcg == 1000)
    }
}

@Suite struct AnOwnerForEverything {
    @Test func adoptsOwnerless() {
        let out = migrate(V2)
        #expect(out.profiles.count == 1)
        #expect(out.logs.allSatisfy { $0.profileId == out.activeProfileId })
    }

    @Test func keepsExistingProfile() {
        let out = migrate(V3)
        #expect(out.activeProfileId == "arun" && out.profiles[0].name == "Arun")
    }

    @Test func repairsActiveProfileId() {
        let out = migrate(V3.replacingOccurrences(of: #""activeProfileId":"arun""#, with: #""activeProfileId":"deleted-profile""#))
        #expect(out.activeProfileId == "arun")
        #expect(out.logs.allSatisfy { l in out.profiles.contains { $0.id == l.profileId } })
    }
}

@Suite struct FieldsThatDidNotExist {
    @Test func emptyCollections() {
        let out = migrate(V1)
        #expect(out.measurements.isEmpty && out.labs.isEmpty && out.customPeptides.isEmpty)
    }

    @Test func keepsMeasurements() {
        #expect(migrate(V4).measurements.count == 1)
        #expect(migrate(V4).measurements[0].weightKg == 88.2)
    }

    @Test func fillsSettings() {
        let out = migrate(V1)
        #expect(out.settings.budWarningDays == 5)
        #expect(out.settings.currency == DEFAULT_SETTINGS.currency)
        #expect(out.settings.backupKeep == DEFAULT_SETTINGS.backupKeep)
    }
}

@Suite struct Robustness {
    @Test func idempotent() {
        let once = migrate(V1)
        #expect(migrateAppData(once) == once)
        let current = migrate(V4)
        #expect(migrateAppData(current) == current)
    }

    @Test(arguments: ["null", "{}", "\"nonsense\"", "[]"]) func survivesJunk(_ junk: String) {
        let out = migrate(junk)
        #expect(out.version == DATA_VERSION && !out.profiles.isEmpty && out.logs.isEmpty)
    }

    @Test func distrustsVersion() {
        let out = migrate(v1(version: DATA_VERSION))
        #expect(out.vials[0].drawnMcg == 1000)
        #expect(out.logs.allSatisfy { !$0.profileId.isEmpty })
    }

    @Test func newestFirst() {
        let out = migrate(V1)
        #expect(out.logs[0].at > out.logs[1].at)
    }
}

@Suite struct LooksLikeAppData {
    @Test func acceptsHistorical() {
        for p in [V1, V2, V3, V4] { #expect(looksLikeAppData(json(p))) }
    }

    @Test func rejectsElse() {
        for junk in ["null", "{}", "[]", "\"x\"", "5", #"{"logs":[]}"#] { #expect(!looksLikeAppData(json(junk))) }
    }
}

@Suite struct VersionStamp {
    @Test func emptyIsCurrent() {
        #expect(AppData.empty.version == DATA_VERSION)
        #expect(migrateAppData(AppData.empty) == migrateAppData(migrateAppData(AppData.empty)))
    }

    @Test func recoversMisstamped() throws {
        var o = try JSONValue.from(migrate(V4)).objectValue!
        o["version"] = .number(1)
        let out = migrateAppData(.object(o))
        #expect(out.version == DATA_VERSION && out.logs.count == 2 && out.measurements.count == 1)
        #expect(out.logs.allSatisfy { !$0.profileId.isEmpty })
    }
}

@Suite struct CheckInsV6 {
    @Test func emptyList() { #expect(migrate(#"{"version":5,"logs":[],"protocols":[]}"#).checkIns.isEmpty) }

    @Test func adoptsOwnerless() {
        let out = migrate(#"{"logs":[],"protocols":[],"checkIns":[{"id":"c1","at":1780272000000,"ratings":{"energy":4}}]}"#)
        #expect(out.checkIns[0].profileId == out.activeProfileId)
    }

    @Test func collapsesDay() {
        let day = local(2026, 6, 1)
        let out = migrate(#"{"logs":[],"protocols":[],"checkIns":[{"id":"morning","profileId":"me","at":\#(day + HOUR),"ratings":{"energy":2}},{"id":"evening","profileId":"me","at":\#(day + 20 * HOUR),"ratings":{"energy":5}}]}"#)
        #expect(out.checkIns.count == 1 && out.checkIns[0].ratings["energy"] == 5)
    }

    @Test func normalisesToDayStart() {
        let out = migrate(#"{"logs":[],"protocols":[],"checkIns":[{"id":"c","profileId":"me","at":\#(local(2026, 6, 1, 22, 45)),"ratings":{}}]}"#)
        #expect(out.checkIns[0].at == local(2026, 6, 1))
    }

    @Test func profilesApart() {
        let day = local(2026, 6, 1, 9)
        let out = migrate(#"{"logs":[],"protocols":[],"profiles":[{"id":"a","name":"A","createdAt":0},{"id":"b","name":"B","createdAt":0}],"activeProfileId":"a","checkIns":[{"id":"1","profileId":"a","at":\#(day),"ratings":{"energy":1}},{"id":"2","profileId":"b","at":\#(day),"ratings":{"energy":5}}]}"#)
        #expect(out.checkIns.count == 2)
    }

    @Test func idempotent() {
        let once = migrate(#"{"logs":[],"protocols":[],"checkIns":[{"id":"c","profileId":"me","at":\#(nowMillis()),"ratings":{"mood":3}}]}"#)
        #expect(migrateAppData(once) == once)
    }
}

@Suite struct OverridesV7 {
    @Test func emptyMap() { #expect(migrate(#"{"version":6,"logs":[]}"#).halfLifeOverrides.isEmpty) }

    @Test func carriesFigures() {
        let out = migrate(#"{"version":7,"halfLifeOverrides":{"kpv":{"hours":2,"setAt":1700000000000,"note":"vendor sheet"}}}"#)
        #expect(out.halfLifeOverrides == ["kpv": HalfLifeOverride(hours: 2, setAt: 1_700_000_000_000, note: "vendor sheet")])
    }

    @Test func dropsUnusable() {
        let out = migrate(#"{"version":7,"halfLifeOverrides":{"good":{"hours":4,"setAt":1},"zero":{"hours":0,"setAt":1},"negative":{"hours":-2,"setAt":1},"text":{"hours":"soon","setAt":1}}}"#)
        #expect(Array(out.halfLifeOverrides.keys) == ["good"])
    }

    @Test func repairsTimestamp() {
        let out = migrate(#"{"version":7,"halfLifeOverrides":{"kpv":{"hours":2}}}"#)
        #expect(out.halfLifeOverrides["kpv"]?.hours == 2 && (out.halfLifeOverrides["kpv"]?.setAt ?? 0) > 0)
    }

    @Test func idempotent() {
        let once = migrate(#"{"version":6,"halfLifeOverrides":{"kpv":{"hours":2,"setAt":5}}}"#)
        #expect(migrateAppData(once) == once)
    }
}

@Suite struct OrdersV7 {
    @Test func emptyList() { #expect(migrate(#"{"version":6,"logs":[]}"#).orders.isEmpty) }

    @Test func adopts() {
        let out = migrate(#"{"version":7,"orders":[{"id":"o1","shippingCost":60,"placedAt":1}]}"#)
        #expect(out.orders[0].profileId == out.activeProfileId)
    }

    @Test func keepsOrderDropsFigure() {
        let out = migrate(#"{"version":7,"orders":[{"id":"good","profileId":"me","shippingCost":60,"placedAt":1},{"id":"zero","profileId":"me","shippingCost":0,"placedAt":1},{"id":"text","profileId":"me","shippingCost":"sixty","placedAt":1}]}"#)
        #expect(out.orders.map(\.id) == ["good", "zero", "text"])
        #expect(out.orders.map(\.shippingCost) == [60, nil, nil])
    }

    @Test func refusesNoId() {
        #expect(migrate(#"{"version":7,"orders":[{"profileId":"me","shippingCost":60,"placedAt":1}]}"#).orders.isEmpty)
    }

    @Test func idempotent() {
        let once = migrate(#"{"version":7,"orders":[{"id":"o1","profileId":"me","shippingCost":60,"placedAt":1}]}"#)
        #expect(migrateAppData(once) == once)
    }
}

@Suite struct BottlesV8 {
    @Test func emptyShelf() { #expect(migrate(#"{"version":7,"logs":[]}"#).diluents.isEmpty) }

    @Test func adopts() {
        let out = migrate(#"{"version":8,"diluents":[{"id":"b1","kind":"bacteriostatic","volumeMl":30,"state":"sealed"}]}"#)
        #expect(out.diluents[0].profileId == out.activeProfileId)
    }

    @Test func dropsEmpty() {
        let out = migrate(#"{"version":8,"diluents":[{"id":"good","profileId":"me","kind":"bacteriostatic","volumeMl":30,"state":"sealed"},{"id":"empty","profileId":"me","kind":"bacteriostatic","volumeMl":0,"state":"sealed"}]}"#)
        #expect(out.diluents.map(\.id) == ["good"])
    }

    @Test func idempotent() {
        let once = migrate(#"{"version":8,"diluents":[{"id":"b1","profileId":"me","kind":"bacteriostatic","volumeMl":30,"state":"sealed"}]}"#)
        #expect(migrateAppData(once) == once)
    }
}

@Suite struct NotesV9 {
    let note = #"{"id":"n1","profileId":"me","peptideId":"ghk-cu","text":"Stings under 1 mg/mL.","updatedAt":1700000000000}"#

    @Test func emptyList() { #expect(migrate(#"{"version":8,"logs":[]}"#).compoundNotes.isEmpty) }

    @Test func carriesNote() {
        #expect(migrate(#"{"version":9,"compoundNotes":[\#(note)]}"#).compoundNotes
            == [CompoundNote(id: "n1", profileId: "me", peptideId: "ghk-cu", text: "Stings under 1 mg/mL.", updatedAt: 1_700_000_000_000)])
    }

    @Test func adopts() {
        let out = migrate(#"{"version":9,"compoundNotes":[{"id":"n1","peptideId":"ghk-cu","text":"x","updatedAt":1}]}"#)
        #expect(out.compoundNotes[0].profileId == out.activeProfileId)
    }

    @Test func dropsBlankAndCompoundless() {
        let out = migrate(#"{"version":9,"compoundNotes":[\#(note),{"id":"n2","profileId":"me","peptideId":"bpc-157","text":"   ","updatedAt":1}]}"#)
        #expect(out.compoundNotes.map(\.id) == ["n1"])
        #expect(migrate(#"{"version":9,"compoundNotes":[{"id":"n3","profileId":"me","peptideId":"","text":"x","updatedAt":1}]}"#).compoundNotes.isEmpty)
    }

    @Test func newestWins() {
        let out = migrate(#"{"version":9,"compoundNotes":[\#(note),{"id":"n2","profileId":"me","peptideId":"ghk-cu","text":"Half that again and it is fine.","updatedAt":1700000000001}]}"#)
        #expect(out.compoundNotes.count == 1 && out.compoundNotes[0].id == "n2")
    }

    @Test func twoProfiles() {
        let out = migrate(#"{"version":9,"profiles":[{"id":"me","name":"Me","tone":"mint","createdAt":0},{"id":"you","name":"You","tone":"sky","createdAt":0}],"activeProfileId":"me","compoundNotes":[\#(note),{"id":"n2","profileId":"you","peptideId":"ghk-cu","text":"Never hurts.","updatedAt":1}]}"#)
        #expect(out.compoundNotes.count == 2)
    }

    @Test func idempotent() {
        let once = migrate(#"{"version":8,"compoundNotes":[\#(note)]}"#)
        #expect(migrateAppData(once) == once)
    }
}

@Suite struct NewerBuildDocument {
    @Test func carriesUnknownField() throws {
        let out = migrate(#"{"version":99,"logs":[],"somethingAddedLater":[{"id":"x"}]}"#)
        #expect(out.extra["somethingAddedLater"] == json(#"[{"id":"x"}]"#))
        #expect(out.version == DATA_VERSION)
        let back = try JSONDecoder().decode(JSONValue.self, from: out.exportJSON())
        #expect(back["somethingAddedLater"] == json(#"[{"id":"x"}]"#))
    }

    @Test func repairsKnownFields() {
        let out = migrate(#"{"version":99,"logs":[{"id":"l1","peptideId":"kpv","at":1,"doseMcg":100,"route":"subcutaneous"}],"unknownThing":true}"#)
        #expect(!out.logs[0].profileId.isEmpty)
        #expect(out.extra["unknownThing"] == .bool(true))
    }

    /// Not in the original: the same guarantee one level down, per row, which
    /// matters here because every row also travels through CloudKit on its own.
    @Test func carriesUnknownRowFields() throws {
        let out = migrate(#"{"logs":[{"id":"l1","peptideId":"kpv","at":1,"doseMcg":100,"route":"subcutaneous","futureField":{"a":1}}],"protocols":[]}"#)
        #expect(out.logs[0].extra["futureField"] == json(#"{"a":1}"#))
        let back = try JSONDecoder().decode(JSONValue.self, from: out.exportJSON())
        #expect(back["logs"]?.arrayValue?.first?["futureField"] == json(#"{"a":1}"#))
    }

    @Test func unknownEnumValuesRoundTrip() throws {
        let out = migrate(#"{"logs":[{"id":"l1","peptideId":"kpv","at":1,"doseMcg":100,"route":"transdermal","site":"calf-l"}],"protocols":[]}"#)
        #expect(out.logs[0].route.rawValue == "transdermal" && !out.logs[0].route.isKnown)
        #expect(out.logs[0].site?.label == "calf-l")
    }

    @Test func unreadableRowsSurviveExport() throws {
        let out = migrate(#"{"logs":[{"id":"l1","at":1}],"protocols":[]}"#)
        #expect(out.logs.isEmpty)
        let back = try JSONDecoder().decode(JSONValue.self, from: out.exportJSON())
        #expect(back["logs"]?.arrayValue?.count == 1)
    }
}
