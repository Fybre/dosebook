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
                .keyboardType(.decimalPad)
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
func describeSplit(_ dailyMcg: Double?, _ times: [String]) -> String? {
    let clean = times.filter { !$0.isEmpty }
    guard clean.count >= 2 else { return nil }
    let when = clean.sorted().joined(separator: " \(t("plan_and")) ")
    if let daily = dailyMcg, daily > 0 {
        return t("times_split_dose", ["daily": .string(formatDose(daily)), "n": .number(Double(clean.count)),
                                      "each": .string(formatDose(daily / Double(clean.count))), "when": .string(when)])
    }
    return t("times_split_plain", ["n": .number(Double(clean.count)), "when": .string(when)])
}

/// The times a dose day carries, up to six.
struct TimesOfDayEditor: View {
    @Binding var times: [String]
    var dailyMcg: Double?

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
        if let split = describeSplit(dailyMcg, times) {
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
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .monospacedDigit()
                .onChange(of: text) { _, s in
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
