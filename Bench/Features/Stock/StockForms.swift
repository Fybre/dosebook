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
                FooterRow {
                Text(chosen.map { t("stock_ml_left_before", ["ml": .string(trim(bottleRemainingMl($0), 2))]) } ?? untrackedHint)
            }
            } footer: { FooterWrap {
                Text(chosen.map { t("stock_ml_left_before", ["ml": .string(trim(bottleRemainingMl($0), 2))]) } ?? untrackedHint)
            }}
        }
    }
}

private struct FormChrome: ViewModifier {
    var title: String
    var confirm: String
    var disabled: Bool
    var dismissAfter: Bool
    var action: () -> Void
    @Environment(\.dismiss) private var dismiss
    func body(content: Content) -> some View {
        content
            .navigationTitle(title)
            .inlineTitle()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
                ToolbarItem(placement: .confirmationAction) { Button(confirm) { action(); if dismissAfter { dismiss() } }.disabled(disabled) }
            }
    }
}

extension View {
    func formChrome(_ title: String, confirm: String, disabled: Bool = false, dismissAfter: Bool = true, action: @escaping () -> Void) -> some View {
        modifier(FormChrome(title: title, confirm: confirm, disabled: disabled, dismissAfter: dismissAfter, action: action))
    }
}

// MARK: - Adding vials

struct AddVialForm: View {
    @Environment(AppStore.self) private var store
    var scanFirst = false
    var startingPeptideId: String?
    var alreadyMixed = false
    /// Editing keeps the compound, profile, order and dose-history links intact.
    var editingVial: Vial?

    @State private var scanning = false
    @State private var addingCompound = false
    @State private var loaded = false
    @State private var peptideId = ""
    @State private var strengthMg: Double = 10
    @State private var count: Double = 1
    @State private var tabletsPerPack: Double = 30
    @State private var state: VialState = .sealed
    @State private var ml: Double = 2
    @State private var diluent: DiluentKind = .bacteriostatic
    @State private var mixedOn = Date()
    @State private var partiallyUsed = false
    @State private var fractionLeft: Double = 1
    @State private var inMl = true
    @State private var bottleId = ""
    @State private var syringeId = "u100-0.5"
    @State private var supplier = ""
    @State private var lot = ""
    @State private var notes = ""
    @State private var hasExpiry = false
    @State private var expiry = Date()
    @State private var cost: Double?
    @State private var shipping: Double?
    @State private var payCurrency = ""
    @State private var pricedAsKit = false
    @State private var purchaseExpanded = false

    private var tablets: Bool {
        editingVial.map(isPack) ?? (store.data.peptide(peptideId)?.preparation == .tablet)
    }
    private var spray: Bool { editingVial.map(isSpray) ?? false }
    private var capacity: Double { (tablets ? packStrengthMg(strengthMg, tabletsPerPack) : strengthMg) * 1000 }
    private var mixed: Bool { state == .reconstituted && !tablets }
    private var remaining: Double { capacity * (partiallyUsed ? fractionLeft : 1) }
    private var n: Int { max(1, min(50, Int(count.isFinite ? count : 1))) }
    private var valid: Bool {
        !peptideId.isEmpty && capacity.isFinite && capacity > 0 &&
        (!mixed || (ml.isFinite && ml > 0)) &&
        (!partiallyUsed || (fractionLeft.isFinite && fractionLeft >= 0 && fractionLeft <= 1)) &&
        (cost == nil || (cost!.isFinite && cost! >= 0)) &&
        (shipping == nil || (shipping!.isFinite && shipping! >= 0))
    }

