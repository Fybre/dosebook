import Foundation
import Testing
@testable import BenchCore

@Suite struct VialLabelTests {
    let lib = Library.peptides

    @Test func aTypicalLabel() {
        let l = parseVialLabel(["RETATRUTIDE", "10mg", "For research use only", "Lot: RT2406-B", "Exp: 05/2027"], peptides: lib)
        #expect(l.peptideId == "retatrutide")
        #expect(l.strengthMg == 10)
        #expect(l.lot == "RT2406-B")
        #expect(l.expiresAt == local(2027, 5, 31))
    }

    @Test func nameAndStrengthOnOneLine() {
        let l = parseVialLabel(["BPC-157 5 mg", "Batch No. 2291"], peptides: lib)
        #expect(l.peptideId == "bpc-157" && l.strengthMg == 5 && l.lot == "2291")
    }

    @Test func micrograms() {
        #expect(parseVialLabel(["Ipamorelin", "5000 mcg"], peptides: lib).strengthMg == 5)
    }

    @Test func anUncertainNameOffersChoices() {
        let l = parseVialLabel(["CJC-1295", "2mg"], peptides: lib)
        #expect(l.peptideId == nil)
        #expect(Set(l.candidates) == ["cjc-1295-dac", "cjc-1295-no-dac"])
        #expect(l.strengthMg == 2)
    }

    @Test func expiryForms() {
        #expect(labelExpiry("EXP 2027-03") == local(2027, 3, 31))
        #expect(labelExpiry("exp. 11/26") == local(2026, 11, 30))
        #expect(labelExpiry("Use by 31/05/2027") == local(2027, 5, 31))
        #expect(labelExpiry("Expiry date: 2028-02-15") == local(2028, 2, 29))
        // Day and month could swap, so nothing is guessed.
        #expect(labelExpiry("EXP 05/06/2027") == nil)
        #expect(labelExpiry("Manufactured 2025") == nil)
    }

    @Test func nothingRecognisable() {
        let l = parseVialLabel(["For research use only", "Store at 2-8°C"], peptides: lib)
        #expect(l.peptideId == nil && l.candidates.isEmpty && l.strengthMg == nil && l.lot == nil && l.expiresAt == nil)
    }
}
