import SwiftUI
import BenchCore

/// A number field that can be emptied: the text as typed is shown for as long
/// as it still means the number held (`shownValue` in BenchCore), so a field
/// showing 0 can be cleared and typing 250 does not give 0250.
struct NumberField: View {
    var title: String
    @Binding var value: Double
    var suffix: String? = nil
    var range: ClosedRange<Double>? = nil
    @State private var draft: String?
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: Binding(
                get: { shownValue(draft, value) },
                set: { text in
                    draft = text
                    let n = Double(text.replacingOccurrences(of: ",", with: ".")) ?? (text.isEmpty ? 0 : value)
                    value = range.map { min(max(n, $0.lowerBound), $0.upperBound) } ?? n
                }))
                .decimalKeyboard()
                .multilineTextAlignment(.trailing)
                .focused($focused)
                .monospacedDigit()
            if let suffix { Text(suffix).foregroundStyle(.secondary) }
        }
        .onChange(of: focused) { _, f in if !f { draft = nil } }
    }
}

/// A labelled row holding a `NumberField`.
struct NumberRow: View {
    var label: String
    @Binding var value: Double
    var suffix: String? = nil
    var range: ClosedRange<Double>? = nil
    var body: some View {
        LabeledContent(label) { NumberField(title: label, value: $value, suffix: suffix, range: range).frame(maxWidth: 160) }
    }
}

/// An "HH:mm" string edited as a time.
struct TimeField: View {
    var label: String
    @Binding var time: String

    var body: some View {
        DatePicker(label, selection: Binding(
            get: { Date(millis: atTimeOfDay(startOfLocalDay(nowMillis()), time)) },
            set: { d in
                let c = LocalTime.calendar.dateComponents([.hour, .minute], from: d)
                time = String(format: "%02d:%02d", c.hour ?? 9, c.minute ?? 0)
            }), displayedComponents: .hourAndMinute)
    }
}

let WEEKDAY_KEYS = ["weekday_sun", "weekday_mon", "weekday_tue", "weekday_wed", "weekday_thu", "weekday_fri", "weekday_sat"]

/// Sunday-first toggles, indexed as `Date.getDay()` is.
struct WeekdayPicker: View {
    @Binding var days: [Int]
    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<7, id: \.self) { i in
                let on = days.contains(i)
                Button {
                    days = on ? days.filter { $0 != i } : (days + [i]).sorted()
                } label: {
                    Text(t(WEEKDAY_KEYS[i])).font(.caption.weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
                        .background(on ? Color.accentColor : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 8))
                        .foregroundStyle(on ? Color.white : Color.primary)
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(on ? .isSelected : [])
            }
        }
    }
}

/// "500 mcg a day, as 2 doses of 250 mcg at 07:00 and 19:00."
func describeSplit(_ dailyMcg: Double?, _ times: [String], peptide: Peptide? = nil) -> String? {
    let clean = times.filter { !$0.isEmpty }
    guard clean.count >= 2 else { return nil }
    let when = clean.sorted().joined(separator: " \(t("plan_and")) ")
    if let daily = dailyMcg, daily > 0 {
        return t("times_split_dose", ["daily": .string(doseLabel(daily, peptide)), "n": .number(Double(clean.count)),
                                      "each": .string(doseLabel(daily / Double(clean.count), peptide)), "when": .string(when)])
    }
    return t("times_split_plain", ["n": .number(Double(clean.count)), "when": .string(when)])
}

/// The times a dose day carries, up to six.
struct TimesOfDayEditor: View {
    @Binding var times: [String]
    var dailyMcg: Double?
    var peptide: Peptide? = nil

    var body: some View {
        ForEach(times.indices, id: \.self) { i in
            HStack {
                TimeField(label: times.count > 1 ? t("times_nth", ["n": .number(Double(i + 1)), "total": .number(Double(times.count))]) : t("times_label"),
                          time: Binding(get: { times[i] }, set: { times[i] = $0 }))
                if times.count > 1 {
                    Button(role: .destructive) { times.remove(at: i) } label: { Image(systemName: "minus.circle.fill") }
                        .buttonStyle(.borderless)
                        .accessibilityLabel(t("times_remove", ["time": .string(times[i])]))
                }
            }
        }
        if times.count < 6 {
            Button { times.append(nextFreeTime(times)) } label: { Label(t("times_add"), systemImage: "plus") }
        }
        if let split = describeSplit(dailyMcg, times, peptide: peptide) {
            Text(split).font(.footnote).foregroundStyle(.secondary)
        }
    }

