import SwiftUI
import BenchCore
import BenchStore

/// Log a dose, or edit one. The protocol answers compound and dose together;
/// the container the dose comes out of decides whether it is counted in marks,
/// presses or tablets. Every figure comes from BenchCore.
struct LogDoseSheet: View {
    @Environment(AppStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    var defaultPeptideId: String?
    var editId: String?
    var anySite = false

    @State private var peptideId = ""
    @State private var protocolId = ""
    @State private var doseMcg: Double = 0
    @State private var at = Date()
    @State private var site: InjectionSite?
    @State private var route: Route = .subcutaneous
    @State private var vialId = ""
    @State private var syringeId = "u100-0.5"
    @State private var notes = ""
    @State private var skipped = false
    @State private var siteOverride = false
    @State private var feeling: Int?
    @State private var effects: [String] = []
    @State private var loaded = false
    @State private var confirmDelete = false
    @State private var addingCompound = false
    @State private var showSkipHelp = false

    private var data: AppData { store.data }
    private var mine: AppData { data.mine }
    private var editing: DoseLog? { editId.flatMap { id in mine.logs.first { $0.id == id } } }
    private var peptide: Peptide? { data.peptide(peptideId) }
    private var protocol_: DoseProtocol? { mine.protocols.first { $0.id == protocolId } }
    private var syringe: SyringeSpec { syringeById(syringeId) ?? SYRINGES[2] }
    private var nasal: Bool { route == .intranasal }
    private var tablets: Bool { peptide?.preparation == .tablet }
    private var noBarrel: Bool { nasal || tablets }
    private var hasSite: Bool { routeHasSite(route) }
    private var container: ContainerKind { containerForDose(peptide?.preparation, route) }
    private var routes: [Route] { routeChoices(peptide?.routes ?? [], mine.vials, peptideId, peptide?.preparation) }
    private var pinned: [InjectionSite] { protocol_?.sites ?? [] }
    private var vial: Vial? { mine.vials.first { $0.id == vialId } }
    private var conc: Double { vial.flatMap { v in v.diluentMl.map { concentration(mgToMcg(v.strengthMg), $0) } } ?? .nan }
    private var canConvert: Bool { conc.isFinite && conc > 0 }
    private var draw: DrawResult? {
        guard !noBarrel, let v = vial, let d = v.diluentMl else { return nil }
        return calculateDraw(vialMcg: mgToMcg(v.strengthMg), diluentMl: d, doseMcg: doseMcg, syringe: syringe)
    }
    private var tabletCount: Double? {
        guard tablets, let v = vial, tabletsForDose(v, doseMcg) > 0 else { return nil }
        return jsFixed(tabletsForDose(v, doseMcg), 3)
    }
    private var presses: Double? {
        guard nasal, let v = vial, spraysForDose(v, doseMcg) > 0 else { return nil }
        return spraysForDose(v, doseMcg)
    }

    var body: some View {
        ScrollViewReader { proxy in
        Form {
            let active = mine.protocols.filter(\.active)
            if !active.isEmpty || protocol_ != nil {
                Section {
                    Picker(t("log_protocol"), selection: Binding(get: { protocolId }, set: chooseProtocol)) {
                        Text(t("log_no_protocol")).tag("")
                        ForEach(active) { p in
                            Text("\(data.peptide(p.peptideId)?.name ?? p.peptideId), \(p.name), \(formatDose(scheduledDoseMcg(p, at.millis)))").tag(p.id)
                        }
                        if let p = protocol_, !p.active {
                            Text(t("log_protocol_stopped", ["peptide": .string(data.peptide(p.peptideId)?.name ?? p.peptideId), "name": .string(p.name)])).tag(p.id)
                        }
                    }
                } footer: { Text(protocol_ != nil ? t("log_protocol_sets") : t("log_outside_plan")) }
            }

            Section {
                Picker(t("plan_peptide"), selection: Binding(get: { peptideId }, set: choosePeptide)) {
                    ForEach(data.allPeptides) { Text($0.name).tag($0.id) }
                }
                Button { addingCompound = true } label: { Label(t("add_compound_inline"), systemImage: "plus") }
            }

            Section {
                AmountRow(label: t("plan_dose"), value: $doseMcg, range: 0...100_000_000)
                    .disabled(skipped)
                if let p = protocol_ {
                    Text(t("log_protocol_calls_for", ["dose": .string(formatDose(scheduledDoseMcg(p, at.millis)))])).font(.caption).foregroundStyle(.secondary)
                }
                countField
                if !noBarrel {
                    Picker(t("log_barrel"), selection: Binding(get: { syringe.scale }, set: setScale)) {
                        Text("U-100").tag(SyringeScale.u100)
                        Text("U-40").tag(SyringeScale.u40)
                    }
                    .pickerStyle(.segmented)
                    Text(syringe.scale == .u40 ? t("log_u40_hint") : t("log_u100_hint")).font(.caption).foregroundStyle(.secondary)
                }
                DatePicker(t("log_when"), selection: $at)
            }

            Section {
                // The stored route stays visible even when the library no longer offers it.
                Picker(t("plan_route"), selection: Binding(get: { route }, set: chooseRoute)) {
                    ForEach(routes.contains(route) ? routes : [route] + routes, id: \.self) { Text($0.label).tag($0) }
                }
                .id("route")
                if hasSite && !skipped {
                    Picker(t("log_site_short"), selection: $site) {
                        Text(t("log_not_recorded")).tag(InjectionSite?.none)
                        ForEach(INJECTION_SITES.filter { pinned.isEmpty || siteOverride || pinned.contains($0.id) }, id: \.id.rawValue) {
                            Text(siteLabel($0.id)).tag(Optional($0.id))
                        }
                    }
                    SiteMapView(logs: mine.logs.filter { $0.peptideId == peptideId }, selected: site.map { [$0] } ?? [],
                                allowed: siteOverride ? nil : pinned, onSelect: { s in
                                    if !pinned.isEmpty && !pinned.contains(s) { siteOverride = true }
                                    site = s
                                }, nowMs: at.millis)
                        .frame(maxWidth: .infinity)
                    if !pinned.isEmpty {
                        Button(siteOverride ? t("log_back_to_pinned") : t("log_use_any_site")) { siteOverride.toggle() }
                    }
                }
            } footer: {
                if hasSite && !skipped {
                    Text(!pinned.isEmpty && !siteOverride ? "Rotating through the \(pinned.count) sites pinned to this protocol." : t("log_green_ring"))
                }
            }

            stockSection
            drawSection

            if let p = peptide, isBlend(p), doseMcg > 0, !skipped {
                Section {
                    BlendBreakdownView(blend: p, doseMcg: doseMcg, resolve: { data.peptide($0) },
                                       dosesPerWeek: protocol_.map { protocolDosesPerWeek($0, at.millis) }, compact: true)
                }
            }

            if !skipped {
                Section {
                    // Five equal buttons, unless the text is too large to fit them on one line.
                    let feelings = ForEach(1...5, id: \.self) { n in
                        let on = feeling == n
                        Button { feeling = on ? nil : n } label: {
                            Text(FEELING_LABELS[n] ?? "").font(.caption.weight(.semibold)).lineLimit(1).fixedSize()
                                .padding(.horizontal, 10).frame(maxWidth: typeSize.isAccessibilitySize ? nil : .infinity, minHeight: 32)
                                .background(on ? (FEELING_TONE[n] ?? .neutral).color : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                                .foregroundStyle(on ? Color.white : Color.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityAddTraits(on ? .isSelected : [])
                    }
                    if typeSize.isAccessibilitySize { FlowLayout(spacing: 6) { feelings } } else { HStack(spacing: 6) { feelings } }
                    Text(t("log_anything_to_note")).font(.caption).foregroundStyle(.secondary)
                    FlowChips(items: COMMON_SIDE_EFFECTS, selected: $effects)
                }
            }

            Section(t("labs_notes")) {
                TextField(t("log_notes_placeholder"), text: $notes, axis: .vertical)
            }

            Section {
                Toggle(t("log_record_skipped"), isOn: $skipped)
                DisclosureGroup(t("log_skipped_dose_label"), isExpanded: $showSkipHelp) {
                    Text(t("log_skipped_why")).font(.footnote)
                    Text(t("log_skipped_effects")).font(.footnote)
                }
            }

            if let e = editing {
                Section {
                    Button(t("ios_log_delete"), role: .destructive) { confirmDelete = true }
                } footer: { Text(t("log_delete_returns", ["dose": .string(formatDose(e.doseMcg))])) }
            }
        }
        .debugAnchor(proxy)
        }
        .navigationTitle(editing != nil ? t("log_edit_dose_title") : t("log_log_a_dose"))
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .cancellationAction) { Button(t("cancel")) { dismiss() } }
            ToolbarItem(placement: .confirmationAction) {
                Button(editing != nil ? t("log_save_changes") : skipped ? t("log_record_skip") : t("log_save_dose"), action: save)
                    .disabled(peptideId.isEmpty || (!skipped && !(doseMcg > 0)))
            }
        }
        .confirmationDialog(t("log_delete_returns", ["dose": .string(formatDose(editing?.doseMcg ?? 0))]), isPresented: $confirmDelete, titleVisibility: .visible) {
            Button(t("ios_log_delete"), role: .destructive) {
                if let e = editing { store.mutate { $0.removeLog(e.id) } }
                dismiss()
            }
        }
        .sheet(isPresented: $addingCompound) { NavigationStack { CustomCompoundForm(onCreated: { choosePeptide($0.id) }) } }
        .onAppear(perform: load)
        .onChange(of: site) { _, s in
            if let s, !siteOverride, !pinned.isEmpty, !pinned.contains(s) { siteOverride = true }
        }
    }

    // MARK: Sections

    @ViewBuilder private var countField: some View {
        if tablets {
            let v = vial
            NumberRow(label: t("log_tablets"), value: Binding(
                get: { v.map { jsFixed(tabletsForDose($0, doseMcg), 2) } ?? 0 },
                set: { n in if let v { doseMcg = jsFixed(mcgForTablets(v, n), 2) } }), suffix: t("log_tablets_suffix"))
                .disabled(skipped || v == nil)
            Text(v == nil ? t("log_tablets_no_pack") : mcgPerTablet(v!) > 0 ? t("log_per_tablet_hint", ["dose": .string(formatDose(mcgPerTablet(v!)))]) : t("log_no_tablet_size"))
                .font(.caption).foregroundStyle(.secondary)
        } else if nasal {
            let v = vial
            NumberRow(label: t("log_presses"), value: Binding(
                get: { v.map { spraysForDose($0, doseMcg) } ?? 0 },
                set: { n in if let v { doseMcg = jsFixed(mcgForSprays(v, jsRound(n)), 2) } }), suffix: t("log_presses_suffix"))
                .disabled(skipped || v == nil)
            Text(v.map { mcgPerSpray($0) > 0 } == true
                 ? t("log_per_press_hint", ["dose": .string(formatDose(mcgPerSpray(v!))), "ml": .string(trim(mlForSprays(v!, spraysForDose(v!, doseMcg)), 2))])
                 : t("log_fill_spray_first"))
                .font(.caption).foregroundStyle(.secondary)
        } else {
            NumberRow(label: t("log_syringe_units"), value: Binding(
                get: { canConvert ? jsFixed(unitsFromDose(doseMcg, conc, syringe.scale), 2) : 0 },
                set: { u in if canConvert { doseMcg = jsFixed(doseFromUnits(u, conc, syringe.scale), 2) } }), suffix: t("log_units_suffix"))
                .disabled(skipped || !canConvert)
            Text(canConvert ? t("log_unit_worth", ["mcg": .string(trim(mcgPerUnitOfScale(conc, syringe.scale), 2)), "marks": .string(t("count_units", ["n": .number(syringe.graduationUnits)]))])
                 : t("log_reconstitute_first"))
                .font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder private var stockSection: some View {
        let usable = drawableVials(mine.vials, peptideId, nowMillis(), container)
        Section {
            if usable.isEmpty {
                Text(nasal ? t("log_no_spray_filled") : tablets ? t("log_no_pack_in_stock") : t("log_no_vial_in_stock"))
                    .font(.footnote).foregroundStyle(Tone.tangerine.color)
            } else {
                Picker(nasal ? t("log_sprayed_from") : tablets ? t("log_taken_from") : t("log_drawn_from"), selection: $vialId) {
                    Text(t("log_not_recorded_stock")).tag("")
                    ForEach(usable) { v in
                        let st = vialStatus(v)
                        let left = isPack(v) ? t("count_tablets", ["n": .number(tabletsRemaining(v))])
                            : v.state == .reconstituted && v.diluentMl != nil ? t("log_ml_left", ["ml": .string(trim(st.remainingMl, 2))]) : t("stock_sealed")
                        Text("\(jsNumberString(v.strengthMg)) mg · \(left) · \(t("log_mcg_remaining", ["mcg": .string(formatDose(st.remainingMcg))]))\(st.expired ? " · " + t("stock_past_date") : "")").tag(v.id)
                    }
                }
                if let v = vial, doseMcg > 0, !skipped {
                    let stock = stockFor(mine.vials, peptideId, doseMcg, at.millis, container)
                    let leftAfter = max(0, vialRemainingMcg(v) - doseMcg)
                    let vialDosesAfter = (leftAfter / doseMcg).rounded(.down)
                    HStack(alignment: .firstTextBaseline) {
                        Text(jsNumberString(vialDosesAfter)).font(.title3.monospacedDigit()).foregroundStyle(Tone.tangerine.color)
                        Text(t("log_doses_left_in_vial", ["n": .number(vialDosesAfter), "dose": .string(formatDose(doseMcg))])).font(.footnote).foregroundStyle(.secondary)
                    }
                    Text("\(t("log_remaining_in_vial", ["left": .string(formatDose(leftAfter))])) · \(jsNumberString(max(0, stock.dosesRemaining - 1))) \(t("log_across_your_stock"))")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } footer: {
            if !usable.isEmpty {
                Text(t("log_vial_hint", ["container": .string(nasal ? t("log_container_bottle") : tablets ? t("log_container_pack") : t("log_container_vial"))]))
            }
        }
    }

    @ViewBuilder private var drawSection: some View {
        if let draw, !skipped {
            Section {
                HStack {
                    Pill(text: "\(trim(draw.unitsRounded, 2)) \(t("log_units_suffix")) · \(trim(draw.volumeRoundedMl, 3)) mL", tone: .tangerine)
                    Pill(text: syringe.scale == .u100 ? "U-100" : "U-40")
                }
                .id("draw")
                Picker(t("log_syringe"), selection: $syringeId) { ForEach(SYRINGES) { Text($0.label).tag($0.id) } }
                SyringeView(spec: syringe, units: draw.unitsRounded, ghostUnits: draw.units, overCapacity: draw.warnings.contains(.exceedsBarrel))
            }
        } else if nasal, let v = vial, mcgPerSpray(v) > 0, doseMcg > 0, !skipped {
            Section {
                HStack {
                    Pill(text: t("log_press_count", ["n": .number(spraysForDose(v, doseMcg))]), tone: .grape)
                    Pill(text: "\(trim(mlForSprays(v, spraysForDose(v, doseMcg)), 2)) mL · \(formatDose(mcgForSprays(v, spraysForDose(v, doseMcg))))")
                }
                Text(t("log_nostrils_note")).font(.caption).foregroundStyle(.secondary)
            }
        }
    }

    // MARK: Behaviour

    private func load() {
        guard !loaded else { return }
        loaded = true
        syringeId = data.settings.defaultSyringeId ?? "u100-0.5"
        if let e = editing {
            peptideId = e.peptideId; protocolId = e.protocolId ?? ""; doseMcg = e.doseMcg; at = Date(millis: e.at)
            route = e.route; site = e.site; vialId = e.vialId ?? ""; notes = e.notes ?? ""; skipped = e.isSkipped
            feeling = e.feeling; effects = e.sideEffects ?? []; siteOverride = true
            if let spec = syringeForLog(syringeId: e.syringeId, syringeScale: e.syringeScale, defaultId: data.settings.defaultSyringeId) { syringeId = spec.id }
            return
        }
        let id = defaultPeptideId ?? data.allPeptides.first?.id ?? ""
        peptideId = id
        let proto = mine.protocols.first { $0.active && $0.peptideId == id }
        protocolId = proto?.id ?? ""
        applyProtocol(proto, id, nowMillis())
        if anySite { siteOverride = true }
    }

    private func containerFor(_ pid: String, _ r: Route) -> ContainerKind { containerForDose(data.peptide(pid)?.preparation, r) }

    private func applyProtocol(_ proto: DoseProtocol?, _ pid: String, _ atMs: Millis) {
        let dose = proto.map { scheduledDoseMcg($0, atMs) } ?? 0
        let onlySpray = proto == nil && pickVialForDose(mine.vials, pid, dose, atMs, .vial) == nil && pickVialForDose(mine.vials, pid, dose, atMs, .spray) != nil
        let nextRoute = proto?.route ?? defaultRoute(data.peptide(pid)?.preparation, onlySpray)
        doseMcg = dose
        route = nextRoute
        vialId = pickVialForDose(mine.vials, pid, dose, atMs, containerFor(pid, nextRoute))?.id ?? ""
        siteOverride = false
        site = suggestSite(mine.logs.filter { $0.peptideId == pid }, atMs, allowed: proto?.sites)
    }

    private func choosePeptide(_ id: String) {
        peptideId = id
        let proto = mine.protocols.first { $0.active && $0.peptideId == id }
        protocolId = proto?.id ?? ""
        applyProtocol(proto, id, at.millis)
    }

    private func chooseRoute(_ r: Route) {
        route = r
        vialId = pickVialForDose(mine.vials, peptideId, doseMcg, at.millis, containerFor(peptideId, r))?.id ?? ""
    }

    private func chooseProtocol(_ id: String) {
        protocolId = id
        guard let p = mine.protocols.first(where: { $0.id == id }) else { return }
        peptideId = p.peptideId
        applyProtocol(p, p.peptideId, at.millis)
    }

    private func setScale(_ next: SyringeScale) {
        syringeId = (SYRINGES.first { $0.scale == next && $0.capacityMl == syringe.capacityMl } ?? SYRINGES.first { $0.scale == next }!).id
    }

    private func save() {
        let d = draw
        let trimmed = notes.trimmingCharacters(in: .whitespacesAndNewlines)
        let log = DoseLog(id: editing?.id ?? "", profileId: editing?.profileId ?? "", protocolId: protocol_?.id, peptideId: peptideId, at: at.millis,
                          doseMcg: doseMcg, route: route, site: hasSite && !skipped ? site : nil, vialId: vialId.isEmpty ? nil : vialId,
                          volumeMl: d?.volumeRoundedMl, units: d?.unitsRounded, presses: presses, tablets: tabletCount,
                          syringeId: d != nil ? syringe.id : nil, syringeScale: d != nil ? syringe.scale : nil,
                          skipped: skipped ? true : nil, notes: trimmed.isEmpty ? nil : trimmed, feeling: feeling,
                          sideEffects: effects.isEmpty ? nil : effects)
        if let e = editing {
            store.mutate { $0.updateLog(e.id) { var l = log; l.extra = $0.extra; $0 = l } }
        } else {
            store.mutate { $0.addLog(log) }
        }
        dismiss()
    }
}

/// Wrapping toggle chips.
struct FlowChips: View {
    var items: [String]
    @Binding var selected: [String]
    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                let on = selected.contains(item)
                Button { selected = on ? selected.filter { $0 != item } : selected + [item] } label: {
                    Text(item).font(.caption).padding(.horizontal, 10).padding(.vertical, 6)
                        .background(on ? Tone.rose.color.opacity(0.18) : Color(.tertiarySystemFill), in: Capsule())
                        .foregroundStyle(on ? Tone.rose.color : .secondary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// Lays children out in rows, wrapping when a row is full. A child wider than
/// the row is offered the row's width, so its text wraps instead of running off.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    private func sizes(_ subviews: Subviews, _ width: CGFloat) -> [CGSize] {
        subviews.map { v in
            let natural = v.sizeThatFits(.unspecified)
            return natural.width <= width ? natural : v.sizeThatFits(ProposedViewSize(width: width, height: nil))
        }
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        var x: CGFloat = 0, y: CGFloat = 0, rowH: CGFloat = 0, maxX: CGFloat = 0
        for s in sizes(subviews, width) {
            if x > 0 && x + s.width > width { x = 0; y += rowH + spacing; rowH = 0 }
            x += s.width + spacing; rowH = max(rowH, s.height); maxX = max(maxX, x - spacing)
        }
        return CGSize(width: min(width, maxX), height: y + rowH)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX, y = bounds.minY, rowH: CGFloat = 0
        for (v, s) in zip(subviews, sizes(subviews, bounds.width)) {
            if x > bounds.minX && x + s.width > bounds.maxX { x = bounds.minX; y += rowH + spacing; rowH = 0 }
            v.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(s))
            x += s.width + spacing; rowH = max(rowH, s.height)
        }
    }
}
