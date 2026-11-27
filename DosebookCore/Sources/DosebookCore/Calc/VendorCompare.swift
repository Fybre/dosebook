import Foundation

// Who is cheaper. Every priced vial is a price for its supplier (or for "no supplier"); the
// latest per supplier and compound is ranked on price per mg, so a 5 mg and a 10 mg vial
// compare fairly. Saved quotes sit alongside as prices not yet paid. Money in more than
// one currency is never added up or converted: the ranking is in one currency, and any
// other is listed beside it unranked.

/// A price someone quoted, kept to compare against. Stored in the settings' `extra`.
public struct VendorQuote: Equatable, Sendable, Identifiable {
    public var id: String
    public var vendor: String
    public var peptideId: String
    public var strengthMg: Double
    public var price: Double
    public var shipping: Double?
    public var currency: String
    public var at: Millis
    public init(id: String, vendor: String, peptideId: String, strengthMg: Double, price: Double,
                shipping: Double? = nil, currency: String, at: Millis) {
        self.id = id; self.vendor = vendor; self.peptideId = peptideId; self.strengthMg = strengthMg
        self.price = price; self.shipping = shipping; self.currency = currency; self.at = at
    }
}

public extension Settings {
    var vendorQuotes: [VendorQuote] {
        get {
            (extra["iosVendorQuotes"]?.arrayValue ?? []).compactMap { v in
                guard let o = v.objectValue, let id = o["id"]?.stringValue, let vendor = o["vendor"]?.stringValue,
                      let pid = o["peptideId"]?.stringValue, let mg = o["strengthMg"]?.numberValue,
                      let price = o["price"]?.numberValue, let cur = o["currency"]?.stringValue,
                      let at = o["at"]?.numberValue else { return nil }
                return VendorQuote(id: id, vendor: vendor, peptideId: pid, strengthMg: mg, price: price,
                                   shipping: o["shipping"]?.numberValue, currency: cur, at: at)
            }
        }
        set {
            if newValue.isEmpty { extra.removeValue(forKey: "iosVendorQuotes"); return }
            extra["iosVendorQuotes"] = .array(newValue.map { q in
                var o: [String: JSONValue] = ["id": .string(q.id), "vendor": .string(q.vendor), "peptideId": .string(q.peptideId),
                                              "strengthMg": .number(q.strengthMg), "price": .number(q.price),
                                              "currency": .string(q.currency), "at": .number(q.at)]
                if let s = q.shipping { o["shipping"] = .number(s) }
                return .object(o)
            })
        }
    }
}

public struct VendorPrice: Equatable, Sendable, Identifiable {
    public var id: String
    public var vendor: String
    public var strengthMg: Double
    public var price: Double
    /// This vial's share of its order's shipping; 0 when unknown or in another currency.
    public var shippingShare: Double
    public var currency: String
    public var at: Millis?
    public var isQuote: Bool
    /// The price per mg the time before, from the same supplier, in the same currency.
    public var previousPerMg: Double?
    /// A purchase with no supplier recorded, grouped as one line; the app words it.
    public var isUnnamed: Bool { vendor.isEmpty }
    public var perMg: Double { price / strengthMg }
    public var perMgShipped: Double { (price + shippingShare) / strengthMg }
    public func perMg(shipping: Bool) -> Double { shipping ? perMgShipped : perMg }
}

public struct VendorComparison: Equatable, Sendable {
    public var peptideId: String
    public var currency: String
    /// Cheapest first, in `currency`.
    public var ranked: [VendorPrice]
    /// Suppliers priced in another currency; not ranked.
    public var otherCurrency: [VendorPrice]
    /// Vials of this compound with no price, so left out. Ones with no supplier are kept, as one unnamed line.
    public var skipped: Int
}

private func vendorKey(_ s: String) -> String { s.trimmingCharacters(in: .whitespaces).lowercased() }

/// Compounds with at least one priced vial, or a saved quote.
public func comparableCompounds(_ data: AppData) -> [String] {
    var out: [String] = []
    for v in data.mine.vials where v.cost != nil && v.strengthMg > 0 {
        if !out.contains(v.peptideId) { out.append(v.peptideId) }
    }
    for q in data.settings.vendorQuotes where !out.contains(q.peptideId) { out.append(q.peptideId) }
    return out
}

