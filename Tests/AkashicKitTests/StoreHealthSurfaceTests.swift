import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// `StoreHealth` 的每個欄位都必須被消費，不得只存在型別裡（#263）。
///
/// ## 這道守衛防的是什麼
///
/// #263 的修法把健康事實收斂成單一來源，但那只解決了**已知的**欄位。真正的風險是
/// **下一個**：有人加一項檢查到 `StoreHealth`，只在 `doctor()` 渲染、忘了 App
/// ——第三條路徑沒了，卻換成「同一條路徑但只有一面顯示」。
///
/// 那個失敗**安靜**：型別編譯得過、測試全綠、doctor 照樣報問題，只有 App 使用者
/// 看不到。而 App 是取代 Zotero 的主要 UI（`replace-endnote-and-zotero`）。
///
/// ## 為什麼用反射而非人工清單
///
/// 人工清單會與型別分岔——那正是 `entity-backlink-completeness` 的表錯過三次的形狀。
/// 反射問的是型別自己：「你有哪些欄位」，然後逐一要求兩個消費面都提到它。
final class StoreHealthSurfaceTests: XCTestCase {

    /// 用一個真實的 `StoreHealth` 值取欄位名——不寫死清單。
    private func healthFieldNames() throws -> [String] {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-health-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let health = store.health(from: try store.load())
        return Mirror(reflecting: health).children.compactMap(\.label)
    }

    /// 欄位不得為空——反射拿不到東西時，下面兩條會 vacuous pass。
    func testReflectionActuallySeesFields() throws {
        let names = try healthFieldNames()
        XCTAssertGreaterThanOrEqual(names.count, 10,
                                    "反射應看到 StoreHealth 的全部欄位，實得 \(names)")
    }

    /// **每個欄位都必須被 `doctor()` 提到**。
    func testEveryFieldIsConsumedByDoctor() throws {
        let source = try repoFile("Sources/AkashicMCPKit/AkashicService.swift")
        // 只看 doctor() 那一段——整檔搜尋會讓別處偶然提到某個名字就算通過。
        guard let start = source.range(of: "public func doctor() throws -> String {") else {
            return XCTFail("找不到 doctor() —— 本測試的前提不成立")
        }
        let body = String(source[start.lowerBound...].prefix(6000))
        for field in try healthFieldNames() {
            XCTAssertTrue(body.contains("health.\(field)"),
                          "doctor() 沒有消費 StoreHealth.\(field) —— "
                          + "加了欄位卻只有一面渲染，那是 #263 修掉的分岔換個形狀回來")
        }
    }

    /// **每個欄位都必須經由 `AppState` 到得了 App 面**。
    ///
    /// App 的 UI（`AkashicApp/Sources/ContentView.swift`）不在 SwiftPM target 內、
    /// 本測試建置不到它，所以這裡驗的是**上游那一段**：`AppState` 必須持有整份
    /// `health`，讓 UI 拿得到每個欄位。持有整份而非逐欄位複製，正是讓「加欄位」
    /// 不需要改 `AppState` 的原因。
    func testAppStateHoldsTheWholeHealthValue() throws {
        let source = try repoFile("Sources/AkashicAppKit/AppState.swift")
        XCTAssertTrue(source.contains("var health: StoreHealth?"),
                      "AppState 必須持有整份 StoreHealth——逐欄位複製會讓新欄位漏掉")
        XCTAssertTrue(source.contains("store.health(from:"),
                      "AppState 必須走 LibraryStore.health(from:)，不得自行推導")
    }

    /// `AppState` **不得**自行重算健康事實——那會讓單一路徑失效。
    func testAppStateDoesNotRederiveHealthFacts() throws {
        let source = try repoFile("Sources/AkashicAppKit/AppState.swift")
        XCTAssertFalse(source.contains("crossRecordIssues()"),
                       "AppState 不得自己算 crossRecordIssues——走 health")
        XCTAssertFalse(source.contains("auditSourceIndex()"),
                       "AppState 不得自己算 sources audit——走 health")
        XCTAssertFalse(source.contains("layoutResidue()"),
                       "AppState 不得自己算 layoutResidue——走 health")
    }

    private func repoFile(_ rel: String) throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            let candidate = dir.appendingPathComponent(rel)
            if FileManager.default.fileExists(atPath: candidate.path) {
                return try String(contentsOf: candidate, encoding: .utf8)
            }
        }
        throw XCTSkip("找不到 \(rel) —— 跳過來源掃描")
    }
}
