import SwiftUI
import BenchCore

/// The body figure with tappable injection sites, drawn from the original's
/// path in its own 200 × 240 coordinate space (`BODY`/`SITE_DOTS` in BenchCore).
struct SiteMapView: View {
    var logs: [DoseLog]
    var selected: Set<InjectionSite> = []
    var allowed: [InjectionSite]? = nil
    /// Pin several sites (Plan) rather than pick one (logging).
    var multi = false
    var showLegend = true
    var onSelect: ((InjectionSite) -> Void)?
    var nowMs: Millis = nowMillis()

    private var usage: [InjectionSite: SiteUsage] {
        Dictionary(siteUsage(logs, nowMs).map { ($0.site, $0) }, uniquingKeysWith: { a, _ in a })
    }

    private var suggestion: InjectionSite? {
        multi ? nil : siteChoices(logs, nowMs, allowed: allowed, limit: 1).first?.site
    }

    var body: some View {
        VStack(spacing: 8) {
            GeometryReader { geo in
                let s = min(geo.size.width / 200, geo.size.height / 240)
                let ox = (geo.size.width - 200 * s) / 2
                ZStack(alignment: .topLeading) {
                    BodyShape().fill(Color(.tertiarySystemFill))
                    BodyShape().stroke(Color(.separator), lineWidth: 1.5)
                    ForEach(SITE_DOTS, id: \.id.rawValue) { dot in
                        dotView(dot)
                            .position(x: dot.cx * s, y: dot.cy * s)
                    }
                }
                .frame(width: 200 * s, height: 240 * s)
                .offset(x: ox)
            }
            .aspectRatio(200.0 / 240.0, contentMode: .fit)
            .frame(maxWidth: 220)
            if showLegend { legend }
        }
    }

    @ViewBuilder private func dotView(_ dot: SiteDot) -> some View {
        let u = usage[dot.id]
        let fill = 1 - (u?.rested ?? 1)
        let isSelected = selected.contains(dot.id)
        let isSuggested = !isSelected && dot.id == suggestion
        let offPlan = allowed.map { !$0.isEmpty && !$0.contains(dot.id) } ?? false
        let label = "\(siteLabel(dot.id)). " + (u?.lastUsedAt.map { t("site_last_used", ["when": .string(relativeTime($0, nowMs: nowMs))]) } ?? t("site_never_used"))
        Button { onSelect?(dot.id) } label: {
            ZStack {
                if isSuggested {
                    Circle().strokeBorder(Color.accentColor.opacity(0.6), style: StrokeStyle(lineWidth: 1, dash: [3, 3])).frame(width: 26, height: 26)
                }
                Circle()
                    .fill(isSelected && !multi ? Color.primary : (fill > 0.05 ? Color.orange.opacity(fill * 0.88) : Color(.systemBackground)))
                Circle().strokeBorder(isSelected ? (multi ? Color.accentColor : Color.primary) : (isSuggested ? Color.accentColor : (fill > 0.05 ? Color.orange : Color(.separator))),
                                      lineWidth: isSelected || isSuggested ? 2.2 : 1.4)
                if isSelected && !multi { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(Color(.systemBackground)) }
                if isSelected && multi { Circle().fill(Color.accentColor).frame(width: 8, height: 8) }
                if !isSelected, let n = u?.recentCount, n > 0 {
                    Text("\(n)").font(.system(size: 8, design: .monospaced)).foregroundStyle(fill > 0.5 ? Color(.systemBackground) : .secondary)
                }
            }
            .frame(width: 16, height: 16)
            .contentShape(Circle().inset(by: -8))
        }
        .buttonStyle(.plain)
        .disabled(onSelect == nil)
        .opacity(offPlan ? 0.35 : 1)
        .accessibilityLabel(label)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var legend: some View {
        HStack(spacing: 12) {
            if multi {
                legendItem(Circle().strokeBorder(Color.accentColor, lineWidth: 2), t("site_legend_pinned"))
                legendItem(Circle().strokeBorder(Color(.separator)), t("site_legend_not_pinned"))
            } else {
                legendItem(Circle().fill(Color.orange), t("site_legend_used_recently"))
                legendItem(Circle().strokeBorder(Color(.separator)), t("site_legend_rested"))
                legendItem(Circle().strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 1, dash: [2, 2])), t("site_legend_suggested"))
            }
        }
        .font(.caption2).foregroundStyle(.secondary)
    }

    private func legendItem(_ shape: some View, _ text: String) -> some View {
        HStack(spacing: 4) { shape.frame(width: 9, height: 9); Text(text) }
    }
}

/// The original's body outline, scaled from its 200 × 240 viewBox.
struct BodyShape: Shape {
    func path(in rect: CGRect) -> Path {
        let s = min(rect.width / 200, rect.height / 240)
        func p(_ x: Double, _ y: Double) -> CGPoint { CGPoint(x: x * s, y: y * s) }
        var path = Path()
        path.addEllipse(in: CGRect(x: 85 * s, y: 7 * s, width: 30 * s, height: 30 * s))
        path.move(to: p(100, 40))
        path.addCurve(to: p(68, 52), control1: p(88, 40), control2: p(72, 44))
        path.addLine(to: p(62, 82)); path.addLine(to: p(72, 85)); path.addLine(to: p(74, 62)); path.addLine(to: p(74, 118))
        path.addCurve(to: p(78, 162), control1: p(74, 128), control2: p(76, 136))
        path.addLine(to: p(88, 162)); path.addLine(to: p(90, 118)); path.addLine(to: p(110, 118)); path.addLine(to: p(112, 162))
        path.addLine(to: p(122, 162))
        path.addCurve(to: p(126, 118), control1: p(124, 136), control2: p(126, 128))
        path.addLine(to: p(126, 62)); path.addLine(to: p(128, 85)); path.addLine(to: p(138, 82)); path.addLine(to: p(132, 52))
        path.addCurve(to: p(100, 40), control1: p(128, 44), control2: p(112, 40))
        path.closeSubpath()
        path.move(to: p(78, 162))
        path.addCurve(to: p(78, 230), control1: p(76, 178), control2: p(76, 200))
        path.addLine(to: p(88, 230))
        path.addCurve(to: p(90, 162), control1: p(90, 200), control2: p(90, 178))
        path.closeSubpath()
        path.move(to: p(110, 162))
        path.addCurve(to: p(112, 230), control1: p(110, 178), control2: p(110, 200))
        path.addLine(to: p(122, 230))
        path.addCurve(to: p(122, 162), control1: p(124, 200), control2: p(124, 178))
        path.closeSubpath()
        return path
    }
}
