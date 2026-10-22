import SwiftUI
import BenchCore
import BenchStore

/// What is in the fridge, what is on its way, and the water beside it.
struct StockView: View {
    @Environment(AppStore.self) private var store
    @State private var sheet: StockSheet?
    @State private var deleting: Vial?
    @State private var now = nowMillis()

    enum StockSheet: Identifiable {
        case add, scan, left(Vial), reconstitute(Vial), topUp(Vial), transfer(Vial), tabletSize([Vial]), addBottle, useBottle(DiluentBottle)
        var id: String {
            switch self {
            case .add: "add"
            case .scan: "scan"
            case .left(let v): "l" + v.id
            case .reconstitute(let v): "r" + v.id
            case .topUp(let v): "t" + v.id
            case .transfer(let v): "s" + v.id
            case .tabletSize(let vs): "z" + vs[0].id
            case .addBottle: "bottle"
            case .useBottle(let b): "u" + b.id
            }
        }
    }

    var body: some View {
        let data = store.data
        let mine = data.mine
        let vials = mine.vials
        let settings = data.settings
        let currency = settings.currency
        // Paid for and not here: kept out of every stock figure, counted in Spent.
        let onOrder = vials.filter { $0.state == .onOrder }
        let sealed = vials.filter { $0.state == .sealed }
        let open = vials.filter { $0.state == .reconstituted }
        let done = vials.filter { $0.state == .finished || $0.state == .discarded }
        let totalMg = (sealed + open).reduce(0) { $0 + vialRemainingMcg($1) } / 1000
        let spend = totalSpend(vials, fallbackCurrency: currency, orders: mine.orders)
        let unused = sumByCurrency(sealed + open, remainingValue, fallbackCurrency: currency)
        let ctx = RowContext(data: data, now: now)

        ScrollViewReader { proxy in
        List {
            if !vials.isEmpty {
                Section {
                    HStack(alignment: .top) {
                        StatView(label: t("stock_sealed"), value: String(sealed.count))
                        StatView(label: t("stock_open"), value: String(open.count), tone: .tangerine)
                        StatView(label: t("stock_remaining"), value: "\(trim(totalMg, 2)) mg", tone: .sky)
                    }
                    if spend.pricedVials > 0 {
                        HStack(alignment: .top) {
                            StatView(label: t("stock_spent"), value: formatTotals(spend.byCurrency), tone: .grape)
                            StatView(label: t("stock_still_in_vials"), value: formatTotals(unused), tone: .mint)
                            if !spend.shippingByCurrency.isEmpty {
                                StatView(label: t("stock_shipping"), value: formatTotals(spend.shippingByCurrency), tone: .sky)
                            }
                        }
                        Text(t("stock_priced_vials", ["n": .number(Double(spend.pricedVials))])
                             + (spend.unpricedVials > 0 ? t("stock_without_price", ["n": .number(Double(spend.unpricedVials))]) : "")
                             + "." + (spend.mixed ? t("stock_mixed_currency") : ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                } footer: { Text(t("stock_remaining_hint")) }
            }

            if settings.waterAtBottom != true { waterShelf(mine, settings) }

            if vials.isEmpty {
                ContentUnavailableView {
                    Label(t("stock_no_vials"), systemImage: "testtube.2")
                } description: { Text(t("stock_empty_desc")) } actions: {
                    Button(t("stock_add_vial")) { sheet = .add }.buttonStyle(.borderedProminent)
                }
            }

            if !onOrder.isEmpty {
                Section(t("stock_on_order")) {
                    ForEach(groupOnOrder(vials)) { g in
                        VialRow(vial: g.vials[0], group: g, ctx: ctx, actions: [
                            .init(t("stock_it_arrived"), "shippingbox", prominent: true) {
                                // The whole delivery: arriving happened once. Dated from today.
                                let at = nowMillis()
                                store.mutate { d in for v in g.vials { d.updateVial(v.id) { $0.state = .sealed; $0.acquiredAt = at } } }
                            },
                        ], onDelete: { deleting = g.vials[0] })
                    }
                }
            }

            if !open.isEmpty {
                Section {
                    ForEach(open) { v in
                        var actions: [VialAction] = []
                        if !isPack(v) { actions.append(.init(t("ios_left_title"), "slider.horizontal.3") { sheet = .left(v) }) }
                        if !isPack(v) { actions.append(.init(t("stock_add_diluent"), "drop") { sheet = .topUp(v) }) }
                        if !isSpray(v) && !isPack(v) { actions.append(.init(t("stock_to_spray"), "humidifier") { sheet = .transfer(v) }) }
                        if isPack(v) || data.peptide(v.peptideId)?.preparation == .tablet {
                            actions.append(.init(t("stock_set_tablet_size"), nil) { sheet = .tabletSize([v]) })
                        }
                        actions.append(.init(t("stock_mark_empty"), nil) { store.mutate { $0.updateVial(v.id) { $0.state = .finished } } })
                        return VialRow(vial: v, group: nil, ctx: ctx, actions: actions, onDelete: { deleting = v })
                    }
                } header: { Text(t("stock_open")).id("open") }
            }

            if !sealed.isEmpty {
                // Off unless asked for, so nobody's shelf rearranges itself after an update.
                let rows: [(Vial, VialGroup?)] = settings.groupIdenticalVials == true
                    ? groupSealedVials(sealed).map { ($0.vials[0], $0) } : sealed.map { ($0, nil) }
                Section {
                    ForEach(rows, id: \.0.id) { v, g in
                        var actions: [VialAction] = []
                        if isPack(v) {
                            actions.append(.init(t("stock_open_pack"), nil, prominent: true) { store.mutate { $0.updateVial(v.id) { $0 = openPack($0, nowMillis()) } } })
                        } else {
                            actions.append(.init((g?.count ?? 1) > 1 ? t("stock_reconstitute_one") : t("stock_reconstitute"), "drop.fill") { sheet = .reconstitute(v) })
                        }
                        if isPack(v) || data.peptide(v.peptideId)?.preparation == .tablet {
                            actions.append(.init(t("stock_set_tablet_size"), nil) { sheet = .tabletSize(g?.vials ?? [v]) })
                        }
                        return VialRow(vial: v, group: g, ctx: ctx, actions: actions, onDelete: { deleting = v })
                    }
                } header: { Text(t("stock_sealed")).id("sealed") }
            }

            if !done.isEmpty {
                Section(t("stock_finished")) {
                    ForEach(done) { v in
                        Text("\(data.peptide(v.peptideId)?.name ?? v.peptideId) · \(jsNumberString(v.strengthMg)) mg")
                            .font(.subheadline).foregroundStyle(.secondary)
                            .swipeActions { Button(t("stock_delete"), role: .destructive) { store.mutate { $0.removeVial(v.id) } } }
                    }
                }
            }

            if settings.waterAtBottom == true { waterShelf(mine, settings) }

            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label(t("stock_28_day_note"), systemImage: "info.circle").font(.subheadline.weight(.semibold))
                    Text(t("stock_bud_explainer")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        }
        .debugAnchor(proxy)
        }
        .navigationTitle(t("stock_title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Menu {
                    Button { sheet = .add } label: { Label(t("stock_add_vial"), systemImage: "square.and.pencil") }
                    Button { sheet = .scan } label: { Label(t("ios_scan_title"), systemImage: "camera.viewfinder") }
                } label: { Label(t("stock_add_vial"), systemImage: "plus") }
            }
        }
        .onAppear { now = nowMillis() }
        #if DEBUG
        .onAppear {
            let args = ProcessInfo.processInfo.arguments
            if sheet == nil, args.contains("-stockScan") { sheet = .scan }
            // `-vialLeft`: the amount-left form for the first open vial.
            if sheet == nil, args.contains("-vialLeft"), let v = store.data.mine.vials.first(where: { $0.state == .reconstituted && !isPack($0) }) { sheet = .left(v) }
        }
        #endif
        .sheet(item: $sheet) { s in
            NavigationStack {
                switch s {
                case .add: AddVialForm()
                case .scan: AddVialForm(scanFirst: true)
                case .left(let v): VialLeftForm(vial: v)
                case .reconstitute(let v): ReconstituteForm(vial: v)
                case .topUp(let v): TopUpForm(vial: v)
                case .transfer(let v): TransferToSprayForm(vial: v)
                case .tabletSize(let vs): TabletSizeForm(vials: vs)
                case .addBottle: AddBottleForm()
                case .useBottle(let b): UseElsewhereForm(bottle: b)
                }
            }
        }
        // Never the whole group: one tap, one vial, the oldest of them.
        .confirmationDialog(t("stock_delete_vial"), isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            Button(t("stock_delete"), role: .destructive) {
                if let v = deleting { store.mutate { $0.removeVial(v.id) } }
                deleting = nil
            }
        } message: { Text(t("stock_delete_tip")) }
    }

    /// Water, on its own shelf: none of the vial arithmetic applies to it.
    @ViewBuilder private func waterShelf(_ mine: AppData, _ settings: Settings) -> some View {
        let live = mine.diluents.filter { $0.state != .finished && $0.state != .discarded }
        let rows = shelfRows(live, now, grouped: settings.groupIdenticalVials == true)
        let stock = diluentStock(mine.diluents, .bacteriostatic, now)
        Section {
            if live.isEmpty {
                Text(t("stock_water_section_desc")).font(.footnote).foregroundStyle(.secondary)
            }
            ForEach(rows) { row in
                let b = row.bottle
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 8) {
                        Text(diluentName(b.kind)).font(.subheadline)
                        Pill(text: bottleStateName(b.state), tone: b.state == .sealed ? .neutral : .tangerine)
                        if !bottleUsable(b, now) { Pill(text: t("stock_bottle_unusable"), tone: .rose) }
                        Spacer()
                        // A group of sealed bottles counts rather than measures.
                        Text(row.count > 1 ? t("stock_bottles_each", ["n": .number(Double(row.count)), "ml": .string(trim(b.volumeMl, 1))])
                             : t("stock_bottle_left", ["left": .string(trim(bottleRemainingMl(b), 1)), "total": .string(trim(b.volumeMl, 1))]))
                            .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                    }
                    FlowLayout(spacing: 6) {
                        if b.state == .sealed { Button(t("stock_open_bottle")) { store.mutate { $0.openDiluent(b.id) } } }
                        if b.state != .discarded && bottleRemainingMl(b) > 0 { Button(t("stock_used_elsewhere")) { sheet = .useBottle(b) } }
                        if b.state != .discarded { Button(t("stock_discard")) { store.mutate { $0.updateDiluent(b.id) { $0.state = .discarded } } } }
                    }
                    .buttonStyle(.bordered).controlSize(.small)
                }
                .swipeActions { Button(t("stock_remove_bottle"), role: .destructive) { store.mutate { $0.removeDiluent(b.id) } } }
            }
            Button { sheet = .addBottle } label: { Label(t("stock_add_bottle"), systemImage: "plus") }
        } header: {
            Text(t("stock_water_section"))
        } footer: {
            if stock.remainingMl > 0 {
                Text(t("stock_water_across", ["ml": .string(trim(stock.remainingMl, 1)), "n": .number(Double(stock.bottles))]))
            }
        }
    }
}

/// Everything a row needs to answer for its compound, computed once per screen.
struct RowContext {
    var data: AppData
    var now: Millis
    var scale: SyringeScale { (syringeById(data.settings.defaultSyringeId ?? "") ?? SYRINGES[2]).scale }
    private var active: [DoseProtocol] { data.mine.protocols.filter(\.active) }

