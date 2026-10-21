import Foundation

// Port of src/lib/import/pdf.ts. The text layer of a PDF with no PDF library:
// find the content streams, inflate them, read the text-showing operators. No
// OCR and no custom font encodings, by design; everything found is reviewed.
// Works on arrays of UTF-16 units holding latin-1 bytes, as the original did on
// strings, so every offset means what it meant there.

public struct PdfError: Error, Equatable { public var message: String }

public struct PdfText: Equatable, Sendable {
    /// Every line, in the order the operators emitted them.
    public var lines: [String]
    /// How many content streams contributed.
    public var streams: Int
}

public func looksLikePdf(_ bytes: [UInt8]) -> Bool {
    bytes.count > 4 && bytes[0] == 0x25 && bytes[1] == 0x50 && bytes[2] == 0x44 && bytes[3] == 0x46
}

private typealias Chars = [UInt16]

private func chars(_ s: String) -> Chars { Array(s.utf16) }
private func string(_ c: some Collection<UInt16>) -> String { String(decoding: c, as: UTF16.self) }
private func latin1(_ bytes: some Collection<UInt8>) -> Chars { bytes.map(UInt16.init) }

private func indexOf(_ hay: Chars, _ needle: Chars, from: Int) -> Int {
    guard !needle.isEmpty, hay.count >= needle.count else { return -1 }
    var i = max(0, from)
    while i <= hay.count - needle.count {
        if hay[i] == needle[0] && hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
        i += 1
    }
    return -1
}

/// JS `lastIndexOf(needle, from)`: the last occurrence starting at or before `from`.
private func lastIndexOf(_ hay: Chars, _ needle: Chars, before from: Int) -> Int {
    var i = min(from, hay.count - needle.count)
    while i >= 0 {
        if hay[i..<(i + needle.count)].elementsEqual(needle) { return i }
        i -= 1
    }
    return -1
}

private struct RawStream { var dict: String; var body: [UInt8] }

private let STREAM = chars("stream"), ENDSTREAM = chars("endstream"), OBJ = chars("obj"), END = chars("end")

/// Every `stream ... endstream` payload with the dictionary before it, found by scanning.
private func findStreams(_ bytes: [UInt8], _ text: Chars) -> [RawStream] {
    var out: [RawStream] = [], at = 0
    while at < text.count {
        let start = indexOf(text, STREAM, from: at)
        if start == -1 { break }
        if start >= 3 && text[(start - 3)..<start].elementsEqual(END) { at = start + 6; continue }
        let objStart = lastIndexOf(text, OBJ, before: start)
        let dict = objStart == -1 ? "" : string(text[objStart..<start])
        var bodyStart = start + STREAM.count
        if bodyStart < text.count && text[bodyStart] == 13 { bodyStart += 1 }
        if bodyStart < text.count && text[bodyStart] == 10 { bodyStart += 1 }
        let end = indexOf(text, ENDSTREAM, from: bodyStart)
        if end == -1 { break }
        var e = end
        if e > bodyStart && text[e - 1] == 10 { e -= 1 }
        if e > bodyStart && text[e - 1] == 13 { e -= 1 }
        out.append(RawStream(dict: dict, body: Array(bytes[bodyStart..<e])))
        at = end + ENDSTREAM.count
    }
    return out
}

