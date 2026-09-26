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
            let r = try CLITestHarness.run(args + ["--library", bare.path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
            XCTAssertEqual(r.status, 1, "\(args)：\(r.output)")
            XCTAssertTrue(r.output.contains("不是 Akashic library"), "\(args)：\(r.output)")
            XCTAssertFalse(r.output.contains("Usage:"), "執行期失敗不印 usage——\(args)：\(r.output)")
        }
    }

    /// run() 期間的 `ValidationError` 仍是 64，但 usage 是子命令的，不是 `akashic <subcommand>`
    func testUsageErrorFromRunShowsTheSubcommandUsage() throws {
        let root = try makeStore()
        let r = try CLITestHarness.run(["query", "--same-journal-as", "a", "--cited-by", "b", "--library", root.path],
                                       env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
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
                                       env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
        XCTAssertEqual(r.status, 64, r.output)
        XCTAssertTrue(r.output.contains("See 'akashic library create --help'"), r.output)
    }

    /// R1 verify：只看 argv 的檢查要早於開 store（放在 `validate()`）。store 缺佈局時，打錯的 key／--tier／--fields
    /// 仍是 64——先前 library create 的 key 檢查排在 openStore 之後，會先報執行期失敗。
    /// library add／remove 的 key 格式先前交給服務層、被包成 1，同一個打錯的 key 在 create 回 64、在 add 回 1。
    func testArgvOnlyChecksRunBeforeTheStoreIsOpened() throws {
        let bare = tmp.appendingPathComponent("not-a-store")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        let cases: [[String]] = [
            ["library", "create", "Bad Key", "--name", "x"],
            ["library", "add", "Bad Key", "some2020x"],
            ["library", "remove", "Bad Key", "some2020x"],
            ["resolve-people", "--tier", "nope"],
            ["update-person", "--key", "x", "--fields", "[1,2]"],
        ]
        for args in cases {
            let r = try CLITestHarness.run(args + ["--library", bare.path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
            XCTAssertEqual(r.status, 64, "\(args)：\(r.output)")
            XCTAssertFalse(r.output.contains("不是 Akashic library"), "argv 錯誤不得被缺佈局搶先——\(args)：\(r.output)")
            XCTAssertTrue(r.output.contains("Usage: akashic \(args[0])"), "\(args)：\(r.output)")
        }
    }

    /// stdin 是 argv 以外：update-person 從 stdin 讀到的不是 JSON object → 執行期失敗（1），與 create-entry 的輸入檔同一類。
    /// harness 的子程序繼承測試程序的 stdin（空的），正好是這個情形。
    func testUpdatePersonStdinContentIsARuntimeFailure() throws {
        let root = try makeStore()
        let r = try CLITestHarness.run(["update-person", "--key", "x", "--library", root.path],
                                       env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("stdin 必須是 JSON object"), r.output)
        XCTAssertFalse(r.output.contains("Usage:"), r.output)
    }

    /// 對照組：parse 階段的錯誤本來就是 64＋子命令 usage，本輪不動它
    func testParseErrorIsUnchanged() throws {
        let r = try CLITestHarness.run(["library", "create"], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
        XCTAssertEqual(r.status, 64, r.output)
        XCTAssertTrue(r.output.contains("Usage: akashic library create"), r.output)
    }
}