    var body: some View {
        Form {
            if editingVial == nil {
                Section {
                    Button { scanning = true } label: { Label(t("ios_scan_title"), systemImage: "camera.viewfinder") }
                    Picker(t("plan_peptide"), selection: Binding(get: { peptideId }, set: choose)) {
                        ForEach(store.data.allPeptides) { Text($0.name).tag($0.id) }
                    }
                    Button { addingCompound = true } label: { Label(t("add_compound_inline"), systemImage: "plus") }
                BlendAmountsPrompt(peptideId: peptideId)
                }
            } else {
                Section { Text(store.data.peptide(peptideId)?.name ?? peptideId).font(.headline) }
            }
            Section {
                AmountRow(label: tablets ? t("stock_mg_per_tablet") : t("stock_strength"), value: $strengthMg, base: .mg, range: 0...100_000)
                if tablets { NumberRow(label: t("stock_tablets_per_pack"), value: $tabletsPerPack, range: 1...10_000) }
                if editingVial == nil {
                    NumberRow(label: tablets ? t("stock_how_many_packs") : t("stock_how_many"), value: $count, range: 1...50)
                }
                if !spray {
                    Picker(t("ios_vial_state"), selection: $state) {
                        Text(t("stock_sealed")).tag(VialState.sealed)
                        Text(tablets ? t("stock_open") : t("ios_stock_already_reconstituted")).tag(VialState.reconstituted)
                        Text(t("stock_on_order")).tag(VialState.onOrder)
                    }
                }
                if editingVial == nil && n > 1 && state == .reconstituted {
                    Text(t("ios_vial_batch_open")).font(.footnote).foregroundStyle(.secondary)
                }
            }
            if mixed {
                Section(t("stock_reconstitute")) {
                    NumberRow(label: t("stock_water_added"), value: $ml, suffix: "mL", range: 0...100)
                    Picker(t("stock_diluent"), selection: $diluent) {
                        ForEach(DILUENT_CHOICES, id: \.self) { Text(diluentName($0)).tag($0) }
                        if !DILUENT_CHOICES.contains(diluent) { Text(diluentName(diluent)).tag(diluent) }
                    }
                    DatePicker(t("ios_stock_mixed_on"), selection: $mixedOn, in: ...Date(), displayedComponents: .date)
                    Text(t("stock_makes_conc", ["conc": .string(trim(ml > 0 ? strengthMg / ml : 0, 3))]))
                        .font(.footnote).foregroundStyle(.secondary)
                    if editingVial?.state == .reconstituted {
                        Text(t("ios_vial_correct_mix")).font(.footnote).foregroundStyle(.secondary)
                    }
                }
                if editingVial?.state != .reconstituted {
                    let bottles = shelfOrder(store.data.mine.diluents.filter { $0.kind == diluent && bottleUsable($0, nowMillis()) }, nowMillis())
                    BottlePicker(label: t("stock_from_bottle"), optionKey: "stock_bottle_option", bottles: bottles,
                                 untrackedHint: t("stock_untracked_bottle"), bottleId: $bottleId)
                }
            }
            if state != .onOrder {
                Section(t("ios_left_title")) {
                    Toggle(t("ios_stock_partially_used"), isOn: $partiallyUsed)
                    if partiallyUsed {
                        if mixed {
                            Picker(t("ios_left_enter_as"), selection: $inMl) {
                                Text("mL").tag(true)
                                Text(t("ios_left_amount")).tag(false)
                            }.pickerStyle(.segmented)
                        }
                        if mixed && inMl {
                            NumberRow(label: t("ios_left_title"), value: Binding(
                                get: { jsFixed(fractionLeft * ml, 3) }, set: { fractionLeft = ml > 0 ? $0 / ml : 0 }),
                                      suffix: "mL", range: 0...max(0, ml))
                        } else {
                            AmountRow(label: t("ios_left_title"), value: Binding(
                                get: { remaining }, set: { fractionLeft = capacity > 0 ? $0 / capacity : 0 }),
                                      base: .mcg, range: 0...max(0, capacity))
                        }
                        Text(t("ios_left_hint", ["amount": .string(formatDose(remaining)), "pct": .string(trim(fractionLeft * 100, 0))]))
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                }
            }
            if mixed && !spray {
                ReconstitutionDosePreview(vial: draft(), diluentMl: ml, remainingMcg: remaining, syringeId: $syringeId)
            }
            Section {
                DisclosureGroup(t("ios_vial_purchase"), isExpanded: $purchaseExpanded) {
                    TextField(t("stock_source"), text: $supplier)
                    TextField(t("ios_scan_lot"), text: $lot).capitalisedCharacters()
                    Toggle(t("ios_scan_has_expiry"), isOn: $hasExpiry)
                    if hasExpiry { DatePicker(t("ios_scan_expiry"), selection: $expiry, displayedComponents: .date) }
                    OptionalNumberRow(label: pricedAsKit ? t("stock_cost_kit") : t("stock_cost_per_vial_label"), value: $cost, suffix: payCurrency)
                    if editingVial == nil {
                        Picker(t("stock_priced_as"), selection: $pricedAsKit) {
                            Text(t("stock_per_vial")).tag(false)
                            Text(t("stock_whole_kit")).tag(true)
                        }
                    }
                    Picker(t("stock_paid_in"), selection: $payCurrency) {
                        ForEach(CURRENCIES, id: \.code) { Text("\($0.code) · \($0.label)").tag($0.code) }
                    }
                    if editingVial == nil { OptionalNumberRow(label: t("stock_shipping_order"), value: $shipping, suffix: payCurrency) }
                    TextField(t("labs_notes"), text: $notes, axis: .vertical)
                }
            }
        }
        .formChrome(t(editingVial == nil ? "stock_new_vial" : "ios_vial_edit"), confirm: t("save"), disabled: !valid, action: save)
        .sheet(isPresented: $addingCompound) { NavigationStack { CustomCompoundForm(onCreated: { choose($0.id) }) } }
        .sheet(isPresented: $scanning) { NavigationStack { ScanVialView(onScanned: apply) } }
        .onChange(of: diluent) { bottleId = "" }
        .onAppear(perform: load)
    }

    /// Start with the existing record so edits retain metadata and all relationships.
    private func draft() -> Vial {
        var v = editingVial ?? Vial(id: "", profileId: "", peptideId: peptideId, strengthMg: strengthMg, state: state)
        v.strengthMg = capacity / 1000
        v.state = state
        v.supplier = clean(supplier); v.lot = clean(lot); v.notes = clean(notes)
        v.expiresAt = hasExpiry ? endOfLocalDay(expiry.millis) : nil
        v.cost = cost.map { pricedAsKit && editingVial == nil ? $0 / Double(n) : $0 }
        v.currency = v.cost == nil ? nil : payCurrency
        if editingVial == nil { v.acquiredAt = nowMillis(); v.container = tablets ? .pack : nil }
        if tablets { v.mgPerTablet = strengthMg }
        if mixed {
            v.diluentMl = ml; v.diluent = diluent
            v.reconstitutedAt = min(nowMillis(), mixedOn.millis)
            // Correcting volume or remaining stock never extends the original use-by date.
            if editingVial?.reconstitutedAt != v.reconstitutedAt || editingVial?.state != .reconstituted {
                v.budAt = spray ? editingVial?.budAt : beyondUseDate(v.reconstitutedAt!)
            }
        } else if !tablets {
            v.reconstitutedAt = nil; v.diluentMl = nil; v.diluent = nil; v.diluentBottleId = nil; v.budAt = nil
        } else if state == .reconstituted && editingVial?.state != .reconstituted {
            v = openPack(v, nowMillis())
        }
        v.drawnMcg = jsFixed(capacity - remaining, 6)
        return v
    }

    private func save() {
        guard valid else { return }
        let v = draft()
        store.mutate { d in
            if mixed && !spray {
                d.settings.reconstitutionPreferences[d.activeProfileId + ":" + peptideId] =
                    ReconstitutionPreference(diluentMl: ml, diluent: diluent, syringeId: syringeId)
            }
            if editingVial != nil {
                d.editVialDetails(v, fromBottleId: bottleId.isEmpty ? nil : bottleId)
            } else {
                let before = Set(d.vials.map(\.id))
                var sealed = v
                if v.state == .reconstituted {
                    sealed.state = .sealed; sealed.reconstitutedAt = nil; sealed.budAt = nil
                    sealed.diluentMl = nil; sealed.diluent = nil; sealed.diluentBottleId = nil
                }
                sealed.drawnMcg = 0
                d.addOrder(Array(repeating: sealed, count: n), shippingCost: shipping, currency: shipping == nil ? nil : payCurrency)
                if let added = d.vials.first(where: { !before.contains($0.id) }) {
                    var first = v; first.id = added.id
                    d.editVialDetails(first, fromBottleId: bottleId.isEmpty ? nil : bottleId)
                }
            }
        }
    }

    private func load() {
        guard !loaded else { return }; loaded = true
        payCurrency = store.data.settings.currency
        syringeId = store.data.settings.defaultSyringeId ?? "u100-0.5"
        if let v = editingVial {
            useRememberedMix(v.peptideId)
            peptideId = v.peptideId; state = v.state
            strengthMg = isPack(v) ? (v.mgPerTablet ?? v.strengthMg) : v.strengthMg
            tabletsPerPack = isPack(v) && strengthMg > 0 ? v.strengthMg / strengthMg : 30
            ml = v.diluentMl ?? 2; diluent = v.diluent ?? .bacteriostatic
            mixedOn = v.reconstitutedAt.map { Date(millis: $0) } ?? Date()
            fractionLeft = vialFractionRemaining(v); partiallyUsed = fractionLeft < 1
            supplier = v.supplier ?? ""; lot = v.lot ?? ""; notes = v.notes ?? ""
            cost = v.cost; payCurrency = v.currency ?? payCurrency
            hasExpiry = v.expiresAt != nil; expiry = v.expiresAt.map { Date(millis: $0) } ?? Date()
            if alreadyMixed && !isPack(v) { state = .reconstituted }
        } else {
            choose(startingPeptideId ?? store.data.allPeptides.first?.id ?? "")
            if alreadyMixed && !tablets { state = .reconstituted }
            if scanFirst { scanning = true }
        }
    }
    private func clean(_ s: String) -> String? {
        let value = s.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }
    private func choose(_ id: String) {
        peptideId = id
        useRememberedMix(id)
        if let first = store.data.peptide(id)?.vialSizesMg.first { strengthMg = first }
        fractionLeft = 1; partiallyUsed = false
    }
    private func useRememberedMix(_ id: String) {
        ml = 2; diluent = .bacteriostatic; bottleId = ""
        syringeId = store.data.settings.defaultSyringeId ?? "u100-0.5"
        if let preference = store.data.settings.reconstitutionPreferences[store.data.activeProfileId + ":" + id],
           preference.diluentMl.isFinite, preference.diluentMl > 0 {
            ml = preference.diluentMl; diluent = preference.diluent
            if syringeById(preference.syringeId) != nil { syringeId = preference.syringeId }
        }
    }
    private func apply(_ scan: ScannedVial) {
        choose(scan.peptideId)
        if scan.strengthMg > 0 { strengthMg = scan.strengthMg }
        if let value = scan.lot { lot = value }
        if let value = scan.expiresAt { hasExpiry = true; expiry = Date(millis: value) }
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

/// Estimates use today's protocol dose and the original concentration, even for part-used stock.
private struct ReconstitutionDosePreview: View {
    @Environment(AppStore.self) private var store
    var vial: Vial
    var diluentMl: Double
    var remainingMcg: Double
    @Binding var syringeId: String
    @State private var choosingSyringe = false

    var body: some View {
        let protocols = store.data.mine.protocols.filter {
            $0.active && $0.peptideId == vial.peptideId &&
                [.subcutaneous, .intramuscular, .intravenous].contains($0.route)
        }
        let syringe = syringeById(syringeId) ?? SYRINGES[2]
        let now = nowMillis()
        Section {
            if protocols.isEmpty {
                Text(t("ios_recon_no_protocol")).font(.footnote).foregroundStyle(.secondary)
            } else {
                DisclosureGroup(isExpanded: $choosingSyringe) {
                    SyringePickerView(value: Binding(get: { syringe.id }, set: {
                        syringeId = $0; choosingSyringe = false
                    }))
                } label: {
                    Text(syringe.label).font(.subheadline)
                }
                if diluentMl.isFinite && diluentMl > 0 && remainingMcg.isFinite && remainingMcg >= 0 {
                    ForEach(protocols) { p in
                        let dose = scheduledDoseMcg(p, now)
                        let draw = calculateDraw(vialMcg: vialCapacityMcg(vial), diluentMl: diluentMl,
                                                 doseMcg: dose, syringe: syringe)
                        VStack(alignment: .leading, spacing: 6) {
                            Text(p.name).font(.subheadline.bold())
                            if dose.isFinite && dose > 0 && draw.units.isFinite {
                                Text(t("ios_units_per", ["marks": .string(trim(draw.units, 3)), "dose": .string(formatDose(dose))]))
                                    .font(.headline).monospacedDigit()
                                Text(t("ios_recon_doses", ["count": .number(floor(min(remainingMcg, vialCapacityMcg(vial)) / dose + 1e-9)),
                                                           "units": .string(trim(draw.units, 3)),
                                                           "scale": .string(syringe.scale == .u100 ? "U-100" : "U-40")]))
                                    .font(.subheadline)
                                Text(t("calc_volume") + ": " + trim(draw.volumeMl, 4) + " mL").font(.caption).foregroundStyle(.secondary)
                                if draw.warnings.contains(.exceedsBarrel) {
                                    Text(t("calc_body_exceeds_barrel")).font(.footnote).foregroundStyle(Tone.rose.color)
                                }
                                if draw.warnings.contains(.belowGraduation) {
                                    Text(t("calc_body_below_graduation")).font(.footnote).foregroundStyle(Tone.tangerine.color)
                                } else if draw.warnings.contains(.offGraduation) {
                                    Text(t("calc_body_off_graduation")).font(.footnote).foregroundStyle(Tone.tangerine.color)
                                }
                            } else {
                                Text(t("ios_recon_no_dose")).font(.footnote).foregroundStyle(.secondary)
                            }
                        }
                    }
                    Text(t("ios_recon_current_dose")).font(.footnote).foregroundStyle(.secondary)
                } else {
                    Text(t("calc_enter_to_see")).font(.footnote).foregroundStyle(.secondary)
                }
            }
        } header: { Text(t("ios_recon_summary")) }
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
                FooterRow {
                if let after {
                    Text(t("stock_becomes", ["before": .string(formatConcentration(vialConcentration(vial))),
                                             "after": .string(formatConcentration(vialConcentration(after))),
                                             "ml": .string(trim(vialRemainingMl(after), 2))]))
                } else {
                    Text(t("stock_adding_now"))
                }
            }
            } footer: { FooterWrap {
                if let after {
                    Text(t("stock_becomes", ["before": .string(formatConcentration(vialConcentration(vial))),
                                             "after": .string(formatConcentration(vialConcentration(after))),
                                             "ml": .string(trim(vialRemainingMl(after), 2))]))
                } else {
                    Text(t("stock_adding_now"))
                }
            }}
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
                FooterRow {
                Text(plan.map { t("stock_bottle_now", ["ml": .string(trim($0.bottle.diluentMl ?? 0, 2)), "conc": .string(formatConcentration(vialConcentration($0.bottle)))]) } ?? t("stock_nothing_to_pour"))
            }
            } footer: { FooterWrap {
                Text(plan.map { t("stock_bottle_now", ["ml": .string(trim($0.bottle.diluentMl ?? 0, 2)), "conc": .string(formatConcentration(vialConcentration($0.bottle)))]) } ?? t("stock_nothing_to_pour"))
            }}
            Section {
                NumberRow(label: t("stock_one_press"), value: $perSpray, suffix: "mL", range: 0...10)
                FooterRow {
                VStack(alignment: .leading, spacing: 4) {
                    if perPress > 0 { Text(t("ios_stock_a_press", ["dose": .string(formatDose(perPress))])) }
                    Text(MEASURE_A_PRESS)
                }
            }
            } footer: { FooterWrap {
                VStack(alignment: .leading, spacing: 4) {
                    if perPress > 0 { Text(t("ios_stock_a_press", ["dose": .string(formatDose(perPress))])) }
                    Text(MEASURE_A_PRESS)
                }
            }}
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
                FooterRow {
                if ok { Text(t("stock_pack_after", ["mg": .string(trim(packMg, 3)), "left": .string(t("count_tablets", ["n": .number(left)]))])) }
            }
            } footer: { FooterWrap {
                if ok { Text(t("stock_pack_after", ["mg": .string(trim(packMg, 3)), "left": .string(t("count_tablets", ["n": .number(left)]))])) }
            }}
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
