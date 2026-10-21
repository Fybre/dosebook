import Foundation
import Testing
@testable import BenchCore

@Suite struct ImportValuesTests {
    @Test func isBlankSeparatesAbsentFromZero() {
        #expect(isBlank(""))
        #expect(isBlank("   "))
        #expect(isBlank(nil))
        #expect(!isBlank("0"))
    }

    @Test func parseNumberReads() {
        #expect(parseNumber("42") == 42)
        #expect(parseNumber("94.2") == 94.2)
        #expect(parseNumber("-1.5") == -1.5)
        #expect(parseNumber("0") == 0)
        #expect(parseNumber("94.2 kg") == 94.2)
        #expect(parseNumber("1,234") == 1234)
        #expect(parseNumber("10 mg") == 10)
        #expect(parseNumber("n/a") == nil)
        #expect(parseNumber("") == nil)
        #expect(parseNumber("--") == nil)
        #expect(parseNumber("Wegovy 1.0 mg") == 1)
        #expect(parseNumber("Mounjaro® 10.0 mg") == 10)
    }

    @Test func parseDateForms() {
        #expect(parseDate("2026-07-26") == local(2026, 7, 26))
        #expect(parseDate("2026/07/26") == local(2026, 7, 26))
        #expect(parseDate("2026.07.26") == local(2026, 7, 26))
        #expect(parseDate("2026-07-26", "13:36") == local(2026, 7, 26, 13, 36))
        #expect(parseDate("2026-07-26T09:32:10", "23:00") == local(2026, 7, 26, 9, 32, 10))
    }

    @Test func parseDateRefuses() {
        for bad in ["10/07/2026", "07/10/2026", "26-07-2026", "2026-02-31", "2026-13-01", "2026-00-10", "", "last Tuesday"] {
            #expect(parseDate(bad) == nil, "\(bad)")
        }
    }

    @Test func parseDateIsLocalMidnight() {
        let at = parseDate("2026-07-26")!
        #expect(hours(at) == 0)
        #expect(dayOfMonth(at) == 26)
    }

