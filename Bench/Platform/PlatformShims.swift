import SwiftUI
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

// The few places iOS and macOS differ in name only, so views read the same on both.

extension View {
    /// A compact title, where the platform has a choice of title sizes.
    func inlineTitle() -> some View {
        #if os(iOS)
        navigationBarTitleDisplayMode(.inline)
        #else
        self
        #endif
    }

    /// The number pad, where there is an on-screen keyboard.
    func decimalKeyboard() -> some View {
        #if os(iOS)
        keyboardType(.decimalPad)
        #else
        self
        #endif
    }

    /// A scroll view's content held to exactly its width, so a chart a fraction of a
    /// point too wide cannot let the page slide sideways under a finger. The Mac has
    /// no such slide, and there the pin fed back through the window's size and the
    /// readable-width margins until the content was thousands of points wide.
    func pinnedToScrollWidth() -> some View {
        #if os(iOS)
        containerRelativeFrame(.horizontal)
        #else
        frame(maxWidth: .infinity)
        #endif
    }

    /// A row's actions: swiped to on iOS, a right-click menu on the Mac, where rows
    /// do not swipe.
    func rowActions<A: View>(@ViewBuilder _ actions: () -> A) -> some View {
        #if os(iOS)
        swipeActions(content: actions)
        #else
        contextMenu(menuItems: actions)
        #endif
    }

    /// For a field already beside its label: the Mac's forms otherwise print the
    /// field's own title too ("Dose  Dose 0 mcg").
    func fieldTitleHidden() -> some View {
        #if os(macOS)
        labelsHidden()
        #else
        self
        #endif
    }

    /// One look for every screen's title bar on the Mac: no grey band, which it
    /// otherwise draws only when content starts right under it (Settings, the table).
    func plainTitleBar() -> some View {
        #if os(macOS)
        toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        #else
        self
        #endif
    }

    /// Capitals as typed, for lot numbers.
    func capitalisedCharacters() -> some View {
        #if os(iOS)
        textInputAutocapitalization(.characters)
        #else
        self
        #endif
    }
}

#if canImport(UIKit)
typealias PlatformImage = UIImage
#else
typealias PlatformImage = NSImage
#endif

extension PlatformImage {
    /// The pixels, for Vision.
    var pixels: CGImage? {
        #if canImport(UIKit)
        cgImage
        #else
        cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
}

/// Where the system keeps this app's notification settings.
@MainActor var notificationSettingsURL: URL? {
    #if os(iOS)
    URL(string: UIApplication.openNotificationSettingsURLString)
    #else
    URL(string: "x-apple.systempreferences:com.apple.Notifications-Settings.extension")
    #endif
}

#if os(macOS)
/// iOS's names for the system colours the views use, as their nearest Mac colours.
extension NSColor {
    static var separator: NSColor { .separatorColor }
    static var tertiaryLabel: NSColor { .tertiaryLabelColor }
    static var systemBackground: NSColor { .textBackgroundColor }
    static var systemGroupedBackground: NSColor { .windowBackgroundColor }
    static var secondarySystemGroupedBackground: NSColor { .controlBackgroundColor }
}
#endif

/// A list of sections. One name for the screens' lists, so the Mac can be given
/// its own look in one place. (A grouped form was tried there: it centres itself in
/// a narrow column, and the settings screen drew nothing inside one.)
struct GroupedList<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        List { content }.listStyle(.inset)
        #else
        List { content }
        #endif
    }
}

/// A section's footer. The Mac's lists give a footer one line and cut the rest off,
/// so there the same text is shown by `FooterRow` as the section's last row instead.
struct FooterWrap<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        EmptyView()
        #else
        content
        #endif
    }
}

/// A section's footer text as its last row, on the Mac only; see `FooterWrap`.
struct FooterRow<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        #if os(macOS)
        content
            .font(.caption)
            .foregroundStyle(.secondary)
            .listRowSeparator(.hidden)
        #endif
    }
}
