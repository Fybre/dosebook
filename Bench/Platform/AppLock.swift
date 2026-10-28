import SwiftUI
import LocalAuthentication
import BenchCore
#if canImport(UIKit)
import UIKit
#endif

/// Face ID, Touch ID or the device passcode before Dosebook opens, and a blank
/// cover in the app switcher. Per device: kept in UserDefaults, not with the data.
///
/// If the device has nothing to unlock with (no passcode set), the lock lets
/// you in: refusing would lock your own records away behind something that
/// cannot be answered.
@MainActor @Observable
final class AppLock {
    static let shared = AppLock()

    static let enabledKey = "bench.appLock"
    static let delayKey = "bench.appLockDelay"

    private(set) var locked = false
    private(set) var authenticating = false
    private var phase: ScenePhase = .active
    private var backgroundedAt: Date?

    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }
    /// Seconds in the background before it asks again; 0 is every time.
    var delay: TimeInterval { UserDefaults.standard.double(forKey: Self.delayKey) }
    var coverVisible: Bool { enabled && (locked || phase != .active) }

    #if DEBUG
    /// `-lockPreview`: stays locked, without asking, for screenshots.
    private var preview: Bool { ProcessInfo.processInfo.arguments.contains("-lockPreview") }
    #endif

    /// Locked from the first moment, before anything is drawn.
    func launch() {
        guard enabled else { return }
        locked = true
        refreshCover()
    }

    func phaseChanged(_ new: ScenePhase) {
        phase = new
        guard enabled else { locked = false; refreshCover(); return }
        switch new {
        case .background:
            if backgroundedAt == nil { backgroundedAt = Date() }
        case .active:
            if let at = backgroundedAt {
                if Date().timeIntervalSince(at) >= delay { locked = true }
                backgroundedAt = nil
            }
            if locked && !authenticating { Task { await unlock() } }
        default: break
        }
        refreshCover()
    }

    func unlock() async {
        guard locked, !authenticating else { return }
        #if DEBUG
        if preview { return }
        #endif
        authenticating = true
        let ok = await Self.authenticate(reason: t("ios_lock_reason"))
        authenticating = false
        if ok { locked = false }
        refreshCover()
    }

    /// True when it was answered, or when there is nothing to answer it with.
    static func authenticate(reason: String) async -> Bool {
        let context = LAContext()
        var error: NSError?
        guard context.canEvaluatePolicy(.deviceOwnerAuthentication, error: &error) else { return true }
        return (try? await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: reason)) ?? false
    }

    /// Whether the device has a passcode or biometrics to lock with.
    static var available: Bool {
        var error: NSError?
        return LAContext().canEvaluatePolicy(.deviceOwnerAuthentication, error: &error)
    }

    /// Turns it on only after one successful unlock, so it cannot be set up to fail.
    func turnOn() async -> Bool {
        guard Self.available, await Self.authenticate(reason: t("ios_lock_reason")) else { return false }
        UserDefaults.standard.set(true, forKey: Self.enabledKey)
        return true
    }

    func turnOff() {
        UserDefaults.standard.set(false, forKey: Self.enabledKey)
        locked = false
        refreshCover()
    }

    // MARK: The cover

    private func refreshCover() {
        #if os(iOS)
        if coverVisible { CoverWindow.show() } else { CoverWindow.hide() }
        #endif
    }
}

/// What is shown over everything while locked, or while the app is out of sight.
struct LockCover: View {
    @State private var lock = AppLock.shared

    var body: some View {
        ZStack {
            Rectangle().fill(.background).ignoresSafeArea()
            VStack(spacing: 16) {
                Image(systemName: "lock.fill").font(.system(size: 44)).foregroundStyle(Color.accentColor)
                Text(t("ios_lock_locked")).font(.title3.weight(.semibold))
                if lock.locked && !lock.authenticating {
                    Button { Task { await lock.unlock() } } label: { Label(t("ios_lock_unlock"), systemImage: "lock.open.fill") }
                        .buttonStyle(.borderedProminent).controlSize(.large)
                }
            }
        }
    }
}

#if os(iOS)
/// A window of its own above the app's, so it covers an open sheet too.
@MainActor
private enum CoverWindow {
    private static var window: UIWindow?

    static func show() {
        if let window { window.isHidden = false; return }
        guard let scene = UIApplication.shared.connectedScenes.compactMap({ $0 as? UIWindowScene }).first else { return }
        let w = UIWindow(windowScene: scene)
        w.windowLevel = .alert + 1
        w.rootViewController = UIHostingController(rootView: LockCover())
        w.isHidden = false
        window = w
    }

    static func hide() { window?.isHidden = true }
}
#else
extension View {
    /// On the Mac the cover goes over the window's content. (A sheet that is open
    /// stays above it; sheets there belong to the window.)
    func appLockCover() -> some View {
        overlay { if AppLock.shared.coverVisible { LockCover() } }
    }
}
#endif
