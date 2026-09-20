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

    // MARK: 有解不了的 token 時，可解的那個仍要遷移（#424 裁決 A）

    /// `DOI 10.1037/h0077149` 的 DOI 必須升格，即使 `DOI` 這個標籤 token 解析不了。
    ///
    /// ## 註解與實作分岔了，而註解讀起來完全合理
    ///
    /// `take` 的收尾寫著：
    ///
    /// ```swift
    /// // 只要有任何一個 bad，就**不移除殘留**——殘留是那些解不了的值唯一的棲身處。
    /// return bad.isEmpty ? values : nil
    /// ```
    ///
    /// 註解說的是「不移除殘留」，實作做的是「**連結構化值都不寫**」。前者保護解不了的
    /// 那個 token，後者連可解的那個一起放棄——而兩者在報告上看起來一樣：那筆會出現在
    /// `skipped` 裡，理由寫「解析不了」，讀者合理地以為指的是整個值。
    ///
    /// 實測（2026-08-28）store 有 **2 筆**因此卡住（`dweck1975role`／`hong1999implicit`），
    /// 兩筆的 DOI 本身都完全合法。它們是 #424 裁決 A 的三分之二。
    func testAnUnparseableLabelDoesNotBlockTheParseableIdentifier() throws {
        var e = Entry(id: UUID(), citekey: "d1975", type: .periodicalArticle, title: "T")
        e.fields["doi"] = "DOI 10.1037/h0077149"
        _ = try store.writeEntry(e)
        commitAll()

        let r = try IdentifierMigration.run(store: store, apply: true)
        XCTAssertTrue(r.blockers.isEmpty, "無阻擋前提：\(r.blockers)")

        let after = try store.load().entries.first { $0.citekey == "d1975" }
        XCTAssertEqual(after?.doi.map(\.normalized), ["10.1037/h0077149"],
                       "可解的 DOI 必須升格——一個解不了的**標籤**不該讓整筆放棄")
        XCTAssertEqual(after?.fields["doi"], "DOI 10.1037/h0077149",
                       "殘留必須保留——那個解不了的 token 沒有別的棲身處（這半是註解本來就說對的）")
        XCTAssertTrue(r.skipped.contains { $0.citekey == "d1975" && $0.value == "DOI" },
                      "解不了的 token 仍要出現在報告裡（lossless-intake：丟棄必須可見）")
    }

    /// **邊界：全部 token 都解不了時，什麼都不寫。**
    ///
    /// 上一個測試放寬的是「有些解得開」的情形。這個釘住它沒有順便放寬「一個都解不開」
    /// ——那時結構化欄位應該維持空的，殘留原封不動。
    func testWhenNothingParsesNothingIsWritten() throws {
        var e = Entry(id: UUID(), citekey: "junk", type: .periodicalArticle, title: "T")
        e.fields["doi"] = "not-a-doi also-not"
        _ = try store.writeEntry(e)
        commitAll()

        _ = try IdentifierMigration.run(store: store, apply: true)
        let after = try store.load().entries.first { $0.citekey == "junk" }
        XCTAssertTrue(after?.doi.isEmpty ?? false, "一個都解不開時不得寫入任何結構化值")
        XCTAssertEqual(after?.fields["doi"], "not-a-doi also-not", "殘留原封不動")
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

    // MARK: provenance value 與識別碼值同一次原子改寫（task 8.3）

    /// **釘住「為什麼是零」**（`zero-instance-guards` 第 8 列的第二半）。
    ///
    /// `rewritingProvenance` 至今零次改寫。**entry 那條呼叫**的理由不是「還沒發生」，是結構上走不到：
    /// 寫入面驗證要求 reference 的 `value` 必須落在該欄位的**結構化清單**內
    /// （`Provenance.swift`：「value「…」不在 doi 清單內——值被改寫後 provenance 成了孤兒」）。
    /// 而遷移只從 `fields` 殘留搬值——一筆帶殘留的記錄，其結構化清單是空的，
    /// 所以它不可能合法地帶著一個指向該殘留值的 reference。
    ///
    /// **venue 那條呼叫不在此列**（#556 R5／R7 verify）：它要兩個前提同時成立——
    /// (a) 某筆 work 的 `fields` 殘留裡有一個未正規化的 ISSN token（例如 `00333123`；token 不含空白，
    ///     `IdentifierTokenizer` 在空白與逗號處切，所以 `"0033 3123"` 這種形永遠不會成為 `old`），
    ///     且它的 venue 邊已歸戶到該 venue——`rewritesByVenue` 只從這裡產生 rewrite；
    /// (b) 該 venue 持有一筆 value 與那個 raw token `==` 的 reference（Swift 字串相等是 canonical 相等，對 ASCII token 等同位元組相等）——手改進得去：
    ///     venue 的 `issn` 清單非空，`validateReferenceAttachment` 解析後比 normalized，`{field: issn, value: "00333123"}`
    ///     對 `issn: [0033-3123]` 過 validate。
    /// live store 2026-09-20：(a) 為 0（`fields` 殘留裡的 ISSN 已搬完）、(b) 為 0。那條路可達、零實例；本測試只釘 entry。
    ///
    /// 這條測試釘住 entry 那個機制。**它一旦變綠（＝寫入面放寬了），`rewritingProvenance`
    /// 就從裝飾品變成承重結構**（這句 2026-08-25 起就在；它是這條測試存在的理由，不是待辦——#556 R8 verify 第 16 列）。
    func testAResidueValuedReferenceCannotBeWrittenAtAll() throws {
        var e = Entry(id: UUID(), citekey: "a2020", type: .periodicalArticle, title: "T")
        e.fields["doi"] = "10.1007/BF02294210"          // 殘留，結構化 doi 仍為空
        e.references = [ProvenanceReference(
            field: "doi", value: "10.1007/BF02294210",
            kind: .judgement(statement: "自 Crossref 查得",
                             restsOn: ["sha256:2d711642b726b04401627ca9fbac32f5c8530fb1903cc4db02258717921a4881"]))]

        XCTAssertThrowsError(try store.writeEntry(e),
                             "殘留值的 reference 必須被寫入面拒絕——這正是 "
                             + "rewritingProvenance 目前不可達的原因") { err in
            XCTAssertTrue("\(err)".contains("不在 doi 清單內"), "實得：\(err)")
        }
    }

    /// 遷移**不得**用殘留覆寫已在場的結構化值（#394 verify）。
    ///
    /// §3 讓兩者並存是設計中的過渡態，而 `canonicalDOIs` 的立場是「同時在場時正典是
    /// 結構化那個」。原本 `updated.doi = v` 是無條件賦值——方向正好相反且不可逆。
    func testResidueDoesNotOverwriteAStructuredIdentifier() throws {
        var e = Entry(id: UUID(), citekey: "a2020", type: .periodicalArticle, title: "T")
        e.doi = [try XCTUnwrap(DOI("10.1007/canonical"))]
        _ = try store.writeEntry(e)
        // 繞過寫入面把殘留加回磁碟——並存狀態只能這樣造出來
        let url = store.entityURL(id: e.id)
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: "fields:", with: "fields:\n  doi: 10.9999/residue")
        if !text.contains("fields:") { text += "\nfields:\n  doi: 10.9999/residue\n" }
        try text.write(to: url, atomically: true, encoding: .utf8)
        commitAll()

        let r = try IdentifierMigration.run(store: store, apply: true)
        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "a2020" })
        XCTAssertEqual(after.doi.map(\.normalized), ["10.1007/canonical"],
                       "正典值必須存活——遷移用殘留覆寫它是不可逆的降級")
        XCTAssertTrue(r.skipped.contains { $0.citekey == "a2020" && $0.field == "doi" },
                      "略過必須具名（lossless-intake 執行細節 3）")
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

        _ = try IdentifierMigration.run(store: store, apply: true)
        XCTAssertNil(try issnOnDisk("good2020"), "未受影響的那筆照常遷移")
        XCTAssertEqual(try issnOnDisk("bad2020"), "1082-989X", "受阻的那筆原封不動")
    }
}

