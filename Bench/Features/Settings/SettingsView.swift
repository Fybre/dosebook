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
    @State private var confirmingReset = false

    var body: some View {
        let data = store.data
        let mine = data.mine
        let settings = data.settings
        GroupedList {
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

            Section(t("ios_appearance")) {
                Picker(t("theme_label"), selection: setting(\.theme)) {
                    Label(t("ios_theme_system_short"), systemImage: "circle.lefthalf.filled").tag(ThemeSetting.system)
                    Label(t("ios_theme_light_short"), systemImage: "sun.max").tag(ThemeSetting.light)
                    Label(t("ios_theme_dark_short"), systemImage: "moon").tag(ThemeSetting.dark)
                }
                .pickerStyle(.segmented)
                .listRowBackground(Color.clear)
                .listRowInsets(EdgeInsets())
            }

            ProfilesSection()
            RemindersSection()
            HealthSection()
            BackupsSection()

            Section {
                Text(t("ios_data_note")).font(.footnote).foregroundStyle(.secondary)
                Button { exporting = true } label: { Label(t("settings_export_file"), systemImage: "square.and.arrow.up") }
                Button { exportingCsv = true } label: { Label(t("settings_doses_csv"), systemImage: "tablecells") }.disabled(mine.logs.isEmpty)
                NavigationLink { ImportView() } label: { Label(t("import_title"), systemImage: "square.and.arrow.down") }
                NavigationLink(value: MoreView.Screen.report) { Label(t("settings_report_clinician"), systemImage: "doc.text") }
                FooterRow {
                Text(t("settings_currently_holding", ["doses": .string(t("count_doses", ["n": .number(Double(mine.logs.count))])),
                                                       "protocols": .string(t("count_protocols", ["n": .number(Double(mine.protocols.count))])),
                                                       "vials": .string(t("count_vials", ["n": .number(Double(mine.vials.count))]))]))
            }
            } header: { Text(t("settings_your_data")) } footer: { FooterWrap {
                Text(t("settings_currently_holding", ["doses": .string(t("count_doses", ["n": .number(Double(mine.logs.count))])),
                                                       "protocols": .string(t("count_protocols", ["n": .number(Double(mine.protocols.count))])),
                                                       "vials": .string(t("count_vials", ["n": .number(Double(mine.vials.count))]))]))
            }}

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
                Picker(t("ios_stock_sort"), selection: setting(\.stockSort)) {
                    Text(t("ios_stock_sort_alpha")).tag(StockSort.alphabetical)
                    Text(t("ios_stock_sort_date")).tag(StockSort.dateAdded)
                        Text(t("ios_stock_sort_newest")).tag(StockSort.newestFirst)
                }
                Picker(t("settings_group_vials"), selection: Binding(get: { settings.groupIdenticalVials == true }, set: { v in store.mutate { $0.settings.groupIdenticalVials = v } })) {
                    Text(t("settings_one_row_vial")).tag(false)
                    Text(t("settings_one_row_compound")).tag(true)
                }
                Picker(t("settings_water_position"), selection: Binding(get: { settings.waterAtBottom == true }, set: { v in store.mutate { $0.settings.waterAtBottom = v } })) {
                    Text(t("settings_water_top")).tag(false)
                    Text(t("settings_water_bottom")).tag(true)
                }
                Picker(t("ios_language"), selection: $langRaw) {
                    ForEach(Lang.allCases, id: \.rawValue) { Text($0.label).tag($0.rawValue) }
                }
            }

            LockSection()

            Section {
                Toggle(t("ios_early_hours"), isOn: Binding(get: { settings.earlyHoursCountForNightBefore },
                                                          set: { v in store.mutate { $0.settings.earlyHoursCountForNightBefore = v } }))
                FooterRow { Text(t("ios_early_hours_hint")) }
            } footer: { FooterWrap { Text(t("ios_early_hours_hint")) }}

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
        .readableWidth()
        .navigationTitle(t("settings_title"))
        .backupExporter(isPresented: $exporting)
        .fileExporter(isPresented: $exportingCsv, document: CsvDocument(text: csv.text), contentType: .commaSeparatedText,
                      defaultFilename: "bench-doses-\(isoDay())") { result in
            if case .success = result { message = (.sky, t("settings_exported_csv", ["n": .number(Double(csv.rows.count))])) }
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
        case .local:
            #if LOCAL_ONLY
            #if os(macOS)
            t("ios_sync_test_mac")
            #else
            t("ios_sync_test")
            #endif
            #else
            t("ios_sync_local")
            #endif
        case .memory: t("ios_sync_memory")
        }
    }

    private func setting<V>(_ path: WritableKeyPath<BenchCore.Settings, V>) -> Binding<V> {
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
                .rowActions {
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
            FooterRow { Text(t("settings_profiles_note")) }
        } header: { Text(t("settings_profiles")) } footer: { FooterWrap { Text(t("settings_profiles_note")) }}
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
            #if os(macOS)
            RichText(t("ios_reminders_intro_mac")).font(.footnote).foregroundStyle(.secondary)
            #else
            RichText(t("reminders_intro")).font(.footnote).foregroundStyle(.secondary)
            #endif
            switch state {
            case nil: Text(t("reminders_checking")).font(.footnote).foregroundStyle(.secondary)
            case .available?: CalloutText(t("ios_notify_on")).font(.footnote).callout(.sky)
            case .notAsked?: CalloutText(t("ios_notify_ask")).font(.footnote).callout(.tangerine)
            case .denied?:
                CalloutText(t("ios_notify_off")).font(.footnote).callout(.tangerine)
                Button(t("ios_open_settings")) { if let url = notificationSettingsURL { openURL(url) } }
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
            FooterRow {
            Text(t("reminders_calendar_note").replacingOccurrences(of: "**", with: "") + (reminders.showCompound ? " " + t("reminders_named_warning") : ""))
        }
        } header: { Text(t("reminders_title")) } footer: { FooterWrap {
            Text(t("reminders_calendar_note").replacingOccurrences(of: "**", with: "") + (reminders.showCompound ? " " + t("reminders_named_warning") : ""))
        }}
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

// MARK: - Apple Health

private struct HealthSection: View {
    @Environment(AppStore.self) private var store
    @Environment(\.openURL) private var openURL
    @State private var state: HealthKitAdapter.Availability?
    @State private var busy = false
    @State private var result: String?

    var body: some View {
        Section {
            RichText(t("ios_health_desc")).font(.footnote).foregroundStyle(.secondary)
            switch state {
            case nil: Text(t("settings_checking")).font(.footnote).foregroundStyle(.secondary)
            case .unavailable?: CalloutText(t("ios_health_unavailable")).font(.footnote).callout(.tangerine)
            case .notAsked?:
                CalloutText(t("ios_health_not_asked")).font(.footnote).callout(.tangerine)
                Button { Task { await connect() } } label: { Label(busy ? t("settings_waiting") : t("ios_health_allow"), systemImage: "heart.text.square") }
                    .disabled(busy)
            case .asked?:
                CalloutText(t("ios_health_asked")).font(.footnote).callout(.sky)
                Button { Task { await sync() } } label: { Label(busy ? t("settings_syncing") : t("settings_sync_now"), systemImage: "arrow.triangle.2.circlepath") }
                    .disabled(busy)
                Text(t("ios_health_auto")).font(.caption).foregroundStyle(.secondary)
                Text(t("settings_read_only")).font(.caption).foregroundStyle(.secondary)
            }
            if state != nil && state != .unavailable, let url = URL(string: "x-apple-health://") {
                Button { openURL(url) } label: { Label(t("ios_health_title"), systemImage: "arrow.up.forward.app") }
            }
            if let result { Text(result).font(.footnote.weight(.medium)) }
        } header: { Text(t("ios_health_title")) }
        .task { state = await HealthKitAdapter.availability() }
    }

    private func connect() async {
        busy = true
        defer { busy = false }
        _ = await HealthKitAdapter.requestPermissions()
        state = await HealthKitAdapter.availability()
        if state == .asked { await sync() }
    }

    /// Weight since the newest stored reading, or the last year; then the month's vitals.
    private func sync() async {
        busy = true
        result = nil
        defer { busy = false }
        do {
            // Nil only when a pull on opening is already under way; it brings the same readings.
            let plan = try await HealthKitAdapter.pullWeight(into: store)
            await HealthKitAdapter.pullVitals(into: store)
            result = plan.map { describeSync(summarise($0)) } ?? t("ios_health_synced_already")
        } catch {
            result = t("ios_health_failed")
        }
    }
}

// MARK: - Automatic backups

private struct BackupsSection: View {
    @Environment(AppStore.self) private var store
    @State private var files: [BackupFile] = []
    @State private var note: String?
    @State private var restoring: BackupFile?

    var body: some View {
        let settings = store.data.settings
        Section {
            RichText(t("ios_backups_desc")).font(.footnote).foregroundStyle(.secondary)
            Picker(t("settings_take_one"), selection: Binding(get: { settings.backupEnabled ? settings.backupIntervalHours : 0 }, set: { v in
                store.mutate { d in
                    d.settings.backupEnabled = v > 0
                    if v > 0 { d.settings.backupIntervalHours = v }
                }
            })) {
                Text(t("reminders_never")).tag(0.0)
                Text(t("settings_every_6h")).tag(6.0)
                Text(t("plan_daily")).tag(24.0)
                Text(t("plan_weekly")).tag(168.0)
            }
            NumberRow(label: t("keep"), value: Binding(get: { settings.backupKeep }, set: { v in store.mutate { $0.settings.backupKeep = max(1, v.rounded(.down)) } }),
                      suffix: t("settings_copies"), range: 1...50)
            LabeledContent(t("settings_last_backup"), value: settings.lastBackupAt.map { relativeTime($0) } ?? t("reminders_never"))
            Button { backUp() } label: { Label(t("settings_back_up_now"), systemImage: "externaldrive.badge.plus") }
            if let note { Text(note).font(.footnote.weight(.medium)) }
            ForEach(files, id: \.name) { f in
                HStack {
                    VStack(alignment: .leading) {
                        Text("\(formatDate(f.at)) \(formatTime(f.at))").font(.subheadline)
                        if let size = f.size { Text("\(max(1, Int((Double(size) / 1024).rounded()))) KB").font(.caption).foregroundStyle(.secondary) }
                    }
                    Spacer()
                    Button(t("settings_restore")) { restoring = f }.buttonStyle(.bordered).controlSize(.small)
                }
            }
            FooterRow {
            Text(files.isEmpty ? t("settings_no_backups") : t("ios_backups_count", ["n": .number(Double(files.count))]) + " " + t("settings_keep_hint"))
        }
        } header: { Text(t("settings_backups")) } footer: { FooterWrap {
            Text(files.isEmpty ? t("settings_no_backups") : t("ios_backups_count", ["n": .number(Double(files.count))]) + " " + t("settings_keep_hint"))
        }}
        .onAppear { files = BackupFolder.list() }
        .confirmationDialog(t("settings_restore"), isPresented: Binding(get: { restoring != nil }, set: { if !$0 { restoring = nil } }), titleVisibility: .visible, presenting: restoring) { f in
            Button(t("settings_replace_all"), role: .destructive) { restore(f) }
            Button(t("settings_keep_what_i_have"), role: .cancel) {}
        } message: { f in Text(t("settings_restore_confirm", ["date": .string(formatDate(f.at))])) }
    }

    private func backUp() {
        let outcome = BackupFolder.run(store)
        if let name = outcome.name, outcome.ok {
            note = outcome.pruned > 0 ? t("settings_backup_saved", ["name": .string(name), "n": .number(Double(outcome.pruned))]) : t("settings_backup_written", ["name": .string(name)])
        } else {
            note = t("settings_backup_write_failed")
        }
        files = BackupFolder.list()
    }

    private func restore(_ f: BackupFile) {
        guard let raw = BackupFolder.read(f.name) else { note = t("settings_backup_read_failed"); return }
        guard let preview = try? AppData.load(raw) else { note = t("settings_backup_unreadable"); return }
        do {
            try store.importBackup(raw)
            note = t("settings_restored_from", ["name": .string(f.name), "doses": .string(t("count_doses", ["n": .number(Double(preview.logs.count))])),
                                                "protocols": .string(t("count_protocols", ["n": .number(Double(preview.protocols.count))])),
                                                "vials": .string(t("count_vials", ["n": .number(Double(preview.vials.count))]))])
        } catch {
            note = t("settings_backup_not_bench")
        }
        restoring = nil
    }
}

// MARK: - Lock

private struct LockSection: View {
    @AppStorage(AppLock.enabledKey) private var enabled = false
    @AppStorage(AppLock.delayKey) private var delay = 0.0
    @State private var failed = false

    var body: some View {
        Section {
            Toggle(t("ios_lock_toggle"), isOn: Binding(get: { enabled }, set: { on in
                if on {
                    // Only once it has been unlocked, so it cannot be set up to fail.
                    Task { failed = !(await AppLock.shared.turnOn()) }
                } else {
                    failed = false
                    AppLock.shared.turnOff()
                }
            }))
            .disabled(!AppLock.available && !enabled)
            if enabled {
                Picker(t("ios_lock_after"), selection: $delay) {
                    Text(t("ios_lock_now")).tag(0.0)
                    Text(t("ios_lock_1m")).tag(60.0)
                    Text(t("ios_lock_5m")).tag(300.0)
                }
            }
            if !AppLock.available && !enabled { Text(t("ios_lock_unavailable")).font(.footnote).foregroundStyle(Tone.tangerine.color) }
            if failed { Text(t("ios_lock_failed")).font(.footnote).foregroundStyle(Tone.tangerine.color) }
            FooterRow { Text(t("ios_lock_hint")) }
        } header: { Text(t("ios_lock_title")) } footer: { FooterWrap { Text(t("ios_lock_hint")) }}
    }
}
