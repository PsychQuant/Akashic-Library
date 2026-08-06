import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #115：`openStore()` 是 refuse-if-newer 的 choke point。
///
/// `StoreVersion.check` 曾只在 `load()` 被呼叫——凡不經 `load()` 的路徑全部繞過：
/// `fmt` 的全庫 read-modify-write（#112 DA 實測：format 太新的 store 上 doctor/validate
/// 拒絕、fmt 照改寫 exit 0——**用本 binary 的舊語意改寫較新格式的記錄**）、
/// `library create` 對 malformed marker 照走。修在 `openStore()` 讓**全部** CLI 指令
/// （現在的與未來新增的）一次涵蓋。
final class RefuseIfNewerGateTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-gate115-\(UUID().uuidString)")
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try store.writePerson(Person(key: "p-one", names: ["P"], authorized: ["P"]))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func snapshot() throws -> [String: Data] {
        var out: [String: Data] = [:]
        let dir = root.appendingPathComponent("entities")
        for u in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)
        where u.pathExtension == "yaml" {
            out[u.lastPathComponent] = try Data(contentsOf: u)
        }
        return out
    }

    func testFmtRefusesTooNewStoreBeforeTouchingAnyFile() throws {
        try "format: \(StoreVersion.supported + 1)\n".write(
            to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
        let before = try snapshot()

        let r = try CLITestHarness.run(["fmt", "--library", root.path], env: [:])
        XCTAssertNotEqual(r.status, 0, "太新的 store 上 fmt 必須拒絕：\(r.output)")
        XCTAssertTrue(r.output.contains("升級"), "訊息要指路（請升級）：\(r.output)")
        XCTAssertEqual(try snapshot(), before,
                       "拒絕必須發生在動任何檔案之前——改寫後才拒絕等於沒拒絕")
    }

    func testFmtCheckAlsoRefusesTooNew() throws {
        try "format: \(StoreVersion.supported + 1)\n".write(
            to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
        let r = try CLITestHarness.run(["fmt", "--check", "--library", root.path], env: [:])
        XCTAssertNotEqual(r.status, 0, "--check 讀的也是「按舊語意解讀新格式」——同樣拒絕")
    }

    func testLibraryCreateRefusesMalformedMarker() throws {
        try "format: banana\n".write(
            to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
        let r = try CLITestHarness.run(
            ["library", "create", "sinica", "--name", "中研院", "--library", root.path], env: [:])
        XCTAssertNotEqual(r.status, 0, "malformed marker 上 library create 必須拒絕：\(r.output)")
        XCTAssertFalse(FileManager.default.fileExists(
                           atPath: root.appendingPathComponent("libraries/sinica.yaml").path),
                       "拒絕時不得留下任何寫入")
    }

    func testQueryAlsoGatedAtOpen() throws {
        // read-only 指令經 openStore 同受閘——「按舊語意誤讀」讀跟寫一樣危險，
        // 且它們原本經 load() 就會被擋，行為無實質變化（迴歸確認訊息一致）
        try "format: \(StoreVersion.supported + 1)\n".write(
            to: StoreVersion.url(in: root), atomically: true, encoding: .utf8)
        let r = try CLITestHarness.run(["query", "--library", root.path], env: [:])
        XCTAssertNotEqual(r.status, 0)
    }

    func testNormalStoreUnaffected() throws {
        let r = try CLITestHarness.run(["fmt", "--check", "--library", root.path], env: [:])
        XCTAssertEqual(r.status, 0, "正常 store 的 fmt --check 不受影響：\(r.output)")
    }
}
