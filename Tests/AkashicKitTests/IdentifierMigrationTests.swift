import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #394 §8：`migrate-identifiers`。
final class IdentifierMigrationTests: XCTestCase {

    // MARK: - task 8.2：先正規化再去重，去重後仍 >1 者才是真多號

    /// 實測的三種多值寫法都要切得開。
    func testMultiValueShapesAreSplit() {
        XCTAssertEqual(IdentifierMigration.candidates("0022-3506 1467-6494", field: "issn"),
                       ["0022-3506", "1467-6494"])
        XCTAssertEqual(IdentifierMigration.candidates("0033-3123,1860-0980", field: "issn"),
                       ["0033-3123", "1860-0980"])
        // 括號標註整段丟掉——`(Electronic)` 是人給的註記，不是識別碼的一部分，
        // 而我們沒有欄位可以存它。留著會讓值解析失敗，等於把整筆略過。
        XCTAssertEqual(IdentifierMigration.candidates("1860-0980 (Electronic) 0033-3123 (Linking)", field: "issn"),
                       ["1860-0980", "0033-3123"])
    }

    /// **異寫法合併**：task 8.2 具名的第一個實例。
    /// `0003-066x` 與 `0003-066X 1935-990X` 去重後是兩個相異值，不是三個。
    func testAmericanPsychologistMergesToTwoDistinctValues() {
        let raws = IdentifierMigration.candidates("0003-066x", field: "issn")
            + IdentifierMigration.candidates("0003-066X 1935-990X", field: "issn")
        let (values, bad) = IdentifierMigration.normalizedUnique(raws, ISSN.init)
        XCTAssertTrue(bad.isEmpty, "不該有解析不了的：\(bad)")
        XCTAssertEqual(values.map(\.normalized), ["0003-066X", "1935-990X"],
                       "大小寫異寫法必須收斂成同一個——相等由正規形決定")
    }

    /// **真多號保留**：task 8.2 具名的第二個實例。print 與 electronic 是兩個真的號。
    func testBehaviorResearchMethodsKeepsTwo() {
        let (values, _) = IdentifierMigration.normalizedUnique(
            IdentifierMigration.candidates("1554-351X 1554-3528", field: "issn"), ISSN.init)
        XCTAssertEqual(values.count, 2)
    }

    /// 實測 store 內的 `0033-2909 (Print) 0033-2909`——去重後**只剩一個**。
    /// 這一筆是「合併」與「真多號」在同一個字串裡長得一模一樣的證據：
    /// 不先正規化再去重，它會被當成兩個 ISSN 存進去。
    func testAValueThatLooksMultiButDedupesToOne() {
        let (values, _) = IdentifierMigration.normalizedUnique(
            IdentifierMigration.candidates("0033-2909 (Print) 0033-2909", field: "issn"), ISSN.init)
        XCTAssertEqual(values.map(\.normalized), ["0033-2909"])
    }

    /// 無法解析的 token **不猜、不丟棄**——回報給人。
    ///
    /// `DOI 10.1037/h0077149` 切開後 `DOI` 解析不了、後半是合法 DOI。第一版測試
    /// 斷言「整個解析不了」而自己先紅——切開之後那個 DOI 其實救得回來。
    func testUnparseableTokensAreReportedWhileTheRealOneIsRecovered() {
        let (values, bad) = IdentifierMigration.normalizedUnique(
            IdentifierMigration.candidates("DOI 10.1037/h0077149", field: "doi"), DOI.init)
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

    /// **DOI 的括號絕不能剝**——Elsevier／Wiley 的後綴合法含括號，實測 52 筆。
    /// 第一版對所有種類一律剝括號，把它們切成兩半，乾跑報告裡出現 `00255-9` 這種殘骸
    /// 並被當成「資料解析不了」。
    func testDOIParenthesesAreNotStripped() {
        XCTAssertEqual(
            IdentifierMigration.candidates("10.1016/S0304-4076(98)00255-9", field: "doi"),
            ["10.1016/S0304-4076(98)00255-9"])
        XCTAssertNotNil(DOI("10.1016/S0304-4076(98)00255-9"))
    }

    /// ISSN／ISBN 的括號**要剝**——那是人給的註記。
    func testISSNAnnotationsAreStripped() {
        XCTAssertEqual(
            IdentifierMigration.candidates("1860-0980 (Electronic) 0033-3123 (Linking)",
                                           field: "issn"),
            ["1860-0980", "0033-3123"])
    }
}

/// `IdentifierMigration.run()` 的端到端契約（#394 verify）。
///
/// **這些測試在此之前不存在。** ensemble 指出 `run()` 全樹零覆蓋——而它是那個真的
/// 改寫了 731 個檔的函式；兩支姊妹遷移（`VenueMigration`／`PersonIdentityMigration`）
/// 各有 8 與 10+ 個 `run()` 測試。
///
/// 前兩支釘住的是一個**已被端到端重現過**的資料毀損：work 先寫（`fields.issn` 已刪）、
/// venue 後寫，venue 那格失敗時 ISSN 從兩邊都消失，且工具內不可逆。
final class IdentifierMigrationRunTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-idmig-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        _ = LibraryStore.git(["init", "-q"], in: root)
        _ = LibraryStore.git(["config", "user.email", "t@t"], in: root)
        _ = LibraryStore.git(["config", "user.name", "t"], in: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func commitAll() {
        _ = LibraryStore.git(["add", "-A"], in: root)
        _ = LibraryStore.git(["commit", "-q", "-m", "seed"], in: root)
    }

    /// 帶 `fields.issn` 且 venue 邊已歸戶的一筆 work。
    @discardableResult
    private func seedArticle(_ ck: String, venueKey: String, issn: String) throws -> Entry {
        var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: "T-\(ck)")
        e.venues = [.key(venueKey)]
        e.fields["issn"] = issn
        _ = try store.writeEntry(e)
        return e
    }

