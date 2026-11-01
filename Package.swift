// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TokenCurrent",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "TokenCurrentCore", targets: ["TokenCurrentCore"]),
        .executable(name: "TokenCurrent", targets: ["TokenCurrent"])
    ],
    targets: [
        .systemLibrary(name: "CSQLite", pkgConfig: "sqlite3", providers: [.apt(["libsqlite3-dev"])]),
        .target(name: "TokenCurrentCore", dependencies: ["CSQLite"]),
        .executableTarget(name: "TokenCurrent", dependencies: ["TokenCurrentCore"]),
        .testTarget(name: "TokenCurrentCoreTests", dependencies: ["TokenCurrentCore"])
    ]
)
