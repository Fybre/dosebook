import SwiftUI
import UniformTypeIdentifiers
import BenchCore
import BenchStore

/// A Bench backup as a file, in the original's export format.
struct BackupDocument: FileDocument {
    static var readableContentTypes: [UTType] { [.json] }
    var data: Data
    init(data: Data) { self.data = data }
    init(configuration: ReadConfiguration) throws { data = configuration.file.regularFileContents ?? Data() }
    func fileWrapper(configuration: WriteConfiguration) throws -> FileWrapper { FileWrapper(regularFileWithContents: data) }
}

func backupFileName(_ at: Millis = nowMillis()) -> String {
    let c = LocalTime.calendar.dateComponents([.year, .month, .day], from: Date(millis: at))
    return String(format: "bench-backup-%04d-%02d-%02d", c.year!, c.month!, c.day!)
}

private struct BackupExporter: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        content.fileExporter(isPresented: $isPresented, document: BackupDocument(data: (try? store.exportBackup()) ?? Data()),
                             contentType: .json, defaultFilename: backupFileName()) { result in
            if case .success = result { store.markBackedUp() }
        }
    }
}

extension View {
    /// Present the save sheet for a backup, and stamp it on success.
    func backupExporter(isPresented: Binding<Bool>) -> some View { modifier(BackupExporter(isPresented: isPresented)) }
}
