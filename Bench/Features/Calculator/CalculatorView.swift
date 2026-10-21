import SwiftUI
import BenchCore
import BenchStore

/// Reconstitution: vial, water and dose in; where to draw to out, on the barrel in your hand.
struct CalculatorView: View {
    @Environment(AppStore.self) private var store
    @State private var vialMg: Double = 10
    @State private var diluentMl: Double = 2
    @State private var doseMcg: Double = 500
    @State private var syringeId = "u100-0.5"
    @State private var peptideId = ""
    @State private var addingCompound = false
    @State private var choosingSyringe = false

    var body: some View {
        let syringe = syringeById(syringeId) ?? SYRINGES[2]
        let vialMcg = mgToMcg(vialMg)
        let draw = calculateDraw(vialMcg: vialMcg, diluentMl: diluentMl, doseMcg: doseMcg, syringe: syringe)
        let suggestions = Array(suggestDiluents(vialMcg, doseMcg, syringe).prefix(4))
        let valid = draw.volumeMl.isFinite && draw.volumeMl > 0
        let other: SyringeScale = syringe.scale == .u100 ? .u40 : .u100
        let scaleName = { (s: SyringeScale) in s == .u100 ? "U-100" : "U-40" }

        ScrollViewReader { proxy in
        List {
            Section { Text(t("calc_intro")).font(.subheadline).foregroundStyle(.secondary) }

            Section(t("calc_which_syringe")) {
                DisclosureGroup(isExpanded: $choosingSyringe) {
                    SyringePickerView(value: Binding(get: { syringeId }, set: { syringeId = $0; choosingSyringe = false }))
                } label: {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(syringe.label).font(.subheadline.bold())
                        Text(syringeDetail(syringe)).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if !choosingSyringe { MiniSyringe(spec: syringe) }
                FlowLayout(spacing: 6) {
                    Pill(text: t("calc_one_mark", ["ml": .string(trim(mlPerUnit(syringe.scale), 4))]), tone: syringe.scale == .u40 ? .rose : .sky)
                    Pill(text: t("calc_barrel_reads", ["max": .string(trim(capacityUnits(syringe), 1))]))
                    Pill(text: t("calc_marks_every", ["step": .string(trim(syringe.graduationUnits, 2))]))
                }
                if let note = syringe.note { Text(note).font(.caption).foregroundStyle(.secondary) }
                VStack(alignment: .leading, spacing: 4) {
                    CalloutText(t("calc_check_barrel"), bold: true)
                    CalloutText(t("calc_barrel_warning"))
                }
                .font(.footnote).callout(.tangerine)
            }

            Section {
                Picker(t("calc_peptide_optional"), selection: Binding(get: { peptideId }, set: apply)) {
                    Text(t("calc_choose_prefill")).tag("")
                    ForEach(store.data.allPeptides) { Text($0.name).tag($0.id) }
                }
                Button { addingCompound = true } label: { Label(t("add_compound_inline"), systemImage: "plus") }
                AmountRow(label: t("calc_vial_strength"), value: $vialMg, base: .mg, range: 0...100_000)
                NumberRow(label: t("calc_water_to_add"), value: $diluentMl, suffix: "mL", range: 0...1000)
                AmountRow(label: t("calc_dose_you_want"), value: $doseMcg, range: 0...100_000_000)
            } header: { Text(t("calc_vial_and_dose")) } footer: { Text("\(t("calc_peptide_hint")) \(t("calc_water_hint"))") }

            Section {
                if valid {
                    SyringeView(spec: syringe, units: draw.unitsRounded, ghostUnits: draw.units, overCapacity: draw.warnings.contains(.exceedsBarrel))
                    if draw.warnings.contains(.offGraduation) {
                        Text(t("calc_dashed_line", ["units": .string(trim(draw.units, 2))])).font(.caption).foregroundStyle(.blue).frame(maxWidth: .infinity)
                    }
                    Grid(alignment: .topLeading, horizontalSpacing: 16, verticalSpacing: 14) {
                        GridRow {
                            stat(t("calc_volume"), "\(trim(draw.volumeRoundedMl, 3)) mL", t("calc_volume_hint"), .tangerine)
                            stat(t("calc_scale_marks", ["scale": .string(scaleName(syringe.scale))]), trim(draw.unitsRounded, 2),
                                 t("calc_on_the_scale", ["range": .string(syringe.scale == .u100 ? "0 to 100" : "0 to 40")]), .neutral)
                        }
                        GridRow {
                            stat(t("calc_concentration"), formatConcentration(draw.concentrationMcgPerMl), t("calc_mcg_per_mark", ["mcg": .string(trim(draw.mcgPerGraduation, 2))]), .neutral)
                            stat(t("calc_doses_per_vial"), jsNumberString(draw.dosesPerVial), t("calc_at_each", ["dose": .string(formatDose(doseMcg))]), .sky)
                        }
                    }
                    if draw.warnings.contains(.offGraduation) {
                        Text("\(t("calc_settling_on", ["marks": .string(trim(draw.unitsRounded, 2))])) **\(formatDose(draw.deliveredMcg))**, \(draw.roundingErrorMcg > 0 ? t("calc_which_is_over") : t("calc_which_is_under")) **\(formatDose(abs(draw.roundingErrorMcg)))** (\(trim(abs(draw.roundingErrorPercent), 1))%).")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                    // The other barrel is never a guess.
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: "arrow.left.arrow.right").font(.caption).foregroundStyle(.tertiary)
                        Text("\(t("calc_same_volume_reads", ["ml": .string(formatMl(draw.volumeRoundedMl))])) **\(trim(draw.volumeRoundedMl * (other == .u100 ? 100 : 40), 2))** \(t("calc_marks_on_barrel", ["scale": .string(scaleName(other))]))")
                            .font(.footnote).foregroundStyle(.secondary)
                    }
                } else {
                    Text(t("calc_enter_to_see")).foregroundStyle(.secondary).frame(maxWidth: .infinity).padding(.vertical, 20)
                }
            } header: { Text(t("calc_draw_to_here")).id("draw") }

            if !draw.warnings.isEmpty {
                Section {
                    ForEach(draw.warnings, id: \.self) { w in
                        let copy = warningCopy(w)
                        VStack(alignment: .leading, spacing: 4) {
                            CalloutText(copy.title, bold: true)
                            CalloutText(copy.body)
                        }
                        .font(.footnote).callout(copy.danger ? .rose : .tangerine)
                    }
                }
            }

            if !suggestions.isEmpty {
                Section {
                    ForEach(suggestions, id: \.diluentMl) { s in
                        let active = abs(s.diluentMl - diluentMl) < 1e-9
                        Button { diluentMl = s.diluentMl } label: {
                            HStack(spacing: 10) {
                                Text("\(trim(s.diluentMl, 2)) mL").font(.subheadline.monospacedDigit()).frame(width: 64, alignment: .leading)
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(t("calc_marks_count", ["n": .string(trim(s.units, 2))])).font(.subheadline.monospacedDigit()).foregroundStyle(Tone.tangerine.color)
                                    Text("\(trim(s.concentrationMgPerMl, 3)) mg/mL · \(t("calc_mcg_per_mark_value", ["n": .string(trim(s.mcgPerGraduation, 2))]))")
                                        .font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer(minLength: 0)
                                if s.landsOnMark { Image(systemName: "checkmark").foregroundStyle(Tone.leaf.color).accessibilityLabel(t("calc_lands_on_mark")) }
                                if active { Pill(text: t("calc_current"), tone: .tangerine) }
                            }
                        }
                        .buttonStyle(.plain)
                    }
                } header: { Text(t("calc_cleaner_volumes")) } footer: { Text(t("calc_cleaner_desc")) }
            }

            Section(t("calc_how_worked_out")) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("concentration = \(jsNumberString(vialMg)) mg ÷ \(trim(diluentMl, 2)) mL = **\(trim(draw.concentrationMgPerMl, 4)) mg/mL**")
                    Text("volume = \(formatDose(doseMcg)) ÷ \(trim(draw.concentrationMgPerMl, 4)) mg/mL = **\(trim(draw.volumeMl, 4)) mL**")
                    Text("\(t("calc_marks_formula", ["volume": .string(trim(draw.volumeMl, 4)), "per": .string(trim(graduationMl(syringe), 4))])) **\(trim(draw.volumeMl / graduationMl(syringe), 2))**")
                }
                .font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(t("calc_displacement_note")).font(.footnote).foregroundStyle(.secondary)
            }

            Section {
                Label(t("calc_disclaimer"), systemImage: "exclamationmark.triangle").font(.footnote).foregroundStyle(.secondary)
            }
        }
        .debugAnchor(proxy)
        }
        .navigationTitle(t("calc_title"))
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: $addingCompound) { NavigationStack { CustomCompoundForm(onCreated: { apply($0.id) }) } }
    }

    private func stat(_ label: String, _ value: String, _ hint: String, _ tone: Tone) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            Text(value).font(.title3.bold().monospacedDigit()).foregroundStyle(tone == .neutral ? Color.primary : tone.color)
            Text(hint).font(.caption2).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func warningCopy(_ w: DrawWarning) -> (danger: Bool, title: String, body: String) {
        switch w {
        case .exceedsBarrel: (true, t("calc_warn_wont_fit"), t("calc_body_exceeds_barrel"))
        case .belowGraduation: (true, t("calc_warn_below_mark"), t("calc_body_below_graduation"))
        case .offGraduation: (false, t("calc_warn_between_marks"), t("calc_body_off_graduation"))
        case .lowVolume: (false, t("calc_warn_very_small"), t("calc_body_low_volume", ["n": .number(MIN_RELIABLE_UNITS)]))
        case .exceedsVial: (true, t("calc_warn_too_much"), t("calc_body_exceeds_vial"))
        }
    }

    /// Prefills the vial size and the middle of the first dose range.
    private func apply(_ id: String) {
        peptideId = id
        guard let p = store.data.peptide(id) else { return }
        if let first = p.vialSizesMg.first { vialMg = first }
        if let range = p.doseRanges.first {
            let mid = (range.lowMcg + range.highMcg) / 2
            doseMcg = mid >= 1000 ? jsFixed(mid / 1000, 3) * 1000 : jsFixed(mid, 1)
        }
    }
}
