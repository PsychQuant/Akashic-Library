import XCTest
@testable import AkashicS2
@testable import AkashicStoreIO

/// 攔截請求的 URLProtocol（本 target 自用；AkashicS2Tests 那份在別的模組）。
final class S2ToolStub: URLProtocol {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var handler: ((URLRequest) -> (Int, Data))?
    nonisolated(unsafe) private static var _count = 0
    static func install(_ h: @escaping (URLRequest) -> (Int, Data)) { lock.lock(); handler = h; _count = 0; lock.unlock() }
    static var count: Int { lock.lock(); defer { lock.unlock() }; return _count }
    static func session() -> URLSession {
        let c = URLSessionConfiguration.ephemeral
        c.protocolClasses = [S2ToolStub.self]
        return URLSession(configuration: c)
    }
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.lock.lock(); Self._count += 1; let h = Self.handler; Self.lock.unlock()
        let (status, body) = h?(request) ?? (599, Data())
        client?.urlProtocol(self, didReceive: HTTPURLResponse(url: request.url!, statusCode: status, httpVersion: nil, headerFields: nil)!,
                            cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

/// #664 任務 6.1：MCP 面（design「MCP 面的 async 路徑」與「兩個面都做，MCP 面有位元組上限」）。
final class S2ToolTests: XCTestCase {
    private var stateDir: String!
    override func setUpWithError() throws { stateDir = NSTemporaryDirectory() + "s2-tool-\(UUID().uuidString)" }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(atPath: stateDir) }

    private func env(_ extra: [String: String] = [:]) -> [String: String] {
        ["HOME": "/Users/tester", "AKASHIC_S2_STATE_DIR": stateDir,
         "AKASHIC_S2_KEYCHAIN_SERVICE": "akashic-test-\(UUID().uuidString)"].merging(extra) { $1 }
    }

    private static func records(_ n: Int) -> [[String: Any]] {
        (0..<n).map { ["citedPaper": ["paperId": "p\($0)", "title": String(repeating: "t", count: 380)]] }
    }

    /// spec Scenario「The same paper through MCP」：只放得下 120 筆 → total 1000、returned 120、nextOffset 120。
    func testReferencesAreTrimmedToTheByteBudget() async throws {
        let all = Self.records(1000)
        S2ToolStub.install { request in
            if request.url!.path.hasSuffix("/references") {
                return (200, try! JSONSerialization.data(withJSONObject: ["offset": 0, "data": all]))
            }
            return (200, try! JSONSerialization.data(withJSONObject: ["paperId": "seed", "referenceCount": 1000]))
        }
        // 上限以獨立的 JSONSerialization 算出「恰好 120 筆時」的整份大小
        let envelope: [String: Any] = ["endpoint": "references", "total": 1000, "returned": 120, "truncated": true,
                                       "offset": 0, "nextOffset": 120, "data": Array(all.prefix(120))]
        let budget = try JSONSerialization.data(withJSONObject: envelope, options: [.sortedKeys, .withoutEscapingSlashes]).count
        let out = await S2Tool.run(S2ToolArguments(endpoint: "references", id: "DOI:10.1/x", fields: [], limit: 1000),
                                   environment: env(["AKASHIC_S2_BASE_URL": "http://127.0.0.1:9"]),
                                   session: S2ToolStub.session(), budget: budget)
        XCTAssertFalse(out.isError, out.text)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.text.utf8)) as? [String: Any], out.text)
        XCTAssertEqual(obj["total"] as? Int, 1000)
        XCTAssertEqual(obj["returned"] as? Int, 120)
        XCTAssertEqual(obj["truncated"] as? Bool, true)
        XCTAssertEqual(obj["nextOffset"] as? Int, 120)
        XCTAssertEqual((obj["data"] as? [Any])?.count, 120)
    }

    // MARK: 續查契約（#664 verify R1 第 5、6、7、22 列）

    private func referencesStub(count: Int, titleLength: Int = 10) {
        S2ToolStub.install { request in
            if request.url!.path.hasSuffix("/references") {
                let q = URLComponents(url: request.url!, resolvingAgainstBaseURL: false)?.queryItems ?? []
                let offset = Int(q.first { $0.name == "offset" }?.value ?? "0")!
                let limit = Int(q.first { $0.name == "limit" }?.value ?? "100")!
                let end = min(count, offset + limit)
                var body: [String: Any] = ["offset": offset, "data": (offset..<end).map {
                    ["citedPaper": ["paperId": "p\($0)", "title": String(repeating: "t", count: titleLength)]]
                }]
                if end < count { body["next"] = end }
                return (200, try! JSONSerialization.data(withJSONObject: body))
            }
            return (200, try! JSONSerialization.data(withJSONObject: ["paperId": "seed", "referenceCount": count]))
        }
    }

    /// 第一筆就超過上限：以前回「成功、returned 0、nextOffset 等於 offset」，照它續查永遠原地踏步。
    func testARecordLargerThanTheBudgetIsAnErrorNotAnEmptySuccess() async {
        referencesStub(count: 1, titleLength: 5_000)
        let out = await S2Tool.run(S2ToolArguments(endpoint: "references", id: "DOI:10.1/x", fields: [], limit: 1),
                                   environment: env(["AKASHIC_S2_BASE_URL": "http://127.0.0.1:9"]),
                                   session: S2ToolStub.session(), budget: 1_000)
        XCTAssertTrue(out.isError, out.text)
        XCTAssertTrue(out.text.contains("fields"), "要告訴呼叫者怎麼縮小：\(out.text)")
    }

    /// 預設 limit 100 剛好放得下、S2 還有更多：`truncated` 是 false，但 `nextOffset` 要指出還有下一頁——
    /// 續查的訊號是 `nextOffset`，不是 `truncated`（那只表示被位元組上限截斷）。
    func testWhenTheDefaultPageFitsButS2HasMoreTheCursorStillSaysSo() async throws {
        referencesStub(count: 1000)
        let out = await S2Tool.run(S2ToolArguments(endpoint: "references", id: "DOI:10.1/x", fields: []),
                                   environment: env(["AKASHIC_S2_BASE_URL": "http://127.0.0.1:9"]),
                                   session: S2ToolStub.session())
        XCTAssertFalse(out.isError, out.text)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.text.utf8)) as? [String: Any], out.text)
        XCTAssertEqual(obj["returned"] as? Int, 100)
        XCTAssertEqual(obj["truncated"] as? Bool, false)
        XCTAssertEqual(obj["nextOffset"] as? Int, 100)
        XCTAssertEqual(obj["total"] as? Int, 1000)
    }

    /// 讀到最後一頁：`nextOffset` 是 null，照它續查就會停。
    func testTheLastPageEndsTheContinuation() async throws {
        referencesStub(count: 130)
        let out = await S2Tool.run(S2ToolArguments(endpoint: "references", id: "DOI:10.1/x", fields: [], offset: 100),
                                   environment: env(["AKASHIC_S2_BASE_URL": "http://127.0.0.1:9"]),
                                   session: S2ToolStub.session())
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.text.utf8)) as? [String: Any], out.text)
        XCTAssertEqual(obj["returned"] as? Int, 30)
        XCTAssertTrue(obj["nextOffset"] is NSNull, out.text)
    }

    /// MCP 的 limit 上限是 S2 的一頁（1000）：一個呼叫不能獨占全機每秒 1 次的額度好幾分鐘。
    func testALimitBeyondOneS2PageIsRefusedBeforeAnyRequest() async {
        referencesStub(count: 10)
        let out = await S2Tool.run(S2ToolArguments(endpoint: "references", id: "DOI:10.1/x", fields: [], limit: 1_000_000),
                                   environment: env(["AKASHIC_S2_BASE_URL": "http://127.0.0.1:9"]),
                                   session: S2ToolStub.session())
        XCTAssertTrue(out.isError, out.text)
        XCTAssertTrue(out.text.contains("1000"), out.text)
        XCTAssertEqual(S2ToolStub.count, 0)
    }

    func testMissingKeyIsAnErrorWithTheSetupGuidanceAndNoRequest() async {
        S2ToolStub.install { _ in (200, Data("{}".utf8)) }
        let service = "akashic-test-\(UUID().uuidString)"
        let out = await S2Tool.run(S2ToolArguments(endpoint: "paper", id: "DOI:10.1037/a0038889"),
                                   environment: env(["AKASHIC_S2_KEYCHAIN_SERVICE": service]),
                                   session: S2ToolStub.session())
        XCTAssertTrue(out.isError)
        XCTAssertTrue(out.text.hasPrefix("Error: 找不到 Semantic Scholar 的 API 金鑰"), out.text)
        XCTAssertTrue(out.text.contains(service) && out.text.contains("semantic-scholar.md"), out.text)
        XCTAssertEqual(S2ToolStub.count, 0)
    }

    func testUnknownEndpointAndMissingIdentifierAreErrors() async {
        let unknown = await S2Tool.run(S2ToolArguments(endpoint: "papers"), environment: env())
        XCTAssertTrue(unknown.isError)
        XCTAssertTrue(unknown.text.contains("papers"), unknown.text)
        let missing = await S2Tool.run(S2ToolArguments(endpoint: "paper"), environment: env())
        XCTAssertTrue(missing.isError)
        XCTAssertTrue(missing.text.contains("paper"), missing.text)
    }

    func testStatusReportsTheKeychainItemWithoutReadingAValue() async throws {
        let service = "akashic-test-\(UUID().uuidString)"
        let out = await S2Tool.run(S2ToolArguments(endpoint: "status"),
                                   environment: env(["AKASHIC_S2_KEYCHAIN_SERVICE": service]))
        XCTAssertFalse(out.isError, out.text)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.text.utf8)) as? [String: Any])
        let keychain = try XCTUnwrap(obj["keychain"] as? [String: Any])
        XCTAssertEqual(keychain["service"] as? String, service)
        XCTAssertEqual(keychain["present"] as? Bool, false)
        XCTAssertEqual(obj["host"] as? String, "api.semanticscholar.org")
    }
}

