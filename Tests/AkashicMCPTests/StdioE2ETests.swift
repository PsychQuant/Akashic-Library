import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
import AkashicSQLite

/// End-to-end：spawn akashic-mcp binary，走 JSON-RPC over stdio
/// （initialize → tools/list → tools/call）。
final class StdioE2ETests: XCTestCase {
    var root: URL!
    var process: Process!
    var stdinPipe: Pipe!
    var stdoutPipe: Pipe!
    var reader: FileHandle!
    /// 讀到但還沒交出去的位元組：一次 read 可能拿到兩行，第二行留給下一次（#578 R1 verify）
    var pending = Data()

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
        Self.setNonBlocking(reader.fileDescriptor)
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

    /// 讀一行 JSON-RPC 回應（10 秒 timeout，逾時丟錯）。讀行只有 `readRawLine` 一份實作，這裡只解析。
    private func readResponse() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: readRawLine()) as! [String: Any]
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
        XCTAssertEqual(tools.count, 35)   // #557: + akashic_update_organization；#664: + akashic_s2；#544: + akashic_update_entry；#586: + akashic_dismiss_divergence；#13/#14/#18/#77 歷次擴充；#76: + akashic_divergences；#68: + akashic_update_person；#290: + akashic_import_wos；#304: + venue×4 + org×2；#340: + akashic_enrich_from_zotero；#458: + akashic_enrich
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
        XCTAssertEqual(tools.count, 35, "深度炸彈之後 server 必須照常服務：\(listResp)")
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

    /// #642 R1 verify（Codex）：`akashic_libraries` 的 `types`／`excluded` 是規則——`set-kind` 又是整值替換。字串型（少一層括號）
    /// 若被折成空陣列，規則就被存成比要求更寬鬆的樣子。**必須經真 binary**：陣列解析住在 server 的分派閉包裡（`argList`），
    /// 服務層測試用的是已定型的 `[String]`，覆蓋不到。整次拒絕、registry 位元組不變。
    func testStringTypedRuleArraysAreRefusedAndTheRegistryIsUntouched() throws {
        let store = LibraryStore(root: root)
        try store.writeLibrary(Library(key: "reading", name: "R", membership: .topic))
        let before = try Data(contentsOf: store.libraryURL(key: "reading"))
        try initialize()
        let types = try call(2, "akashic_libraries", ["action": "set-kind", "key": "reading", "kind": "rule",
                                                     "venue": "psychometrika", "types": "periodical-article"])
        XCTAssertTrue(types.contains("types 必須是字串陣列"), types)
        let excluded = try call(3, "akashic_libraries", ["action": "set-kind", "key": "reading", "kind": "rule",
                                                        "venue": "psychometrika", "excluded": "someone2020a"])
        XCTAssertTrue(excluded.contains("excluded 必須是字串陣列"), excluded)
        let mixed = try call(4, "akashic_libraries", ["action": "create", "key": "new-lib", "name": "N", "kind": "rule",
                                                     "venue": "psychometrika", "excluded": ["a2020a", 42]])
        XCTAssertTrue(mixed.contains("excluded 的每個元素都必須是字串"), mixed)
        XCTAssertEqual(try Data(contentsOf: store.libraryURL(key: "reading")), before, "被拒絕的 set-kind 不得動 registry 檔")
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.libraryURL(key: "new-lib").path), "被拒絕的 create 不得建檔")
    }

    /// #542 R1 verify（兩席 HIGH）：`akashic_enrich` 的 proposals item schema 宣告 `additionalProperties: false`，先前只列
    /// `sourceDigest`——照 schema 呼叫的 client 送不出 `sourceURL`／`sourceRetrieved`，三個 provenance 鍵在 MCP 面上出不來。
    func testEnrichSchemaListsEverySourceField() throws {
        try initialize()
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let r = try readResponse()
        let tools = ((r["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        let enrich = try XCTUnwrap(tools.first { $0["name"] as? String == "akashic_enrich" })
        let proposals = ((enrich["inputSchema"] as? [String: Any])?["properties"] as? [String: Any])?["proposals"] as? [String: Any]
        let item = try XCTUnwrap(proposals?["items"] as? [String: Any])
        XCTAssertEqual(item["additionalProperties"] as? Bool, false)
        let props = Set(((item["properties"] as? [String: Any]) ?? [:]).keys)
        for k in ["sourceDigest", "sourceURL", "sourceRetrieved", "sourceMediaType", "sourceStatus"] {
            XCTAssertTrue(props.contains(k), "schema 要列出 \(k)，否則照規矩的 client 送不出來：\(props.sorted())")
        }
        let desc = enrich["description"] as? String ?? ""
        XCTAssertFalse(desc.contains("只回顯進報告、不進 store"), "#517 之後為假的那句不得留在描述裡")
        XCTAssertTrue(desc.contains("provenanceWritten"), "描述要說出 payload 的 provenance 鍵")
        XCTAssertTrue(desc.contains("provenanceOmitted"), "#655：描述要說出刻意不寫的欄位在哪個鍵")
    }

    /// #610 R1 verify：`ambiguousSourceClaims` 只在非空時出現，只讀描述的 LLM 呼叫端沒有理由去檢查它——而它代表「有條目本趟被整個略過」，
    /// 重要性與 writeFailed 相當。描述要點名這個鍵。
    func testImportZoteroDescriptionNamesTheAmbiguousClaimsKey() throws {
        try initialize()
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let r = try readResponse()
        let tools = ((r["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        let tool = try XCTUnwrap(tools.first { $0["name"] as? String == "akashic_import_zotero" })
        let desc = tool["description"] as? String ?? ""
        XCTAssertTrue(desc.contains("ambiguousSourceClaims"), desc)
        XCTAssertTrue(desc.contains("writeFailed"), "既有的 writeFailed 說明不得被擠掉：\(desc)")
    }

    /// #611 R2 verify 第 11 列：f96e922a 為了擠進當時的 54,000 預算而修剪了 `akashic_import_zotero` 的說明，預算隨後調到 60,000，修剪卻留著；
    /// 被拿掉的是承重的語意——不是回應鍵（#672 的守衛只查鍵名在不在，修剪前後都綠）：`groupSize` 是什麼、`groupTooLarge` 列沒有 `other`、
    /// 「一對都不記」、DOI 相等只是提名、哪些狀態算記下／沒記下，以及 `updatedHashOnly` 的前提（Zotero 已同步）與「不宣稱原因」。
    /// MCP 呼叫端讀不到 CLI `--help`（`import-zotero` 的 abstract 只有一行），所以這些只能在說明裡。
    func testImportZoteroDescriptionStatesTheDOINominationAndHashOnlyContracts() throws {
        try initialize()
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let r = try readResponse()
        let tools = ((r["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        let tool = try XCTUnwrap(tools.first { $0["name"] as? String == "akashic_import_zotero" })
        let desc = tool["description"] as? String ?? ""
        for phrase in ["groupSize＝共用的 work 數", "不帶 other", "一對都不記", "DOI 相等只是提名",
                       "recorded／alreadyRecorded", "沒記下來的", "Zotero 已同步", "不宣稱原因"] {
            XCTAssertTrue(desc.contains(phrase), "說明少了承重的語意「\(phrase)」（MCP 呼叫端讀不到 CLI --help）：\(desc)")
        }
    }

    /// #684：`ambiguousSourceClaims` 在 MCP 面有上限——**dispatch 層真的把上限傳給服務**。service 層的測試
    /// （`ImportZoteroReportSurfaceTests`）釘住截斷本身；這裡釘住 `Server.swift` 沒有漏掉 `claimLimit:` 那個引數
    /// （漏掉的話所有 service 層測試照綠，而 MCP 面無上限）。
    func testImportZoteroCapsTheAmbiguousClaimsAtTheServer() throws {
        let limit = 20   // = `AkashicMCPServer.ambiguousClaimsLimit`；執行檔 target 測試 import 不到，這個數字是描述裡對呼叫端的承諾
        let count = limit + 2
        let zotero = try PayloadZoteroDB(dir: root, itemCount: count)
        let store = LibraryStore(root: root)
        for n in 1...count {
            for twin in ["a", "b"] {
                var e = Entry(id: UUID(), citekey: "claimed\(String(format: "%02d", n))\(twin)", type: .periodicalArticle, title: "C\(n)\(twin)")
                e.provenance = Provenance(zoteroKey: String(format: "KEYART%02d", n), zoteroVersion: 1, libraryID: 1)
                try store.writeEntry(e)
            }
        }
        try initialize()
        let text = try call(2, "akashic_import_zotero", ["zotero_db": zotero.url.path])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
        let claims = try XCTUnwrap(obj["ambiguousSourceClaims"] as? [String: [String]], text)
        XCTAssertEqual(claims.count, limit, "MCP 面截到上限")
        XCTAssertEqual(obj["ambiguousSourceClaimsTotal"] as? Int, count, "分母是完整的來源數")
        XCTAssertEqual(obj["ambiguousSourceClaimsTruncated"] as? Bool, true)
    }

    /// #696：其餘清單在 MCP 面同樣有上限——釘住 `Server.swift` 真的把 `listLimit:` 傳給服務（漏掉的話 service 層測試照綠，
    /// 而 MCP 面無上限）。一次首次匯入就是 `created` 最長的時候：整個 Zotero library 的筆數。
    func testImportZoteroCapsEveryListAtTheServer() throws {
        let limit = 20   // = `AkashicMCPServer.importListLimit`；執行檔 target 測試 import 不到，這個數字是描述裡對呼叫端的承諾
        let count = limit + 2
        let zotero = try PayloadZoteroDB(dir: root, itemCount: count)
        try initialize()
        let text = try call(2, "akashic_import_zotero", ["zotero_db": zotero.url.path])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
        XCTAssertEqual((obj["created"] as? [String])?.count, limit, "MCP 面截到上限：\(text.prefix(300))")
        XCTAssertEqual((obj["listTotals"] as? [String: Int])?["created"], count, "分母是完整的筆數：\(text.prefix(300))")
        XCTAssertEqual(obj["truncatedLists"] as? [String], ["created"])
        XCTAssertEqual(try LibraryStore(root: root).load().entries.filter { $0.provenance != nil }.count, count,
                       "上限只截報告，每一筆都寫進去（fixture 另有一筆非 Zotero 的 entry，不算）")
    }

    /// #561 R1 verify：清單以外的讀取器同一條規則——給了而型別不對（null 也算）整個呼叫拒絕。
    /// 最尖的是 `dry_run: "true"`：先前被折成 false，呼叫端要的乾跑變成真的寫入。
    func testMalformedScalarArgumentsAreRefused() throws {
        try initialize()
        let entities = root.appendingPathComponent("entities")
        func snapshot() throws -> [String: Data] {
            var out: [String: Data] = [:]
            for n in try FileManager.default.contentsOfDirectory(atPath: entities.path) {
                out[n] = try Data(contentsOf: entities.appendingPathComponent(n))
            }
            return out
        }
        let before = try snapshot()
        let dry = try call(2, "akashic_update_person", ["key": "fann", "fields": ["orcid": "0000-0002-1825-0097"], "dry_run": "true"])
        XCTAssertTrue(dry.contains("dry_run 必須是 boolean"), dry)
        let nullDry = try call(3, "akashic_import_wos", ["path": "/nonexistent.txt", "dry_run": NSNull()])
        XCTAssertTrue(nullDry.contains("dry_run 必須是 boolean"), nullDry)
        let keys = try call(4, "akashic_enrich_from_zotero", ["citekeys": ["a2020x", 42], "dry_run": true])
        XCTAssertTrue(keys.contains("citekeys 的每個元素都必須是字串"), keys)
        let libID = try call(5, "akashic_import_zotero", ["library_id": "5"])
        XCTAssertTrue(libID.contains("library_id 必須是整數"), libID)
        let str = try call(6, "akashic_set_status", ["citekey": 42, "status": "read"])
        XCTAssertTrue(str.contains("citekey 必須是字串"), str)
        let nullStr = try call(7, "akashic_set_status", ["citekey": NSNull(), "status": "read"])
        XCTAssertTrue(nullStr.contains("citekey 必須是字串"), nullStr)
        XCTAssertEqual(try snapshot(), before, "被拒絕的呼叫不得改任何記錄")
    }
}

/// #655 的 MCP 面——**經真 binary**：`date` 在來源齊備時寫 `field: date` 的 reference，`authors` 不寫而理由進
/// `provenanceOmitted`。service 層的測試（`EnrichDateProvenanceServiceTests`）釘住 payload；這裡釘住 server 的
/// 參數解析與分派沒有把新鍵弄丟。
extension StdioE2ETests {
    func testEnrichWritesDateReferenceAndNamesWhyAuthorsHaveNone() throws {
        try LibraryStore(root: root).writeEntry(Entry(id: UUID(), citekey: "anon2020x", type: .periodicalArticle, title: "Anon"))
        try initialize()
        let digest = "sha256:" + String(repeating: "b", count: 64)
        let text = try call(2, "akashic_enrich", [
            "proposals": [["citekey": "anon2020x", "date": "2020", "authors": ["Some One"], "sourceDigest": digest,
                           "sourceURL": "https://example.org/x", "sourceRetrieved": "2026-09-28", "sourceStatus": 200]],
            "include_absent_authors": true, "dry_run": false,
        ])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
        let item = try XCTUnwrap((obj["items"] as? [[String: Any]])?.first, text)
        XCTAssertEqual(item["provenanceWritten"] as? [String], ["date"], text)
        let why = try XCTUnwrap((item["provenanceOmitted"] as? [String: String])?["authors"], text)
        XCTAssertTrue(why.contains("field: authors"), why)
        let e = try XCTUnwrap(try LibraryStore(root: root).load().entries.first { $0.citekey == "anon2020x" })
        XCTAssertEqual(e.date, "2020")
        XCTAssertEqual(e.authors, [.literal("Some One")])
        XCTAssertEqual(e.references.map(\.field), ["date"], "只有 date 有來源；authors 那一格不收 enrich 的 retrieval")
    }
}

/// #695 的 MCP 面——**經真 binary**：`akashic_enrich` 的來源欄位走 #674 的 retrieval 形狀檢查（整批拒絕、具名），
/// `akashic_update_person` 與 `akashic_update_venue` 的 `references: []` 都拒絕、同一句話。service 層的測試釘住訊息；
/// 這裡釘住 server 的參數解析與分派沒有把它們吞掉（person 的 references 在 `fields` 裡、venue 的是獨立參數，兩條不同的解析）。
extension StdioE2ETests {
    func testEnrichSourceShapeAndEmptyReferencesAreRefused() throws {
        try initialize()
        let entities = root.appendingPathComponent("entities")
        func snapshot() throws -> [String: Data] {
            var out: [String: Data] = [:]
            for n in try FileManager.default.contentsOfDirectory(atPath: entities.path) {
                out[n] = try Data(contentsOf: entities.appendingPathComponent(n))
            }
            return out
        }
        let before = try snapshot()
        let enrich = try call(2, "akashic_enrich", [
            "proposals": [["citekey": "cheng2025identifiability", "fields": ["note": "n"],
                           "sourceDigest": "sha256:" + String(repeating: "b", count: 64),
                           "sourceURL": "ftp://example.org/x", "sourceRetrieved": "2026-09-30", "sourceStatus": 200]],
            "dry_run": false,
        ])
        XCTAssertTrue(enrich.contains("http／https") && enrich.contains("整批拒絕"), enrich)
        let person = try call(3, "akashic_update_person", ["key": "fann", "fields": ["references": [Any]()]])
        let venue = try call(4, "akashic_update_venue", ["key": "psychometrika", "references": [Any]()])
        XCTAssertTrue(person.contains("references 是空陣列"), person)
        XCTAssertTrue(venue.contains("references 是空陣列"), venue)
        XCTAssertEqual(try snapshot(), before, "被拒絕的呼叫不得改任何記錄")
    }
}

/// #544：`akashic_update_entry` 不帶 `dry_run` 就是乾跑。**必須經真 binary**：dispatch 的 case 標籤打錯字只有實際呼叫抓得到
/// （#138 F4 的教訓）；參數形狀錯（字串不是陣列）整個呼叫拒絕（#561 的同一條）。
extension StdioE2ETests {
    func testUpdateEntryDefaultsToDryRun() throws {
        try initialize()
        let text = try call(2, "akashic_update_entry",
                            ["citekey": "cheng2025identifiability", "remove_fields": ["journaltitle=測試：乾跑不寫"]])
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
        XCTAssertEqual(obj["dryRun"] as? Bool, true, "不帶 dry_run 就是乾跑：\(text)")
        XCTAssertEqual((obj["fieldRemovals"] as? [[String: Any]])?.first?["field"] as? String, "journaltitle", text)
        let e = try LibraryStore(root: root).load().entries.first { $0.citekey == "cheng2025identifiability" }
        XCTAssertEqual(e?.fields["journaltitle"], "Psychometrika", "磁碟不動")

        let bad = try call(3, "akashic_update_entry",
                           ["citekey": "cheng2025identifiability", "remove_fields": "journaltitle=x"])
        XCTAssertTrue(bad.contains("字串陣列"), bad)

        // #614：add_sources 接到服務（鍵名打錯的話會落到「沒有要做的事」）
        let absent = try call(4, "akashic_update_entry",
                              ["citekey": "cheng2025identifiability", "add_sources": ["sha256:" + String(repeating: "cd", count: 32)]])
        XCTAssertTrue(absent.contains("本機沒有"), absent)

        // #680：remove_zotero_sources 接到服務（鍵名打錯的話會落到「沒有要做的事」），乾跑回報告、磁碟不動
        var withSource = Entry(id: UUID(), citekey: "zsrc2025", type: .periodicalArticle, title: "T")
        withSource.provenance = Provenance(zoteroKey: "PRIM0001", zoteroVersion: 5, libraryID: 1)
        withSource.additionalProvenance = [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)]
        try LibraryStore(root: root).writeEntry(withSource)
        let zs = try call(7, "akashic_update_entry", ["citekey": "zsrc2025", "remove_zotero_sources": ["5:GRP00001=E2E：乾跑"]])
        let zsObj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(zs.utf8)) as? [String: Any], zs)
        XCTAssertEqual(zsObj["dryRun"] as? Bool, true, zs)
        XCTAssertEqual((zsObj["zoteroSourceRemovals"] as? [[String: Any]])?.first?["source"] as? String, "5:GRP00001", zs)
        let stillThere = try LibraryStore(root: root).load().entries.first { $0.citekey == "zsrc2025" }
        XCTAssertEqual(stillThere?.additionalProvenance.count, 1, "乾跑，磁碟不動")
        let notArray = try call(8, "akashic_update_entry", ["citekey": "zsrc2025", "remove_zotero_sources": "5:GRP00001=x"])
        XCTAssertTrue(notArray.contains("字串陣列"), notArray)

        // #677：remove_sources 接到服務（鍵名打錯的話會落到「沒有要做的事」）——digest 不在清單上是具名拒絕
        let notListed = try call(9, "akashic_update_entry",
                                 ["citekey": "cheng2025identifiability", "remove_sources": ["sha256:" + String(repeating: "cd", count: 32) + "=連錯了"]])
        XCTAssertTrue(notListed.contains("akashic.sources 沒有"), notListed)
        XCTAssertFalse(notListed.contains("沒有要做的事"), notListed)

        // 四條腿（remove_fields／add_sources／remove_zotero_sources／remove_sources）任兩條組合都被拒（#680／#677）：6 對，每一對都是同一個具名拒絕、磁碟不動
        let legArgs: [(String, [String])] = [
            ("remove_fields", ["journaltitle=x"]),
            ("add_sources", ["sha256:" + String(repeating: "cd", count: 32)]),
            ("remove_zotero_sources", ["5:GRP00001=x"]),
            ("remove_sources", ["sha256:" + String(repeating: "cd", count: 32) + "=x"]),
        ]
        var pairId = 20, pairsChecked = 0
        for i in legArgs.indices {
            for j in legArgs.indices where j > i {
                let out = try call(pairId, "akashic_update_entry",
                                   ["citekey": "zsrc2025", legArgs[i].0: legArgs[i].1, legArgs[j].0: legArgs[j].1, "dry_run": false])
                XCTAssertTrue(out.contains("兩兩各自單獨呼叫"), "\(legArgs[i].0)＋\(legArgs[j].0)：\(out)")
                pairId += 1; pairsChecked += 1
            }
        }
        XCTAssertEqual(pairsChecked, 6)
        let afterPairs = try LibraryStore(root: root).load().entries.first { $0.citekey == "zsrc2025" }
        XCTAssertEqual(afterPairs?.additionalProvenance.count, 1, "被拒的組合零寫入")

        // b11c R1 verify 第 42 列：缺 citekey 是缺參數，不是「找不到：citekey「」」
        let missing = try call(5, "akashic_update_entry", ["remove_fields": ["journaltitle=x"]])
        XCTAssertTrue(missing.contains("citekey 是必填參數"), missing)
        XCTAssertFalse(missing.contains("找不到"), missing)
        let blank = try call(6, "akashic_update_entry", ["citekey": "   ", "remove_fields": ["journaltitle=x"]])
        XCTAssertTrue(blank.contains("citekey 是必填參數"), blank)
    }
}

/// #578：`tools/list` 回應的位元組上限。工具清單由每個 session、每個呼叫端付費，描述每長一句都是全體的成本。
///
/// 預算的規則（#578，使用者 2026-09-27 裁決「先精簡描述再設預算」）：**精簡後實測 × 1.25，無條件進位到下一個 1,000**。
/// 2026-09-28（+08:00）量測：精簡前 56,382 bytes（32 個工具，超過單一 MCP 輸出的 48 KiB）、精簡後 39,164 bytes
/// → 39,164 × 1.25 = 48,955 → 49,000。量的是 `tools/list` 回應那一行的原始位元組（不含換行）。
/// 39,164 是補上 #670 兩個旗標的描述之前量的；`ee29fe47` 出貨時實測 39,285（照同一公式得 50,000，超過 48 KiB），
/// 當時預算維持 49,000、待使用者確認（#578 R1 verify DA）。2026-09-29 的樹（33 個工具）實測 43,021；同日 #664 加 `akashic_s2` 後（34 個工具）實測 44,451；#672 為每個工具補上回應鍵之後（33 個工具，未含 `akashic_s2`）實測 48,262（補之前 45,888）。
/// **2026-09-29（+08:00）使用者裁決：預算調高到 52,000。** 當時量到兩者合併（34 個工具）是 49,346：#672 刻意讓描述點名每一個回應鍵
/// （MCP 呼叫端讀不到 CLI help），#664 多一個工具。52,000 高於 48 KiB（49,152）——2026-09-28 的裁決刻意把預算壓在它之下；
/// 那個 48 KiB 是本 repo 對單一工具回應的上限（`candidateByteBudget`），不是 client 對 `tools/list` 的上限。沒選的兩個方案：
/// 50,000（只放得下那一輪）、維持 49,000 再精簡約 1 KB（MCP 呼叫端讀不到的契約文字會再變多）。
/// **2026-10-01（+08:00）使用者裁決：預算調高到 54,000。** 當時整合 #695／#705／#703 的 R1 修正與 #700、#710 之後實測 51,997，
/// 只剩 3 bytes；而同日裁決的三個新面（#557 的 `akashic_update_organization`、#559 的 `unauthorize`、#611 匯入報告的新鍵）估計共需約 1 KB，
/// #700 另有 `person.unknownFields`、`items[].partial` 兩個回應鍵放不進描述。沒選的兩個方案：預算不動、削既有描述騰空間（#700 的守衛要求
/// 回應鍵出現在描述裡，可削的地方有限）；新面先只做 CLI（MCP 面延到預算重裁）。
/// **2026-10-01 晚（+08:00）使用者裁決：預算調高到 60,000。** 當天整合 #564、#611 R1 修正之後實測 54,235，修剪
/// `akashic_import_zotero` 的說明後 53,939、只剩 61 bytes，同一天第三次撞上。修剪的代價是把契約細節移到 CLI `--help`，
/// 而只講 MCP 的 client 執行不了 CLI——修剪等於把契約藏到它讀不到的地方。結構性的解法另開 #713（按需讀完整說明的 MCP 工具）。
/// 沒選的兩個方案：64,000（context 成本更高）、維持 54,000 繼續修剪。
/// 描述長到撞上它時，先把契約細節移到 #713 落地後的按需說明（在那之前是 CLI `--help` 或 docs/store-format.md），不是改這個數字；要調高須回 #578 重新裁決。
extension StdioE2ETests {
    static let toolsListByteBudget = 60_000

    /// 讀一行原始回應位元組（不解析）。10 秒內讀不到整行就丟錯——空掃描不是通過。
    func readRawLine() throws -> Data {
        try Self.readLine(fd: reader.fileDescriptor, pending: &pending, timeout: 10)
    }

    enum LineReadError: Error, CustomStringConvertible {
        case timeout(received: Int), eof(received: Int), io(Int32)
        var description: String {
            switch self {
            case .timeout(let n): return "期限內未收到完整的一行回應（已收 \(n) bytes）"
            case .eof(let n): return "對端關閉，未收到完整的一行（已收 \(n) bytes）"
            case .io(let e): return "read 失敗（errno \(e)）"
            }
        }
    }

    static func setNonBlocking(_ fd: Int32) {
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
    }

    /// 從 non-blocking 的 fd 讀到一行為止（不含換行）。
    ///
    /// 不用 `FileHandle.availableData`：它對 pipe 是阻塞呼叫，子行程開著 stdout 卻不輸出時會一直等，
    /// 迴圈的期限永遠輪不到檢查（#578 R1 verify，Codex）。一次讀到的第二行留在 `pending`，下一次先交出它。
    static func readLine(fd: Int32, pending: inout Data, timeout: TimeInterval) throws -> Data {
        let deadline = Date().addingTimeInterval(timeout)
        var chunk = [UInt8](repeating: 0, count: 65_536)
        while true {
            if let newline = pending.firstIndex(of: UInt8(ascii: "\n")) {
                let line = Data(pending[pending.startIndex..<newline])
                pending = Data(pending[pending.index(after: newline)...])
                return line
            }
            let n = chunk.withUnsafeMutableBytes { read(fd, $0.baseAddress, $0.count) }
            if n > 0 { pending.append(contentsOf: chunk[0..<n]); continue }
            if n == 0 { throw LineReadError.eof(received: pending.count) }
            let err = errno
            guard err == EAGAIN || err == EWOULDBLOCK || err == EINTR else { throw LineReadError.io(err) }
            if Date() >= deadline { throw LineReadError.timeout(received: pending.count) }
            Thread.sleep(forTimeInterval: 0.02)
        }
    }

    /// 負控：子行程開著 stdout 但不輸出——讀行要在期限內以逾時結束，不是掛住。
    func testLineReaderTimesOutWhenThePeerStaysSilent() throws {
        let sleeper = Process()
        sleeper.executableURL = URL(fileURLWithPath: "/bin/sleep")
        sleeper.arguments = ["30"]
        let out = Pipe()
        sleeper.standardOutput = out
        try sleeper.run()
        defer { sleeper.terminate() }
        // 父行程的寫端關掉：讀取若退回阻塞，會在子行程結束時以 EOF 失敗，而不是永遠掛住
        try out.fileHandleForWriting.close()
        let fd = out.fileHandleForReading.fileDescriptor
        Self.setNonBlocking(fd)
        var buffer = Data()
        let started = Date()
        XCTAssertThrowsError(try Self.readLine(fd: fd, pending: &buffer, timeout: 0.5)) { error in
            guard case LineReadError.timeout = error else { return XCTFail("應是逾時：\(error)") }
        }
        XCTAssertLessThan(Date().timeIntervalSince(started), 5, "期限 0.5 秒，不得掛到子行程結束")
    }

    /// 一次 read 拿到兩行時，第二行留給下一次，不被丟掉。
    func testLineReaderKeepsTheSecondLineOfOneRead() throws {
        let printer = Process()
        printer.executableURL = URL(fileURLWithPath: "/usr/bin/printf")
        printer.arguments = ["first\\nsecond\\n"]
        let out = Pipe()
        printer.standardOutput = out
        try printer.run()
        printer.waitUntilExit()
        let fd = out.fileHandleForReading.fileDescriptor
        Self.setNonBlocking(fd)
        var buffer = Data()
        XCTAssertEqual(try Self.readLine(fd: fd, pending: &buffer, timeout: 5), Data("first".utf8))
        XCTAssertEqual(try Self.readLine(fd: fd, pending: &buffer, timeout: 5), Data("second".utf8))
    }

    func testToolsListResponseStaysWithinByteBudget() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:] as [String: Any],
                             "clientInfo": ["name": "t", "version": "1"]]])
        _ = try readRawLine()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let line = try readRawLine()
        // 先確認量到的真的是 tools/list 的回應——量錯一行（錯誤回應、別的 id）會讓上限永遠綠
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: line) as? [String: Any],
                                "tools/list 的回應不是 JSON object")
        XCTAssertEqual(obj["id"] as? Int, 2, "讀到的不是 tools/list 的回應：\(obj.keys.sorted())")
        let tools = try XCTUnwrap((obj["result"] as? [String: Any])?["tools"] as? [[String: Any]],
                                  "回應裡沒有 result.tools——沒有量到工具清單")
        XCTAssertFalse(tools.isEmpty, "工具清單是空的——空掃描不是通過")
        XCTAssertLessThanOrEqual(line.count, Self.toolsListByteBudget,
                                 "tools/list 回應 \(line.count) bytes，超過預算 \(Self.toolsListByteBudget)（#578）。"
                                 + "先精簡描述（契約細節移到 CLI --help／docs），要調高預算須回 #578 重新裁決")
    }
}

