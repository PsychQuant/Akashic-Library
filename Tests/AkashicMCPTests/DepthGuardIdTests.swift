import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #153 verify F1/F2 的 regression（真 binary stdio）：深度 error 回覆的 id 抽取
/// 不誤抓巢狀 id、控制字元 id 退回 null 使回覆維持合法 JSON。
///
/// 與 StdioE2ETests 共用 spawn 模式，但獨立檔以隔離 id-extraction 的攻擊向量。
final class DepthGuardIdTests: XCTestCase {
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
            .appendingPathComponent("akashic-depthid-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        process = Process()
        process.executableURL = productsDirectory.appendingPathComponent("akashic-mcp")
        process.environment = ProcessInfo.processInfo.environment
            .filter { !$0.key.hasPrefix("AKASHIC_") }
            .merging(["AKASHIC_LIBRARY": root.path]) { _, new in new }
        stdinPipe = Pipe(); stdoutPipe = Pipe()
        process.standardInput = stdinPipe
        process.standardOutput = stdoutPipe
        process.standardError = Pipe()
        try process.run()
        reader = stdoutPipe.fileHandleForReading
        try handshake()
    }

    override func tearDownWithError() throws {
        process.terminate()
        try? FileManager.default.removeItem(at: root)
    }

    private func writeLine(_ s: String) {
        stdinPipe.fileHandleForWriting.write(Data((s + "\n").utf8))
    }

    private func readResponse() throws -> [String: Any] {
        var buf = Data()
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            let chunk = reader.availableData
            if chunk.isEmpty { continue }
            buf.append(chunk)
            if let nl = buf.firstIndex(of: 0x0A) {
                let line = buf[..<nl]
                return (try JSONSerialization.jsonObject(with: line)) as? [String: Any] ?? [:]
            }
        }
        throw XCTSkip("10 秒內未收到回應（server 可能已死）")
    }

    private func handshake() throws {
        writeLine(#"{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"t","version":"0"}}}"#)
        _ = try readResponse()
        writeLine(#"{"jsonrpc":"2.0","method":"notifications/initialized"}"#)
    }

    private var bomb: String {
        String(repeating: "[", count: 300) + String(repeating: "]", count: 300)
    }

    /// F1：頂層真 id=222、params 裡埋假 id=111——error 不得回 111。
    func testNestedIdNotStolen() throws {
        writeLine(#"{"jsonrpc":"2.0","method":"tools/call","params":{"arguments":{"id":111},"junk":\#(bomb)},"id":222}"#)
        let resp = try readResponse()
        XCTAssertNotNil(resp["error"], "應為深度 error：\(resp)")
        XCTAssertEqual(resp["id"] as? Int, 222, "頂層真 id：\(resp)")
    }

    /// F1：id 只在深層時退回 null（不誤抓）。
    func testDeepOnlyIdFallsBackToNull() throws {
        writeLine(#"{"jsonrpc":"2.0","method":"tools/call","params":{"arguments":{"id":111},"junk":\#(bomb)}}"#)
        let resp = try readResponse()
        XCTAssertNotNil(resp["error"])
        XCTAssertTrue(resp["id"] is NSNull, "深層 id 不誤抓、退回 null：\(resp)")
    }

    /// F2：控制字元 id → 回覆是合法 JSON（readResponse 的 JSONSerialization 會證），
    /// id 退回 null。
    func testControlCharIdYieldsValidJSONWithNullId() throws {
        // id 帶 TAB（0x09）——直接內插會是非法 JSON
        writeLine("{\"jsonrpc\":\"2.0\",\"id\":\"x\u{09}y\",\"method\":\"tools/call\",\"params\":{\"junk\":\(bomb)}}")
        let resp = try readResponse()   // 非法 JSON 會在此拋
        XCTAssertNotNil(resp["error"])
        XCTAssertTrue(resp["id"] is NSNull, "控制字元 id 退回 null：\(resp)")
        XCTAssertTrue(process.isRunning)
    }

    /// 整數與乾淨字串 id 正常回傳（不過度退化成 null）。
    func testCleanIdsPreserved() throws {
        writeLine(#"{"jsonrpc":"2.0","id":7,"method":"tools/call","params":{"junk":\#(bomb)}}"#)
        XCTAssertEqual(try readResponse()["id"] as? Int, 7)
        writeLine(#"{"jsonrpc":"2.0","id":"req-abc","method":"tools/call","params":{"junk":\#(bomb)}}"#)
        XCTAssertEqual(try readResponse()["id"] as? String, "req-abc")
    }
}
