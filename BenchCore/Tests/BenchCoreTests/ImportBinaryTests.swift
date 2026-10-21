import Foundation
import Testing
@testable import BenchCore

private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Double {
    var c = DateComponents()
    c.year = y; c.month = m; c.day = d; c.hour = h
    var cal = Calendar(identifier: .gregorian)
    cal.timeZone = TimeZone(identifier: "UTC")!
    return cal.date(from: c)!.millis
}

private func buildXlsx(sheet: String, sharedStrings: String? = nil, styles: String? = nil, workbook: String? = nil) -> [UInt8] {
    var files = [("[Content_Types].xml", "<Types/>"), ("xl/workbook.xml", workbook ?? "<workbook><sheets/></workbook>"), ("xl/worksheets/sheet1.xml", sheet)]
    if let sharedStrings { files.append(("xl/sharedStrings.xml", sharedStrings)) }
    if let styles { files.append(("xl/styles.xml", styles)) }
    return zipOf(files)
}
private func sheet(_ rows: String) -> String { "<worksheet><sheetData>\(rows)</sheetData></worksheet>" }

@Suite struct XlsxTests {
    @Test func serials() {
        #expect(serialToMs(46229) == utc(2026, 7, 26))
        #expect(serialToMs(1) == utc(1900, 1, 1))
        #expect(serialToMs(59) == utc(1900, 2, 28))
        #expect(serialToMs(61) == utc(1900, 3, 1))
        #expect(serialToMs(46229.5) == utc(2026, 7, 26, 12))
        #expect(serialToMs(46229 - 1462, date1904: true) == utc(2026, 7, 26))
    }

    @Test func columns() {
        #expect(columnToIndex("A1") == 0)
        #expect(columnToIndex("B2") == 1)
        #expect(columnToIndex("Z9") == 25)
        #expect(columnToIndex("AA1") == 26)
        #expect(columnToIndex("AZ1") == 51)
        #expect(columnToIndex("BA1") == 52)
        #expect(columnToIndex("12") == -1)
    }