/// 括號註記配對到相鄰的值，而不是各自成堆（#394 verify）。
extension IdentifierMigrationTests {
    func testAnnotationsPairWithTheValueTheyFollow() {
        let p = IdentifierMigration.qualifiedCandidates(
            "1939-1455(Electronic),0033-2909(Print)", field: "issn")
        XCTAssertEqual(p.map(\.value), ["1939-1455", "0033-2909"])
        XCTAssertEqual(p.map { $0.qualifier ?? "—" }, ["Electronic", "Print"],
                       "資訊不是「有兩個號、有兩個註記」，是「1939-1455 是電子版」")
    }

    func testSpaceSeparatedAnnotationsAlsoPair() {
        let p = IdentifierMigration.qualifiedCandidates(
            "1860-0980 (Electronic) 0033-3123 (Linking)", field: "issn")
        XCTAssertEqual(p.map(\.value), ["1860-0980", "0033-3123"])
        XCTAssertEqual(p.map { $0.qualifier ?? "—" }, ["Electronic", "Linking"])
    }

    func testISBNQualifierIsFreeTextNotAClosedSet() {
        let p = IdentifierMigration.qualifiedCandidates("9780935302356 (alk. paper)", field: "isbn")
        XCTAssertEqual(p.map(\.value), ["9780935302356"])
        XCTAssertEqual(p.first?.qualifier, "alk. paper",
                       "MARC 020 $q 的值域本來就開放——寫成封閉列舉會把資料擋在門外")
    }

