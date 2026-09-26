import XCTest
@testable import AkashicCore

/// #394：識別碼的 value type。
///
/// **用真實值測，不發明值。** 每個合法案例都是 store 內或公開可查的真識別碼，
/// check digit 已手算核對過——發明的值會讓「我的算法錯了」與「這個值本來就非法」
/// 無法區分。
final class IdentifierTests: XCTestCase {

    // MARK: - ISSN

    func testISSNAcceptsRealValues() {
        // American Psychologist（print）／Behavior Research Methods（print 與 electronic）／JPSP
        for v in ["0003-066X", "1554-351X", "1554-3528", "0022-3514"] {
            XCTAssertEqual(ISSN(v)?.normalized, v, "真實 ISSN 應被接受且不變形：\(v)")
        }
    }

    /// store 內實測到的錯值：check digit 的 X 寫成小寫。ISSN 標準規定大寫。
    func testISSNNormalizesLowercaseCheckDigit() {
        XCTAssertEqual(ISSN("0003-066x")?.normalized, "0003-066X",
                       "小寫 x 是錯的寫法，寫入面要正規化成大寫")
    }

    func testISSNAcceptsSpacingVariants() {
        XCTAssertEqual(ISSN("0003 066X")?.normalized, "0003-066X")
        XCTAssertEqual(ISSN("0003066X")?.normalized, "0003-066X")
    }

    /// store 內實測到的另一種錯值：一個欄位塞兩個號。
    func testISSNRejectsTwoInOneField() {
        XCTAssertNil(ISSN("1467-8624(Electronic),0009-3920(Print)"),
                     "一欄兩號必須拒絕——正規化成單一值會靜默丟掉其中一個")
    }

    func testISSNRejectsWrongShapeAndBadCheckDigit() {
        XCTAssertNil(ISSN("12345"), "長度不對")
        XCTAssertNil(ISSN("0003-0660"), "check digit 錯（正解是 X）")
        XCTAssertNil(ISSN(""), "空字串")
    }

    /// #589：非 ASCII 數字寫成的號必須拒絕。`CharacterSet.alphanumerics` 與 `wholeNumberValue` 都認 Unicode 數字，
    /// 全形與阿拉伯-印度數字過得了 mod-11、原樣成為 normalized——去重比字串、回讀比不出來。
    func testISSNRejectsNonASCIIDigits() {
        XCTAssertNotNil(ISSN("0033-3123"), "前提：ASCII 版是合法的號（Psychometrika）")
        XCTAssertNil(ISSN("\u{FF10}\u{FF10}\u{FF13}\u{FF13}-\u{FF13}\u{FF11}\u{FF12}\u{FF13}"), "全形數字")
        XCTAssertNil(ISSN("\u{0660}\u{0660}\u{0663}\u{0663}-\u{0663}\u{0661}\u{0662}\u{0663}"), "阿拉伯-印度數字")
        XCTAssertNil(ISSN("0033-312\u{FF13}"), "只混一個全形數字也拒絕")
        XCTAssertNil(ISSN("0033-3123\u{0663}"), "夾帶的非 ASCII 數字不得被濾掉後放行")
        XCTAssertNil(ISSN("0003-066\u{FF38}"), "全形 X 不是 check digit 的 X")
    }

    /// 同一個 `idCompact` 也服務 ISBN 與 ORCID（#589 的同形）。
    func testISBNAndORCIDRejectNonASCIIDigits() {
        XCTAssertNotNil(ISBN("0-12-179060-6"))
        XCTAssertNil(ISBN("\u{FF10}-12-179060-6"))
        XCTAssertNotNil(ORCID("0000-0003-0899-7477"))
        XCTAssertNil(ORCID("0000-0003-0899-747\u{FF17}"))
    }

    /// #589 R1 verify：DOI 的註冊者段同樣只收 ASCII 數字（後綴不受限）。
    func testDOIRegistrantRejectsNonASCIIDigits() {
        XCTAssertNotNil(DOI("10.1037/met0000100"))
        XCTAssertNil(DOI("10.\u{FF11}\u{FF10}\u{FF13}\u{FF17}/met0000100"), "全形")
        XCTAssertNil(DOI("10.\u{0661}\u{0660}\u{0663}\u{0667}/met0000100"), "阿拉伯-印度數字")
        XCTAssertNil(DOI("10.\u{00B9}\u{2070}\u{00B3}\u{2077}/x"), "上標")
        XCTAssertNotNil(DOI("10.1037/\u{00E9}t\u{00E9}"), "後綴可以含 Unicode")
    }

