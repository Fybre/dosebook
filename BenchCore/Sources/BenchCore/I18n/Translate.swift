import Foundation
import Synchronization

// Port of src/lib/i18n (translate + plural). The dictionary is the original's
// translations.ts, exported to JSON by tools/export-library.mjs, so the copy on
// every screen is the original's copy, in all four languages.

public enum Lang: String, CaseIterable, Sendable, Codable {
    case en, de, sl, pl

    public var label: String {
        switch self {
        case .en: "English"
        case .de: "Deutsch"
        case .sl: "Slovenščina"
        case .pl: "Polski"
        }
    }

    public var locale: Locale { Locale(identifier: rawValue) }
}

public enum PluralCategory: String, Sendable { case zero, one, two, few, many, other }

/// CLDR cardinal rules for the four shipped languages. Swift has no runtime
/// equivalent of `Intl.PluralRules`, so the rules are written out; they are
/// short and tested.
public func pluralCategory(_ lang: Lang, _ n: Double) -> PluralCategory {
    guard n.isFinite else { return .other }
    let a = abs(n)
    let isInt = a == a.rounded()
    let i = isInt ? Int(a) : Int(a.rounded(.down))
    switch lang {
    case .en, .de:
        return isInt && i == 1 ? .one : .other
    case .sl:
        if !isInt { return .few }
        switch i % 100 {
        case 1: return .one
        case 2: return .two
        case 3, 4: return .few
        default: return .other
        }
    case .pl:
        if !isInt { return .other }
        if i == 1 { return .one }
        let d = i % 10, h = i % 100
        if (2...4).contains(d) && !(12...14).contains(h) { return .few }
        return .many
    }
}

public enum I18n {
    private static let current = Mutex<Lang>(.en)

    /// Binds a language for one task, so tests can switch without racing each other.
    @TaskLocal public static var override: Lang?

    /// The language the app is set to. The app sets this from its stored preference.
    public static var lang: Lang {
        get { override ?? current.withLock { $0 } }
        set { current.withLock { $0 = newValue } }
    }

    static let dictionaries: [String: [String: String]] = {
        guard let url = Bundle.module.url(forResource: "translations", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode([String: [String: String]].self, from: data) else { return [:] }
        return decoded
    }()

    public static func hasKey(_ key: String) -> Bool { dictionaries["en"]?[key] != nil || dictionaries["en"]?["\(key)_other"] != nil }
}

public enum TVar: Sendable, ExpressibleByStringLiteral, ExpressibleByIntegerLiteral, ExpressibleByFloatLiteral {
    case string(String)
    case number(Double)
    public init(stringLiteral value: String) { self = .string(value) }
    public init(integerLiteral value: Int) { self = .number(Double(value)) }
    public init(floatLiteral value: Double) { self = .number(value) }

    var text: String {
        switch self {
        case .string(let s): s
        case .number(let n): jsNumberString(n)
        }
    }

    var number: Double? {
        switch self {
        case .number(let n): n
        case .string(let s): s.isEmpty ? nil : jsNumber(s)
        }
    }
}

/// Look up a string and substitute `{name}` slots. A key with an `_other` form
/// is a plural family, resolved on `vars["n"]` in the given language.
public func translate(_ lang: Lang, _ key: String, _ vars: [String: TVar] = [:]) -> String {
    let strings = I18n.dictionaries[lang.rawValue] ?? [:]
    let english = I18n.dictionaries["en"] ?? [:]
    var name = key
    let other = "\(key)_other"
    if strings[other] ?? english[other] != nil {
        let form: String
        if let n = vars["n"]?.number, n.isFinite { form = "\(key)_\(pluralCategory(lang, n).rawValue)" } else { form = other }
        name = (strings[form] ?? english[form]) != nil ? form : other
    }
    var s = strings[name] ?? english[name] ?? key
    for (k, v) in vars {
        if let r = s.range(of: "{\(k)}") { s.replaceSubrange(r, with: v.text) }
    }
    return s
}

/// `t("key")` in the current language.
public func t(_ key: String, _ vars: [String: TVar] = [:]) -> String { translate(I18n.lang, key, vars) }