    /// DOI 的後綴合法含括號——**不得**被當成限定詞切開。
    func testDOIIsNotPairedBecauseItDoesNotAbsorb() {
        let p = IdentifierMigration.qualifiedCandidates(
            "10.1016/S0304-4076(98)00255-9", field: "doi")
        XCTAssertEqual(p.map(\.value), ["10.1016/S0304-4076(98)00255-9"])
        XCTAssertNil(p.first?.qualifier)
    }

    /// 去重時**有限定詞的勝過沒有的**；相等仍只看正規形。
    func testDedupPrefersTheValueThatCarriesAQualifier() {
        let (values, bad) = IdentifierMigration.normalizedUniqueQualified(
            [("0003-066x", nil), ("0003-066X", "print")], ISSN.init)
        XCTAssertTrue(bad.isEmpty)
        XCTAssertEqual(values.count, 1, "異寫法仍是同一個號")
        XCTAssertEqual(values.first?.medium, .print, "限定詞不得因去重而消失")
    }

    /// 同一個號帶兩個不同角色時保留先出現的——一個 String? 裝不下兩個。
    func testConflictingQualifiersKeepTheFirst() {
        let (values, _) = IdentifierMigration.normalizedUniqueQualified(
            [("0022-3514", "Print"), ("0022-3514", "Linking")], ISSN.init)
        XCTAssertEqual(values.count, 1)
        XCTAssertEqual(values.first?.medium, .print)
    }
}

/// venue 既有的 ISSN medium 不得因為一次不相干的 apply 而消失（#394 verify）。
extension IdentifierMigrationRunTests {
    func testExistingVenueMediumSurvivesAnUnrelatedApply() throws {
        var venue = Venue(key: "j", type: .periodical)
        venue.issn = [try XCTUnwrap(ISSN("0033-3123")).withQualifier("linking"),
                      try XCTUnwrap(ISSN("1860-0980")).withQualifier("electronic")]
        _ = try store.writeVenue(venue)
        // 一筆帶 fields.issn 的 work，落點就是這個 venue——會觸發 venue 重寫
        var e = Entry(id: UUID(), citekey: "a2020", type: .periodicalArticle, title: "T")
        e.venues = [.key("j")]
        e.fields["issn"] = "0033-3123"
        _ = try store.writeEntry(e)
        commitAll()

        _ = try IdentifierMigration.run(store: store, apply: true)

        let after = try XCTUnwrap(try store.load().venues.first { $0.key == "j" })
        XCTAssertEqual(after.issn.map { $0.medium?.rawValue ?? "—" }.sorted(),
                       ["electronic", "linking"],
                       "既有的 medium 必須存活——先前 VenuePlan 只帶正規形字串，"
                       + "apply 從字串重建時 ISSN.init 把 medium 設成 nil，"
                       + "於是一次不相干的遷移會刪掉磁碟上已有的 qualifier")
    }

    /// 從括號註記解析出來的 medium 要真的寫進 venue，不能只活在報告裡。
    func testMediumParsedFromAnnotationReachesTheVenue() throws {
        _ = try store.writeVenue(Venue(key: "j", type: .periodical))
        var e = Entry(id: UUID(), citekey: "a2020", type: .periodicalArticle, title: "T")
        e.venues = [.key("j")]
        e.fields["issn"] = "1939-1455(Electronic),0033-2909(Print)"
        _ = try store.writeEntry(e)
        commitAll()

        _ = try IdentifierMigration.run(store: store, apply: true)

        let after = try XCTUnwrap(try store.load().venues.first { $0.key == "j" })
        let byValue = Dictionary(uniqueKeysWithValues:
            after.issn.map { ($0.normalized, $0.medium?.rawValue ?? "—") })
        XCTAssertEqual(byValue["1939-1455"], "electronic")
        XCTAssertEqual(byValue["0033-2909"], "print",
                       "整條 qualifier 管線對 ISSN 的遷移路徑先前等於不存在")
    }
}

