import Foundation
import Testing
@testable import BenchCore

// The original has no store tests; these hold the rules its comments state.

private func dose(_ peptide: String = "bpc-157", at: Millis = 1_000_000, mcg: Double = 250, route: Route = .subcutaneous,
                  skipped: Bool? = nil, vialId: String? = nil) -> DoseLog {
    DoseLog(id: "", profileId: "", peptideId: peptide, at: at, doseMcg: mcg, route: route, vialId: vialId, skipped: skipped)
}

@Suite struct StoreActionTests {
    @Test func addLogDrawsFromOpenVialAndRecordsMarks() {
        var d = AppData()
        let v = d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 2))
        let id = d.addLog(dose())
        let log = d.logs.first { $0.id == id }!
        #expect(log.vialId == v && log.profileId == "me")
        #expect(log.units == 10 && log.syringeScale == .u100 && log.syringeId == "u100-0.5")
        #expect(d.vials[0].drawnMcg == 250)
    }

    @Test func skippedOrUnstockedDosesDrawNothing() {
        var d = AppData()
        d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 2))
        d.addLog(dose(skipped: true))
        d.addLog(dose("kpv"))
        #expect(d.vials[0].drawnMcg == nil && d.logs.allSatisfy { $0.vialId == nil })
    }

    @Test func tabletDoseDrawsFromPack() {
        var d = AppData()
        var custom = Peptide(id: "custom-slu", name: "SLU", category: .metabolic)
        custom.preparation = .tablet
        d.addCustomPeptide(custom)
        let pack = d.addVial(Vial(id: "", profileId: "", peptideId: "custom-slu", strengthMg: 600, state: .sealed, container: .pack, mgPerTablet: 10))
        d.addLog(dose("custom-slu", mcg: 10_000, route: .oral))
        let v = d.vials.first { $0.id == pack }!
        #expect(v.drawnMcg == 10_000 && v.state == .reconstituted)
    }

    @Test func neverDrawsFromAnotherProfile() {
        var d = AppData()
        d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 2))
        d.addProfile(name: "Partner")
        d.addLog(dose())
        #expect(d.vials[0].drawnMcg == nil)
    }

    @Test func editAndDeleteReconcileStock() {
        var d = AppData()
        d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 2))
        let id = d.addLog(dose())
        d.updateLog(id) { $0.doseMcg = 500 }
        #expect(d.vials[0].drawnMcg == 500)
        d.updateLog(id) { $0.peptideId = "kpv" }
        #expect(d.logs[0].vialId == nil && d.vials[0].drawnMcg == 0)
        let id2 = d.addLog(dose())
        d.removeLog(id2)
        #expect(d.vials[0].drawnMcg == 0)
    }

    @Test func profilesCascade() {
        var d = AppData()
        let p2 = d.addProfile(name: " ")
        #expect(d.activeProfile.name == "Profile 2" && d.activeProfile.tone == .grape)
        d.addLog(dose())
        d.addDiluent(DiluentBottle(id: "", profileId: "", kind: .bacteriostatic, volumeMl: 30, state: .sealed))
        d.removeProfile(p2)
        #expect(d.logs.isEmpty && d.diluents.isEmpty && d.activeProfileId == "me")
        d.removeProfile("me")
        #expect(d.profiles.count == 1)
        d.switchProfile("nobody")
        #expect(d.activeProfileId == "me")
    }

    @Test func removingProtocolKeepsHistory() {
        var d = AppData()
        let p = d.addProtocol(makeProtocol(startedAt: 0, schedule: Schedule(kind: .daily)))
        var l = dose(); l.protocolId = p
        d.addLog(l)
        d.removeProtocol(p)
        #expect(d.protocols.isEmpty && d.logs.count == 1 && d.logs[0].protocolId == nil)
    }

    @Test func ordersAreDeliveries() {
        var d = AppData()
        let v = Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .onOrder)
        d.addOrder([v], shippingCost: nil, currency: nil)
        #expect(d.orders.isEmpty && d.vials[0].orderId == nil)
        d.addOrder([v, v], shippingCost: 0, currency: "EUR")
        #expect(d.orders.count == 1 && d.orders[0].shippingCost == nil && d.vials.filter { $0.orderId != nil }.count == 2)
        let ids = d.vials.filter { $0.orderId != nil }.map(\.id)
        d.removeVial(ids[0])
        #expect(d.orders.count == 1)
        d.removeVial(ids[1])
        #expect(d.orders.isEmpty)
    }

    @Test func reconstituteDrawsWaterAndTopUpKeepsBUD() {
        var d = AppData()
        let b = d.addDiluent(DiluentBottle(id: "", profileId: "", kind: .bacteriostatic, volumeMl: 30, state: .sealed))
        let v = d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .sealed))
        d.reconstituteVial(v, diluentMl: 2, diluent: .bacteriostatic, at: 1000, fromBottleId: b)
        #expect(d.diluents[0].drawnMl == 2 && d.diluents[0].state == .open && d.vials[0].budAt == beyondUseDate(1000))
        d.topUpVial(v, addedMl: 1, fromBottleId: b, now: 5000)
        #expect(isClose(d.vials[0].diluentMl!, 3, digits: 9) && d.vials[0].budAt == beyondUseDate(1000) && d.diluents[0].drawnMl == 3)
        d.topUpVial(v, addedMl: -1, fromBottleId: b)
        #expect(d.diluents[0].drawnMl == 3)
    }

    @Test func sprayTransfer() {
        var d = AppData()
        let v = d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, cost: 40, diluentMl: 1))
        let bottle = d.transferToSpray(vialId: v, addedMl: 4, mlPerSpray: 0.1)!
        #expect(d.vials.count == 2 && d.vials.first { $0.id == v }!.state == .finished)
        let b = d.vials.first { $0.id == bottle }!
        #expect(b.container == .spray && b.profileId == "me" && b.cost == 40 && d.vials.first { $0.id == v }!.cost == nil)
    }

    @Test func checkInsUpsertAndRefuseTomorrow() {
        var d = AppData()
        let now = local(2026, 6, 10, 14)
        let a = d.saveCheckIn(at: local(2026, 6, 10, 8), ratings: ["energy": 2], notes: nil, now: now)
        let b = d.saveCheckIn(at: local(2026, 6, 10, 20), ratings: ["energy": 4], notes: "better", now: now)
        #expect(a == b && d.checkIns.count == 1 && d.checkIns[0].rating(.energy) == 4)
        #expect(d.saveCheckIn(at: local(2026, 6, 11, 9), ratings: [:], notes: nil, now: now) == nil)
    }

    @Test func vitalsUpsert() {
        var d = AppData()
        d.recordVitals(dayMs: local(2026, 6, 10, 9), sleepHours: 7, restingHrBpm: nil)
        d.recordVitals(dayMs: local(2026, 6, 10, 18), sleepHours: nil, restingHrBpm: 55)
        #expect(d.measurements.count == 1 && d.measurements[0].sleepHours == 7 && d.measurements[0].restingHrBpm == 55)
        d.recordVitals(dayMs: 0, sleepHours: nil, restingHrBpm: nil)
        #expect(d.measurements.count == 1)
    }

    @Test func notesAndOverrides() {
        var d = AppData()
        d.setCompoundNote("ghk-cu", text: "  stings  ")
        let id = d.compoundNotes[0].id
        d.setCompoundNote("ghk-cu", text: "stings less diluted")
        #expect(d.compoundNotes.count == 1 && d.compoundNotes[0].id == id && d.compoundNotes[0].text == "stings less diluted")
        d.setCompoundNote("ghk-cu", text: "   ")
        #expect(d.compoundNotes.isEmpty)
        d.setHalfLifeOverride("kpv", hours: 2, now: 5)
        #expect(d.halfLifeOverrides["kpv"]?.hours == 2)
        d.setHalfLifeOverride("kpv", hours: 0)
        #expect(d.halfLifeOverrides.isEmpty)
    }

    @Test func customCompoundKeepsId() {
        var d = AppData()
        let p = draftToPeptide(CustomDraft(name: "Mine"))
        d.addCustomPeptide(p)
        var renamed = p; renamed.name = "Renamed"; renamed.id = "custom-renamed"
        d.updateCustomPeptide(p.id, renamed)
        #expect(d.customPeptides.count == 1 && d.customPeptides[0].id == p.id && d.customPeptides[0].name == "Renamed")
        #expect(d.allPeptides.count == Library.peptides.count + 1)
    }

    @Test func importKeepsSyncAndMigrates() {
        var d = AppData()
        d.settings.extra["sync"] = .object(["url": .string("https://x")])
        var backup = AppData()
        backup.logs = [DoseLog(id: "l1", profileId: "", peptideId: "kpv", at: 1, doseMcg: 1, route: .subcutaneous)]
        d.importData(backup)
        #expect(d.logs[0].profileId == "me" && d.settings.extra["sync"] != nil)
        #expect(d.exportDocument.settings.extra["sync"] == nil)
        d.importHistory(logs: [dose(vialId: "v")], measurements: [])
        #expect(d.logs.count == 2 && d.logs.allSatisfy { $0.vialId == nil })
    }
}
