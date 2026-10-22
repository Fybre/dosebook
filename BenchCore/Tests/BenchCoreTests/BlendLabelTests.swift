import Foundation
import Testing
@testable import BenchCore

private func blend(_ a: Double?, _ b: Double?, dosing: BlendDosing = .split) -> Peptide {
    var d = CustomDraft(name: "CJC/Ipa", category: .blend)
    d.components = [BlendComponent(peptideId: "cjc-1295-no-dac", name: "CJC-1295", mgPerVial: a),
                    BlendComponent(peptideId: "ipamorelin", name: "Ipamorelin", mgPerVial: b)]
    var p = draftToPeptide(d)
    if dosing == .perComponent { p.blendDosing = .perComponent }
    return p
}

@Suite struct BlendLabelTests {
    @Test func evenBlendReadsEach() {
        #expect(doseLabel(500, blend(10, 10)) == "250 mcg each")
        #expect(blendTotalLabel(500, blend(10, 10)) == "500 mcg blend")
        #expect(firstPartShare(blend(10, 10)) == 0.5)
    }

    @Test func unevenBlendNamesItsParts() {
        #expect(doseLabel(400, blend(5, 15)) == "100 mcg CJC-1295 + 300 mcg Ipamorelin")
        #expect(firstPartShare(blend(5, 15)) == 0.25)
    }

    @Test func singlesAndUnweighedBlendsStayPlain() {
        #expect(doseLabel(250, Library.byId["bpc-157"]) == "250 mcg")
        #expect(blendTotalLabel(250, Library.byId["bpc-157"]) == nil)
        #expect(doseLabel(500, blend(nil, nil)) == "500 mcg")
        #expect(doseLabel(500, nil) == "500 mcg")
        // A blend dosed per part already says its parts' amount.
        #expect(doseLabel(250, blend(10, 10, dosing: .perComponent)) == "250 mcg")
    }

    @Test func remindersSayEach() {
        var d = AppData()
        let b = blend(10, 10)
        d.addCustomPeptide(b)
        _ = d.addProtocol(makeProtocol(peptideId: b.id, name: "CJC/Ipa nightly", startedAt: local(2026, 7, 1), doseMcg: 500,
                                       schedule: Schedule(kind: .daily, timeOfDay: "22:00")))
        var settings = DEFAULT_REMINDERS; settings.enabled = true; settings.showCompound = true
        let r = remindersFor(protocols: d.protocols, logs: [], peptides: d.allPeptides, settings: settings, nowMs: local(2026, 7, 6, 12))
        #expect(r.first?.body == "250 mcg each due.")
    }
}
