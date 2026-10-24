import SwiftUI

/// The widest a screen's content goes, so lines stay readable on iPad.
let READABLE_WIDTH: CGFloat = 720

private struct ReadableWidth: ViewModifier {
    var limit: CGFloat
    @State private var width: CGFloat = 0

    /// Nil keeps the system's own margins, as on iPhone and in narrow windows.
    /// The Mac's lists take no notice of content margins, so the Mac keeps them
    /// everywhere and every screen fills the window alike.
    private var margin: CGFloat? {
        #if os(macOS)
        nil
        #else
        width > limit + 80 ? (width - limit) / 2 : nil
        #endif
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.horizontal, margin, for: .scrollContent)
            // The margins must not count towards the minimum size: on the Mac a window
            // grows to fit its content, the margins grow with the window, and round it went.
            .frame(minWidth: 0, maxWidth: .infinity)
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { width = $0 }
    }
}

extension View {
    /// On a wide screen, centres a List or ScrollView's content at a readable
    /// width. Put it on the scroll view itself, before any `.sheet`, so sheets
    /// keep their own margins.
    func readableWidth(_ limit: CGFloat = READABLE_WIDTH) -> some View { modifier(ReadableWidth(limit: limit)) }
}
