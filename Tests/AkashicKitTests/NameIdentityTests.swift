import XCTest
@testable import AkashicCore

/// 名字的**判定用**等值判準（#296）。
///
/// `NameNormalization.matchingKey` 是它的對偶：配對用、容許假陽性。本判準用於判定
/// （斷言同一並丟棄），**沒有下一關**，所以零假陽性。
final class NameIdentityTests: XCTestCase {

    /// 三個收進來的變換各自生效。
    func testCanonicalCollapsesWhitespaceOnly() {
        XCTAssertTrue(NameIdentity.same("謝叔蓉", "謝叔蓉 "), "前後空白")
        XCTAssertTrue(NameIdentity.same(" 謝叔蓉", "謝叔蓉"), "前導空白")
        XCTAssertTrue(NameIdentity.same("Li  Ming", "Li Ming"), "內部空白串收斂")
        XCTAssertTrue(NameIdentity.same("Li\tMing", "Li Ming"), "tab 也是空白")
        XCTAssertTrue(NameIdentity.same("  Li   Ming  ", "Li Ming"), "三者同時")
    }

    /// **冪等**——正規形再正規化一次不變。
    ///
    /// 沒有這條，判準就不能安全地當成鍵用（Set／字典），而互斥檢查與 merge 去重
    /// 正是這樣用它的。
    func testCanonicalIsIdempotent() {
        for s in ["謝叔蓉 ", "  Li   Ming  ", "Chang, Y-H.", "鄭澈", ""] {
            let once = NameIdentity.canonical(s)
            XCTAssertEqual(NameIdentity.canonical(once), once, "不冪等：\(s.debugDescription)")
        }
    }

    /// **大小寫摺疊刻意不收**（#296 D2）——這條防的是「順手加上」。
    ///
    /// `"Macdonald"` 與 `"MacDonald"` 幾乎總是同一個名字，但「幾乎總是」不滿足收錄
    /// 條件（「兩個字串只差這個就**必然**是同一個名字」）。判定會丟棄資料且沒有
    /// 下一關，所以條件是必然而非機率。
    ///
    /// 代價還**不對稱**：收了之後判定會在拉丁書寫系統上多丟掉一批名字，卻在 CJK 上
    /// 完全沒有效果（大小寫摺疊對 CJK 是 no-op）——用拉丁側的假陽性風險換拉丁側的
    /// 便利，對本 store 的主要書寫系統毫無幫助。
    ///
    /// 要收必須是一次**顯式裁決**（新開 issue、附實測），不是順手帶進來。
    func testCaseFoldingIsDeliberatelyExcluded() {
        XCTAssertFalse(NameIdentity.same("Macdonald", "MacDonald"),
                       "大小寫摺疊不在判定判準內——見 #296 D2")
        // 對照：配對判準**確實**視它們為同一（那是它的工作）。
        XCTAssertEqual(NameNormalization.matchingKey("Macdonald"),
                       NameNormalization.matchingKey("MacDonald"),
                       "前提：配對判準應視為同一，否則本測試沒有對照意義")
    }

    /// NFKC 與連字號家族統一同樣不收——它們會把不同名字塌成一個。
    func testCompatibilityMappingsAreExcluded() {
        // U+2010 HYPHEN vs ASCII hyphen：配對判準收，判定判準不收。
        XCTAssertFalse(NameIdentity.same("Chang, Y\u{2010}H.", "Chang, Y-H."),
                       "連字號家族統一屬配對，不屬判定")
        XCTAssertEqual(NameNormalization.matchingKey("Chang, Y\u{2010}H."),
                       NameNormalization.matchingKey("Chang, Y-H."),
                       "前提：配對判準應視為同一")
    }

    /// 真正不同的名字不得被判為同一。
    func testDistinctNamesStayDistinct() {
        XCTAssertFalse(NameIdentity.same("鄭澈", "Che Cheng"))
        XCTAssertFalse(NameIdentity.same("李明", "李銘"))
    }
}

/// 三個站點接上判準後的行為（#296）。
final class NameIdentityCallSiteTests: XCTestCase {

    /// **分割互斥不再被前後空白穿透**——這是 issue 具名的失敗。
    func testTrailingWhitespaceDoesNotEscapeDisjointCheck() {
        let issues = AuthorizedNames.validateDisjointPartitions(
            authorized: ["謝叔蓉"], variant: ["謝叔蓉 "], ownerKey: "hsieh-shu-jung")
        XCTAssertFalse(issues.isEmpty,
                       "只差尾端空白的名字分居兩分割時必須被報為重疊——先前穿透所有守衛")
        XCTAssertEqual(issues.first?.severity, .error, "互斥違反是 error（結構約束）")
    }

    /// 真正不同的名字分居兩分割是**合法**的——不得誤報。
    func testDistinctNamesInTwoPartitionsAreFine() {
        let issues = AuthorizedNames.validateDisjointPartitions(
            authorized: ["鄭澈"], variant: ["Che Cheng"], ownerKey: "che-cheng")
        XCTAssertTrue(issues.isEmpty, "不同的名字分居兩分割是正常的：\(issues)")
    }

    /// **近重複被指出為未決**——warning，不擋寫入。
    func testNearDuplicateIsSurfacedAsWarning() {
        let issues = AuthorizedNames.validateNearDuplicates(
            names: ["Chang, Y-H.", "Chang, Y\u{2010}H."], ownerKey: "chang-y-h")
        XCTAssertEqual(issues.count, 1, "配對同一但判定不同 → 一條 warning：\(issues)")
        XCTAssertEqual(issues.first?.severity, .warning,
                       "**不得是 error**——那兩個名字可能真的不同，擋寫入等於把"
                       + "「值得問一下」升級成「你錯了」")
        XCTAssertTrue(issues.first?.message.contains("近重複") ?? false,
                      "訊息要說出是什麼問題：\(issues.first?.message ?? "")")
    }

    /// 不相關的名字不得誤報近重複。
    func testUnrelatedNamesDoNotTriggerNearDuplicate() {
        let issues = AuthorizedNames.validateNearDuplicates(
            names: ["鄭澈", "Che Cheng"], ownerKey: "che-cheng")
        XCTAssertTrue(issues.isEmpty, "配對判準也不匹配時不得報近重複：\(issues)")
    }

    /// 判定判準視為同一的兩個名字**不算**近重複——它們已經被收斂了。
    func testExactlyEqualUnderJudgementIsNotNearDuplicate() {
        let issues = AuthorizedNames.validateNearDuplicates(
            names: ["Li Ming", "Li  Ming"], ownerKey: "li-ming")
        XCTAssertTrue(issues.isEmpty,
                      "只差重複空白 → 判定判準已視為同一，不是未決問題：\(issues)")
    }

    /// 近重複進得了 `Person.validate()`——否則它只是一個沒人呼叫的函式。
    func testNearDuplicateReachesPersonValidate() {
        var p = Person(key: "chang-y-h",
                       names: PersonNames(authorized: ["Chang, Y-H."],
                                          variant: ["Chang, Y\u{2010}H."]))
        p.id = UUID()
        let issues = p.validate()
        XCTAssertTrue(issues.contains { $0.message.contains("近重複") },
                      "Person.validate() 必須含近重複 warning：\(issues.map(\.message))")
    }
}
