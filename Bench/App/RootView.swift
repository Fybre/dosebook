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
            Tab(t("more"), systemImage: "ellipsis.circle", value: "more") { NavigationStack { MoreView() } }
        }
    }
}

struct MoreView: View {
    var body: some View {
        List {
            Section {
                NavigationLink { CalculatorView() } label: { Label(t("nav_calc"), systemImage: "function") }
                NavigationLink { LibraryView() } label: { Label(t("nav_library"), systemImage: "books.vertical") }
                NavigationLink { LabsView() } label: { Label(t("nav_bloodwork"), systemImage: "drop") }
                NavigationLink { ReportView() } label: { Label(t("settings_report_clinician"), systemImage: "doc.text") }
            }
            Section {
                NavigationLink { SettingsView() } label: { Label(t("nav_settings_label"), systemImage: "gear") }
                NavigationLink { AboutView() } label: { Label(t("nav_about"), systemImage: "info.circle") }
            }
        }
        .navigationTitle(t("more"))
    }
}
