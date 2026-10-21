// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BenchCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [
        .library(name: "BenchCore", targets: ["BenchCore"]),
        .library(name: "BenchStore", targets: ["BenchStore"]),
    ],
    targets: [
        .target(
            name: "BenchCore",
            resources: [.process("Resources")]
        ),
        // Persistence: SwiftData envelope records, synced through CloudKit by the app.
        .target(name: "BenchStore", dependencies: ["BenchCore"]),
        .testTarget(name: "BenchCoreTests", dependencies: ["BenchCore"]),
        .testTarget(name: "BenchStoreTests", dependencies: ["BenchStore", "BenchCore"]),
    ]
)
