import Foundation
import BenchCore

/// The clinician report as data, built once and shown twice: on screen and as a PDF.
struct ReportModel {
    struct Table { var head: [String]; var rows: [[String]] }
    struct Pair { var label: String; var value: String }

    var heading: String
    var meta: String
    var compiled: String
    var running: Table?
    var interactions: [(title: String, detail: String)]
    var bloodwork: Table?
    var outcomes: [Pair]
    var feeling: [Pair]
    var suppression: String?
    var history: Table?
    var historyNote: String?
    var footer: String

    init(_ data: AppData, windowDays: Double, now: Millis = nowMillis()) {
        let since = now - windowDays * DAY_MS
        let mine = data.mine
        let resolve: (String) -> Peptide? = { data.peptide($0) }
        let profile = data.activeProfile
        heading = t("report_heading")
        meta = t("report_meta", ["profile": .string(profile.name.isEmpty ? t("report_profile") : profile.name), "from": .string(formatDate(since, nowMs: now)),
                                 "to": .string(formatDate(now, nowMs: now)), "printed": .string(formatDate(now, nowMs: now))])
        compiled = t("report_compiled")

        let active = mine.protocols.filter(\.active)
        running = active.isEmpty ? nil : Table(
            head: [t("report_col_compound"), t("report_col_class"), t("report_col_dose"), t("report_col_frequency"), t("report_col_since"), t("report_col_adherence")],
            rows: active.map { p in
                let peptide = resolve(p.peptideId)
                let a = adherence(p, logsForProtocol(p, mine.logs), max(p.startedAt, since), now)
                return [peptide?.name ?? p.peptideId, peptide?.category.label ?? t("report_unknown"), formatDose(scheduledDoseMcg(p, now)),
                        t("report_per_week", ["n": .string(trim(protocolDosesPerWeek(p, now), 2))]), formatDate(p.startedAt, nowMs: now),
                        a.expected > 0 ? t("report_taken_of", ["taken": .number(Double(a.taken)), "expected": .number(Double(a.expected))]) : t("report_na")]
            })
        interactions = stackIssues(mine.protocols, resolve: resolve, nowMs: now).map { ($0.title, $0.detail) }

        let labs = mine.labs.filter { $0.at >= since }.sorted { $0.at > $1.at }
        bloodwork = labs.isEmpty ? nil : Table(
            head: [t("report_col_date"), t("report_col_marker"), t("report_col_result"), t("report_col_reference"), t("report_col_lab")],
            rows: labs.map { l in
                let marker = Library.marker(l.markerId)
                return [formatDate(l.at, nowMs: now), marker?.name ?? l.markerId, "\(jsNumberString(l.value)) \(marker?.unit ?? "")".trimmingCharacters(in: .whitespaces),
                        l.refLow != nil || l.refHigh != nil
                            ? t("report_range", ["low": .string(l.refLow.map { jsNumberString($0) } ?? ""), "high": .string(l.refHigh.map { jsNumberString($0) } ?? "")]).trimmingCharacters(in: .whitespaces)
                            : t("report_not_recorded"),
                        l.lab ?? t("report_not_recorded")]
            })

        let unit = data.settings.weightUnit
        let weight = weightChange(mine.measurements, since: since)
        let logs = mine.logs.filter { $0.at >= since }.sorted { $0.at > $1.at }
        let rated = mine.checkIns.filter { $0.at >= since }
        outcomes = [
            Pair(label: t("report_weight_change"), value: weight.map {
                t("report_weight_value", ["delta": .string("\($0.deltaKg > 0 ? "+" : "")\(trim(toDisplayWeight($0.deltaKg, unit), 1))"),
                                          "unit": .string(unit.rawValue), "days": .string(t("count_days", ["n": .number(windowDays)]))])
            } ?? t("report_not_recorded")),
            Pair(label: t("report_doses_logged"), value: String(logs.count)),
            Pair(label: t("report_days_rated"), value: String(rated.count)),
        ]
        let avg = averages(rated)
        feeling = avg.contains { $0.mean != nil } ? avg.map { a in
            Pair(label: a.label, value: a.mean.map { m in t("report_mean_value", ["mean": .string(trim(m, 1)), "days": .number(Double(a.days))]) } ?? t("report_na"))
        } : []

        let recovery = pctPlan(mine.logs, resolve: resolve, nowMs: now)
        if recovery.compounds.isEmpty {
            suppression = nil
        } else {
            let body = t("report_suppression_body", ["compounds": .string(t("count_compounds", ["n": .number(Double(recovery.compounds.count))])),
                                                     "list": .string(recovery.compounds.map { t("report_last_dose_on", ["name": .string($0.name), "date": .string(formatDate($0.lastDoseAt, nowMs: now))]) }.joined(separator: "; "))])
            let tail = !recovery.blockedBy.isEmpty ? t("report_no_clearance", ["names": .string(recovery.blockedBy.joined(separator: ", "))])
                : recovery.earliestStart.map { t("report_clears_around", ["date": .string(formatDate($0, nowMs: now))]) } ?? ""
            suppression = tail.isEmpty ? body : "\(body) \(tail)"
        }

        history = logs.isEmpty ? nil : Table(
            head: [t("report_col_date"), t("report_col_compound"), t("report_col_dose"), t("report_col_route"), t("report_col_site"), t("report_col_reported")],
            rows: logs.prefix(60).map { l in
                let reported = [l.feeling.map { FEELING_LABELS[$0] ?? String($0) }, (l.sideEffects ?? []).isEmpty ? nil : l.sideEffects!.joined(separator: ", ")]
                    .compactMap { $0 }.joined(separator: " · ")
                return [formatDate(l.at, nowMs: now), resolve(l.peptideId)?.name ?? l.peptideId, l.isSkipped ? t("report_skipped") : formatDose(l.doseMcg),
                        l.route.label, l.site?.rawValue ?? t("report_not_recorded"), reported.isEmpty ? t("report_nothing_reported") : reported]
            })
        historyNote = logs.count > 60 ? t("report_showing_recent", ["total": .number(Double(logs.count))]) : nil
        footer = t("report_footer")
    }

