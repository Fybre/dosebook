import SwiftUI

/// Whether the screen a view sits in is the one being shown. A tab that has been visited stays in the view
/// tree after another is chosen, and SwiftUI keeps laying it out, so a screen full of charts costs seconds
/// of work every time the window changes (a dialog opening, say). Charts draw nothing while their screen is
/// hidden: a blank space of the same height, put back the moment the tab is chosen again.
private struct ScreenActiveKey: EnvironmentKey { static let defaultValue = true }

extension EnvironmentValues {
    var screenActive: Bool {
        get { self[ScreenActiveKey.self] }
        set { self[ScreenActiveKey.self] = newValue }
    }
}

private struct ChartWhenActive: ViewModifier {
    @Environment(\.screenActive) private var active
    var height: CGFloat

    func body(content: Content) -> some View {
        if active { content } else { Color.clear.frame(height: height) }
    }
}

extension View {
    /// For a chart of a fixed height: shown only while its screen is.
    func chartWhenActive(height: CGFloat) -> some View { modifier(ChartWhenActive(height: height)) }
}
