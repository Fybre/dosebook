import SwiftUI
import BenchCore
import BenchStore

/// One name per diluent, used by every screen.
func diluentName(_ k: DiluentKind) -> String {
    switch k {
    case .bacteriostatic: t("diluent_bacteriostatic")
    case .sterile: t("diluent_sterile")
    case .saline: t("diluent_saline")
    case .oil: t("diluent_oil")
    default: k.rawValue
    }
}

func bottleStateName(_ s: BottleState) -> String {
    switch s {
    case .sealed: t("stock_bottle_sealed")
    case .open: t("stock_bottle_open")
    case .finished: t("stock_bottle_finished")
    case .discarded: t("stock_bottle_discarded")
    default: s.rawValue
    }
}

/// The kinds a vial can be made up with. Oil is not one.
let DILUENT_CHOICES: [DiluentKind] = [.bacteriostatic, .sterile, .saline]

/// Which tracked bottle the water came from; "" is water the app does not track.
private struct BottlePicker: View {
    var label: String
    var optionKey: String
    var bottles: [DiluentBottle]
    var untrackedHint: String
    @Binding var bottleId: String
    var body: some View {
        if !bottles.isEmpty {
            let chosen = bottles.first { $0.id == bottleId }
            Section {
                Picker(label, selection: $bottleId) {
                    ForEach(bottles) { b in
                        Text(t(optionKey, ["ml": .string(trim(b.volumeMl, 2)), "left": .string(trim(bottleRemainingMl(b), 2))])
                             + (b.state == .sealed ? t("stock_sealed_suffix") : "")).tag(b.id)
                    }
                    Text(t("stock_not_tracked")).tag("")
                }
            } footer: {
                Text(chosen.map { t("stock_ml_left_before", ["ml": .string(trim(bottleRemainingMl($0), 2))]) } ?? untrackedHint)
            }
        }
    }
}

private struct FormChrome: ViewModifier {
    var title: String
    var confirm: String
    var disabled: Bool
    var action: () -> Void
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(confirm) { action(); dismiss() }.disabled(disabled) }
            }
    }
}

extension View {
    func formChrome(_ title: String, confirm: String, disabled: Bool = false, action: @escaping () -> Void) -> some View {
        modifier(FormChrome(title: title, confirm: confirm, disabled: disabled, action: action))
    }
}

// MARK: - Adding vials

struct AddVialForm: View {
    @Environment(AppStore.self) private var store
    /// Opens the label scanner straight away.
    var scanFirst = false
    /// The compound to start on, when added from somewhere that knows it.
    var startingPeptideId: String?
    /// Start on "mixed, in use", for a vial already being drawn from.
    var alreadyMixed = false

    enum Place: Hashable { case fridge, onOrder, mixed }
    private var arrived: Bool { place != .onOrder }
    @State private var scanning = false
    @State private var lot = ""
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var peptideId = ""
    @State private var strengthMg: Double = 10
    @State private var count: Double = 1
    @State private var tabletsPerPack: Double = 30
    @State private var shipping: Double?
    @State private var payCurrency = ""
    @State private var supplier = ""
    @State private var cost: Double?
    @State private var pricedAsKit = false
    @State private var place: Place = .fridge
    @State private var mixedMl: Double = 2
    @State private var mixedOn = Date()
    @State private var addingCompound = false
    @State private var loaded = false

