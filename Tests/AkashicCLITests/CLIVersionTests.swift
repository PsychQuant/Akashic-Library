import XCTest

/// `akashic --version`（#775）：印建置時的 commit（`scripts/stamp-version.sh` 寫進 `BuildVersion.swift`）。
///
/// 沒經過戳記腳本的建置——包括這支測試跑的建置——印佔位值 `unknown`、結束碼 0。舊 CLI 對這個旗標回 64
/// （ArgumentParser 的用法錯誤），akashic-mcp plugin 的 SessionStart hook（`plugin/hooks/check-cli.sh`）
/// 靠這兩個結果分辨「沒有戳記的新 CLI」與「比 #775 還舊的 CLI」，兩者都改比檔案時間。
final class CLIVersionTests: XCTestCase {
    func testUnstampedBuildPrintsThePlaceholder() throws {
        let r = try CLITestHarness.run(["--version"], env: [:])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertEqual(r.output.trimmingCharacters(in: .whitespacesAndNewlines), "unknown")
    }
}
