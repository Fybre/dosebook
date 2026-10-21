import SwiftUI
import BenchCore
import BenchStore

struct LabsView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Text("Coming next")
        }
        .navigationTitle(t("nav_bloodwork"))
    }
}
