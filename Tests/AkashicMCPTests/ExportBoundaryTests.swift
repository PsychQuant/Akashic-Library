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
        var e = Entry(id: UUID(), citekey: "dirty2020", type: .periodicalArticle, title: dirty)
        e.authors = [.literal(dirty)]
        e.fields = ["journaltitle": dirty]
        e.date = "2020"
        return e
    }

    /// **正常的書目內容**，不是攻擊面——Zotero 匯入的書目帶 LaTeX 跳脫是常態。
    private func latexEntry() -> Entry {
        var e = Entry(id: UUID(), citekey: "latex2020", type: .periodicalArticle,
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
        var e = Entry(id: UUID(), citekey: "long2020", type: .periodicalArticle, title: "Long")
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
            var e = Entry(id: UUID(), citekey: "huge\(i)y2020", type: .periodicalArticle, title: "Huge \(i)")
            e.fields = ["abstract": chunk]
            e.date = "2020"
            try store.writeEntry(e)
        }
        XCTAssertThrowsError(try service.export(citekeys: nil, format: "bib")) { err in
            let msg = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(msg.contains("--output"), "拒絕時要指路，否則使用者卡住：\(msg)")
        }
    }

    /// **上限必須量消毒之後**（#171 複驗 b′）——`documentSafe` 是 6 倍膨脹器。
    ///
    /// 這條與上一條的差別**只在內容的性質**：上一條是良性的 `A`（消毒後長度不變），
    /// 這一條是全 ESC（實測 1 MB → 6 MB）。原始 2 MB 遠低於 8 MB 上限、消毒後 12 MB
    /// 遠超過——量錯地方的話最壞情況真正進 LLM context 的是 48 MB 而不是 8 MB。
    ///
    /// **良性內容量不出這個差別**，所以上一條不會紅、這一條會。對抗性輸入的上限
    /// 要用對抗性輸入測。
    func testOversizeIsMeasuredAfterSanitisationNotBefore() throws {
        var e = Entry(id: UUID(), citekey: "expand2020", type: .periodicalArticle, title: "Expand")
        e.fields = ["abstract": String(repeating: esc, count: 2_000_000)]
        e.date = "2020"
        try LibraryStore(root: root).writeEntry(e)
        XCTAssertThrowsError(try service.export(citekeys: ["expand2020"], format: "bib")) { err in
            let msg = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(msg.contains("citekeys"),
                          "指路只能指呼叫端真的有的旋鈕——akashic_export 沒有 --library／--tag：\(msg)")
        }
    }

    /// #562：指名的 citekey 查無時，訊息只列前 10 個再附總數——一次送幾千個不存在的
    /// citekey，錯誤訊息不得等比膨脹（它也進 LLM context）。
    func testMissingCitekeyListIsCappedWithTotal() throws {
        let wanted = (0..<25).map { String(format: "nope%02d", $0) }
        XCTAssertThrowsError(try service.export(citekeys: wanted, format: "bib")) { err in
            let msg = "\(err)"
            XCTAssertTrue(msg.contains("nope09"), "前 10 個要列出：\(msg)")
            XCTAssertFalse(msg.contains("nope10"), "第 11 個起不列：\(msg)")
            XCTAssertTrue(msg.contains("共 25 項"), "總數要揭露：\(msg)")
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

    /// **#569 R1 verify（三席同指）**：`documentSafe` 曾是手抄的舊列舉，TAG 字元、ZWSP、SHY 經 `akashic_export`／
    /// `akashic_graph` 原樣進 LLM context。現在它用輸出閘的性質；ZWJ 在文件裡保留（人讀的文件），CSL-JSON 以 JSON 自己的
    /// `\uXXXX` 逃脫、連 ZWJ 一起、無損。
    func testDocumentExitsUseTheOutputGateProperty() throws {
        // 比 scalar，不比 String：Swift 的 `contains` 以 grapheme 為單位，ZWJ 與 TAG 是 extender、併進前一個 cluster，
        // 單獨找永遠找不到——「不含」的斷言會恆真（寫這支測試時實際踩到）
        let tag = "\u{E0041}", zwsp = "\u{200B}", shy = "\u{00AD}", zwj = "\u{200D}"
        func has(_ s: String, _ one: String) -> Bool { s.unicodeScalars.contains(one.unicodeScalars.first!) }
        var e = Entry(id: UUID(), citekey: "tag2020", type: .periodicalArticle,
                      title: "Tag\(tag)Name zw\(zwsp)sp so\(shy)ft ک\(zwj)ی")
        e.date = "2020"
        try LibraryStore(root: root).writeEntry(e)
        let bib = try service.export(citekeys: ["tag2020"], format: "bib")
        for s in [tag, zwsp] { XCTAssertFalse(has(bib, s), "bib：raw \(s.unicodeScalars.first!.value)") }
        XCTAssertTrue(bib.contains("U+E0041"), bib)
        XCTAssertTrue(has(bib, zwj), "文件保留 ZWJ（比照人可讀輸出的裁決）")
        XCTAssertFalse(has(bib, shy), "MCP 的 bib 回到 LLM context，SHY 照人可讀輸出逃脫（R3 verify；檔案出口保留它，見 CLI 那支）")
        let json = try service.export(citekeys: ["tag2020"], format: "csl-json")
        for s in [tag, zwsp, shy, zwj] { XCTAssertFalse(has(json, s), "csl-json：raw \(s.unicodeScalars.first!.value)") }
        let parsed = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.utf8)) as? [[String: Any]])
        XCTAssertEqual(parsed.first?["title"] as? String, e.title, "CSL-JSON 的逃脫是 JSON 自己的語法，解回來逐字相同")
        let graph = try service.graph(focus: "tag2020", depth: 1, format: "mermaid")
        XCTAssertFalse(has(graph, tag), "graph：raw TAG")
    }

    /// **R2／R3 verify**：兩種文件出口、兩個集合。MCP 的 bib 與 graph 回到 LLM context，照人可讀輸出逃脫排版字元（SHY 在那裡是
    /// 隱藏通道）；檔案與終端出口逐位元組保留它們（CLI 那支釘住）。graphml 另逃 noncharacter（XML 1.0 不收 U+FFFF）。
    func testLLMDocumentExitsEscapeTypographyAndGraphMLStaysValidXML() throws {
        let content = "Exact coverage of\u{00A0}confidence intervals\u{3000}試驗 em\u{00AD}pirical n\u{2009}=\u{2009}234 造\u{E000}字"
        var e = Entry(id: UUID(), citekey: "typo2020", type: .periodicalArticle, title: content)
        e.date = "2020"
        try LibraryStore(root: root).writeEntry(e)
        let bib = try service.export(citekeys: ["typo2020"], format: "bib")
        XCTAssertTrue(bib.contains("U+00AD") && bib.contains("U+00A0") && bib.contains("U+E000"), "LLM 出口照人可讀輸出逃脫：\(bib)")
        let mermaid = try service.graph(focus: "typo2020", depth: 1, format: "mermaid")
        XCTAssertTrue(mermaid.contains("U+00A0"), mermaid)   // label 截在前 30 字左右，SHY 在截斷點之後

        var bad = Entry(id: UUID(), citekey: "nonchar2020", type: .periodicalArticle, title: "Title\u{FFFF}End")
        bad.date = "2020"
        try LibraryStore(root: root).writeEntry(bad)
        let graphml = try service.graph(focus: "nonchar2020", depth: 1, format: "graphml")
        XCTAssertFalse(graphml.unicodeScalars.contains { $0.value == 0xFFFF }, "noncharacter 原樣通過 → 不是合法 XML")
        XCTAssertTrue(XMLParser(data: Data(graphml.utf8)).parse(), graphml)
    }

    /// CLI `export-bib` 的預設 stdout 同一件事（真 binary）。
    func testCLIStdoutKeepsTypographicContent() throws {
        try CLIFixture.requireBinary()
        // NBSP、U+3000、SHY、私用區造字——檔案與終端出口的正當內容（R2／R3 verify）
        let content = "A\u{00A0}B\u{3000}C\u{00AD}D 造\u{E000}字"
        var e = Entry(id: UUID(), citekey: "typo2021", type: .periodicalArticle, title: content)
        e.date = "2021"
        try LibraryStore(root: root).writeEntry(e)
        let stdout = CLIFixture.run(["export-bib", "--library", root.path], home: fakeHome).stdout
        XCTAssertNotNil(stdout.range(of: content, options: .literal), stdout)
        // 變體選擇子照逃（R4 verify：一串 VS17–256 接在 ASCII 後每個字元夾帶一個位元組，CLI stdout 會被 agent 讀進 LLM context）
        var vs = Entry(id: UUID(), citekey: "vs2021", type: .periodicalArticle, title: "Hi\u{E0169}\u{E0167}there \u{845B}\u{E0100}")
        vs.date = "2021"
        try LibraryStore(root: root).writeEntry(vs)
        let out2 = CLIFixture.run(["export-bib", "--library", root.path], home: fakeHome).stdout
        XCTAssertFalse(out2.unicodeScalars.contains { (0xE0100...0xE01EF).contains($0.value) }, out2)
        XCTAssertTrue(out2.contains("U+E0169"), out2)
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