/// #587：`akashic_update_venue` 的 `references` 與帶角色的 `add_issn`、`akashic_add_venue` 帶角色的 `issn`——**必須經真 binary**：
/// `references` 的物件陣列解析住在 server 的分派閉包裡（`argObjectList`），服務層測不到它。
extension StdioE2ETests {
    func testVenueReferencesAndMediumReachTheService() throws {
        try initialize()
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        let created = try call(2, "akashic_add_venue", ["key": "ampsy", "type": "periodical",
                                                        "names": ["American Psychologist"], "issn": ["0003-066X (print)"]])
        XCTAssertTrue(created.contains("issnMediumRecorded"), created)
        let updated = try call(3, "akashic_update_venue", [
            "key": "ampsy",
            "references": [["field": "issn", "value": "0003-066X", "kind": "retrieval",
                            "url": "https://portal.issn.org/resource/ISSN/0003-066X", "retrieved": "2026-09-29",
                            "status": 200, "media_type": "text/html", "content": digest]],
        ])
        XCTAssertTrue(updated.contains("\"referencesAdded\":1") || updated.contains("\"referencesAdded\" : 1"), updated)
        let view = try call(4, "akashic_venue", ["key": "ampsy"])
        XCTAssertTrue(view.contains("\"medium\":\"print\"") || view.contains("\"medium\" : \"print\""), "回讀要帶角色：\(view)")

        let bare = try call(5, "akashic_update_venue", ["key": "ampsy", "references": "issn"])
        XCTAssertTrue(bare.contains("references 必須是物件陣列"), bare)
        let strings = try call(6, "akashic_update_venue", ["key": "ampsy", "references": ["issn"]])
        XCTAssertTrue(strings.contains("references 的每個元素都必須是物件"), strings)
        let boolStatus = try call(7, "akashic_update_venue", [
            "key": "ampsy",
            "references": [["field": "issn", "value": "0003-066X", "kind": "retrieval", "url": "https://portal.issn.org/resource/ISSN/0003-066X",
                            "retrieved": "2026-09-29", "status": true, "content": digest]],
        ])
        XCTAssertTrue(boolStatus.contains("status 必須是整數"), "JSON 的 true 經 valueToAny 是 NSNumber，不得被當成 1：\(boolStatus)")

        // #673：讀取面看得到通用 references；remove_reference 接到服務（鍵名打錯的話不會走到移除面）——store 不在 git 裡，所以停在 git 閘
        XCTAssertTrue(view.contains("\"references\"") && view.contains("portal.issn.org"), "venue 讀取面要列出通用 references：\(view)")
        let removal: [[String: Any]] = [["field": "issn", "value": "0003-066X", "reason": "r"]]
        let gated = try call(8, "akashic_update_venue", ["key": "ampsy", "remove_reference": removal])
        XCTAssertTrue(gated.contains("#673") && gated.contains("git"), "remove_reference 要走到移除面（實跑要 git 閘）：\(gated)")
        let missing = try call(9, "akashic_update_venue", ["key": "ampsy", "remove_reference": [["field": "issn", "value": "0000-0000", "reason": "r"]]])
        XCTAssertTrue(missing.contains("沒有 field「issn」 value「0000-0000」"), "定位不到要具名：\(missing)")
        let combined = try call(10, "akashic_update_venue", ["key": "ampsy", "remove_reference": removal, "add_names": ["X"]])
        XCTAssertTrue(combined.contains("單獨呼叫"), combined)
        let notObjects = try call(11, "akashic_update_venue", ["key": "ampsy", "remove_reference": ["issn"]])
        XCTAssertTrue(notObjects.contains("remove_reference 的每個元素都必須是物件"), notObjects)
    }
}

