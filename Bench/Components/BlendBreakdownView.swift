import SwiftUI
import BenchCore

/// What each component of a blend dose delivers, against its own standalone range.
struct BlendBreakdownView: View {
    var blend: Peptide
    var doseMcg: Double
    var resolve: (String) -> Peptide?
    var dosesPerWeek: Double?
    var compact = false

    var body: some View {
        let parts = decomposeDose(blend, doseMcg, resolve: resolve, dosesPerWeek: dosesPerWeek)
        if !parts.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, p in row(p) }
                if let summary = describeBlendDose(parts) {
                    Text(summary).font(.footnote).foregroundStyle(parts.contains { $0.relativeToTypical == .above } ? Tone.rose.color : .secondary)
                }
            }
        }
    }

    private func row(_ p: ComponentDose) -> some View {
        let (tone, label): (Tone, String) = switch p.relativeToTypical {
        case .within: (.leaf, "in usual range")
        case .above: (.rose, "above usual")
        case .below: (.neutral, "below usual")
        default: (.neutral, "no range known")
        }
        return VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                Text(formatDose(p.mcg)).font(.footnote.monospacedDigit().bold())
                Text(p.name).font(.footnote)
                if p.fraction < 1 { Text(t("blend_share_of", ["share": .string(percent(p.fraction))])).font(.caption2).foregroundStyle(.secondary) }
                Spacer(minLength: 4)
                Pill(text: label, tone: tone)
            }
            Group {
                if p.comparedOn == .weekly, let w = p.weeklyMcg {
                    Text(t("blend_weekly_vs", ["mine": .string(formatDose(w)), "low": .string(formatDose(p.typicalWeeklyLowMcg ?? 0)), "high": .string(formatDose(p.typicalWeeklyHighMcg ?? 0))])
                         + (p.typicalFrequency.map { " (\($0))" } ?? ""))
                } else if let low = p.typicalLowMcg {
                    Text(t("blend_usually_per_dose", ["low": .string(formatDose(low)), "high": .string(formatDose(p.typicalHighMcg ?? low))]) + (p.typicalFrequency.map { ", \($0)" } ?? ""))
                } else {
                    Text(t("blend_no_standalone_range"))
                }
            }
            .font(.caption).foregroundStyle(.secondary)
            if !compact {
                Text(p.peptide?.halfLifeHours.map { "half-life \(formatHalfLife($0))" } ?? "no published half-life").font(.caption2).foregroundStyle(.tertiary)
            }
        }
    }
}
