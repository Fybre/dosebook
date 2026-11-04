import SwiftUI

/// A row that stacks its parts when the text size is one of the accessibility sizes, where
/// side by side leaves each part a sliver and breaks words in the middle.
struct AdaptiveStack<Content: View>: View {
    @Environment(\.dynamicTypeSize) private var typeSize
    var alignment: VerticalAlignment = .center
    var spacing: CGFloat = 8
    @ViewBuilder var content: Content

    var body: some View {
        let layout = typeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(alignment: alignment, spacing: spacing))
        layout { content }
    }
}
