import SwiftUI
import BenchCore
import BenchStore

struct RootView: View {
    @AppStorage("bench.tab") private var tab = "now"

    var body: some View {
        TabView(selection: $tab) {
            Tab(t("nav_now"), systemImage: "waveform.path.ecg", value: "now") { NavigationStack { TodayView() } }
            Tab(t("nav_plan"), systemImage: "checklist", value: "plan") { NavigationStack { PlanView() } }
            Tab(t("nav_log"), systemImage: "book.pages", value: "log") { NavigationStack { LogView() } }
            Tab(t("nav_stock"), systemImage: "flask", value: "stock") { NavigationStack { StockView() } }
            Tab(t("more"), systemImage: "ellipsis.circle", value: "more") { MoreStack() }
        }
    }
}

struct MoreView: View {
    enum Screen: String, Hashable { case calculator, library, labs, report, settings, about }

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
        .navigationTitle(t("more"))
        .navigationDestination(for: Screen.self) { s in
            switch s {
            case .calculator: CalculatorView()
            case .library: LibraryView()
            case .labs: LabsView()
            case .report: ReportView()
            case .settings: SettingsView()
            case .about: AboutView()
            }
        }
    }
}

/// The More tab's stack, holding the path so a debug launch can push a screen.
private struct MoreStack: View {
    @State private var path: [MoreView.Screen] = []
    var body: some View {
        NavigationStack(path: $path) { MoreView() }
        #if DEBUG
            .onAppear {
                // `-more <screen>` opens one of these directly, for screenshots.
                let args = ProcessInfo.processInfo.arguments
                if let i = args.firstIndex(of: "-more"), i + 1 < args.count, let s = MoreView.Screen(rawValue: args[i + 1]), path.isEmpty {
                    path = [s]
                }
            }
        #endif
    }
}