/// #675：`akashic_update_venue` 的 `edit_name_segment`——**必須經真 binary**：物件陣列的解析住在 server 的分派閉包裡（`argObjectList`），
/// JSON 的 `true` 是 NSNumber 布林、`null` 是 NSNull、整數不是字串，這幾件事服務層測不到。
extension StdioE2ETests {
    func testEditNameSegmentReachesTheService() throws {
        try initialize()
        let created = try call(2, "akashic_add_venue", ["key": "sankhya", "type": "periodical", "names": ["Sankhyā", "Sankhya Old"]])
        XCTAssertTrue(created.contains("sankhya"), created)

        // 鍵名接到服務：有變動的編輯走到 git 閘（store 不在 git 裡）；remove: true 是布林、被解析成移除而不是型別錯誤
        let set: [[String: Any]] = [["name": "Sankhyā", "set": ["start": "1933", "end": NSNull()], "reason": "r"]]
        let gated = try call(3, "akashic_update_venue", ["key": "sankhya", "edit_name_segment": set])
        XCTAssertTrue(gated.contains("#675") && gated.contains("git"), "edit_name_segment 要走到編輯面（有變動要 git 閘）：\(gated)")
        let removal: [[String: Any]] = [["name": "Sankhya Old", "remove": true, "reason": "r"]]
        let gatedRemoval = try call(4, "akashic_update_venue", ["key": "sankhya", "edit_name_segment": removal])
        XCTAssertTrue(gatedRemoval.contains("#675") && gatedRemoval.contains("git"), "remove: true 要被解析成布林：\(gatedRemoval)")

        // null 是清除：這一段本來就沒有 note，所以沒有變動——不過 git 閘、不寫
        let noop = try call(5, "akashic_update_venue", ["key": "sankhya", "edit_name_segment": [["name": "Sankhyā", "set": ["note": NSNull()], "reason": "r"]]])
        XCTAssertTrue(noop.contains("unchanged") && noop.contains("nameSegments"), "null 經 valueToAny 是 NSNull，要被讀成清除：\(noop)")

        // 型別錯誤
        let stringBool = try call(6, "akashic_update_venue", ["key": "sankhya", "edit_name_segment": [["name": "Sankhya Old", "remove": "true", "reason": "r"]]])
        XCTAssertTrue(stringBool.contains("remove 必須是布林"), "字串 \"true\" 不是 true：\(stringBool)")
        let intStart = try call(7, "akashic_update_venue", ["key": "sankhya", "edit_name_segment": [["name": "Sankhyā", "set": ["start": 1933], "reason": "r"]]])
        XCTAssertTrue(intStart.contains("必須是字串或 null"), "整數不是字串：\(intStart)")
        let notArray = try call(8, "akashic_update_venue", ["key": "sankhya", "edit_name_segment": "Sankhyā"])
        XCTAssertTrue(notArray.contains("edit_name_segment 必須是物件陣列"), notArray)
        let notObjects = try call(9, "akashic_update_venue", ["key": "sankhya", "edit_name_segment": ["Sankhyā"]])
        XCTAssertTrue(notObjects.contains("edit_name_segment 的每個元素都必須是物件"), notObjects)
        let combined = try call(10, "akashic_update_venue", ["key": "sankhya", "edit_name_segment": set, "add_names": ["X"]])
        XCTAssertTrue(combined.contains("單獨呼叫"), combined)
        let notFound = try call(11, "akashic_update_venue", ["key": "sankhya", "edit_name_segment": [["name": "No Such", "set": ["note": "n"], "reason": "r"]]])
        XCTAssertTrue(notFound.contains("沒有") && notFound.contains("Sankhya Old"), "定位不到要具名並列出現有的名字：\(notFound)")
    }
}

