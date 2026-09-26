import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #549：「命令列打錯了」與「命令列對、環境不對」要分得開——exit code 與 usage 兩個訊號都是。
///
/// - 用法錯誤：exit 64（`EX_USAGE`），印**該子命令**的 usage（parse 階段本來就是；run() 期間的 `ValidationError` 由頂層補上）
/// - 執行期失敗（`RuntimeFailure`）：exit 1，不印 usage
///
/// 走真 binary——exit code 與 usage 都是頂層出口的行為，in-process 呼叫 `run()` 量不到。
final class CLIExitCodeTests: XCTestCase {
    private var tmp: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-exit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tmp, withIntermediateDirectories: true)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func makeStore() throws -> URL {
        let root = tmp.appendingPathComponent("lib")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        return root
    }

    /// issue 的四個實測命令：缺佈局是環境問題，不是用法問題
    func testMissingLayoutIsARuntimeFailureNotAUsageError() throws {
        let bare = tmp.appendingPathComponent("not-a-store")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        let draft = tmp.appendingPathComponent("in.json")
        try #"{"type": "periodical-article", "title": "T"}"#.write(to: draft, atomically: true, encoding: .utf8)
        for args in [["validate"], ["people"], ["bootstrap-people"], ["create-entry", "--file", draft.path]] {
            let r = try CLITestHarness.run(args + ["--library", bare.path], env: ["HOME": tmp.path])
            XCTAssertEqual(r.status, 1, "\(args)：\(r.output)")
            XCTAssertTrue(r.output.contains("不是 Akashic library"), "\(args)：\(r.output)")
            XCTAssertFalse(r.output.contains("Usage:"), "執行期失敗不印 usage——\(args)：\(r.output)")
        }
    }

    /// run() 期間的 `ValidationError` 仍是 64，但 usage 是子命令的，不是 `akashic <subcommand>`
    func testUsageErrorFromRunShowsTheSubcommandUsage() throws {
        let root = try makeStore()
        let r = try CLITestHarness.run(["query", "--same-journal-as", "a", "--cited-by", "b", "--library", root.path],
                                       env: ["HOME": tmp.path])
        XCTAssertEqual(r.status, 64, r.output)
        XCTAssertTrue(r.output.contains("關係查詢一次一種"), r.output)
        XCTAssertTrue(r.output.contains("Usage: akashic query"), r.output)
        XCTAssertFalse(r.output.contains("Usage: akashic <subcommand>"), r.output)
        XCTAssertTrue(r.output.contains("See 'akashic query --help'"), r.output)
    }

    /// 巢狀子命令的路徑要完整（`akashic library create`，不是 `akashic create`）
    func testNestedSubcommandPathIsComplete() throws {
        let root = try makeStore()
        let r = try CLITestHarness.run(["library", "create", "Bad Key", "--name", "x", "--library", root.path],
                                       env: ["HOME": tmp.path])
        XCTAssertEqual(r.status, 64, r.output)
        XCTAssertTrue(r.output.contains("See 'akashic library create --help'"), r.output)
    }

    /// 對照組：parse 階段的錯誤本來就是 64＋子命令 usage，本輪不動它
    func testParseErrorIsUnchanged() throws {
        let r = try CLITestHarness.run(["library", "create"], env: ["HOME": tmp.path])
        XCTAssertEqual(r.status, 64, r.output)
        XCTAssertTrue(r.output.contains("Usage: akashic library create"), r.output)
    }
}
