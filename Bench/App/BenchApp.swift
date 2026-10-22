import SwiftUI
import BenchCore
import BenchStore
import CoreData

@main
struct BenchApp: App {
    @State private var store: AppStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        _store = State(initialValue: Bootstrap.makeStore())
    }

    var body: some Scene {
        WindowGroup {
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
                    if phase == .active { store.reload(); BackupFolder.runIfDue(store) }
                }
                .task { BackupFolder.runIfDue(store) }
        }
    }
}

@MainActor
enum Bootstrap {
    static let containerId = "iCloud.me.fybre.bench"

    /// CloudKit when there is an iCloud account and the build is entitled; this
    /// device only otherwise. The choice is shown in Settings.
    static func makeStore() -> AppStore {
        if let lang = UserDefaults.standard.string(forKey: "bench.lang").flatMap(Lang.init(rawValue:)) { I18n.lang = lang }
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count { UserDefaults.standard.set(args[i + 1], forKey: "bench.tab") }
        #if DEBUG
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
            return store
        }
        #endif
        let wantsCloud = FileManager.default.ubiquityIdentityToken != nil
            && !ProcessInfo.processInfo.arguments.contains("-localOnly")
        if wantsCloud, let records = try? RecordStore(location: .cloud(containerId: containerId)) {
            return AppStore(records: records)
        }
        if let records = try? RecordStore(location: .local) { return AppStore(records: records) }
        // Last resort, so the app opens rather than crashing; nothing will persist.
        return AppStore(records: try! RecordStore(location: .memory))
    }
}

extension ThemeSetting {
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
}
