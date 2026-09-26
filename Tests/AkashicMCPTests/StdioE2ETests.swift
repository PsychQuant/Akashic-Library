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
        var e1 = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
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
        // #632：真 binary 握手回報的版號等於 mcpb/manifest.json（發布版號的正典），不是寫死的舊值
        let repo = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let manifest = try JSONSerialization.jsonObject(with: Data(contentsOf: repo.appendingPathComponent("mcpb/manifest.json"))) as? [String: Any]
        XCTAssertEqual(serverInfo?["version"] as? String, manifest?["version"] as? String)

        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])

        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let listResponse = try readResponse()
        let tools = ((listResponse["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        XCTAssertEqual(tools.count, 31)   // #13/#14/#18/#77 歷次擴充；#76: + akashic_divergences；#68: + akashic_update_person；#290: + akashic_import_wos；#304: + venue×4 + org×2；#340: + akashic_enrich_from_zotero；#458: + akashic_enrich
        XCTAssertTrue(tools.contains { ($0["name"] as? String) == "akashic_enrich" })
        XCTAssertTrue(tools.contains { ($0["name"] as? String) == "akashic_record_divergence" })
        XCTAssertTrue(tools.contains { ($0["name"] as? String) == "akashic_import_wos" })
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
    /// `akashic_resolve_people` 的 judge 參數真的暴露在 schema 上（#386）。
    ///
    /// **工具數刻意不變**——判定是既有 tool 的新參數，不是新 tool。所以工具數斷言擋不住
    /// 「參數忘了註冊」這個失敗；這條補上那一格。
    func testResolvePeopleExposesTheJudgeParameter() throws {
        try send([
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": ["protocolVersion": "2024-11-05",
                       "capabilities": [:] as [String: Any],
                       "clientInfo": ["name": "e2e-test", "version": "0"]],
        ])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let listResp = try readResponse()
        guard let result = listResp["result"] as? [String: Any],
              let tools = result["tools"] as? [[String: Any]],
              let rp = tools.first(where: { $0["name"] as? String == "akashic_resolve_people" })
        else { return XCTFail("找不到 akashic_resolve_people：\(listResp)") }
        let props = ((rp["inputSchema"] as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
        XCTAssertNotNil(props["judge"],
                        "judge 參數未暴露——CLI 有而 MCP 沒有就是 mcp-cli-parity 說的"
                        + "「缺口安靜累積」。實際參數：\(props.keys.sorted())")
        let desc = ((props["judge"] as? [String: Any])?["description"] as? String) ?? ""
        XCTAssertTrue(desc.contains("歧義"),
                      "描述必須說明歧義列也適用——那正是本參數存在的理由：\(desc)")
    }

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
                                     "rests_on": ["sha256:d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4"]]],
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
        XCTAssertEqual(load.divergences.first?.judgement?.restsOn, ["sha256:d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4"])

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
        XCTAssertEqual(tools.count, 31, "深度炸彈之後 server 必須照常服務：\(listResp)")
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

/// #162：**MCP 的 per-tool 錯誤出口**必須消毒——走真 binary、真 stdio。
///
/// CLI 早有單一消毒出口，而且那是明寫的裁決（`CLI.swift`：「逐條補 error 站點是
/// 假性閉合——新增的 case 又會裸奔」）。**MCP 從沒拿到同樣處置**：`Main.swift`
/// 消毒了啟動錯誤，`Server.swift` 的 per-tool catch 沒有。
///
/// 後果是全面的：`StoreYAMLError.invalidField` 的 `errorDescription` **刻意不消毒**
/// payload（它自帶的 exempt 註解寫明策略是 sink-side，並承認「約 50 個跨行 throw
/// 站點未消毒，靠 sink 兜底」）。缺了這個 sink，那些站點的 payload——檔案裡的未知
/// 欄位名、YAML 鍵、值原文——逐字進 LLM context。
///
/// **必須走真 binary**：在測試裡重建 `let message = errorDescription ?? "\(error)"`
/// 再自己包 `displaySafeMultiline` 是同義反覆——它會綠，但證明不了 `Server.swift`
/// 那一行真的呼叫了它（#171 verify 171-1 的教訓）。
extension StdioE2ETests {
    func testToolErrorPayloadIsSanitisedAtTheMCPExit() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:],
                             "clientInfo": ["name": "t", "version": "1"]]])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])

        let hostile = "ev\u{1B}[31m\u{202E}il"

        // **這條才是本 change 的主論證**（#162 verify 182-1）：一條**實際可達**的
        // `StoreYAMLError` 折行 throw 站點。`update_person` 的未知維度名經
        // `YAML.swift` 的 `throw StoreYAMLError.invalidField("person.profile",
        // "不認得的維度「\(name)」…")`（折行、payload 全裸）→ `errorDescription`
        // 依政策不消毒 → MCP 的 per-tool catch。
        //
        // 先前這裡用 `akashic_get_entry` 餵敵意 citekey——那是**同義反覆**：
        // `ServiceError.notFound` 早在 throw 站點就 `displaySafe` 了，有沒有本
        // change 的修法都不含 raw ESC。席位實測：只還原 catch 的消毒（保留
        // `Unknown tool` 那處）→ **1029 條全綠**，主論證零回歸測試。
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                  "params": ["name": "akashic_update_person",
                             "arguments": ["key": "chen-h-y",
                                           "fields": ["profile": [hostile: []]],
                                           "dry_run": true]]])
        // **取出真正的字串，不要 `String(describing:)`**（#162 verify 182-4）。
        //
        // 對 JSON 反序列化出來的 `NSDictionary`，`String(describing:)` 會把所有
        // 非 ASCII scalar 逐一跳脫成 `\Uxxxx`——於是兩條 `contains("\u{202E}")`
        // **結構上不可能失敗**（席位實測：payload 換成只有 RLO、還原 catch 的消毒
        // → 測試照樣通過），整條由 ESC（ASCII，不被跳脫）單獨扛著。
        //
        // 更糟的是「有沒有走到那條路徑」的護欄也是空的：`contains("不認得的維度")`
        // 恆 false，於是 `|| contains("Error")` 被後者滿足——**任何**錯誤回應都過。
        // fixture 的 person key 一旦改名，這條測試會安靜退回成它剛取代掉的那個
        // 同義反覆，而且沒有訊號。
        let text = try toolResultText(try readResponse())
        XCTAssertTrue(text.contains("不認得的維度"),
                      "必要條件，不能與「Error」做 `||`——那會讓任何錯誤回應都過：\(text.prefix(300))")
        XCTAssertFalse(text.contains("\u{1B}"), "raw ESC 抵達 tool result（進 LLM context）")
        XCTAssertFalse(text.contains("\u{202E}"), "raw U+202E 抵達 tool result")

        // 未知 tool 名同理——它也是 caller 給的字串
        try send(["jsonrpc": "2.0", "id": 3, "method": "tools/call",
                  "params": ["name": "akashic_\(hostile)", "arguments": [:]]])
        let text2 = try toolResultText(try readResponse())
        XCTAssertTrue(text2.contains("Unknown tool"), "要走到那條路徑：\(text2.prefix(200))")
        XCTAssertFalse(text2.contains("\u{1B}"), "Unknown tool 的名字也要消毒")
        XCTAssertFalse(text2.contains("\u{202E}"), "同上")
    }

    /// 從 JSON-RPC 回應取出 `result.content[0].text` 的**真字串**。
    ///
    /// `String(describing:)` 對 `NSDictionary` 會跳脫非 ASCII，讓所有針對 bidi／
    /// LS-PS 的斷言變成裝飾（#162 verify 182-4）。
    private func toolResultText(_ resp: [String: Any]) throws -> String {
        let result = try XCTUnwrap(resp["result"] as? [String: Any],
                                   "回應沒有 result：\(resp)")
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        return content.compactMap { $0["text"] as? String }.joined(separator: "\n")
    }
}

