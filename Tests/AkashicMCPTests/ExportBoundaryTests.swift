import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// 匯出／圖形的**輸出邊界**——走真的呼叫點，不走測試自己組裝的 library call。
///
/// ## 為什麼這個檔案存在（#171 verify 171-1）
///
/// #165 原本的測試呼叫的是 `displaySafeMultiline(...)`，由測試自己傳入匯出量級的
/// 上限。它綠，但它**沒有經過被修的那兩行**。席位的 mutation 給出結論性的證明：
/// 把 `AkashicService.export()` 與 `Commands.swift` stdout 分支的消毒**整條還原**，
/// 1014 條測試一條都不紅。
///
/// 那個測試量的是一個 PR 之前就已經正確的 library function。所以這裡的每一條都
/// 從真入口進——MCP 直呼 `AkashicService`，CLI 跑真 binary 讀真 stdout。
///
/// ## 兩個判準
///
/// - **危險字元不得抵達 sink**：C0／bidi／LS-PS。
/// - **文件必須仍是合法文件**：這是 `documentSafe` 存在的理由。`displaySafe` 跳脫
///   反斜線（反偽造），而反斜線在 .bib 與 JSON 裡**是內容語法**——套上去會讓
///   `\textit{}` 變成 `\u{005C}textit{}`、讓 JSON 不能 parse。同一份匯出走
///   `--output` 是好的、走 stdout 是壞的，而 stdout 是預設路徑。
final class ExportBoundaryTests: XCTestCase {
    private let esc = "\u{1B}"
    private let rtl = "\u{202E}"
    private let lineSep = "\u{2028}"

    private var root: URL!
    private var fakeHome: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-exb-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try store.writeEntry(dirtyEntry())
        try store.writeEntry(latexEntry())
        service = AkashicService(root: root, environment: ["AKASHIC_HOME": fakeHome.path])
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    /// 三種各自不同的威脅：ANSI escape injection、RTL override、行結構注入。
    private func dirtyEntry() -> Entry {
        let dirty = "Evil\(esc)[31m\(rtl)gnihsihp\(lineSep)line2"
        var e = Entry(id: UUID(), citekey: "dirty2020", type: "article", title: dirty)
        e.authors = [.literal(dirty)]
        e.fields = ["journaltitle": dirty]
        e.date = "2020"
        return e
    }