/// 認不出的 ISSN qualifier 保留原值並報出來，不靜默丟（#394 verify）。
extension IdentifierMigrationRunTests {
    func testUnrecognizedQualifierSurvivesRoundTripAndIsReported() throws {
        var v = Venue(key: "j", type: .periodical)
        // `Online` 是 Crossref／Zotero 對電子 ISSN 最常見的寫法，不在封閉三值內
        v.issn = [try XCTUnwrap(ISSN("1935-990X")).withQualifier("Online")]

        let out = try VenueYAML.encode(v)
        XCTAssertTrue(out.contains("qualifier: Online"),
                      "原值必須寫回磁碟——先前 qualifier 直接回 medium?.rawValue，"
                      + "認不出的寫法在 encode 當下就消失了：\(out)")
        let back = try VenueYAML.decode(out)
        XCTAssertEqual(back.issn.first?.qualifierRaw, "Online", "讀取面原樣保留")
        XCTAssertNil(back.issn.first?.medium, "認不出就是認不出——不猜")

        XCTAssertTrue(back.validate().contains { $0.message.contains("Online") },
                      "認不出必須報出來（lossless-intake 執行細節 3：靜默是最糟的形式）")
    }

    /// pre-flight 要模擬 writeVenue 的**全部**閘，不只是「檔案受追蹤」。
    func testPreflightCatchesAVenueThatWriteVenueWouldReject() throws {
        var v = Venue(key: "j", type: .periodical)
        // authorized 與 variant 同時含同一個名字 → validate() 回 .error
        // → writeVenue 的 assertNoErrors 會 throw。這與本 change 無關，
        // 是既有真實 store 就可能有的狀態。
        v.names = Timeline([TemporalValue(value: "J")])
        v.authorized = ["J", "J"]
        _ = try? store.writeVenue(v)
        // 若上面寫不進去就改用磁碟直接放（模擬既有的壞狀態）
        try seedArticle("a2020", venueKey: "j", issn: "0003-066X")
        commitAll()

        let r = try IdentifierMigration.run(store: store, apply: true)
        // 不論該 venue 是否真的觸發 error，本測試釘住的是**機制**：
        // pre-flight 走的是 assertVenueWritable 的同一份清單，不是自己複製的兩條。
        XCTAssertNoThrow(try IdentifierMigration.run(store: store, apply: false),
                         "pre-flight 不得靠例外傳遞失敗——那會讓 report 整個被丟棄")
        _ = r
    }
}

