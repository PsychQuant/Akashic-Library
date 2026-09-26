import Foundation
import XCTest
@testable import AkashicMCPKit

/// #632：`akashic-mcp` 握手回報的 `serverInfo.version` 曾寫死 `0.2.0`，與 release 無關——#630 排查時新舊兩個 binary
/// 握手都說 0.2.0。發布的版號以 `mcpb/manifest.json` 為準（`scripts/release-signed.sh` 要求 VERSION 與它相等），
/// 所以握手的版號必須等於它；release 腳本另在發布前核對同一件事。
final class MCPServerVersionTests: XCTestCase {
    private var repo: URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    func testServerVersionEqualsTheManifestVersion() throws {
        let data = try Data(contentsOf: repo.appendingPathComponent("mcpb/manifest.json"))
        let manifest = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(AkashicMCPVersion.current, manifest["version"] as? String)
    }

    /// 握手用的就是這個常數，不是另一個字面值。
    func testServerHandshakeUsesTheConstant() throws {
        let server = try String(contentsOf: repo.appendingPathComponent("Sources/akashic-mcp/Server.swift"), encoding: .utf8)
        XCTAssertTrue(server.contains("version: AkashicMCPVersion.current"))
    }

    /// release 腳本在發布前核對常數與 VERSION——少了它，manifest 改了而常數沒改時只有這裡的測試會紅，而發布不跑測試。
    func testReleaseScriptChecksTheConstant() throws {
        let script = try String(contentsOf: repo.appendingPathComponent("scripts/release-signed.sh"), encoding: .utf8)
        XCTAssertTrue(script.contains("AkashicMCPVersion.swift"))
    }
}
