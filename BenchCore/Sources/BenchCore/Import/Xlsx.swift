import Foundation

// Port of src/lib/import/xlsx.ts. The first worksheet of an .xlsx into the same
// rows the CSV reader produces, with date-formatted cells turned into ISO text.

private let EPOCH_SERIAL_1900: Double = 25569
private let SERIAL_1904_OFFSET: Double = 1462

private let BUILTIN_DATE_FORMATS: Set<Int> = Set(Array(14...22) + Array(27...36) + Array(45...47) + Array(50...58))

/// Excel serial to epoch ms. Serial 60 is Excel's non-existent 29 February 1900.
public func serialToMs(_ serial: Double, date1904: Bool = false) -> Double {
    if date1904 { return jsRound((serial + SERIAL_1904_OFFSET - EPOCH_SERIAL_1900) * DAY_MS) }
    let epoch = serial < 60 ? EPOCH_SERIAL_1900 - 1 : EPOCH_SERIAL_1900
    return jsRound((serial - epoch) * DAY_MS)
}

/// JS `toISOString`, in UTC with milliseconds.
func isoString(_ ms: Double) -> String {
    let f = DateFormatter()
    f.locale = Locale(identifier: "en_US_POSIX")
    f.timeZone = TimeZone(identifier: "UTC")
    f.calendar = Calendar(identifier: .gregorian)
    f.dateFormat = "yyyy-MM-dd'T'HH:mm:ss.SSS'Z'"
    return f.string(from: Date(millis: ms))
}

private func serialToIso(_ serial: Double, _ date1904: Bool) -> String {
    let iso = isoString(serialToMs(serial, date1904: date1904))
    // Whole-day serials stay bare dates so no timezone can move them.
    return serial == serial.rounded() ? String(iso.prefix(10)) : iso
}

func unescapeXml(_ s: String) -> String {
    var out = s.replacingOccurrences(of: "&lt;", with: "<").replacingOccurrences(of: "&gt;", with: ">")
        .replacingOccurrences(of: "&quot;", with: "\"").replacingOccurrences(of: "&apos;", with: "'")
    out = JSRegex("&#(\\d+);").replaceAll(out) { m in Int(m[1]!).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? m[0]! }
    out = JSRegex("&#x([0-9a-fA-F]+);").replaceAll(out) { m in Int(m[1]!, radix: 16).flatMap(Unicode.Scalar.init).map { String(Character($0)) } ?? m[0]! }
    return out.replacingOccurrences(of: "&amp;", with: "&")
}

