import Foundation

/// The palette names the original's UI uses for status colours. The app maps
/// them onto SwiftUI colours; keeping the names here lets the pure modules say
/// which tone without knowing anything about drawing.
public enum Tone: String, Sendable, CaseIterable {
    case mint, grape, tangerine, sky, rose, leaf, neutral, muted
}