/// 經真的 akashic-mcp binary：工具有列出、參數型別不對整個呼叫拒絕、status 走得通。
final class S2ToolStdioTests: XCTestCase {
    private var root: URL!
    private var process: Process!
    private var stdinPipe: Pipe!
    private var reader: FileHandle!
    private var pending = Data()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-s2-e2e-\(UUID().uuidString)")
        try LibraryStore(root: root).ensureLayout()
        var products: URL!
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            products = bundle.bundleURL.deletingLastPathComponent()
        }
        process = Process()
        process.executableURL = products.appendingPathComponent("akashic-mcp")
        process.environment = ProcessInfo.processInfo.environment
            .filter { !$0.key.hasPrefix("AKASHIC_") }
            .merging(["AKASHIC_LIBRARY": root.path,
                      "AKASHIC_S2_KEYCHAIN_SERVICE": "akashic-test-e2e",
                      "AKASHIC_S2_STATE_DIR": root.appendingPathComponent("s2-state").path]) { _, new in new }
        stdinPipe = Pipe()
        let stdout = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdout
        process.standardError = Pipe()
        try process.run()
        reader = stdout.fileHandleForReading
        StdioE2ETests.setNonBlocking(reader.fileDescriptor)
    }

    override func tearDownWithError() throws {
        process.terminate()
        try? FileManager.default.removeItem(at: root)
    }

    private func send(_ obj: [String: Any]) throws {
        stdinPipe.fileHandleForWriting.write(try JSONSerialization.data(withJSONObject: obj))
        stdinPipe.fileHandleForWriting.write(Data("\n".utf8))
    }
    private func read() throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: StdioE2ETests.readLine(fd: reader.fileDescriptor, pending: &pending, timeout: 10)) as! [String: Any]
    }
    private func initialize() throws {
        try send(["jsonrpc": "2.0", "id": 1, "method": "initialize",
                  "params": ["protocolVersion": "2024-11-05", "capabilities": [:] as [String: Any],
                             "clientInfo": ["name": "t", "version": "1"]]])
        _ = try read()
        try send(["jsonrpc": "2.0", "method": "notifications/initialized"])
    }
    private func call(_ id: Int, _ args: [String: Any]) throws -> (text: String, isError: Bool) {
        try send(["jsonrpc": "2.0", "id": id, "method": "tools/call", "params": ["name": "akashic_s2", "arguments": args]])
        let result = try XCTUnwrap(try read()["result"] as? [String: Any])
        let text = ((result["content"] as? [[String: Any]]) ?? []).compactMap { $0["text"] as? String }.joined()
        return (text, result["isError"] as? Bool ?? false)
    }

    func testToolIsListedWithItsEndpoints() throws {
        try initialize()
        try send(["jsonrpc": "2.0", "id": 2, "method": "tools/list"])
        let tools = try XCTUnwrap((try read()["result"] as? [String: Any])?["tools"] as? [[String: Any]])
        let s2 = try XCTUnwrap(tools.first { $0["name"] as? String == "akashic_s2" }, "akashic_s2 沒有列出")
        let schema = try XCTUnwrap(s2["inputSchema"] as? [String: Any])
        let props = try XCTUnwrap(schema["properties"] as? [String: Any])
        let endpoint = try XCTUnwrap(props["endpoint"] as? [String: Any])
        XCTAssertEqual(Set(endpoint["enum"] as? [String] ?? []),
                       ["paper", "match", "batch", "references", "citations", "recommend", "author_search", "author_papers", "status"])
        XCTAssertEqual(schema["required"] as? [String], ["endpoint"])
    }

    func testWrongArgumentTypesRefuseTheWholeCall() throws {
        try initialize()
        let bad = try call(3, ["endpoint": "references", "id": "DOI:10.1/x", "limit": "5"])
        XCTAssertTrue(bad.isError)
        XCTAssertTrue(bad.text.contains("limit") && bad.text.contains("整數"), bad.text)
        let nullID = try call(4, ["endpoint": "paper", "id": NSNull()])
        XCTAssertTrue(nullID.isError)
        XCTAssertTrue(nullID.text.contains("id"), nullID.text)
    }

    func testStatusGoesThroughTheRealServer() throws {
        try initialize()
        let out = try call(5, ["endpoint": "status"])
        XCTAssertFalse(out.isError, out.text)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.text.utf8)) as? [String: Any], out.text)
        XCTAssertEqual((obj["keychain"] as? [String: Any])?["service"] as? String, "akashic-test-e2e")
    }
}
