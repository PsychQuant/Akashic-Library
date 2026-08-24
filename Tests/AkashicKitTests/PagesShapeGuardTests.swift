import XCTest
import Foundation
@testable import AkashicCore

/// `pages` 欄位形狀守衛（`kiki830621/storyline#7`）。
///
/// 三筆實測缺陷驅動了這道守衛，而**三筆裡只有一筆會在下游炸開**：
///
/// - `clarkson2010impact` 的 `1948550610386628` 讓 R 的 `yaml` 大整數溢位落成 `NA`——會叫
/// - `sun2011educational` 的 `0734282910386628` 開頭有 `0`，YAML 當字串讀——**不叫**
/// - `lynn1986determination` 的 `382???386` 是合法字串——**不叫**
///
/// 也就是說在這道守衛之前，偵測完全依賴「下游剛好會壞」，而安靜的那兩種才是多數。
/// 下面每一組測試都用**真實的那三個值**，不用捏造的樣本——捏造的值會讓門檻看起來
/// 剛好合適，而真值才會證明它真的合適。
final class PagesShapeGuardTests: XCTestCase {

    private func messages(_ pages: String?) -> [String] {
        Entry.pagesShapeIssues(pages).map(\.message)
    }

    // MARK: - 三筆實測缺陷都要被抓到

    func testFlagsTheDOISuffixThatOverflowedDownstream() {
        let issues = Entry.pagesShapeIssues("1948550610386628")
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].message.contains("16 位純數字"), issues[0].message)
        XCTAssertTrue(issues[0].message.contains("DOI"), issues[0].message)
    }

    /// 這一則是守衛存在的**主要**理由：它在下游完全不會出聲。
    func testFlagsTheSilentDOISuffixWithLeadingZero() {
        XCTAssertEqual(messages("0734282910394976").count, 1,
                       "開頭為 0 的 DOI 後綴在 YAML 是合法字串，下游不會壞——只有這道守衛看得到它")
    }

    func testFlagsMojibakeFromATranscodedEnDash() {
        let issues = Entry.pagesShapeIssues("382???386")
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].message.contains("替換字元"), issues[0].message)
    }

    // MARK: - 修好之後就不該再叫（回歸保護）

    func testAcceptsTheCorrectedValuesOfAllThreeRecords() {
        for corrected in ["231-238", "534-546", "382-386"] {
            XCTAssertEqual(messages(corrected), [], "更正後的 \(corrected) 不該再被 flag")
        }
    }

    // MARK: - 不得誤傷合法形狀

    /// 判準不是「pages 是不是數字」。article-number 期刊的 `pages` 本來就是單一數字。
    func testDoesNotFlagLegitimateArticleNumbers() {
        for legit in ["e12345", "1234", "e0284637", "382", "R1-R14", "S23-S31",
                      "231-238", "1029–1046", "iii-xvii", "382, 385-390"] {
            XCTAssertEqual(messages(legit), [], "\(legit) 是合法的 pages 形狀，不該被 flag")
        }
    }

    func testIgnoresAbsentAndBlankPages() {
        XCTAssertEqual(messages(nil), [])
        XCTAssertEqual(messages(""), [])
        XCTAssertEqual(messages("   "), [])
    }

    // MARK: - 門檻的界定

    /// 位數門檻取 10：9 位仍可能是（很怪但合法的）article number，10 位起不可能是頁碼。
    /// 把界定寫成測試，是為了讓日後有人調門檻時必須明確地改掉一個斷言，而不是靜默移動它。
    func testTenDigitThresholdIsTheBoundary() {
        XCTAssertEqual(messages(String(repeating: "9", count: 9)), [],
                       "9 位仍在放行側")
        XCTAssertEqual(messages(String(repeating: "9", count: 10)).count, 1,
                       "10 位起攔下")
    }

    func testFlagsAWholeDOIThatLandedInPages() {
        let issues = Entry.pagesShapeIssues("10.1177/1948550610386628")
        XCTAssertEqual(issues.count, 1)
        XCTAssertTrue(issues[0].message.contains("DOI 的形狀"), issues[0].message)
    }

    // MARK: - 接線：`Entry.validate()` 真的有呼叫它

    /// 守衛寫對了但沒有被 `validate()` 呼叫，是這一族缺陷最容易復發的形狀
    /// （`renameEntry` 漏掉 `judgement.prefers` 就是同型：函式正確、呼叫端沒接上）。
    func testEntryValidateActuallyCallsTheGuard() {
        var entry = Entry(id: UUID(),
                          citekey: "clarkson2010impact",
                          type: .periodicalArticle,
                          title: "The impact of illusory fatigue on executive control")
        entry.fields["pages"] = "1948550610386628"
        XCTAssertTrue(entry.validate().contains { $0.message.contains("pages") },
                      "Entry.validate() 必須把 pages 形狀檢查接上")

        entry.fields["pages"] = "231-238"
        XCTAssertFalse(entry.validate().contains { $0.message.contains("pages") })
    }
}
