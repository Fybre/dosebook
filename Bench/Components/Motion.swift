import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
#endif

/// Whether the person has asked the system to cut back on movement.
@MainActor var reduceMotionOn: Bool {
    #if os(macOS)
    NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    #else
    UIAccessibility.isReduceMotionEnabled
    #endif
}

/// `withAnimation`, except that it changes things at once when Reduce Motion is on.
@MainActor func withMotion<T>(_ animation: Animation? = .default, _ body: () throws -> T) rethrows -> T {
    reduceMotionOn ? try body() : try withAnimation(animation, body)
}
