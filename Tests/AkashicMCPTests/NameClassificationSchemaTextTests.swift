import XCTest
@testable import AkashicStoreIO

/// #564 b36 Y1 第 3 列：`akashic_update_person` 的 inputSchema 屬性說明是機器可讀的契約，與工具描述、CLI help 同一份裁決——
/// 2026-10-05 裁決第 2 點（只替進出 authorized 的名字寫記錄，留下的不寫確認）之後，工具描述改了、`judgement` 屬性仍寫「仍是對外形的寫確認」，
/// 只讀屬性說明的 LLM 呼叫端會以為附理由能替沒動的名字留一筆確認，實際上那種呼叫被拒。這支測試走**真 binary** 的 `tools/list`（呼叫端看到的
/// 就是這一份），釘住名字分類相關的屬性說明：不得宣稱 `fields.names` 會寫「確認」，`judgement` 要說出「進出才收、否則拒收」。
final class NameClassificationSchemaTextTests: XCTestCase {
    private var root: URL!
    private var process: Process!
    private var stdinPipe: Pipe!
    private var reader: FileHandle!
    private var pending = Data()

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-schematext-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
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
    }

    override func tearDownWithError() throws {
        process.terminate()
        try? FileManager.default.removeItem(at: root)
    }

    private func send(_ obj: [String: Any]) throws {
        stdinPipe.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: obj) + Data("\n".utf8))
    }
    private func readResponse() throws -> [String: Any] {
        let line = try StdioE2ETests.readLine(fd: reader.fileDescriptor, pending: &pending, timeout: 20)
        return try XCTUnwrap(try JSONSerialization.jsonObject(with: line) as? [String: Any])
    }

    private func updatePersonTool() throws -> [String: Any] { try tool("akashic_update_person") }

    private func tool(_ name: String) throws -> [String: Any] {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:] as [String: Any],
                             "clientInfo": ["name": "t", "version": "1"]]])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let resp = try readResponse()
        XCTAssertEqual(resp["id"] as? Int, 2, "讀到的不是 tools/list 的回應")
        let tools = try XCTUnwrap((resp["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        return try XCTUnwrap(tools.first { $0["name"] as? String == name }, "tools/list 裡沒有 \(name)")
    }

    func testUpdatePersonSchemaDoesNotPromiseAConfirmationForUnmovedNames() throws {
        let tool = try updatePersonTool()
        let props = try XCTUnwrap((tool["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        let judgement = try XCTUnwrap((props["judgement"] as? [String: Any])?["description"] as? String, "judgement 沒有說明")
        XCTAssertTrue(judgement.contains("進出") && judgement.contains("必填") && judgement.contains("拒收"),
                      "judgement 要說出名字進出 authorized 時必填、否則拒收：\(judgement)")
        // b38 Z1 第 10／12 列：「必填，否則拒收」讀起來像「沒附就拒」，那由「必填」已經說了；新增的限制是**沒有名字進出卻附了**就拒——
        // 三個詞各出現一次兩種讀法都滿足，所以釘住第二句本身
        XCTAssertTrue(judgement.contains("沒進出則拒收"), "judgement 要說出沒有名字進出時附了也拒收：\(judgement)")
        // 名字分類相關的說明都不得說 fields.names 會寫「確認」（person 的整份替換不寫確認，2026-10-05 裁決第 2 點）
        let description = try XCTUnwrap(tool["description"] as? String)
        for (label, text) in [("judgement", judgement), ("description", description)] {
            XCTAssertFalse(text.contains("確認"), "\(label) 仍宣稱會寫確認：\(text)")
        }
        XCTAssertTrue(description.contains("只替進出的名字寫"), "工具描述與屬性說明同一份裁決：\(description)")
    }

    /// b38 Z1 第 2／11 列：organization `remove_names` 的報告在 MCP 面截 segments（合計至多 `removalDetailCap` 段），新的回應鍵要寫在 MCP 面
    func testOrganizationRemoveNamesSchemaNamesTheDetailKeys() throws {
        let tool = try tool("akashic_update_organization")
        let props = try XCTUnwrap((tool["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])
        let removeNames = try XCTUnwrap((props["remove_names"] as? [String: Any])?["description"] as? String)
        XCTAssertTrue(removeNames.contains("detailsTruncated") && removeNames.contains("detailsListed") && removeNames.contains("20 段"), removeNames)
    }
}