    var body: some View {
        let data = store.data
        let currency = data.settings.currency
        let peptide = data.peptide(peptideId)
        let tablets = peptide?.preparation == .tablet
        let packMg = packStrengthMg(strengthMg, tabletsPerPack)
        let n = max(1, count)
        // Stored per vial, whichever way it was entered.
        let perVial: Double? = cost.flatMap { pricedAsKit ? costPerVialInKit($0, n) : $0 }
        Form {
            Section {
                Button { scanning = true } label: { Label(t("ios_scan_title"), systemImage: "camera.viewfinder") }
            } footer: { Text(t("ios_stock_scan_hint")) }
            Section {
                Picker(t("plan_peptide"), selection: Binding(get: { peptideId }, set: choose)) {
                    ForEach(data.allPeptides) { Text($0.name).tag($0.id) }
                }
                Button { addingCompound = true } label: { Label(t("add_compound_inline"), systemImage: "plus") }
            }
            Section {
                AmountRow(label: tablets ? t("stock_mg_per_tablet") : t("stock_strength"), value: $strengthMg, base: .mg, range: 0...100_000)
                if tablets {
                    NumberRow(label: t("stock_tablets_per_pack"), value: $tabletsPerPack, range: 1...10_000)
                }
                NumberRow(label: tablets ? t("stock_how_many_packs") : t("stock_how_many"), value: $count, range: 1...50)
                TextField(t("stock_source"), text: $supplier, prompt: Text("\(t("stock_source")) (\(t("optional")))"))
                LabeledContent(t("ios_scan_lot")) {
                    TextField(t("optional"), text: $lot).multilineTextAlignment(.trailing).capitalisedCharacters()
                }
                Toggle(t("ios_scan_has_expiry"), isOn: $hasExpiry)
                if hasExpiry { DatePicker(t("ios_scan_expiry"), selection: $expiry, displayedComponents: .date) }
                Picker(t("stock_where"), selection: $place) {
                    Text(t("stock_in_the_fridge")).tag(Place.fridge)
                    if !tablets { Text(t("ios_stock_mixed_in_use")).tag(Place.mixed) }
                    Text(t("stock_on_order")).tag(Place.onOrder)
                }
                if place == .mixed && !tablets {
                    NumberRow(label: t("stock_water_added"), value: $mixedMl, suffix: "mL", range: 0...100)
                    DatePicker(t("ios_stock_mixed_on"), selection: $mixedOn, in: ...Date(), displayedComponents: .date)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if tablets { Text(t("stock_pack_holds", ["mg": .string(trim(packMg, 2))])) }
                    else if let sizes = peptide?.vialSizesMg, !sizes.isEmpty {
                        Text(t("stock_common_sizes", ["sizes": .string(sizes.map { jsNumberString($0) }.joined(separator: ", "))]))
                    }
                    if !arrived { Text(t("stock_on_order_hint")) }
                    if place == .mixed && !tablets {
                        Text(t("stock_makes_conc", ["conc": .string(trim(mixedMl > 0 ? strengthMg / mixedMl : 0, 3))]))
                        Text(n > 1 ? t("ios_stock_mixed_hint_many") : t("ios_stock_mixed_hint"))
                    }
                }
            }
            Section {
                OptionalNumberRow(label: pricedAsKit ? t("stock_cost_kit") : t("stock_cost_per_vial_label"), value: $cost, suffix: payCurrency)
                Picker(t("stock_priced_as"), selection: $pricedAsKit) {
                    Text(t("stock_per_vial")).tag(false)
                    Text(n > 1 ? t("stock_kit_of", ["n": .number(n)]) : t("stock_whole_kit")).tag(true)
                }
                Picker(t("stock_paid_in"), selection: $payCurrency) {
                    ForEach(CURRENCIES, id: \.code) { Text("\($0.code) · \($0.label)").tag($0.code) }
                }
                if let c = cost, c > 0, payCurrency != currency, let url = converterUrl(c, payCurrency, currency) {
                    Link(t("ios_stock_convert", ["amount": .string(formatMoney(c, payCurrency)), "currency": .string(currency)]), destination: url)
                }
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if let perVial, strengthMg > 0 {
                        Text(t("stock_cost_hint", ["avial": .string(formatMoney(perVial, currency)), "permg": .string(formatMoney(perVial / strengthMg, currency))])
                             + (n > 1 ? t("stock_cost_all", ["total": .string(formatMoney(perVial * n, currency)), "n": .number(n)]) : ""))
                    } else {
                        Text(t("stock_cost_optional"))
                    }
                    Text(t("stock_paid_in_hint"))
                }
            }
            Section {
                OptionalNumberRow(label: t("stock_shipping_order"), value: $shipping, suffix: payCurrency)
            } footer: {
                if let s = shipping, s > 0 {
                    Text(t("stock_shipping_split", ["each": .string(formatMoney(s / n, currency)), "vials": .string(t("count_vials", ["n": .number(n)]))]))
                } else {
                    Text(t("stock_shipping_optional"))
                }
            }
        }
        .formChrome(t("stock_new_vial"),
                    confirm: arrived ? t("stock_add_vials", ["vials": .string(what(tablets, n))]) : t("stock_add_vials_on_order", ["vials": .string(what(tablets, n))]),
                    disabled: peptideId.isEmpty || !(tablets ? packMg > 0 : strengthMg > 0) || (place == .mixed && !tablets && !(mixedMl > 0))) {
            let base = Vial(id: "", profileId: "", peptideId: peptideId, strengthMg: tablets ? packMg : strengthMg,
                            state: arrived ? .sealed : .onOrder,
                            supplier: supplier.trimmingCharacters(in: .whitespaces).isEmpty ? nil : supplier.trimmingCharacters(in: .whitespaces),
                            lot: lot.trimmingCharacters(in: .whitespaces).isEmpty ? nil : lot.trimmingCharacters(in: .whitespaces),
                            cost: perVial, currency: perVial == nil ? nil : payCurrency, acquiredAt: nowMillis(), expiresAt: hasExpiry ? endOfLocalDay(expiry.millis) : nil,
                            container: tablets ? .pack : nil, mgPerTablet: tablets ? strengthMg : nil)
            let paid = shipping.flatMap { $0 > 0 ? $0 : nil }
            let mix = place == .mixed && !tablets
            let ml = mixedMl, mixedAt = min(nowMillis(), mixedOn.millis)
            store.mutate { d in
                let before = Set(d.vials.map(\.id))
                d.addOrder(Array(repeating: base, count: Int(n)), shippingCost: paid, currency: paid == nil ? nil : payCurrency)
                // One of them is the vial being drawn from; the rest stay sealed.
                if mix, let id = d.vials.first(where: { !before.contains($0.id) })?.id {
                    d.reconstituteVial(id, diluentMl: ml, diluent: .bacteriostatic, at: mixedAt)
                }
            }
        }
        .sheet(isPresented: $addingCompound) { NavigationStack { CustomCompoundForm(onCreated: { choose($0.id) }) } }
        .sheet(isPresented: $scanning) { NavigationStack { ScanVialView(onScanned: apply) } }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            payCurrency = store.data.settings.currency
            if let id = startingPeptideId, store.data.peptide(id) != nil { choose(id) }
            else if let first = store.data.allPeptides.first { choose(first.id) }
            if alreadyMixed { place = .mixed }
            if scanFirst { scanning = true }
        }
    }

    private func what(_ tablets: Bool, _ n: Double) -> String {
        tablets ? t("count_packs", ["n": .number(n)]) : t("count_vials", ["n": .number(n)])
    }

    /// A checked scan: the compound, and whatever else the label gave.
    private func apply(_ s: ScannedVial) {
        choose(s.peptideId)
        if s.strengthMg > 0 { strengthMg = s.strengthMg }
        if let l = s.lot { lot = l }
        if let e = s.expiresAt { hasExpiry = true; expiry = Date(millis: e) }
    }

    private func choose(_ id: String) {
        peptideId = id
        if let first = store.data.peptide(id)?.vialSizesMg.first { strengthMg = first }
    }
}

