import XCTest
import Foundation
import Darwin
@testable import AkashicStoreIO

/// #703 R2 verify 第 27 則：`store-source` 複製途中收到 Ctrl-C（`SIGINT`）或 `SIGTERM`，先前留下最大 256 MiB 的暫存檔——`defer` 對訊號
/// 結束不會跑。現在 `InFlightSourceFiles` 在存檔進行中接管這兩個訊號：刪掉登記中的暫存檔，再照原本的訊號結束行程。
///
/// 真 binary：輸入是接近上限的 sparse 檔（算 digest 那一遍讀洞很快，複製那一遍真的寫 256 MiB 左右的暫存檔），測試輪詢 `sources/` 等暫存檔
/// 出現、送訊號、等行程結束、確認沒有暫存檔留下。行程被那個訊號結束（`uncaughtSignal`），或訊號到時剛好放完（rc=0）都算；兩種都不得留暫存。
final class SourceSignalCleanupCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-srcsig-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try LibraryStore(root: root, key: nil, environment: [:]).ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func temporaryFiles() -> [String] {
        let dir = root.appendingPathComponent("sources")
        return ((try? FileManager.default.subpathsOfDirectory(atPath: dir.path)) ?? []).filter { $0.contains(".incoming-") }
    }

    /// 一次嘗試：回「送訊號時暫存檔在不在」與行程怎麼結束的。
    private func interruptOnce(_ sig: Int32, size: Int) throws -> (caught: Bool, reason: Process.TerminationReason, status: Int32) {
        let input = base.appendingPathComponent("big-\(UUID().uuidString).bin")
        XCTAssertTrue(FileManager.default.createFile(atPath: input.path, contents: nil))
        let h = try FileHandle(forWritingTo: input)
        try h.truncate(atOffset: UInt64(size))
        try h.close()
        defer { try? FileManager.default.removeItem(at: input) }
        let p = try CLITestHarness.start(["store-source", input.path, "--media-type", "application/octet-stream", "--retrieved", "2026-10-01",
                                          "--origin", "signal-test", "--acquisition", "file", "--library", root.path],
                                         env: ["AKASHIC_HOME": home.path])
        var caught = false
        let deadline = Date().addingTimeInterval(60)
        while p.isRunning && Date() < deadline {
            if !temporaryFiles().isEmpty {
                kill(p.processIdentifier, sig)
                caught = true
                break
            }
            usleep(300)
        }
        p.waitUntilExit()
        return (caught, p.terminationReason, p.terminationStatus)
    }

    private func assertInterruptLeavesNoTemporaryFile(_ sig: Int32, name: String) throws {
        // 每次嘗試用不同大小（不同 digest）：前一次若剛好放完，位址上已有那一份、下一次不會再建暫存檔
        for attempt in 0..<3 {
            let r = try interruptOnce(sig, size: LibraryStore.maxSourceBytes - attempt * 4_096)
            XCTAssertEqual(temporaryFiles(), [], "\(name) 之後不得留下暫存檔（第 \(attempt + 1) 次）")
            guard r.caught else { continue }
            XCTAssertTrue((r.reason == .uncaughtSignal && r.status == sig) || (r.reason == .exit && r.status == 0),
                          "\(name)：行程要被那個訊號結束（或剛好已經放完），實得 \(r.reason.rawValue)／\(r.status)")
            return
        }
        XCTFail("三次都沒在暫存檔存在的期間送出 \(name)——這台機器的複製太快，測試沒有真的測到")
    }

    func testSIGINTDuringACopyLeavesNoTemporaryFile() throws {
        try assertInterruptLeavesNoTemporaryFile(SIGINT, name: "SIGINT")
    }

    func testSIGTERMDuringACopyLeavesNoTemporaryFile() throws {
        try assertInterruptLeavesNoTemporaryFile(SIGTERM, name: "SIGTERM")
    }
}
