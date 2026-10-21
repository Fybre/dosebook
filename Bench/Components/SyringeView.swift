import SwiftUI
import BenchCore

/// The barrel, drawn to its real marks. Ticks come from `barrelTicks`, judged at
/// the width actually on screen, and a barrel too fine for it is magnified and
/// says so rather than thinned.
struct SyringeView: View {
    var spec: SyringeSpec
    var units: Double
    var ghostUnits: Double? = nil
    var overCapacity = false

    var body: some View {
        GeometryReader { geo in
            let w = geo.size.width
            let s = w / 640
            let barrelL = 96 * s, barrelR = 494 * s, barrelT = 34 * s, barrelB = 92 * s
            let barrelW = barrelR - barrelL, mid = (barrelT + barrelB) / 2
            let scale = barrelTicks(spec, barrelW, allowMagnify: true)
            let shown = scale.shownUnits
            let safe = units.isFinite ? max(0, units) : 0
            let fraction = shown > 0 ? min(1, safe / shown) : 0
            let plungerX = barrelR - fraction * barrelW
            Canvas { ctx, _ in
                let line = Color(.separator), faint = Color(.tertiaryLabel)
                ctx.fill(Path(roundedRect: CGRect(x: plungerX - 78 * s, y: mid - 4 * s, width: 80 * s, height: 8 * s), cornerRadius: s), with: .color(line))
                ctx.fill(Path(roundedRect: CGRect(x: plungerX - 84 * s, y: mid - 21 * s, width: 9 * s, height: 42 * s), cornerRadius: 2 * s), with: .color(faint))
                let barrel = Path(roundedRect: CGRect(x: barrelL, y: barrelT, width: barrelW, height: barrelB - barrelT), cornerRadius: 2 * s)
                ctx.fill(barrel, with: .color(Color(.tertiarySystemFill)))
                ctx.stroke(barrel, with: .color(line), lineWidth: 1.5)
                if barrelR - plungerX > 0.5 {
                    ctx.fill(Path(CGRect(x: plungerX, y: barrelT + 1.5 * s, width: barrelR - plungerX, height: barrelB - barrelT - 3 * s)),
                             with: .linearGradient(Gradient(colors: overCapacity ? [.pink, .pink] : [Color.accentColor.opacity(0.65), Color.accentColor]),
                                                   startPoint: CGPoint(x: 0, y: barrelT), endPoint: CGPoint(x: 0, y: barrelB)))
                }
                ctx.fill(Path(roundedRect: CGRect(x: plungerX - 3 * s, y: barrelT + s, width: 9 * s, height: barrelB - barrelT - 2 * s), cornerRadius: 1.5 * s), with: .color(faint))
                for tick in scale.ticks {
                    let x = barrelR - tick.fraction * barrelW
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: barrelT + s))
                    p.addLine(to: CGPoint(x: x, y: barrelT + (tick.major ? 17 : 9) * s))
                    ctx.stroke(p, with: .color(.primary.opacity(tick.major ? 0.75 : 0.35)), lineWidth: tick.major ? 1.4 : 0.8)
                    if tick.major && tick.units > 0 && x > barrelL + 13 * s {
                        ctx.draw(Text(jsNumberString(tick.units)).font(.system(size: max(8, 13 * s), design: .monospaced)).foregroundColor(.secondary),
                                 at: CGPoint(x: x, y: barrelB - 12 * s))
                    }
                }
                if let ghost = ghostUnits, abs(ghost - safe) > 1e-6, shown > 0 {
                    let x = barrelR - min(1, ghost / shown) * barrelW
                    var p = Path()
                    p.move(to: CGPoint(x: x, y: barrelT - 7 * s)); p.addLine(to: CGPoint(x: x, y: barrelB + 7 * s))
                    ctx.stroke(p, with: .color(.blue), style: StrokeStyle(lineWidth: 1.5, dash: [3, 3]))
                }
                var hub = Path()
                hub.move(to: CGPoint(x: barrelR, y: barrelT + 6 * s)); hub.addLine(to: CGPoint(x: barrelR + 26 * s, y: mid - 7 * s))
                hub.addLine(to: CGPoint(x: barrelR + 26 * s, y: mid + 7 * s)); hub.addLine(to: CGPoint(x: barrelR, y: barrelB - 6 * s)); hub.closeSubpath()
                ctx.fill(hub, with: .color(line))
                ctx.fill(Path(roundedRect: CGRect(x: barrelR + 26 * s, y: mid - 6 * s, width: 22 * s, height: 12 * s), cornerRadius: 2 * s), with: .color(faint))
                var needle = Path()
                needle.move(to: CGPoint(x: barrelR + 48 * s, y: mid)); needle.addLine(to: CGPoint(x: w - 8 * s, y: mid))
                ctx.stroke(needle, with: .color(.secondary), style: StrokeStyle(lineWidth: 2.5, lineCap: .round))
                ctx.fill(Path(roundedRect: CGRect(x: barrelL - 5 * s, y: barrelT - 9 * s, width: 7 * s, height: barrelB - barrelT + 18 * s), cornerRadius: 2 * s), with: .color(line))
            }
            .overlay(alignment: .bottomLeading) {
                if scale.magnified {
                    Text("0–\(jsNumberString(shown)) of \(jsNumberString(capacityUnits(spec)))").font(.caption2).foregroundStyle(.secondary)
                }
            }
        }
        .aspectRatio(640.0 / 132.0, contentMode: .fit)
        .accessibilityElement()
        .accessibilityLabel(t("syringe_aria_showing", ["units": .string(jsToFixed(units, 1)), "capacity": .number(capacityUnits(spec)), "scale": .string(spec.scale == .u100 ? "U-100" : "U-40")]))
    }
}

