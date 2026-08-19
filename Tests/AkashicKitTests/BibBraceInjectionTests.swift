import XCTest
@testable import AkashicCore
@testable import AkashicExport
import BiblatexAPA

/// #176：一個欄位值可以在匯出的 `.bib` 裡開出一整筆不存在的 entry。
///
/// 欄位值寫成 `{value}`。值裡有不平衡的 `}` 就提早關掉欄位，之後的內容被當成
/// bibtex 語法解析。下游（LaTeX build、文獻管理器、讀這份輸出的 LLM）分不出
/// 偽造的那筆與真的有什麼不同。
///
/// ## 判準是「輸出永遠平衡」，不是「有沒有加 backslash」
///
/// 第一版的修法輸出 `\{` / `\}`。用真的 `biber --tool` 量過，那**不成立**：
/// btparse（biber 背後的 parser，BibTeX 本尊亦然）數大括號時**完全不看
/// backslash**，`\}` 照樣關掉欄位。同一個 payload：
///
/// | 輸出成 | biber |
/// |---|---|
/// | 未處理 | 2 筆 entry，偽造的與真的無從分辨 |
/// | `\}` | **syntax error**，整檔零輸出／整筆被 skip |
/// | `\textbraceright{}` | 1 筆 entry，payload 留成文字，0 error |
///
/// 所以下面的主判準是**結構性質**（輸出自身平衡），不是比對某個逃脫拼法——
/// 那對任何做括號計數的 parser 都成立，比逐一實測每個消費端更強。
///
/// 這些測試**不呼叫 biber**（CI 不保證有 TeX）。biber 的量測是決定判準用的，
/// 判準本身在這裡用純函式釘住。
final class BibBraceInjectionTests: XCTestCase {

    /// 通報的 payload：一個 title 開出 `forged2099`。
    private static let payload = "ok},\n}\n@ARTICLE{forged2099,\n  TITLE = {I am fake"

    private func entry(title: String = "t",
                       fields: [String: String] = [:],
                       authors: [AkashicCore.Author] = []) -> Entry {
        var e = Entry(id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-0000000001A1")!,
                      citekey: "genuine2025", type: .periodicalArticle,
                      title: title, authors: authors, date: "2025")
        e.fields = fields
        return e
    }

    /// 一行 `.bib` 文字裡的大括號是否良好巢狀。btparse 就是這樣數的——**不看
    /// backslash**，所以這個 helper 也不看。
    private func isBalanced(_ s: String) -> Bool {
        var depth = 0
        for ch in s {
            if ch == "{" { depth += 1 }
            if ch == "}" { depth -= 1; if depth < 0 { return false } }
        }
        return depth == 0
    }

    // MARK: - 主判準

    func testHostileTitleCannotFabricateAnEntry() {
        let bib = BibExport.bibFile(entries: [entry(title: Self.payload)], people: [])
        XCTAssertEqual(bib.components(separatedBy: "@ARTICLE{").count - 1, 1,
                       "輸出裡只能有一筆 entry：\n\(bib)")
        XCTAssertFalse(bib.contains("@ARTICLE{forged2099"), "值不得開出新 entry")
        XCTAssertTrue(bib.contains("forged2099"), "逃脫不是刪除——內容要留著")
        XCTAssertTrue(isBalanced(bib), "整份輸出必須平衡：\n\(bib)")
    }

    /// 每一個值都要過，不只 title。`fields` 是**使用者／匯入端**寫進去的自由欄位，
    /// 而 `bibEntry` 把它們原樣攤平成 biblatex 欄位。
    func testEveryFieldValueIsGuarded() {
        for field in ["journaltitle", "note", "abstract", "pages"] {
            let bib = BibExport.bibFile(
                entries: [entry(fields: [field: Self.payload])], people: [])
            XCTAssertEqual(bib.components(separatedBy: "@ARTICLE{").count - 1, 1,
                           "\(field) 沒被守住：\n\(bib)")
            XCTAssertTrue(isBalanced(bib), "\(field) 的輸出不平衡")
        }
    }

    /// 作者名同樣是 store 內容（`.literal` 是尚未歸戶的原字串）。
    func testHostileAuthorLiteralIsGuarded() {
        let bib = BibExport.bibFile(
            entries: [entry(authors: [.literal(Self.payload)])], people: [])
        XCTAssertEqual(bib.components(separatedBy: "@ARTICLE{").count - 1, 1)
        XCTAssertTrue(isBalanced(bib))
    }

