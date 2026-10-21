import SwiftUI
import UniformTypeIdentifiers
import BenchCore
import BenchStore

struct SettingsView: View {
    @Environment(AppStore.self) private var store
    @AppStorage("bench.lang") private var langRaw = I18n.lang.rawValue
    @State private var message: (tone: Tone, text: String)?
    @State private var exporting = false
    @State private var exportingCsv = false
    @State private var importing = false
    @State private var pendingImport: (raw: Data, preview: AppData)?
    @State private var confirmingReset = false

    var body: some View {
        let data = store.data
        let mine = data.mine
        let settings = data.settings
        List {
            if let message {
                Section { CalloutText(message.text).font(.footnote).callout(message.tone) }
            }
            RescueNotice()

            Section {
                Label {
                    Text(syncText).font(.footnote)
                } icon: {
                    Image(systemName: store.location.isCloud ? "icloud" : store.location.isMemory ? "exclamationmark.icloud" : "iphone")
                        .foregroundStyle(store.location.isMemory ? Tone.rose.color : Color.accentColor)
                }
            } header: { Text(t("ios_sync_title")) }

            ProfilesSection()
            RemindersSection()

            Section {
                Text(t("ios_data_note")).font(.footnote).foregroundStyle(.secondary)
                Button { exporting = true } label: { Label(t("settings_export_file"), systemImage: "square.and.arrow.up") }
                Button { exportingCsv = true } label: { Label(t("settings_doses_csv"), systemImage: "tablecells") }.disabled(mine.logs.isEmpty)
                Button { importing = true } label: { Label(t("ios_import_backup"), systemImage: "square.and.arrow.down") }
                NavigationLink(value: MoreView.Screen.report) { Label(t("settings_report_clinician"), systemImage: "doc.text") }
            } header: { Text(t("settings_your_data")) } footer: {
                Text(t("settings_currently_holding", ["doses": .string(t("count_doses", ["n": .number(Double(mine.logs.count))])),
                                                       "protocols": .string(t("count_protocols", ["n": .number(Double(mine.protocols.count))])),
                                                       "vials": .string(t("count_vials", ["n": .number(Double(mine.vials.count))]))]))
            }

            Section(t("settings_defaults")) {
                NavigationLink {
                    List { SyringePickerView(value: Binding(get: { settings.defaultSyringeId ?? "" },
                                                            set: { id in store.mutate { $0.settings.defaultSyringeId = id.isEmpty ? nil : id } }),
                                             allowUnset: true) }
                        .navigationTitle(t("settings_usual_syringe"))
                } label: {
                    LabeledContent(t("settings_usual_syringe"), value: settings.defaultSyringeId.flatMap(syringeById)?.label ?? t("syringe_ask_each_time"))
                }
                Picker(t("settings_currency"), selection: setting(\.currency)) {
                    ForEach(CURRENCIES, id: \.code) { Text($0.label).tag($0.code) }
                }
                Picker(t("settings_weight_in"), selection: setting(\.weightUnit)) {
                    Text(t("settings_kilograms")).tag(WeightUnit.kg)
                    Text(t("settings_pounds")).tag(WeightUnit.lb)
                }
                NumberRow(label: t("settings_warn_vial_dates"), value: setting(\.budWarningDays), suffix: t("days"), range: 0...28)
                NumberRow(label: t("settings_low_stock_at"), value: setting(\.lowStockDoses), suffix: t("settings_doses_suffix"), range: 0...60)
                Picker(t("settings_group_vials"), selection: Binding(get: { settings.groupIdenticalVials == true }, set: { v in store.mutate { $0.settings.groupIdenticalVials = v } })) {
                    Text(t("settings_one_row_vial")).tag(false)
                    Text(t("settings_one_row_compound")).tag(true)
                }
                Picker(t("settings_water_position"), selection: Binding(get: { settings.waterAtBottom == true }, set: { v in store.mutate { $0.settings.waterAtBottom = v } })) {
                    Text(t("settings_water_top")).tag(false)
                    Text(t("settings_water_bottom")).tag(true)
                }
                Picker(t("theme_label"), selection: setting(\.theme)) {
                    Text(t("ios_theme_system")).tag(ThemeSetting.system)
                    Text(t("theme_light")).tag(ThemeSetting.light)
                    Text(t("theme_dark")).tag(ThemeSetting.dark)
                }
                Picker(t("ios_language"), selection: $langRaw) {
                    ForEach(Lang.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
            }

            Section {
                Text(t("settings_erase_desc")).font(.footnote).foregroundStyle(.secondary)
                Button(t("settings_erase"), role: .destructive) { confirmingReset = true }
            } header: { Text(t("settings_erase")) }

            Section {
                Text(t("settings_about_1"))
                Text(t("settings_about_2"))
                Text(t("settings_about_3"))
                NavigationLink(value: MoreView.Screen.about) { Text(t("about_title")) }
            } header: { Text(t("settings_what_it_is")) }
            .font(.footnote)
        }
        .navigationTitle(t("settings_title"))
        .backupExporter(isPresented: $exporting)
        .fileExporter(isPresented: $exportingCsv, document: CsvDocument(text: csv.text), contentType: .commaSeparatedText,
                      defaultFilename: "bench-doses-\(isoDay())") { result in
            if case .success = result { message = (.sky, t("settings_exported_csv", ["n": .number(Double(csv.rows.count))])) }
        }
        .fileImporter(isPresented: $importing, allowedContentTypes: [.json]) { result in
            guard case .success(let url) = result else { return }
            let access = url.startAccessingSecurityScopedResource()
            defer { if access { url.stopAccessingSecurityScopedResource() } }
            guard let raw = try? Data(contentsOf: url), let preview = try? AppData.load(raw), !preview.logs.isEmpty || !preview.protocols.isEmpty || !preview.vials.isEmpty || !preview.profiles.isEmpty else {
                message = (.rose, t("ios_import_not_bench")); return
            }
            pendingImport = (raw, preview)
        }
        .confirmationDialog(t("import_own_export"), isPresented: Binding(get: { pendingImport != nil }, set: { if !$0 { pendingImport = nil } }), titleVisibility: .visible) {
            Button(t("import_replace_everything"), role: .destructive) {
                guard let p = pendingImport else { return }
                do {
                    try store.importBackup(p.raw)
                    message = (.sky, t("ios_imported", ["doses": .string(t("count_doses", ["n": .number(Double(p.preview.logs.count))])),
                                                       "protocols": .string(t("count_protocols", ["n": .number(Double(p.preview.protocols.count))])),
                                                       "vials": .string(t("count_vials", ["n": .number(Double(p.preview.vials.count))]))]))
                } catch {
                    message = (.rose, t("ios_import_not_bench"))
                }
                pendingImport = nil
            }
            Button(t("settings_keep_what_i_have"), role: .cancel) { pendingImport = nil }
        } message: {
            if let p = pendingImport {
                RichText(t("import_own_export_body", ["doses": .string(t("count_doses", ["n": .number(Double(p.preview.logs.count))])),
                                                      "protocols": .string(t("count_protocols", ["n": .number(Double(p.preview.protocols.count))])),
                                                      "vials": .string(t("count_vials", ["n": .number(Double(p.preview.vials.count))]))]))
            }
        }
        .confirmationDialog(t("settings_erase"), isPresented: $confirmingReset, titleVisibility: .visible) {
            Button(t("settings_erase_confirm", ["n": .number(Double(mine.logs.count + mine.protocols.count + mine.vials.count))]), role: .destructive) {
                store.mutate { $0.resetAll() }
                message = (.rose, t("settings_erased"))
            }
            Button(t("settings_keep_my_data"), role: .cancel) {}
        } message: { Text(t("settings_erase_desc")) }
    }

    private var csv: (rows: [String], text: String) {
        let data = store.data
        return doseCsv(data.mine.logs) { data.peptide($0)?.name ?? $0 }
    }

    private var syncText: String {
        switch store.location {
        case .cloud: t("ios_sync_cloud")
        case .local: t("ios_sync_local")
        case .memory: t("ios_sync_memory")
        }
    }

    private func setting<V>(_ path: WritableKeyPath<Settings, V>) -> Binding<V> {
        Binding(get: { store.data.settings[keyPath: path] }, set: { v in store.mutate { $0.settings[keyPath: path] = v } })
    }

    private func isoDay() -> String {
        let c = LocalTime.calendar.dateComponents([.year, .month, .day], from: Date())
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }
}

extension StoreLocation {
    var isCloud: Bool { if case .cloud = self { true } else { false } }
    var isMemory: Bool { if case .memory = self { true } else { false } }
}

struct CsvDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.commaSeparatedText] }
    var text: String
    init(text: String) { self.text = text }
    init(configuration: ReadConfiguration) throws { text = String(decoding: configuration.file.regularFileContents ?? Data(), as: UTF8.self) }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: Data(text.utf8)) }
}

