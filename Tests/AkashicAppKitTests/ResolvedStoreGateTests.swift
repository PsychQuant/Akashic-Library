import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicAppKit

/// #125 的收工判準：**issue body 那段事故程式碼在型別上不可表達**。
///
/// ```swift
/// try GraphModel(store: LibraryStore(root: registered.root, environment: env)).rebuildIndex()
/// ```
///
/// 那行在 #160 之後**仍然編得過**，而且席位 R2 逐字重現同一個事故：keyless 重建
/// 在已註冊 store 裡長出 `.akashic/index.sqlite`、`~/.akashic/index/<key>.sqlite`
/// 從未更新、query 開不了檔。
///
/// ## 為什麼這條測試掃原始碼而不是「寫一個編不過的呼叫」
///
/// 編不過的東西**寫不進測試檔**——它會讓整個 target 編不起來。所以「這行編不過」
/// 這個性質沒辦法用一條普通的斷言表達。
///
/// 掃原始碼是次好的：它驗的是**沒有任何生產程式碼繞過那個型別**。真正的
/// 「編不過」由 `GraphModel.init(store: ResolvedStore)` 的簽名保證，而簽名的存在
/// 由下面第一條斷言釘住。
final class ResolvedStoreGateTests: XCTestCase {

    private var repoRoot: URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // AkashicAppKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // repo root
    }

    /// `GraphModel` 的 init **只**收 `ResolvedStore`。
    ///
    /// 這條看起來像自明之理，但它是上面那個「編不過」的唯一機械見證：簽名一旦
    /// 被放寬回 `LibraryStore`，事故程式碼就又編得過了，而其他測試不會有訊號
    /// （它們傳的是 `ResolvedStore`，那在放寬後的簽名下……編不過。好，那會紅）。
    ///
    /// 真正要防的是**加一個 overload**——`init(store: LibraryStore)` 與
    /// `init(store: ResolvedStore)` 並存時所有測試照樣綠，而閘門形同虛設。
    func testGraphModelHasNoLibraryStoreInitialiser() throws {
        let src = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/AkashicAppKit/GraphModel.swift"),
            encoding: .utf8)
        let inits = src.split(separator: "\n").filter {
            $0.contains("init(store:") && !$0.trimmingCharacters(in: .whitespaces).hasPrefix("///")
        }
        XCTAssertEqual(inits.count, 1, "只能有一個 init——多一個收 LibraryStore 的 overload，"
                       + "閘門就形同虛設而所有測試照樣綠：\(inits)")
        XCTAssertTrue(inits[0].contains("ResolvedStore"),
                      "唯一的 init 必須收 ResolvedStore：\(inits[0])")
    }

    /// **沒有任何生產程式碼自己建 `LibraryStore` 餵給 `GraphModel`。**
    ///
    /// 型別擋住了直接傳，但擋不住 `GraphModel(store: .unregistered(LibraryStore(...),
    /// reason: "..."))`——那條路徑是**刻意留的**（keyless 是合法狀態），代價是
    /// 它可以被誤用。生產程式碼一律走 `AppState.resolvedStore`。
    func testNoProductionCodeConstructsAStoreForGraphModel() throws {
        // **顯示層現在住兩個目錄**（#427/#429）：`AkashicApp/Sources` 只剩 112 行的
        // `@main` 殼，4 個 view 已搬進 `Sources/AkashicAppKit`。
        //
        // 只掃前者的話,本守衛在搬檔那一刻就變成 **tautology**——殼檔 `LibraryStore(`
        // 出現 0 次,兩條斷言必然通過,而下方的反空洞檢查**也照樣綠**（殼檔還在）。
        // 它是全樹唯一擋 #125 那個事故的守衛,失效方式卻完全安靜。
        //
        // 不能改成「掃 AkashicAppKit」了事:那個 target 同時裝著**模型**,而模型建 store
        // 是 #101 刻意開放的路。所以掃兩個目錄 ＋ 一張**封閉豁免表**（附理由）。
        let viewDirs = ["AkashicApp/Sources", "Sources/AkashicAppKit"]
        /// 合法持有 store 建構的模型檔——**封閉列舉,不得依性質相似類推第三個**。
        /// 判準是「它是不是顯示層」,而不是「它現在有沒有觸發斷言」。
        let modelFiles: Set<String> = [
            "AppState.swift",    // #101：解析 store 的唯一入口,它本來就該建
            "GraphModel.swift",  // 接受 `.unregistered` 的那一端,keyless 是合法狀態
        ]
        var files: [URL] = []
        for d in viewDirs {
            let dir = repoRoot.appendingPathComponent(d)
            files += (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil))?
                .filter { $0.pathExtension == "swift" } ?? []
        }
        files = files.filter { !modelFiles.contains($0.lastPathComponent) }
        // **反空洞:數量下限而非「非空」**。搬檔之後只剩殼檔時 `isEmpty` 仍是 false,
        // 所以那個檢查抓不到本輪的失效。實測顯示層有 5 個檔（殼 1 ＋ view 4）。
        XCTAssertGreaterThanOrEqual(files.count, 5,
                                    "顯示層只找到 \(files.count) 個檔——view 被搬走了？"
                                    + "本守衛靠檔案清單存在才有意義,清單縮水即是失效")
        for f in files {
            let text = try String(contentsOf: f, encoding: .utf8)
            XCTAssertFalse(text.contains("LibraryStore("),
                           "\(f.lastPathComponent)：App 層不得自己建 store（#101／#125）")
            XCTAssertFalse(text.contains(".unregistered("),
                           "\(f.lastPathComponent)：生產程式碼不該走 keyless opt-out")
        }
    }

    /// `.unregistered` 的**理由是必填的**——與 `display-safe-exempt` 同一個哲學。
    ///
    /// 這條驗的是簽名，不是內容：編譯器強制存在，讀者強制看見。
    func testUnregisteredRequiresAReason() throws {
        let src = try String(
            contentsOf: repoRoot.appendingPathComponent("Sources/AkashicStoreIO/ResolvedStore.swift"),
            encoding: .utf8)
        XCTAssertTrue(src.contains("unregistered(_ store: LibraryStore, reason: String)"),
                      "理由不得變成選填——例外要留下可稽核的字")
    }

    /// 行為面：`AppState.resolvedStore` 帶著 key，keyless 與帶 key 各自去對的位置。
    func testResolvedStoreCarriesTheRegistryKey() throws {
        let home = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-125home-\(UUID().uuidString)")
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-125-\(UUID().uuidString)")
        defer {
            try? FileManager.default.removeItem(at: home)
            try? FileManager.default.removeItem(at: root)
        }
        try LibraryStore(root: root).ensureLayout()

        let keyed = AppState(root: root, key: "main", environment: ["AKASHIC_HOME": home.path])
        XCTAssertTrue(keyed.resolvedStore.store.indexURL.path.hasPrefix(home.path + "/"),
                      "帶 key → index 在 <home>/index/")
        let keyless = AppState(root: root, key: nil, environment: ["AKASHIC_HOME": home.path])
        XCTAssertTrue(keyless.resolvedStore.store.indexURL.path.hasPrefix(root.path + "/"),
                      "keyless → 回落 in-store。keyless 是合法狀態，不是錯誤")
    }
}
