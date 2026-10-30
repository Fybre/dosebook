import SwiftUI
import BenchCore
import BenchStore
import CoreData

#if os(macOS) && !LOCAL_ONLY
/// A Mac app has to ask for pushes itself. Even so, while the app sits in the background, development
/// builds often get no push, and a change from the phone shows up when the window next comes to the front.
final class MacAppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApplication.shared.registerForRemoteNotifications()
    }
}
#endif

@main
struct BenchApp: App {
    @State private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase
    #if os(macOS) && !LOCAL_ONLY
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) private var appDelegate
    #endif

    init() {
        let store = Bootstrap.makeStore()
        _store = State(initialValue: store)
        // Before launch finishes, so a button tapped on a reminder reaches the store.
        NotificationHandler.shared.install(store)
        // Locked before anything is drawn, when the lock is on.
        AppLock.shared.launch()
        // Doses logged from a widget or Shortcut, recorded as soon as the app can.
        LogInbox.apply = { [store] in WidgetSync.applyPending(store) }
        WidgetSync.applyPending(store)
        #if os(macOS)
        RunLoopNudge.install()
        #endif
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            Group {
                #if DEBUG && os(iOS)
                if ProcessInfo.processInfo.arguments.contains("-widgetPreview") { WidgetPreviewScreen() } else { RootView() }
                #else
                RootView()
                #endif
            }
                .environment(store)
                .tint(.accentColor)
                // Applied to the windows rather than with preferredColorScheme, which
                // does not reliably hand control back to the system.
                .onChange(of: store.data.settings.theme, initial: true) { _, theme in theme.apply() }
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                    store.reloadSoon()
                }
                #if os(macOS)
                .appLockCover()
                #endif
                .onChange(of: scenePhase, initial: true) { _, phase in
                    AppLock.shared.phaseChanged(phase)
                }
                .onChange(of: scenePhase, initial: true) { _, phase in
                    if phase == .active {
                        store.reload(); BackupFolder.runIfDue(store)
                        WidgetSync.applyPending(store)
                        // Bring all permitted Health readings in when Dosebook opens or returns.
                        Task {
                            _ = try? await HealthKitAdapter.pullWeight(into: store)
                            await HealthKitAdapter.pullVitals(into: store)
                        }
                    }
                }
                .task { BackupFolder.runIfDue(store) }
        }
        #if os(macOS)
        .defaultSize(width: 1280, height: 860)
        #endif
        .commands { BenchCommands() }
        #if os(macOS)
        // The Mac's own Settings window, under the app menu and ⌘,.
        Settings {
            NavigationStack { SettingsView() }
                .environment(store)
                .formStyle(.grouped)
                .frame(minWidth: 560, minHeight: 640)
        }
        #endif
    }
}

/// ⌘N logs a dose, the thing done most. On the Mac, New Window moves to ⇧⌘N.
struct BenchCommands: Commands {
    @Environment(\.openWindow) private var openWindow
    /// The front window's own "log a dose", so ⌘N opens one sheet, not one per window.
    @FocusedValue(\.logDose) private var logDoseHere

    var body: some Commands {
        #if os(macOS)
        CommandGroup(replacing: .newItem) {
            logDose
            Button(t("ios_new_window")) { openWindow(id: "main") }
                .keyboardShortcut("n", modifiers: [.command, .shift])
        }
        #else
        CommandGroup(after: .newItem) { logDose }
        #endif
    }

    private var logDose: some View {
        Button(t("log_new_dose")) { logDoseHere?.run() }
            .keyboardShortcut("n")
            .disabled(logDoseHere == nil)
    }
}

/// A window's "log a dose". Always equal to itself: what it does never changes
/// (it writes through the window's state), so a new closure each update must not
/// make the menu rebuild.
struct LogDoseAction: Equatable {
    let run: () -> Void
    static func == (_: LogDoseAction, _: LogDoseAction) -> Bool { true }
}

extension FocusedValues {
    /// Set by each window: go to Now and open Log a dose there.
    @Entry var logDose: LogDoseAction?
}

@MainActor
enum Bootstrap {
    static let containerId = "iCloud.me.fybre.dosebook"

