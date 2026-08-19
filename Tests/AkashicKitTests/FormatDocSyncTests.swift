import XCTest
@testable import AkashicStoreIO

/// `StoreVersion.supported` 與兩份文件的 format 對照表不得分岔（#311）。
///
/// ## 為什麼需要機械檢查
///
/// store format 的**真正正典是程式碼**（`StoreVersion.supported`）——它是 refuse-if-newer
/// 實際比較的那個數字。兩份文件都是它的摘寫：
///
/// - `docs/store-format.md` 的版本對照表（詳，含實測依據）
/// - `README.md` 的摘要表（略，指向前者）
///
/// 三者之間**沒有任何機制保證同步**，而分岔已經發生過兩次：
///
/// 1. **#301**：正典表有 1–11 全部列，README 漏掉 format 8，且把「原佔 8、**已被 #232
///    佔用**順延」砍成「rebase 順延」——使缺口讀起來像跳號。發現路徑是有人剛好去比對兩張表。
/// 2. **#311 落地時實測（2026-08-19）**：#336 把 `supported` bump 到 12，**兩份文件都沒改**。
///    這比 #301 更嚴重——#311 開案時只設想「README vs 正典」的分岔，實況是**程式碼與兩份
///    文件都分岔**。
///
/// 第 2 次正是 #311 預言的「format 12 出現時同一個缺陷會再發生一次」。它在 issue 開立後
/// 五天內就應驗了，而且**沒有任何人發現**——直到本測試存在為止。
///
/// ## 為什麼是「supported 必須出現在兩份文件」而不是全等比對
///
/// README 是**摘寫**，內容本來就不該與正典表逐字相同；全等比對會逼兩份文件變成同一份，
/// 那反而消滅了摘要的價值。本測試只擋**最常犯且後果最實的那一種**：bump 了程式碼、忘了文件。
///
/// 另外釘住**連續性**——文件的 format 編號不得跳號。#301 的第二半（把「已被佔用順延」
/// 砍成「rebase 順延」）就是跳號讀起來像遺漏的成因。
final class FormatDocSyncTests: XCTestCase {

    /// repo root。測試在 `.build/` 下跑，往上走到含 `Package.swift` 的目錄。
    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) {
                return dir
            }
        }
        throw XCTSkip("找不到 repo root（Package.swift）——跳過 doc-sync 檢查")
    }

    private func read(_ rel: String) throws -> String {
        let url = try repoRoot().appendingPathComponent(rel)
        return try String(contentsOf: url, encoding: .utf8)
    }

    /// 目前支援的 format **必須**在正典表裡有一列。
    func testSupportedFormatHasRowInCanonicalTable() throws {
        let doc = try read("docs/store-format.md")
        let expected = "| \(StoreVersion.supported) |"
        XCTAssertTrue(doc.contains(expected),
                      """
                      docs/store-format.md 缺 format \(StoreVersion.supported) 的列。
                      bump 了 StoreVersion.supported 就要補正典表——這正是 #301／#311 兩次分岔的形狀。
                      """)
    }

    /// 目前支援的 format **必須**在 README 摘要表裡有一列。
    func testSupportedFormatHasRowInREADME() throws {
        let readme = try read("README.md")
        let expected = "| format \(StoreVersion.supported) |"
        XCTAssertTrue(readme.contains(expected),
                      """
                      README.md 缺 format \(StoreVersion.supported) 的列。
                      README 是摘寫、內容不必與正典逐字相同，但**必須有那一列**。
                      """)
    }

    /// 文件的 format 編號不得跳號。
    ///
    /// 釘住 #301 的第二半：跳號讀起來像遺漏，而「原佔 8、已被 #232 佔用順延」這種
    /// 資訊一旦在複製過程流失，缺口就無法與真正的遺漏區分。
    func testCanonicalTableFormatNumbersAreContiguous() throws {
        let doc = try read("docs/store-format.md")
        var found: Set<Int> = []
        for line in doc.split(separator: "\n", omittingEmptySubsequences: false) {
            guard line.hasPrefix("| ") else { continue }
            let cell = line.dropFirst(2).prefix(while: { $0 != "|" })
                .trimmingCharacters(in: .whitespaces)
            if let n = Int(cell), n >= 1, n <= StoreVersion.supported { found.insert(n) }
        }
        let missing = (1...StoreVersion.supported).filter { !found.contains($0) }
        XCTAssertTrue(missing.isEmpty,
                      "docs/store-format.md 的 format 編號跳號，缺：\(missing.sorted())")
    }
}