    /// #589 R2 verify：後綴不可含控制、格式、不可見字元——渲染上與真號相同、卻成為另一個 normalized。
    func testDOISuffixRejectsInvisibleAndControlCharacters() {
        for bad in ["10.1037/met\u{200B}0000100", "10.1037/met0000100\u{202E}", "10.1037/abc\u{0007}",
                    "10.1037/abc\u{FEFF}", "10.1037/x\u{0000}y", "10.1037/a\u{E0041}", "10.1037/a\u{00AD}b",
                    "10.1037/met\u{2800}0000100"] {
            XCTAssertNil(DOI(bad), bad.unicodeScalars.map { String(format: "%04X", $0.value) }.joined(separator: " "))
        }
        XCTAssertNotNil(DOI("10.1037/met0000100"))
    }

    // MARK: - DOI

    func testDOIAcceptsAndNormalizes() {
        let d = DOI("10.2188/jea.je20240034")
        XCTAssertEqual(d?.normalized, "10.2188/jea.je20240034")
        // 前綴要剝掉，否則同一個 DOI 在 store 內會有兩種寫法
        XCTAssertEqual(DOI("https://doi.org/10.2188/JEA.JE20240034")?.normalized,
                       "10.2188/jea.je20240034",
                       "URL 前綴要剝、大小寫要收斂——DOI 的比對規則是大小寫不敏感")
        XCTAssertEqual(DOI("doi:10.2188/jea.je20240034")?.normalized, "10.2188/jea.je20240034")
    }

    func testDOIRejectsWrongShape() {
        XCTAssertNil(DOI("2188/jea.je20240034"), "缺 10. 前綴")
        XCTAssertNil(DOI("10.2188"), "缺斜線與後綴")
        XCTAssertNil(DOI("10.2188/"), "後綴為空")
        XCTAssertNil(DOI("10.21/x"), "註冊者不足 4 碼")
    }

    // MARK: - PMID

    func testPMIDAcceptsAndNormalizes() {
        XCTAssertEqual(PMID("39098040")?.normalized, "39098040")
        XCTAssertEqual(PMID("PMID:39098040")?.normalized, "39098040")
        // 前導零不是有意義的——不正規化掉的話同一筆會有兩種寫法
        XCTAssertEqual(PMID("0039098040")?.normalized, "39098040")
    }

    func testPMIDRejectsNonDigits() {
        XCTAssertNil(PMID("39098040x"))
        XCTAssertNil(PMID(""))
        XCTAssertNil(PMID("0"), "PubMed 沒有 0 號")
    }

    // MARK: - ISBN

    func testISBNAcceptsBothForms() {
        // Cohen 1988 統計檢定力分析（store 內實測值，13 碼）
        XCTAssertEqual(ISBN("978-0-12-179060-8")?.normalized, "9780121790608")
        // 同一本書的 10 碼形（check digit 手算核對）
        XCTAssertNotNil(ISBN("0-12-179060-6"), "ISBN-10 也要接受")
    }

    /// **已裁決：換算。**（2026-08-24，取代先前「刻意不換算」的那一版。）
    ///
    /// 這支測試原本斷言 10 碼**不得**被換算，訊息寫著「那是尚未裁決的問題」——它是
    /// 一支刻意的現況斷言，等裁決落下時變紅。裁決落下了，所以它換內容而不是被刪：
    /// 10 碼與 13 碼是同一個識別碼的兩種編碼，收斂它們是**正規化**。
    ///
    /// 保留這段歷史是為了下一個讀者知道這裡曾經是留白，而不是一直都這樣。
    func testISBNConvertsTenToThirteen() {
        XCTAssertEqual(ISBN("0-12-179060-6")?.normalized, "9780121790608",
                       "10 碼換算成 13 碼——與同一本書的 13 碼形收斂到同一個值")
        XCTAssertEqual(ISBN("0-12-179060-6"), ISBN("978-0-12-179060-8"),
                       "同一本書的兩種編碼必須相等，否則去重收不掉異寫法")
    }

    func testISBNRejectsBadCheckDigit() {
        XCTAssertNil(ISBN("978-0-12-179060-9"), "13 碼 check digit 錯")
        XCTAssertNil(ISBN("0-12-179060-0"), "10 碼 check digit 錯")
        XCTAssertNil(ISBN("123"), "長度不對")
    }

    // MARK: - ORCID

    func testORCIDAcceptsRealValues() {
        // 陳君厚／黃彥棕／程毅豪／陳珍信（store 內實測值）
        for v in ["0000-0003-0899-7477", "0000-0001-7657-0040",
                  "0000-0003-4038-9439", "0000-0001-7063-3338"] {
            XCTAssertEqual(ORCID(v)?.normalized, v, "真實 ORCID 應被接受且不變形：\(v)")
        }
    }