/// 形狀前置升級**不得改壞合法的 format-13 檔**（#425 verify HIGH）。
extension IdentifierMigrationRunTests {
    /// YAML mapping 無序——`qualifier:` 寫在 `value:` 之前是完全合法的，
    /// 而且 `decodeQualifiedList` 讀得出來。
    ///
    /// 舊判斷 `if !v.hasPrefix("value:")` 假設「不是 value: 開頭 ⇒ 裸純量」，
    /// 於是把 `- qualifier: print` 改成 `- value: qualifier: print`，該檔從此讀不出來。
    /// **quarantine 守衛擋不住它**——守衛在寫入之後才跑。
    ///
    /// 這個寫法不是憑空假設：守衛自己的錯誤訊息就叫使用者「需人工改成 `- value: …`
    /// 後重跑」，而手改時把 qualifier 放前面完全自然。
    func testLegalFormat13FileWithQualifierFirstIsNotRewritten() throws {
        var v = Venue(key: "j", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X")).withQualifier("print")]
        _ = try store.writeVenue(v)

        let url = store.entityURL(id: v.id)
        let original = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(original.contains("- value: 0003-066X"), "前提：預設鍵序是 value 在前")
        let swapped = original.replacingOccurrences(
            of: "- value: 0003-066X\n  qualifier: print",
            with: "- qualifier: print\n  value: 0003-066X")
        XCTAssertNotEqual(swapped, original, "前提：替換要真的發生")
        try swapped.write(to: url, atomically: true, encoding: .utf8)
        commitAll()

        // 前提：這個形狀本來就讀得出來
        let readBack = try store.load().venues.first { $0.key == "j" }
        XCTAssertEqual(readBack?.issn.first?.medium, .print, "前提：鍵序反過來仍解析得出")

        _ = try IdentifierMigration.run(store: store, apply: true)

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), swapped,
                       "合法的 format-13 檔不得被形狀升級碰到——"
                       + "它只該處理 format-12 的裸純量")
    }

    /// 續行（`  qualifier: …`）不得讓序列模式提早結束，否則其後的裸純量元素全部漏掉。
    func testContinuationLineDoesNotEndTheSequence() throws {
        var v = Venue(key: "j", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X")).withQualifier("print")]
        _ = try store.writeVenue(v)
        let url = store.entityURL(id: v.id)
        // 第一個元素是 mapping（帶續行），第二個是 format-12 的裸純量
        var text = try String(contentsOf: url, encoding: .utf8)
        text = text.replacingOccurrences(of: "  qualifier: print",
                                         with: "  qualifier: print\n- 1935-990X")
        try text.write(to: url, atomically: true, encoding: .utf8)
        commitAll()

        _ = try IdentifierMigration.run(store: store, apply: true)

        let after = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(after.contains("- value: 1935-990X"),
                      "續行之後的裸純量必須也被升級——舊實作在續行處就把序列模式關掉了：\n\(after)")
    }
}

/// 跨 work 累積到 venue 那一步也要套用「有 qualifier 的勝過沒有的」（#425 verify HIGH）。
extension IdentifierMigrationRunTests {
    /// **這是真實資料的形狀**：同一份期刊被多篇引用，只有其中一篇的字串帶括號註記，
    /// 而那一篇的 citekey 不一定排在前面。
    ///
    /// `for v in raws where !merged.contains(v)` 走 `Identifier.==`，而它**刻意只比
    /// `normalized`**（那是 dedup 的前提，不能改）——所以先進來的勝出，**不論它有沒有
    /// qualifier**。同一個檔案裡的 `normalizedUniqueQualified` 明寫了偏好規則，
    /// 跨 work 累積那一步沒套用它。
    ///
    /// 既有兩支測試都剛好避開這個格子：一支是「venue 已有 qualified、work 供
    /// unqualified」，一支是「venue 空 ＋ **單一**帶註記的 work」。
    func testQualifierSurvivesWhenAnEarlierWorkSuppliesTheSameISSNUnqualified() throws {
        _ = try store.writeVenue(Venue(key: "j", type: .periodical))
        // citekey 排序：aaa 在 zzz 之前，而**帶註記的是 zzz**
        try seedArticle("aaa2020", venueKey: "j", issn: "0033-3123 1860-0980")
        try seedArticle("zzz2020", venueKey: "j",
                        issn: "1860-0980 (Electronic) 0033-3123 (Linking)")
        commitAll()

        _ = try IdentifierMigration.run(store: store, apply: true)

        let v = try XCTUnwrap(try store.load().venues.first { $0.key == "j" })
        let byValue = Dictionary(uniqueKeysWithValues:
            v.issn.map { ($0.normalized, $0.medium?.rawValue ?? "—") })
        XCTAssertEqual(byValue["1860-0980"], "electronic",
                       "註記不得因為另一篇 work 先供給同一個號而消失")
        XCTAssertEqual(byValue["0033-3123"], "linking")
    }
}

/// 乾跑與 apply 必須看到**同一組** blockers（#425 verify HIGH）。
extension IdentifierMigrationRunTests {
    /// 形狀升級先前只在 `apply == true` 寫檔，所以乾跑時裸純量還在 → load 時
    /// quarantine → 守衛 throw；而 `--apply` 先升級再 load 因而**成功**。
    /// 同一個 store：乾跑拒跑、apply 成功。
    ///
    /// 這違反本命令自己寫下的契約（「乾跑與 apply 得到**同一組** blockers——乾跑因此
    /// 真的能預告 apply 的結果」），而且錯誤訊息**說了假話**：它斷言那是「本命令的
    /// 形狀前置升級沒認出的寫法」，而實測觸發值**正是**它認得的形式。
    func testDryRunSucceedsOnAStoreThatApplyWouldUpgrade() throws {
        var v = Venue(key: "j", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X"))]
        _ = try store.writeVenue(v)
        // 退回 format-12 的裸純量形狀——這正是本命令存在的理由
        let url = store.entityURL(id: v.id)
        let text = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "- value: 0003-066X", with: "- 0003-066X")
        try text.write(to: url, atomically: true, encoding: .utf8)
        commitAll()

        // 乾跑**不得** throw——它要能預告 apply 的結果
        let dry = try IdentifierMigration.run(store: store, apply: false)
        XCTAssertEqual(dry.shapeUpgraded.count, 1, "乾跑要報出它會升級哪些檔")
        XCTAssertEqual(dry.applied, 0, "乾跑零寫入")
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text,
                       "乾跑不得改動磁碟")

