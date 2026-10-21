import Foundation

// Port of src/lib/calc/cost.ts. Cost is recorded per vial; everything else is derived.

/// A vial's share of its order's shipping. Derived, never stored, and unrounded.
public func shippingShare(_ vial: Vial, _ vials: [Vial], _ orders: [Order]) -> Double {
    guard let orderId = vial.orderId, !orderId.isEmpty,
          let order = orders.first(where: { $0.id == orderId }),
          let cost = order.shippingCost, cost > 0 else { return 0 }
    let siblings = vials.filter { $0.orderId == orderId }.count
    return siblings > 0 ? cost / Double(siblings) : 0
}

/// What a vial cost in total: its price, plus its share of getting it here.
public func landedCost(_ vial: Vial, _ vials: [Vial], _ orders: [Order]) -> Double? {
    guard let cost = vial.cost, cost > 0 else { return nil }
    return cost + shippingShare(vial, vials, orders)
}

public func costPerMg(_ vial: Vial) -> Double? {
    guard let cost = vial.cost, cost > 0, vial.strengthMg > 0 else { return nil }
    return cost / vial.strengthMg
}

public func costPerDose(_ vial: Vial, _ doseMcg: Double) -> Double? {
    guard let perMg = costPerMg(vial), doseMcg > 0 else { return nil }
    return perMg * (doseMcg / 1000)
}

public struct SpendSummary: Equatable, Sendable {
    public var totalSpend: Double
    public var currency: String?
    public var mixedCurrencies: Bool
    public var pricedVials: Int
    public var unpricedVials: Int
    public var costPerMg: Double?
    public var costPerDose: Double?
    public var costPerWeek: Double?
    public var costPerMonth: Double?
}

/// Spend for one peptide, blended across every priced vial. Mixed currencies give no rate.
public func spendFor(_ vials: [Vial], _ peptideId: String, _ doseMcg: Double, _ dosesPerWeek: Double,
                     fallbackCurrency: String = "INR") -> SpendSummary {
    let mine = vials.filter { $0.peptideId == peptideId }
    let priced = mine.filter { ($0.cost ?? 0) > 0 && $0.strengthMg > 0 }
    var currencies: [String] = []
    for v in priced {
        let c = v.currency ?? fallbackCurrency
        if !currencies.contains(c) { currencies.append(c) }
    }
    let mixed = currencies.count > 1
    let total = priced.reduce(0) { $0 + $1.cost! }
    let totalMg = priced.reduce(0) { $0 + $1.strengthMg }
    let perMg: Double? = mixed || totalMg <= 0 ? nil : total / totalMg
    let perDose: Double? = perMg.flatMap { doseMcg > 0 ? $0 * (doseMcg / 1000) : nil }
    let perWeek: Double? = perDose.flatMap { dosesPerWeek > 0 ? $0 * dosesPerWeek : nil }
    return SpendSummary(
        totalSpend: mixed ? 0 : total,
        currency: mixed ? nil : currencies.first,
        mixedCurrencies: mixed,
        pricedVials: priced.count,
        unpricedVials: mine.count - priced.count,
        costPerMg: perMg, costPerDose: perDose, costPerWeek: perWeek,
        // A month is 365/12 weeks' worth of days, not four weeks.
        costPerMonth: perWeek.map { ($0 * 365) / 12 / 7 }
    )
}

/// Value still sitting unused in a vial, at what it cost.
public func remainingValue(_ vial: Vial) -> Double? {
    guard let perMg = costPerMg(vial) else { return nil }
    return perMg * (max(0, vialCapacityMcg(vial) - (vial.drawnMcg ?? 0)) / 1000)
}

public struct CurrencyTotal: Equatable, Sendable {
    public var currency: String
    public var total: Double
    /// How many vials (or, for shipping, orders) the figure covers.
    public var vials: Int
    public init(currency: String, total: Double, vials: Int) {
        self.currency = currency; self.total = total; self.vials = vials
    }
}

