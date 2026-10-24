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