    @Test func parseClockForms() {
        #expect(parseClock("13:36") == Clock(h: 13, mi: 36, s: 0))
        #expect(parseClock("09:32:10") == Clock(h: 9, mi: 32, s: 10))
        #expect(parseClock("23:23") == Clock(h: 23, mi: 23, s: 0))
        #expect(parseClock("1:36 pm") == Clock(h: 13, mi: 36, s: 0))
        #expect(parseClock("12:05 am") == Clock(h: 0, mi: 5, s: 0))
        #expect(parseClock("12:05 PM") == Clock(h: 12, mi: 5, s: 0))
        for bad in ["25:00", "10:75", "morning", ""] { #expect(parseClock(bad) == nil) }
    }

    @Test func parseDoseUnits() {
        #expect(parseDoseMcg("10") == 10_000)
        #expect(parseDoseMcg("2.5") == 2500)
        #expect(parseDoseMcg("10 mg") == 10_000)
        #expect(parseDoseMcg("500 mcg") == 500)
        #expect(parseDoseMcg("500 µg") == 500)
        #expect(parseDoseMcg("250ug") == 250)
        #expect(parseDoseMcg("0.001 g") == 1000)
        #expect(parseDoseMcg("500µg") == 500)
        #expect(parseDoseMcg("500 μg") == 500)
        #expect(parseDoseMcg("0") == 0)
        for bad in ["20 units", "20 iu", "20u", "0.5 mL", "2 clicks", "-5 mg", "a lot", ""] {
            #expect(parseDoseMcg(bad) == nil, "\(bad)")
        }
    }

    @Test func parseBooleanSpellings() {
        for t in ["1", "true", "TRUE", "yes", "Y", "on"] { #expect(parseBoolean(t) == true) }
        for f in ["0", "false", "no", "N", "off"] { #expect(parseBoolean(f) == false) }
        #expect(parseBoolean("") == nil)
        #expect(parseBoolean("maybe") == nil)
    }
}

@Suite struct DelimitedTests {
    @Test func sniffs() {
        #expect(sniffDelimiter("a,b,c\n1,2,3") == .comma)
        #expect(sniffDelimiter("a\tb\tc\n1\t2\t3") == .tab)
        #expect(sniffDelimiter("a;b;c\n1;2;3") == .semicolon)
        #expect(sniffDelimiter("a|b|c\n1|2|3") == .pipe)
        #expect(sniffDelimiter("name,note\n\"Smith; John\",\"a; b; c; d\"") == .comma)
        #expect(sniffDelimiter("weight\n94.2") == .comma)
        #expect(sniffDelimiter("\"a\nb\",c,d\n1,2,3") == .comma)
        #expect(sniffDelimiter("\u{FEFF}a,b,c") == .comma)
    }

    @Test func stripsBom() {
        #expect(stripBom("\u{FEFF}Date,Jab") == "Date,Jab")
        #expect(stripBom("Date,Jab") == "Date,Jab")
        #expect(stripBom("Date\u{FEFF}Jab") == "Date\u{FEFF}Jab")
    }

    @Test func parses() {
        #expect(parseDelimited("a,b\n1,2") == [["a", "b"], ["1", "2"]])
        #expect(parseDelimited("note,dose\n\"felt sick, badly\",10") == [["note", "dose"], ["felt sick, badly", "10"]])
        let rows = parseDelimited("note,dose\n\"line one\nline two\",10")
        #expect(rows.count == 2)
        #expect(rows[1][0] == "line one\nline two")
        #expect(parseDelimited("note\n\"he said \"\"ouch\"\"\"") == [["note"], ["he said \"ouch\""]])
        #expect(parseDelimited("a,b\r\n1,2\r\n") == [["a", "b"], ["1", "2"]])
        #expect(parseDelimited("a,b\r1,2") == [["a", "b"], ["1", "2"]])
        #expect(parseDelimited("a,b\n1,2\n").count == 2)
        #expect(parseDelimited("a,b,c\n1,,") == [["a", "b", "c"], ["1", "", ""]])
        #expect(parseDelimited("a\n\"\"") == [["a"], [""]])
        #expect(parseDelimited("a\n5\" long") == [["a"], ["5\" long"]])
        #expect(parseDelimited("a,b\n 1 , 2 ") == [["a", "b"], [" 1 ", " 2 "]])
        #expect(parseDelimited("nausea,pain\n,0") == [["nausea", "pain"], ["", "0"]])
        #expect(parseDelimited("a;b\n1;2", .semicolon) == [["a", "b"], ["1", "2"]])
        #expect(parseDelimited("") == [])
        #expect(parseDelimited("\n") == [[""]])
    }

    @Test func tables() {
        var t = toTable(parseDelimited("Date,Weight\n2026-01-01,94.2"))
        #expect(t.headers == ["Date", "Weight"])
        #expect(t.records == [["Date": "2026-01-01", "Weight": "94.2"]])
        t = toTable([[], ["", ""], ["Date", "Weight"], ["2026-01-01", "94.2"]])
        #expect(t.headers == ["Date", "Weight"])
        #expect(t.records.count == 1)
        #expect(toTable(parseDelimited("a,b\n1,2\n,\n3,4")).records.count == 2)
        t = toTable(parseDelimited("dose,dose\n1,2"))
        #expect(t.headers == ["dose", "dose 2"])
        #expect(t.records[0] == ["dose": "1", "dose 2": "2"])
        #expect(toTable(parseDelimited("a,,c\n1,2,3")).headers == ["a", "column 2", "c"])
        t = toTable([["a", "b", "c"], ["1"]])
        #expect(t.records[0] == ["a": "1", "b": "", "c": ""])
        #expect(t.raggedRows == 1)
        t = toTable([["a", "b"], ["1", "2", "3"]])
        #expect(t.records[0]["column 3"] == "3")
        #expect(t.raggedRows == 1)
        #expect(toTable([]) == ImportTable(headers: [], records: [], raggedRows: 0))
    }

    @Test func normalisesHeaders() {
        #expect(normaliseHeader("Recorded Weight (kg)") == "recorded weight")
        #expect(normaliseHeader("Pain Level") == "pain level")
        #expect(normaliseHeader("dose_mcg") == "dose mcg")
        #expect(normaliseHeader("  Date  ") == "date")
        #expect(normaliseHeader("Jab Notes") == "jab notes")
        #expect(normaliseHeader("---") == "")
        #expect(normaliseHeader("") == "")
    }
}
