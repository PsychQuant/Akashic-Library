import XCTest
import Foundation
@testable import AkashicStoreIO

/// #703 R1 verify 第 13、18、22、23 則：存檔在複製途中被殺掉（SIGKILL、斷電、逾時）留下的 `.<62 hex>.incoming-<UUID>` 暫存檔，
/// 先前沒有任何面報它（`auditSourceIndex` 只認 62 hex 的檔名）。現在 `akashic doctor` 以 ⚠ 列出路徑與大小、不刪。
/// 真 binary、scratch store（`--library` 與 `AKASHIC_HOME` 都指 scratch）。
final class SourcesStrayTemporaryCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-stray-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try LibraryStore(root: root, key: nil, environment: [:]).ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    func testDoctorListsAStrayTemporaryFileWithItsSizeAndLeavesIt() throws {
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        let name = LibraryStore.temporaryBlobName(digest: digest, token: UUID().uuidString)
        let dir = root.appendingPathComponent("sources/ab")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try Data(repeating: 1, count: 4_321).write(to: dir.appendingPathComponent(name))
        let r = try CLITestHarness.run(["doctor", "--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertTrue(r.output.contains("殘留的暫存檔（4321 bytes") && r.output.contains("sources/ab/\(name)"), r.output)
        XCTAssertFalse(r.output.contains("孤兒 blob"), "暫存檔不是 blob：\(r.output)")
        XCTAssertTrue(FileManager.default.fileExists(atPath: dir.appendingPathComponent(name).path), "只報不刪")
    }

    /// b26 F6 LOW 11（真 binary）：修改時間在未來的殘留暫存檔——先前印「最後修改於 0 秒前；一小時內還在動…不要刪」，永遠不算殘留。
    /// 現在說時間在未來、不能用它判斷；b29 V5 起也不歸在「中斷的存檔」那一類——判不出就說判不出。
    func testDoctorDoesNotTrustAFutureModificationTime() throws {
        let digest = "sha256:" + String(repeating: "cd", count: 32)
        let name = LibraryStore.temporaryBlobName(digest: digest, token: UUID().uuidString)
        let dir = root.appendingPathComponent("sources/cd")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let file = dir.appendingPathComponent(name)
        try Data(repeating: 2, count: 99).write(to: file)
        try FileManager.default.setAttributes([.modificationDate: Date(timeIntervalSinceNow: 3 * 365 * 86_400)], ofItemAtPath: file.path)
        let r = try CLITestHarness.run(["doctor", "--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertTrue(r.output.contains("修改時間在未來"), r.output)
        XCTAssertFalse(r.output.contains("最後修改於 0 秒前"), r.output)
        XCTAssertFalse(r.output.contains("一小時內還在動"), "不可信的時間不能被讀成『還在動』：\(r.output)")
        // b29 V5 LOW 10：也不能斷言它是中斷的存檔留下的——先前前半說判不出、後半說「中斷的存檔留下的——…可以刪掉」
        XCTAssertFalse(r.output.contains("中斷的存檔留下的——"), r.output)
        XCTAssertTrue(r.output.contains("判不出是中斷的存檔留下的、還是正在進行的存檔"), r.output)
    }
}