/// Whether a compound has ever had a vial in Stock, in any state. With none, a
/// protocol for it has nothing to draw from and no syringe units to show.
@MainActor func hasAnyVial(_ data: AppData, _ peptideId: String) -> Bool {
    data.mine.vials.contains { $0.peptideId == peptideId }
}

/// A compound to add a vial for, from a prompt elsewhere.
struct VialFor: Identifiable {
    var peptideId: String
    var mixed = false
    var id: String { peptideId + (mixed ? "+mixed" : "") }
}

// MARK: - Correcting what is left

/// What is left in an open vial, set by eye: in mL of solution for a mixed vial,
/// or as an amount. Doses logged afterwards come out of the new figure.
struct VialLeftForm: View {
    @Environment(AppStore.self) private var store
    var vial: Vial
    @State private var leftMcg: Double = 0
    @State private var inMl = true
    @State private var loaded = false

    var body: some View {
        let conc = vialConcentration(vial)
        let mixed = conc.isFinite && conc > 0
        let cap = vialCapacityMcg(vial)
        let name = store.data.peptide(vial.peptideId)?.name ?? vial.peptideId
        Form {
            Section {
                if mixed {
                    Picker(t("ios_left_enter_as"), selection: $inMl) {
                        Text("mL").tag(true)
                        Text(t("ios_left_amount")).tag(false)
                    }
                    .pickerStyle(.segmented)
                }
                if mixed && inMl {
                    NumberRow(label: t("ios_left_title"), value: Binding(get: { jsFixed(leftMcg / conc, 3) }, set: { leftMcg = $0 * conc }),
                              suffix: "mL", range: 0...((vial.diluentMl ?? 0)))
                } else {
                    AmountRow(label: t("ios_left_title"), value: $leftMcg, base: .mcg, range: 0...cap)
                }
            } header: { Text("\(name) · \(jsNumberString(vial.strengthMg)) mg") } footer: {
                Text(t("ios_left_hint", ["amount": .string(formatDose(min(leftMcg, cap))), "pct": .string(trim(cap > 0 ? min(leftMcg, cap) / cap * 100 : 0, 0))])
                     + (mixed ? " " + t("ios_left_ml", ["ml": .string(trim(min(leftMcg, cap) / conc, 2)), "full": .string(trim(vial.diluentMl ?? 0, 2))]) : ""))
            }
        }
        .formChrome(t("ios_left_title"), confirm: t("save")) {
            store.mutate { $0.setVialRemaining(vial.id, remainingMcg: leftMcg) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            leftMcg = vialRemainingMcg(vial)
        }
    }
}

// MARK: - Making up and topping up

struct ReconstituteForm: View {
    @Environment(AppStore.self) private var store
    var vial: Vial
    @State private var ml: Double = 2
    @State private var diluent: DiluentKind = .bacteriostatic
    @State private var bottleId = ""
    @State private var loaded = false

