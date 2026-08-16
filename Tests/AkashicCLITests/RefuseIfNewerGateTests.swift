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
        // **fixture 必須是 deviating 記錄**（#134 verify F2 的 mutation 教訓）：
        // writePerson 出的是 canonical form，fmt 對它本來就零改寫——byte-snapshot
        // 斷言在「閘移到 scan 之後」的變異下照樣綠（席位實測：變異 binary 對
        // deviating store 印了拒絕、exit 非零、**照樣改寫了檔案**——#112 原 bug
        // 在綠測試下重現）。手刻反時間序 affiliations 讓 fmt 真的有東西要改，
        // snapshot 斷言才咬得到「拒絕先於改寫」。
        let id = UUID()
        let yaml = """
        person:
        id: \(id.uuidString)
        key: p-one
        names:
          authorized:
          - P
        profile:
          affiliations:
          - value:
              literal: ISS
            start: 2013-07
          - value:
              literal: ISS
            start: 2003-01
            end: 2006-08
        """ + "\n"
        try yaml.write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
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
        // fixture 是 deviating（F2 的要求）——正常 store 上 --check 走到偏離報告
        // （exit 1、印偏離），而**不是**被版本閘擋下：這才證明 gate 只擋該擋的
        let r = try CLITestHarness.run(["fmt", "--check", "--library", root.path], env: [:])
        XCTAssertEqual(r.status, 1, "偏離報告的 exit 1：\(r.output)")
        XCTAssertTrue(r.output.contains("偏離"), "走到正常 fmt 流程：\(r.output)")
        XCTAssertFalse(r.output.contains("升級"), "不得被版本閘誤擋：\(r.output)")
    }
}