private func parseSharedStrings(_ xml: String) -> [String] {
    JSRegex(#"<si\b[^>]*/>|<si\b[\s\S]*?</si>"#).all(xml).map { si in
        JSRegex(#"<t\b[^>]*>([\s\S]*?)</t>"#).all(si[0]!).map { unescapeXml($0[1]!) }.joined()
    }
}

private func parseStyles(_ xml: String) -> Set<Int> {
    var customDateIds = Set<Int>()
    for m in JSRegex(#"<numFmt\b[^>]*numFmtId="(\d+)"[^>]*formatCode="([^"]*)""#).all(xml) {
        let code = unescapeXml(m[2]!)
        let bare = JSRegex(#"\[[^\]]*\]"#).replaceAll(JSRegex(#""[^"]*""#).replaceAll(code, ""), "")
        if JSRegex("[ymdhs]", "i").test(bare) { customDateIds.insert(Int(m[1]!)!) }
    }
    let cellXfs = JSRegex(#"<cellXfs\b[^>]*>([\s\S]*?)</cellXfs>"#).exec(xml)?[1] ?? ""
    var dateXfs = Set<Int>()
    for (i, xf) in JSRegex(#"<xf\b[^>]*/>|<xf\b[\s\S]*?</xf>"#).all(cellXfs).enumerated() {
        let id = Int(JSRegex(#"numFmtId="(\d+)""#).exec(xf[0]!)?[1] ?? "0")!
        if BUILTIN_DATE_FORMATS.contains(id) || customDateIds.contains(id) { dateXfs.insert(i) }
    }
    return dateXfs
}

/// Column letters to a zero-based index: A→0, Z→25, AA→26.
public func columnToIndex(_ ref: String) -> Int {
    guard let letters = JSRegex("^([A-Z]+)").exec(ref.uppercased())?[1] else { return -1 }
    var n = 0
    for u in letters.unicodeScalars { n = n * 26 + Int(u.value) - 64 }
    return n - 1
}

private func parseSheet(_ xml: String, _ shared: [String], _ dateXfs: Set<Int>, _ date1904: Bool) -> [[String]] {
    var rows: [[String]] = []
    for rowXml in JSRegex(#"<row\b[^>]*/>|<row\b[\s\S]*?</row>"#).all(xml) {
        var cells: [String] = []
        for cellMatch in JSRegex(#"<c\b[^>]*/>|<c\b[\s\S]*?</c>"#).all(rowXml[0]!) {
            let cellXml = cellMatch[0]!
            let ref = JSRegex(#"r="([A-Z]+\d+)""#).exec(cellXml)?[1]
            let index = ref.map(columnToIndex) ?? cells.count
            let type = JSRegex(#"\st="([^"]+)""#).exec(cellXml)?[1] ?? "n"
            let styleIndex = Int(JSRegex(#"\ss="(\d+)""#).exec(cellXml)?[1] ?? "-1")!
            var value = ""
            if type == "inlineStr" {
                value = JSRegex(#"<t\b[^>]*>([\s\S]*?)</t>"#).all(cellXml).map { unescapeXml($0[1]!) }.joined()
            } else if let raw = JSRegex(#"<v\b[^>]*>([\s\S]*?)</v>"#).exec(cellXml)?[1] {
                let text = unescapeXml(raw)
                if type == "s" {
                    value = Int(text).flatMap { $0 >= 0 && $0 < shared.count ? shared[$0] : nil } ?? ""
                } else if type == "b" {
                    value = text == "1" ? "TRUE" : "FALSE"
                } else if type == "n" && dateXfs.contains(styleIndex) && !text.trimmingCharacters(in: .whitespaces).isEmpty {
                    let serial = text.jsNumber
                    value = serial.isFinite ? serialToIso(serial, date1904) : text
                } else {
                    value = text
                }
            }
            guard index >= 0 else { continue }
            while cells.count <= index { cells.append("") }
            cells[index] = value
        }
        rows.append(cells)
    }
    let width = rows.map(\.count).max() ?? 0
    return rows.map { $0 + Array(repeating: "", count: width - $0.count) }
}

public struct XlsxError: Error, Equatable { public var message: String }

/// The first worksheet of an .xlsx into rows.
public func readXlsx(_ bytes: [UInt8]) throws -> [[String]] {
    guard bytes.count >= 4, bytes[0] == 0x50, bytes[1] == 0x4b else {
        throw XlsxError(message: "That is not an .xlsx file. The old .xls format and renamed CSVs are not readable, re-save it as .xlsx or .csv.")
    }
    let files: [String: [UInt8]]
    do { files = try Zip.entries(bytes) } catch {
        throw XlsxError(message: "That spreadsheet could not be opened, the file may be damaged.")
    }
    let text = { (name: String) in files[name].map { String(decoding: $0, as: UTF8.self) } ?? "" }
    let sheetRe = JSRegex(#"^xl/worksheets/sheet\d+\.xml$"#)
    let number = { (n: String) in Int(JSRegex(#"\d+"#).exec(n)![0]!)! }
    let sheets = files.keys.filter { sheetRe.test($0) }.sorted { number($0) < number($1) }
    guard let first = sheets.first else { throw XlsxError(message: "That spreadsheet has no worksheets.") }
    let date1904 = JSRegex(#"date1904="(1|true)""#, "i").test(text("xl/workbook.xml"))
    return parseSheet(text(first), parseSharedStrings(text("xl/sharedStrings.xml")), parseStyles(text("xl/styles.xml")), date1904)
}