    private func issnOnDisk(_ ck: String) throws -> String? {
        try store.load().entries.first { $0.citekey == ck }?.fields["issn"]
    }

    // MARK: 快樂路徑（run() 的基本覆蓋，此前完全沒有）

    func testApplyMovesISSNFromWorkToVenue() throws {
        _ = try store.writeVenue(Venue(key: "j", type: .periodical))
        try seedArticle("a2020", venueKey: "j", issn: "0003-066X")
        commitAll()

        let r = try IdentifierMigration.run(store: store, apply: true)
        XCTAssertTrue(r.blockers.isEmpty, "無阻擋前提：\(r.blockers)")
        XCTAssertNil(try issnOnDisk("a2020"), "work 側的殘留已移除")
        XCTAssertEqual(try store.load().venues.first?.issn.map(\.normalized), ["0003-066X"],
                       "號落在 venue 上")
    }

    // MARK: 毀資料的兩個形狀——ISSN 必須存活

    func testUntrackedVenueBlocksTheWorkInsteadOfDestroyingItsISSN() throws {
        try seedArticle("a2020", venueKey: "j", issn: "0003-066X")
        commitAll()                                   // work 已追蹤
        _ = try store.writeVenue(Venue(key: "j", type: .periodical))   // venue **未** commit

        let r = try IdentifierMigration.run(store: store, apply: true)

        XCTAssertFalse(r.blockers.isEmpty, "未追蹤的 venue 必須被裁決為阻擋前提")
        XCTAssertEqual(try issnOnDisk("a2020"), "0003-066X",
                       "落點寫不進去時，work 側的 ISSN 必須原封不動——"
                       + "刪掉它而 venue 沒收到就是純粹的資料消失")
    }

    func testDanglingVenueKeyBlocksTheWorkInsteadOfDestroyingItsISSN() throws {
        try seedArticle("a2020", venueKey: "ghost", issn: "0003-066X")  // 無此 venue 記錄
        commitAll()

        let r = try IdentifierMigration.run(store: store, apply: true)

        XCTAssertFalse(r.blockers.isEmpty, "懸空的 venue key 必須被裁決為阻擋前提")
        XCTAssertEqual(try issnOnDisk("a2020"), "0003-066X", "ISSN 必須存活")
    }

    // MARK: 丟棄必須可見（lossless-intake 執行細節 3）

    func testStrippedParentheticalAnnotationsAreReported() throws {
        _ = try store.writeVenue(Venue(key: "j", type: .periodical))
        var e = Entry(id: UUID(), citekey: "a2020", type: .periodicalArticle, title: "T")
        e.venues = [.key("j")]
        e.fields["issn"] = "1939-1455(Electronic),0033-2909(Print)"
        _ = try store.writeEntry(e)
        commitAll()

        let r = try IdentifierMigration.run(store: store, apply: false)

        XCTAssertEqual(r.discardedAnnotations.count, 1)
        XCTAssertEqual(r.discardedAnnotations.first?.annotations, ["Electronic", "Print"],
                       "Electronic／Print 是有書目語意的 qualifier——剝掉可以，"
                       + "不報出來不行（lossless-intake 執行細節 3：靜默是最糟的形式）")
        XCTAssertEqual(r.discardedAnnotations.first?.raw,
                       "1939-1455(Electronic),0033-2909(Print)",
                       "原值要在報告裡，否則使用者無從復原")
    }

    /// DOI 的後綴合法含括號——**不得**被當成註記剝掉，也不該回報成丟棄。
    func testDOIParenthesesAreNotTreatedAsAnnotations() {
        let (values, annotations) = IdentifierMigration.candidatesWithAnnotations(
            "10.1016/S0304-4076(98)00255-9", field: "doi")
        XCTAssertEqual(values, ["10.1016/S0304-4076(98)00255-9"])
        XCTAssertTrue(annotations.isEmpty, "DOI 不吸收多值也不剝括號")
    }

    // MARK: 乾跑必須預告 apply 會擋下什麼

    func testDryRunRevealsTheSameBlockersApplyWould() throws {
        try seedArticle("a2020", venueKey: "ghost", issn: "0003-066X")
        commitAll()

        let dry = try IdentifierMigration.run(store: store, apply: false)
        XCTAssertFalse(dry.blockers.isEmpty,
                       "乾跑存在的理由就是讓會毀資料的前提在寫入前現形——"
                       + "先前 trackedness 只在 apply 內查，於是乾跑對此完全沉默")
        XCTAssertEqual(dry.applied, 0, "乾跑零寫入")
        XCTAssertEqual(try issnOnDisk("a2020"), "0003-066X")
    }

    /// 一個未受影響的 work 不該被別人的阻擋前提牽連。
    func testBlockedVenueDoesNotStopUnrelatedWorks() throws {
        _ = try store.writeVenue(Venue(key: "ok", type: .periodical))
        try seedArticle("good2020", venueKey: "ok", issn: "0003-066X")
        try seedArticle("bad2020", venueKey: "ghost", issn: "1082-989X")
        commitAll()

        let r = try IdentifierMigration.run(store: store, apply: true)
        XCTAssertNil(try issnOnDisk("good2020"), "未受影響的那筆照常遷移")
        XCTAssertEqual(try issnOnDisk("bad2020"), "1082-989X", "受阻的那筆原封不動")
    }
}
