import XCTest

/// 「library」三義的消歧措辭必須留在原處（#315）。
///
/// ## 為什麼這需要守衛
///
/// 「library」在本專案至少承載三個意思，而**最危險的一對**是：
///
/// | 介面 | 意思 | 值域 |
/// |---|---|---|
/// | CLI `--library` | **開哪個 store** | 檔案系統路徑 |
/// | MCP `library` 參數 | store **內**的 membership 分類 | `StoreKey` |
///
/// 同名、鄰接、不同型別、不同語意，而**錯用不會報錯**——只會 scope 到錯的東西，然後回一個
/// 看起來完全合理的空集合或子集。這種缺陷不會被任何測試抓到，因為兩邊各自都「正確地」
/// 執行了被要求的事。
///
/// #315 的三個候選裡，本組守的是 **option (2)（保留名稱、強化描述）**——零成本下限。
/// 它的弱點寫在 issue 裡：「保證只來自文字」。這一組就是把那個保證變成機械的。
///
/// ## 一個反直覺的方向（改名裁決時需要）
///
/// issue 的 option (1) 預設要改的是 MCP 參數。但 store 自己的目錄叫 **`libraries/`**
/// ——membership 那個意思才是 store 的**原生詞彙**，CLI 的 `--library`（store root）反而
/// 是異類。所以若日後裁定改名，該改的很可能是 CLI 旗標而不是 MCP 參數，而那是使用者
/// 手打的介面、成本高得多。本組不預設任何一邊，只確保現況的消歧文字不會靜默消失。
final class LibraryTermDisambiguationTests: XCTestCase {

    private func repoRoot() throws -> URL {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(
                atPath: dir.appendingPathComponent("Package.swift").path) { return dir }
        }
        throw XCTSkip("找不到 repo root")
    }

    private func source(_ rel: String) throws -> String {
        try String(contentsOf: try repoRoot().appendingPathComponent(rel), encoding: .utf8)
    }

    /// CLI 的 `--library` help 必須說出它**不是** membership 分類。
    func testCLIHelpDisambiguatesAgainstMembership() throws {
        let src = try source("Sources/akashic/CLI.swift")
        XCTAssertTrue(src.contains("store root 路徑"),
                      "`--library` 的 help 應直接說它是 store root")
        XCTAssertTrue(src.contains("**不是** membership 分類"),
                      "`--library` 的 help 必須說出它不是什麼——#315 的危害正是"
                      + "「兩個意思看起來一樣」")
    }

    /// MCP 的兩個 `library` 參數描述都必須說出它們**不是** store root。
    ///
    /// **兩個都要**：只改一個會留下一個仍然誤導的入口，而讀者不會知道哪個是被修過的。
    func testMCPSchemaDescriptionsDisambiguateAgainstStoreRoot() throws {
        let src = try source("Sources/akashic-mcp/Server.swift")
        // **只數 schema 描述，不數註解。** 第一版沒濾註解，於是我自己寫的那行
        // `// #315：明寫它**不是** store root` 也被算進去，斷言 2 卻命中 3
        // ——一個守衛把自己的說明文字當成被守的對象。
        let descriptionLines = src.split(separator: "\n", omittingEmptySubsequences: false)
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("//") }
            .joined(separator: "\n")
        let occurrences = descriptionLines.components(separatedBy: "**不是** store root").count - 1
        XCTAssertEqual(occurrences, 2,
                       "兩個 MCP tool 的 `library` 描述都要說出它不是 store root，"
                       + "實際命中 \(occurrences) 處（已排除註解行）")
        // 兩個 tool 的描述用不同動詞（篩選／過濾），分別斷言以確保**兩個都**改了
        // ——只改一個會留下一個仍然誤導的入口。
        XCTAssertTrue(descriptionLines.contains("membership 分類 key 篩選"),
                      "akashic_search 的描述應正面說出它是 store 內的分類")
        XCTAssertTrue(descriptionLines.contains("membership 分類 key 過濾"),
                      "akashic_person 的描述應正面說出它是 store 內的分類")
    }

    /// plugin skill 的文件裡**兩義並存**，所以兩邊都要有警告。
    ///
    /// 這不是假設的風險：#315 量測時發現同一個 skill 的兩份文件分別用了兩個意思
    /// （`SKILL.md` 的 `akashic_person(library:)` 與 `writing-to-the-store.md` 的
    /// `--library <暫存路徑>`），而**沒有任何一處提醒讀者它們不同**。
    func testSkillDocsWarnAboutBothSenses() throws {
        let skill = try source("plugin/skills/akashic-bootstrap/SKILL.md")
        XCTAssertTrue(skill.contains("#315"),
                      "SKILL.md 用了 MCP 義的 `library:`，必須警告同名的另一義")
        XCTAssertTrue(skill.contains("membership"),
                      "SKILL.md 應正面說出那裡的 library 是 membership 分類")

        let writing = try source(
            "plugin/skills/akashic-bootstrap/references/writing-to-the-store.md")
        XCTAssertTrue(writing.contains("#315"),
                      "writing-to-the-store.md 用了 CLI 義的 `--library`，必須警告另一義")
        XCTAssertTrue(writing.contains("開哪個 store"),
                      "應正面說出那裡的 --library 是 store root")
    }

    /// **反向守衛**：`libraries/` 這個目錄名是 membership 義的來源，不得被誤讀成 store root。
    ///
    /// 這條記錄的是上面 doc 裡那個反直覺的方向。它斷言的是一個**事實**（store 的目錄叫
    /// `libraries/`），而那個事實是日後改名裁決的依據——若哪天目錄改名，這條會紅，
    /// 提醒重新檢視整個 #315 的分析。
    func testStoreDirectoryForMembershipIsStillNamedLibraries() throws {
        let src = try source("Sources/AkashicStoreIO/LibraryStore.swift")
        XCTAssertTrue(src.contains("\"libraries\""),
                      "membership 定義住在 store 的 `libraries/` 目錄——那是「library "
                      + "＝membership」為原生詞彙的依據（#315 的改名分析建立在此）")
    }
}
