// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BenchCore",
    platforms: [.iOS(.v18), .macOS(.v15)],
    products: [.library(name: "BenchCore", targets: ["BenchCore"])],
    targets: [
        .target(
            name: "BenchCore",
            resources: [.process("Resources")]
        ),
        .testTarget(name: "BenchCoreTests", dependencies: ["BenchCore"]),
    ]
)
