import XCTest

/// `akashic --version`（#775）：印建置時的 commit（`scripts/stamp-version.sh` 寫進 `BuildVersion.swift`）。
///
/// 沒經過戳記腳本的建置——包括這支測試跑的建置——印佔位值 `unknown`、結束碼 0。比 #775 舊的 CLI 對這個旗標回 64
/// （ArgumentParser 的用法錯誤）。akashic-mcp plugin 的 SessionStart hook（`plugin/hooks/check-cli.sh`）把兩者分開處理：
/// `unknown` 比檔案時間；回 64 而比對的基準上已經有 `BuildVersion.swift`，就是必定落後，基準上還沒有才比檔案時間。
final class CLIVersionTests: XCTestCase {
    func testUnstampedBuildPrintsThePlaceholder() throws {
        let r = try CLITestHarness.run(["--version"], env: [:])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertEqual(r.output.trimmingCharacters(in: .whitespacesAndNewlines), "unknown")
    }
}
