import XCTest
import Foundation
@testable import AkashicStoreIO
@testable import akashic

/// #705 R3 verify（logic 席）：命令以**沒有訊息**的非零結束碼收場（`throw ExitCode(1)`——import-zotero 的 `writeFailed`、未記下的 DOI 提名，
/// 以及其他幾個命令）時，CLI 進入點先前以 `!safe.isEmpty` 守住 stderr 的第一行，於是這一格 stderr 整個是空的：stdout 有 `writtenWithLegacyCopy`
/// 的報告、結束碼 1、stderr 空——只擷取 stderr 與結束碼的呼叫端（cron、CI）讀不到「不要重跑（兩份並存時 #631 會拒絕）」，而那正是這一行存在的理由。
///
/// `LegacyCopyReport.reportedOnStdout` 是整個 process 的 static（CLI 一個 process 跑一個命令）。本檔在 process 內先呼叫 `printLines`
/// 讓它 > 0——之後的斷言不依賴測試順序。
final class LegacyCopyStderrTextTests: XCTestCase {
    private func reportOne() {
        LegacyCopyReport.printLines([LegacyCopyLeft(kind: .work, key: "k2020a", id: UUID(), legacyFile: "entries/k2020a.yaml", detail: "d")])
    }

    func testSilentNonZeroExitStillSaysTheWritesAreNotFailures() {
        reportOne()
        let text = LegacyCopyReport.stderrText(errorText: "")
        XCTAssertTrue(text.hasPrefix("已寫入 "), text)
        XCTAssertTrue(text.contains("不要重跑"), text)
        XCTAssertTrue(text.contains("沒有錯誤訊息") && text.contains("stdout"), "說出原因在 stdout：\(text)")
        XCTAssertFalse(text.contains("以下是這次失敗的原因"), "沒有後續的錯誤可接：\(text)")
    }

    func testAnErrorMessageStillFollowsTheLeadOnTheNextLine() {
        reportOne()
        let text = LegacyCopyReport.stderrText(errorText: "Error: UNIQUE constraint failed")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        XCTAssertEqual(lines.count, 2, text)
        guard lines.count == 2 else { return }
        XCTAssertTrue(lines[0].hasPrefix("已寫入 ") && lines[0].hasSuffix("以下是這次失敗的原因："), lines[0])
        XCTAssertEqual(lines[1], "Error: UNIQUE constraint failed")
    }
}
