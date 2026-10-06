import Foundation
import Network
import XCTest

/// 只聽 127.0.0.1 的假 S2 伺服器（綁 loopback，不觸發防火牆提示）。記錄每個請求的
/// 方法、目標、header 與送達時間；回應由 `handler` 決定。只處理不帶 body 的請求。
final class LoopbackS2Server: @unchecked Sendable {
    struct Seen { let method: String; let target: String; let headers: [String: String]; let at: Date }
    typealias Handler = @Sendable (_ method: String, _ target: String) -> (status: Int, headers: [String: String], body: Data)

    private let listener: NWListener
    private let queue = DispatchQueue(label: "loopback-s2-server")
    private let lock = NSLock()
    private var _seen: [Seen] = []
    private let handler: Handler
    let port: UInt16

    init(handler: @escaping Handler) throws {
        self.handler = handler
        let params = NWParameters.tcp
        params.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: params)
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            switch state { case .ready, .failed, .cancelled: ready.signal(); default: break }
        }
        let box = WeakBox()
        listener.newConnectionHandler = { conn in box.server?.serve(conn) }
        listener.start(queue: queue)
        _ = ready.wait(timeout: .now() + 5)
        guard let p = listener.port?.rawValue, p != 0 else { throw URLError(.cannotConnectToHost) }
        port = p
        box.server = self
    }

    final class WeakBox: @unchecked Sendable { weak var server: LoopbackS2Server? }

    var baseURL: String { "http://127.0.0.1:\(port)" }
    var seen: [Seen] { lock.lock(); defer { lock.unlock() }; return _seen }
    func stop() { listener.cancel() }

    private func serve(_ conn: NWConnection) {
        conn.start(queue: queue)
        receive(conn, buffer: Data())
    }

    private func receive(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [self] data, _, isComplete, error in
            var buf = buffer
            if let data { buf.append(data) }
            if let end = buf.range(of: Data("\r\n\r\n".utf8)) {
                respond(conn, head: String(decoding: buf[..<end.lowerBound], as: UTF8.self))
            } else if isComplete || error != nil {
                conn.cancel()
            } else {
                receive(conn, buffer: buf)
            }
        }
    }

    private func respond(_ conn: NWConnection, head: String) {
        let lines = head.components(separatedBy: "\r\n")
        let parts = (lines.first ?? "").split(separator: " ").map(String.init)
        let method = parts.first ?? "", target = parts.count > 1 ? parts[1] : ""
        var headers: [String: String] = [:]
        for line in lines.dropFirst() {
            guard let i = line.firstIndex(of: ":") else { continue }
            headers[line[..<i].lowercased()] = line[line.index(after: i)...].trimmingCharacters(in: .whitespaces)
        }
        lock.lock(); _seen.append(Seen(method: method, target: target, headers: headers, at: Date())); lock.unlock()
        let (status, extra, body) = handler(method, target)
        var head = "HTTP/1.1 \(status) Stub\r\nContent-Type: application/json\r\nContent-Length: \(body.count)\r\nConnection: close\r\n"
        for (k, v) in extra { head += "\(k): \(v)\r\n" }
        var out = Data((head + "\r\n").utf8)
        out.append(body)
        conn.send(content: out, completion: .contentProcessed { _ in conn.cancel() })
    }
}

/// 參考文獻的假回應：每頁最多 100 筆，總數 `count`；非 references 的請求回 referenceCount。
func referencesStub(count: Int) -> LoopbackS2Server.Handler {
    { _, target in
        func json(_ o: Any) -> Data { try! JSONSerialization.data(withJSONObject: o) }
        let comps = URLComponents(string: "http://x" + target)!
        func q(_ n: String) -> Int? { comps.queryItems?.first { $0.name == n }?.value.flatMap(Int.init) }
        if comps.path.hasSuffix("/references") {
            let offset = q("offset") ?? 0, limit = q("limit") ?? 100
            let end = min(count, offset + min(limit, 100))
            let data = (offset..<end).map { i -> [String: Any] in
                ["citedPaper": ["paperId": "p\(i)", "title": "Title \(i)", "year": 2000 + i % 20,
                                "authors": [["name": "Author \(i)"]]]]
            }
            var body: [String: Any] = ["offset": offset, "data": data]
            if end < count { body["next"] = end }
            return (200, [:], json(body))
        }
        return (200, [:], json(["paperId": "seed", "referenceCount": count]))
    }
}

