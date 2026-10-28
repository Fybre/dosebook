import SwiftUI
import BenchCore
import BenchStore

/// Places that must never be used: never suggested, never offered when logging or pinning.
/// Past doses given there stay in the log as they were.
struct NeverSitesView: View {
    @Environment(AppStore.self) private var store

    var body: some View {
        let never = Set(store.data.settings.neverInjectSites)
        GroupedList {
            Section {
                SiteMapView(logs: [], selected: never, multi: true, showLegend: false, onSelect: { toggle($0, never) })
                    .frame(maxWidth: .infinity)
                FooterRow { Text(t("ios_sites_map_hint")) }
            } footer: { FooterWrap { Text(t("ios_sites_map_hint")) }}
            Section {
                ForEach(INJECTION_SITES, id: \.id.rawValue) { info in
                    Toggle(siteLabel(info.id), isOn: Binding(get: { !never.contains(info.id) }, set: { on in
                        if on { set(never.subtracting([info.id])) } else if never.count < INJECTION_SITES.count - 1 { set(never.union([info.id])) }
                    }))
                }
            } header: { Text(t("ios_sites_allowed")) } footer: { FooterWrap { Text(t("ios_sites_keep_one")) }}
        }
        .readableWidth()
        .navigationTitle(t("ios_sites_title"))
        .inlineTitle()
    }

    private func toggle(_ site: InjectionSite, _ never: Set<InjectionSite>) {
        if never.contains(site) { set(never.subtracting([site])) }
        else if never.count < INJECTION_SITES.count - 1 { set(never.union([site])) }
    }

    private func set(_ sites: Set<InjectionSite>) {
        store.mutate { $0.settings.neverInjectSites = InjectionSite.allCases.filter(sites.contains) }
    }
}
