import Foundation

// Port of src/lib/import/delimited.ts. RFC 4180 plus a trailing newline and a
// UTF-8 byte order mark. Works on UTF-16 units, as the original did on JS strings.

public enum Delimiter: String, CaseIterable, Sendable {
    case comma = ",", tab = "\t", semicolon = ";", pipe = "|"
}

private let QUOTE: UInt16 = 34, CR: UInt16 = 13, LF: UInt16 = 10

public func stripBom(_ text: String) -> String {
    text.hasPrefix("\u{FEFF}") ? String(text.dropFirst()) : text
}

/// Guess the delimiter from the header line, counting only separators outside quotes.
public func sniffDelimiter(_ text: String) -> Delimiter {
    let line = firstLogicalLine(Array(stripBom(text).utf16))
    var best = Delimiter.comma, bestCount = 0
    for d in Delimiter.allCases {
        let count = countOutsideQuotes(line, d.rawValue.utf16.first!)
        if count > bestCount { best = d; bestCount = count }
    }
    return best
}

private func firstLogicalLine(_ text: [UInt16]) -> ArraySlice<UInt16> {
    var quoted = false, i = 0
    while i < text.count {
        let ch = text[i]
        if ch == QUOTE {
            if quoted && i + 1 < text.count && text[i + 1] == QUOTE { i += 1 } else { quoted.toggle() }
        } else if !quoted && (ch == LF || ch == CR) {
            return text[0..<i]
        }
        i += 1
    }
    return text[...]
}

private func countOutsideQuotes(_ line: ArraySlice<UInt16>, _ d: UInt16) -> Int {
    var quoted = false, count = 0
    var i = line.startIndex
    while i < line.endIndex {
        let ch = line[i]
        if ch == QUOTE {
            if quoted && i + 1 < line.endIndex && line[i + 1] == QUOTE { i += 1 } else { quoted.toggle() }
        } else if !quoted && ch == d {
            count += 1
        }
        i += 1
    }
    return count
}

/// Rows of raw cell strings: quotes unwrapped, doubled quotes unescaped, nothing else.
public func parseDelimited(_ text: String, _ delimiter: Delimiter? = nil) -> [[String]] {
    let src = Array(stripBom(text).utf16)
    let d = (delimiter ?? sniffDelimiter(stripBom(text))).rawValue.utf16.first!
    var rows: [[String]] = [], row: [String] = [], cell: [UInt16] = []
    var quoted = false, cellWasQuoted = false

    func endCell() { row.append(String(decoding: cell, as: UTF16.self)); cell = []; cellWasQuoted = false }
    func endRow() { endCell(); rows.append(row); row = [] }

    var i = 0
    while i < src.count {
        let ch = src[i]
        if quoted {
            if ch == QUOTE {
                if i + 1 < src.count && src[i + 1] == QUOTE { cell.append(QUOTE); i += 1 } else { quoted = false }
            } else {
                cell.append(ch)
            }
            i += 1
            continue
        }
        if ch == QUOTE && cell.isEmpty {
            // Only a quote at the start of a cell opens a quoted field.
            quoted = true; cellWasQuoted = true
        } else if ch == d {
            endCell()
        } else if ch == CR {
            if i + 1 < src.count && src[i + 1] == LF { i += 1 }
            endRow()
        } else if ch == LF {
            endRow()
        } else {
            cell.append(ch)
        }
        i += 1
    }
    if !cell.isEmpty || cellWasQuoted || !row.isEmpty { endRow() }
    return rows
}

public struct ImportTable: Equatable, Sendable {
    public var headers: [String]
    /// One map per row, keyed by header; duplicate headers get a numeric suffix.
    public var records: [[String: String]]
    /// Rows whose cell count differed from the header's.
    public var raggedRows: Int
}

/// Lower case, alphanumeric only, parenthesised content dropped.
public func normaliseHeader(_ h: String) -> String {
    var s = h.lowercased()
    s = JSRegex(#"\([^)]*\)"#).replaceAll(s, " ")
    s = JSRegex("[^a-z0-9]+").replaceAll(s, " ")
    return s.trimmingCharacters(in: .whitespaces)
}

/// Keyed records from the first non-empty row as headers. Extra cells are kept positionally.
public func toTable(_ rows: [[String]]) -> ImportTable {
    let blank = { (c: String) in c.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    guard let headerIndex = rows.firstIndex(where: { $0.contains { !blank($0) } }) else {
        return ImportTable(headers: [], records: [], raggedRows: 0)
    }
    var seen: [String: Int] = [:]
    let headers = rows[headerIndex].enumerated().map { i, h -> String in
        let trimmed = h.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = trimmed.isEmpty ? "column \(i + 1)" : trimmed
        let n = seen[name] ?? 0
        seen[name] = n + 1
        return n == 0 ? name : "\(name) \(n + 1)"
    }
    var records: [[String: String]] = [], ragged = 0
    for row in rows.dropFirst(headerIndex + 1) {
        if !row.contains(where: { !blank($0) }) { continue }
        if row.count != headers.count { ragged += 1 }
        var rec: [String: String] = [:]
        for (i, h) in headers.enumerated() { rec[h] = i < row.count ? row[i] : "" }
        if row.count > headers.count { for i in headers.count..<row.count { rec["column \(i + 1)"] = row[i] } }
        records.append(rec)
    }
    return ImportTable(headers: headers, records: records, raggedRows: ragged)
}
