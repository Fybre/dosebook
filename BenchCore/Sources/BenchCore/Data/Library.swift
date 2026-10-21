import Foundation

/// The built-in reference library, exported from the original's TypeScript by
/// `tools/export-library.mjs`. Sorted by name, as `PEPTIDES` is.
public enum Library {
    public static let peptides: [Peptide] = load("peptides", [Peptide].self) ?? []
    public static let byId: [String: Peptide] = Dictionary(peptides.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })

    public static let labMarkers: [LabMarker] = labs?.markers ?? []
    public static let labCategoryLabels: [String: String] = labs?.categoryLabels ?? [:]

    public static func marker(_ id: String) -> LabMarker? { labMarkers.first { $0.id == id } }

    struct LabsFile: Decodable {
        var markers: [LabMarker]
        var categoryLabels: [String: String]
    }

    static let labs: LabsFile? = load("labs", LabsFile.self)

    static func load<T: Decodable>(_ name: String, _: T.Type) -> T? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "json"),
              let data = try? Data(contentsOf: url) else { return nil }
        do { return try JSONDecoder().decode(T.self, from: data) } catch {
            assertionFailure("\(name).json: \(error)")
            return nil
        }
    }
}

/// A compound by id, from custom compounds first, then the library.
public func findPeptide(_ id: String, custom: [Peptide] = []) -> Peptide? {
    custom.first { $0.id == id } ?? Library.byId[id]
}
