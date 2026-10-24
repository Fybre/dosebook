import SwiftUI
import Charts
import BenchCore
import BenchStore

/// Bloodwork by marker: the latest value, its change, its history, and what is worth checking.
struct LabsView: View {
    @Environment(AppStore.self) private var store
    @State private var adding = false

    var body: some View {
        let data = store.data
        let labs = data.mine.labs
        let compounds = data.mine.protocols.filter(\.active).compactMap { data.peptide($0.peptideId) }.map {
            LabCompoundTraits(category: $0.category.rawValue, mechanismClass: ($0.mechanismClass ?? []).map(\.rawValue), c17AlphaAlkylated: $0.c17AlphaAlkylated == true)
        }
        let missing = missingMarkerIds(labs, compounds)
        GroupedList {
            Section { Text(t("labs_subtitle")).font(.subheadline).foregroundStyle(.secondary) }
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    CalloutText(t("labs_reference_ranges"), bold: true)
                    CalloutText(t("labs_reference_desc"))
                }
                .font(.footnote).callout(.sky)
                if !missing.isEmpty {
                    VStack(alignment: .leading, spacing: 4) {
                        Label { CalloutText(t("labs_worth_checking"), bold: true) } icon: { Image(systemName: "drop.fill").foregroundStyle(Tone.sky.color) }
                        CalloutText(t("labs_worth_checking_list", ["markers": .string(missing.map { Library.marker($0)?.name ?? $0 }.joined(separator: ", "))]))
                    }
                    .font(.footnote).callout(.sky)
                }
            }
            if labs.isEmpty {
                ContentUnavailableView {
                    Label(t("labs_no_results"), systemImage: "drop")
                } description: { Text(t("labs_empty_desc")) } actions: {
                    Button(t("labs_add_first")) { adding = true }.buttonStyle(.borderedProminent)
                }
            }
            ForEach(trackedMarkerIds(labs), id: \.self) { id in
                if let marker = Library.marker(id) {
                    MarkerHistory(marker: marker, results: labs.filter { $0.markerId == id })
                }
            }
        }
        .readableWidth()
        .navigationTitle(t("labs_title"))
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button { adding = true } label: { Label(t("labs_add_result"), systemImage: "plus") }
            }
        }
        .sheet(isPresented: $adding) { NavigationStack { AddLabForm() } }
    }
}

private struct MarkerHistory: View {
    @Environment(AppStore.self) private var store
    var marker: LabMarker
    var results: [LabResult]

    var body: some View {
        let latest = latestResult(results, marker.id)
        let trend = labTrend(results, marker.id)
        let series = labSeries(results, marker.id)
        let verdict = latest.map { verdictFor(marker, $0) }
        Section {
            HStack(alignment: .bottom, spacing: 24) {
                if let latest {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack(alignment: .firstTextBaseline, spacing: 4) {
                            Text(trim(latest.value, marker.decimals)).font(.largeTitle.weight(.heavy))
                            Text(marker.unit).font(.footnote.weight(.medium)).foregroundStyle(.secondary)
                        }
                        Text(formatDate(latest.at) + (latest.lab.map { " · \($0)" } ?? "")).font(.caption).foregroundStyle(.secondary)
                    }
                }
                if let trend {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("\(trend.delta > 0 ? "+" : "−")\(trim(abs(trend.delta), marker.decimals)) \(marker.unit)").font(.subheadline.bold())
                        Text(t("labs_over_days", ["n": .number(jsRound(trend.days))]) + (trend.percent.map { ", \(trim(abs($0), 1))%" } ?? ""))
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            if series.count > 1 {
                Chart(series, id: \.at) { p in
                    LineMark(x: .value("at", Date(millis: p.at)), y: .value(marker.unit, p.value)).foregroundStyle(Tone.sky.color)
                    PointMark(x: .value("at", Date(millis: p.at)), y: .value(marker.unit, p.value)).foregroundStyle(Tone.sky.color)
                }
                .chartYScale(domain: .automatic(includesZero: false))
                .frame(height: 120)
                .accessibilityLabel(t("labs_chart_label", ["marker": .string(marker.name), "from": .string(trim(series[0].value, marker.decimals)),
                                                           "to": .string(trim(series[series.count - 1].value, marker.decimals)), "unit": .string(marker.unit)]))
            }
            Text(marker.why).font(.footnote).foregroundStyle(.secondary)
            if let basis = verdict?.basis { Text(t("labs_judged_against", ["basis": .string(basis)])).font(.caption).foregroundStyle(.tertiary) }
            if verdict?.status == .unknown, let note = marker.rangeNote { Text(note).font(.caption).foregroundStyle(.tertiary) }
            ForEach(results.sorted { $0.at > $1.at }) { r in
                let v = verdictFor(marker, r)
                HStack(spacing: 10) {
                    Text(trim(r.value, marker.decimals)).font(.subheadline.bold()).frame(width: 72, alignment: .leading)
                    Text(formatDate(r.at)).font(.caption).foregroundStyle(.secondary).frame(width: 90, alignment: .leading)
                    Text((r.refLow != nil || r.refHigh != nil
                          ? t("labs_ref_range", ["low": .string(r.refLow.map { jsNumberString($0) } ?? t("not_available")), "high": .string(r.refHigh.map { jsNumberString($0) } ?? t("not_available"))])
                          : v.status == .unknown ? t("labs_no_range") : "") + (r.notes.map { " · \($0)" } ?? ""))
                        .font(.caption).foregroundStyle(.tertiary).lineLimit(1)
                }
                .rowActions {
                    Button(role: .destructive) { store.mutate { $0.removeLab(r.id) } } label: { Label(t("stock_delete"), systemImage: "trash") }
                }
                .accessibilityAction(named: t("labs_delete_result_from", ["marker": .string(marker.name), "date": .string(formatDate(r.at))])) {
                    store.mutate { $0.removeLab(r.id) }
                }
            }
        } header: {
            HStack {
                Text(marker.name)
                Spacer()
                if let verdict, verdict.status != .unknown { Pill(text: verdict.label, tone: verdict.tone == .muted ? .neutral : verdict.tone) }
            }
        }
    }
}

private struct AddLabForm: View {
    @Environment(AppStore.self) private var store
    @State private var markerId = Library.labMarkers.first?.id ?? ""
    @State private var value: Double?
    @State private var refLow: Double?
    @State private var refHigh: Double?
    @State private var at = Date()
    @State private var lab = ""
    @State private var notes = ""

