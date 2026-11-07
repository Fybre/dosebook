// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "DosebookCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "DosebookCore", targets: ["DosebookCore"]),
        .library(name: "DosebookStore", targets: ["DosebookStore"]),
    ],
    targets: [
        .target(
            name: "DosebookCore",
            resources: [.process("Resources")]
        ),
        // Persistence: SwiftData envelope records, synced through CloudKit by the app.
        .target(name: "DosebookStore", dependencies: ["DosebookCore"]),
        .testTarget(name: "DosebookCoreTests", dependencies: ["DosebookCore"], exclude: ["Fixtures"]),
        .testTarget(name: "DosebookStoreTests", dependencies: ["DosebookStore", "DosebookCore"]),
    ]
)