    // MARK: HTML for the PDF

    var html: String {
        func esc(_ s: String) -> String {
            s.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;").replacingOccurrences(of: ">", with: "&gt;")
        }
        func table(_ t: Table) -> String {
            "<table><thead><tr>" + t.head.map { "<th>\(esc($0))</th>" }.joined() + "</tr></thead><tbody>"
                + t.rows.map { "<tr>" + $0.map { "<td>\(esc($0))</td>" }.joined() + "</tr>" }.joined() + "</tbody></table>"
        }
        func pairs(_ ps: [Pair]) -> String {
            "<dl>" + ps.map { "<div><dt>\(esc($0.label))</dt><dd>\(esc($0.value))</dd></div>" }.joined() + "</dl>"
        }
        func section(_ title: String, _ body: String) -> String { "<section><h3>\(esc(title))</h3>\(body)</section>" }
        func empty(_ s: String) -> String { "<p class=\"empty\">\(esc(s))</p>" }
        var out = """
        <html><head><meta charset="utf-8"><style>
        body { font-family: -apple-system, Helvetica, sans-serif; font-size: 10pt; color: #111; }
        h2 { font-size: 16pt; margin: 0 0 4pt; } h3 { font-size: 11pt; margin: 14pt 0 6pt; border-bottom: 1px solid #ccc; padding-bottom: 2pt; }
        .meta, .compiled, .empty, footer { color: #555; } .compiled { font-size: 9pt; }
        table { width: 100%; border-collapse: collapse; } th { text-align: left; font-size: 8.5pt; color: #555; border-bottom: 1px solid #999; }
        td { font-size: 9pt; padding: 3pt 4pt 3pt 0; border-bottom: 1px solid #e3e3e3; vertical-align: top; } tr { page-break-inside: avoid; }
        dl { display: flex; flex-wrap: wrap; gap: 6pt 24pt; margin: 0; } dt { font-size: 8.5pt; color: #555; } dd { margin: 0; font-weight: 600; }
        footer { margin-top: 18pt; font-size: 8.5pt; border-top: 1px solid #ccc; padding-top: 6pt; }
        </style></head><body>
        <h2>\(esc(heading))</h2><p class="meta">\(esc(meta))</p><p class="compiled">\(esc(compiled))</p>
        """
        out += section(t("report_running"), running.map(table) ?? empty(t("report_nothing_active")))
        if !interactions.isEmpty {
            out += section(t("report_interactions"), "<ul>" + interactions.map { "<li><strong>\(esc($0.title)).</strong> \(esc($0.detail))</li>" }.joined() + "</ul>")
        }
        out += section(t("report_bloodwork"), bloodwork.map(table) ?? empty(t("report_no_labs")))
        out += section(t("report_outcomes"), pairs(outcomes) + (feeling.isEmpty ? "" : "<p class=\"meta\">\(esc(t("report_mean_rating")))</p>" + pairs(feeling)))
        if let suppression { out += section(t("report_suppression"), "<p>\(esc(suppression))</p>") }
        out += section(t("report_dose_history"), (history.map(table) ?? empty(t("report_no_doses"))) + (historyNote.map { "<p class=\"empty\">\(esc($0))</p>" } ?? ""))
        out += "<footer>\(esc(footer))</footer></body></html>"
        return out
    }
}