/// #705：寫進 `entities/`、搬移後的 legacy 拷貝沒刪掉的那一筆——工具分派的收集範圍把它附進回應。**必須經真 binary**：
/// 範圍與附上都在 `Server.swift` 的分派裡，服務層的測試（`WrittenWithLegacyCopyTests`）只能照同一個順序重演，證不到接線。
extension StdioE2ETests {
    /// legacy 檔受 git 追蹤、乾淨（寫入時會搬移它），所在目錄唯讀——刪除必然失敗。以 root 執行時造不出來，skip。
    private func lockAfterCommit(_ dir: URL) throws {
        StoreGitCommit.commitAll(root)
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let probe = dir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }
    }

    /// 成功的回應：鍵在 JSON 物件裡，不在 writeFailed。index 重建以 entities/ 那份為準、略過 legacy 拷貝（#709），所以這一格是成功回應。
    func testLegacyCopyLeftIsReportedOnTheSuccessSide() throws {
        let store = LibraryStore(root: root)
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        let p = Person(key: "yang-hau-hung", names: PersonNames(variant: ["Hau-Hung Yang"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        try lockAfterCommit(store.peopleDir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.peopleDir.path) }

        try initialize()
        let text = try call(2, "akashic_update_person", ["key": p.key, "fields": ["note": "改過"]])
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: Any]], text)
        XCTAssertEqual(rows.first?["key"] as? String, p.key)
        XCTAssertEqual(rows.first?["legacyFile"] as? String, "people/\(p.key).yaml")
        XCTAssertNil(obj["writeFailed"], text)
        XCTAssertTrue(try String(contentsOf: store.entityURL(id: p.id), encoding: .utf8).contains("改過"), "寫了")
    }

    /// 會寫既有 work／person 的工具，說明都提到這個鍵——呼叫端讀不到 CLI --help，說明沒寫就等於它不存在（#672 的立場）。
    /// 回應鍵守衛（`ToolPayloadKeyGuardTests`）看不到它：這個鍵只在 legacy 拷貝刪不掉時出現，情境造不出來。
    func testWriterToolDescriptionsNameWrittenWithLegacyCopy() throws {
        try initialize()
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = ((try readResponse()["result"] as? [String: Any])?["tools"] as? [[String: Any]]) ?? []
        let described = Set(tools.filter { ($0["description"] as? String)?.contains("writtenWithLegacyCopy") == true }
            .compactMap { $0["name"] as? String })
        let writers: Set<String> = ["akashic_libraries", "akashic_set_status", "akashic_tag", "akashic_link",
                                    "akashic_resolve_people", "akashic_update_entry", "akashic_resolve_venues",
                                    "akashic_resolve_organizations", "akashic_update_person", "akashic_import_zotero",
                                    "akashic_enrich_from_zotero", "akashic_enrich", "akashic_import_wos"]
        XCTAssertEqual(described, writers, "缺：\(writers.subtracting(described).sorted())；多：\(described.subtracting(writers).sorted())")
    }

    /// 兩筆**不同**的記錄（id 不同）共用一個 citekey——index rebuild 必然撞 UNIQUE。#709 起同一筆記錄的 legacy 拷貝不再讓重建失敗
    /// （index 以 entities/ 那份為準），要造「寫了之後別的步驟失敗」得用真的重複。
    private func breakIndexRebuild(_ store: LibraryStore) throws {
        for title in ["A", "B"] {
            try store.writeEntry(Entry(id: UUID(), citekey: "dup2020x", type: .periodicalArticle, title: title, date: "2020"))
        }
    }

    /// #709：work 留下 legacy 拷貝之後——
    /// (a) 留下它的那次寫入回成功、`writtenWithLegacyCopy` 是結構化的鍵；index 那個 id 只有一列、取 entities/ 那一份（tag 只在那一份，
    ///     之後手改 legacy 那一份的標題 index 也看不到——使用者看過的代價）；
    /// (b) 不相干記錄的寫入照常成功（先前整個 store 會重建 index 的寫入都撞 UNIQUE）；
    /// (e) 那一筆本身照舊寫不進去（#641：兩份並存，無法唯一定位）。
    func testALegacyWorkLeftoverNoLongerBreaksTheIndex() throws {
        let store = LibraryStore(root: root)
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        let e = Entry(id: UUID(), citekey: "legacy2020work", type: .periodicalArticle, title: "Legacy", date: "2020")
        let legacyURL = store.entriesDir.appendingPathComponent("\(e.citekey).yaml")
        try EntryYAML.encode(e).write(to: legacyURL, atomically: true, encoding: .utf8)
        try lockAfterCommit(store.entriesDir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path) }

        try initialize()
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                  "params": ["name": "akashic_tag", "arguments": ["citekey": e.citekey, "add": ["x"]]]])
        let tagged = try XCTUnwrap(try readResponse()["result"] as? [String: Any])
        let taggedText = try toolResultText(["result": tagged])
        XCTAssertNotEqual(tagged["isError"] as? Bool, true, "(a) 寫入呼叫回成功：\(taggedText)")
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(taggedText.utf8)) as? [String: Any], taggedText)
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: Any]], taggedText)
        XCTAssertEqual(rows.map { $0["key"] as? String }, [e.citekey])
        XCTAssertEqual(rows.first?["legacyFile"] as? String, "entries/\(e.citekey).yaml")

        // 手改 legacy 那一份（目錄唯讀、檔案本身可寫：原地寫，不經暫存檔換名）
        var edited = e
        edited.title = "Hand edit"
        try EntryYAML.encode(edited).write(to: legacyURL, atomically: false, encoding: .utf8)

        let other = try call(3, "akashic_tag", ["citekey": "cheng2025identifiability", "add": ["y"]])
        let otherObj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(other.utf8)) as? [String: Any],
                                     "(b) 不相干記錄的寫入照常成功：\(other)")
        XCTAssertNil(otherObj["writtenWithLegacyCopy"], "這一次沒有留下拷貝：\(other)")

        let db = try SQLiteDB(path: store.indexURL.path, readOnly: true)
        let indexed = try db.query("SELECT citekey, title FROM entries WHERE uuid = ?", bind: [e.id.uuidString])
        XCTAssertEqual(indexed.count, 1, "(a) 那個 id 只有一列：\(indexed)")
        XCTAssertEqual(indexed.first?["title"] as? String, "Legacy", "取 entities/ 那一份，手改 legacy 的標題 index 看不到")
        XCTAssertEqual(try db.query("SELECT tag FROM tags WHERE entry_uuid = ?", bind: [e.id.uuidString]).map { $0["tag"] as? String },
                       ["x"], "tag 只在 entities/ 那一份")

        try send(["jsonrpc": "2.0", "id": 4, "method": "tools/call",
                  "params": ["name": "akashic_tag", "arguments": ["citekey": e.citekey, "add": ["z"]]]])
        let again = try XCTUnwrap(try readResponse()["result"] as? [String: Any])
        let againText = try toolResultText(["result": again])
        XCTAssertEqual(again["isError"] as? Bool, true, "(e) 那一筆本身照舊寫不進去：\(againText)")
        XCTAssertTrue(againText.contains("無法唯一定位"), againText)
        XCTAssertFalse(try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8).contains("- z"), "沒寫")
    }

    /// 寫了之後別的步驟失敗（store 裡另有兩筆**不同**的記錄共用 citekey，tag 之後的 index rebuild 撞 UNIQUE）：錯誤回應的文字附上同一份報告。
    func testLegacyCopyLeftSurvivesALaterFailure() throws {
        let store = LibraryStore(root: root)
        try breakIndexRebuild(store)
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        let e = Entry(id: UUID(), citekey: "legacy2020work", type: .periodicalArticle, title: "Legacy", date: "2020")
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        try lockAfterCommit(store.entriesDir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path) }

        try initialize()
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                  "params": ["name": "akashic_tag", "arguments": ["citekey": e.citekey, "add": ["x"]]]])
        let result = try XCTUnwrap(try readResponse()["result"] as? [String: Any])
        let text = ((result["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        XCTAssertEqual(result["isError"] as? Bool, true, "前提：index rebuild 撞兩筆不同記錄共用的 citekey：\(text)")
        XCTAssertTrue(text.hasPrefix("writtenWithLegacyCopy"), "報告在錯誤訊息最前面（#705 R1 verify 第 5 列）：\(text)")
        XCTAssertTrue(text.contains("work「\(e.citekey)」"), text)
        XCTAssertTrue(text.contains("Error: "), "原本的錯誤接在後面：\(text)")
        XCTAssertTrue(try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8).contains("- x"), "寫了")
    }

    /// #705 R1 verify 第 1 列：`akashic_import_zotero` 的 rebuild 失敗時，報告整份嵌進錯誤訊息，而錯誤出口有上限（200 行／96 KB）——
    /// `writtenWithLegacyCopy` 每筆在 pretty JSON 裡佔七行，三十二筆（224 行）就被截掉一截，要人去刪的檔案清單不完整。現在 importer 收下的
    /// 交給分派的範圍，放在回應最前面；嵌進錯誤的 payload 不再帶（不報兩次）。#705 R2 verify 第 13 列起那一段**刻意**有上限
    /// （`writtenWithLegacyCopyLimit`，20 筆）：標題是完整筆數，多出的一行說筆數與去哪裡找（`akashic validate`）——被截是揭露過的，不是錯誤出口意外截掉。
    /// 讀回應的期限放寬到 120 秒：每一筆的 legacy 搬移都問一次 git，機器忙的時候三十幾筆會逼近預設的 10 秒。
    func testImportRebuildFailureReportsTheLegacyCopiesWithACap() throws {
        let n = 32
        let zotero = try PayloadZoteroDB(dir: root, itemCount: n)
        let store = LibraryStore(root: root)
        try breakIndexRebuild(store)   // #709 起 legacy 拷貝本身不再讓 rebuild 失敗——另放兩筆不同的記錄共用 citekey
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        var keys: [String] = []
        for i in 1...n {
            var e = Entry(id: UUID(), citekey: String(format: "legacy2025n%02d", i), type: .periodicalArticle, title: "Old \(i)", date: "2025")
            e.provenance = Provenance(zoteroKey: String(format: "KEYART%02d", i), zoteroVersion: 1, libraryID: 1)
            try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"), atomically: true, encoding: .utf8)
            keys.append(e.citekey)
        }
        try lockAfterCommit(store.entriesDir)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: store.entriesDir.path) }

        try initialize()
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/call",
                  "params": ["name": "akashic_import_zotero", "arguments": ["zotero_db": zotero.url.path]]])
        let response = try JSONSerialization.jsonObject(with: Self.readLine(fd: reader.fileDescriptor, pending: &pending, timeout: 120))
        let result = try XCTUnwrap((response as? [String: Any])?["result"] as? [String: Any])
        let text = ((result["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined(separator: "\n")
        XCTAssertEqual(result["isError"] as? Bool, true, "前提：index rebuild 撞兩筆不同記錄共用的 citekey：\(text.prefix(400))")
        let lines = text.split(separator: "\n", omittingEmptySubsequences: false)
        XCTAssertTrue(lines.first?.hasPrefix("writtenWithLegacyCopy") == true && lines.first?.hasSuffix(": \(n)") == true,
                      "報告在最前面、標題是完整筆數：\(lines.first ?? "")")
        let limit = 20   // `AkashicService.writtenWithLegacyCopyLimit`——本檔走真 binary、不 import AkashicMCPKit；常數改了這裡會紅
        XCTAssertEqual(lines.filter { $0.hasPrefix("  ⚠ work「") }.count, limit, "列前 \(limit) 筆")
        for k in keys.sorted().prefix(limit) { XCTAssertTrue(text.contains("work「\(k)」"), "\(k) 不在回應裡") }
        XCTAssertTrue(text.contains("另有 \(n - limit) 筆未列出") && text.contains("akashic validate"), "多出的一行揭露：\(text.prefix(4_000))")
        XCTAssertTrue(text.contains("Error: index rebuild 失敗"), "原本的錯誤接在後面")
        XCTAssertFalse(text.contains("\"legacyFile\""), "嵌進錯誤的 payload 不再帶這個鍵——同一筆不報兩次")
        // 三個鍵同進同出（#705 R2 verify 第 13 列）：嵌進錯誤的 payload 不再帶筆數與有沒有截——留下一個孤兒的 Total 會讓讀的人以為這份 JSON 的清單在別處
        XCTAssertFalse(text.contains("\"writtenWithLegacyCopyTotal\"") || text.contains("\"writtenWithLegacyCopyTruncated\""),
                       "三個鍵一起不在嵌進錯誤的 payload 裡")
    }
}

/// #611 R3 verify 第 1／5／8 列：`akashic_record_divergence` 撞上「同一個 id 已被另一組候選占著」時，MCP 錯誤出口逐行截 400——
/// R2 的單行訊息被截在出路之前（實測 406 字、`dismiss-divergence`／`resolve-divergence` 都不在）。**必須經真 binary**：截斷住在分派層。
extension StdioE2ETests {
    func testRecordDivergenceRefusalShowsThePathOutThroughTheMCPSink() throws {
        let a = "vanderwaals2025identifiabilityofpolychoriccorrelationmodelsundermisspecification"
        let b = "kowalczykiewicz2025estimatingthresholdsinordinalfactoranalysiswithmissingdata"
        let store = LibraryStore(root: root)
        for key in [a, a + "-renamed", b] {
            try store.writeEntry(Entry(id: UUID(), citekey: key, type: .periodicalArticle, title: key))
        }
        let id = DeterministicUUID.forDivergence(candidateKeys: [a, b])
        _ = try store.writeDivergence(Divergence(id: id, question: "已改名的一組",
                                                 candidates: [a + "-renamed", b].map { DivergenceCandidate(key: $0, shape: .work) }))
        try initialize()
        let text = try call(2, "akashic_record_divergence", ["question": "又一次", "candidates": ["\(a):work", "\(b):work"]])
        XCTAssertTrue(text.contains("akashic dismiss-divergence \(id.uuidString) --reason"), "出路要在 MCP 回應裡：\(text)")
        XCTAssertTrue(text.contains("akashic_dismiss_divergence"), "MCP 呼叫端可用的那個工具：\(text)")
        XCTAssertTrue(text.contains("resolve-divergence"), text)
        XCTAssertFalse(text.contains("（已截斷）"), "每一行都在 400 之內：\(text)")
    }
}

/// #705 第三次 verify（LOW 17、INFO 24）：十三份說明共用的一句（`Server.legacyCopyNote`）以「鍵名加 Total／加 NotApplied」指名兩個附屬的鍵，
/// 完整鍵名不在任何說明裡。這裡從真 binary 的 tools/list 釘住：帶這一句的說明恰十三份、每份都有那兩個組字；組出來的鍵名對得上常數由
/// `LegacyCopyNoteKeyTests` 釘住。先前只有位元組預算的測試，改掉這一句或改名一個鍵都不會紅。
extension StdioE2ETests {
    func testTheSharedLegacyCopyNoteNamesBothCompanionKeys() throws {
        try initialize()
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: try readRawLine()) as? [String: Any])
        let tools = try XCTUnwrap((obj["result"] as? [String: Any])?["tools"] as? [[String: Any]], "\(obj.keys.sorted())")
        let carrying = tools.compactMap { $0["description"] as? String }.filter { $0.contains("列在 writtenWithLegacyCopy（") }
        XCTAssertEqual(carrying.count, 13, "帶共用那一句的說明數")
        for d in carrying {
            XCTAssertTrue(d.contains("鍵名加 Total＝總數") && d.contains("加 NotApplied＝"), d)
        }
    }
}
