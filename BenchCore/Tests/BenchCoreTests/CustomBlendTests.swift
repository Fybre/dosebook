import Foundation
import Testing
@testable import BenchCore

/// CJC-1295 without DAC and ipamorelin, 10 mg of each in one vial.
private func cjcIpa(_ dosing: BlendDosing = .split, cjc: Double? = 10, ipa: Double? = 10) -> CustomDraft {
    var d = CustomDraft(name: "CJC/Ipa", category: .blend, doseLowMcg: 200, doseHighMcg: 300)
    d.components = [BlendComponent(peptideId: "cjc-1295-no-dac", name: "CJC-1295 without DAC", mgPerVial: cjc),
                    BlendComponent(peptideId: "ipamorelin", name: "Ipamorelin", mgPerVial: ipa)]
    d.blendDosing = dosing
    return d
}

@Suite struct CustomBlendTests {
    @Test func buildsABlend() {
        let p = draftToPeptide(cjcIpa())
        #expect(isBlend(p))
        #expect(p.components?.map(\.peptideId) == ["cjc-1295-no-dac", "ipamorelin"])
        #expect(p.vialSizesMg == [20])
        #expect(p.blendDosing == nil)
        #expect(p.summary == "A blend you added yourself: CJC-1295 without DAC 10 mg, Ipamorelin 10 mg.")
        #expect(p.halfLifeNote?.contains("own curve") == true)
    }

    @Test func splitsADoseByMass() {
        let parts = decomposeDose(draftToPeptide(cjcIpa()), 200, resolve: { Library.byId[$0] })
        #expect(parts.map(\.mcg) == [100, 100])
        let uneven = decomposeDose(draftToPeptide(cjcIpa(cjc: 5, ipa: 15)), 200, resolve: { Library.byId[$0] })
        #expect(uneven.map(\.mcg) == [50, 150])
    }

    @Test func perComponentDosing() {
        let p = draftToPeptide(cjcIpa(.perComponent))
        #expect(p.blendDosing == .perComponent)
        #expect(decomposeDose(p, 100, resolve: { Library.byId[$0] }).map(\.mcg) == [100, 100])
    }

    @Test func aTypedVialSizeWins() {
        var d = cjcIpa()
        d.vialSizeMg = 22
        #expect(draftToPeptide(d).vialSizesMg == [22])
    }

    @Test func validation() {
        let all = Library.peptides
        #expect(validateDraft(cjcIpa(), existing: all).isEmpty)
        var one = cjcIpa(); one.components.removeLast()
        #expect(validateDraft(one, existing: all).contains { $0.field == .components })
        var unnamed = cjcIpa(); unnamed.components[1].name = " "
        #expect(validateDraft(unnamed, existing: all).contains { $0.field == .components })
        #expect(validateDraft(cjcIpa(ipa: nil), existing: all).contains { $0.field == .components })
        // Per-part dosing does not need the masses.
        #expect(validateDraft(cjcIpa(.perComponent, cjc: nil, ipa: nil), existing: all).isEmpty)
        var loop = cjcIpa(); loop.components[0].peptideId = slugifyCompound("CJC/Ipa")
        #expect(validateDraft(loop, existing: all).contains { $0.field == .components })
    }

    @Test func roundTrips() {
        let back = peptideToDraft(draftToPeptide(cjcIpa(.perComponent)))
        #expect(back.components == cjcIpa().components)
        #expect(back.blendDosing == .perComponent)
        #expect(back.summary == nil)
        #expect(draftToPeptide(back).summary.hasPrefix("A blend you added yourself"))
    }

    @Test func aDerivedVialSizeFollowsTheParts() {
        var back = peptideToDraft(draftToPeptide(cjcIpa()))
        #expect(back.vialSizeMg == nil)
        back.components[0].mgPerVial = 5; back.components[1].mgPerVial = 5
        #expect(draftToPeptide(back).vialSizesMg == [10])
        var typed = cjcIpa(); typed.vialSizeMg = 22
        #expect(peptideToDraft(draftToPeptide(typed)).vialSizeMg == 22)
    }

    @Test func singleCompoundsAreUnchanged() {
        let p = draftToPeptide(CustomDraft(name: "Thing", doseLowMcg: 100))
        #expect(!isBlend(p) && p.components == nil && p.vialSizesMg.isEmpty)
    }
}