    @Test func cells() throws {
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c></row><row r="2"><c r="A2"><v>1</v></c><c r="B2"><v>94.2</v></c></row>"#),
                                       sharedStrings: "<sst><si><t>Date</t></si><si><t>Weight</t></si></sst>")) == [["Date", "Weight"], ["1", "94.2"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1"><v>1</v></c><c r="C1"><v>3</v></c></row>"#))) == [["1", "", "3"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"#),
                                       sharedStrings: "<sst><si><r><t>Mounjaro</t></r><r><t>® 10 mg</t></r></si></sst>")) == [["Mounjaro® 10 mg"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" t="s"><v>0</v></c></row>"#),
                                       sharedStrings: "<sst><si><t>a &amp;lt; b &amp; c</t></si></sst>")) == [["a &lt; b & c"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" t="inlineStr"><is><t>hello</t></is></c></row>"#))) == [["hello"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" t="b"><v>1</v></c><c r="B1" t="b"><v>0</v></c></row>"#))) == [["TRUE", "FALSE"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1"/><c r="B1"><v>2</v></c></row>"#))) == [["", "2"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1"><v>1</v></c><c r="B1"><v>2</v></c><c r="C1"><v>3</v></c></row><row r="2"><c r="A2"><v>4</v></c></row>"#)))
                == [["1", "2", "3"], ["4", "", ""]])
    }

    @Test func dates() throws {
        let one = #"<styleSheet><cellXfs count="1"><xf numFmtId="14"/></cellXfs></styleSheet>"#
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" s="0"><v>46229</v></c></row>"#), styles: one)) == [["2026-07-26"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" s="0"><v>46229</v></c><c r="B1" s="1"><v>46229</v></c></row>"#),
                                       styles: #"<styleSheet><cellXfs count="2"><xf numFmtId="14"/><xf numFmtId="0"/></cellXfs></styleSheet>"#)) == [["2026-07-26", "46229"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" s="0"><v>46229</v></c></row>"#),
                                       styles: #"<styleSheet><numFmts><numFmt numFmtId="164" formatCode="dd/mm/yyyy"/></numFmts><cellXfs count="1"><xf numFmtId="164"/></cellXfs></styleSheet>"#)) == [["2026-07-26"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" s="0"><v>1500</v></c></row>"#),
                                       styles: #"<styleSheet><numFmts><numFmt numFmtId="165" formatCode="&quot;usd&quot;#,##0.00"/></numFmts><cellXfs count="1"><xf numFmtId="165"/></cellXfs></styleSheet>"#)) == [["1500"]])
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" s="0"><v>46229.5</v></c></row>"#),
                                       styles: #"<styleSheet><cellXfs count="1"><xf numFmtId="22"/></cellXfs></styleSheet>"#))[0][0] == "2026-07-26T12:00:00.000Z")
        #expect(try readXlsx(buildXlsx(sheet: sheet(#"<row r="1"><c r="A1" s="0"><v>\#(46229 - 1462)</v></c></row>"#), styles: one,
                                       workbook: #"<workbook><workbookPr date1904="1"/></workbook>"#)) == [["2026-07-26"]])
    }

    @Test func sheets() throws {
        #expect(try readXlsx(zipOf([("xl/workbook.xml", "<workbook/>"),
                                    ("xl/worksheets/sheet2.xml", sheet(#"<row r="1"><c r="A1" t="inlineStr"><is><t>second</t></is></c></row>"#)),
                                    ("xl/worksheets/sheet1.xml", sheet(#"<row r="1"><c r="A1" t="inlineStr"><is><t>first</t></is></c></row>"#))])) == [["first"]])
        #expect(try readXlsx(zipOf([("xl/workbook.xml", "<workbook/>"),
                                    ("xl/worksheets/sheet10.xml", sheet(#"<row><c t="inlineStr"><is><t>ten</t></is></c></row>"#)),
                                    ("xl/worksheets/sheet2.xml", sheet(#"<row><c t="inlineStr"><is><t>two</t></is></c></row>"#))])) == [["two"]])
    }

    @Test func refusals() {
        #expect(throws: XlsxError.self) { try readXlsx(Array("Date,Weight\n2026-01-01,94.2".utf8)) }
        do { _ = try readXlsx(Array("Date,Weight".utf8)) } catch let e as XlsxError { #expect(e.message.contains("not an .xlsx file")) } catch {}
        do { _ = try readXlsx(zipOf([("a.txt", "hi")])); Issue.record("should throw") } catch let e as XlsxError { #expect(e.message.contains("no worksheets")) } catch {}
    }
}

private func buildPdf(_ content: String, compress: Bool = true) -> [UInt8] {
    let raw = Array(content.utf8)
    let body = compress ? zlibStream(raw) : raw
    let filter = compress ? " /Filter /FlateDecode" : ""
    let header = Array("%PDF-1.4\n1 0 obj\n<< /Type /Page >>\nendobj\n2 0 obj\n<< /Length \(body.count)\(filter) >>\nstream\n".utf8)
    return header + body + Array("\nendstream\nendobj\ntrailer\n<< /Root 1 0 R >>\n%%EOF\n".utf8)
}
private func show(_ lines: [String]) -> String { "BT /F1 12 Tf \(lines.map { "1 0 0 1 72 700 Tm (\($0)) Tj" }.joined(separator: " ")) ET" }
private func linesOf(_ content: String, compress: Bool = true) throws -> [String] { try readPdfText(buildPdf(content, compress: compress)).lines }

@Suite struct PdfTextTests {
    @Test func magic() {
        #expect(looksLikePdf(buildPdf(show(["x"]))))
        #expect(!looksLikePdf(Array("Marker,Value\nHbA1c,5.4".utf8)))
        #expect(!looksLikePdf([]))
    }

    @Test func streams() throws {
        let r = try readPdfText(buildPdf(show(["HbA1c 5.4 %", "Total testosterone 612 ng/dL"])))
        #expect(r.streams == 1)
        #expect(r.lines.contains("HbA1c 5.4 %") && r.lines.contains("Total testosterone 612 ng/dL"))
        #expect(try linesOf(show(["Ferritin 84 ng/mL"]), compress: false).contains("Ferritin 84 ng/mL"))
    }

    @Test func operators() throws {
        #expect(try linesOf("BT (first) Tj 0 -14 Td (second) Tj 0 -14 Td (third) Tj ET") == ["first", "second", "third"])
        #expect(try linesOf("BT 1 0 0 1 72 700 Tm (Oes) Tj (tradiol) Tj ( 28 pg/mL) Tj ET").contains("Oestradiol 28 pg/mL"))
        #expect(try linesOf("BT 1 0 0 1 72 700 Tm [(Hae) -20 (matocrit) -20 ( 48 %)] TJ ET").contains("Haematocrit 48 %"))
        #expect(try linesOf("BT 1 0 0 1 72 700 Tm <4C697061736520333120552F4C> Tj ET").contains("Lipase 31 U/L"))
        #expect(try linesOf(#"BT 1 0 0 1 72 700 Tm (Insulin 6.1 \265IU/mL) Tj ET"#).contains("Insulin 6.1 \u{00b5}IU/mL"))
        #expect(try linesOf(#"BT 1 0 0 1 72 700 Tm (\376\377\000A\000L\000T\000 \0002\0002) Tj ET"#).contains("ALT 22"))
        #expect(try linesOf("BT 1 0 0 1 72 700 Tm (Free T (calculated) 18.2) Tj ET").contains("Free T (calculated) 18.2"))
        #expect(try linesOf(#"BT 1 0 0 1 72 700 Tm (Result \) high) Tj ET"#).contains("Result ) high"))
        #expect(try linesOf("BT 1 0 0 1 72 700 Tm (TSH    1.8     mIU/L) Tj ET").contains("TSH 1.8 mIU/L"))
        #expect(try linesOf("BT ( ) Tj 0 -14 Td (Real 1) Tj 0 -14 Td () Tj ET") == ["Real 1"])
    }

    @Test func nonText() throws {
        #expect(try readPdfText(buildPdf(show(["only one"]))).streams == 1)
        let r = try readPdfText(buildPdf("q 100 0 0 100 0 0 cm /Im1 Do Q"))
        #expect(r.streams == 0 && r.lines.isEmpty)
        #expect(try linesOf("q /Im0 Do Q").isEmpty)
    }

    @Test func refusals() {
        #expect(throws: PdfError.self) { try readPdfText(Array("Marker,Value\n".utf8)) }
        let tagged = buildPdf(show(["x"])) + Array(" /Encrypt 9 0 R ".utf8)
        do { _ = try readPdfText(tagged); Issue.record("should throw") } catch let e as PdfError { #expect(e.message.lowercased().contains("encrypted")) } catch {}
    }

    @Test func survivesBrokenStream() throws {
        let merged = buildPdf(show(["Glucose 92 mg/dL"])) + Array("1 0 obj\n<< /Length 4 /Filter /FlateDecode >>\nstream\n".utf8) + [0, 1, 2, 3] + Array("\nendstream\nendobj\n".utf8)
        #expect(try readPdfText(merged).lines.contains("Glucose 92 mg/dL"))
    }
}
