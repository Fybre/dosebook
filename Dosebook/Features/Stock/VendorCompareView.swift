import SwiftUI
import DosebookCore
import DosebookStore

/// Who is cheaper for a compound, on price per mg, and how a new quote compares.
struct VendorCompareView: View {
    @Environment(AppStore.self) private var store
    @State private var peptideId = ""
    @State private var includeShipping = false
    @State private var quoteVendor = ""
    @State private var quoteMg: Double?
    @State private var quotePrice: Double?
    @State private var quoteShipping: Double?

    private var data: AppData { store.data }
    private var compounds: [String] {
        var ids = comparableCompounds(data)
        if !peptideId.isEmpty && !ids.contains(peptideId) { ids.append(peptideId) }
        return ids
    }
    private func vendorName(_ v: String) -> String { v.isEmpty ? t("ios_vc_no_vendor") : v }
    private func name(_ id: String) -> String { data.peptide(id)?.name ?? id }

    var body: some View {
        let comparison = peptideId.isEmpty ? nil : compareVendors(data, peptideId: peptideId, shipping: includeShipping)
        Form {
            if compounds.isEmpty {
                Section { Text(t("ios_vc_empty")).foregroundStyle(.secondary) }
            } else {
                Section {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(compounds, id: \.self) { id in
                                Button { peptideId = id } label: {
                                    Text(name(id)).font(.subheadline)
                                        .padding(.horizontal, 12).padding(.vertical, 6)
                                        .background(peptideId == id ? Color.accentColor.opacity(0.18) : Color(.systemFill), in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                if let comparison { ranking(comparison) }
                if let comparison { quoteSection(comparison) }
            }
        }
        .navigationTitle(t("ios_vc_title"))
        .inlineTitle()
        .onAppear { if peptideId.isEmpty { peptideId = compounds.first ?? "" } }
    }

    // MARK: Ranking

    @ViewBuilder private func ranking(_ c: VendorComparison) -> some View {
        Section {
            ForEach(Array(c.ranked.enumerated()), id: \.element.id) { i, r in row(r, rank: i, best: c.ranked.first, currency: c.currency) }
            Toggle(t("ios_vc_include_shipping"), isOn: $includeShipping)
            if c.skipped > 0 { Text(t("ios_vc_skipped", ["n": .number(Double(c.skipped))])).font(.caption).foregroundStyle(.secondary) }
        } header: {
            Text(name(c.peptideId))
        } footer: {
            Text(t(c.ranked.count > 1 ? "ios_vc_sub_many" : "ios_vc_sub_one", ["n": .number(Double(c.ranked.count))]))
        }
        if !c.otherCurrency.isEmpty {
            Section {
                ForEach(c.otherCurrency) { r in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) { Text(vendorName(r.vendor)); detail(r) }
                        Spacer()
                        Text(formatMoney(r.perMg(shipping: includeShipping), r.currency) + t("ios_vc_per_mg")).monospacedDigit()
                    }
                }
            } header: { Text(t("ios_vc_other_currency")) } footer: { Text(t("ios_vc_other_currency_note")) }
        }
    }

    private func detail(_ r: VendorPrice) -> some View {
        Text("\(trim(r.strengthMg, 3)) mg · \(formatMoney(r.price, r.currency))" + (r.at.map { " · " + formatDate($0) } ?? ""))
            .font(.caption).foregroundStyle(.secondary)
    }

    private func row(_ r: VendorPrice, rank: Int, best: VendorPrice?, currency: String) -> some View {
        let mine = r.perMg(shipping: includeShipping)
        let top = best?.perMg(shipping: includeShipping) ?? mine
        return HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(vendorName(r.vendor)).fontWeight(.medium)
                    if r.isQuote { Pill(text: t("ios_vc_quote"), tone: .sky) }
                }
                detail(r)
                if !r.isQuote, let was = r.previousPerMg, abs(was - r.perMg) > 0.005 {
                    Text(t("ios_vc_was", ["price": .string(formatMoney(was, currency) + t("ios_vc_per_mg"))])).font(.caption2).foregroundStyle(.secondary)
                }
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(formatMoney(mine, currency) + t("ios_vc_per_mg")).fontWeight(.medium).monospacedDigit()
                if rank == 0 { Pill(text: t("ios_vc_cheapest"), tone: .leaf) }
                else if top > 0 { Pill(text: "+" + String(Int(((mine - top) / top * 100).rounded())) + "%", tone: .tangerine) }
            }
        }
        .contextMenu {
            if r.isQuote {
                Button(role: .destructive) { store.mutate { $0.settings.vendorQuotes.removeAll { $0.id == r.id } } } label: { Label(t("stock_delete"), systemImage: "trash") }
            }
        }
    }

    // MARK: Quote

    @ViewBuilder private func quoteSection(_ c: VendorComparison) -> some View {
        let check = quoteMg.flatMap { mg in quotePrice.flatMap { price in checkQuote(strengthMg: mg, price: price, shipping: quoteShipping, against: c, includeShipping: includeShipping) } }
        Section {
            TextField(t("ios_vc_vendor_optional"), text: $quoteVendor)
            OptionalNumberRow(label: t("ios_vc_vial_size"), value: $quoteMg, suffix: "mg")
            OptionalNumberRow(label: t("ios_vc_price"), value: $quotePrice, suffix: c.currency)
            OptionalNumberRow(label: t("ios_vc_shipping"), value: $quoteShipping, suffix: c.currency)
            if let check {
                VStack(alignment: .leading, spacing: 4) {
                    Text(summary(check, c)).font(.subheadline)
                    ForEach(Array(check.against.enumerated()), id: \.offset) { _, a in
                        Text(compareText(a)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !quoteVendor.trimmingCharacters(in: .whitespaces).isEmpty, let mg = quoteMg, let price = quotePrice {
                    Button(t("ios_vc_save")) { save(c, mg: mg, price: price) }
                }
            } else if quoteMg != nil || quotePrice != nil {
                Text(t("ios_vc_need_both")).font(.caption).foregroundStyle(.secondary)
            }
        } header: { Text(t("ios_vc_check")) } footer: { Text(t("ios_vc_check_hint")) }
    }

    private func summary(_ q: QuoteCheck, _ c: VendorComparison) -> String {
        quoteShipping ?? 0 > 0
            ? t("ios_vc_quote_ship", ["a": .string(formatMoney(q.perMg, c.currency)), "b": .string(formatMoney(q.perMgShipped, c.currency))])
            : t("ios_vc_quote_plain", ["a": .string(formatMoney(q.perMg, c.currency))])
    }

    private func compareText(_ a: (vendor: String, isQuote: Bool, difference: Double)) -> String {
        let pct = String(Int((abs(a.difference) * 100).rounded()))
        if Int((abs(a.difference) * 100).rounded()) == 0 { return t("ios_vc_same_as", ["vendor": .string(vendorName(a.vendor))]) }
        return t(a.difference > 0 ? "ios_vc_above" : "ios_vc_below", ["pct": .string(pct), "vendor": .string(vendorName(a.vendor))])
    }

    private func save(_ c: VendorComparison, mg: Double, price: Double) {
        let q = VendorQuote(id: UUID().uuidString, vendor: quoteVendor.trimmingCharacters(in: .whitespaces), peptideId: c.peptideId,
                            strengthMg: mg, price: price, shipping: quoteShipping, currency: c.currency, at: nowMillis())
        store.mutate { $0.settings.vendorQuotes.append(q) }
        quoteVendor = ""; quoteMg = nil; quotePrice = nil; quoteShipping = nil
    }
}