    /// A new time twelve hours after the last, so it does not start as a duplicate.
    private func nextFreeTime(_ times: [String]) -> String {
        let last = times.last ?? "09:00"
        let h = (Int(last.prefix(2)) ?? 9)
        return String(format: "%02d:%@", (h + 12) % 24, String(last.suffix(2)))
    }
}

/// Grouped-card section header with an optional trailing badge.
struct CardHeader: View {
    var title: String
    var systemImage: String? = nil
    var badge: (String, Tone)? = nil
    var body: some View {
        HStack {
            if let systemImage { Image(systemName: systemImage) }
            Text(title.uppercased()).font(.caption.weight(.bold)).tracking(0.5)
            Spacer()
            if let badge { Pill(text: badge.0, tone: badge.1) }
        }
        .foregroundStyle(.secondary)
    }
}

/// A number that may be absent: an empty field means nil, not zero.
struct OptionalNumberField: View {
    var title: String
    @Binding var value: Double?
    var suffix: String? = nil
    @State private var text = ""
    @State private var loaded = false

    var body: some View {
        HStack(spacing: 6) {
            TextField(title, text: $text)
                .decimalKeyboard()
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onChange(of: text) { _, s in
                    // Filling the field from the value is not an edit.
                    if s == (value.map(jsNumberString) ?? "") { return }
                    let trimmed = s.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: ",", with: ".")
                    value = trimmed.isEmpty ? nil : Double(trimmed) ?? value
                }
            if let suffix { Text(suffix).foregroundStyle(.secondary) }
        }
        .onAppear {
            if !loaded { text = value.map(jsNumberString) ?? ""; loaded = true }
        }
    }
}

/// A labelled optional number, with a hint or error under it.
struct OptionalNumberRow: View {
    var label: String
    @Binding var value: Double?
    var suffix: String? = nil
    var hint: String? = nil
    var error: String? = nil
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(label) { OptionalNumberField(title: label, value: $value, suffix: suffix).frame(maxWidth: 160) }
            if let msg = error ?? hint { Text(msg).font(.caption).foregroundStyle(error != nil ? Tone.rose.color : .secondary) }
        }
    }
}

/// The unit an amount is held in, whatever the field shows.
enum MassBase { case mcg, mg }

private func toMcg(_ v: Double, _ base: MassBase) -> Double { base == .mcg ? v : v * 1000 }
private func fromMcg(_ mcg: Double, _ base: MassBase) -> Double { base == .mcg ? mcg : jsFixed(mcg / 1000, 9) }

/// Shown in mg when it is at least a milligram and reads cleanly there, else in mcg.
private func naturalUnit(_ mcg: Double?, _ base: MassBase) -> DoseUnit {
    guard let mcg, mcg > 0 else { return base == .mg ? .mg : .mcg }
    return mcg >= 1000 && jsFixed(mcg / 1000, 3) * 1000 == jsFixed(mcg, 6) ? .mg : .mcg
}

private func shown(_ mcg: Double, _ unit: DoseUnit) -> Double { unit == .mg ? jsFixed(mcg / 1000, 6) : jsFixed(mcg, 3) }
private func typed(_ n: Double, _ unit: DoseUnit) -> Double { unit == .mg ? jsFixed(n * 1000, 6) : n }

/// A tappable mcg/mg suffix.
struct UnitToggle: View {
    @Binding var unit: DoseUnit
    var body: some View {
        Button(unit.rawValue) { unit = unit == .mcg ? .mg : .mcg }
            .buttonStyle(.bordered).controlSize(.mini).font(.caption.weight(.semibold))
            .accessibilityLabel(t("log_switch_unit", ["unit": .string(unit == .mcg ? "mg" : "mcg")]))
    }
}

