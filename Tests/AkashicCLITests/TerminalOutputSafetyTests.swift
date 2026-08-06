import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #114：ArgumentParser 頂層錯誤輸出的消毒 choke point。
///
/// throw 路徑的終點曾完全沒有消毒：任何 errorDescription 內插的使用者可控內容
/// （store.yaml 逐字行、config key、Yams 錯誤展開）原樣落地 stderr——
/// #112 verify 實測 ESC/BEL 穿透、2 MB 行無上限。逐條補 14 個 ValidationError
/// 是假性閉合（DA 裁決）：明天新增的 error case 又會裸奔。
final class TerminalOutputSafetyTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-term114-\(UUID().uuidString)")
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    func testDisplaySafeMultilinePreservesNewlinesAndEscapesPerLine() {
        let input = "line1\nline\u{1B}[31m2\nline3"
        let out = displaySafeMultiline(input)
        XCTAssertEqual(out.components(separatedBy: "\n").count, 3, "換行是唯一保留的分隔符")
        XCTAssertFalse(out.contains("\u{1B}"), "行內控制字元照舊跳脫")
        XCTAssertTrue(out.contains("line1") && out.contains("line3"))
    }

    func testDisplaySafeMultilineBoundsLineCount() {
        let input = Array(repeating: "x", count: 500).joined(separator: "\n")
        let out = displaySafeMultiline(input, maxLines: 200)
        XCTAssertLessThan(out.components(separatedBy: "\n").count, 210)
        XCTAssertTrue(out.contains("截斷"), "截斷要明說，不靜默吞行")
    }

    func testPoisonedMarkerErrorIsSanitized() throws {
        // ESC（清螢幕/偽造輸出）與 BEL 藏進 marker——doctor 的錯誤訊息不得原樣轉印
        try "format: \u{1B}[2J\u{07}forged\n".write(
            to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
        let r = try CLITestHarness.run(["doctor", "--library", root.path], env: [:])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertFalse(r.output.contains("\u{1B}"), "ESC 不得穿透到 terminal 輸出")
        XCTAssertFalse(r.output.contains("\u{07}"), "BEL 不得穿透")
    }

    func testHugeMarkerLineIsBounded() throws {
        try ("format: " + String(repeating: "x", count: 2_000_000) + "\n").write(
            to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
        let r = try CLITestHarness.run(["doctor", "--library", root.path], env: [:])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertLessThan(r.output.count, 100_000,
                          "2 MB 的行不得整條進 stderr——MCP/LLM context 的無上限灌注同型")
    }

    func testHelpOutputSurvivesIntact() throws {
        // --help 走同一條錯誤輸出路徑（CleanExit）——消毒不得毀掉合法多行輸出
        let r = try CLITestHarness.run(["--help"], env: [:])
        XCTAssertEqual(r.status, 0)
        XCTAssertTrue(r.output.contains("SUBCOMMANDS"), r.output)
        XCTAssertGreaterThan(r.output.components(separatedBy: "\n").count, 10,
                             "help 是多行輸出——被壓成單行＝消毒毀了 usage")
        XCTAssertFalse(r.output.contains("\\u{"), "合法輸出不得出現跳脫殘渣")
    }

    func testValidationErrorUsageStillMultiline() throws {
        // 缺必要參數的 validation error 帶 usage 段——同樣要保持多行完整
        let r = try CLITestHarness.run(["library", "create"], env: [:])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertGreaterThan(r.output.components(separatedBy: "\n").count, 3,
                             "usage 段是多行的：\(r.output)")
    }
}
