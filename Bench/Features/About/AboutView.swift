import SwiftUI
import BenchCore
import BenchStore

struct AboutView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Text("Coming next")
        }
        .navigationTitle(t("nav_about"))
    }
}
