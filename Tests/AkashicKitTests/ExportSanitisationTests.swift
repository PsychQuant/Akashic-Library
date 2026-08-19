import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicExport

/// #165：匯出面的消毒**只在顯示邊界**，不在序列化層。
///
/// ## 為什麼這條測試存在
///
/// `akashic export-bib`（預設印 stdout）與 MCP `akashic_export`（.bib 全文當 tool
/// result 回 LLM）先前**未消毒**。守衛的 opt-out 曾寫著「跳脫由 biblatex 層負責」
/// ——那句話**字面成立、實質全假**：biblatex 跳脫的是 TeX specials（`{}` `\` `%`
/// `&`），與 C0／bidi／LS-PS 是**兩組不相干的字元集**。
///
/// verify 席的行為探針（本檔把它固定下來）實測：raw ESC 與 U+202E **原樣通過**。
///
/// ## 為什麼守衛抓不到它
///
/// `BibExport.serialize` 不是 `DisplaySinkCoverageTests` 認得的 sink 形狀。這個 leak
/// 是**行為探針**發現的，不是靜態掃描。所以本檔是行為測試而非再加一條掃描規則——
/// 「守衛全綠 ≠ 這一面安全」的又一個實例（#164）。
///
/// ## 判準：檔案是資料，stdout／tool result 是顯示
///
/// 同一份內容兩種待遇——寫檔**必須保真**（消毒會讓下游 BibTeX 引擎讀到壞資料），
/// 顯示**必須消毒**。
///
/// **本檔只管序列化層那一半。** 輸出邊界那一半在 `ExportBoundaryTests`，而且它
/// **必須走真的呼叫點**：本檔原本也含輸出邊界的測試，但它們呼叫的是測試自己
/// 手動組裝的 `displaySafeMultiline(...)`，從未經過被修的那兩行——席位 mutation
/// 證明把整條修法還原後 1014 條全綠（#171 verify 171-1）。「測到了那個函式」不
/// 等於「測到了那條路徑」。
final class ExportSanitisationTests: XCTestCase {

    /// 三種各自不同的威脅：ANSI escape injection、RTL override、行結構注入。
    private let esc = "\u{1B}"
    private let rtl = "\u{202E}"
    private let lineSep = "\u{2028}"

    private func dirtyEntry() -> Entry {
        let dirty = "Evil\(esc)[31m\(rtl)gnihsahp\(lineSep)line2"
        var e = Entry(id: UUID(), citekey: "dirty2020", type: .periodicalArticle, title: dirty)
        e.authors = [.literal(dirty)]
        e.fields = ["journaltitle": dirty]
        e.date = "2020"
        return e
    }

    // MARK: - 序列化層：原樣通過（這是**刻意**的，不是缺陷）

    /// `BibExport` 保真——寫檔路徑依賴這件事。
    ///
    /// 若哪天有人「順手」在這裡加消毒，這條會紅並指出：那會破壞 `--output <file>`
    /// 的正確性。消毒屬輸出邊界。
    func testBibSerialisationPreservesRawBytes() {
        let bib = BibExport.bibFile(entries: [dirtyEntry()], people: [])
        XCTAssertTrue(bib.contains(esc), "序列化層必須保真——寫檔要的是原始位元組")
        XCTAssertTrue(bib.contains(rtl), "同上")
    }

    /// biblatex 跳脫的是 TeX specials，**不是** C0／bidi——這是「跳脫由 biblatex
    /// 層負責」那句話為假的機械證明。
    func testBiblatexEscapesTexSpecialsNotControlCharacters() {
        var e = Entry(id: UUID(), citekey: "tex2020", type: .periodicalArticle,
                      title: "100% \(esc)[31m of \\{braces\\}")
        e.date = "2020"
        let bib = BibExport.bibFile(entries: [e], people: [])
        // **`BibWriter.serialize` 做零跳脫**——它只是 `"{\(value)}"` 包大括號，
        // `%` 原樣留在輸出裡（#171 verify 171-6）。原本這裡斷言 `!contains("\n100%")`
        // 並附註「TeX special 的處理是 biblatex 的職責」：那句話是**假的**，而斷言
        // 恆真——欄位行永遠長成 `  TITLE = {…`（兩空白縮排），`\n100%` 在結構上
        // 不可能出現。席位兩個方向的 mutation 都證實它不敏感（讓 BibWriter 真的把
        // `%` 跳脫成 `\%`，斷言**仍然 passed`）。
        //
        // 改成斷言真實的事實：寫檔路徑對 TeX special **保真**（不處理）。
        XCTAssertTrue(bib.contains("100%"),
                      "BibWriter 不跳脫 TeX special——寫檔路徑對此保真，不要以為它安全")
        // 但控制字元原樣在——兩組字元集不相干
        XCTAssertTrue(bib.contains(esc),
                      "ESC 不在 TeX specials 裡，biblatex 不會碰它——這正是那句話為假的地方")
    }

}