/// FlateDecode or no filter; anything else is skipped rather than guessed at.
private func decodeStream(_ s: RawStream) -> Chars? {
    if JSRegex(#"/Filter\s*/(?!FlateDecode)"#).test(s.dict) { return nil }
    if !s.dict.contains("FlateDecode") { return s.body.isEmpty ? nil : latin1(s.body) }
    return Inflate.zlib(s.body).map(latin1)
}

private func isContent(_ decoded: Chars) -> Bool {
    let s = string(decoded)
    return JSRegex(#"\bBT\b"#).test(s) && JSRegex(#"\b(Tj|TJ)\b"#).test(s)
}

private func isOctal(_ c: UInt16) -> Bool { c >= 48 && c <= 55 }

/// Backslash escapes and three-digit octal.
private func unescapeLiteral(_ raw: Chars) -> Chars {
    var out: Chars = [], i = 0
    let simple: [UInt16: UInt16] = [110: 10, 114: 13, 116: 9, 98: 8, 102: 12, 40: 40, 41: 41, 92: 92]
    while i < raw.count {
        let c = raw[i]
        if c != 92 { out.append(c); i += 1; continue }
        i += 1
        guard i < raw.count else { break }
        let next = raw[i]
        if let s = simple[next] { out.append(s); i += 1; continue }
        if isOctal(next) {
            var oct = [next]
            while oct.count < 3 && i + 1 < raw.count && isOctal(raw[i + 1]) { i += 1; oct.append(raw[i]) }
            out.append(UInt16(string(oct), radix: 8)!)
            i += 1
            continue
        }
        if next == 10 { i += 1; continue }
        if next == 13 { if i + 1 < raw.count && raw[i + 1] == 10 { i += 1 }; i += 1; continue }
        out.append(next)
        i += 1
    }
    return out
}

/// `<48656C6C6F>`; an odd length pads with a trailing zero.
private func decodeHexString(_ raw: Chars) -> Chars {
    var hex = string(raw).filter { $0.isHexDigit && $0.isASCII }
    if hex.count % 2 == 1 { hex += "0" }
    var out: Chars = []
    var idx = hex.startIndex
    while idx < hex.endIndex {
        let next = hex.index(idx, offsetBy: 2)
        out.append(UInt16(hex[idx..<next], radix: 16)!)
        idx = next
    }
    return out
}

/// UTF-16BE behind a byte order mark, as generators write anything non-ASCII.
private func decodeMaybeUtf16(_ s: Chars) -> Chars {
    guard s.count >= 2, s[0] == 0xFE, s[1] == 0xFF else { return s }
    var out: Chars = [], i = 2
    while i + 1 < s.count { out.append(s[i] << 8 | s[i + 1]); i += 2 }
    return out
}

private func isLetter(_ c: UInt16) -> Bool { (c >= 65 && c <= 90) || (c >= 97 && c <= 122) }

/// The text of one content stream; cursor moves become line breaks.
private func textFromContent(_ content: Chars) -> [String] {
    var out: [String] = [], line: Chars = [], i = 0
    let ws = JSRegex(#"\s+"#)
    func endLine() {
        let trimmed = ws.replaceAll(string(line), " ").trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty { out.append(trimmed) }
        line = []
    }
    while i < content.count {
        let c = content[i]
        if c == 40 { // (
            var depth = 1, raw: Chars = []
            i += 1
            while i < content.count && depth > 0 {
                let ch = content[i]
                if ch == 92 {
                    raw.append(ch)
                    if i + 1 < content.count { raw.append(content[i + 1]) }
                    i += 2
                    continue
                }
                if ch == 40 { depth += 1 } else if ch == 41 { depth -= 1; if depth == 0 { break } }
                raw.append(ch)
                i += 1
            }
            i += 1
            line += decodeMaybeUtf16(unescapeLiteral(raw))
            continue
        }
        if c == 60 && (i + 1 >= content.count || content[i + 1] != 60) { // < but not <<
            let close = indexOf(content, [62], from: i)
            if close == -1 { break }
            line += decodeMaybeUtf16(decodeHexString(Array(content[(i + 1)..<close])))
            i = close + 1
            continue
        }
        if c == 60 { // << dictionary
            let close = indexOf(content, [62, 62], from: i)
            i = close == -1 ? content.count : close + 2
            continue
        }
        if c == 37 { // % comment
            let nl = indexOf(content, [10], from: i)
            i = nl == -1 ? content.count : nl + 1
            continue
        }
        if isLetter(c) || c == 42 || c == 39 || c == 34 {
            var op: Chars = []
            while i < content.count {
                let ch = content[i]
                guard isLetter(ch) || (ch >= 48 && ch <= 57) || ch == 42 || ch == 39 || ch == 34 else { break }
                op.append(ch)
                i += 1
            }
            let name = string(op)
            if ["Td", "TD", "T*", "Tm", "ET", "'", "\""].contains(name) { endLine() }
            continue
        }
        i += 1
    }
    endLine()
    return out
}

/// The text layer. Throws only for a file that is not a PDF, or is encrypted.
public func readPdfText(_ bytes: [UInt8]) throws -> PdfText {
    guard looksLikePdf(bytes) else { throw PdfError(message: "That does not look like a PDF.") }
    let text = latin1(bytes)
    if JSRegex(#"/Encrypt\b"#).test(string(text)) {
        throw PdfError(message: "This PDF is encrypted. Open it in a reader and save or print an unprotected copy first.")
    }
    var lines: [String] = [], streams = 0
    for raw in findStreams(bytes, text) {
        guard let decoded = decodeStream(raw), isContent(decoded) else { continue }
        streams += 1
        lines += textFromContent(decoded)
    }
    return PdfText(lines: lines.filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }, streams: streams)
}