    var body: some View {
        let marker = Library.marker(markerId)
        let grouped = Library.labMarkers.reduce(into: [(String, [LabMarker])]()) { acc, m in
            if let i = acc.firstIndex(where: { $0.0 == m.category.rawValue }) { acc[i].1.append(m) } else { acc.append((m.category.rawValue, [m])) }
        }
        Form {
            Section {
                Picker(t("labs_marker"), selection: $markerId) {
                    ForEach(grouped, id: \.0) { category, markers in
                        Section(Library.labCategoryLabels[category] ?? category) {
                            ForEach(markers, id: \.id) { m in Text(m.name + (m.aka.map { ", \($0)" } ?? "")).tag(m.id) }
                        }
                    }
                }
                FooterRow { if let marker { Text(marker.why) } }
            } footer: { FooterWrap { if let marker { Text(marker.why) } }}
            Section {
                OptionalNumberRow(label: t("labs_value"), value: $value, suffix: marker?.unit)
                DatePicker(t("log_when"), selection: $at)
            }
            Section {
                OptionalNumberRow(label: t("labs_your_low"), value: $refLow, suffix: t("labs_optional"))
                OptionalNumberRow(label: t("labs_your_high"), value: $refHigh, suffix: t("labs_optional"))
                FooterRow {
                Text(marker?.guideline.map { t("labs_guideline_note", ["marker": .string(marker!.name), "source": .string($0.source)]) } ?? t("labs_copy_interval"))
            }
            } footer: { FooterWrap {
                Text(marker?.guideline.map { t("labs_guideline_note", ["marker": .string(marker!.name), "source": .string($0.source)]) } ?? t("labs_copy_interval"))
            }}
            Section {
                TextField(t("labs_lab_name"), text: $lab, prompt: Text(t("labs_lab_placeholder")))
                TextField(t("labs_note"), text: $notes, prompt: Text(t("labs_note_placeholder")))
                FooterRow { Text(t("labs_lab_hint")) }
            } footer: { FooterWrap { Text(t("labs_lab_hint")) }}
        }
        .formChrome(t("labs_add_result"), confirm: t("labs_save_result"), disabled: !(value?.isFinite ?? false)) {
            guard let value else { return }
            let l = lab.trimmingCharacters(in: .whitespaces), n = notes.trimmingCharacters(in: .whitespaces)
            store.mutate {
                $0.addLab(LabResult(id: "", profileId: "", at: at.millis, markerId: markerId, value: value, refLow: refLow, refHigh: refHigh,
                                    lab: l.isEmpty ? nil : l, notes: n.isEmpty ? nil : n))
            }
        }
    }
}