// MARK: - Profiles

private struct ProfilesSection: View {
    @Environment(AppStore.self) private var store
    @State private var newName = ""
    @State private var deleting: Profile?

    var body: some View {
        let data = store.data
        let unit = data.settings.weightUnit
        Section {
            ForEach(data.profiles) { p in
                let active = p.id == data.activeProfileId
                let protocols = data.protocols.filter { $0.profileId == p.id }.count
                let doses = data.logs.filter { $0.profileId == p.id }.count
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 12) {
                        Circle().fill(p.tone.color).frame(width: 32, height: 32)
                            .overlay(Text(String(p.name.prefix(1)).uppercased()).font(.subheadline.bold()).foregroundStyle(.white))
                        TextField(t("profile_name_placeholder"), text: Binding(get: { p.name }, set: { v in store.mutate { $0.updateProfile(p.id) { $0.name = v } } }))
                            .font(.headline)
                            .accessibilityLabel(t("settings_name_for", ["name": .string(p.name)]))
                        if active { Pill(text: t("settings_showing"), tone: Tone(rawValue: p.tone.rawValue) ?? .mint) }
                        else { Button(t("settings_switch_to")) { store.mutate { $0.switchProfile(p.id) } }.buttonStyle(.bordered).controlSize(.small) }
                    }
                    HStack(spacing: 8) {
                        ForEach(ProfileTone.allCases, id: \.rawValue) { tone in
                            Button { store.mutate { $0.updateProfile(p.id) { $0.tone = tone } } } label: {
                                Circle().fill(tone.color).frame(width: 22, height: 22)
                                    .overlay(Circle().stroke(Color.primary, lineWidth: p.tone == tone ? 2 : 0).padding(-3))
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(t("settings_colour", ["tone": .string(tone.rawValue)]))
                            .accessibilityAddTraits(p.tone == tone ? .isSelected : [])
                        }
                        Spacer()
                        Text("\(t("count_protocols", ["n": .number(Double(protocols))])) · \(t("count_doses", ["n": .number(Double(doses))]))")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                    OptionalNumberRow(label: t("settings_body_weight"), value: Binding(
                        get: { p.weightKg.map { jsFixed(toDisplayWeight($0, unit), 1) } },
                        set: { v in store.mutate { $0.updateProfile(p.id) { $0.weightKg = v.map { fromDisplayWeight($0, unit) } } } }),
                        suffix: unit.rawValue, hint: p.weightKg != nil ? t("settings_weight_set") : t("settings_weight_unset"))
                }
                .padding(.vertical, 4)
                .swipeActions {
                    if data.profiles.count > 1 {
                        Button(t("plan_delete_named", ["name": .string(p.name)]), role: .destructive) { deleting = p }
                    }
                }
            }
            HStack {
                TextField(t("profile_their_name"), text: $newName)
                    .accessibilityLabel(t("profile_new_name"))
                    .onSubmit(add)
                Button(t("profile_add"), action: add).disabled(newName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        } header: { Text(t("settings_profiles")) } footer: { Text(t("settings_profiles_note")) }
        .confirmationDialog(deleting.map { t("plan_delete_named", ["name": .string($0.name)]) } ?? "",
                            isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible, presenting: deleting) { p in
            Button(t("plan_delete_named", ["name": .string(p.name)]), role: .destructive) { store.mutate { $0.removeProfile(p.id) } }
            Button(t("keep"), role: .cancel) {}
        } message: { p in
            Text(t("settings_delete_profile_confirm", ["name": .string(p.name),
                                                       "protocols": .string(t("count_protocols", ["n": .number(Double(data.protocols.filter { $0.profileId == p.id }.count))])),
                                                       "doses": .string(t("count_doses", ["n": .number(Double(data.logs.filter { $0.profileId == p.id }.count))]))]))
        }
    }

    private func add() {
        let name = newName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        store.mutate { _ = $0.addProfile(name: name) }
        newName = ""
    }
}

// MARK: - Reminders

private let LEAD_OPTIONS: [Double] = [0, 15, 30, 60]
private let CALENDAR_SPANS: [Double] = [7, 14, 21, 30, 60, 90, 180]

private struct RemindersSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var state: ReminderScheduler.Availability?
    @State private var result: String?
    @State private var calendarFile: URL?

    var body: some View {
        let data = store.data
        let reminders = data.settings.reminders ?? DEFAULT_REMINDERS
        let armed = remindersFor(protocols: data.mine.protocols, logs: data.mine.logs, peptides: data.allPeptides, settings: reminders, nowMs: nowMillis())
        Section {
            RichText(t("reminders_intro")).font(.footnote).foregroundStyle(.secondary)
            switch state {
            case nil: Text(t("reminders_checking")).font(.footnote).foregroundStyle(.secondary)
            case .available?: CalloutText(t("ios_notify_on")).font(.footnote).callout(.sky)
            case .notAsked?: CalloutText(t("ios_notify_ask")).font(.footnote).callout(.tangerine)
            case .denied?:
                CalloutText(t("ios_notify_off")).font(.footnote).callout(.tangerine)
                Button(t("ios_open_settings")) { if let url = URL(string: UIApplication.openNotificationSettingsURLString) { openURL(url) } }
            }
            Picker(t("reminders_remind_me"), selection: Binding(get: { reminders.enabled ? reminders.leadMinutes : -1 }, set: { v in Task { await setEnabled(v >= 0, v >= 0 ? v : reminders.leadMinutes) } })) {
                Text(t("reminders_never")).tag(-1.0)
                ForEach(LEAD_OPTIONS, id: \.self) { m in Text(t("reminders_lead_\(Int(m))")).tag(m) }
            }
            .disabled(state == .denied)
            if reminders.enabled {
                Text(armed.first.map { t("reminders_set", ["reminders": .string(t("count_reminders", ["n": .number(Double(armed.count))])), "when": .string(formatDateTime($0.at))]) }
                     ?? t("reminders_nothing_yet"))
                    .font(.footnote).foregroundStyle(.secondary)
            }
            Picker(t("reminders_what_it_says"), selection: Binding(get: { reminders.showCompound }, set: { v in update { $0.showCompound = v } })) {
                Text(t("reminders_say_minimal")).tag(false)
                Text(t("reminders_say_full")).tag(true)
            }
            Picker(t("reminders_send_calendar"), selection: Binding(get: { reminders.calendarDays }, set: { v in update { $0.calendarDays = v } })) {
                ForEach(CALENDAR_SPANS, id: \.self) { d in Text(t("reminders_span_\(Int(d))")).tag(d) }
            }
            Button { exportCalendar(reminders) } label: { Label(t("reminders_export"), systemImage: "calendar.badge.plus") }
            if let calendarFile {
                ShareLink(item: calendarFile) { Label(t("ios_share_file"), systemImage: "square.and.arrow.up") }
            }
            if let result { Text(result).font(.footnote.weight(.medium)) }
        } header: { Text(t("reminders_title")) } footer: {
            Text(t("reminders_calendar_note").replacingOccurrences(of: "**", with: "") + (reminders.showCompound ? " " + t("reminders_named_warning") : ""))
        }
        .task { state = await ReminderScheduler.availability() }
    }

    private func update(_ change: @escaping (inout RemindersSettings) -> Void) {
        store.mutate { d in
            var r = d.settings.reminders ?? DEFAULT_REMINDERS
            change(&r)
            d.settings.reminders = r
        }
    }

    private func setEnabled(_ enabled: Bool, _ lead: Double) async {
        result = nil
        guard enabled else {
            update { $0.enabled = false }
            ReminderScheduler.clear()
            return
        }
        var ok = await ReminderScheduler.availability() == .available
        if !ok { ok = await ReminderScheduler.requestPermission() }
        state = await ReminderScheduler.availability()
        guard ok else { result = t("ios_reminders_refused"); return }
        update { $0.enabled = true; $0.leadMinutes = lead }
    }

    private func exportCalendar(_ reminders: RemindersSettings) {
        result = nil
        calendarFile = nil
        let data = store.data
        let ics = buildCalendar(protocols: data.mine.protocols, peptides: data.allPeptides, settings: reminders, nowMs: nowMillis())
        let count = calendarEventCount(ics)
        guard count > 0 else { result = t("reminders_nothing_to_export"); return }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(calendarFileName())
        do {
            try Data(ics.utf8).write(to: url, options: .atomic)
            calendarFile = url
            result = t("ios_calendar_ready", ["doses": .string(t("count_doses", ["n": .number(Double(count))]))])
        } catch {
            result = t("reminders_nothing_to_export")
        }
    }
}
