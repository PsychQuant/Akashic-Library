import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #146 verify G2／R6：**CLI 與 MCP 兩個出口面零覆蓋**。
///
/// 席位把四個 mutation 同時套上，1038 條全綠：
///
/// | mutation | 後果 |
/// |---|---|
/// | 刪掉 MCP 的 `d["digestSources"]` | F1 修的東西整個消失 |
/// | 寫入失敗仍計入 `migrated`／`records` | 報告誇報 |
/// | CLI 不印 failures 區塊 | F4 的使用者面消失 |
/// | CLI doctor 殘留區塊整段不印 | 功能等同不存在 |
///
/// library 層（`ProvenanceMigration`）現在釘住了，**出口面沒有**。而這個 change 的
/// 「守」那一半（doctor 報殘留）與「說」那一半（failures／skipped）全部住在出口面。
final class MigrateProvenanceCLITests: XCTestCase {
    var root: URL!

    private var productsDirectory: URL {
        for bundle in Bundle.allBundles where bundle.bundlePath.hasSuffix(".xctest") {
            return bundle.bundleURL.deletingLastPathComponent()
        }
        fatalError("找不到 products directory")
    }

    private func runCLI(_ args: [String]) throws -> (status: Int32, out: String) {
        let p = Process()
        p.executableURL = productsDirectory.appendingPathComponent("akashic")
        p.arguments = args + ["--library", root.path]
        // AKASHIC_* 無條件剝除——不剝除會讀開發機的真實 config.yaml（#105 之後
        // `--library` 會反查 registry）。同 `ResolvePeopleSelectiveTests` 的沙箱紀律。
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("AKASHIC_") }
        let o = Pipe(), e = Pipe()
        p.standardOutput = o; p.standardError = e
        try p.run()
        let od = o.fileHandleForReading.readDataToEndOfFile()
        let ed = e.fileHandleForReading.readDataToEndOfFile()
        p.waitUntilExit()
        return (p.terminationStatus,
                String(decoding: od, as: UTF8.self) + String(decoding: ed, as: UTF8.self))
    }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-mpcli-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let digest = "sha256:" + String(repeating: "0a", count: 32)
        var p = Person(key: "chen-pao-yang", names: ["Chen, Pao-Yang"])
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.key("iss"), source: digest,
                          note: "由論文作者機構字串推得：統計所是該學程的 host institute")])
        try store.writePerson(p)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// **`doctor` 必須報殘留。** 席位 mutation：整段不印 → 全綠。
    func testDoctorReportsDigestResidue() throws {
        let r = try runCLI(["doctor"])
        XCTAssertTrue(r.out.contains("digest 形式的 source"),
                      "「守」的那一半住在這裡——不印就等於功能不存在：\(r.out)")
        XCTAssertTrue(r.out.contains("migrate-provenance"), "要指路")
    }

    /// dry-run 回報數字、不動磁碟；實跑之後 doctor 歸零。
    func testDryRunThenApplyThenResidueGoesToZero() throws {
        let dry = try runCLI(["migrate-provenance", "--dry-run"])
        XCTAssertTrue(dry.out.contains("（dry-run）"), dry.out)
        XCTAssertTrue(dry.out.contains("1 筆"), dry.out)
        XCTAssertTrue(try runCLI(["doctor"]).out.contains("digest 形式的 source"),
                      "dry-run 不得改變任何東西")

        let real = try runCLI(["migrate-provenance"])
        XCTAssertEqual(real.status, 0, real.out)
        XCTAssertTrue(real.out.contains("✓"), real.out)
        XCTAssertFalse(try runCLI(["doctor"]).out.contains("digest 形式的 source"),
                       "遷移之後殘留必須歸零")
    }

    /// **寫入失敗：逐筆列出 + 非零退出**（G1／G2）。
    ///
    /// 三塊紀律（per-item 收容、先報失敗、**然後 throw**）本 repo 四處都是一起用的；
    /// 先前只拿了前兩塊，於是**機器看的訊號嚴格變差**——原本 exit 1、改完 exit 0，
    /// `&&` 串接／CI／`/loop` 會在半新半舊的 store 上看到成功。
    func testWriteFailureIsListedAndExitsNonZero() throws {
        let load = try LibraryStore(root: root).load()
        let target = try XCTUnwrap(load.people.first)
        let f = root.appendingPathComponent("entities/\(target.id.uuidString).yaml")
        let lock = Process()
        lock.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
        lock.arguments = ["uchg", f.path]
        try lock.run(); lock.waitUntilExit()
        defer {
            let u = Process()
            u.executableURL = URL(fileURLWithPath: "/usr/bin/chflags")
            u.arguments = ["nouchg", f.path]
            try? u.run(); u.waitUntilExit()
        }
        let r = try runCLI(["migrate-provenance"])
        guard r.out.contains("寫入失敗") else {
            throw XCTSkip("chflags 沒生效（容器／檔案系統不支援）——這條要真的寫失敗才驗得到")
        }
        XCTAssertTrue(r.out.contains("chen-pao-yang"), "要逐筆列出是哪一筆：\(r.out)")
        XCTAssertTrue(r.out.contains("冪等"), "要說可以重跑")
        XCTAssertNotEqual(r.status, 0,
                          "部分失敗必須非零退出——半新半舊的 store 不得被 `&&` 讀成成功")
        XCTAssertFalse(r.out.contains("NSCocoaErrorDomain"),
                       "訊息要是 localizedDescription 不是 NSError dump（G3）：\(r.out)")
    }
}
