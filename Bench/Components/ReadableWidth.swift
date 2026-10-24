import SwiftUI

/// The widest a screen's content goes, so lines stay readable on iPad.
let READABLE_WIDTH: CGFloat = 720

/// For a List: on a wide screen, its rows centred at a readable width.
private struct ReadableWidth: ViewModifier {
    var limit: CGFloat
    /// The list's own width, and how much of each side something else covers
    /// (the iPad's sidebar sits over the list's leading edge in landscape).
    @State private var space = Space()

    struct Space: Equatable { var width: CGFloat = 0; var leading: CGFloat = 0; var trailing: CGFloat = 0 }

    /// Nil keeps the system's own margins, as on iPhone and in narrow windows.
    /// A list measures its margins from its own edges, under the sidebar, so the
    /// covered part is added back on. The Mac's lists ignore content margins, so it
    /// keeps the system's everywhere.
    private var margins: (leading: CGFloat, trailing: CGFloat)? {
        #if os(macOS)
        return nil
        #else
        guard space.width > limit + 80 else { return nil }
        let side = (space.width - limit) / 2
        return (space.leading + side, space.trailing + side)
        #endif
    }

    func body(content: Content) -> some View {
        content
            .contentMargins(.leading, margins?.leading, for: .scrollContent)
            .contentMargins(.trailing, margins?.trailing, for: .scrollContent)
            // The margins must not count towards the minimum size: on the Mac a window
            // grows to fit its content, the margins grow with the window, and round it went.
            .frame(minWidth: 0, maxWidth: .infinity)
            .onGeometryChange(for: Space.self) {
                Space(width: $0.size.width, leading: $0.safeAreaInsets.leading, trailing: $0.safeAreaInsets.trailing)
            } action: { space = $0 }
    }
}

extension View {
    /// On a wide screen, centres a List's content at a readable width. Put it on
    /// the list itself, before any `.sheet`, so sheets keep their own margins.
    /// A ScrollView page uses `pageWidth` instead.
    func readableWidth(_ limit: CGFloat = READABLE_WIDTH) -> some View { modifier(ReadableWidth(limit: limit)) }

    /// A ScrollView's page: exactly the visible width (`available`, measured on the
    /// scroll view), and no wider than `limit`, centred. Exactly the width because a
    /// chart a fraction of a point too wide let an iPhone page slide sideways; set
    /// rather than taken from the container, because beside the iPad's sidebar the
    /// container is the whole screen. The Mac fills the window.
    func pageWidth(_ available: CGFloat, limit: CGFloat = READABLE_WIDTH) -> some View {
        #if os(iOS)
        frame(maxWidth: limit).frame(width: available > 0 ? available : nil)
        #else
        frame(maxWidth: .infinity)
        #endif
    }
}