/// #458：generic add-only 補值的 MCP 面——**必須經真 binary**（dispatch 的 case 標籤打錯字只有
/// 實際呼叫抓得到，#138 F4 的教訓）。spec「MCP dry run is the default」：不帶 `dry_run` 就是乾跑。
extension StdioE2ETests {
    func testEnrichToolDefaultsToDryRun() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:],
                             "clientInfo": ["name": "t", "version": "0"]]])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])

        try send([
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": "akashic_enrich",
                       "arguments": ["proposals": [
                           ["citekey": "cheng2025identifiability",
                            "fields": ["abstract": "An abstract", "abstract-es": "Un resumen"],
                            "source_digest": "sha256:e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5"],
                       ]]],
        ])
        let resp = try readResponse()
        let result = resp["result"] as? [String: Any]
        XCTAssertNotEqual(result?["isError"] as? Bool, true, "\(resp)")
        let text = ((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
        XCTAssertEqual(obj["dryRun"] as? Bool, true, "不帶 dry_run 就是乾跑：\(text)")
        let items = try XCTUnwrap(obj["items"] as? [[String: Any]])
        XCTAssertEqual(items.first?["category"] as? String, "added")
        XCTAssertEqual(items.first?["sourceDigest"] as? String,
                       "sha256:e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5", "digest 回顯（snake_case 也收）")
        let keys = (items.first?["additions"] as? [[String: Any]])?.compactMap { $0["key"] as? String } ?? []
        XCTAssertEqual(keys, ["abstract", "abstract_es"], "雙摘要分鍵，經 FieldKey.normalized：\(text)")

        // 磁碟不動
        let e = try LibraryStore(root: root).load().entries.first { $0.citekey == "cheng2025identifiability" }
        XCTAssertNil(e?.fields["abstract"])
        XCTAssertTrue(e?.references.isEmpty ?? false, "digest 不進 references")
    }

    /// 頂層打錯位置的欄位（`abstract` 不在 `fields` 裡）要被拒絕，不是靜默略過後回「補了」。
    func testEnrichRejectsUnknownTopLevelKeys() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:],
                             "clientInfo": ["name": "t", "version": "0"]]])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        try send([
            "jsonrpc": "2.0", "id": 2, "method": "tools/call",
            "params": ["name": "akashic_enrich",
                       "arguments": ["proposals": [["citekey": "cheng2025identifiability", "abstract": "misplaced"]]]],
        ])
        let resp = try readResponse()
        let result = resp["result"] as? [String: Any]
        XCTAssertEqual(result?["isError"] as? Bool, true, "\(resp)")
        let text = ((result?["content"] as? [[String: Any]])?.first?["text"] as? String) ?? ""
        XCTAssertTrue(text.contains("abstract") && text.contains("fields"), text)
    }
}