/// #664 任務 5.1：`akashic s2` 子命令群。一律不碰真的 keychain、不連真的 S2：
/// 成功路徑走 loopback（不讀 keychain），缺金鑰路徑用 `akashic-test-` 開頭的 service。
final class S2CommandTests: XCTestCase {
    private var stateDir: String!

    override func setUpWithError() throws {
        stateDir = NSTemporaryDirectory() + "s2-cli-\(UUID().uuidString)"
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: stateDir) }

    private func env(_ extra: [String: String] = [:]) -> [String: String] {
        ["AKASHIC_S2_STATE_DIR": stateDir,
         "AKASHIC_S2_KEYCHAIN_SERVICE": "akashic-test-\(UUID().uuidString)"].merging(extra) { $1 }
    }

    private func json(_ output: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(output.utf8)) as? [String: Any], output)
    }

    /// spec Scenario「A user without a key looks up a paper」。
    func testMissingKeyExitsThreeWithSetupGuidance() throws {
        let service = "akashic-test-\(UUID().uuidString)"
        let r = try CLITestHarness.run(["s2", "paper", "DOI:10.1037/a0038889"],
                                       env: ["AKASHIC_S2_STATE_DIR": stateDir, "AKASHIC_S2_KEYCHAIN_SERVICE": service])
        XCTAssertEqual(r.status, 3, r.output)
        XCTAssertTrue(r.output.contains(service), r.output)
        XCTAssertTrue(r.output.contains("default"), r.output)
        XCTAssertTrue(r.output.contains("semantic-scholar.md"), r.output)
    }

    /// harness 的保險：沒指定 keychain service 的 `s2` 呼叫一律補上 akashic-test-harness。
    func testHarnessInjectsATestServiceWhenNoneIsGiven() throws {
        let r = try CLITestHarness.run(["s2", "status", "--json"], env: ["AKASHIC_S2_STATE_DIR": stateDir])
        XCTAssertEqual(r.status, 3, r.output)
        let keychain = try XCTUnwrap(try json(r.output)["keychain"] as? [String: Any])
        XCTAssertEqual(keychain["service"] as? String, "akashic-test-harness")
        XCTAssertEqual(keychain["account"] as? String, "default")
        XCTAssertEqual(keychain["present"] as? Bool, false)
        XCTAssertEqual(keychain["readable"] as? Bool, false)
        XCTAssertEqual(try json(r.output)["host"] as? String, "api.semanticscholar.org")
    }

    /// spec Scenario「A limit caps the records」＋ loopback 不帶金鑰。
    func testReferencesThroughLoopbackRespectLimitAndCarryNoKey() throws {
        let server = try LoopbackS2Server(handler: referencesStub(count: 1000))
        defer { server.stop() }
        let r = try CLITestHarness.run(["s2", "references", "DOI:10.1/x", "--limit", "50", "--json"],
                                       env: env(["AKASHIC_S2_BASE_URL": server.baseURL]))
        XCTAssertEqual(r.status, 0, r.output)
        let out = try json(r.output)
        XCTAssertEqual(out["source"] as? String, "semantic-scholar")
        XCTAssertEqual(out["endpoint"] as? String, "references")
        XCTAssertEqual((out["data"] as? [Any])?.count, 50)
        XCTAssertEqual(out["total"] as? Int, 1000)
        let fetchedAt = try XCTUnwrap(out["fetchedAt"] as? String)
        XCTAssertNotNil(fetchedAt.range(of: #"T\d\d:\d\d:\d\d([+-]\d\d:\d\d|Z)$"#, options: .regularExpression), fetchedAt)
        XCTAssertFalse(server.seen.isEmpty)
        XCTAssertTrue(server.seen.allSatisfy { $0.headers["x-api-key"] == nil })
    }

    func testHumanReadableFormListsOneLinePerRecord() throws {
        let server = try LoopbackS2Server(handler: referencesStub(count: 3))
        defer { server.stop() }
        let r = try CLITestHarness.run(["s2", "references", "DOI:10.1/x"],
                                       env: env(["AKASHIC_S2_BASE_URL": server.baseURL]))
        XCTAssertEqual(r.status, 0, r.output)
        for i in 0..<3 {
            XCTAssertTrue(r.output.contains("Title \(i)"), r.output)
            XCTAssertTrue(r.output.contains("Author \(i)"), r.output)
        }
    }

    /// spec Scenario「An unknown identifier」。
    func testNotFoundExitsFiveNamingTheIdentifier() throws {
        let server = try LoopbackS2Server { _, _ in (404, [:], Data("{\"error\":\"Paper not found\"}".utf8)) }
        defer { server.stop() }
        let r = try CLITestHarness.run(["s2", "paper", "DOI:10.0000/none"],
                                       env: env(["AKASHIC_S2_BASE_URL": server.baseURL]))
        XCTAssertEqual(r.status, 5, r.output)
        XCTAssertTrue(r.output.contains("DOI:10.0000/none"), r.output)
    }

    /// spec Example「Retry budget」最後一列：Retry-After 120 → 4，不等。
    func testRetryAfterBeyondSixtySecondsExitsFour() throws {
        let server = try LoopbackS2Server { _, _ in (429, ["Retry-After": "120"], Data()) }
        defer { server.stop() }
        let r = try CLITestHarness.run(["s2", "paper", "DOI:10.1/x"],
                                       env: env(["AKASHIC_S2_BASE_URL": server.baseURL]))
        XCTAssertEqual(r.status, 4, r.output)
        XCTAssertEqual(server.seen.count, 1)
    }

    /// #664 任務 5.2：兩個程序共用同一個狀態目錄、各送 3 個請求——6 個送達時間兩兩間隔
    /// 至少 1 秒（容許 50 ms）。author-search 不另查 total，每頁 1 筆＋`--limit 3` 恰為 3 個請求。
    /// #701：這個間隔由節流在鎖內比對上一次的實際放行來保證。先前只由預約保證，前一個程序晚醒時量到過 0.92 秒。
    func testTwoProcessesShareTheOneRequestPerSecondBudget() throws {
        let server = try LoopbackS2Server { _, target in
            let comps = URLComponents(string: "http://x" + target)!
            let offset = comps.queryItems?.first { $0.name == "offset" }?.value.flatMap(Int.init) ?? 0
            let body: [String: Any] = ["total": 100, "offset": offset, "next": offset + 1,
                                       "data": [["authorId": "a\(offset)", "name": "N\(offset)"]]]
            return (200, [:], try! JSONSerialization.data(withJSONObject: body))
        }
        defer { server.stop() }
        let shared = env(["AKASHIC_S2_BASE_URL": server.baseURL])
        let statuses = ThreadSafeStatuses()
        DispatchQueue.concurrentPerform(iterations: 2) { i in
            let r = try? CLITestHarness.run(["s2", "author-search", "--name", "Lane \(i)", "--limit", "3"], env: shared)
            statuses.append(r?.status ?? -1)
        }
        XCTAssertEqual(statuses.values.sorted(), [0, 0])
        let times = server.seen.map(\.at).sorted()
        XCTAssertEqual(times.count, 6)
        for (a, b) in zip(times, times.dropFirst()) {
            XCTAssertGreaterThanOrEqual(b.timeIntervalSince(a), 1.0 - 0.05, "\(times)")
        }
    }

    /// spec Scenario「A base URL pointing elsewhere is refused」：環境變數不是 argv（#549），回 1。
    func testBaseURLOutsideLoopbackExitsOne() throws {
        let r = try CLITestHarness.run(["s2", "paper", "DOI:10.1/x"],
                                       env: env(["AKASHIC_S2_BASE_URL": "https://example.org"]))
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("AKASHIC_S2_BASE_URL"), r.output)
    }

    /// 只看 argv 判得出的錯誤在 validate() 回 64（#549）：--limit 0、識別碼含 .. 路徑片段。
    func testArgvErrorsExit64() throws {
        let limit = try CLITestHarness.run(["s2", "references", "DOI:10.1/x", "--limit", "0"], env: env())
        XCTAssertEqual(limit.status, 64, limit.output)
        let dots = try CLITestHarness.run(["s2", "paper", "../../author/1"], env: env())
        XCTAssertEqual(dots.status, 64, dots.output)
        let rec = try CLITestHarness.run(["s2", "recommend", "DOI:10.1/x", "--limit", "501"], env: env())
        XCTAssertEqual(rec.status, 64, rec.output)
    }

    /// 空白的 `--title`／`--name` 只看 argv 就判得出（#549），所以是 64，不是讀完才發現的 1（#664 verify R1 第 16 列）。
    func testBlankTitleOrNameExit64() throws {
        for args in [["s2", "match", "--title", ""], ["s2", "match", "--title", "   "],
                     ["s2", "author-search", "--name", ""], ["s2", "author-search", "--name", "  "]] {
            let r = try CLITestHarness.run(args, env: env())
            XCTAssertEqual(r.status, 64, "\(args)：\(r.output)")
        }
    }

    /// 金鑰不得落盤（#664 verify R1 第 1 列）：預設連線若帶 `URLCache`，每個 GET 都會在
    /// `~/Library/Caches/akashic/Cache.db` 留下一筆（含請求 header）。跑一次查詢，前後那個檔不得有任何變動。
    func testARunLeavesNoCacheFileBehind() throws {
        let caches = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Library/Caches/akashic")
        func fingerprint() -> String {
            ["Cache.db", "Cache.db-wal", "Cache.db-shm", "fsCachedData"].map { name -> String in
                let attrs = try? FileManager.default.attributesOfItem(atPath: caches.appendingPathComponent(name).path)
                return "\(name):\((attrs?[.size] as? Int).map(String.init) ?? "-"):\((attrs?[.modificationDate] as? Date)?.timeIntervalSince1970 ?? 0)"
            }.joined(separator: "|")
        }
        let before = fingerprint()
        let server = try LoopbackS2Server(handler: referencesStub(count: 5))
        defer { server.stop() }
        let r = try CLITestHarness.run(["s2", "references", "DOI:10.1/x", "--json"],
                                       env: env(["AKASHIC_S2_BASE_URL": server.baseURL]))
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertFalse(server.seen.isEmpty)
        XCTAssertEqual(fingerprint(), before, "查詢不得動到 URLCache 的檔案")
    }

    /// `--ids-file` 的內容是要 POST 給第三方的：不像識別碼的行（含空白）在送出任何請求之前就拒絕（#664 verify R1 第 24 列）。
    func testBatchRefusesLinesThatDoNotLookLikeIdentifiersBeforeSendingAnything() throws {
        let server = try LoopbackS2Server { _, _ in (200, [:], Data("[]".utf8)) }
        defer { server.stop() }
        let file = NSTemporaryDirectory() + "ids-\(UUID().uuidString).txt"
        try "DOI:10.1/ok\nthis is not an identifier, it is a sentence\n".write(toFile: file, atomically: true, encoding: .utf8)
        defer { try? FileManager.default.removeItem(atPath: file) }
        let r = try CLITestHarness.run(["s2", "batch", "--ids-file", file], env: env(["AKASHIC_S2_BASE_URL": server.baseURL]))
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(server.seen.isEmpty, "不得送出任何請求")
    }

    func testBatchRefusesAHugeIdsFileWithoutReadingItAll() throws {
        let file = NSTemporaryDirectory() + "ids-big-\(UUID().uuidString).txt"
        try String(repeating: "DOI:10.1/x\n", count: 40_000).write(toFile: file, atomically: true, encoding: .utf8)   // ≈ 440 KB
        defer { try? FileManager.default.removeItem(atPath: file) }
        let r = try CLITestHarness.run(["s2", "batch", "--ids-file", file], env: env())
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("256 KiB"), r.output)
    }
}

final class ThreadSafeStatuses: @unchecked Sendable {
    private let lock = NSLock()
    private var _values: [Int32] = []
    var values: [Int32] { lock.lock(); defer { lock.unlock() }; return _values }
    func append(_ v: Int32) { lock.lock(); _values.append(v); lock.unlock() }
}
