#if os(macOS)
import SwiftUI
import DosebookCore

/// Per-Mac preference; no health data or account information is sent to GitHub.
@MainActor @Observable
final class MacUpdates {
    static let shared = MacUpdates()
    static let enabledKey = "dosebook.updates.automatic"
    private let checkedKey = "dosebook.updates.checked"
    private let notifiedKey = "dosebook.updates.notified"
    private var loop: Task<Void, Never>?
    private(set) var checking = false
    private(set) var available: AppRelease?
    private(set) var status = ""
    var installed: String { Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown" }
    var enabled: Bool { UserDefaults.standard.bool(forKey: Self.enabledKey) }

    private init() {
        if let data = UserDefaults.standard.data(forKey: "dosebook.updates.release"),
           let release = try? JSONDecoder().decode(AppRelease.self, from: data),
           release.isUpdate(for: installed) {
            available = release
            status = t("mac_updates_available", ["version": .string(release.version)])
        }
    }

    func start() {
        guard loop == nil else { return }
        loop = Task {
            while !Task.isCancelled {
                await check()
                try? await Task.sleep(for: .seconds(3600))
            }
        }
    }

    func check(manual: Bool = false) async {
        guard !checking, manual || enabled else { return }
        if !manual {
            notifyIfNeeded()
            if let last = UserDefaults.standard.object(forKey: checkedKey) as? Date,
               Date().timeIntervalSince(last) < 86400 { return }
        }
        checking = true
        defer { checking = false }
        status = t("mac_updates_checking")
        // Also throttle failures so activation cannot repeatedly hit a rate limit.
        UserDefaults.standard.set(Date(), forKey: checkedKey)
        do {
            var request = URLRequest(url: URL(string: "https://api.github.com/repos/Fybre/dosebook/releases/latest")!)
            request.timeoutInterval = 20
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
            let (data, response) = try await URLSession.shared.data(for: request)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else { throw URLError(.badServerResponse) }
            let release = try JSONDecoder().decode(AppRelease.self, from: data)
            guard AppVersion(installed) != nil, AppVersion(release.tag_name) != nil,
                  !release.draft, !release.prerelease,
                  release.assets.contains(where: { $0.name == "Dosebook.dmg" && $0.state == "uploaded" }) else {
                throw URLError(.cannotParseResponse)
            }
            available = release.isUpdate(for: installed) ? release : nil
            UserDefaults.standard.set(data, forKey: "dosebook.updates.release")
            status = available == nil ? t("mac_updates_current") : t("mac_updates_available", ["version": .string(release.version)])
            if !manual { notifyIfNeeded() }
        } catch {
            status = t("mac_updates_failed")
        }
    }

    private func notifyIfNeeded() {
        guard enabled, NSApp.isActive, !AppLock.shared.locked,
              let release = available,
              UserDefaults.standard.string(forKey: notifiedKey) != release.tag_name,
              let window = NSApp.keyWindow ?? NSApp.mainWindow, window.attachedSheet == nil else { return }
        UserDefaults.standard.set(release.tag_name, forKey: notifiedKey)
        let alert = NSAlert()
        alert.messageText = t("mac_updates_available", ["version": .string(release.version)])
        alert.informativeText = t("mac_updates_notice")
        alert.addButton(withTitle: t("mac_updates_download"))
        alert.addButton(withTitle: t("mac_updates_later"))
        alert.beginSheetModal(for: window) { response in
            if response == .alertFirstButtonReturn { NSWorkspace.shared.open(release.url) }
        }
    }
}

struct MacUpdatesSection: View {
    @AppStorage(MacUpdates.enabledKey) private var automatic = false
    private var updates: MacUpdates { .shared }

    var body: some View {
        Section {
            LabeledContent(t("mac_updates_installed"), value: updates.installed)
            Toggle(t("mac_updates_automatic"), isOn: $automatic)
                .onChange(of: automatic) { _, enabled in
                    if enabled { Task { await updates.check() } }
                }
            Button(t("mac_updates_check")) { Task { await updates.check(manual: true) } }
                .disabled(updates.checking)
            if !updates.status.isEmpty { Text(updates.status).font(.footnote).foregroundStyle(.secondary) }
            if let release = updates.available {
                Link(t("mac_updates_download"), destination: release.url)
            }
            FooterRow { Text(t("mac_updates_hint")) }
        } header: { Text(t("mac_updates_title")) } footer: {
            FooterWrap { Text(t("mac_updates_hint")) }
        }
    }
}
#endif
