import Foundation

/// Whether a logged dose matches what was typed in the Log's search box. Every word
/// has to be found somewhere in the compound's name, the site, the route, the notes,
/// the side effects or the dose itself, in any order and ignoring case and accents.
public func logMatches(_ l: DoseLog, query: String, peptideName: String) -> Bool {
    let words = query.split(whereSeparator: \.isWhitespace).map(String.init)
    guard !words.isEmpty else { return true }
    var haystack = [peptideName, l.route.label, l.notes ?? "", (l.sideEffects ?? []).joined(separator: " "), formatDose(l.doseMcg)]
    if let site = l.site { haystack.append(site.label) }
    if l.isSkipped { haystack.append("skipped") }
    let text = haystack.joined(separator: " ")
    return words.allSatisfy { text.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
}
