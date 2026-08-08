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
/// 顯示**必須消毒**。所以測試分兩半：序列化層原樣通過、輸出邊界擋下。
final class ExportSanitisationTests: XCTestCase {

    /// 三種各自不同的威脅：ANSI escape injection、RTL override、行結構注入。
    private let esc = "\u{1B}"
    private let rtl = "\u{202E}"
    private let lineSep = "\u{2028}"

    private func dirtyEntry() -> Entry {
        let dirty = "Evil\(esc)[31m\(rtl)gnihsahp\(lineSep)line2"
        var e = Entry(id: UUID(), citekey: "dirty2020", type: "article", title: dirty)
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
        var e = Entry(id: UUID(), citekey: "tex2020", type: "article",
                      title: "100% \(esc)[31m of \\{braces\\}")
        e.date = "2020"
        let bib = BibExport.bibFile(entries: [e], people: [])
        // TeX special 被處理（至少 `%` 不會裸留成註解起點）
        XCTAssertFalse(bib.contains("\n100%"), "TeX special 的處理是 biblatex 的職責")
        // 但控制字元原樣在——兩組字元集不相干
        XCTAssertTrue(bib.contains(esc),
                      "ESC 不在 TeX specials 裡，biblatex 不會碰它——這正是那句話為假的地方")
    }

    // MARK: - 輸出邊界：擋下

    /// `displaySafeMultiline` 用匯出量級的上限時，仍必須擋住三種字元。
    ///
    /// 這條釘住的是**上限放寬沒有把消毒一起放掉**——`maxTotal: 200_000_000` 是為了
    /// 不截斷全庫匯出，但字元級的跳脫不受上限影響。
    func testDisplayBoundarySanitisesAtExportScale() {
        let bib = BibExport.bibFile(entries: [dirtyEntry()], people: [])
        let shown = displaySafeMultiline(bib, maxLineLength: 4_000,
                                         maxLines: 2_000_000, maxTotal: 200_000_000)
        XCTAssertFalse(shown.contains(esc), "raw ESC 進終端＝ANSI escape injection")
        XCTAssertFalse(shown.contains(rtl), "raw U+202E 進 LLM context＝RTL override")
        XCTAssertFalse(shown.contains(lineSep), "U+2028 是行結構注入面")
        // 但內容仍可讀——消毒不是刪除
        XCTAssertTrue(shown.contains("dirty2020"), "消毒後仍要看得懂是哪一筆")
        XCTAssertTrue(shown.contains("Evil"), "非危險部分原樣保留")
    }

    /// 全庫規模不得被截斷成無效的 .bib——上限放寬的理由本身要被釘住。
    ///
    /// `displaySafeMultiline` 的預設是 200 行／96 KB（為單筆記錄的錯誤訊息設的）。
    /// 匯出用預設會在中途斷掉，產出一個下游解析不了的檔案。
    func testExportScaleLimitsDoNotTruncateWholeLibrary() {
        let entries = (0..<400).map { i -> Entry in
            var e = Entry(id: UUID(), citekey: "e\(i)y2020", type: "article",
                          title: "Title number \(i) with some reasonable length")
            e.date = "2020"
            return e
        }
        let bib = BibExport.bibFile(entries: entries, people: [])
        let defaults = displaySafeMultiline(bib)
        let exportScale = displaySafeMultiline(bib, maxLineLength: 4_000,
                                               maxLines: 2_000_000, maxTotal: 200_000_000)
        XCTAssertTrue(defaults.count < bib.count,
                      "預設上限對 400 筆會截斷——這正是不能用預設的理由")
        XCTAssertEqual(exportScale.count, bib.count,
                       "匯出量級的上限不得截斷（截斷 = 產出無效的 .bib）")
        XCTAssertTrue(exportScale.contains("e399y2020"), "最後一筆要在")
    }
}
