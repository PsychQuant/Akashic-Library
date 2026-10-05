import XCTest
import Foundation
@testable import AkashicStoreIO
@testable import akashic
import AkashicMCPKit

/// #705 R3 verify（logic 席）：命令以**沒有訊息**的非零結束碼收場（`throw ExitCode(1)`——import-zotero 的 `writeFailed`、未記下的 DOI 提名，
/// 以及其他幾個命令）時，CLI 進入點先前以 `!safe.isEmpty` 守住 stderr 的第一行，於是這一格 stderr 整個是空的：stdout 有 `writtenWithLegacyCopy`
/// 的報告、結束碼 1、stderr 空——只擷取 stderr 與結束碼的呼叫端（cron、CI）讀不到那幾筆寫了。
///
/// #705 R2 verify 第二輪（logic 第 13 則、devils-advocate 第 25 則）：第一行無條件說「不要重跑；刪掉 legacy 那份即可」，而它恰好在兩種要重跑的情形出現——
/// 那幾筆裡有之後的寫入沒套用的（`laterWriteRefused`），以及沒有訊息的非零結束（有記錄沒寫成功）。措辭改成依情形。
///
/// 措辭的斷言走純函式（`stderrText(errorText:reported:notApplied:)`），不依賴 process 內累積的 static；計數有沒有跟著 `laterWriteRefused` 走，
/// 另一支經 `printLines` 驗。
final class LegacyCopyStderrTextTests: XCTestCase {
    private func item(notApplied: Bool) -> LegacyCopyLeft {
        var x = LegacyCopyLeft(kind: .work, key: "k2020a", id: UUID(), legacyFile: "entries/k2020a.yaml", detail: "d")
        x.laterWriteRefused = notApplied
        return x
    }

    func testSilentNonZeroExitSaysTheWritesAreNotFailuresButDoesNotSayDoNotRerun() {
        let text = LegacyCopyReport.stderrText(errorText: "", reported: 1, notApplied: 0)
        XCTAssertTrue(text.hasPrefix("已寫入 1 筆"), text)
        XCTAssertTrue(text.contains("不是失敗"), text)
        XCTAssertFalse(text.contains("不要重跑"), "非零結束的原因可能要重跑——不得叫人不要重跑：\(text)")
        XCTAssertTrue(text.contains("可能需要重跑") && text.contains("stdout"), "說出原因在 stdout、那一部分可能要重跑：\(text)")
        XCTAssertFalse(text.contains("以下是這次失敗的原因"), "沒有後續的錯誤可接：\(text)")
    }

    func testNotAppliedItemsAreToldToRerunAfterDeletingTheCopy() {
        let text = LegacyCopyReport.stderrText(errorText: "Error: x", reported: 3, notApplied: 2)
        XCTAssertTrue(text.contains("其中 2 筆之後的寫入沒套用") && text.contains("要重跑"), text)
        XCTAssertFalse(text.contains("不必為了自己重跑"), "有沒套用的就不得說不必重跑：\(text)")
        XCTAssertFalse(text.contains("不要重跑"), text)
    }

