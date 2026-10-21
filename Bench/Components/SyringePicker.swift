import SwiftUI
import BenchCore

private func mlLabel(_ ml: Double) -> String { ml == ml.rounded(.towardZero) ? jsNumberString(ml) : jsToFixed(ml, 1) }

func marksLabel(_ spec: SyringeSpec) -> String {
    if spec.graduationUnits == 0.5 { return t("marks_half_unit") }
    if spec.graduationUnits == 1 { return t("marks_one_unit") }
    return t("marks_n_unit", ["n": .number(spec.graduationUnits)])
}

func syringeDetail(_ spec: SyringeSpec) -> String {
    t("syringe_detail", ["scale": .string(spec.scale == .u100 ? "U-100" : "U-40"), "units": .number(capacityUnits(spec)), "marks": .string(marksLabel(spec))])
}

/// An empty barrel, plunger home, so the picker shows the object in your hand.
struct MiniSyringe: View {
    var spec: SyringeSpec
    var body: some View {
        GeometryReader { geo in
            let rod = 14.0, padL = rod + 10, needle = 16.0, h = 38.0
            let barrelW = max(40, geo.size.width - padL - needle - 8)
            let scale = barrelTicks(spec, barrelW, minSpacingPx: 2, allowMagnify: true)
            Canvas { ctx, _ in
                let l = padL, r = padL + barrelW, mid = h / 2 + 2
                ctx.fill(Path(roundedRect: CGRect(x: l - 4 - rod, y: mid - 2.5, width: rod, height: 5), cornerRadius: 1), with: .color(Color(.separator)))
                ctx.fill(Path(roundedRect: CGRect(x: l - 9 - rod, y: mid - 10, width: 6, height: 20), cornerRadius: 1.2), with: .color(Color(.tertiaryLabel)))
                ctx.fill(Path(roundedRect: CGRect(x: l - 4, y: 0, width: 4, height: h + 2), cornerRadius: 1.2), with: .color(Color(.tertiaryLabel)))
                let barrel = Path(roundedRect: CGRect(x: l, y: 2, width: barrelW, height: h - 2), cornerRadius: 2)
                ctx.fill(barrel, with: .color(Color(.tertiarySystemFill)))
                ctx.stroke(barrel, with: .color(Color(.separator)), lineWidth: 1.1)
                for tick in scale.ticks {
                    let x = r - tick.fraction * barrelW
                    var p = Path(); p.move(to: CGPoint(x: x, y: 4)); p.addLine(to: CGPoint(x: x, y: tick.major ? 15 : 9))
                    ctx.stroke(p, with: .color(.primary.opacity(tick.major ? 0.8 : 0.32)), lineWidth: tick.major ? 1.1 : 0.6)
                    if tick.major && tick.units > 0 && x > l + 8 {
                        ctx.draw(Text(jsNumberString(tick.units)).font(.system(size: 7, design: .monospaced)).foregroundColor(.secondary), at: CGPoint(x: x, y: h - 7))
                    }
                }
                var tip = Path()
                tip.move(to: CGPoint(x: r, y: mid - 4)); tip.addLine(to: CGPoint(x: r + 8, y: mid)); tip.addLine(to: CGPoint(x: r, y: mid + 4)); tip.closeSubpath()
                ctx.fill(tip, with: .color(Color(.tertiaryLabel)))
                var n = Path(); n.move(to: CGPoint(x: r + 8, y: mid)); n.addLine(to: CGPoint(x: r + needle + 6, y: mid))
                ctx.stroke(n, with: .color(.secondary), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
            }
            .overlay(alignment: .bottomLeading) {
                if scale.magnified { Text("first \(jsNumberString(scale.shownUnits)) units").font(.system(size: 7)).foregroundStyle(.tertiary).padding(.leading, padL + 2) }
            }
        }
        .frame(height: 42)
        .accessibilityHidden(true)
    }
}

/// Pictures rather than a list, because the question is which object is in your hand.
struct SyringePickerView: View {
    @Binding var value: String
    var allowUnset = false

    var body: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 260), spacing: 8)], spacing: 8) {
            if allowUnset { option(id: "", title: t("syringe_ask_each_time"), detail: t("syringe_unset_detail"), spec: nil) }
            ForEach(SYRINGES) { s in option(id: s.id, title: "\(mlLabel(s.capacityMl)) mL", detail: syringeDetail(s), spec: s) }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(t("syringe_label"))
    }

    private func option(id: String, title: String, detail: String, spec: SyringeSpec?) -> some View {
        let active = value == id
        return Button { value = id } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack {
                    Text(title).font(.subheadline.bold())
                    Spacer()
                    if active { Image(systemName: "checkmark").font(.caption.bold()).foregroundStyle(Color.accentColor) }
                }
                Text(detail).font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.leading)
                if let spec { MiniSyringe(spec: spec) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(active ? Color.accentColor.opacity(0.12) : Color(.tertiarySystemFill), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(active ? Color.accentColor : .clear, lineWidth: 1.5))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(active ? [.isSelected] : [])
    }
}
