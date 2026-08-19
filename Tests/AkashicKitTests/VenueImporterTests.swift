import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicWoSImport
@testable import AkashicZoteroImport

/// importer 產生 `.literal` venue ref（#304 task 3.2）。
/// 契約：只 literal 不猜 key（Importer never guesses scenario）；fields 原樣保留；
/// 對映唯一來源 `VenueDerivation`（與 migration 共用，不留第二份清單）。
final class VenueImporterTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vimp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let header = "Authors\tAuthor Full Names\tArticle Title\tSource Title\tPublication Year\tDOI\n"

    func testWoSImportProducesLiteralVenueAndKeepsField() throws {
        let tsv = header
            + "Cheng, C\tCheng, Che\tIdentifiability\tPSYCHOMETRIKA\t2025\t10.1/xyz\n"
        _ = try WoSImport.run(text: tsv, store: store)
        let e = try store.load().entries[0]
        XCTAssertEqual(e.venues, [.literal("PSYCHOMETRIKA")],
                       "WoS 匯入只產生 literal——即使店裡日後有同名 venue 也不自動配對")
        XCTAssertEqual(e.fields["journaltitle"], "PSYCHOMETRIKA", "欄位字串照舊保留")
    }

    func testZoteroMappingDerivesLiteralOnlyWhenEmpty() throws {
        let item = ZoteroItem(key: "K1", version: 1, libraryID: 1,
                              typeName: "journalArticle",
                              fields: ["title": "T", "publicationTitle": "Psychometrika"],
                              authors: [], tags: [], attachmentPaths: [])
        var entry = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "")
        ZoteroMapping.applyBiblatexFields(from: item, to: &entry)
        XCTAssertEqual(entry.venues, [.literal("Psychometrika")])

        // 已歸戶（.key）者：pull 更新不得覆寫
        var resolved = Entry(id: UUID(), citekey: "y2025", type: .periodicalArticle, title: "")
        resolved.venues = [.key("psychometrika")]
        ZoteroMapping.applyBiblatexFields(from: item, to: &resolved)
        XCTAssertEqual(resolved.venues, [.key("psychometrika")],
                       "既有 venues（含歸戶 key）永不被 pull 覆寫")
    }
}