    func testOnlyWrittenItemsNeedNoRerunForThemselves() {
        let text = LegacyCopyReport.stderrText(errorText: "Error: UNIQUE constraint failed", reported: 1, notApplied: 0)
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.count, 2, text)
        guard lines.count == 2 else { return }
        XCTAssertTrue(lines[0].hasPrefix("已寫入 1 筆") && lines[0].contains("不必為了自己重跑"), lines[0])
        XCTAssertTrue(lines[0].hasSuffix("以下是這次失敗的原因（它要另外處理）："), lines[0])
        XCTAssertEqual(lines[1], "Error: UNIQUE constraint failed")
    }

    func testNothingReportedLeavesTheErrorAlone() {
        XCTAssertEqual(LegacyCopyReport.stderrText(errorText: "Error: x", reported: 0, notApplied: 0), "Error: x")
    }

    /// 計數經 `printLines` 累積：標了 `laterWriteRefused` 的那一筆讓 static 版本說要重跑。
    func testPrintLinesCountsNotAppliedItems() {
        LegacyCopyReport.printLines([item(notApplied: true)])
        let text = LegacyCopyReport.stderrText(errorText: "")
        XCTAssertTrue(text.contains("筆之後的寫入沒套用"), text)
    }

    /// #705 第三次 verify（LOW 13、INFO 31）：stdout 報告的標題（與 App 側欄同一句）先前無條件說「刪掉 legacy 那份即可」，同一份報告裡標了
    /// 「之後的寫入沒有套用」的列卻說刪掉之後要重跑；而逐筆訊息都帶「確認 entities/ 那份是新的之後」，標題沒有。
    func testTheHeadlineNeitherSaysThatIsAllNorDropsTheCaveat() {
        XCTAssertFalse(LegacyCopyLeft.explanation.contains("即可"), LegacyCopyLeft.explanation)
        XCTAssertTrue(LegacyCopyLeft.explanation.contains("確認 entities/ 那份是新的之後"), LegacyCopyLeft.explanation)
        let lines = LegacyCopyLeft.reportLines([item(notApplied: true)])
        XCTAssertTrue(lines[0].contains(LegacyCopyLeft.explanation), lines[0])
        XCTAssertTrue(lines[1].contains(LegacyCopyLeft.laterWriteRefusedNote), "要重跑的那一句在逐筆的列上：\(lines[1])")
    }

    /// #705 第四次 verify（LOW 20）：stderr 的第一行是 cron／CI 唯一讀到的一行，先前仍無條件說「要刪掉 legacy 那份」——標題上一輪加的前提沒有跟上。
    func testTheStderrLeadCarriesTheSameCaveatAsTheHeadline() {
        for (reported, notApplied) in [(1, 0), (2, 1)] {
            let text = LegacyCopyReport.stderrText(errorText: "", reported: reported, notApplied: notApplied)
            XCTAssertTrue(text.contains("確認 entities/ 那份是新的之後刪掉 legacy 那份"), text)
            XCTAssertFalse(text.contains("即可"), text)
        }
    }
}

/// #705（使用者 2026-10-05 裁決）：結束碼 0、但同一個操作之後的寫入沒套用時，stderr 多印的那一行。真 binary 的兩支在
/// `ZoteroReportCLITests`（`import-zotero` 是 2026-10-05 唯一走得到這一格的命令）；這裡釘純函式的兩種 stdout（文字、JSON）與「沒有就不印」。
extension LegacyCopyStderrTextTests {
    func testTheExitZeroLineIsAbsentWhenEverythingApplied() {
        XCTAssertNil(LegacyCopyReport.successStderrLine(notApplied: 0, stdoutIsJSON: false))
        XCTAssertNil(LegacyCopyReport.successStderrLine(notApplied: 0, stdoutIsJSON: true))
    }

    func testTheExitZeroLineSaysHowManyWhereToLookAndToRerun() throws {
        let text = try XCTUnwrap(LegacyCopyReport.successStderrLine(notApplied: 2, stdoutIsJSON: false))
        XCTAssertFalse(text.contains("\n"), "恰好一行：\(text)")
        XCTAssertTrue(text.contains("有 2 筆之後的寫入沒套用"), text)
        XCTAssertTrue(text.contains("stdout 的 writtenWithLegacyCopy 段"), text)
        XCTAssertTrue(text.contains(LegacyCopyReport.rerunAdvice) && text.contains("確認 entities/ 那份是新的"),
                      "要重跑的判準與非零結束的第一行同一句：\(text)")
        XCTAssertFalse(text.contains("不必") || text.contains("不要重跑"), text)
        let nonZero = LegacyCopyReport.stderrText(errorText: "", reported: 3, notApplied: 2)
        XCTAssertTrue(nonZero.contains(LegacyCopyReport.rerunAdvice), "兩條訊息共用同一句：\(nonZero)")
    }

    func testTheExitZeroLineNamesTheJSONKeysWhenStdoutIsJSON() throws {
        let text = try XCTUnwrap(LegacyCopyReport.successStderrLine(notApplied: 1, stdoutIsJSON: true))
        for key in ["writtenWithLegacyCopy", "laterWriteNotApplied", AkashicService.writtenWithLegacyCopyNotAppliedKey] {
            XCTAssertTrue(text.contains(key), "\(key)：\(text)")
        }
    }
}
