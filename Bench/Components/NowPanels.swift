import SwiftUI
import BenchCore

/// The cards on the Now screen that can be switched off. Due and overdue doses, the
/// pause banner, tips and warnings always show: they are about something to do.
enum NowPanel: String, CaseIterable, Identifiable {
    case today, interactions, laterToday, chart, protocols, weight, checkIn, bloodwork, trends, worthSorting
    var id: String { rawValue }

    var title: String {
        switch self {
        case .today: t("ios_panel_today")
        case .interactions: t("ios_panel_interactions")
        case .laterToday: t("now_later_today")
        case .chart: t("now_circulating")
        case .protocols: t("now_active_protocols")
        case .weight: t("weight_title")
        case .checkIn: t("ios_panel_checkin")
        case .bloodwork: t("nav_bloodwork")
        case .trends: t("ios_panel_trends")
        case .worthSorting: t("now_worth_sorting")
        }
    }

    var symbol: String {
        switch self {
        case .today: "checkmark.circle"
        case .interactions: "exclamationmark.shield"
        case .laterToday: "clock"
        case .chart: "waveform.path.ecg"
        case .protocols: "syringe"
        case .weight: "scalemass"
        case .checkIn: "face.smiling"
        case .bloodwork: "drop"
        case .trends: "chart.bar"
        case .worthSorting: "list.bullet.clipboard"
        }
    }
}

/// Which panels are hidden, kept on this device (a phone and an iPad can differ).
struct NowPanels {
    static let key = "bench.now.hidden"

    static func hidden(_ raw: String) -> Set<NowPanel> {
        Set(raw.split(separator: ",").compactMap { NowPanel(rawValue: String($0)) })
    }

    static func raw(_ hidden: Set<NowPanel>) -> String {
        NowPanel.allCases.filter(hidden.contains).map(\.rawValue).joined(separator: ",")
    }
}
