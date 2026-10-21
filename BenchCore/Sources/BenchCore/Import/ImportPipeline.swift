import Foundation

// Port of src/lib/import/pipeline.ts. The one place that knows about file
// types: from a chosen file to something the screen can show. A Bench export
// short-circuits, since it replaces everything rather than merging.

public enum SourceFormat: String, Sendable { case csv, json, xlsx, pdf }

public enum ReadResult: Sendable {
    /// One of this app's own exports; the raw bytes go to the restore path.
    case benchExport(Data)
    case table(format: SourceFormat, profile: ImportProfile, table: ImportTable, plan: ImportPlan)
    /// Bloodwork, matched analyte by analyte and confirmed row by row.
    case labReport(LabReport, lines: [String])
}

public struct ImportError: Error, Equatable { public var message: String }

public let ACCEPTED_EXTENSIONS = ["csv", "tsv", "txt", "json", "xlsx", "xlsm", "pdf"]

public struct ImportOptions: Sendable {
    public var peptides: [Peptide]
    public var existingLogs: [(at: Millis, peptideId: String)]
    public var existingMeasurements: [(at: Millis, weightKg: Double?)]
    public init(peptides: [Peptide], existingLogs: [(at: Millis, peptideId: String)], existingMeasurements: [(at: Millis, weightKg: Double?)]) {
        self.peptides = peptides; self.existingLogs = existingLogs; self.existingMeasurements = existingMeasurements
    }
    /// What the active profile already holds.
    public init(_ data: AppData) {
        self.init(peptides: data.allPeptides, existingLogs: data.mine.logs.map { ($0.at, $0.peptideId) },
                  existingMeasurements: data.mine.measurements.map { ($0.at, $0.weightKg) })
    }
}

