import XCTest
@testable import AkashicCore
@testable import AkashicExport
import BiblatexAPA

/// 必要欄位補充表的退場守衛（#354）。
///
/// `BibExport` 有一張**暫時的**補充表，補上依賴完全沒有意見的 entry type。依
/// `no-compat-fallback`，這種例外必須帶**可執行的退場量測**——「之後再刪」不算，
/// 「當 `<這個量測>` 回 0 就刪」才算。
///
/// 這一組就是那個量測。它的每一條都在回答「這張表現在還有存在的理由嗎」。
final class APA7SupplementalFieldsTests: XCTestCase {

    /// 補充表涵蓋的型別（與 `BibExport` 的私有常數同步；下方測試要求它們一致）。
    private static let supplementedTypes = ["INREFERENCE"]

    /// **退場量測**：補充表只能涵蓋依賴**沒有**的型別。
    ///
    /// 上游哪天把 `INREFERENCE` 加進 `APADataModel.requiredFields`，這條就會紅——
    /// 那一刻該做的是**刪掉補充表的那一列**，不是改這條測試。
    func testSupplementOnlyCoversTypesTheDependencyLacks() {
        for type in Self.supplementedTypes {
            XCTAssertNil(APADataModel.requiredFields[type],
                         "上游已經有 \(type) 的必要欄位表了——請刪掉 "
                         + "BibExport.supplementalRequiredFields 的那一列（退場即刪，"
                         + "留著只會是一個永遠不生效卻看似有用的分支）")
        }
    }

    /// **順序守衛**：依賴優先，補充表只在依賴沒有意見時生效。
    ///
    /// 反過來就變成「用我們的意見覆寫依賴的」——那是 #359 明確拒絕做的事。這條用一個
    /// 依賴**確實有**的型別驗證順序沒被寫反。
    func testDependencyWinsOverSupplement() {
        // ARTICLE 在依賴的表裡，值是 [AUTHOR, TITLE, JOURNALTITLE, DATE]。
        XCTAssertEqual(BibExport.requiredFields(for: "ARTICLE"),
                       APADataModel.requiredFields["ARTICLE"],
                       "依賴有意見的型別必須原樣取用，不得被補充表干擾")
    }

    /// 補充表的型別真的被當成「已檢查」。
    ///
    /// 沒有這條，補充表可以存在而完全不生效（同 #264 的 `storeSource`：API 完整、
    /// 防護齊全、零 production 呼叫端）。
    func testSupplementedTypesAreActuallyChecked() {
        // `wikipediaEntry` 送 INREFERENCE。缺 BOOKTITLE 要被抓到。
        let noBooktitle = Entry(id: UUID(), citekey: "anon2019wiki", type: .wikipediaEntry,
                               title: "List of Oldest Companies", authors: [], date: "2019")
        let report = BibExport.apa7Report(entries: [noBooktitle], people: [])
        XCTAssertTrue(report.uncheckedCitekeys.isEmpty,
                      "INREFERENCE 現在有補充表，不該再落進 unchecked")
        XCTAssertEqual(report.issues.filter { $0.severity == .error }.map(\.message),
                       ["Missing required field: BOOKTITLE"],
                       "應只報缺 BOOKTITLE")
    }

    /// **`AUTHOR` 不得是必要欄位。**
    ///
    /// 這是整條線的重點。APA7 §10.3 的參考工具書條目**條目名佔作者位置**，所以維基
    /// 條目沒有個人作者是**正確形式**而非缺漏。#352 把 `wikipediaEntry` 從
    /// `INCOLLECTION`（要求 `AUTHOR`）改對映到 `INREFERENCE` 就是為了消除那 14 筆
    /// 假陽性——若補充表把 `AUTHOR` 寫進必要欄位，那個假陽性就從另一條路回來了。
    func testAuthorIsNotRequiredForReferenceWorkEntries() {
        var entry = Entry(id: UUID(), citekey: "anon2019wiki", type: .wikipediaEntry,
                          title: "List of Oldest Companies", authors: [], date: "2019")
        entry.fields = ["booktitle": "Wikipedia"]
        let errors = BibExport.apa7Report(entries: [entry], people: [])
            .issues.filter { $0.severity == .error }
        XCTAssertTrue(errors.isEmpty,
                      "無個人作者的維基條目是 APA7 的正確形式，不該報 error：\(errors)")
    }