    /// **逐個作者逃脫，不是 join 之後。** 一個壞名字不該把同一筆裡其他機構名的
    /// `{...}` 標記一起拖進逃脫——那會改掉合法記錄的排版輸出。
    func testOneBadAuthorDoesNotEscapeTheOthers() {
        let bib = BibExport.bibFile(
            entries: [entry(authors: [.literal("{World Health Organization}"),
                                      .literal(Self.payload)])],
            people: [])
        XCTAssertTrue(bib.contains("{World Health Organization}"),
                      "機構名的大括號標記必須原樣存活：\n\(bib)")
        XCTAssertTrue(isBalanced(bib))
    }

    // MARK: - 平衡的值必須原樣通過

    /// biblatex 用 `{...}` 保護大小寫、機構名用它標記——都是合法且常見的。
    /// 一律逃脫會改掉每一筆這種記錄的排版輸出。
    func testBalancedBracesSurviveVerbatim() {
        let legit = "{DNA} sequencing of {E. coli}"
        let bib = BibExport.bibFile(entries: [entry(title: legit)], people: [])
        XCTAssertTrue(bib.contains("TITLE = {\(legit)},"), "保護大小寫被動到了：\n\(bib)")
        XCTAssertFalse(bib.contains("textbraceleft"), "這裡沒有東西該被逃脫")
    }

    func testNestedBalancedBracesSurviveVerbatim() {
        let legit = "a {b {c} d} e"
        XCTAssertTrue(BibExport.bibFile(entries: [entry(title: legit)], people: [])
            .contains("TITLE = {\(legit)},"))
    }

    // MARK: - 判準本身

    /// 逐一釘住 `braceSafe`，含**已經帶 LaTeX 逃脫**的輸入——那是 `.bib` 來回
    /// 轉換會產生的形狀，也是「`\}` 就夠了」這個假設破掉的地方。
    func testBraceSafeOutputIsAlwaysBalanced() {
        let hostile = [
            Self.payload,
            "}{",                                   // 總數相同但不是良好巢狀
            "a {b",                                 // 開了沒關——吞掉後面整份檔案
            #"ok\},\n\}\n@ARTICLE{forged_pre,"#,    // 已帶 `\}`
            #"trailing backslash \"#,
        ]
        for value in hostile {
            let out = BibExport.braceSafe(value)
            XCTAssertTrue(isBalanced(out), "不平衡：\(value.debugDescription) → \(out)")
            XCTAssertFalse(out.contains(#"\\"#),
                           "雙 backslash 會讓下一個大括號活過來：\(out)")
        }
    }

    func testBraceSafeLeavesCleanValuesAlone() {
        XCTAssertEqual(BibExport.braceSafe("plain title"), "plain title")
        XCTAssertEqual(BibExport.braceSafe("{DNA} sequencing"), "{DNA} sequencing")
    }

    // MARK: - 與 writer 那一層的關係

    /// `biblatex-apa-swift` 的 `BibWriter` 也有一份同樣的防護。**兩份不衝突**：
    /// 平衡的值兩邊都原樣通過，所以這裡做完之後那邊是 no-op。
    ///
    /// 留兩份不是重複——不受信任的內容源自 store，邊界的擁有者是這裡；`BibWriter`
    /// 是共用的 canonical library，換一個 writer 或它的規則改了，洞就回來。
    ///
    /// **這裡不斷言 `BibWriter.braceSafe`**：它是那個模組的 internal 符號，而且
    /// 目前只存在於未合併的 branch 上。跨層的合成性質由下面的 round-trip 間接
    /// 涵蓋（真的走完 `BibWriter.serialize` 再解析回來）——斷言一個只在別的
    /// branch 上存在的具名符號，會讓測試在 merge 前後有兩種意思。
    func testGuardIsIdempotent() {
        let once = BibExport.braceSafe(Self.payload)
        XCTAssertEqual(BibExport.braceSafe(once), once, "第二次必須是 no-op")
        XCTAssertTrue(isBalanced(once))
    }

    /// 走完整條路徑再用 parser 讀回來：一筆進、一筆出。
    func testRoundTripThroughParserYieldsExactlyOneEntry() {
        let bib = BibExport.bibFile(entries: [entry(title: Self.payload)], people: [])
        let parsed = BibParser.parse(content: bib)
        XCTAssertEqual(parsed.entries.count, 1, "解析後只能有一筆")
        XCTAssertEqual(parsed.entries.first?.key, "genuine2025")
        XCTAssertNil(parsed.entries.first { $0.key.contains("forged") },
                     "偽造的 key 不得成為 entry")
    }
}
