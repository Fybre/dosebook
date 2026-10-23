import SwiftUI
import BenchCore

/// The iPhone app's own releases. English, as the original's changelog is.
struct Release {
    var version: String
    var date: String
    var summary: String
    var changes: [String]
}

let RELEASES: [Release] = [
    Release(version: "1.0", date: "2026", summary: "Bench on iPhone, with your records in iCloud.", changes: [
        "Every screen of the original: Now, Plan, Log, Stock, the calculator, the library, bloodwork and the clinician report.",
        "Records sync through your private iCloud database. There is still no account and no server.",
        "Backups read and write the same file format as the web and Android apps.",
        "Dose reminders are scheduled on the phone and say only that a dose is due unless you choose otherwise.",
    ]),
]

var CURRENT_VERSION: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? RELEASES[0].version }

struct AboutView: View {
    @State private var expanded: String? = RELEASES.first?.version

    var body: some View {
        List {
            Section { Text(t("about_subtitle")).font(.subheadline).foregroundStyle(.secondary) }
            Section {
                Text(t("about_desc"))
                Text(t("about_what_it_is_2", ["compounds": .number(Double(Library.peptides.count))]))
            } header: { HStack { Text(t("about_what_it_is")); Spacer(); Pill(text: "v\(CURRENT_VERSION)", tone: .mint) } }
            Section {
                Text(t("ios_about_data_1"))
                Text(t("ios_about_data_2"))
                Text(t("ios_about_data_3"))
            } header: { Label(t("about_your_data"), systemImage: "lock") }
            Section(t("about_skipped_dose")) {
                RichText(t("about_skipped_1"))
                Text(t("about_skipped_stops")).font(.subheadline.weight(.semibold))
                ForEach(["about_skipped_vial", "about_skipped_curve", "about_skipped_ring", "about_skipped_left_out", "about_skipped_greyed"], id: \.self) {
                    Label(t($0), systemImage: "minus").font(.footnote)
                }
                Text(t("about_skipped_shows")).font(.subheadline.weight(.semibold))
                Text(t("about_skipped_where"))
            }
            Section(t("about_what_it_tracks")) {
                ForEach([t("about_tracks_compounds", ["n": .number(Double(Library.peptides.count))]), t("about_tracks_protocols"), t("about_tracks_reconstitution"),
                         t("about_tracks_stock"), t("about_tracks_sites"), t("ios_tracks_weight"),
                         t("about_tracks_markers", ["n": .number(Double(Library.labMarkers.count))]), t("about_tracks_interactions")], id: \.self) {
                    Label($0, systemImage: "checkmark").font(.subheadline)
                }
            }
            Section {
                ForEach(RELEASES, id: \.version) { r in
                    DisclosureGroup(isExpanded: Binding(get: { expanded == r.version }, set: { expanded = $0 ? r.version : nil })) {
                        ForEach(r.changes, id: \.self) { Text($0).font(.footnote) }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack { Text("v\(r.version)").font(.subheadline.bold()); Text(r.date).font(.caption).foregroundStyle(.secondary) }
                            Text(r.summary).font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                }
            } header: { Label(t("about_whats_new"), systemImage: "sparkles") }
            Section(t("about_who_made_it")) {
                RichText(t("ios_about_port"))
                Link(destination: URL(string: "https://github.com/ArunNGun/Bench")!) { Label(t("ios_about_original"), systemImage: "chevron.left.forwardslash.chevron.right") }
                Text(t("about_corrections")).font(.footnote).foregroundStyle(.secondary)
                NavigationLink(t("ios_about_licences")) { LicencesView() }
            }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    CalloutText(t("about_what_it_is_not"), bold: true)
                    CalloutText(t("about_not_body"))
                }
                .font(.footnote).callout(.tangerine)
            }
            Section {
                Text(t("about_numbers_1"))
                Text(t("about_numbers_2"))
            } header: { Label(t("about_numbers_title"), systemImage: "exclamationmark.shield") }
            Section { NavigationLink(t("about_export_data"), value: MoreView.Screen.settings) }
        }
        .readableWidth()
        .font(.subheadline)
        .navigationTitle(t("about_title"))
    }
}

/// The original's MIT licence, which has to travel with the parts of it this app carries.
private struct LicencesView: View {
    var body: some View {
        ScrollView {
            Text(Bundle.main.url(forResource: "ThirdPartyLicenses", withExtension: "txt").flatMap { try? String(contentsOf: $0, encoding: .utf8) } ?? "")
                .font(.footnote.monospaced())
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .textSelection(.enabled)
        }
        .navigationTitle(t("ios_about_licences"))
    }
}