    var body: some View {
        let now = nowMillis()
        let bottles = store.data.mine.diluents
        let available = shelfOrder(bottles.filter { $0.kind == diluent && bottleUsable($0, now) }, now)
        let chosen = available.first { $0.id == bottleId }
        let conc = ml > 0 ? vial.strengthMg / ml : 0
        Form {
            Section {
                NumberRow(label: t("stock_water_added"), value: $ml, suffix: "mL", range: 0...100)
                Picker(t("stock_diluent"), selection: Binding(get: { diluent }, set: { diluent = $0; bottleId = pickBottle(bottles, $0, ml, now)?.id ?? "" })) {
                    ForEach(DILUENT_CHOICES, id: \.self) { Text(diluentName($0)).tag($0) }
                }
            } footer: { Text(t("stock_makes_conc", ["conc": .string(trim(conc, 3))])) }
            BottlePicker(label: t("stock_from_bottle"), optionKey: "stock_bottle_option", bottles: available, untrackedHint: t("stock_untracked_bottle"), bottleId: $bottleId)
            if let chosen, bottleRemainingMl(chosen) < ml - 1e-9 {
                Text(t("stock_bottle_short", ["has": .string(trim(bottleRemainingMl(chosen), 2)), "want": .string(trim(ml, 2))])).foregroundStyle(Tone.tangerine.color)
            }
            if diluent == .sterile { Text(t("stock_sterile_water_note")).foregroundStyle(Tone.tangerine.color) }
            Section {
                Text(t("stock_swirl_note", ["days": .string(t("count_days", ["n": .number(MULTI_DOSE_VIAL_BUD_DAYS)]))])).font(.footnote).foregroundStyle(.secondary)
            }
        }
        .formChrome(t("stock_reconstitute"), confirm: t("stock_reconstitute"), disabled: !(ml > 0)) {
            store.mutate { $0.reconstituteVial(vial.id, diluentMl: ml, diluent: diluent, fromBottleId: bottleId.isEmpty ? nil : bottleId) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            bottleId = pickBottle(bottles, diluent, ml, now)?.id ?? ""
        }
    }
}

struct TopUpForm: View {
    @Environment(AppStore.self) private var store
    var vial: Vial
    @State private var ml: Double = 0.5
    @State private var bottleId = ""
    @State private var loaded = false

