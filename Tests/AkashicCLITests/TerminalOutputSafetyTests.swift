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

    /// #135 verify F2：VT/FF/CR/NEL/LS/PS **不是**分隔符——isNewline 版 wrapper 曾把
    /// 它們轉成真 LF，讓困在單一 YAML scalar 的內容獲得多行輸出注入（偽造報告行）。
    func testNonLFSeparatorsAreEscapedNotConverted() {
        for (name, ch) in [("LS", "\u{2028}"), ("PS", "\u{2029}"), ("NEL", "\u{0085}"),
                           ("VT", "\u{000B}"), ("FF", "\u{000C}"), ("CR", "\u{000D}")] {
            let out = displaySafeMultiline("AAA\(ch)BBB")
            XCTAssertFalse(out.contains("AAA\nBBB"),
                           "\(name) 被轉成真 LF＝單行內容的多行注入")
            XCTAssertTrue(out.contains("AAA") && out.contains("BBB"))
        }
        // CRLF 是正常換行（正規化為 LF）——不因 F2 修法而壞
        XCTAssertEqual(displaySafeMultiline("a\r\nb").components(separatedBy: "\n").count, 2)
    }

    /// #135 verify F3：跳脫是 8 倍膨脹器——many-lines 形狀曾放大到 ~640 KB
    /// （比未消毒還多 6.3 倍）。總量 cap 讓「有上限」成為真保證。
    func testAmplifiedManyLineOutputIsBounded() {
        let bomb = Array(repeating: String(repeating: "\u{1B}", count: 400), count: 250)
            .joined(separator: "\n")
        let out = displaySafeMultiline(bomb)
        XCTAssertLessThan(out.count, 110_000, "跳脫膨脹後仍須有總量上限")
        XCTAssertTrue(out.contains("截斷"))
    }

    /// #135 verify F4：harness 的 deadlock 修復（先讀後 wait）在 GREEN 態零覆蓋——
    /// 錯誤路徑的輸出已被 choke point 的 cap 馴服到 64 KB 以下，構造大輸出要走
    /// **合法多行輸出**：500 個 quarantined 檔讓 validate 印 500 行報告（>64 KB）。
    /// 修復回歸（wait 先於讀）時本測試 hang 而非默默通過。
    func testHarnessSurvivesOutputLargerThanPipeBuffer() throws {
        let entities = root.appendingPathComponent("entities")
        for i in 0..<900 {
            try "this is not a valid record yaml [ \(String(repeating: "pad", count: 40))".write(
                to: entities.appendingPathComponent("\(UUID().uuidString).yaml"),
                atomically: true, encoding: .utf8)
            _ = i
        }
        let r = try CLITestHarness.run(["validate", "--library", root.path], env: [:])
        XCTAssertNotEqual(r.status, 0)
        XCTAssertGreaterThan(r.output.count, 64 * 1024,
                             "前置：本測試的輸出必須超過 pipe buffer 才能釘 deadlock 修復")
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

    /// #554 R31（R30 verify 第 2／27 列）：**直接傳到頂層的原始錯誤**（不是五個 `ValidationError` 包裝之一）也要逃一次——R30 只經列舉式的
    /// `displaySafeAssembled`，ZWSP 原樣落 stderr；MCP 面走性質式，兩面不同字串。這裡用真 binary：`enrich --from <目錄>` 讓 `Data(contentsOf:)`
    /// 擲出 Foundation 錯誤（路徑含 ZWSP），stderr 必須等於 `displaySafeErrorMultiline(同一個錯誤, prefix: "Error: ")`。
    func testRawErrorReachingTheTopLevelIsEscapedOnce() throws {
        let dir = root.appendingPathComponent("pro\u{200B}posals.json", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let (status, output) = try CLITestHarness.run(["enrich", "--from", dir.path, "--library", root.path], env: [:])
        XCTAssertEqual(status, 1)
        let stderr = output.trimmingCharacters(in: .newlines)
        XCTAssertTrue(stderr.hasPrefix("Error: "), stderr)
        XCTAssertFalse(stderr.unicodeScalars.contains { $0.value == 0x200B }, "裸 ZWSP 落 stderr：\(stderr)")
        XCTAssertEqual(stderr.components(separatedBy: "\\u{200B}").count - 1, 1, "ZWSP 恰逃一次：\(stderr)")
        XCTAssertFalse(stderr.contains("\\u{005C}"), "二次逃脫：\(stderr)")
        XCTAssertTrue(stderr.contains("pro\\u{200B}posals.json"), stderr)
        // 兩面逐字相同在這裡**不能**用等式釘：Foundation 的 localizedDescription 由各程序的 bundle 決定語言（xctest 程序印中文、
        // 裸 CLI 印英文），同一個錯誤的原文本來就不同。等式由 `SanitizationBoundaryTests.testTwoFacesAgreeEvenWhenTruncated`（同程序）
        // 與 R31 的 E2E 腳本（CLI 與 akashic-mcp 兩個裸 binary、同一個 store）釘，這裡只釘「頂層真的走了 displaySafeErrorText」。
    }
}