    func testORCIDNormalizesURLAndSpacing() {
        XCTAssertEqual(ORCID("https://orcid.org/0000-0003-0899-7477")?.normalized,
                       "0000-0003-0899-7477")
        XCTAssertEqual(ORCID("0000000308997477")?.normalized, "0000-0003-0899-7477",
                       "無連字號形也要接受並補回")
    }

    func testORCIDRejectsBadCheckDigit() {
        XCTAssertNil(ORCID("0000-0003-0899-7478"), "末位改一碼即非法")
        XCTAssertNil(ORCID("0000-0003-0899-747"), "長度不對")
    }

    // MARK: - ROR

    func testRORAcceptsRealValue() {
        // 中央研究院的 ROR（公開可查；MOD 97-10 手算核對過）
        XCTAssertEqual(ROR("05bqach95")?.normalized, "05bqach95")
        XCTAssertEqual(ROR("https://ror.org/05bqach95")?.normalized, "05bqach95")
        XCTAssertEqual(ROR("05BQACH95")?.normalized, "05bqach95", "大小寫要收斂")
    }

    func testRORRejectsBadCheckDigitAndShape() {
        XCTAssertNil(ROR("05bqach96"), "check digit 錯")
        XCTAssertNil(ROR("15bqach95"), "ROR 一律以 0 開頭")
        XCTAssertNil(ROR("05bqach9"), "長度不對")
        XCTAssertNil(ROR("05iqach95"), "i 不在 Crockford base32 字母表內")
    }

    // MARK: - 共通契約

    /// 每種識別碼都要說得出自己的預期形狀——錯誤訊息要具名，不是「格式錯誤」。
    func testEveryKindDescribesItsShape() {
        XCTAssertFalse(ISSN.shapeDescription.isEmpty)
        XCTAssertFalse(DOI.shapeDescription.isEmpty)
        XCTAssertFalse(PMID.shapeDescription.isEmpty)
        XCTAssertFalse(ISBN.shapeDescription.isEmpty)
        XCTAssertFalse(ORCID.shapeDescription.isEmpty)
        XCTAssertFalse(ROR.shapeDescription.isEmpty)
    }

    /// 正規化是冪等的——把正規形再餵一次要得到同一個值。
    ///
    /// 這條在本 repo 特別要釘：`displaySafe` 就是**不**冪等的（它逃脫反斜線自身），
    /// 而那個不冪等踩過坑。識別碼的正規化不得有同樣的性質。
    func testNormalizationIsIdempotent() {
        func twice<T: Identifier>(_ raw: String, _ make: (String) -> T?) -> String? {
            guard let once = make(raw) else { return nil }
            return make(once.normalized)?.normalized
        }
        XCTAssertEqual(twice("0003-066x", ISSN.init), "0003-066X")
        XCTAssertEqual(twice("10.2188/JEA.JE20240034", DOI.init), "10.2188/jea.je20240034")
        XCTAssertEqual(twice("0000000308997477", ORCID.init), "0000-0003-0899-7477")
        XCTAssertEqual(twice("05BQACH95", ROR.init), "05bqach95")
        XCTAssertEqual(twice("0039098040", PMID.init), "39098040")
        XCTAssertEqual(twice("978-0-12-179060-8", ISBN.init), "9780121790608")
    }

    // MARK: - raw 保留（#394，讀取面原樣保留的前提）

    /// 識別碼**同時**持有原樣字串與正規形。
    ///
    /// **為什麼型別要留 raw**：decode 當下若把值改寫成正規形，記憶體值就與磁碟不一致，
    /// 而 provenance reference 的 `value` 必須落在該欄位的**現值**清單內——於是既有
    /// reference 變孤兒、整筆記錄拒讀。Task 1.1 探針實測過這個 quarantine
    /// （`people: 1` → `people: 0`、`quarantined: 1`）。
    ///
    /// 語意分工（task 4.1 的驗證目標逐字如此）：**讀取→raw、寫入→normalized**。
    func testRawIsPreservedAlongsideTheNormalForm() {
        let issn = ISSN("0003-066x")
        XCTAssertEqual(issn?.raw, "0003-066x", "原樣字串必須留著——它是磁碟上的那個")
        XCTAssertEqual(issn?.normalized, "0003-066X", "正規形照樣算得出來")
    }

    func testRawIsPreservedForEveryKind() {
        XCTAssertEqual(DOI("https://doi.org/10.1037/MET0000524")?.raw,
                       "https://doi.org/10.1037/MET0000524")
        XCTAssertEqual(ISBN("978-0-12-179060-8")?.raw, "978-0-12-179060-8")
        XCTAssertEqual(PMID("0039098040")?.raw, "0039098040")
        XCTAssertEqual(ORCID("0000000308997477")?.raw, "0000000308997477")
        XCTAssertEqual(ROR("05BQACH95")?.raw, "05BQACH95")
    }

