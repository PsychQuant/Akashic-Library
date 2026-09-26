import Foundation
import XCTest

/// #592：`rests_on` 的寫入閘與 decode 閘自 #507 起只收 `sha256:` digest。描述若仍說收 URL，照描述呼叫的消費端
/// 會拿到拒絕——描述在說謊、閘在說真話。源碼掃描釘住兩個面的描述（MCP tool schema 與 CLI help）。
final class RestsOnDescriptionTests: XCTestCase {
    private func read(_ path: String) throws -> String {
        let repo = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        return try String(contentsOf: repo.appendingPathComponent(path), encoding: .utf8)
    }

    /// 每一行提到 rests_on（或 CLI 的 rests-on 描述）的描述字串，都不得把 URL 說成合法值。
    func testNoRestsOnDescriptionClaimsURLsAreAccepted() throws {
        for path in ["Sources/akashic-mcp/Server.swift", "Sources/akashic/Commands.swift"] {
            let offending = try read(path).split(separator: "\n").filter {
                $0.contains("來源 URL 或") || $0.contains("URL 或 sha256")
            }
            XCTAssertEqual(offending, [], path)
        }
    }

    /// record_divergence 的 rests_on 描述要說出 digest 形狀與取得方式。
    func testRecordDivergenceRestsOnNamesTheDigestShape() throws {
        let server = try read("Sources/akashic-mcp/Server.swift")
        let line = try XCTUnwrap(server.split(separator: "\n").first { $0.contains("判斷依據的存檔 digest") })
        XCTAssertTrue(line.contains("sha256:64hex"))
        XCTAssertTrue(line.contains("akashic_store_source"))
    }
}
