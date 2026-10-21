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
                .preferredColorScheme(store.data.settings.theme.colorScheme)
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
    static let containerId = "iCloud.com.craigmewett.bench"

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
    var colorScheme: ColorScheme? {
        switch self {
        case .dark: .dark
        case .light: .light
        default: nil
        }
    }
}
