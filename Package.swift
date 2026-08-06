// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "AkashicKit",
    platforms: [.macOS(.v14)],
    products: [
        .library(name: "AkashicKit", targets: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph", "AkashicWoSImport",
        ]),
        .library(name: "AkashicAppKit", targets: ["AkashicAppKit"]),
        .executable(name: "akashic", targets: ["akashic"]),
    ],
    dependencies: [
        .package(url: "https://github.com/jpsim/Yams.git", "5.0.0"..<"7.0.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", .upToNextMinor(from: "0.12.0")),
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
        .target(name: "AkashicWoSImport", dependencies: ["AkashicCore", "AkashicStoreIO"]),
        .target(name: "AkashicExport", dependencies: [
            "AkashicStoreIO",
            .product(name: "BiblatexAPA", package: "biblatex-apa-swift"),
        ]),
        .executableTarget(name: "akashic", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicWoSImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .target(name: "AkashicAppKit", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph",
        ]),
        .target(name: "AkashicMCPKit", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph",
            .product(name: "Yams", package: "Yams"),
        ]),
        .executableTarget(name: "akashic-mcp", dependencies: [
            "AkashicMCPKit",
            .product(name: "MCP", package: "swift-sdk"),
        ]),
        .target(name: "AkashicTestGuard", linkerSettings: [
            // XCTest 不在一般 build 的預設搜尋路徑——測試 helper target 的標準連結設定
            .unsafeFlags(["-Xlinker", "-weak_framework", "-Xlinker", "XCTest"], .when(platforms: [.macOS])),
        ]),
        .testTarget(name: "AkashicKitTests", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph", "AkashicSQLite",
            "AkashicWoSImport", "AkashicTestGuard",
        ]),
        .testTarget(name: "AkashicCLITests", dependencies: ["akashic", "AkashicTestGuard"]),
        .testTarget(name: "AkashicMCPTests", dependencies: ["AkashicMCPKit", "akashic-mcp", "AkashicTestGuard"]),
        .testTarget(name: "AkashicAppKitTests",
                    dependencies: ["AkashicAppKit", "AkashicCore", "AkashicStoreIO", "AkashicTestGuard"]),
    ]
)
