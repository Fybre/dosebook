import Foundation
import Testing
@testable import DosebookCore

@Suite struct VendorCompareTests {
    func data() -> AppData {
        var d = AppData()
        d.settings.currency = "GBP"
        // Other Labs: 10 mg for 35 (3.50/mg). Acme: 5 mg for 20 then 5 mg for 22 (latest 4.40/mg, was 4.00).
        d.vials = [
            vial("a", peptideId: "bpc", strengthMg: 10, cost: 35, currency: "GBP", supplier: "Other Labs", acquiredAt: local(2026, 10, 12)),
            vial("b", peptideId: "bpc", strengthMg: 5, cost: 20, currency: "GBP", supplier: "Acme", acquiredAt: local(2026, 9, 1)),
            vial("c", peptideId: "bpc", strengthMg: 5, cost: 22, currency: "GBP", supplier: " acme ", acquiredAt: local(2026, 11, 3)),
            vial("d", peptideId: "bpc", strengthMg: 5, cost: nil, supplier: "Acme"),
            vial("e", peptideId: "bpc", strengthMg: 5, cost: 10, currency: "GBP"),
            vial("f", peptideId: "tb", strengthMg: 5, cost: 30, currency: "EUR", supplier: "Euro Shop", acquiredAt: local(2026, 10, 1)),
        ]
        return d
    }

    @Test func rankedOnPricePerMgWithLatestPerVendor() {
        let c = compareVendors(data(), peptideId: "bpc", shipping: false)
        // The vial with no supplier (10 for 5 mg, 2.00/mg) is its own unnamed line.
        #expect(c.ranked.map(\.vendor) == ["", "Other Labs", "Acme"] && c.ranked[0].isUnnamed)
        #expect(isClose(c.ranked[1].perMg, 3.5) && isClose(c.ranked[2].perMg, 4.4))
        #expect(c.ranked[2].previousPerMg == 4.0)
        #expect(c.skipped == 1 && c.currency == "GBP" && c.otherCurrency.isEmpty)
    }

    @Test func shippingIsSpreadOverTheOrder() {
        var d = data()
        d.orders = [Order(id: "o1", profileId: "me", shippingCost: 10, currency: "GBP", placedAt: local(2026, 11, 3))]
        d.vials[2].orderId = "o1"
        d.vials.append(vial("g", peptideId: "other", strengthMg: 5, orderId: "o1"))   // a second vial in the same order
        let c = compareVendors(d, peptideId: "bpc", shipping: true)
        let acme = c.ranked.first { $0.vendor == "Acme" }!
        #expect(acme.shippingShare == 5 && isClose(acme.perMgShipped, (22 + 5) / 5))
        #expect(c.ranked.map(\.vendor) == ["", "Other Labs", "Acme"])
    }

    @Test func otherCurrenciesAreNotRanked() {
        var d = data()
        d.vials[1].currency = "EUR"; d.vials[2].currency = "EUR"
        let c = compareVendors(d, peptideId: "bpc", shipping: false)
        #expect(c.currency == "GBP" && c.ranked.map(\.vendor) == ["", "Other Labs"] && c.otherCurrency.map(\.vendor) == ["Acme"])
    }

    @Test func quoteAgainstVendors() {
        let c = compareVendors(data(), peptideId: "bpc", shipping: false)
        let q = checkQuote(strengthMg: 10, price: 39, shipping: 6, against: c, includeShipping: false)!
        #expect(isClose(q.perMg, 3.9) && isClose(q.perMgShipped, 4.5))
        #expect(q.against.map(\.vendor) == ["", "Other Labs", "Acme"])
        #expect(isClose(q.against[1].difference, 0.1143, digits: 3) && isClose(q.against[2].difference, -0.1136, digits: 3))
        #expect(checkQuote(strengthMg: 0, price: 5, shipping: nil, against: c, includeShipping: false) == nil)
    }

    @Test func savedQuotesJoinTheRanking() {
        var d = data()
        d.settings.vendorQuotes = [VendorQuote(id: "q1", vendor: "New Vendor", peptideId: "bpc", strengthMg: 10, price: 30, currency: "GBP", at: local(2026, 11, 20))]
        #expect(d.settings.vendorQuotes.count == 1)
        let c = compareVendors(d, peptideId: "bpc", shipping: false)
        #expect(c.ranked.first { $0.vendor == "New Vendor" }?.isQuote == true)
        #expect(comparableCompounds(d).contains("bpc") && comparableCompounds(d).contains("tb"))
        d.settings.vendorQuotes = []
        #expect(d.settings.extra["iosVendorQuotes"] == nil)
    }
}

@Suite struct OilCompoundTests {
    @Test func oilKeepsStrengthAndBottleThroughEditing() {
        var draft = CustomDraft(name: "Primo", preparation: .solution)
        draft.strengthMgPerMl = 100; draft.bottleMl = 10
        let p = draftToPeptide(draft)
        #expect(p.concentrationsMgPerMl == [100])
        #expect(p.vialSizesMg == [1000])
        let back = peptideToDraft(p)
        #expect(back.strengthMgPerMl == 100 && back.bottleMl == 10)
    }
    @Test func powderIgnoresOilFields() {
        var draft = CustomDraft(name: "Powder one", preparation: .powder)
        draft.strengthMgPerMl = 100; draft.bottleMl = 10
        #expect(draftToPeptide(draft).concentrationsMgPerMl == nil)
    }
}
