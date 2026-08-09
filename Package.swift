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
        .target(name: "AkashicProposition", dependencies: ["AkashicCore"]),
        .target(name: "AkashicSQLite"),
        .target(name: "AkashicZoteroImport", dependencies: ["AkashicStoreIO", "AkashicSQLite"]),
        .target(name: "AkashicIndex", dependencies: ["AkashicStoreIO", "AkashicSQLite"]),
        .target(name: "AkashicQuery", dependencies: ["AkashicIndex", "AkashicSQLite", "AkashicCore"]),
        .target(name: "AkashicGraph", dependencies: ["AkashicIndex", "AkashicSQLite", "AkashicCore"]),
        .target(name: "AkashicWoSImport", dependencies: ["AkashicCore", "AkashicStoreIO"]),
        .target(name: "AkashicExport", dependencies: [
            "AkashicStoreIO",
            .product(name: "BiblatexAPA", package: "biblatex-apa-swift"),
        ]),
        .executableTarget(name: "akashic", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicWoSImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph",
            "AkashicMCPKit",   // #68：update-person 與 MCP 面共用同一條合併路徑
            .product(name: "BiblatexAPA", package: "biblatex-apa-swift"),   // #206：create-entry --format bib
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
        // 測試 helper（只被 test targets 依賴，不經任何 product 對外）：
        // guard 本體 + C constructor loader（bundle 載入即啟用，#124 verify F1/F5）
        .target(name: "AkashicTestGuard", dependencies: ["AkashicTestGuardLoader"]),
        .target(name: "AkashicTestGuardLoader"),
        .testTarget(name: "AkashicKitTests", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph", "AkashicSQLite",
            "AkashicWoSImport", "AkashicTestGuard",
        ]),
        .testTarget(name: "AkashicPropositionTests",
                    dependencies: ["AkashicProposition", "AkashicCore"]),
        .testTarget(name: "AkashicCLITests", dependencies: ["akashic", "AkashicTestGuard"]),
        .testTarget(name: "AkashicMCPTests", dependencies: ["AkashicMCPKit", "akashic-mcp", "AkashicTestGuard", "AkashicQuery", "AkashicGraph", "AkashicStoreIO"]),
        .testTarget(name: "AkashicAppKitTests",
                    dependencies: ["AkashicAppKit", "AkashicCore", "AkashicStoreIO", "AkashicTestGuard"]),
    ]
)
