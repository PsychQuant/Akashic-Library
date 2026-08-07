import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// End-to-end：spawn akashic-mcp binary，走 JSON-RPC over stdio
/// （initialize → tools/list → tools/call）。
final class StdioE2ETests: XCTestCase {
    var root: URL!
    var process: Process!
    var stdinPipe: Pipe!
    var stdoutPipe: Pipe!
    var reader: FileHandle!

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-e2e-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        var e1 = Entry(id: UUID(), citekey: "cheng2025identifiability", type: "article",
                       title: "Identifiability of polychoric models",
                       authors: [.literal("Che Cheng")], date: "2025")
        e1.fields["journaltitle"] = "Psychometrika"
        try store.writeEntry(e1)
        try store.writePerson(Person(key: "chen-h-y", names: ["Chen, H.-Y."]))
        try store.writePerson(Person(key: "chen-hui-yun", names: ["Chen, Hui-Yun"]))

        process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("akashic-mcp")
        process.environment = ProcessInfo.processInfo.environment
            .filter { !$0.key.hasPrefix("AKASHIC_") }   // 反查時代不與開發機 registry 耦合（#105）
            .merging(["AKASHIC_LIBRARY": root.path]) { _, new in new }
        stdinPipe = Pipe()
        stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        try process.run()
        reader = stdoutPipe.fileHandleForReading
    }

    override func tearDownWithError() throws {
        process.terminate()
        try? FileManager.default.removeItem(at: root)
    }

    private func send(_ obj: [String: Any]) throws {
        let data = try JSONSerialization.data(withJSONObject: obj)
        stdinPipe.fileHandleForWriting.write(data)
        stdinPipe.fileHandleForWriting.write(Data("\n".utf8))
    }

    /// 讀一行 JSON-RPC 回應（阻塞，10 秒 timeout）。
    private func readResponse() throws -> [String: Any] {
        var buffer = Data()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let chunk = reader.availableData
            if chunk.isEmpty {
                Thread.sleep(forTimeInterval: 0.05)
                continue
            }
            buffer.append(chunk)
            if let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
                let line = buffer[..<newline]
                return try JSONSerialization.jsonObject(with: Data(line)) as! [String: Any]
            }
        }
        XCTFail("10 秒內未收到回應")
        return [:]
    }

    func testInitializeListCall() throws {
        try send([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": [
                "protocolVersion": "2024-11-05",
                "capabilities": [:] as [String: Any],
                "clientInfo": ["name": "e2e-test", "version": "0"],
            ],
        ])
        let initResponse = try readResponse()
        let serverInfo = ((initResponse["result"] as? [String: Any])?["serverInfo"] as? [String: Any])
        XCTAssertEqual(serverInfo?["name"] as? String, "akashic-mcp")

        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])

        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let listResponse = try readResponse()
        let tools = ((listResponse["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(tools.count, 20)   // #13/#14/#18/#77 歷次擴充；#76: + akashic_divergences；#68: + akashic_update_person
        XCTAssertTrue(tools.contains { ($0["name"] as? String) == "akashic_record_divergence" })
        XCTAssertTrue(tools.contains { ($0["name"] as? String) == "akashic_divergences" })
        XCTAssertTrue(tools.contains { ($0["name"] as? String) == "akashic_search" })
        XCTAssertTrue(tools.contains { ($0["name"] as? String) == "akashic_libraries" })
        XCTAssertTrue(tools.contains { ($0["name"] as? String) == "akashic_person" })
        XCTAssertTrue(tools.contains { ($0["name"] as? String) == "akashic_files" })

        try send([
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": ["name": "akashic_search",
                       "arguments": ["journal": "Psychometrika"]],
        ])
        let callResponse = try readResponse()
        let content = ((callResponse["result"] as? [String: Any])?["content"] as? [[String: Any]]) ?? []
        let text = content.first?["text"] as? String ?? ""
        XCTAssertTrue(text.contains("cheng2025identifiability"), text)
    }

    /// #77/#133：record_divergence 的 dispatch 層煙霧——service 測試蓋不到
    /// Server.swift 的 arg 取用（schema key 改名／掉參數，service 層全綠照樣壞）。
    /// 這裡用**與 schema 一致的 key 名**（question/candidates/judgement/rests_on）
    /// 走真 binary，釘住 dispatch 的每個參數都真的被轉發。
    func testRecordDivergenceToolCallEndToEnd() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:],
                             "clientInfo": ["name": "t", "version": "0"]]])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])

        try send([
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": "akashic_record_divergence",
                       "arguments": ["question": "縮寫是否同一人",
                                     "candidates": ["chen-h-y:person", "chen-hui-yun:person"],
                                     "judgement": "同一人",
                                     "rests_on": ["https://example.org/roster"]]],
        ])
        let resp = try readResponse()
        let result = resp["result"] as? [String: Any]
        XCTAssertNotEqual(result?["isError"] as? Bool, true, "\(resp)")
        let text = ((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(text.contains("id"), text)
        XCTAssertTrue(text.contains("true"), "judgement 有被轉發（hasJudgement）：\(text)")

        // 判斷落地（judgement/rests_on 兩個 key 都真的到了 store）
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.divergences.first?.judgement?.statement, "同一人")
        XCTAssertEqual(load.divergences.first?.judgement?.restsOn, ["https://example.org/roster"])

        // #138 verify F4：akashic_divergences 不只出現在 tools/list，還要真的
        // 打得通——dispatch switch 的 case 標籤打錯字，只有實際呼叫抓得到。
        try send([
            "jsonrpc": "2.0", "id": 3, "method": "tools/call",
            "params": ["name": "akashic_divergences", "arguments": [:]],
        ])
        let listResp = try readResponse()
        let listResult = listResp["result"] as? [String: Any]
        XCTAssertNotEqual(listResult?["isError"] as? Bool, true, "\(listResp)")
        let listText = ((listResult?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(listText.contains("縮寫是否同一人"), "list 要含剛記下的 question：\(listText)")
        XCTAssertTrue(listText.contains("\"count\""), listText)
    }
}

/// #152：深度炸彈的 transport 層 regression——**必須經真 binary**（in-process
/// 測不到 transport，#148 的教訓）。
extension StdioE2ETests {
    func testDeepNestingBombGetsErrorAndServerSurvives() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:],
                             "clientInfo": ["name": "t", "version": "0"]]])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])

        // depth 300：撞毀窗口正中央（200-700）。手組 raw bytes——JSONSerialization
        // 自己也會炸深巢狀
        let bomb = String(repeating: "[", count: 300) + String(repeating: "]", count: 300)
        let msg = #"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"name":"akashic_people","arguments":{"junk":\#(bomb)}}}"#
        stdinPipe.fileHandleForWriting.write(Data((msg + "\n").utf8))

        let errResp = try readResponse()
        XCTAssertEqual(errResp["id"] as? Int, 7, "error 要回給正確的請求 id：\(errResp)")
        let error = errResp["error"] as? [String: Any]
        XCTAssertNotNil(error, "必須是 JSON-RPC error 而不是進程死亡：\(errResp)")
        XCTAssertTrue((error?["message"] as? String)?.contains("depth") == true, "\(errResp)")

        // server 存活：後續請求照常服務
        try send(["jsonrpc": "2.0", "id": 8, "method": "tools/list", "params": [:]])
        let listResp = try readResponse()
        let tools = ((listResp["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(tools.count, 20, "深度炸彈之後 server 必須照常服務：\(listResp)")
        XCTAssertTrue(process.isRunning, "進程必須存活")
    }

    /// 引號感知：字串字面量裡的括號不算深度——大量 `[` 字元的**合法字串值**
    /// 不得被誤擋。
    func testBracketsInsideStringsDoNotTripGuard() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:],
                             "clientInfo": ["name": "t", "version": "0"]]])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])

        let bracketsString = String(repeating: "[", count: 500)
        try send(["jsonrpc": "2.0", "id": 9, "method": "tools/call",
                  "params": ["name": "akashic_search",
                             "arguments": ["author": bracketsString]]])
        let resp = try readResponse()
        XCTAssertEqual(resp["id"] as? Int, 9)
        // 搜不到是正常（查詢字串怪）；重點是**不是** depth error、server 活著
        if let error = resp["error"] as? [String: Any] {
            XCTAssertFalse((error["message"] as? String)?.contains("depth") == true,
                           "字串內括號不得觸發深度守衛：\(resp)")
        }
        XCTAssertTrue(process.isRunning)
    }
}
