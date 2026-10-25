import SwiftUI
import BenchCore
import BenchStore
import CoreData

@main
struct BenchApp: App {
    @State private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        let store = Bootstrap.makeStore()
        _store = State(initialValue: store)
        // Before launch finishes, so a button tapped on a reminder reaches the store.
        NotificationHandler.shared.install(store)
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(store)
                .tint(.accentColor)
                // Applied to the windows rather than with preferredColorScheme, which
                // does not reliably hand control back to the system.
                .onChange(of: store.data.settings.theme, initial: true) { _, theme in theme.apply() }
                .onReceive(NotificationCenter.default.publisher(for: .NSPersistentStoreRemoteChange)) { _ in
                    store.reload()
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .active {
                        store.reload(); BackupFolder.runIfDue(store)
                        // New weigh-ins from Apple Health each time Bench comes to the front.
                        Task { _ = try? await HealthKitAdapter.pullWeight(into: store) }
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
    static let containerId = "iCloud.me.fybre.bench"

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
            if args.contains("-demoGoal") { store.mutate { $0.settings.weightGoal = WeightGoal(kg: 88, startKg: 98) } }
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
