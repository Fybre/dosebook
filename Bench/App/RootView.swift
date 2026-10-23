import SwiftUI
import BenchCore
import BenchStore

struct RootView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("bench.tab") private var tab = "now"
    @AppStorage("bench.lang") private var langRaw = I18n.lang.rawValue
    @State private var reselects: [String: Int] = [:]

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
            Tab(t("more"), systemImage: "ellipsis.circle", value: "more") { MoreStack() }
        }
        .environment(\.tabReselects, reselects)
        // Strings are read when views build, so a new language rebuilds the tree.
        .id(langRaw)
        .onChange(of: langRaw) { _, raw in if let l = Lang(rawValue: raw) { I18n.lang = l } }
        // Reminders follow the plan: re-armed whenever the records change.
        .task(id: store.data) { await ReminderScheduler.rearm(store.data) }
    }
}

struct MoreView: View {
    enum Screen: String, Hashable { case calculator, library, labs, report, settings, about, importer }

    var body: some View {
        List {
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
    /// How many times each tab has been tapped while already selected.
    var tabReselects: [String: Int] {
        get { self[TabReselectsKey.self] }
        set { self[TabReselectsKey.self] = newValue }
    }
}
