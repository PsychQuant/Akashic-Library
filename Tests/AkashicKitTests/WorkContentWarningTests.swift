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
        let keeper = Entry(id: UUID(), citekey: "k2020", type: "article", title: keeperTitle)
        let doomed = Entry(id: UUID(), citekey: "d2020", type: "article", title: doomedTitle)
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
        let keeper = Entry(id: UUID(), citekey: "k", type: "article", title: "")
        let doomed = Entry(id: UUID(), citekey: "d", type: "article", title: "The Only Real Title")
        XCTAssertTrue(LibraryStore.fieldsLostByMerging(doomed, into: keeper)
            .contains { $0.contains("The Only Real Title") }, "缺席方向仍是拒絕")
    }

    /// **preview 與實跑必須給同一組提醒**——提醒的價值在於它出現在還能反悔的時點。
    ///
    /// 兩邊都取自同一個 `validateWorkPreconditions` 回傳值，所以這條釘的是
    /// 「那個共用點沒有被繞過」（159-1 的形狀：兩邊各自準備輸入、各自可能改壞）。
    func testPreviewAndActualCarrySameWarnings() throws {
        var keeper = Entry(id: UUID(), citekey: "k2020", type: "article", title: "Short")
        keeper.date = "2020"
        var doomed = Entry(id: UUID(), citekey: "d2020", type: "article",
                           title: "Short: A Much Longer Subtitle")
        doomed.date = "2020"
        try store.writeEntry(keeper); try store.writeEntry(doomed)
        let d = Divergence(
            id: UUID(), question: "同一篇？",
            candidates: [DivergenceCandidate(key: "k2020", shape: .work),
                         DivergenceCandidate(key: "d2020", shape: .work)])
        try store.writeDivergence(d)
        GitFixture.commitAll(root, message: "seed")

        let preview = try store.previewResolveDivergence(
            id: d.id, survivor: "k2020", overrideReason: nil)
        XCTAssertTrue(preview.warnings.contains { $0.contains("A Much Longer Subtitle") },
                      "dry-run 是唯一還能反悔的時點，提醒必須在那裡：\(preview.warnings)")
        let actual = try store.resolveDivergence(id: d.id, survivor: "k2020")
        XCTAssertEqual(preview.warnings, actual.warnings,
                       "兩邊取自同一個共用點——不一致代表那個點被繞過了")
        XCTAssertEqual(actual.failures, [], "提醒不擋——合併仍要成功")
        XCTAssertEqual(actual.merged, ["d2020"])
    }
}
