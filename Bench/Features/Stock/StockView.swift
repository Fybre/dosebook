import SwiftUI
import BenchCore
import BenchStore

struct StockView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        List {
            Text("Coming next")
        }
        .navigationTitle(t("nav_stock"))
    }
}
