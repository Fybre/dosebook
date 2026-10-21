import Foundation

// Port of src/lib/calc/numberField.ts.
//
// What a number field shows: the text as typed for as long as it still means the
// number the caller holds (so a field showing 0 can be emptied, and typing 250
// does not give 0250), otherwise the caller's value.

/// `draft` is the text being typed, nil when the field is not being edited.
public func shownValue(_ draft: String?, _ value: Double?) -> String {
    guard let draft else { return value.map(jsNumberString) ?? "" }
    guard let value else { return "" }
    let typed = jsNumber(draft) ?? .nan
    return typed == value ? draft : jsNumberString(value)
}