public func compareVendors(_ data: AppData, peptideId: String, shipping: Bool, preferredCurrency: String? = nil) -> VendorComparison {
    let vials = data.mine.vials.filter { $0.peptideId == peptideId }
    // Each order's shipping, spread over every vial that came in it.
    var perOrder: [String: Int] = [:]
    for v in data.mine.vials { if let o = v.orderId { perOrder[o, default: 0] += 1 } }
    let orders = Dictionary(data.mine.orders.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    var skipped = 0
    var purchases: [String: [VendorPrice]] = [:]
    var names: [String: String] = [:]
    for v in vials {
        let name = (v.supplier ?? "").trimmingCharacters(in: .whitespaces)
        guard let cost = v.cost, cost.isFinite, cost >= 0, v.strengthMg > 0 else { skipped += 1; continue }
        let cur = v.currency ?? data.settings.currency
        var share = 0.0
        if let oid = v.orderId, let o = orders[oid], let s = o.shippingCost, s > 0, (o.currency ?? cur) == cur {
            share = s / Double(max(1, perOrder[oid] ?? 1))
        }
        let key = vendorKey(name) + "|" + cur
        names[key] = names[key] ?? name
        purchases[key, default: []].append(VendorPrice(id: v.id, vendor: name, strengthMg: v.strengthMg, price: cost, shippingShare: share,
                                                       currency: cur, at: v.acquiredAt, isQuote: false, previousPerMg: nil))
    }
    for q in data.settings.vendorQuotes where q.peptideId == peptideId && q.strengthMg > 0 {
        let key = vendorKey(q.vendor) + "|" + q.currency
        names[key] = names[key] ?? q.vendor
        purchases[key, default: []].append(VendorPrice(id: q.id, vendor: q.vendor, strengthMg: q.strengthMg, price: q.price,
                                                       shippingShare: q.shipping ?? 0, currency: q.currency, at: q.at, isQuote: true, previousPerMg: nil))
    }
    // Latest per supplier and currency; saved quotes are their own lines, not that supplier's last purchase.
    var latest: [VendorPrice] = []
    for (key, var list) in purchases {
        if let shown = names[key] { for i in list.indices { list[i].vendor = shown } }
        let bought = list.filter { !$0.isQuote }.sorted { ($0.at ?? 0, $0.id) > ($1.at ?? 0, $1.id) }
        if var last = bought.first {
            last.previousPerMg = bought.dropFirst().first?.perMg
            latest.append(last)
        }
        latest.append(contentsOf: list.filter(\.isQuote))
    }
    let counts = Dictionary(grouping: latest, by: \.currency).mapValues(\.count)
    let currency = preferredCurrency.flatMap { c in counts[c] != nil ? c : nil }
        ?? (counts[data.settings.currency] != nil ? data.settings.currency : counts.max { $0.value < $1.value }?.key)
        ?? data.settings.currency
    let ranked = latest.filter { $0.currency == currency }.sorted {
        let (a, b) = ($0.perMg(shipping: shipping), $1.perMg(shipping: shipping))
        return a != b ? a < b : $0.vendor.localizedCaseInsensitiveCompare($1.vendor) == .orderedAscending
    }
    let other = latest.filter { $0.currency != currency }.sorted { $0.vendor.localizedCaseInsensitiveCompare($1.vendor) == .orderedAscending }
    return VendorComparison(peptideId: peptideId, currency: currency, ranked: ranked, otherCurrency: other, skipped: skipped)
}

public struct QuoteCheck: Equatable, Sendable {
    public var perMg: Double
    public var perMgShipped: Double
    /// Each ranked line against this quote: the quote's difference as a fraction of that line's price (+0.11 is 11% dearer).
    public var against: [(vendor: String, isQuote: Bool, difference: Double)]
    public static func == (a: QuoteCheck, b: QuoteCheck) -> Bool {
        a.perMg == b.perMg && a.perMgShipped == b.perMgShipped
            && a.against.map(\.vendor) == b.against.map(\.vendor) && a.against.map(\.difference) == b.against.map(\.difference)
    }
}

/// Nil when the size or price is not a usable figure.
public func checkQuote(strengthMg: Double, price: Double, shipping: Double?, against comparison: VendorComparison, includeShipping: Bool) -> QuoteCheck? {
    guard strengthMg.isFinite, strengthMg > 0, price.isFinite, price >= 0 else { return nil }
    let ship = max(0, shipping ?? 0)
    let perMg = price / strengthMg, shipped = (price + ship) / strengthMg
    let mine = includeShipping ? shipped : perMg
    let lines = comparison.ranked.compactMap { r -> (vendor: String, isQuote: Bool, difference: Double)? in
        let theirs = r.perMg(shipping: includeShipping)
        return theirs > 0 ? (r.vendor, r.isQuote, (mine - theirs) / theirs) : nil
    }
    return QuoteCheck(perMg: perMg, perMgShipped: shipped, against: lines)
}
