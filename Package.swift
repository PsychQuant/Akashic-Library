// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AkashicKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AkashicKit", targets: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph",
        ]),
        .executable(name: "akashic", targets: ["akashic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", "5.0.0"..<"7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(path: "repos/biblatex-apa-swift"),
    ],
    targets: [
        .target(name: "AkashicCore", dependencies: [
            .product(name: "Yams", package: "Yams"),
        ]),
        .target(name: "AkashicStoreIO", dependencies: [
            "AkashicCore",
            .product(name: "Yams", package: "Yams"),
        ]),
        .target(name: "AkashicEntity", dependencies: ["AkashicCore"]),
        .target(name: "AkashicSQLite"),
        .target(name: "AkashicZoteroImport", dependencies: ["AkashicStoreIO", "AkashicSQLite"]),
        .target(name: "AkashicIndex", dependencies: ["AkashicStoreIO", "AkashicSQLite"]),
        .target(name: "AkashicQuery", dependencies: ["AkashicIndex", "AkashicSQLite"]),
        .target(name: "AkashicGraph", dependencies: ["AkashicIndex", "AkashicSQLite"]),
        .target(name: "AkashicExport", dependencies: [
            "AkashicStoreIO",
            .product(name: "BiblatexAPA", package: "biblatex-apa-swift"),
        ]),
        .executableTarget(name: "akashic", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .testTarget(name: "AkashicKitTests", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph", "AkashicSQLite",
        ]),
        .testTarget(name: "AkashicCLITests", dependencies: ["akashic"]),
    ]
)
