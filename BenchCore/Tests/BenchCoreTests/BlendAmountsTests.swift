import Foundation
import Testing
@testable import BenchCore

@Suite struct BlendAmountsTests {
    @Test func wolverineGetsYourAmounts() throws {
        var d = AppData()
        let before = try #require(d.peptide("wolverine"))
        #expect(blendNeedsAmounts(before))
        #expect(blendParts(before, 1000) == nil)
        #expect(blendContents(before) == "BPC-157 + TB-500")

        d.setBlendAmounts("wolverine", mg: [5, 5])
        let after = try #require(d.peptide("wolverine"))
        #expect(!blendNeedsAmounts(after))
        #expect(after.vialSizesMg.first == 10)
        #expect(doseLabel(1000, after) == "500 mcg each")
        #expect(blendContents(after) == "BPC-157 5 · TB-500 5 mg")
        #expect(d.allPeptides.first { $0.id == "wolverine" }?.components?.map(\.mgPerVial) == [5, 5])

        // Round-trips through a backup, and clears.
        let back = try JSONDecoder().decode(AppData.self, from: JSONEncoder().encode(d))
        #expect(back.blendAmounts["wolverine"] == [5, 5])
        d.setBlendAmounts("wolverine", mg: nil)
        #expect(d.extra["iosBlendAmounts"] == nil && blendNeedsAmounts(d.peptide("wolverine")))
    }

    @Test func amountsThatDoNotFitAreIgnored() throws {
        var d = AppData()
        d.setBlendAmounts("wolverine", mg: [5])
        #expect(blendNeedsAmounts(d.peptide("wolverine")))
        d.setBlendAmounts("wolverine", mg: [5, 0])
        #expect(blendNeedsAmounts(d.peptide("wolverine")))
    }

    @Test func contentsOfAKnownBlend() throws {
        let klow = try #require(AppData().peptide("klow"))
        #expect(blendContents(klow) == "GHK-Cu 50 · BPC-157 10 · TB-500 10 · KPV 10 mg")
        #expect(blendContents(AppData().peptide("bpc-157")) == nil)
    }
}