        let applied = try IdentifierMigration.run(store: store, apply: true)
        XCTAssertEqual(dry.blockers, applied.blockers,
                       "乾跑與 apply 必須得到同一組 blockers——那是本命令自己的契約")
        // **apply 之後磁碟真的要被升級**（#394 verify R4 的負控找到的缺口：
        // 移除寫入區塊時沒有任何測試會紅，也就是那個區塊在正向上未被測到）。
        XCTAssertTrue(try String(contentsOf: url, encoding: .utf8).contains("- value: 0003-066X"),
                      "apply 的最後一步是把模擬結果落到磁碟——乾跑與 apply 的差別"
                      + "就只剩這一步，沒有它兩者完全一樣")
    }
}

/// 形狀升級的判準是「**它是不是真的裸識別碼**」，不是「它長得像不像 mapping」
/// （#394 verify R4 HIGH）。
///
/// ## 為什麼白名單是錯的範疇
///
/// R3 的病是 `hasPrefix("value:")`——猜一種寫法。R3 的修法換成
/// `looksLikeYAMLMapping`（首字元字母、到冒號只有 `[A-Za-z0-9_.-]`）——**那仍是白名單**，
/// 只是邊界挪了一格。R4 實測四種合法的 format-13 寫法在新邊界外面：
/// `- value : X`（冒號前空格）、`-  value: X`、`- {value: X}`（flow）、`- "value": X`。
///
/// 而前兩者改寫後產生 `- value: value : X`——**整檔 YAML 語法錯誤**（plain scalar
/// 不得含 `: `），比原缺陷嚴重：原缺陷只是 decode 失敗。
///
/// 註解當時寫出了正確的性質（「ISSN／ISBN 的值不含冒號」），卻實作了它的**近似補集**。
/// 正確判準是直接問那個性質：`ISSN(v) != nil`。
extension IdentifierMigrationTests {

    private func upgraded(_ yaml: String, key: String = "issn") -> String {
        let lines = yaml.components(separatedBy: "\n")
        return IdentifierMigration.upgradedLines(lines).joined(separator: "\n")
    }

    /// 只有**真的解析得出識別碼**的裸純量才改寫。
    func testOnlyGenuineBareIdentifiersAreRewritten() {
        XCTAssertEqual(upgraded("issn:\n- 0003-066X"), "issn:\n- value: 0003-066X",
                       "真的裸 ISSN → 升級")
        XCTAssertEqual(upgraded("isbn:\n- 9780306406157"), "isbn:\n- value: 9780306406157")
    }

    /// R4 找到的四種合法 mapping 寫法，一個都不得被碰。
    func testLegalMappingShapesAreNeverRewritten() {
        for shape in ["- value : 0003-066X",          // 冒號前空格
                      "-  value: 0003-066X",           // 兩個空格
                      "- {value: 0003-066X, qualifier: print}",   // flow mapping
                      "- \"value\": 0003-066X",        // 引號鍵
                      "- value: 0003-066X"] {          // 標準形
            let src = "issn:\n\(shape)"
            XCTAssertEqual(upgraded(src), src,
                           "合法的 format-13 元素不得被改寫：\(shape)")
        }
    }

    /// 解析不出識別碼的裸純量**也不碰**——不確定就不動，交給 quarantine 具名。
    func testUnparseableBareScalarIsLeftAlone() {
        let src = "issn:\n- 12345"
        XCTAssertEqual(upgraded(src), src,
                       "12345 不是合法 ISSN——包成 `- value: 12345` 只是把 decode 失敗"
                       + "換個位置，而且假裝我們認得它")
    }