    func protocolFor(_ peptideId: String) -> DoseProtocol? { active.first { $0.peptideId == peptideId } }
    func doseFor(_ peptideId: String) -> Double { protocolFor(peptideId).map { scheduledDoseMcg($0, now) } ?? 0 }
    func timesPerDay(_ peptideId: String) -> Int {
        guard let p = protocolFor(peptideId) else { return 1 }
        return dosesPerDoseDay(phaseSpanAt(p, now)?.schedule ?? p.schedule)
    }
    /// When the whole shelf of each compound runs out, spent against its plan. Once per
    /// compound rather than per row: the walk loops over a year of scheduled doses.
    let outlooks: [String: SupplyOutlook]

    init(data: AppData, now: Millis) {
        self.data = data
        self.now = now
        var out: [String: SupplyOutlook] = [:]
        for id in Set(data.mine.vials.map(\.peptideId)) {
            guard let p = data.mine.protocols.first(where: { $0.active && $0.peptideId == id }) else { out[id] = .unknown; continue }
            let container = containerForDose(data.peptide(id)?.preparation, p.route)
            out[id] = supplyOutlook(stockFor(data.mine.vials, id, scheduledDoseMcg(p, now), now, container), p, now)
        }
        outlooks = out
    }

    func outlook(_ peptideId: String) -> SupplyOutlook { outlooks[peptideId] ?? .unknown }
    func shipping(_ v: Vial) -> Double { shippingShare(v, data.mine.vials, data.mine.orders) }
}

struct VialAction {
    var title: String
    var icon: String?
    var prominent = false
    var run: () -> Void
    init(_ title: String, _ icon: String?, prominent: Bool = false, run: @escaping () -> Void) {
        self.title = title; self.icon = icon; self.prominent = prominent; self.run = run
    }
}

private struct VialRow: View {
    var vial: Vial
    /// Present when the row stands for several identical vials; `vial` is the oldest.
    var group: VialGroup?
    var ctx: RowContext
    var actions: [VialAction]
    var onDelete: () -> Void

