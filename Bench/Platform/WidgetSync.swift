import Foundation
import AppIntents
import WidgetKit
import BenchCore
import BenchStore

/// Keeps the widgets' view of the plan current, and records what was logged from
/// a widget or Shortcut.
@MainActor
enum WidgetSync {
    /// A day and a half ahead is as far as a widget looks.
    private static let horizonMs = 36 * HOUR_MS

    static func snapshot(_ data: AppData, now: Millis = nowMillis()) -> WidgetSnapshot {
        let mine = data.mine
        let active = mine.protocols.filter { $0.active && $0.endedAt == nil && $0.schedule.kind != .asNeeded }
        var doses: [WidgetDose] = []
        for p in active {
            let peptide = data.peptide(p.peptideId)
            // The same logs that decide what Now shows as due.
            let answered = mine.logs.filter { $0.protocolId == p.id || $0.peptideId == p.peptideId }
            var times = unloggedDoseTimes(p, answered, now, now + horizonMs)
            let due = dueStatus(p, now, DueOptions(lastLoggedAt: answered.map(\.at).max()))
            if due.state != .none, let at = due.at, at <= now + horizonMs, !times.contains(at) { times.append(at) }
            for at in times {
                doses.append(WidgetDose(protocolId: p.id, name: peptide?.name ?? p.peptideId,
                                        amount: doseLabel(scheduledDoseMcg(p, at), peptide, resolve: { data.peptide($0) }), at: at))
            }
        }
        doses.sort { $0.at != $1.at ? $0.at < $1.at : $0.name < $1.name }
        let today = todayProgress(mine.protocols, mine.logs, now, earlyHours: data.settings.earlyHours)
        return WidgetSnapshot(
            showNames: data.settings.remindersOrDefault.showCompound,
            taken: today.taken, skipped: today.skipped, expected: today.expected,
            paused: currentPause(mine.protocols, now) != nil,
            protocols: active.map { WidgetProtocol(id: $0.id, name: data.peptide($0.peptideId)?.name ?? $0.peptideId) },
            doses: Array(doses.prefix(12)),
            labels: [
                "dueNow": t("ios_widget_due_now"), "overdue": t("ios_widget_overdue"), "next": t("ios_widget_next"),
                "log": t("ios_widget_log"), "doseWord": t("ios_widget_a_dose"), "allDone": t("ios_widget_all_done"),
                "nothing": t("ios_widget_nothing"), "open": t("ios_widget_open"), "today": t("ios_widget_today"),
                "paused": t("ios_widget_paused"),
            ],
            generatedAt: now)
    }

    /// Writes it, and tells the widgets only if it changed.
    static func update(_ data: AppData) {
        guard SharedStore.directory != nil else { return }
        if SharedStore.writeSnapshot(snapshot(data)) { WidgetCenter.shared.reloadAllTimelines() }
    }

    /// Records doses logged from a widget or Shortcut, as taken when they were tapped.
    static func applyPending(_ store: AppStore) {
        let pending = SharedStore.takePending()
        guard !pending.isEmpty else { return }
        store.mutate { d in
            for p in pending { d.logFromReminder(protocolId: p.protocolId, doseAt: p.doseAt, now: p.loggedAt) }
        }
        // Not left to a screen: this can run with the app only woken for a Shortcut.
        update(store.data)
        Task {
            for p in pending { await ReminderScheduler.clearSnoozes(protocolId: p.protocolId) }
            await ReminderScheduler.rearm(store.data)
        }
    }
}

/// "Log my dose in Bench", for Siri, Shortcuts and the Action button.
struct BenchShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: LogNextDoseIntent(),
                    phrases: ["Log my dose in \(.applicationName)", "Log my next dose in \(.applicationName)", "Log a dose in \(.applicationName)"],
                    shortTitle: "Log my next dose", systemImageName: "plus.circle")
    }
}
