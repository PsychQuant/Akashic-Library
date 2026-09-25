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
            "Sources/AkashicStoreIO/StoreHealth.swift",          // duplicateVerdictRecordIssues（D64）——用的是 kindByteKey
            "Sources/AkashicStoreIO/DivergenceResolve.swift",    // fieldsLostByMerging ×3（D69／D73）
            "Sources/AkashicMCPKit/AkashicService.swift",        // paginated 冪等閘 ×2（D69）
            "Sources/AkashicMCPKit/UpdatePerson.swift",          // references append-only 去重（D73）
            "Sources/AkashicCore/AddOnlyEnrichment.swift",       // applied 的冪等（D73）
            "Sources/AkashicCore/VerdictRecordKey.swift",        // 未決記錄的記錄鍵（change resolution-verdict-states，#619）
            "Sources/AkashicMCPKit/UndecidedVerdicts.swift",     // 同一次呼叫寫下的未決記錄（R1 verify：第二個相同 id 不報成「已在」）
            "Sources/AkashicMCPKit/OrgUndecidedVerdicts.swift",  // org 族的同一件事（change org-undecided-leg，#643）
        ]
        let sources = Self.repoRoot.appendingPathComponent("Sources")
        var found: Set<String> = []
        let e = try XCTUnwrap(FileManager.default.enumerator(at: sources, includingPropertiesForKeys: nil))
        // R28（R27 verify DA 第 21 列，mutation 實證）：needle 是 `byteExactKey|kindByteKey`、只看**程式**行——`StoreHealth` 真正的判定點用
        // `kindByteKey`（`byteExactKey` 只在一行註解裡出現），R27 的守衛改一行註解就紅、新增一個只用 `kindByteKey` 的判定點卻全綠
        for case let url as URL in e where url.pathExtension == "swift" {
            let code = try String(contentsOf: url, encoding: .utf8).split(separator: "\n").map { line -> Substring in
                let t = line.drop { $0 == " " }
                if t.hasPrefix("//") { return "" }
                if let c = line.range(of: "   //") { return line[..<c.lowerBound] }   // 行尾的 exempt／說明註解
                return line
            }.joined(separator: "\n")
            if code.contains("byteExactKey") || code.contains("kindByteKey") {
                found.insert(String(url.path.dropFirst(Self.repoRoot.path.count + 1)))
            }
        }
        XCTAssertEqual(found, expected, "多了：\(found.subtracting(expected))；少了：\(expected.subtracting(found))")
    }
}
