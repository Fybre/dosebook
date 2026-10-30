import SwiftUI
import os
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

    /// Selects the whole text when the field takes focus, as a Mac field does, so a new number can simply be typed over it.
    func selectAllWhenFocused(_ focused: Bool) -> some View {
        #if os(iOS)
        onChange(of: focused) { _, now in
            guard now else { return }
            // After the caret has been placed by the tap, or the selection is undone by it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                UIApplication.shared.sendAction(#selector(UIResponder.selectAll(_:)), to: nil, from: nil, for: nil)
            }
        }
        #else
        self
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

#if os(macOS)
/// SwiftUI on the Mac sometimes queues a sheet's presentation on the main run loop without waking it, so the
/// dialog sits unshown until the next event (a click on the title bar, a window move) comes along. A few
/// wake-ups after each click or key press make sure queued work runs straight away. Harmless when not needed.
enum RunLoopNudge {
    static let log = Logger(subsystem: "me.fybre.dosebook", category: "nudge")

    @MainActor private static var installed = false

    @MainActor static func install() {
        guard !installed else { return }
        installed = true
        for name in [NSWindow.didMoveNotification, NSWindow.willMoveNotification, NSWindow.didBecomeKeyNotification,
                     NSWindow.didResignKeyNotification, NSWindow.didChangeOcclusionStateNotification, NSWindow.didUpdateNotification,
                     NSWindow.didChangeScreenNotification] where name != NSWindow.didUpdateNotification {
            NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { n in
                log.notice("window \(n.name.rawValue, privacy: .public)")
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: [.leftMouseUp, .rightMouseUp, .keyUp]) { event in
            log.notice("mouse/key up seen")
            for delay in [0.03, 0.12, 0.35, 0.9, 2.0] {
                DispatchQueue.main.asyncAfter(deadline: .now() + delay) { wake() }
            }
            return event
        }
    }

    /// An event of our own, which makes the event loop return and run what is queued; waking the run loop
    /// alone leaves it inside the wait for the next event.
    @MainActor private static func wake() {
        log.notice("wake")
        CFRunLoopWakeUp(CFRunLoopGetMain())
        // What moving the window sets going: a layout and display pass of the windows we show.
        for window in NSApp.windows where window.isVisible {
            window.contentView?.layoutSubtreeIfNeeded()
            window.displayIfNeeded()
        }
        CATransaction.flush()
        // Moving a window runs the loop in its tracking mode; work queued only for a mode other than the
        // default waits for that. A short turn of each lets it through.
        for mode in [RunLoop.Mode.eventTracking, .modalPanel] {
            _ = RunLoop.main.run(mode: mode, before: Date())
        }
        if let e = NSEvent.otherEvent(with: .applicationDefined, location: .zero, modifierFlags: [], timestamp: 0,
                                      windowNumber: 0, context: nil, subtype: 0, data1: 0, data2: 0) {
            NSApp.postEvent(e, atStart: false)
        }
    }
}
#endif
