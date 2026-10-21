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

private struct BackupExporter: ViewModifier {
    @Environment(AppStore.self) private var store
    @Binding var isPresented: Bool
    func body(content: Content) -> some View {
        content.fileExporter(isPresented: $isPresented, document: BackupDocument(data: (try? store.exportBackup()) ?? Data()),
                             contentType: .json, defaultFilename: String(exportFileName().dropLast(5))) { result in
            if case .success = result { store.markBackedUp() }
        }
    }
}

extension View {
    /// Present the save sheet for a backup, and stamp it on success.
    func backupExporter(isPresented: Binding<Bool>) -> some View { modifier(BackupExporter(isPresented: isPresented)) }
}