    /// **相等由正規形決定，不由 raw**——否則 `0003-066x` 與 `0003-066X` 會被當成
    /// 兩個不同的 ISSN，而 task 8.2 的去重（「先正規化再去重，去重後仍 >1 者才是
    /// 真多號」）就永遠去不掉重複。
    ///
    /// 這條也擋一個具體的退化：Swift 對多欄位 struct 會**合成**逐欄位的 `==`，
    /// 加了 `raw` 之後若讓合成勝出，相等就悄悄變成「兩個欄位都一樣」。
    func testEqualityIsByNormalFormNotByRaw() {
        XCTAssertEqual(ISSN("0003-066x"), ISSN("0003-066X"),
                       "同一個號的兩種寫法是同一個識別碼")
        XCTAssertEqual(DOI("10.1037/MET0000524"), DOI("10.1037/met0000524"))
        XCTAssertEqual(ISBN("978-0-12-179060-8"), ISBN("9780121790608"),
                       "連字號不是識別碼的一部分")
        XCTAssertNotEqual(ISSN("0003-066X"), ISSN("1935-990X"),
                          "不同的號仍然不相等")
    }

    /// 去重要真的去得掉——這是 task 8.2 的直接前提（8 個 venue 收到多值，其中混了
    /// 「同一個號的異寫法」與「真的兩個號」，前者要合併、後者要保留）。
    func testDeduplicationCollapsesSpellingsButKeepsDistinctNumbers() {
        let spellings = [ISSN("0003-066x"), ISSN("0003-066X")].compactMap { $0 }
        var uniq: [ISSN] = []
        for v in spellings where !uniq.contains(v) { uniq.append(v) }
        XCTAssertEqual(uniq.count, 1, "異寫法要合併成一個")

        let real = [ISSN("1554-351X"), ISSN("1554-3528")].compactMap { $0 }
        var uniq2: [ISSN] = []
        for v in real where !uniq2.contains(v) { uniq2.append(v) }
        XCTAssertEqual(uniq2.count, 2, "print 與 electronic 是兩個真的號，不得合併")
    }

    // MARK: - ISBN-10 → ISBN-13 是正規化，不是基數（2026-08-24 裁決）

    /// ISBN-10 與 ISBN-13 **不是兩個識別碼，是同一個識別碼的兩種編碼**：
    /// ISBN-13 ＝ `978` ＋ ISBN-10 的前 9 碼 ＋ 重算 check digit。
    ///
    /// 把它們當成兩個值（或拆成 `isbn10`／`isbn13` 兩個欄位）等於**把編碼當成身分建模**
    /// ——與 `0003-066x` vs `0003-066X` 是同一個錯誤，只是換個尺度。
    func testISBN10NormalizesToISBN13() throws {
        let ten = try XCTUnwrap(ISBN("0-13-441969-3"))
        XCTAssertEqual(ten.normalized, "9780134419695")
        XCTAssertEqual(ten.raw, "0-13-441969-3", "raw 仍保留磁碟上的寫法")
    }

    /// 因此同一本書的兩種寫法**相等**——去重才收得掉（`Identifier.==` 比正規形）。
    func testTheTwoEncodingsOfOneBookAreEqual() throws {
        XCTAssertEqual(try XCTUnwrap(ISBN("0-13-441969-3")),
                       try XCTUnwrap(ISBN("978-0-13-441969-5")))
    }

    /// **真的兩個產品仍是兩個**：softcover 與 electronic 是不同的號，不得被收斂。
    func testDifferentProductsStayDistinct() throws {
        XCTAssertNotEqual(try XCTUnwrap(ISBN("9783642016882")),
                          try XCTUnwrap(ISBN("9783642016899")))
    }

    /// **只能 10 → 13，不能反向**：`979` 開頭的 ISBN-13 沒有 ISBN-10 對應物，
    /// 所以單向轉換才是全定義的。這一條釘住「不要哪天有人加反向轉換」。
    func testA979PrefixedISBN13IsKeptAsIs() throws {
        let v = try XCTUnwrap(ISBN("9791234567896"))
        XCTAssertEqual(v.normalized, "9791234567896")
    }

    /// ISBN-10 的 `X` check digit 換算後仍正確。
    func testISBN10WithXCheckDigitConverts() throws {
        // 0-8044-2957-X 是常用的 X-check-digit 例子
        let v = try XCTUnwrap(ISBN("0-8044-2957-X"))
        XCTAssertEqual(v.normalized.count, 13)
        XCTAssertTrue(v.normalized.hasPrefix("978"))
    }
}