    var body: some View {
        let now = nowMillis()
        let kind = vial.diluent ?? .bacteriostatic
        let bottles = store.data.mine.diluents
        let available = bottles.filter { $0.kind == kind && bottleUsable($0, now) }
        let next = diluentAfterTopUp(vial, ml)
        let after: Vial? = next.map { var v = vial; v.diluentMl = $0; return v }
        Form {
            Section {
                NumberRow(label: t("stock_water_added"), value: $ml, suffix: "mL", range: 0...100)
            } footer: {
                if let after {
                    Text(t("stock_becomes", ["before": .string(formatConcentration(vialConcentration(vial))),
                                             "after": .string(formatConcentration(vialConcentration(after))),
                                             "ml": .string(trim(vialRemainingMl(after), 2))]))
                } else {
                    Text(t("stock_adding_now"))
                }
            }
            Section { Text(t("stock_topup_note")).font(.footnote).foregroundStyle(.secondary) }
            BottlePicker(label: t("stock_from_bottle"), optionKey: "stock_bottle_option", bottles: available, untrackedHint: t("stock_untracked_bottle"), bottleId: $bottleId)
        }
        .formChrome(t("stock_add_diluent"), confirm: t("ios_stock_add_ml", ["ml": .string(trim(ml, 2))]), disabled: after == nil) {
            store.mutate { $0.topUpVial(vial.id, addedMl: ml, fromBottleId: bottleId.isEmpty ? nil : bottleId) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            bottleId = pickBottle(bottles, kind, ml, now)?.id ?? ""
        }
    }
}

/// Empty a made-up vial into a nasal spray bottle.
struct TransferToSprayForm: View {
    @Environment(AppStore.self) private var store
    var vial: Vial
    @State private var addedMl: Double = 4
    @State private var perSpray: Double = DEFAULT_ML_PER_SPRAY
    // Saline: the preservative in bacteriostatic water stings a nose.
    @State private var kind: DiluentKind = .saline
    @State private var bottleId = ""
    @State private var loaded = false

    var body: some View {
        let now = nowMillis()
        let bottles = store.data.mine.diluents
        let available = shelfOrder(bottles.filter { $0.kind == kind && bottleUsable($0, now) }, now)
        let plan = transferToSpray(vial, addedMl: addedMl, mlPerSpray: perSpray, diluent: kind, atMs: now)
        let perPress = plan.map { mcgPerSpray($0.bottle) } ?? 0
        Form {
            Section { Text(t("stock_transfer_note")).font(.footnote).foregroundStyle(.secondary) }
            Section {
                NumberRow(label: t("stock_saline_added"), value: $addedMl, suffix: "mL", range: 0...100)
            } footer: {
                Text(plan.map { t("stock_bottle_now", ["ml": .string(trim($0.bottle.diluentMl ?? 0, 2)), "conc": .string(formatConcentration(vialConcentration($0.bottle)))]) } ?? t("stock_nothing_to_pour"))
            }
            Section {
                NumberRow(label: t("stock_one_press"), value: $perSpray, suffix: "mL", range: 0...10)
            } footer: {
                VStack(alignment: .leading, spacing: 4) {
                    if perPress > 0 { Text(t("ios_stock_a_press", ["dose": .string(formatDose(perPress))])) }
                    Text(MEASURE_A_PRESS)
                }
            }
            Section {
                Picker(t("stock_what_went_in"), selection: $kind) {
                    ForEach([DiluentKind.saline, .sterile, .bacteriostatic], id: \.self) { Text(diluentName($0)).tag($0) }
                }
            }
            BottlePicker(label: t("stock_from_ampoule"), optionKey: "stock_ampoule_option", bottles: available, untrackedHint: t("stock_untracked_nothing"), bottleId: $bottleId)
            Section { Text(t("stock_spray_bud_note")).font(.footnote).foregroundStyle(.secondary) }
        }
        .formChrome(t("stock_transfer_spray"), confirm: t("stock_fill_bottle"), disabled: plan == nil) {
            store.mutate { $0.transferToSpray(vialId: vial.id, addedMl: addedMl, mlPerSpray: perSpray, diluent: kind, fromBottleId: bottleId.isEmpty ? nil : bottleId) }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            bottleId = pickBottle(bottles, .saline, 4, now)?.id ?? ""
        }
    }
}

/// Saying how big one tablet is, on rows that already exist. Writes every vial
/// of a group, since it changes what the row has always been.
struct TabletSizeForm: View {
    @Environment(AppStore.self) private var store
    var vials: [Vial]
    @State private var mgEach: Double = 0
    // The pack as bought, not what is left in it.
    @State private var tablets: Double = 0
    @State private var loaded = false

