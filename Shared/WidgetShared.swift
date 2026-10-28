import Foundation
import AppIntents
import WidgetKit
import UserNotifications

// What the app, its widgets and Shortcuts share. Plain Foundation only, so the
// widget stays small: a snapshot of today's doses the app writes into an App Group
// folder, and a folder of doses logged from outside the app, which the app applies
// the moment it can. The app's own database is never opened from here.

/// The prefix on every dose reminder's id (see `ReminderScheduler`).
let REMINDER_ID_PREFIX = "bench.dose."

struct WidgetDose: Codable, Equatable, Identifiable {
    var protocolId: String
    var name: String
    /// "250 mcg", or "250 mcg each" for a blend.
    var amount: String
    /// When it is scheduled, in milliseconds.
    var at: Double
    var id: String { "\(protocolId)@\(Int64(at))" }
}

struct WidgetProtocol: Codable, Equatable { var id: String; var name: String }

struct WidgetSnapshot: Codable, Equatable {
    /// Whether compound names may be shown on a screen anyone can see; the reminder setting.
    var showNames: Bool
    var taken: Int
    var skipped: Int
    var expected: Int
    /// Everything is paused, so nothing is due however empty the list looks.
    var paused = false
    var protocols: [WidgetProtocol]
    /// Doses not yet logged, soonest first: what is overdue and the next day and a half.
    var doses: [WidgetDose]
    /// The few words a widget shows, in the app's language, as the app last wrote them.
    var labels: [String: String] = [:]
    var generatedAt: Double
}

/// A dose logged from a widget or Shortcut, waiting for the app to record it.
struct PendingLog: Codable { var protocolId: String; var doseAt: Double; var loggedAt: Double }

enum SharedStore {
    /// Named in each target's Info.plist, so the test and release builds keep apart.
    static var group: String? { Bundle.main.object(forInfoDictionaryKey: "BenchAppGroup") as? String }
    static var directory: URL? { group.flatMap { FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: $0) } }
    private static var snapshotURL: URL? { directory?.appendingPathComponent("widget-snapshot.json") }
    private static var pendingDirectory: URL? {
        guard let dir = directory?.appendingPathComponent("pending", isDirectory: true) else { return nil }
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    static func readSnapshot() -> WidgetSnapshot? {
        guard let url = snapshotURL, let data = try? Data(contentsOf: url) else { return nil }
        return try? JSONDecoder().decode(WidgetSnapshot.self, from: data)
    }

    /// True when it changed, so widgets are only told to redraw when they need to be.
    @discardableResult
    static func writeSnapshot(_ s: WidgetSnapshot) -> Bool {
        guard let url = snapshotURL else { return false }
        var forComparison = s
        forComparison.generatedAt = 0
        var old = readSnapshot()
        old?.generatedAt = 0
        if old == forComparison { return false }
        guard let data = try? JSONEncoder().encode(s) else { return false }
        return (try? data.write(to: url, options: .atomic)) != nil
    }

    static func addPending(_ p: PendingLog) {
        guard let dir = pendingDirectory, let data = try? JSONEncoder().encode(p) else { return }
        try? data.write(to: dir.appendingPathComponent("\(UUID().uuidString).json"), options: .atomic)
    }

    /// Everything waiting, oldest first, removed as it is read.
    static func takePending() -> [PendingLog] {
        guard let dir = pendingDirectory, let files = try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) else { return [] }
        var out: [PendingLog] = []
        for f in files where f.pathExtension == "json" {
            if let data = try? Data(contentsOf: f), let p = try? JSONDecoder().decode(PendingLog.self, from: data) { out.append(p) }
            try? FileManager.default.removeItem(at: f)
        }
        return out.sorted { $0.loggedAt < $1.loggedAt }
    }
}

/// Set by the app. In the app's own process (Shortcuts, Siri, the Action button) a
/// logged dose is recorded at once; in a widget's it waits for the app to open.
enum LogInbox {
    @MainActor static var apply: (() -> Void)?
}

enum LogRecorder {
    /// The widest gap between now and a dose that "my next dose" will log.
    static let reachMs = 60.0 * 60_000

    @MainActor
    static func record(protocolId: String, doseAt: Double) {
        SharedStore.addPending(PendingLog(protocolId: protocolId, doseAt: doseAt, loggedAt: Date().timeIntervalSince1970 * 1000))
        // Out of the snapshot now, so the widget does not offer it again before the app has looked.
        if var s = SharedStore.readSnapshot() {
            if let i = s.doses.firstIndex(where: { $0.protocolId == protocolId && $0.at == doseAt }) {
                s.doses.remove(at: i)
                s.taken += 1
                SharedStore.writeSnapshot(s)
            }
        }
        // A reminder for a dose already logged would only nag.
        let key = "\(protocolId):\(Int64(doseAt))"
        UNUserNotificationCenter.current().removePendingNotificationRequests(withIdentifiers: [REMINDER_ID_PREFIX + key])
        LogInbox.apply?()
        WidgetCenter.shared.reloadAllTimelines()
    }
}

/// Log one scheduled dose: the button on a widget.
struct LogDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log dose"
    static let description = IntentDescription("Logs a scheduled dose, as taken now, at the next injection site.")
    static let openAppWhenRun = false

    @Parameter(title: "Protocol") var protocolId: String
    @Parameter(title: "Scheduled at") var doseAt: Double

    init() {}
    init(protocolId: String, doseAt: Double) { self.protocolId = protocolId; self.doseAt = doseAt }

    @MainActor func perform() async throws -> some IntentResult {
        LogRecorder.record(protocolId: protocolId, doseAt: doseAt)
        return .result()
    }
}

struct ProtocolEntity: AppEntity {
    static let typeDisplayRepresentation: TypeDisplayRepresentation = "Protocol"
    static let defaultQuery = ProtocolQuery()
    var id: String
    var name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}

struct ProtocolQuery: EntityQuery {
    func entities(for identifiers: [String]) async throws -> [ProtocolEntity] {
        (SharedStore.readSnapshot()?.protocols ?? []).filter { identifiers.contains($0.id) }.map { ProtocolEntity(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [ProtocolEntity] {
        (SharedStore.readSnapshot()?.protocols ?? []).map { ProtocolEntity(id: $0.id, name: $0.name) }
    }
}

/// "Log my next dose": the one that is due, or the one you name. For Siri, Shortcuts
/// and the Action button.
struct LogNextDoseIntent: AppIntent {
    static let title: LocalizedStringResource = "Log my next dose"
    static let description = IntentDescription("Logs the dose that is due now, as taken now, at the next injection site.")
    static let openAppWhenRun = false

    @Parameter(title: "Protocol", description: "Leave empty for whichever is due.") var protocolChoice: ProtocolEntity?

    static var parameterSummary: some ParameterSummary { Summary("Log my next dose \(\.$protocolChoice)") }

    init() {}

    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        guard let snapshot = SharedStore.readSnapshot() else {
            return .result(dialog: "Open Dosebook once, so it can see your plan.")
        }
        let now = Date().timeIntervalSince1970 * 1000
        let due = snapshot.doses
            .filter { protocolChoice == nil || $0.protocolId == protocolChoice?.id }
            .filter { $0.at <= now + LogRecorder.reachMs }
            .min { $0.at < $1.at }
        guard let dose = due else { return .result(dialog: "Nothing is due right now.") }
        LogRecorder.record(protocolId: dose.protocolId, doseAt: dose.at)
        // Said aloud, so the name only when names are allowed on screen.
        return .result(dialog: snapshot.showNames ? "Logged \(dose.name), \(dose.amount)." : "Logged your dose.")
    }
}
