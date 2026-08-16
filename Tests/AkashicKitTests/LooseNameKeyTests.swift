import XCTest
@testable import AkashicCore

/// 寬鬆鍵生成（design D1；spec person-resolution）。
/// 鍵只用於配對、永不外洩成資料——`matchingKey` 檔頭鐵律的延伸。
final class LooseNameKeyTests: XCTestCase {

    // MARK: - L1 reorder

    func testReorderKeyIsOrderInvariant() {
        // spec scenario: Token reorder nominates at reorder tier（鍵語意半邊）
        XCTAssertEqual(LooseNameKey.reorderKey("Hsu, Yung-Fong"),
                       LooseNameKey.reorderKey("Yung-Fong Hsu"))
        XCTAssertEqual(LooseNameKey.reorderKey("Hsu, Yung-Fong"), "hsu yung-fong",
                       "逗號句點剝除、token 排序、連字號留在 token 內")
    }

    func testReorderKeyInheritsMatchingKeyNormalization() {
        // 大小寫／連字號家族由 matchingKey 吸收——寬鬆鍵疊在它之上，不自建第二份正規化
        XCTAssertEqual(LooseNameKey.reorderKey("YUNG-FONG   HSU"),
                       LooseNameKey.reorderKey("Hsu, Yung\u{2010}Fong"))
    }

    func testReorderKeyDistinguishesDifferentGivenNames() {
        // reorder 不摺縮寫——「Chen, Yi-Hau」與「Chen, Y.-H.」是不同 reorder 鍵（那是 L2 的事）
        XCTAssertNotEqual(LooseNameKey.reorderKey("Chen, Yi-Hau"),
                          LooseNameKey.reorderKey("Chen, Y.-H."))
    }

    func testReorderKeySingleTokenIsItself() {
        XCTAssertEqual(LooseNameKey.reorderKey("鄭澈"), "鄭澈")
    }

    // MARK: - L2 initials

    func testCommaFixesFamilyNameProducingExactlyOneKey() {
        // spec scenario: Comma fixes the family name
        XCTAssertEqual(LooseNameKey.initialsKeys("Chen, Chun-Houh"), ["chen ch"])
    }

    func testNoCommaGeneratesBothReadings() {
        // 無逗號不猜姓氏位置——姓前／姓後各生一鍵
        let keys = LooseNameKey.initialsKeys("C-H Chen")
        XCTAssertEqual(keys.count, 2)
        XCTAssertTrue(keys.contains("chen ch"), "family-last 解讀：姓 chen、initials ch")
        XCTAssertTrue(keys.contains("c-h c"), "family-first 解讀：姓 c-h、initials c")
    }

    func testDottedInitialsCollapseToSameKeyAsFullGivenName() {
        // spec scenario: Initials form nominates at initials tier（鍵語意半邊）
        // 「Chen, Y.-H.」與「Chen, Yi-Hau」在 initials 鍵空間相等
        XCTAssertEqual(LooseNameKey.initialsKeys("Chen, Y.-H."), ["chen yh"])
        XCTAssertFalse(LooseNameKey.initialsKeys("Chen, Yi-Hau")
            .isDisjoint(with: LooseNameKey.initialsKeys("Chen, Y.-H.")))
    }

    func testDotSeparatedInitialsWithoutHyphenKeepAllLetters() {
        // R1-fix B5：`.` 與 `-` 同為分段界——`Chen, Y.H.` 曾塌成 `chen y`
        XCTAssertEqual(LooseNameKey.initialsKeys("Chen, Y.H."), ["chen yh"])
        XCTAssertEqual(LooseNameKey.initialsKeys("Smith, J.A."), ["smith ja"])
        // 真 store 錯提名的重現案例：`L.W. Wang` 不得再撞 `Wang, Limei`（`wang l`）
        XCTAssertFalse(LooseNameKey.initialsKeys("L.W. Wang")
            .contains("wang l"), "\(LooseNameKey.initialsKeys("L.W. Wang"))")
        XCTAssertTrue(LooseNameKey.initialsKeys("L.W. Wang").contains("wang lw"))
    }

    func testDottedAndHyphenatedFormsShareReorderKey() {
        // 同一修正的 reorder 面：`Y.H.` 與 `Y.-H.` 是同一寫法的兩種標點
        XCTAssertEqual(LooseNameKey.reorderKey("Chen, Y.H."),
                       LooseNameKey.reorderKey("Chen, Y.-H."))
    }

    func testMultipleGivenTokensConcatenateInitials() {
        XCTAssertEqual(LooseNameKey.initialsKeys("Smith, Mary Jane"), ["smith mj"])
    }

    func testCJKNameProducesNoInitialsKey() {
        // spec scenario: CJK name skips initials tier
        XCTAssertTrue(LooseNameKey.initialsKeys("鄭澈").isEmpty)
        XCTAssertTrue(LooseNameKey.initialsKeys("鄭 澈").isEmpty, "多 token 的 CJK 同樣不生")
    }

    func testSingleLatinTokenProducesNoInitialsKey() {
        // 沒有 given 部分就沒有 initials 可言
        XCTAssertTrue(LooseNameKey.initialsKeys("Cher").isEmpty)
    }

    func testRomanizationVariantsStayDistinct() {
        // spec scenario: Romanization variant does not nominate——Hsu 與 Xu 任何鍵都不相等
        XCTAssertNotEqual(LooseNameKey.reorderKey("Xu, Yung-Fong"),
                          LooseNameKey.reorderKey("Hsu, Yung-Fong"))
        XCTAssertTrue(LooseNameKey.initialsKeys("Xu, Yung-Fong")
            .isDisjoint(with: LooseNameKey.initialsKeys("Hsu, Yung-Fong")))
    }
}
