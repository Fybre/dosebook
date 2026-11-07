import Foundation

// Port of src/lib/calc/dosecsv.ts. The dose history as a CSV, oldest first.
// One deliberate difference: the time column is always 24-hour HH:mm, where the
// original used the browser's locale. A file handed to a clinician should not
// change shape with the phone's region settings.

public let DOSE_CSV_HEADER = [
    "date", "time", "peptide", "dose_mcg", "dose_mg", "route", "site", "units", "syringe_scale", "volume_ml",
    "skipped", "feeling", "side_effects", "notes", "presses", "tablets",
]

/// Quote only when the value would otherwise break the row.
public func escapeCsv(_ value: String) -> String {
    value.contains(where: { $0 == "\"" || $0 == "," || $0 == "\n" })
        ? "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
        : value
}

private func num(_ d: Double?) -> String { d.map(jsNumberString) ?? "" }

public func doseCsv(_ logs: [DoseLog], nameFor: (String) -> String) -> (rows: [String], text: String) {
    let cal = LocalTime.calendar
    let rows = logs.stableSorted { $0.at < $1.at }.map { l -> String in
        let c = cal.dateComponents([.year, .month, .day, .hour, .minute], from: Date(millis: l.at))
        let date = String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
        let time = String(format: "%02d:%02d", c.hour!, c.minute!)
        let feeling = l.feeling.map { FEELING_LABELS[$0] ?? String($0) } ?? ""
        return [
            date, time, nameFor(l.peptideId), jsNumberString(l.doseMcg), jsNumberString(l.doseMcg / 1000), l.route.rawValue,
            l.site.flatMap { s in INJECTION_SITES.first { $0.id == s }?.label } ?? "",
            num(l.units), l.syringeScale?.rawValue ?? "", num(l.volumeMl), l.isSkipped ? "yes" : "no", feeling,
            (l.sideEffects ?? []).joined(separator: "; "), l.notes ?? "", num(l.presses), num(l.tablets),
        ].map(escapeCsv).joined(separator: ",")
    }
    return (rows, ([DOSE_CSV_HEADER.joined(separator: ",")] + rows).joined(separator: "\n"))
}
