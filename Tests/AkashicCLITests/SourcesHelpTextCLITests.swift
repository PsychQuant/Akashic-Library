import XCTest
import Foundation

/// b31 W5（#703）LOW 4、5：說明不得比行為窄。
/// - `copy-zotero-attachments --apply` 先前只寫「任何一道過不了就整批零寫入」——磁碟區沒回報能力旗標時預演不探測，實跑逐筆拒絕（各進寫入失敗、結束碼 1），
///   不是單一的整批拒絕。
/// - MCP `akashic_store_source` 的說明因位元組預算沒寫「做不到不覆寫放置的磁碟區上每一次都拒絕、含只差補 index 的那一筆」——那一格寫在 CLI 的說明，
///   並說出 MCP 同一道閘。
/// 斷言只取沒有空白的片段：ArgumentParser 在空白處換行。
final class SourcesHelpTextCLITests: XCTestCase {
    private func help(_ args: [String]) throws -> String {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-help-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: home) }
        return try CLITestHarness.run(args + ["--help"], env: ["AKASHIC_HOME": home.path]).output
    }

    func testCopyZoteroAttachmentsHelpNamesThePerItemRefusalWhenFlagsAreUnreadable() throws {
        let text = try help(["copy-zotero-attachments"])
        XCTAssertTrue(text.contains("逐筆拒絕"), text)
        XCTAssertTrue(text.contains("預演不探測"), text)
    }

    func testStoreSourceHelpSaysEveryStoreIsRefusedIncludingIndexOnlyRepairs() throws {
        let text = try help(["store-source"])
        XCTAssertTrue(text.contains("只差補"), text)
        XCTAssertTrue(text.contains("akashic_store_source"), text)
    }
}