    var body: some View {
        let v = vial
        let data = ctx.data
        let st = vialStatus(v, nowMs: ctx.now)
        let budSoon = st.daysToBud.map { $0 < data.settings.budWarningDays } ?? false
        let spray = isSpray(v), pack = isPack(v)
        let dose = ctx.doseFor(v.peptideId)
        let marks = !spray && !pack && dose > 0 ? marksFromVial(v, dose, ctx.scale) : nil
        let many = (group?.count ?? 1) > 1
        let remainingMcg = group?.remainingMcg ?? st.remainingMcg
        let rowCost = group != nil ? group!.cost : v.cost
        let rowSupplier = group != nil ? group!.supplier : v.supplier
        let rowCurrency = (group != nil ? group!.currency : v.currency) ?? data.settings.currency
        let rowShipping = group.map { $0.vials.reduce(0) { $0 + ctx.shipping($1) } } ?? ctx.shipping(v)
        let strengthTotal = group.map { $0.strengthMg * Double($0.count) } ?? v.strengthMg
        let expiresAt = group != nil ? group!.expiresAt : v.expiresAt

        HStack(alignment: .top, spacing: 12) {
            Group {
                if pack { PackGlyph(fraction: st.fractionRemaining, state: v.state) }
                else { VialGlyph(fraction: st.fractionRemaining, state: v.state) }
            }
            VStack(alignment: .leading, spacing: 5) {
                FlowLayout(spacing: 6) {
                    Text(data.peptide(v.peptideId)?.name ?? v.peptideId).font(.subheadline.weight(.medium))
                    Text("\(jsNumberString(v.strengthMg)) mg").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                    if spray { Pill(text: t("stock_nasal_spray_badge"), tone: .grape) }
                    if let rowSupplier { Pill(text: rowSupplier) }
                    if many, let g = group { Pill(text: pack ? t("count_packs", ["n": .number(Double(g.count))]) : t("count_vials", ["n": .number(Double(g.count))]), tone: .sky) }
                    if st.expired { Pill(text: t("stock_past_date"), tone: .rose) }
                    else if budSoon { Pill(text: t("stock_use_soon"), tone: .tangerine) }
                }
                details(v, st, spray: spray, pack: pack, marks: marks, dose: dose, many: many, strengthTotal: strengthTotal, expiresAt: expiresAt, budSoon: budSoon)
                    .font(.caption).foregroundStyle(.secondary)

                if dose > 0 && v.state != .onOrder {
                    let n = (remainingMcg / dose).rounded(.down)
                    let times = ctx.timesPerDay(v.peptideId)
                    (Text(jsNumberString(n)).foregroundColor(Tone.tangerine.color).monospacedDigit()
                     + Text(" " + t("stock_more_doses_suffix", ["n": .number(n), "per": .string(formatDose(dose)), "where": .string(many ? t("stock_across_these_vials") : t("stock_in_this_vial"))])
                            + (times > 1 ? " · " + t("stock_times_per_day", ["n": .number(Double(times))]) : "")
                            + " · " + t("stock_left_suffix", ["amount": .string(formatDose(remainingMcg))])).foregroundColor(.secondary))
                        .font(.caption)
                }
                switch ctx.outlook(v.peptideId) {
                case .runsOut(let at): Text(t("stock_runs_out_line", ["date": .string(formatDate(at, nowMs: ctx.now))])).font(.caption2).foregroundStyle(.tertiary)
                case .beyondHorizon: Text(t("stock_over_a_year")).font(.caption2).foregroundStyle(.tertiary)
                case .unknown: EmptyView()
                }
                if let rowCost {
                    let parts = [
                        formatMoney(rowCost, rowCurrency) + (many ? t("stock_in_total_suffix") : "")
                            + (rowShipping > 0 ? t("stock_shipping_suffix", ["money": .string(formatMoney(rowShipping, rowCurrency))]) : "")
                            + (dose > 0 ? t("stock_a_dose_suffix", ["money": .string(formatMoney((rowCost + rowShipping) / strengthTotal * (dose / 1000), rowCurrency))]) : ""),
                        many && (group?.unpricedCount ?? 0) > 0 ? t("stock_unpriced_count", ["n": .number(Double(group!.unpricedCount))]) : nil,
                    ].compactMap { $0 }
                    Text(parts.joined(separator: " · ")).font(.caption2).foregroundStyle(.tertiary)
                }
                FlowLayout(spacing: 6) {
                    ForEach(actions.indices, id: \.self) { i in
                        let a = actions[i]
                        if a.prominent {
                            Button(action: a.run) { actionLabel(a) }.buttonStyle(.borderedProminent)
                        } else {
                            Button(action: a.run) { actionLabel(a) }.buttonStyle(.bordered)
                        }
                    }
                    Button(role: .destructive, action: onDelete) {
                        Text(many ? t("stock_delete_one") : t("stock_delete")).fixedSize()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                }
                .controlSize(.small)
                .padding(.top, 4)
            }
        }
        .padding(.vertical, 4)
    }

    // Text only: icon labels collapse to icon-only inside a list row's flow.
    private func actionLabel(_ a: VialAction) -> some View { Text(a.title).fixedSize() }

    @ViewBuilder private func details(_ v: Vial, _ st: VialStatus, spray: Bool, pack: Bool, marks: Double?, dose: Double, many: Bool,
                                      strengthTotal: Double, expiresAt: Millis?, budSoon: Bool) -> some View {
        FlowLayout(spacing: 12) {
            if v.state == .onOrder {
                Text(t("stock_not_here_yet"))
                if let at = v.acquiredAt { Text(t("ios_stock_ordered", ["date": .string(formatDate(at, nowMs: ctx.now))])) }
            } else if v.state == .reconstituted, v.diluentMl != nil {
                Text(formatConcentration(st.concentrationMcgPerMl)).monospacedDigit()
                Text(t("log_ml_left", ["ml": .string(trim(st.remainingMl, 2))])).monospacedDigit()
                if let marks { Text(t("stock_marks_per", ["marks": .string(trim(marks, 2)), "dose": .string(formatDose(dose))])).monospacedDigit() }
                if spray, mcgPerSpray(v) > 0 { Text(t("ios_stock_a_press", ["dose": .string(formatDose(mcgPerSpray(v)))])).monospacedDigit() }
                if spray { Text(t("stock_presses_left", ["n": .number(spraysRemaining(v))])) }
                if spray, let at = v.reconstitutedAt { Text(t("stock_filled", ["date": .string(formatDate(at, nowMs: ctx.now))])) }
                if !spray, let bud = v.budAt {
                    Text(t("stock_use_by", ["date": .string(formatDate(bud, nowMs: ctx.now))])).foregroundStyle(budSoon ? Tone.rose.color : .secondary)
                }
            } else {
                if pack {
                    Text(t("stock_tablets_left", ["n": .number(tabletsRemaining(v))])).monospacedDigit()
                    if mgPerTablet(v) > 0 { Text(t("stock_per_tablet", ["mg": .string(trim(mgPerTablet(v), 3))])).monospacedDigit() }
                    else { Text(t("stock_no_tablet_size")).foregroundStyle(Tone.rose.color) }
                } else {
                    Text(t("stock_lyophilised"))
                }
                if many { Text(t("stock_mg_in_total", ["mg": .string(trim(strengthTotal, 2))])).monospacedDigit() }
                if let expiresAt { Text("\(many ? t("stock_first_expires") : t("stock_expires_word")) \(formatDate(expiresAt, nowMs: ctx.now))") }
            }
        }
    }
}