/// #561：畸形的清單／物件參數整個呼叫拒絕，不靜默當成未提供。先前 `authorize: "X"`（少一層括號）折成 `[]`、
/// 零寫入、回報成功；`["A", 42]` 掉成 `["A"]`；`fields: {"year": 2020}` 的數字值被靜默丟掉。**必須經真 binary**：
/// 參數解析住在 server 的分派閉包裡。
extension StdioE2ETests {
    private func initialize() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:],
                             "clientInfo": ["name": "t", "version": "1"]]])
        _ = try readResponse()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }

    private func call(_ id: Int, _ name: String, _ args: [String: Any]) throws -> String {
        try send(["jsonrpc": "2.0", "id": id, "method": "tools/call",
                  "params": ["name": name, "arguments": args]])
        return try toolResultText(try readResponse())
    }

    func testMalformedListAndDictArgumentsAreRefused() throws {
        try initialize()
        let bare = try call(2, "akashic_update_venue", ["key": "psychometrika", "authorize": "Psychometrika"])
        XCTAssertTrue(bare.contains("authorize 必須是字串陣列"), bare)
        let mixed = try call(3, "akashic_update_venue", ["key": "psychometrika", "add_issn": ["0033-3123", 42]])
        XCTAssertTrue(mixed.contains("add_issn 的每個元素都必須是字串"), mixed)
        let newVenue = try call(4, "akashic_add_venue", ["key": "new-journal", "type": "periodical",
                                                         "names": ["New Journal"], "issn": "0033-3123"])
        XCTAssertTrue(newVenue.contains("issn 必須是字串陣列"), newVenue)
        let entities = root.appendingPathComponent("entities")
        let created = try FileManager.default.contentsOfDirectory(atPath: entities.path).contains { name in
            ((try? String(contentsOf: entities.appendingPathComponent(name), encoding: .utf8)) ?? "").contains("key: new-journal")
        }
        XCTAssertFalse(created, "被拒絕的 add_venue 不得建出記錄")
        let fields = try call(5, "akashic_create_entry", ["type": "periodical-article", "title": "T",
                                                          "authors": ["Cheng, C."], "date": "2020",
                                                          "fields": ["volume": 12]])
        XCTAssertTrue(fields.contains("fields 的值都必須是字串"), fields)
        XCTAssertTrue(fields.contains("volume"), "要點名是哪個鍵：\(fields)")
    }
}
