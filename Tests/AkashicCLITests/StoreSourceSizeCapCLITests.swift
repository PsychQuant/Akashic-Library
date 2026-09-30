import XCTest
import Foundation
@testable import AkashicStoreIO

/// #703：`store-source` 的 CLI 面——超過 256 MiB 的檔整個拒絕、不截斷、零寫入，訊息說出路徑、大小與上限。
/// 真 binary、scratch store（`--library` 與 `AKASHIC_HOME` 都指 scratch）；大檔是 sparse 檔（大小以 stat 判斷，不讀、不佔磁碟）。
final class StoreSourceSizeCapCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-sscap-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try LibraryStore(root: root, key: nil, environment: [:]).ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: ["AKASHIC_HOME": home.path])
    }

    func testAFileOverTheCapIsRefusedWithItsPathAndSize() throws {
        let huge = base.appendingPathComponent("huge-scan.pdf")
        XCTAssertTrue(FileManager.default.createFile(atPath: huge.path, contents: nil))
        let w = try FileHandle(forWritingTo: huge)
        try w.truncate(atOffset: UInt64(LibraryStore.maxSourceBytes + 1))
        try w.close()
        let r = try cli(["store-source", huge.path, "--media-type", "application/pdf", "--retrieved", "2026-09-30",
                         "--origin", "scan", "--acquisition", "scan"])
        XCTAssertEqual(r.status, 1, "輸入檔的內容是 argv 以外——執行期失敗，不是用法錯誤：\(r.output)")
        XCTAssertTrue(r.output.contains("huge-scan.pdf") && r.output.contains("\(LibraryStore.maxSourceBytes + 1)")
                      && r.output.contains("256 MiB"), r.output)
        let shards = ((try? FileManager.default.contentsOfDirectory(
            atPath: root.appendingPathComponent("sources").path)) ?? []).filter { $0.count == 2 }
        XCTAssertEqual(shards, [], "零寫入")
    }
}
