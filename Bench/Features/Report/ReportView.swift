import SwiftUI
import BenchCore
import BenchStore

struct ReportView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Text("Coming next")
        }
        .navigationTitle(t("settings_report_clinician"))
    }
}