/// A vial drawn with how much is left; sealed vials show their powder.
struct VialGlyph: View {
    var fraction: Double
    var state: VialState

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 32, size.height / 68)
            let f = max(0, min(1, fraction.isFinite ? fraction : 0))
            let empty = state == .finished || state == .discarded, onOrder = state == .onOrder
            ctx.fill(Path(roundedRect: CGRect(x: 8 * s, y: 2 * s, width: 16 * s, height: 7 * s), cornerRadius: s),
                     with: .color(empty || onOrder ? Color(.tertiaryLabel) : .orange))
            var body = Path()
            body.move(to: CGPoint(x: 11 * s, y: 13 * s)); body.addLine(to: CGPoint(x: 11 * s, y: 18 * s)); body.addLine(to: CGPoint(x: 5 * s, y: 24 * s))
            body.addLine(to: CGPoint(x: 5 * s, y: 62 * s)); body.addQuadCurve(to: CGPoint(x: 8 * s, y: 65 * s), control: CGPoint(x: 5 * s, y: 65 * s))
            body.addLine(to: CGPoint(x: 24 * s, y: 65 * s)); body.addQuadCurve(to: CGPoint(x: 27 * s, y: 62 * s), control: CGPoint(x: 27 * s, y: 65 * s))
            body.addLine(to: CGPoint(x: 27 * s, y: 24 * s)); body.addLine(to: CGPoint(x: 21 * s, y: 18 * s)); body.addLine(to: CGPoint(x: 21 * s, y: 13 * s)); body.closeSubpath()
            ctx.fill(body, with: .color(Color(.tertiarySystemFill)))
            ctx.stroke(body, with: .color(Color(.separator)), lineWidth: 1.2)
            if state == .sealed {
                ctx.fill(Path(roundedRect: CGRect(x: 6.2 * s, y: 52 * s, width: 19.6 * s, height: 11 * s), cornerRadius: s), with: .color(.primary.opacity(0.55)))
            } else if !onOrder, f > 0.01 {
                let h = 38 * f
                ctx.fill(Path(roundedRect: CGRect(x: 6.2 * s, y: (62 - h) * s, width: 19.6 * s, height: h * s), cornerRadius: s), with: .color(.orange.opacity(0.75)))
            }
        }
        .frame(width: 22, height: 46)
        .accessibilityHidden(true)
    }
}

/// A blister pack whose ten slots empty as tablets are taken.
struct PackGlyph: View {
    var fraction: Double
    var state: VialState

    var body: some View {
        Canvas { ctx, size in
            let s = min(size.width / 32, size.height / 68)
            let empty = state == .finished || state == .discarded, onOrder = state == .onOrder
            let left = empty || onOrder ? 0 : blisterDots(fraction, 10)
            let card = Path(roundedRect: CGRect(x: 3 * s, y: 5 * s, width: 26 * s, height: 60 * s), cornerRadius: 3 * s)
            if !onOrder { ctx.fill(card, with: .color(Color(.tertiarySystemFill))) }
            ctx.stroke(card, with: .color(Color(.separator)), lineWidth: 1.2)
            ctx.fill(Path(roundedRect: CGRect(x: 3 * s, y: 5 * s, width: 26 * s, height: 6 * s), cornerRadius: 3 * s), with: .color(empty || onOrder ? Color(.tertiaryLabel) : .orange))
            if state == .sealed {
                ctx.fill(Path(roundedRect: CGRect(x: 6 * s, y: 15 * s, width: 20 * s, height: 46 * s), cornerRadius: 2 * s), with: .color(.orange.opacity(0.85)))
            } else {
                for i in 0..<10 {
                    let col = i % 2
                    let full = i >= 10 - left
                    let r = CGRect(x: (11 + Double(col) * 10 - 3.9) * s, y: (13 + Double((i - col) / 2) * 11.5 - 3.9) * s, width: 7.8 * s, height: 7.8 * s)
                    if full { ctx.fill(Path(ellipseIn: r), with: .color(.orange.opacity(0.85))) }
                    else { ctx.stroke(Path(ellipseIn: r), with: .color(Color(.separator)), lineWidth: 1.2) }
                }
            }
        }
        .frame(width: 22, height: 46)
        .accessibilityHidden(true)
    }
}