/// Add money up, only ever within one currency. Largest first.
public func sumByCurrency(_ vials: [Vial], _ amountOf: (Vial) -> Double?, fallbackCurrency: String) -> [CurrencyTotal] {
    var rows: [CurrencyTotal] = []
    for vial in vials {
        guard let amount = amountOf(vial), amount > 0 else { continue }
        let currency = vial.currency ?? fallbackCurrency
        if let i = rows.firstIndex(where: { $0.currency == currency }) {
            rows[i].total += amount; rows[i].vials += 1
        } else {
            rows.append(CurrencyTotal(currency: currency, total: amount, vials: 1))
        }
    }
    return rows.stableSorted { $0.total > $1.total }
}

public struct SpendTotals: Equatable, Sendable {
    public var byCurrency: [CurrencyTotal]
    /// Postage, kept apart from the goods; `vials` counts orders here.
    public var shippingByCurrency: [CurrencyTotal]
    public var pricedVials: Int
    public var unpricedVials: Int
    public var mixed: Bool
}

/// Total spend across every priced vial, goods and shipping reported apart.
public func totalSpend(_ vials: [Vial], fallbackCurrency: String, orders: [Order] = []) -> SpendTotals {
    let byCurrency = sumByCurrency(vials, { $0.cost }, fallbackCurrency: fallbackCurrency)
    let priced = byCurrency.reduce(0) { $0 + $1.vials }
    let live = Set(vials.compactMap { $0.orderId }.filter { !$0.isEmpty })
    var shipping: [CurrencyTotal] = []
    for order in orders {
        guard live.contains(order.id), let cost = order.shippingCost, cost > 0 else { continue }
        let currency = order.currency ?? fallbackCurrency
        if let i = shipping.firstIndex(where: { $0.currency == currency }) {
            shipping[i].total += cost; shipping[i].vials += 1
        } else {
            shipping.append(CurrencyTotal(currency: currency, total: cost, vials: 1))
        }
    }
    return SpendTotals(byCurrency: byCurrency, shippingByCurrency: shipping.stableSorted { $0.total > $1.total },
                       pricedVials: priced, unpricedVials: vials.count - priced, mixed: byCurrency.count > 1)
}

/// Money in the reader's locale; a fraction only when there is one.
public func formatMoney(_ amount: Double?, _ currency: String = "INR", locale: Locale = .autoupdatingCurrent) -> String {
    guard let amount, amount.isFinite else { return "n/a" }
    let f = NumberFormatter()
    f.locale = locale
    f.numberStyle = .currency
    f.currencyCode = currency
    let whole = amount == amount.rounded()
    f.maximumFractionDigits = whole ? 0 : 2
    f.minimumFractionDigits = 0
    return f.string(from: NSNumber(value: amount)) ?? "\(jsToFixed(amount, 2)) \(currency)"
}

/// One vial's price from the price of the whole kit. Unrounded; nil when it cannot be divided.
public func costPerVialInKit(_ kitTotal: Double, _ vialCount: Double) -> Double? {
    guard kitTotal.isFinite, kitTotal >= 0 else { return nil }
    guard vialCount == vialCount.rounded(), vialCount >= 1 else { return nil }
    return kitTotal / vialCount
}

/// Money for a screen with room for one line: currencies joined, never added.
public func formatTotals(_ totals: [CurrencyTotal], limit: Int = 2) -> String {
    if totals.isEmpty {
        let zero = formatMoney(0, "USD")
        if let r = zero.range(of: "[\\d.,]+", options: .regularExpression) { return zero.replacingCharacters(in: r, with: "0") }
        return zero
    }
    let shown = totals.prefix(limit).map { formatMoney($0.total, $0.currency) }
    let rest = totals.count - shown.count
    return rest > 0 ? "\(shown.joined(separator: " + ")) + \(rest) more" : shown.joined(separator: " + ")
}
