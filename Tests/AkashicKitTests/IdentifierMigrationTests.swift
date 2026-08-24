import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #394 §8：`migrate-identifiers`。
final class IdentifierMigrationTests: XCTestCase {

    // MARK: - task 8.2：先正規化再去重，去重後仍 >1 者才是真多號

    /// 實測的三種多值寫法都要切得開。
    func testMultiValueShapesAreSplit() {
        XCTAssertEqual(IdentifierMigration.candidates("0022-3506 1467-6494"),
                       ["0022-3506", "1467-6494"])
        XCTAssertEqual(IdentifierMigration.candidates("0033-3123,1860-0980"),
                       ["0033-3123", "1860-0980"])
        // 括號標註整段丟掉——`(Electronic)` 是人給的註記，不是識別碼的一部分，
        // 而我們沒有欄位可以存它。留著會讓值解析失敗，等於把整筆略過。
        XCTAssertEqual(IdentifierMigration.candidates("1860-0980 (Electronic) 0033-3123 (Linking)"),
                       ["1860-0980", "0033-3123"])
    }

    /// **異寫法合併**：task 8.2 具名的第一個實例。
    /// `0003-066x` 與 `0003-066X 1935-990X` 去重後是兩個相異值，不是三個。
    func testAmericanPsychologistMergesToTwoDistinctValues() {
        let raws = IdentifierMigration.candidates("0003-066x")
            + IdentifierMigration.candidates("0003-066X 1935-990X")
        let (values, bad) = IdentifierMigration.normalizedUnique(raws, ISSN.init)
        XCTAssertTrue(bad.isEmpty, "不該有解析不了的：\(bad)")
        XCTAssertEqual(values.map(\.normalized), ["0003-066X", "1935-990X"],
                       "大小寫異寫法必須收斂成同一個——相等由正規形決定")
    }

    /// **真多號保留**：task 8.2 具名的第二個實例。print 與 electronic 是兩個真的號。
    func testBehaviorResearchMethodsKeepsTwo() {
        let (values, _) = IdentifierMigration.normalizedUnique(
            IdentifierMigration.candidates("1554-351X 1554-3528"), ISSN.init)
        XCTAssertEqual(values.count, 2)
    }

    /// 實測 store 內的 `0033-2909 (Print) 0033-2909`——去重後**只剩一個**。
    /// 這一筆是「合併」與「真多號」在同一個字串裡長得一模一樣的證據：
    /// 不先正規化再去重，它會被當成兩個 ISSN 存進去。
    func testAValueThatLooksMultiButDedupesToOne() {
        let (values, _) = IdentifierMigration.normalizedUnique(
            IdentifierMigration.candidates("0033-2909 (Print) 0033-2909"), ISSN.init)
        XCTAssertEqual(values.map(\.normalized), ["0033-2909"])
    }

    /// 無法解析的 token **不猜、不丟棄**——回報給人。
    ///
    /// `DOI 10.1037/h0077149` 切開後 `DOI` 解析不了、後半是合法 DOI。第一版測試
    /// 斷言「整個解析不了」而自己先紅——切開之後那個 DOI 其實救得回來。
    func testUnparseableTokensAreReportedWhileTheRealOneIsRecovered() {
        let (values, bad) = IdentifierMigration.normalizedUnique(
            IdentifierMigration.candidates("DOI 10.1037/h0077149"), DOI.init)
        XCTAssertEqual(values.map(\.normalized), ["10.1037/h0077149"],
                       "切得開就救得回來——前綴雜訊不該讓整筆被略過")
        XCTAssertEqual(bad, ["DOI"], "解析不了的 token 必須出現在報告裡：\(bad)")
    }

    // MARK: - 多值的處置**按種類不同**，而這是量出來的

    /// ISBN 的多值是真的：`978-0-13-441969-5` 與 `0-13-441969-3` 是同一本書的
    /// ISBN-13 與 ISBN-10；精裝與電子版也是兩個真的號。實測 5 筆全屬此類 → 吸收。
    func testISBNMultipleValuesAreAbsorbed() {
        XCTAssertTrue(IdentifierMigration.absorbsMultipleValues(field: "isbn"))
        XCTAssertTrue(IdentifierMigration.absorbsMultipleValues(field: "issn"))
    }

    /// DOI／PMID **不吸收**多值。
    ///
    /// 實測唯一一筆多 DOI 是 `yeager2020what` 的 `10.1037/amp0000794` ＋
    /// `10.1037/amp0000794.supp (Supplemental)`——**附錄的 DOI，不是這篇的第二個**。
    /// 吸收它等於讓這筆記錄宣稱自己是另一個物件，而識別碼終結指涉
    /// （`identity-is-judged-not-matched`）：那是一句假的身分宣稱。
    ///
    /// **spec 給 DOI 是清單的證據不支持吸收**：它寫「37 組 work 記錄同題同年而 DOI
    /// 不同」——那是**跨記錄**的重複，不是一筆記錄需要兩個 DOI。型別仍是清單（真的
    /// 多 DOI 存在），但遷移不從一個自由字串裡**發明**多值。
    func testDOIAndPMIDDoNotAbsorbMultipleValues() {
        XCTAssertFalse(IdentifierMigration.absorbsMultipleValues(field: "doi"))
        XCTAssertFalse(IdentifierMigration.absorbsMultipleValues(field: "pmid"))
    }
}
