import Foundation
import Testing
@testable import BenchCore

@Suite struct LibraryTests {
    @Test func loadsEveryCompound() {
        #expect(Library.peptides.count == 50)
        #expect(Set(Library.peptides.map(\.id)).count == Library.peptides.count)
        #expect(Library.peptides.allSatisfy { $0.extra.isEmpty })
    }

    @Test func knownEnumValuesOnly() {
        for p in Library.peptides {
            #expect(p.category.isKnown, "\(p.id) category")
            #expect(p.routes.allSatisfy { $0.isKnown }, "\(p.id) routes")
            #expect(p.doseRanges.allSatisfy { $0.evidence.isKnown }, "\(p.id) evidence")
        }
    }

    @Test func labs() {
        #expect(Library.labMarkers.count == 16)
        #expect(Library.labCategoryLabels["growth"] == "Growth hormone axis")
        #expect(Library.marker("igf1")?.unit == "ng/mL")
    }

    @Test func peptideRoundTrips() throws {
        for p in Library.peptides {
            let back = try Peptide.lenient(from: p.lenientJSON())
            #expect(back == p)
        }
    }
}
