import Foundation
import UserNotifications
import BenchCore
import BenchStore

/// Dose reminders as local notifications, armed from `remindersFor`. Scheduled
/// by the phone itself, so they fire with the app closed. Nothing leaves the device.
@MainActor
enum ReminderScheduler {
    enum Availability { case available, denied, notAsked }

    /// iOS keeps at most 64 pending; leave room for anything else.
    static let limit = 60
    private static let prefix = "bench.dose."
    /// Snoozed copies live apart, so re-arming from the plan does not cancel them.
    private static let snoozePrefix = "bench.snooze."
    static let category = "bench.dose"
    static let logAction = "bench.log"
    static let snoozeAction = "bench.snooze"

    /// "Logged" and "Snooze" on every dose reminder. Neither names the compound,
    /// so a discreet reminder stays discreet.
    static func registerActions() {
        let log = UNNotificationAction(identifier: logAction, title: t("ios_now_log_now"), options: [], icon: UNNotificationActionIcon(systemImageName: "plus"))
        let snooze = UNNotificationAction(identifier: snoozeAction, title: t("ios_snooze_15"), options: [], icon: UNNotificationActionIcon(systemImageName: "clock"))
        UNUserNotificationCenter.current().setNotificationCategories([UNNotificationCategory(identifier: category, actions: [log, snooze], intentIdentifiers: [])])
    }

    static func availability() async -> Availability {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: .available
        case .denied: .denied
        default: .notAsked
        }
    }

    static func requestPermission() async -> Bool {
        (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
    }

    /// Replaces every pending dose reminder with what the plan says now.
    static func rearm(_ data: AppData, now: Millis = nowMillis()) async {
        let center = UNUserNotificationCenter.current()
        let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
        center.removePendingNotificationRequests(withIdentifiers: pending)
        let settings = data.settings.reminders ?? DEFAULT_REMINDERS
        guard settings.enabled, await availability() == .available else { return }
        let mine = data.mine
        let due = remindersFor(protocols: mine.protocols, logs: mine.logs, peptides: data.allPeptides, settings: settings, nowMs: now)
        for r in due.prefix(limit) {
            let content = UNMutableNotificationContent()
            content.title = r.title
            content.body = r.body
            content.sound = .default
            content.categoryIdentifier = category
            content.userInfo = ["protocolId": r.protocolId, "doseAt": r.doseAt]
            let when = LocalTime.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(millis: r.at))
            let request = UNNotificationRequest(identifier: prefix + r.key, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }

    /// The same reminder again in fifteen minutes.
    static func snooze(title: String, body: String, protocolId: String, doseAt: Double) async {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        content.sound = .default
        content.categoryIdentifier = category
        content.userInfo = ["protocolId": protocolId, "doseAt": doseAt]
        let request = UNNotificationRequest(identifier: snoozePrefix + UUID().uuidString, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 15 * 60, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    /// Snoozes for a dose that has now been logged would only nag.
    static func clearSnoozes(protocolId: String) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests()
            .filter { $0.identifier.hasPrefix(snoozePrefix) && ($0.content.userInfo["protocolId"] as? String) == protocolId }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: stale)
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
        }
    }
}

/// Handles the buttons on a reminder. iOS wakes the app in the background to run
/// them, so this is set up at launch, before any screen exists.
@MainActor
final class NotificationHandler: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationHandler()
    weak var store: AppStore?

    func install(_ store: AppStore) {
        self.store = store
        UNUserNotificationCenter.current().delegate = self
        ReminderScheduler.registerActions()
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let content = response.notification.request.content
        let action = response.actionIdentifier
        let title = content.title, body = content.body
        guard let protocolId = content.userInfo["protocolId"] as? String, let doseAt = content.userInfo["doseAt"] as? Double else { return }
        switch action {
        case ReminderScheduler.logAction:
            await MainActor.run {
                guard let store = self.store else { return }
                store.mutate { $0.logFromReminder(protocolId: protocolId, doseAt: doseAt) }
            }
            await ReminderScheduler.clearSnoozes(protocolId: protocolId)
            if let data = await MainActor.run(body: { self.store?.data }) { await ReminderScheduler.rearm(data) }
        case ReminderScheduler.snoozeAction:
            await ReminderScheduler.snooze(title: title, body: body, protocolId: protocolId, doseAt: doseAt)
        default:
            break
        }
    }

    /// A reminder that fires while the app is open still shows, with its buttons.
    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }
}
