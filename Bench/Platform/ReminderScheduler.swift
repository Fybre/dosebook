import Foundation
import UserNotifications
import BenchCore

/// Dose reminders as local notifications, armed from `remindersFor`. Scheduled
/// by the phone itself, so they fire with the app closed. Nothing leaves the device.
@MainActor
enum ReminderScheduler {
    enum Availability { case available, denied, notAsked }

    /// iOS keeps at most 64 pending; leave room for anything else.
    static let limit = 60
    private static let prefix = "bench.dose."

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
            let when = LocalTime.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(millis: r.at))
            let request = UNNotificationRequest(identifier: prefix + r.key, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
        }
    }

    static func clear() {
        let center = UNUserNotificationCenter.current()
        Task {
            let pending = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(prefix) }
            center.removePendingNotificationRequests(withIdentifiers: pending)
        }
    }
}