    /// `AUTHOR` 是 recommended——同節另有帶團體作者的例子，所以它不是禁止而是建議。
    func testAuthorIsRecommendedForReferenceWorkEntries() {
        var entry = Entry(id: UUID(), citekey: "anon2019wiki", type: .wikipediaEntry,
                          title: "An Entry", authors: [], date: "2019")
        entry.fields = ["booktitle": "Wikipedia"]
        let warnings = BibExport.apa7Report(entries: [entry], people: [])
            .issues.filter { $0.severity == .warning }.map(\.message)
        XCTAssertTrue(warnings.contains("Missing recommended field: AUTHOR"),
                      "AUTHOR 應是 recommended（§10.3 有帶團體作者的例子）：\(warnings)")
    }

    /// **仍然未涵蓋的型別要保持可見。**
    ///
    /// 補充表只補了 `INREFERENCE`，因為 `IMAGE`（`visualWork`）與 `UNPUBLISHED`
    /// （`unpublishedWork`）在 store 目前**零實例**——沒有量測就不該猜它們的
    /// 必要欄位（`zero-instance-guards` 的紀律：一列一列裁決，不依性質相似類推）。
    ///
    /// 這條把「還沒補」釘住，讓它們哪天有了實例時不會靜默通過。
    ///
    /// **`.review` 於 #355 離開這份清單**——它改送 `ARTICLE`（因為 10.7 的達成條件是
    /// `ARTICLE`／`VIDEO`／`ONLINE` ＋ `RELATEDTYPE`），而 `ARTICLE` 本來就在依賴的
    /// 必要欄位表內。見下一條的正面斷言。
    func testStillUncoveredTypesRemainVisible() {
        for type in [WorkType.visualWork, .unpublishedWork] {
            let entry = Entry(id: UUID(), citekey: "probe\(type.rawValue.filter(\.isLetter))",
                              type: type, title: "Probe", authors: [], date: "2020")
            let report = BibExport.apa7Report(entries: [entry], people: [])
            XCTAssertEqual(report.uncheckedCitekeys, [entry.citekey],
                           "\(type.rawValue)（送 \(type.biblatexEntryType)）目前零實例、"
                           + "未補必要欄位，必須列為未涵蓋而非靜默通過")
        }
    }

    /// **#355 的附帶效果：`.review` 從「未涵蓋」變成「有下限」。**
    ///
    /// 改送 `ARTICLE` 不只修好了節（10.8 → 10.7），也讓它落進依賴的必要欄位表——
    /// 一筆缺 `JOURNALTITLE` 的書評現在會報 error，而先前它連檢查都沒被檢查。
    ///
    /// 這條是正面斷言：只把 `.review` 從上一條的清單裡拿掉，只證明「它不再未涵蓋」，
    /// **不證明它被檢查到對的東西**。
    func testReviewIsNowCoveredWithTheJournalArticleFloor() {
        let bare = Entry(id: UUID(), citekey: "probereview", type: .review,
                         title: "Review of Something", authors: [], date: "2020")
        let report = BibExport.apa7Report(entries: [bare], people: [])
        XCTAssertTrue(report.uncheckedCitekeys.isEmpty,
                      "`.review` 送 ARTICLE，已被依賴的必要欄位表涵蓋："
                      + "\(report.uncheckedCitekeys)")
        let missing = report.issues.filter { $0.severity == .error }.map(\.message)
        XCTAssertTrue(missing.contains { $0.contains("JOURNALTITLE") },
                      "期刊書評的下限含 JOURNALTITLE（§10.7 的宿主是期刊文章）：\(missing)")
    }
}
