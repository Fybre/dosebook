import Foundation
import Testing
@testable import BenchCore

@Suite struct VialLedgerTests {
    /// A 5 mg vial, mixed, with 250 mcg doses logged against it.
    func setup(doses: Int = 2) -> (AppData, String) {
        var d = AppData()
        let id = d.addVial(Vial(id: "", profileId: "", peptideId: "bpc-157", strengthMg: 5, state: .reconstituted, diluentMl: 2))
        for n in 0..<doses {
            d.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: local(2026, 7, 1 + n, 8), doseMcg: 250, route: .subcutaneous, vialId: id))
        }
        return (d, id)
    }
    func vial(_ d: AppData, _ id: String) -> Vial { d.vials.first { $0.id == id }! }

    @Test func startIsWhatTheDosesDoNotExplain() {
        var (d, id) = setup()
        d.settleDrawnStarts()
        #expect(vial(d, id).drawnMcg == 500 && vial(d, id).drawnStart == 0)
        // Told by hand that 2 mg are gone: the 500 from doses are part of it.
        d.updateVial(id) { $0.drawnMcg = 2000 }
        d.settleDrawnStarts()
        #expect(vial(d, id).drawnStart == 1500)
        d.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: local(2026, 7, 5, 8), doseMcg: 250, route: .subcutaneous, vialId: id))
        d.settleDrawnStarts()
        #expect(vial(d, id).drawnMcg == 2250 && vial(d, id).drawnStart == 1500)
    }

    @Test func aMergeThatKeptOnlyOneDevicesTotalIsPutRight() {
        // Two devices each logged one dose from the same vial. The vial record that survived the
        // merge is the phone's (250 drawn), but both doses are there.
        var (d, id) = setup()
        d.settleDrawnStarts()
        d.updateVial(id) { $0.drawnMcg = 250 }
        let first = d.reconcileDrawn()
        #expect(first)
        #expect(vial(d, id).drawnMcg == 500)
        let second = d.reconcileDrawn()
        #expect(!second, "settled: a second pass changes nothing")
    }

    @Test func aHandCorrectionSurvivesTheNextReconcile() {
        var (d, id) = setup()
        d.updateVial(id) { $0.drawnMcg = 3000 }
        d.settleDrawnStarts()
        let changed = d.reconcileDrawn()
        #expect(!changed)
        #expect(vial(d, id).drawnMcg == 3000)
    }

    @Test func olderDataGetsAStartThatKeepsItsTotal() {
        var (d, id) = setup()
        d.updateVial(id) { $0.drawnMcg = 1200; $0.drawnStart = nil }
        d.reconcileDrawn()
        #expect(vial(d, id).drawnMcg == 1200 && vial(d, id).drawnStart == 700)
    }

    @Test func dosesThatEmptyAVialFinishIt() {
        var (d, id) = setup(doses: 0)
        d.settleDrawnStarts()
        for n in 0..<20 {
            d.logs.append(DoseLog(id: "x\(n)", profileId: d.activeProfileId, peptideId: "bpc-157", at: local(2026, 7, 1 + n), doseMcg: 250, route: .subcutaneous, vialId: id))
        }
        d.reconcileDrawn()
        #expect(vial(d, id).drawnMcg == 5000 && vial(d, id).state == .finished)
    }

    @Test func overdrawDoesNotCorruptTheStart() {
        var (d, id) = setup(doses: 0)
        d.updateVial(id) { $0.drawnMcg = 4900 }
        d.settleDrawnStarts()
        d.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: local(2026, 7, 2, 8), doseMcg: 500, route: .subcutaneous, vialId: id))
        d.settleDrawnStarts()
        #expect(vial(d, id).drawnMcg == 5000)
        #expect(vial(d, id).drawnStart == 4900, "at capacity, the start keeps its last honest value")
    }

    @Test func skippedAndUnlinkedDosesTakeNothing() {
        var (d, id) = setup(doses: 0)
        d.addLog(DoseLog(id: "", profileId: "", peptideId: "bpc-157", at: local(2026, 7, 1, 8), doseMcg: 250, route: .subcutaneous, vialId: id, skipped: true))
        d.settleDrawnStarts()
        #expect(vial(d, id).drawnStart == 0 && d.loggedDrawByVial().isEmpty)
    }

    @Test func deletingADoseGivesItBack() {
        var (d, id) = setup()
        d.settleDrawnStarts()
        d.removeLog(d.logs[0].id)
        d.settleDrawnStarts()
        #expect(vial(d, id).drawnMcg == 250 && vial(d, id).drawnStart == 0)
        let changed = d.reconcileDrawn()
        #expect(!changed)
    }
}
