import Foundation
import Testing
@testable import BenchCore

// Ports of i18n/translate, i18n/plural and format tests. Language-switching
// tests are serialized because `I18n.lang` is global.

@Suite struct TranslateTests {
    @Test func lookups() {
        #expect(translate(.en, "nav_now") == "Now" && translate(.sl, "nav_now") == "Zdaj" && translate(.pl, "nav_now") == "Teraz")
        #expect(translate(.en, "profile_switch", ["name": "Ana"]) == "Switch to Ana")
        #expect(translate(.en, "no_such_key_anywhere") == "no_such_key_anywhere")
    }

    @Test func plurals() {
        #expect(translate(.en, "plan_rotating_sites", ["n": 1]) == "rotating 1 site")
        #expect(translate(.en, "plan_rotating_sites", ["n": 3]) == "rotating 3 sites")
        let sl: (Int) -> String = { translate(.sl, "plan_own_plan_bands", ["n": .number(Double($0))]) }
        #expect(sl(1).contains("tedenski pas.") && sl(2).contains("tedenska pasova.") && sl(3).contains("tedenski pasovi.") && sl(5).contains("tedenskih pasov."))
        let pl: (Int) -> String = { translate(.pl, "library_subtitle", ["n": .number(Double($0))]) }
        #expect(pl(1).hasPrefix("1 substancja,") && pl(3).hasPrefix("3 substancje,") && pl(5).hasPrefix("5 substancji,"))
        #expect(pl(22).hasPrefix("22 substancje,") && pl(12).hasPrefix("12 substancji,"))
        #expect(translate(.sl, "plan_rotating_sites", ["n": 101]) == "kroženje po 101 mestu")
        #expect(translate(.en, "plan_rotating_sites", ["n": "1"]) == "rotating 1 site")
        #expect(translate(.en, "stock_grouped", ["n": 3]) == "3 identical vials")
        #expect(translate(.en, "plan_rotating_sites", ["n": "many"]) == "rotating many sites")
        #expect(translate(.en, "plan_rotating_sites") == "rotating {n} sites")
        #expect(translate(.sl, "plan_rotating_sites", ["n": .number(.nan)]) == "kroženje po NaN mestih")
    }

    @Test func pluralRules() {
        #expect(pluralCategory(.en, 0) == .other && pluralCategory(.en, 1) == .one && pluralCategory(.en, 2) == .other)
        #expect([1, 2, 3, 4, 5].map { pluralCategory(.sl, Double($0)) } == [.one, .two, .few, .few, .other])
        #expect([101, 102, 103].map { pluralCategory(.sl, Double($0)) } == [.one, .two, .few])
        #expect([1, 2, 4, 5, 0].map { pluralCategory(.pl, Double($0)) } == [.one, .few, .few, .many, .many])
        #expect([12, 13, 22, 23].map { pluralCategory(.pl, Double($0)) } == [.many, .many, .few, .few])
        #expect(pluralCategory(.en, .nan) == .other && pluralCategory(.sl, .infinity) == .other)
    }

    @Test func everyLanguageHasEveryKey() {
        let en = Set(I18n.dictionaries["en"]!.keys)
        #expect(en.count > 1000)
        for lang in Lang.allCases { #expect(I18n.dictionaries[lang.rawValue] != nil, "\(lang)") }
    }
}

@Suite struct FormatTests {
    @Test func doses() {
        #expect(formatDosePerDay(250, 1) == "250 mcg" && formatDosePerDay(250, 2) == "250 mcg × 2" && formatDosePerDay(1500, 3) == "1.5 mg × 3")
        #expect(formatDosePerDay(250, 0) == "250 mcg")
        #expect(formatDose(2500) == "2.5 mg" && formatDose(0.25) == "0.25 mcg" && formatDose(.nan) == "n/a")
        #expect(formatDose(1234.5678) == "1.235 mg" && formatDose(500, force: .mg) == "0.5 mg")
        #expect(formatConcentration(5000) == "5 mg/mL" && formatConcentration(50) == "50 mcg/mL")
        #expect(formatMl(0.1) == "0.1 mL" && formatUnits(13.333) == "13.33" && trim(0.1 + 0.2) == "0.3")
        #expect(formatDuration(0.5) == "30 min" && formatDuration(36) == "36 h" && formatDuration(108) == "4.5 d")
        #expect(percent(0.756) == "76%")
    }

    @Test func dates() {
        let aug = local(2026, 8, 27, 12)
        #expect(!formatDate(local(2026, 9, 13), nowMs: aug).contains("2026"))
        #expect(formatDate(local(2027, 3, 13), nowMs: aug).contains("2027"))
        #expect(formatDate(local(2025, 3, 13), nowMs: aug).contains("2025"))
        let dec = local(2026, 12, 31, 12)
        #expect(formatDate(local(2027, 1, 2), nowMs: dec).contains("2027") && !formatDate(local(2026, 1, 2), nowMs: dec).contains("2027"))
        for at in [local(2026, 9, 13, 9, 30), local(2027, 3, 13, 9, 30)] {
            #expect(formatDateTime(at, nowMs: aug).hasPrefix("\(formatDate(at, nowMs: aug)), "))
        }
    }

    @Test func languages() {
        let noon = local(2026, 9, 27, 12)
        let english = I18n.$override.withValue(.en) { formatDate(noon, nowMs: noon) }
        I18n.$override.withValue(.en) { #expect(relativeTime(noon + 26 * 60_000, nowMs: noon) == "in 26 minutes") }
        I18n.$override.withValue(.sl) {
        #expect(formatDate(noon, nowMs: noon) != english && formatDate(noon, nowMs: noon).contains("sep"))
        #expect(!relativeTime(noon + 26 * 60_000, nowMs: noon).contains("in 26 minutes"))
        #expect(relativeTime(noon, nowMs: noon) == "pravkar")
        #expect(formatHalfLife(nil) == "Ni ugotovljeno" && formatHalfLife(30).contains("ur"))
        #expect(formatHalfLife(2) == "2 uri" && formatHalfLife(3) == "3 ure")
        }
    }

    @Test func sites() {
        for lang in Lang.allCases {
            I18n.$override.withValue(lang) {
                for s in INJECTION_SITES { #expect(!siteLabel(s.id).isEmpty && siteLabel(s.id) != s.id.rawValue, "\(lang) \(s.id.rawValue)") }
            }
        }
        let english = I18n.$override.withValue(.en) { siteLabel(.thighL) }
        I18n.$override.withValue(.sl) {
            #expect(siteLabel(.thighL) != english)
            #expect(siteLabel("elbow-l") == "elbow-l")
            #expect(INJECTION_SITES.first { $0.id == .thighL }!.label == "Left thigh" && siteLabel(.thighL) != "Left thigh")
        }
    }
}