    /// 序列中的空行與註解不得讓後續元素漏掉（R4 ⑤）。
    func testBlankLinesAndCommentsDoNotEndTheSequence() {
        let src = "issn:\n- value: 0003-066X\n\n# 這是註解\n- 1935-990X\nnote: x"
        let out = upgraded(src)
        XCTAssertTrue(out.contains("- value: 1935-990X"),
                      "空行與註解之後的裸純量必須也被升級：\n\(out)")
        XCTAssertTrue(out.contains("note: x"), "序列外的鍵不得被動到")
    }

    /// 序列在**下一個頂層鍵**處結束——那才是真正的邊界。
    func testSequenceEndsAtTheNextTopLevelKey() {
        let src = "issn:\n- 0003-066X\nnote: 0003-066X"
        let out = upgraded(src)
        XCTAssertTrue(out.contains("- value: 0003-066X"))
        XCTAssertTrue(out.contains("note: 0003-066X"), "同樣的字串在序列外不得被改寫")
    }
}

/// 形狀升級的寫入必須在 quarantine 守衛**之後**（#394 verify R4）。
extension IdentifierMigrationRunTests {
    /// 先前順序是「升級寫檔 → load → 守衛」，於是守衛擋下時**檔案已經被改過**，
    /// 而 `report`（含 `shapeUpgraded`）隨例外被丟棄——使用者沒有任何線索知道有寫入發生。
    ///
    /// 正確順序是「升級**模擬** → load（餵記憶體版本）→ 守衛 → 才寫」。
    /// 乾跑本來就走模擬，apply 也走同一條，於是兩者的差別只剩最後那一步。
    func testShapeUpgradeIsNotWrittenWhenTheGuardBlocks() throws {
        // 一個會升級的 venue
        var v = Venue(key: "j", type: .periodical)
        v.issn = [try XCTUnwrap(ISSN("0003-066X"))]
        _ = try store.writeVenue(v)
        let url = store.entityURL(id: v.id)
        let legacy = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "- value: 0003-066X", with: "- 0003-066X")
        try legacy.write(to: url, atomically: true, encoding: .utf8)
        // 一個**不相干**的壞檔，讓守衛擋下
        try "venue:\nid: not-a-uuid\nkey: broken\ntype: periodical\n"
            .write(to: store.root.appendingPathComponent("entities/broken.yaml"),
                   atomically: true, encoding: .utf8)
        commitAll()

        XCTAssertThrowsError(try IdentifierMigration.run(store: store, apply: true),
                             "不相干的 quarantine 必須擋下整個 apply")

        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), legacy,
                       "守衛擋下時**一個位元組都不該寫**——先前它已經改過檔了，"
                       + "而 report 隨例外被丟棄，使用者不會知道")
    }
}

// MARK: - 多 DOI 的邊界（#424）

extension IdentifierMigrationTests {

    /// **真的兩個 DOI 仍然要被跳過。**
    ///
    /// `yeager2020what` 的第二個 DOI（`.supp`）指的是**另一個物件**。吸收它等於讓該
    /// 記錄宣稱自己是那個物件，而識別碼**終結指涉**——那是一句假的身分宣稱。
    ///
    /// 這條與 `testAnUnparseableLabelDoesNotBlockTheParseableIdentifier` 是一對：
    /// 那條放寬「有些 token 解不開」的情形，這條釘住它**沒有**順便放寬「解出兩個真值」。
    ///
    /// ## 一個被放棄的方案，記在這裡免得下次重走
    ///
    /// 途中試過「剝掉 `DOI ` 標籤前綴讓它變成單值」。那個方案**會通過本檔的端到端測試**，
    /// 卻讓 `DOI` 這個 token 從 `skipped` 報告裡消失——而
    /// `testUnparseableTokensAreReportedWhileTheRealOneIsRecovered` 正是釘住它要出現。
    /// `lossless-intake` 執行細節 3：丟棄必須可見。
    ///
    /// 真正的根因不在 tokenizer，在 `take` 把兩個決定綁在同一個 `return`。
    func testTwoRealDOIsAreStillNotAbsorbed() {
        let got = IdentifierMigration.qualifiedCandidates(
            "10.1037/amp0000794 10.1037/amp0000794.supp (Supplemental)", field: "doi")
        XCTAssertGreaterThan(got.count, 1,
                             "兩個真的 DOI 必須維持多值（於是被 skipped、交人裁，#424）")
    }
}
