import SwiftUI
import BenchCore
import BenchStore

struct RootView: View {
    @Environment(AppStore.self) private var store
    /// Per window, so a second window on the Mac or iPad keeps its own screen.
    @SceneStorage("bench.tab") private var tab = RootView.firstTab
    /// A new window opens on Now, or on `-tab <name>` when launched with one (for screenshots).
    private static var firstTab: String {
        let args = ProcessInfo.processInfo.arguments
        if let i = args.firstIndex(of: "-tab"), i + 1 < args.count { return args[i + 1] }
        return "now"
    }
    @AppStorage("bench.lang") private var langRaw = I18n.lang.rawValue
    @State private var reselects: [String: Int] = [:]
    /// Bumped by ⌘N in this window; Now opens Log a dose when it changes.
    @State private var logDoseRequests = 0
    @Environment(\.horizontalSizeClass) private var sizeClass
    /// Shown only in the sidebar; a narrow window has no sidebar, so they go under More.
    private static let sidebarOnly: Set<String> = ["calculator", "library", "labs", "report", "settings", "about", "guide"]

    var body: some View {
        TabView(selection: Binding(get: { tab }, set: { next in
            // Choosing the tab already showing is a request to go back to its top.
            if next == tab { reselects[next, default: 0] += 1 }
            tab = next
        })) {
            Tab(t("nav_now"), systemImage: "waveform.path.ecg", value: "now") { NavigationStack { TodayView() } }
            Tab(t("nav_plan"), systemImage: "checklist", value: "plan") { NavigationStack { PlanView() } }
            Tab(t("nav_log"), systemImage: "book.pages", value: "log") { NavigationStack { LogView() } }
            Tab(t("nav_stock"), systemImage: "flask", value: "stock") { NavigationStack { StockView() } }
            // On a wide screen the sidebar lists everything; on a phone these sit under More.
            // Left out entirely when narrow: hidden tabs still count, and past five the
            // system adds its own More tab around ours.
            if sizeClass != .compact {
                TabSection(t("more")) {
                    Tab(t("nav_calc"), systemImage: "function", value: "calculator") { NavigationStack { CalculatorView() } }
                    Tab(t("nav_library"), systemImage: "books.vertical", value: "library") { NavigationStack { LibraryView() } }
                    Tab(t("nav_bloodwork"), systemImage: "drop", value: "labs") { NavigationStack { LabsView() } }
                    Tab(t("settings_report_clinician"), systemImage: "doc.text", value: "report") { NavigationStack { ReportView() } }
                    Tab(t("nav_settings_label"), systemImage: "gear", value: "settings") { NavigationStack { SettingsView() } }
                    Tab(t("nav_about"), systemImage: "info.circle", value: "about") { NavigationStack { AboutView() } }
                    Tab(t("ios_guide_title"), systemImage: "questionmark.circle", value: "guide") { NavigationStack { GuideView() } }
                }
                .defaultVisibility(.hidden, for: .tabBar)
            }
            #if os(iOS)
            // The phone's way to the screens above; the Mac always has its sidebar.
            Tab(t("more"), systemImage: "ellipsis.circle", value: "more") { MoreStack() }
                .defaultVisibility(.hidden, for: .sidebar)
            #endif
        }
        .tabViewStyle(.sidebarAdaptable)
        #if os(iOS)
        // iPad opens on the sidebar; iPhone, which has no room for one, keeps its tab bar.
        .defaultAdaptableTabBarPlacement(sizeClass == .regular ? .sidebar : .automatic)
        #endif
        .environment(\.tabReselects, reselects)
        .environment(\.goToTab) { tab = $0 }
        #if DEBUG
        // After the window's own saved screen is put back, which would otherwise win.
        .task {
            let args = ProcessInfo.processInfo.arguments
            if let i = args.firstIndex(of: "-tab"), i + 1 < args.count {
                try? await Task.sleep(for: .milliseconds(300))
                tab = args[i + 1]
            }
        }
        #endif

        // Forms and sheets as grouped sections on the Mac too, not its two-column default.
        .formStyle(.grouped)
        .onChange(of: sizeClass, initial: true) { _, size in
            if size == .compact, Self.sidebarOnly.contains(tab) { tab = "more" }
        }
        .environment(\.logDoseRequests, logDoseRequests)
        .focusedSceneValue(\.logDose, LogDoseAction { tab = "now"; logDoseRequests += 1 })
        // Strings are read when views build, so a new language rebuilds the tree.
        .id(langRaw)
        .onChange(of: langRaw) { _, raw in if let l = Lang(rawValue: raw) { I18n.lang = l } }
        // Reminders follow the plan: re-armed whenever the records change.
        .task(id: store.data) {
            WidgetSync.update(store.data)
            await ReminderScheduler.rearm(store.data)
            await StockWatcher.shared.update(store.data)
        }
    }
}

struct MoreView: View {
    enum Screen: String, Hashable { case calculator, library, labs, report, settings, about, importer, guide }

    var body: some View {
        List {
            Section {
                NavigationLink(value: Screen.guide) { Label(t("ios_guide_title"), systemImage: "questionmark.circle") }
            }
            Section {
                NavigationLink(value: Screen.calculator) { Label(t("nav_calc"), systemImage: "function") }
                NavigationLink(value: Screen.library) { Label(t("nav_library"), systemImage: "books.vertical") }
                NavigationLink(value: Screen.labs) { Label(t("nav_bloodwork"), systemImage: "drop") }
                NavigationLink(value: Screen.report) { Label(t("settings_report_clinician"), systemImage: "doc.text") }
            }
            Section {
                NavigationLink(value: Screen.settings) { Label(t("nav_settings_label"), systemImage: "gear") }
                NavigationLink(value: Screen.about) { Label(t("nav_about"), systemImage: "info.circle") }
            }
        }
        .readableWidth()
        .navigationTitle(t("more"))
        .navigationDestination(for: Screen.self) { s in
            switch s {
            case .calculator: CalculatorView()
            case .library: LibraryView()
            case .labs: LabsView()
            case .report: ReportView()
            case .settings: SettingsView()
            case .about: AboutView()
            case .importer: ImportView()
            case .guide: GuideView()
            }
        }
    }
}

/// The More tab's stack, holding the path so a debug launch can push a screen.
private struct MoreStack: View {
    @State private var path = NavigationPath()
    var body: some View {
        NavigationStack(path: $path) { MoreView() }
        #if DEBUG
            .onAppear {
                // `-more <screen>` opens one of these directly, for screenshots.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-more"), i + 1 < args.count, let s = MoreView.Screen(rawValue: args[i + 1]), path.isEmpty {
                    path.append(s)
                    if i + 2 < args.count, !args[i + 2].hasPrefix("-") { path.append(args[i + 2]) }
                }
            }
        #endif
    }
}

private struct TabReselectsKey: EnvironmentKey { static let defaultValue: [String: Int] = [:] }
extension EnvironmentValues {
    /// How many times this window has asked for Log a dose from the menu.
    @Entry var logDoseRequests = 0

    /// How many times each tab has been tapped while already selected.
    var tabReselects: [String: Int] {
        get { self[TabReselectsKey.self] }
        set { self[TabReselectsKey.self] = newValue }
    }
}