    var body: some View {
        let v = vials[0]
        let packMg = packStrengthMg(mgEach, tablets)
        let ok = mgEach > 0 && tablets > 0
        let left: Double = ok ? { var c = v; c.strengthMg = packMg; c.mgPerTablet = mgEach; return tabletsRemaining(c) }() : 0
        Form {
            Section {
                AmountRow(label: t("stock_mg_per_tablet"), value: $mgEach, base: .mg, range: 0...100_000)
                NumberRow(label: t("stock_tablets_per_pack"), value: $tablets, range: 0...10_000)
            } footer: {
                if ok { Text(t("stock_pack_after", ["mg": .string(trim(packMg, 3)), "left": .string(t("count_tablets", ["n": .number(left)]))])) }
            }
        }
        .formChrome(t("stock_set_tablet_size"), confirm: t("save"), disabled: !ok) {
            store.mutate { d in
                for target in vials {
                    d.updateVial(target.id) { $0.container = .pack; $0.mgPerTablet = mgEach; $0.strengthMg = packMg }
                }
            }
        }
        .onAppear {
            guard !loaded else { return }
            loaded = true
            let known = mgPerTablet(v)
            mgEach = known
            tablets = known > 0 ? jsRound(v.strengthMg / known) : 0
        }
    }
}

// MARK: - Water

struct AddBottleForm: View {
    @Environment(AppStore.self) private var store
    @State private var kind: DiluentKind = .bacteriostatic
    @State private var volumeMl: Double = 30
    @State private var count: Double = 1

    var body: some View {
        Form {
            Picker(t("stock_what"), selection: $kind) {
                ForEach(DiluentKind.allCases, id: \.self) { Text(diluentName($0)).tag($0) }
            }
            NumberRow(label: t("stock_bottle_size"), value: $volumeMl, suffix: "mL", range: 0...10_000)
            NumberRow(label: t("stock_how_many"), value: $count, range: 1...100)
        }
        .formChrome(t("stock_add_bottle"), confirm: t("stock_add_bottles", ["n": .number(max(1, count))]), disabled: !(volumeMl > 0)) {
            store.mutate { d in
                for _ in 0..<Int(max(1, count)) {
                    d.addDiluent(DiluentBottle(id: "", profileId: "", kind: kind, volumeMl: volumeMl, state: .sealed))
                }
            }
        }
    }
}

/// Water used for something the app does not track. One-way on purpose.
struct UseElsewhereForm: View {
    @Environment(AppStore.self) private var store
    var bottle: DiluentBottle
    @State private var usedMl: Double = 1

    var body: some View {
        let take = min(usedMl, bottleRemainingMl(bottle))
        Form {
            NumberRow(label: t("stock_used_untracked"), value: $usedMl, suffix: "mL", range: 0...10_000)
        }
        .formChrome(t("stock_used_elsewhere"), confirm: t("stock_take_out", ["ml": .string(trim(take, 2))]), disabled: !(usedMl > 0)) {
            store.mutate { $0.drawDiluent(bottle.id, ml: take) }
        }
    }
}
