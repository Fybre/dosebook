import SwiftUI
import BenchCore

/// Drag the Now screen's panels into the order wanted. Kept on this device, like which are shown.
/// Today stays at the top, and what is due always comes straight after it.
struct NowPanelOrderView: View {
    @AppStorage(NowPanels.orderKey) private var orderRaw = ""

    var body: some View {
        let order = NowPanels.order(orderRaw)
        List {
            Section {
                ForEach(order) { panel in
                    Label(panel.title, systemImage: panel.symbol)
                }
                .onMove { from, to in
                    var next = order
                    next.move(fromOffsets: from, toOffset: to)
                    orderRaw = NowPanels.raw(order: next)
                }
            } footer: { FooterWrap { Text(t("ios_panels_arrange_hint")) } }
            Section {
                Button(t("ios_panels_reset")) { orderRaw = "" }.disabled(orderRaw.isEmpty)
            }
        }
        #if os(iOS)
        .environment(\.editMode, .constant(.active))
        #endif
        .readableWidth()
        .navigationTitle(t("ios_panels_arrange"))
        .inlineTitle()
    }
}
