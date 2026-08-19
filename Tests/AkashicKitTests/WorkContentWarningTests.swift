import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #169：`type`／`title` 的刻意排除留下**靜默**的內容遺失——不擋，但要說。
///
/// ## 為什麼「不擋」與「不說」是兩件事
///
/// 排除 `type`／`title` 的比對是對的（#157 的論證）：要求相等會重演 #71 R2 DA 的
/// 誤拒——同一篇的兩筆記錄 title 大小寫／副標題本來就會不同，而 keeper 的寫法
/// **就是人選的 canonical form**。
///
/// 但真 binary 實測（#157 verify 157-17）：
///
///     keeper: "Short"
///     doomed: "Short: A Much Longer Subtitle That Only This Record Has"
///     → exit 0、`✓ 併入`、副標題無聲消失
///
/// 被刪檔在版控裡（消歧的 gate 強制 tracked + clean），所以**可回溯**——這降低了
/// 嚴重度，但不改變「使用者在當下看不到」。
///
/// ## 判準：嚴格包含，不是「不同」
///
/// 對「兩者不同」出聲會讓每一組大小寫／標點差異都觸發提醒，把它變成噪音——而
/// 噪音會讓人停止讀它，那比不提醒更糟。只在**被併者嚴格包含倖存者**時說話，那是
/// 「倖存者的版本較不完整」唯一機械可判定的形狀。
final class WorkContentWarningTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-w169-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        GitFixture.initRepo(root)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func warnings(keeperTitle: String, doomedTitle: String) -> [String] {
        let keeper = Entry(id: UUID(), citekey: "k2020", type: .periodicalArticle, title: keeperTitle)
        let doomed = Entry(id: UUID(), citekey: "d2020", type: .periodicalArticle, title: doomedTitle)
        return LibraryStore.contentWarningsForMerging(doomed, into: keeper)
    }

    /// 倖存者的標題被嚴格包含 → 說。
    func testShorterKeeperTitleIsReported() {
        let w = warnings(keeperTitle: "Short",
                         doomedTitle: "Short: A Much Longer Subtitle That Only This Record Has")
        XCTAssertEqual(w.count, 1, "要說出來：\(w)")
        XCTAssertTrue(w[0].contains("A Much Longer Subtitle"),
                      "要指名將消失的內容，否則提醒不可執行：\(w)")
        XCTAssertTrue(w[0].contains("不擋"), "要說清楚這不是拒絕，避免被讀成錯誤")
    }

    /// **只在倖存者是前綴時出聲**（#169 verify F9）。
    ///
    /// 守衛先前用 `contains`（任意位置）而 `extra` 用 `dropFirst(k.count)` 算，
    /// 於是七種形狀裡**六種訊息在說假話**——最嚴重的是把 keeper **已經有的**
    /// 內容報成「多了」。而引號／方括號／前導標點是 F2 修法的漏網：詞字元 guard
    /// 檢查的是**切歪之後**的字串。
    func testOnlyPrefixContainmentSpeaks() {
        // keeper 在中間／尾端：訊息會從字中間切開 → 不說
        XCTAssertEqual(warnings(keeperTitle: "Nature",
                                doomedTitle: "The Nature of Space and Time"), [])
        XCTAssertEqual(warnings(keeperTitle: "Space and Time",
                                doomedTitle: "On Space and Time"), [])
        // 最嚴重：把 keeper 已經有的內容報成「多了」
        XCTAssertEqual(warnings(keeperTitle: "Core", doomedTitle: "The Core of It"), [])
        // F2 的漏網：純標點包住
        XCTAssertEqual(warnings(keeperTitle: "Learning", doomedTitle: "[Learning]"), [])
        XCTAssertEqual(warnings(keeperTitle: "Learning", doomedTitle: ". Learning"), [])
        // 真前綴仍要說
        XCTAssertEqual(warnings(keeperTitle: "Short",
                                doomedTitle: "Short: A Real Subtitle").count, 1)
    }

    /// **前綴比對走 case-fold**（#169 verify F5）。
    ///
    /// 真 corpus 上 **15/15** 有差異的候選對都是大小寫差異——同一篇的兩筆記錄
    /// 幾乎必然在大小寫上不同。真的帶副標題遺失的那組**同時**帶大小寫差異的
    /// 機率高於不帶，case-sensitive 會整個漏掉。
    func testPrefixMatchIsCaseInsensitive() {
        let w = warnings(keeperTitle: "Attention is all you need",
                         doomedTitle: "Attention Is All You Need: A Retrospective")
        XCTAssertEqual(w.count, 1, "sentence case vs title case 是書目來源最常見的差異：\(w)")
        XCTAssertTrue(w[0].contains(": A Retrospective"),
                      "extra 必須從**原始的** doomed 切——從折疊後的切會印出小寫化的內容")
        XCTAssertFalse(w[0].contains("a retrospective"), "同上")
        // 純大小寫差異（等長）仍不說
        XCTAssertEqual(warnings(keeperTitle: "The Structure of X",
                                doomedTitle: "the structure of x"), [])
        // 大小寫差異 + 尾端句點：詞字元 guard 擋掉
        XCTAssertEqual(warnings(keeperTitle: "The Structure of X",
                                doomedTitle: "the structure of x."), [])
    }

    /// **一般的不同不說**——那會變成噪音，而噪音讓人停止讀提醒。
    func testUnrelatedTitleDifferencesAreSilent() {
        XCTAssertTrue(warnings(keeperTitle: "The Structure of X",
                               doomedTitle: "the structure of x").isEmpty,
                      "大小寫差異不說")
        XCTAssertTrue(warnings(keeperTitle: "A study of Y",
                               doomedTitle: "A study of Z").isEmpty,
                      "內容不同但互不包含——那是兩筆記錄的正常差異，不是遺失")
        XCTAssertTrue(warnings(keeperTitle: "Same", doomedTitle: "Same").isEmpty, "相同不說")
    }

    /// 反方向不說——倖存者較長時，合併不會失去任何東西。
    func testLongerKeeperIsSilent() {
        XCTAssertTrue(warnings(keeperTitle: "Short: With Subtitle",
                               doomedTitle: "Short").isEmpty,
                      "倖存者較完整 → 合併零損失")
    }

    /// **缺席方向歸 `fieldsLostByMerging`**（那裡是**拒絕**不是提醒）——本函式不重複。
    ///
    /// 兩份清單互補：一個問「被併者帶有倖存者沒有的內容嗎」（拒絕），一個問
    /// 「兩邊都有但倖存者的比較少嗎」（提醒）。空值屬前者。
    func testAbsenceBelongsToTheRefusalPathNotHere() {
        XCTAssertTrue(warnings(keeperTitle: "", doomedTitle: "The Only Real Title").isEmpty,
                      "缺席由 fieldsLostByMerging 拒絕，本函式不重複出聲")
        // 而那條確實會拒絕
        let keeper = Entry(id: UUID(), citekey: "k", type: .periodicalArticle, title: "")
        let doomed = Entry(id: UUID(), citekey: "d", type: .periodicalArticle, title: "The Only Real Title")
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(doomed, into: keeper)
            .contains { $0.contains("The Only Real Title") }, "缺席方向仍是拒絕")
    }

    /// **`type` 不在範圍內**（#169 verify F1）。
    ///
    /// `type` 是封閉 token 集合，字串包含與完整度零相關。原始版本窮舉 26 個常見
    /// biblatex type，**13 對**滿足嚴格包含，而真 store 裡 `book`(58)／
    /// `incollection`(6)／`inproceedings`(4) 都在。訊息本身也是假的：`inbook`
    /// 不是 `book` 的較長版本。
    ///
    /// **#325 階段二起 pair 清單從 `allCases` 現算**，不再寫死 biblatex 名字（那些
    /// 值已不在 `WorkType` 的值域裡）。這也讓測試隨值域自動成長——日後新增一個
    /// rawValue 與既有值互為子字串的 case，這條守衛立刻涵蓋它，不必有人記得回來補。
    /// 現行值域恰有一對：`book` ⊂ `book-chapter`。
    func testTypeIsNotComparedAtAll() {
        let pairs: [(WorkType, WorkType)] = WorkType.allCases.flatMap { a in
            WorkType.allCases.compactMap { b in
                (a != b && b.rawValue.contains(a.rawValue)) ? (a, b) : nil
            }
        }
        XCTAssertFalse(pairs.isEmpty, "值域裡至少該有一對嚴格包含（book ⊂ book-chapter），"
                       + "否則這條測試變成 vacuous pass")
        for (k, d) in pairs {
            let keeper = Entry(id: UUID(), citekey: "k", type: k, title: "Same")
            let doomed = Entry(id: UUID(), citekey: "d", type: d, title: "Same")
            XCTAssertEqual(LibraryStore.contentWarningsForMerging(doomed, into: keeper), [],
                           "「\(k.rawValue) ⊂ \(d.rawValue)」是兩個不同的 type，不是內容遺失")
        }
    }

    /// **純標點／空白差異不出聲**（#169 verify F2）。
    ///
    /// 席位在真 store 上量：嚴格包含觸發 5 次，**5 次全部**是「doomed 只多一個
    /// 句點」（APA 式句末句點），真實遺失 0 筆。尾端標點**正好就是**嚴格包含的
    /// 形狀——原本的判準把自己論證要避免的噪音製造了出來。
    func testTrailingPunctuationAndWhitespaceAreNotLoss() {
        for d in ["Learned helplessness in children.", "Learned helplessness in children ",
                  "Learned helplessness in children:", "Learned helplessness in children..."] {
            XCTAssertEqual(warnings(keeperTitle: "Learned helplessness in children",
                                    doomedTitle: d), [],
                           "多出來的只有標點／空白，不是內容：\(d)")
        }
        // 而真的多了一段內容仍要說
        XCTAssertEqual(warnings(keeperTitle: "Short",
                                doomedTitle: "Short: A Real Subtitle").count, 1)
    }

    /// **提醒要指名被併者**（#169 verify F4）。
    ///
    /// 同檔兩條 sibling 路徑都指名（`wouldLoseFields` 帶 citekey、`judgementWarnings`
    /// 帶 collapsed UUID，其 doc 明寫「事後才看到只剩裸 UUID 已經來不及了」）。
    /// 多個 doomed 且 title 相同時，不指名會印出兩行**逐字相同**的 ⚠。
    func testWarningNamesTheDoomedRecord() {
        let keeper = Entry(id: UUID(), citekey: "k2020", type: .periodicalArticle, title: "Short")
        let doomed = Entry(id: UUID(), citekey: "d2020", type: .periodicalArticle,
                           title: "Short: A Real Subtitle")
        let w = LibraryStore.contentWarningsForMerging(doomed, into: keeper)
        XCTAssertTrue(w.first?.contains("d2020") == true, "要指名是哪一筆：\(w)")
    }

    /// **preview 與實跑必須給同一組提醒**——提醒的價值在於它出現在還能反悔的時點。
    ///
    /// 兩邊都取自同一個 `validateWorkPreconditions` 回傳值，所以這條釘的是
    /// 「那個共用點沒有被繞過」（159-1 的形狀：兩邊各自準備輸入、各自可能改壞）。
    func testPreviewAndActualCarrySameWarnings() throws {
        var keeper = Entry(id: UUID(), citekey: "k2020", type: .periodicalArticle, title: "Short")
        keeper.date = "2020"
        var doomed = Entry(id: UUID(), citekey: "d2020", type: .periodicalArticle,
                           title: "Short: A Much Longer Subtitle")
        doomed.date = "2020"
        try store.writeEntry(keeper); try store.writeEntry(doomed)
        // **帶 judgement**：那是唯一會讓 preview 與實跑順序分岔的形狀
        let d = Divergence(
            id: UUID(), question: "同一篇？",
            candidates: [DivergenceCandidate(key: "k2020", shape: .work),
                         DivergenceCandidate(key: "d2020", shape: .work)],
            // **prefers 指向被併者、survivor 選另一邊** → 走 override 路徑，
            // 於是 judgement warning 與 content warning **同時**存在。那是唯一
            // 會讓兩邊順序分岔的形狀；prefers 與 survivor 相符時只有一個 warning，
            // 順序不可能分岔，`XCTAssertEqual(preview, actual)` 就是空跑
            // （#169 verify F3）。
            judgement: Judgement(statement: "名冊確認 d2020 是正式寫法",
                                 restsOn: ["sha256:" + String(repeating: "ab", count: 32)],
                                 prefers: "d2020"))
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")

        let preview = try store.previewResolveDivergence(
            id: d.id, survivor: "k2020", overrideReason: "名冊已更新，改採 k2020")
        XCTAssertGreaterThanOrEqual(preview.warnings.count, 2,
            "fixture 必須同時有 judgement 與 content 兩種 warning——只有一種時順序"
            + "不可能分岔，下面那條 XCTAssertEqual 就是空跑（#169 verify F3）："
            + "\(preview.warnings)")
        XCTAssertTrue(preview.warnings.contains { $0.contains("A Much Longer Subtitle") },
                      "dry-run 是唯一還能反悔的時點，提醒必須在那裡：\(preview.warnings)")
        let actual = try store.resolveDivergence(id: d.id, survivor: "k2020",
                                                 overrideReason: "名冊已更新，改採 k2020")
        XCTAssertEqual(preview.warnings, actual.warnings,
                       "兩邊取自同一個共用點——不一致代表那個點被繞過了")
        XCTAssertEqual(actual.failures, [], "提醒不擋——合併仍要成功")
        XCTAssertEqual(actual.merged, ["d2020"])
    }
}