/// Decode a file and work out what importing it would do. `pdfFallback` reads
/// a PDF's text another way when the built-in extractor finds none.
public func readImportFile(name: String, bytes: [UInt8], options: ImportOptions,
                           pdfFallback: (([UInt8]) -> [String])? = nil) throws -> ReadResult {
    let ext = name.split(separator: ".").count > 1 ? String(name.split(separator: ".").last!).lowercased() : ""
    if ext == "xls" {
        throw ImportError(message: "The old .xls format cannot be read. Open it and save as .xlsx or .csv, then try again.")
    }

    if ext == "pdf" {
        var lines: [String]
        do { lines = try readPdfText(bytes).lines } catch let e as PdfError { throw ImportError(message: e.message) }
        var report = parseLabReport(lines)
        if report.candidates.isEmpty, let fallback = pdfFallback {
            let other = fallback(bytes).map { JSRegex(#"\s+"#).replaceAll($0, " ").trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
            let second = parseLabReport(other)
            if !second.candidates.isEmpty || lines.isEmpty { lines = other; report = second }
        }
        if lines.isEmpty {
            throw ImportError(message: "No text found in that PDF. If it is a scan or a photograph, the words are pixels rather than text and cannot be read on the device. Ask the lab for the original file, or enter the results by hand.")
        }
        if report.candidates.isEmpty {
            throw ImportError(message: "Read \(lines.count) lines from that PDF but recognised no blood markers in them. It may not be a lab report, or it may use names the app does not know yet.")
        }
        return .labReport(report, lines: lines)
    }

    var rows: [[String]]
    var format: SourceFormat
    if ext == "xlsx" || ext == "xlsm" {
        format = .xlsx
        do { rows = try readXlsx(bytes) } catch let e as XlsxError { throw ImportError(message: e.message) }
    } else if ext == "json" {
        format = .json
        guard let parsed = OrderedJSON.parse(String(decoding: bytes, as: UTF8.self)) else {
            throw ImportError(message: "That file is not valid JSON.")
        }
        if isBenchExport(parsed) { return .benchExport(Data(bytes)) }
        rows = jsonToRows(parsed)
        if rows.isEmpty {
            throw ImportError(message: "That JSON has no list of records in it. A Bench export, or an array of rows, can be read.")
        }
    } else {
        format = .csv
        rows = parseDelimited(String(decoding: bytes, as: UTF8.self))
    }

    let table = toTable(rows)
    guard !table.headers.isEmpty else { throw ImportError(message: "That file appears to be empty.") }
    guard let profile = detectProfile(table.headers) else {
        throw ImportError(message: "Could not tell what these columns mean: \(table.headers.prefix(8).joined(separator: ", ")). A date column plus a column naming what was taken, or a weight, is the minimum needed.")
    }
    let read = profile.read(table.records, table.headers)
    let plan = buildImportPlan(records: read.records, problems: read.problems, peptides: options.peptides,
                               existingLogs: options.existingLogs, existingMeasurements: options.existingMeasurements)
    return .table(format: format, profile: profile, table: table, plan: plan)
}

/// Its own export always carries these three together; no other tracker does.
private func isBenchExport(_ v: OrderedJSON) -> Bool {
    guard case .object(let o) = v else { return false }
    let get = { (k: String) in o.first { $0.0 == k }?.1 }
    if case .array = get("logs"), case .array = get("protocols"), case .number = get("version") { return true }
    return false
}

/// A bare array of objects, or an object holding exactly one array.
func jsonToRows(_ value: OrderedJSON) -> [[String]] {
    var list: [OrderedJSON]?
    if case .array(let a) = value { list = a }
    if list == nil, case .object(let o) = value {
        let arrays = o.compactMap { if case .array(let a) = $0.1 { a } else { nil } }
        if arrays.count == 1 { list = arrays[0] }
    }
    guard let list, !list.isEmpty else { return [] }
    let objects = list.compactMap { if case .object(let o) = $0 { o } else { nil } }
    guard !objects.isEmpty else { return [] }
    var headers: [String] = []
    for o in objects { for (k, _) in o where !headers.contains(k) { headers.append(k) } }
    let cell = { (v: OrderedJSON?) -> String in
        switch v {
        case nil, .null?: ""
        case .string(let s)?: s
        case .number(let n)?: jsNumberString(n)
        case .bool(let b)?: b ? "true" : "false"
        case let other?: other.stringify()
        }
    }
    return [headers] + objects.map { o in headers.map { h in cell(o.first { $0.0 == h }?.1) } }
}

/// JSON with object keys in document order, as a JS object keeps them.
indirect enum OrderedJSON: Equatable {
    case null, bool(Bool), number(Double), string(String), array([OrderedJSON]), object([(String, OrderedJSON)])

    static func == (a: OrderedJSON, b: OrderedJSON) -> Bool { a.stringify() == b.stringify() }

    /// `JSON.stringify`, compact.
    func stringify() -> String {
        switch self {
        case .null: return "null"
        case .bool(let b): return b ? "true" : "false"
        case .number(let n): return n.isFinite ? jsNumberString(n) : "null"
        case .string(let s): return Self.quote(s)
        case .array(let a): return "[" + a.map { $0.stringify() }.joined(separator: ",") + "]"
        case .object(let o): return "{" + o.map { Self.quote($0.0) + ":" + $0.1.stringify() }.joined(separator: ",") + "}"
        }
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for u in s.unicodeScalars {
            switch u {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            default:
                if u.value < 0x20 { out += String(format: "\\u%04x", u.value) } else { out.unicodeScalars.append(u) }
            }
        }
        return out + "\""
    }

    static func parse(_ text: String) -> OrderedJSON? {
        var p = Parser(chars: Array(text.unicodeScalars))
        p.skipWs()
        guard let v = p.value() else { return nil }
        p.skipWs()
        return p.i == p.chars.count ? v : nil
    }

    private struct Parser {
        var chars: [Unicode.Scalar]
        var i = 0
        mutating func skipWs() { while i < chars.count, [" ", "\n", "\r", "\t"].contains(chars[i]) { i += 1 } }
        mutating func literal(_ word: String) -> Bool {
            let w = Array(word.unicodeScalars)
            guard i + w.count <= chars.count, Array(chars[i..<(i + w.count)]) == w else { return false }
            i += w.count
            return true
        }
        mutating func value() -> OrderedJSON? {
            guard i < chars.count else { return nil }
            switch chars[i] {
            case "{":
                i += 1; skipWs()
                var o: [(String, OrderedJSON)] = []
                if i < chars.count, chars[i] == "}" { i += 1; return .object(o) }
                while true {
                    skipWs()
                    guard let k = string() else { return nil }
                    skipWs()
                    guard i < chars.count, chars[i] == ":" else { return nil }
                    i += 1; skipWs()
                    guard let v = value() else { return nil }
                    // A repeated key keeps its first position and its last value, as in JS.
                    if let at = o.firstIndex(where: { $0.0 == k }) { o[at].1 = v } else { o.append((k, v)) }
                    skipWs()
                    guard i < chars.count else { return nil }
                    if chars[i] == "," { i += 1; continue }
                    if chars[i] == "}" { i += 1; return .object(o) }
                    return nil
                }
            case "[":
                i += 1; skipWs()
                var a: [OrderedJSON] = []
                if i < chars.count, chars[i] == "]" { i += 1; return .array(a) }
                while true {
                    skipWs()
                    guard let v = value() else { return nil }
                    a.append(v)
                    skipWs()
                    guard i < chars.count else { return nil }
                    if chars[i] == "," { i += 1; continue }
                    if chars[i] == "]" { i += 1; return .array(a) }
                    return nil
                }
            case "\"": return string().map(OrderedJSON.string)
            case "t": return literal("true") ? .bool(true) : nil
            case "f": return literal("false") ? .bool(false) : nil
            case "n": return literal("null") ? .null : nil
            default:
                let start = i
                while i < chars.count, "+-0123456789.eE".unicodeScalars.contains(chars[i]) { i += 1 }
                let s = String(String.UnicodeScalarView(chars[start..<i]))
                guard !s.isEmpty, let n = Double(s) else { return nil }
                return .number(n)
            }
        }
        mutating func string() -> String? {
            guard i < chars.count, chars[i] == "\"" else { return nil }
            i += 1
            var units: [UInt16] = []
            while i < chars.count {
                let c = chars[i]
                if c == "\"" { i += 1; return String(decoding: units, as: UTF16.self) }
                if c == "\\" {
                    i += 1
                    guard i < chars.count else { return nil }
                    switch chars[i] {
                    case "\"": units.append(34)
                    case "\\": units.append(92)
                    case "/": units.append(47)
                    case "b": units.append(8)
                    case "f": units.append(12)
                    case "n": units.append(10)
                    case "r": units.append(13)
                    case "t": units.append(9)
                    case "u":
                        guard i + 4 < chars.count, let v = UInt16(String(String.UnicodeScalarView(chars[(i + 1)...(i + 4)])), radix: 16) else { return nil }
                        units.append(v); i += 4
                    default: return nil
                    }
                    i += 1
                    continue
                }
                units.append(contentsOf: Array(String(c).utf16))
                i += 1
            }
            return nil
        }
    }
}
