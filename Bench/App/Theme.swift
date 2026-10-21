import SwiftUI
import BenchCore

/// The original's six tones, as SwiftUI colours. System colours, so they adapt to dark mode.
extension Tone {
    var color: Color {
        switch self {
        case .mint: .teal
        case .grape: .purple
        case .tangerine: .orange
        case .sky: .blue
        case .rose: .pink
        case .leaf: .green
        case .neutral: .secondary
        case .muted: Color(.tertiaryLabel)
        }
    }
}

extension ProfileTone {
    var color: Color { (Tone(rawValue: rawValue) ?? .mint).color }
}

extension BandTone {
    var color: Color { (Tone(rawValue: rawValue) ?? .neutral).color }
}

extension EvidenceLevel {
    var tone: Tone {
        switch self {
        case .approved: .leaf
        case .clinical: .sky
        case .preliminary: .grape
        case .preclinical: .tangerine
        default: .rose
        }
    }
}

/// A small capsule label, the original's `Pill`.
struct Pill: View {
    var text: String
    var tone: Tone = .neutral
    var body: some View {
        Text(text)
            .font(.caption2.weight(.semibold))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(tone.color.opacity(0.15), in: Capsule())
            .foregroundStyle(tone.color)
    }
}

extension View {
    /// The card look used on Today: grouped background, rounded.
    func card() -> some View {
        padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
