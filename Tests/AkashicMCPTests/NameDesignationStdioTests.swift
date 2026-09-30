import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// 名字分類面的 MCP 參數**經真 binary** 到得了服務層：`akashic_update_venue` 的 `unauthorize`（#559）、`akashic_update_organization`（#557）。
/// 參數解析住在 server 的分派閉包裡（`argList`），服務層測不到它——分派漏接一個參數時，呼叫照樣回成功、什麼都沒做。
///
/// spawn 模式同 `DepthGuardIdTests`；讀回應走 `StdioE2ETests.readLine`（non-blocking、有期限、EOF 與逾時都丟錯）——先前這裡照 `DepthGuardIdTests` 用
/// `availableData` 迴圈，server 靜默時讀取阻塞、期限檢查輪不到，server 崩潰（EOF）則空轉到期限後 `XCTSkip`，把崩潰記成跳過（R1 verify #559／#557 第 10／20 列）。
final class NameDesignationStdioTests: XCTestCase {
    var root: URL!
    var process: Process!
    var stdinPipe: Pipe!
    var reader: FileHandle!
    /// 讀到但還沒交出去的位元組（一次 read 可能拿到兩行）
    var pending = Data()

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-namedes-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        _ = try store.writeVenue(Venue(key: "some-journal", type: .periodical,
                                       names: Timeline([TemporalValue(value: "PSYCHOMETRIKA"), TemporalValue(value: "Psychometrika")]),
                                       authorized: ["Psychometrika"]))
        try store.writeOrganization(Organization(key: "iss", names: Timeline([TemporalValue(value: "Institute of Statistical Science")]),
                                                 id: UUID()))
        process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("akashic-mcp")
        process.environment = ProcessInfo.processInfo.environment
            .filter { !$0.key.hasPrefix("AKASHIC_") }
            .merging(["AKASHIC_LIBRARY": root.path]) { _, new in new }
        stdinPipe = Pipe()
        let stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        try process.run()
        reader = stdoutPipe.fileHandleForReading
        StdioE2ETests.setNonBlocking(reader.fileDescriptor)
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:] as [String: Any],
                             "clientInfo": ["name": "t", "version": "1"]]])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }

    override func tearDownWithError() throws {
        process.terminate()
        try? FileManager.default.removeItem(at: root)
    }

    private func send(_ obj: [String: Any]) throws {
        stdinPipe.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: obj) + Data("\n".utf8))
    }

    /// 讀一行回應。讀不到（逾時、server 結束）是**失敗**——這組測試存在的理由是「分派漏接參數時呼叫照樣回成功」，server 死了就沒有東西被驗到，
    /// 記成跳過會讓新面的 e2e 覆蓋靜默消失。
    private func readResponse() throws -> [String: Any] {
        let line = try StdioE2ETests.readLine(fd: reader.fileDescriptor, pending: &pending, timeout: 20)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: line) as? [String: Any])
    }

    func call(_ id: Int, _ name: String, _ args: [String: Any]) throws -> String {
        try send(["jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": name, "arguments": args]])
        let resp = try readResponse()
        let result = try XCTUnwrap(resp["result"] as? [String: Any], "回應沒有 result：\(resp)")
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }

    func load() throws -> LibraryLoad { try LibraryStore(root: root).load() }

    /// #559：`unauthorize` 到得了服務層——authorized 真的變空、名字留在 names；畸形值（少一層括號）整個呼叫拒絕（#561 的 argList 契約）。
    func testVenueUnauthorizeReachesTheService() throws {
        let bare = try call(2, "akashic_update_venue", ["key": "some-journal", "unauthorize": "Psychometrika"])
        XCTAssertTrue(bare.contains("unauthorize 必須是字串陣列"), bare)
        XCTAssertEqual(try load().venues.first?.authorized, ["Psychometrika"], "畸形值零寫入")

        let out = try call(3, "akashic_update_venue", ["key": "some-journal", "unauthorize": ["Psychometrika"]])
        XCTAssertTrue(out.contains("authorizedWithdrawn") && out.contains("\"index\""), out)
        let v = try XCTUnwrap(try load().venues.first)
        XCTAssertEqual(v.authorized, [])
        XCTAssertEqual(Set(v.names.entries.map(\.value)), ["PSYCHOMETRIKA", "Psychometrika"])
    }

    /// #557：`akashic_update_organization` 是註冊過、分派得到的工具——`authorize` 到得了服務層；沒給、空陣列、只有空白項整批拒絕
    /// （R1 verify：MCP 的 `[]` 曾走完寫檔與重建 index，CLI 早就擋了）；沒有 `unauthorize` 參數（拿掉了）。
    func testUpdateOrganizationReachesTheService() throws {
        let url = LibraryStore(root: root).entityURL(id: try XCTUnwrap(try load().organizations.first).id)
        let before = try Data(contentsOf: url)
        for (id, args) in [(4, ["key": "iss"] as [String: Any]), (5, ["key": "iss", "authorize": [] as [String]]),
                           (6, ["key": "iss", "authorize": [" "]])] {
            let refused = try call(id, "akashic_update_organization", args)
            XCTAssertTrue(refused.contains("沒有要改的"), "\(args)：\(refused)")
        }
        XCTAssertEqual(try Data(contentsOf: url), before, "三種「沒有要改的」都零寫入")

        let out = try call(7, "akashic_update_organization", ["key": "iss", "authorize": ["Institute of Statistical Science"]])
        XCTAssertTrue(out.contains("authorizedAdded"), out)
        XCTAssertEqual(try load().organizations.first?.authorized, ["Institute of Statistical Science"])
    }
}