    /// **正常的書目內容**，不是攻擊面——Zotero 匯入的書目帶 LaTeX 跳脫是常態。
    private func latexEntry() -> Entry {
        var e = Entry(id: UUID(), citekey: "latex2020", type: "article",
                      title: #"Emphasis \textit{word}, 100% & caf\'{e}"#)
        e.fields = ["journaltitle": #"Journal of \LaTeX{} Studies"#]
        e.date = "2020"
        return e
    }

    // MARK: - MCP：真呼叫點

    /// 拔掉 `AkashicService.export` 的消毒，這條就紅。
    func testMCPExportBlocksDangerousScalars() throws {
        let bib = try service.export(citekeys: ["dirty2020"], format: "bib")
        XCTAssertFalse(bib.contains(esc), "raw ESC 進 LLM context＝ANSI escape injection")
        XCTAssertFalse(bib.contains(rtl), "raw U+202E＝RTL override")
        XCTAssertFalse(bib.contains(lineSep), "U+2028 是行結構注入面")
        XCTAssertTrue(bib.contains("dirty2020"), "消毒不是刪除——仍要看得出是哪一筆")
    }

    /// **171-2：消毒後仍必須是合法的 .bib。** 反斜線是內容語法，不得被跳脫。
    func testMCPBibKeepsBackslashSyntaxIntact() throws {
        let bib = try service.export(citekeys: ["latex2020"], format: "bib")
        XCTAssertTrue(bib.contains(#"\textit{word}"#),
                      "反斜線被跳脫 → biblatex 讀到 \\u{005C}textit → 檔案壞掉：\(bib)")
        XCTAssertTrue(bib.contains(#"\LaTeX{}"#), "同上")
        XCTAssertTrue(bib.contains("100%"), "TeX special 由下游處理，本層不碰")
    }

    /// **171-2 的更嚴重版：CSL-JSON 消毒後必須仍能 parse。**
    ///
    /// `JSONSerialization` 產生的 `\"` 被再跳脫成 `\u{005C}"` → 整份不是合法 JSON，
    /// 而 MCP 的 `akashic_export(format:"csl-json")` 走的正是這條路徑。
    func testMCPCSLJSONStaysParseable() throws {
        let json = try service.export(citekeys: nil, format: "csl-json")
        XCTAssertNoThrow(try JSONSerialization.jsonObject(with: Data(json.utf8)),
                         "消毒破壞了 JSON 語法：\(json.prefix(400))")
        XCTAssertFalse(json.contains(esc), "危險字元仍要擋")
        XCTAssertFalse(json.contains(rtl), "同上")
    }

    /// **171-3：abstract 是常態欄位，不得被行長上限截成不閉合的大括號。**
    ///
    /// `BibWriter.serialize` 把每個欄位放單一行，所以「.bib 的行本來就短」不成立。
    func testLongAbstractIsNotTruncated() throws {
        var e = Entry(id: UUID(), citekey: "long2020", type: "article", title: "Long")
        let abstract = String(repeating: "A", count: 5_000)
        e.fields = ["abstract": abstract]
        e.date = "2020"
        try LibraryStore(root: root).writeEntry(e)
        let bib = try service.export(citekeys: ["long2020"], format: "bib")
        XCTAssertFalse(bib.contains("已截斷"), "截斷一份文件永遠產生壞掉的文件")
        XCTAssertTrue(bib.contains(abstract), "5000 字元的 abstract 要完整")
    }

    /// **超量拒絕、不截斷**——MCP 的下游是 LLM context，截一半的 .bib 是壞檔。
    ///
    /// 用**多筆聚合**而非單筆巨檔：store 自己有 8 MB 的單檔上限
    /// （`AliasEventBudget.fileTooLarge`），所以單筆根本寫不進去。這也更貼近真實
    /// 的爆量來源——MCP 的 `akashic_export(citekeys: nil)` 是全庫匯出。
    func testMCPRefusesOversizeExportInsteadOfTruncating() throws {
        let store = LibraryStore(root: root)
        let chunk = String(repeating: "A", count: 3_000_000)
        for i in 0..<4 {
            var e = Entry(id: UUID(), citekey: "huge\(i)y2020", type: "article", title: "Huge \(i)")
            e.fields = ["abstract": chunk]
            e.date = "2020"
            try store.writeEntry(e)
        }
        XCTAssertThrowsError(try service.export(citekeys: nil, format: "bib")) { err in
            let msg = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(msg.contains("--output"), "拒絕時要指路，否則使用者卡住：\(msg)")
        }
    }

    /// **171-4：`graph` 是 `export-bib` 逐行對應的孿生**，三種格式都要消毒。
    ///
    /// 三個 renderer 各自的 escape 處理的是各自格式的 metacharacter，與 C0／bidi
    /// 是兩組不相干的字元集——這正是 #165 用來反駁「跳脫交給下游」的同一論證。
    func testMCPGraphSanitisesAllThreeFormats() throws {
        for format in ["mermaid", "dot", "graphml"] {
            let out = try service.graph(focus: "dirty2020", depth: 1, format: format)
            XCTAssertFalse(out.contains(esc), "\(format)：raw ESC 抵達 LLM context")
            XCTAssertFalse(out.contains(rtl), "\(format)：raw U+202E")
            XCTAssertFalse(out.contains(lineSep), "\(format)：U+2028")
        }
    }

    // MARK: - CLI：真 binary、真 stdout

    /// 拔掉 `Commands.swift` stdout 分支的消毒，這條就紅。
    func testCLIStdoutIsSanitisedButFileIsNot() throws {
        try CLIFixture.requireBinary()
        let stdout = CLIFixture.run(
            ["export-bib", "--library", root.path], home: fakeHome).stdout
        XCTAssertFalse(stdout.isEmpty, "沒有輸出代表指令本身失敗了，不是消毒生效")
        XCTAssertFalse(stdout.contains(esc), "stdout 是顯示——raw ESC 進終端")
        XCTAssertFalse(stdout.contains(rtl), "同上")

        // 而 `--output` 寫檔**必須保真**：同一份內容，兩種待遇。
        let file = root.appendingPathComponent("out.bib")
        _ = CLIFixture.run(
            ["export-bib", "--library", root.path, "--output", file.path], home: fakeHome)
        let written = try String(contentsOf: file, encoding: .utf8)
        XCTAssertTrue(written.contains(esc), "檔案是資料——消毒會讓下游 BibTeX 讀到壞內容")
    }

    /// **171-2 的 CLI 側**：`export-bib > refs.bib` 是最常見的用法，而它走 stdout。
    func testCLIStdoutBibRemainsValidLaTeX() throws {
        try CLIFixture.requireBinary()
        let stdout = CLIFixture.run(
            ["export-bib", "--library", root.path, "--citekeys", "latex2020"],
            home: fakeHome).stdout
        XCTAssertTrue(stdout.contains(#"\textit{word}"#),
                      "shell redirect／pipe 走的都是 stdout，消毒不得破壞語法：\(stdout)")
        XCTAssertTrue(stdout.contains(#"\LaTeX{}"#), "同上")
    }
}
