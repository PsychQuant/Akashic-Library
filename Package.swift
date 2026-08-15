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
        .library(name: "TractatusDocs", targets: ["TractatusDocs"]),
        .executable(name: "tractatus-doc", targets: ["tractatus-doc"]),
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
        .target(name: "AkashicProposition", dependencies: ["AkashicCore", "AkashicStoreIO"]),
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
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        .target(name: "AkashicAppKit", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph",
        ]),
        .target(name: "AkashicMCPKit", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicWoSImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph",
            .product(name: "Yams", package: "Yams"),
        ]),
        .executableTarget(name: "akashic-mcp", dependencies: [
            "AkashicMCPKit",
            .product(name: "MCP", package: "swift-sdk"),
        ]),
        .target(name: "TractatusDocs", dependencies: [
            "AkashicCore",
            .product(name: "Yams", package: "Yams"),
        ]),
        .executableTarget(name: "tractatus-doc", dependencies: [
            "TractatusDocs",
            .product(name: "ArgumentParser", package: "swift-argument-parser"),
        ]),
        // Unicode v1 table 只能由檢入的 15.1.0 UCD 離線重播；production 不依賴此工具。
        .executableTarget(
            name: "UnicodeNormalizationGenerator",
            path: "Tools/UnicodeNormalizationGenerator"
        ),
        // 測試 helper（只被 test targets 依賴，不經任何 product 對外）：
        // guard 本體 + C constructor loader（bundle 載入即啟用，#124 verify F1/F5）
        .target(name: "AkashicTestGuard", dependencies: ["AkashicTestGuardLoader"]),
        .target(name: "AkashicTestGuardLoader"),
        .testTarget(name: "AkashicKitTests", dependencies: [
            "AkashicCore", "AkashicStoreIO", "AkashicEntity", "AkashicZoteroImport",
            "AkashicExport", "AkashicIndex", "AkashicQuery", "AkashicGraph", "AkashicSQLite",
            "AkashicWoSImport", "AkashicTestGuard",
        ]),
        .testTarget(
            name: "AkashicPropositionTests",
            dependencies: ["AkashicProposition", "AkashicCore", "AkashicStoreIO"],
            resources: [.copy("Fixtures")]
        ),
        .testTarget(name: "AkashicCLITests", dependencies: ["akashic", "AkashicTestGuard"]),
        .testTarget(name: "AkashicMCPTests", dependencies: ["AkashicMCPKit", "akashic-mcp", "AkashicTestGuard", "AkashicQuery", "AkashicGraph", "AkashicStoreIO"]),
        .testTarget(name: "AkashicAppKitTests",
                    dependencies: ["AkashicAppKit", "AkashicCore", "AkashicStoreIO", "AkashicTestGuard"]),
        .testTarget(name: "TractatusDocsTests", dependencies: [
            "TractatusDocs", "tractatus-doc", "AkashicTestGuard",
        ], resources: [.copy("Fixtures")]),
    ]
)