/// An amount entered in mcg or mg, held as `base` either way. Until it is typed
/// in or toggled, the unit follows the value (a prefilled 5000 mcg reads 5 mg);
/// from then on it stays put, so typing 1000 in mcg does not jump to mg.
struct AmountRow: View {
    var label: String
    @Binding var value: Double
    var base: MassBase = .mcg
    /// In `base`.
    var range: ClosedRange<Double>? = nil
    @State private var unit: DoseUnit?

    var body: some View {
        let u = unit ?? naturalUnit(toMcg(value, base), base)
        LabeledContent(label) {
            HStack(spacing: 6) {
                NumberField(title: label, value: Binding(
                    get: { shown(toMcg(value, base), u) },
                    set: { n in
                        if unit == nil { unit = u }
                        let v = fromMcg(typed(n, u), base)
                        value = range.map { min(max(v, $0.lowerBound), $0.upperBound) } ?? v
                    }))
                    .id(u)
                UnitToggle(unit: Binding(get: { u }, set: { unit = $0 }))
            }
            .frame(maxWidth: 190)
        }
    }
}

/// An amount that may be absent; empty means nil, not zero.
struct OptionalAmountRow: View {
    var label: String
    @Binding var value: Double?
    var base: MassBase = .mcg
    var hint: String? = nil
    var error: String? = nil
    @State private var unit: DoseUnit?

    var body: some View {
        let u = unit ?? naturalUnit(value.map { toMcg($0, base) }, base)
        VStack(alignment: .leading, spacing: 4) {
            LabeledContent(label) {
                HStack(spacing: 6) {
                    OptionalNumberField(title: label, value: Binding(
                        get: { value.map { shown(toMcg($0, base), u) } },
                        set: { n in
                            if unit == nil { unit = u }
                            value = n.map { fromMcg(typed($0, u), base) }
                        }))
                        .id(u)
                    UnitToggle(unit: Binding(get: { u }, set: { unit = $0 }))
                }
                .frame(maxWidth: 190)
            }
            if let msg = error ?? hint { Text(msg).font(.caption).foregroundStyle(error != nil ? Tone.rose.color : .secondary) }
        }
    }
}

/// A dose for a compound that may be a blend. The value is always the whole blend
/// drawn, as stock and the syringe need it; for a blend it can be entered as each
/// part (or the first part of an uneven blend), with the other figure shown beneath.
struct DoseRow: View {
    var label: String
    @Binding var value: Double
    var peptide: Peptide?
    var range: ClosedRange<Double>? = nil
    var resolve: ((String) -> Peptide?)? = nil
    @AppStorage("bench.blendDoseByPart") private var byPart = true

    var body: some View {
        if let share = firstPartShare(peptide), share > 0, let parts = blendParts(peptide, 1000) {
            let even = parts.allSatisfy { abs($0.fraction - parts[0].fraction) < 1e-9 }
            let partLabel = even ? t("ios_dose_each_part") : parts[0].name
            VStack(alignment: .leading, spacing: 6) {
                AmountRow(label: byPart ? "\(label) · \(partLabel)" : "\(label) · \(t("ios_dose_whole_blend"))",
                          value: Binding(get: { byPart ? jsFixed(value * share, 6) : value },
                                         set: { value = byPart ? jsFixed($0 / share, 6) : $0 }),
                          range: range.map { byPart ? ($0.lowerBound * share)...($0.upperBound * share) : $0 })
                    .id(byPart)
                Picker(t("ios_dose_enter_as"), selection: $byPart) {
                    Text(partLabel).tag(true)
                    Text(t("ios_dose_whole_blend")).tag(false)
                }
                .pickerStyle(.segmented)
                if value > 0 {
                    Text(byPart ? t("ios_dose_is_blend", ["total": .string(formatDose(value)), "parts": .string(partsSentence(value))])
                                : t("ios_dose_is_parts", ["parts": .string(partsSentence(value))]))
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        } else {
            AmountRow(label: label, value: $value, range: range)
        }
    }

    private func partsSentence(_ total: Double) -> String {
        (blendParts(peptide, total, resolve: resolve) ?? []).map { "\(formatDose($0.mcg)) \($0.name)" }.joined(separator: " + ")
    }
}