    /// CloudKit when there is an iCloud account and the build is entitled; this
    /// device only otherwise. The choice is shown in Settings.
    static func makeStore() -> AppStore {
        if let lang = UserDefaults.standard.string(forKey: "bench.lang").flatMap(Lang.init(rawValue:)) { I18n.lang = lang }
        let args = ProcessInfo.processInfo.arguments
        #if DEBUG
        if let i = args.firstIndex(of: "-seedInjectly"), i + 1 < args.count {
            let store = AppStore(records: try! RecordStore(location: .memory), defaults: UserDefaults(suiteName: "bench-demo")!, rescueURL: nil)
            DemoData.seedInjectly(store, args[i + 1].split(separator: ",").map(String.init))
            return store
        }
        if args.contains("-demo") {
            let store = AppStore(records: try! RecordStore(location: .memory), defaults: UserDefaults(suiteName: "bench-demo")!, rescueURL: nil)
            DemoData.seed(store)
            if args.contains("-demoLarge") { DemoData.seedLarge(store) }
            if args.contains("-demoSameCompound") {
                // A second protocol for a compound already running, as in upstream issue #9.
                store.mutate { _ = $0.addProtocol(DoseProtocol(id: "", profileId: "", peptideId: "bpc-157", name: "BPC-157 evening top-up",
                                                               startedAt: startOfLocalDay(nowMillis() - 3 * DAY_MS), doseMcg: 500, route: .subcutaneous,
                                                               schedule: Schedule(kind: .daily, timeOfDay: "21:00"))) }
            }
            if let i = args.firstIndex(of: "-theme"), i + 1 < args.count { store.mutate { $0.settings.theme = ThemeSetting(rawValue: args[i + 1]) } }
            if args.contains("-plotWeight") { store.mutate { $0.settings.plotWeightOnChart = true } }
            if args.contains("-demoGoal") { store.mutate { $0.settings.weightGoal = WeightGoal(kg: 88, startKg: 98) } }
            if args.contains("-demoProfiles") {
                // A second profile, with the first still showing.
                store.mutate { let first = $0.activeProfileId; _ = $0.addProfile(name: "Sam"); $0.switchProfile(first) }
            }
            if args.contains("-demoOneOff") {
                // Doses logged by hand for compounds with no protocol.
                store.mutate {
                    $0.addLog(DoseLog(id: "", profileId: "", peptideId: "cagrilintide", at: nowMillis() - 2 * HOUR_MS, doseMcg: 250, route: .subcutaneous, site: .thighL))
                    $0.addLog(DoseLog(id: "", profileId: "", peptideId: "cagrilintide", at: nowMillis() - 3 * DAY_MS, doseMcg: 250, route: .subcutaneous, site: .thighR))
                    $0.addLog(DoseLog(id: "", profileId: "", peptideId: "aod-9604", at: nowMillis() - 20 * HOUR_MS, doseMcg: 300, route: .subcutaneous, site: .abdomenLM))
                }
            }
            if args.contains("-demoPaused") { store.mutate { $0.pauseAll(until: startOfLocalDay(nowMillis() + 3 * DAY_MS)) } }
            return store
        }
        #endif
        #if LOCAL_ONLY
        // The test build has no iCloud entitlement: this device only.
        let wantsCloud = false
        #else
        let wantsCloud = FileManager.default.ubiquityIdentityToken != nil
            && !ProcessInfo.processInfo.arguments.contains("-localOnly")
        #endif
        if wantsCloud, let records = try? RecordStore(location: .cloud(containerId: containerId)) {
            return AppStore(records: records)
        }
        if let records = try? RecordStore(location: .local) { return AppStore(records: records) }
        // Last resort, so the app opens rather than crashing; nothing will persist.
        return AppStore(records: try! RecordStore(location: .memory))
    }
}

extension ThemeSetting {
    #if canImport(UIKit)
    var interfaceStyle: UIUserInterfaceStyle {
        switch self {
        case .dark: .dark
        case .light: .light
        default: .unspecified
        }
    }

    /// Every window, so sheets and popovers follow too.
    @MainActor func apply() {
        for case let scene as UIWindowScene in UIApplication.shared.connectedScenes {
            for window in scene.windows { window.overrideUserInterfaceStyle = interfaceStyle }
        }
    }
    #else
    /// The whole app, so every window and sheet follows.
    @MainActor func apply() {
        switch self {
        case .dark: NSApp.appearance = NSAppearance(named: .darkAqua)
        case .light: NSApp.appearance = NSAppearance(named: .aqua)
        default: NSApp.appearance = nil
        }
    }
    #endif
}
