import Foundation
import UserNotifications
import Observation
import BenchCore
import BenchStore
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

/// Stock notices: a vial used up (shown on Now until dismissed, and sent as a
/// notification when the app is not open) and "running low" notifications scheduled
/// from the plan. Local only; nothing leaves the device.
@MainActor @Observable
final class StockWatcher {
    static let shared = StockWatcher()

    /// Vials used up that have not been dismissed, oldest first.
    private(set) var pending: [String]
    @ObservationIgnored private var seen: Set<String>?
    @ObservationIgnored private let defaults = UserDefaults.standard
    private static let seenKey = "bench.emptyVialsSeen"
    private static let pendingKey = "bench.emptyVialsPending"
    private static let lowKey = "bench.lowStockSent"
    private static let lowPrefix = "bench.stock.low."

    private init() {
        pending = UserDefaults.standard.stringArray(forKey: Self.pendingKey) ?? []
        seen = UserDefaults.standard.stringArray(forKey: Self.seenKey).map(Set.init)
    }

    func dismiss(_ vialId: String) {
        pending.removeAll { $0 == vialId }
        defaults.set(pending, forKey: Self.pendingKey)
    }

    /// Called whenever the records change.
    func update(_ data: AppData, now: Millis = nowMillis()) async {
        await watchEmptied(data, now: now)
        await armLowStock(data, now: now)
    }

    // MARK: Empty vials

    private func watchEmptied(_ data: AppData, now: Millis) async {
        let used = data.mine.vials.filter(vialUsedUp)
        // The first run only notes what is already finished; nobody wants a notice for last year's vials.
        guard let known = seen else {
            seen = Set(used.map(\.id)); defaults.set(Array(seen!), forKey: Self.seenKey)
            return
        }
        let fresh = used.filter { !known.contains($0.id) }
        guard !fresh.isEmpty else { return }
        seen = known.union(fresh.map(\.id))
        defaults.set(Array(seen!), forKey: Self.seenKey)
        for v in fresh {
            pending.append(v.id)
            if data.settings.emptyVialNotify { await sendEmpty(v, data: data, now: now) }
        }
        defaults.set(pending, forKey: Self.pendingKey)
    }

    private var appIsOpen: Bool {
        #if canImport(UIKit)
        UIApplication.shared.applicationState == .active
        #else
        NSApp.isActive
        #endif
    }

    private func canNotify(_ data: AppData) async -> Bool {
        guard (data.settings.reminders ?? DEFAULT_REMINDERS).enabled else { return false }
        return await ReminderScheduler.availability() == .available
    }

    /// Only when the app is closed or in the background: open, the card on Now says it.
    private func sendEmpty(_ v: Vial, data: AppData, now: Millis) async {
        guard !appIsOpen, await canNotify(data) else { return }
        let named = (data.settings.reminders ?? DEFAULT_REMINDERS).showCompound
        let name = data.peptide(v.peptideId)?.name ?? v.peptideId
        let content = UNMutableNotificationContent()
        content.title = named ? name : "Dosebook"
        content.body = emptyVialText(data, v, named: named, now: now)
        content.sound = .default
        let request = UNNotificationRequest(identifier: "bench.stock.empty." + v.id, content: content,
                                            trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        try? await UNUserNotificationCenter.current().add(request)
    }

    // MARK: Running low

    /// Replaces the pending "running low" notifications with what the plan says now.
    /// Each compound is told once: after it has been sent, nothing more until the stock
    /// has been topped up and then runs down again.
    private func armLowStock(_ data: AppData, now: Millis) async {
        let center = UNUserNotificationCenter.current()
        let stale = await center.pendingNotificationRequests().map(\.identifier).filter { $0.hasPrefix(Self.lowPrefix) }
        center.removePendingNotificationRequests(withIdentifiers: stale)
        var sent = (defaults.dictionary(forKey: Self.lowKey) as? [String: Double]) ?? [:]
        defer { defaults.set(sent, forKey: Self.lowKey) }
        guard data.settings.lowStockNotify, await canNotify(data) else { return }
        let alerts = lowStockAlerts(data, nowMs: now)
        // A compound that has stopped being a concern is forgotten, so the next dip is told again.
        let current = Set(alerts.filter(\.lowNow).map(\.peptideId))
        for (id, at) in sent where at <= now && !current.contains(id) { sent[id] = nil }
        let named = (data.settings.reminders ?? DEFAULT_REMINDERS).showCompound
        for a in alerts {
            if let at = sent[a.peptideId], at <= now { continue }
            let content = UNMutableNotificationContent()
            content.title = named ? a.name : "Dosebook"
            content.body = named
                ? t("ios_low_stock_named", ["name": .string(a.name), "left": .string(t("count_doses", ["n": .number(a.dosesLeft)]))])
                : t("ios_low_stock_discreet")
            content.sound = .default
            let when = LocalTime.calendar.dateComponents([.year, .month, .day, .hour, .minute], from: Date(millis: a.fireAt))
            let request = UNNotificationRequest(identifier: Self.lowPrefix + a.peptideId, content: content,
                                                trigger: UNCalendarNotificationTrigger(dateMatching: when, repeats: false))
            try? await center.add(request)
            sent[a.peptideId] = a.fireAt
        }
    }
}

/// "Your BPC-157 vial is empty. You have 2 more in stock." The discreet form names nothing.
@MainActor func emptyVialText(_ data: AppData, _ v: Vial, named: Bool = true, now: Millis = nowMillis()) -> String {
    guard named else { return t("ios_empty_vial_discreet") }
    let name = data.peptide(v.peptideId)?.name ?? v.peptideId
    let left = vialsLeftInStock(data, like: v, nowMs: now)
    return left == 0
        ? t("ios_empty_vial_none", ["name": .string(name)])
        : t("ios_empty_vial_more", ["name": .string(name), "n": .number(Double(left))])
}
