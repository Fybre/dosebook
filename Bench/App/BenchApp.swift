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
                    if phase == .active { store.reload() }
                }
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
