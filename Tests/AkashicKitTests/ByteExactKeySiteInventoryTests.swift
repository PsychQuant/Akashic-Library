import XCTest
import Foundation
@testable import AkashicCore

/// #554 R27（R26 verify requirements 第 8 列、logic 第 16 列、regression 第 23 列、security 第 51 列）：`ProvenanceReference.byteExactKey` 的 doc
/// 說「位元組相等的判定點是封閉列舉」，而它附的稽核指令跑出來與列舉對不上。機械可檢查的版本是：引用 `byteExactKey` 的檔案集合是封閉的——
/// 新增一個檔要在這裡加一列並在 doc 的列舉裡加一處。
final class ByteExactKeySiteInventoryTests: XCTestCase {
    private static let repoRoot: URL = {
        var u = URL(fileURLWithPath: #filePath)
        while u.lastPathComponent != "Tests" { u.deleteLastPathComponent() }
        return u.deletingLastPathComponent()
    }()

    func testFilesReferencingByteExactKeyAreAClosedList() throws {
        let expected: Set<String> = [
            "Sources/AkashicCore/Provenance.swift",              // 定義
            "Sources/akashic-guards/BacklinkRatchetData.swift",  // 守衛的裁決表（computed 欄位要具名）
            "Sources/AkashicStoreIO/LibraryStore.swift",         // migratedVerdicts 的折疊（D62／D65）
            "Sources/AkashicStoreIO/StoreHealth.swift",          // duplicateVerdictRecordIssues（D64）
            "Sources/AkashicStoreIO/DivergenceResolve.swift",    // fieldsLostByMerging ×3（D69／D73）
            "Sources/AkashicMCPKit/AkashicService.swift",        // paginated 冪等閘 ×2（D69）
            "Sources/AkashicMCPKit/UpdatePerson.swift",          // references append-only 去重（D73）
            "Sources/AkashicCore/AddOnlyEnrichment.swift",       // applied 的冪等（D73）
        ]
        let sources = Self.repoRoot.appendingPathComponent("Sources")
        var found: Set<String> = []
        let e = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        for case let url as URL in e where url.pathExtension == "swift" {
            if try String(contentsOf: url, encoding: .utf8).contains("byteExactKey") {
                found.insert(String(url.path.dropFirst(Self.repoRoot.path.count + 1)))
            }
        }
        XCTAssertEqual(found, expected, "多了：\(found.subtracting(expected))；少了：\(expected.subtracting(found))")
    }
}
