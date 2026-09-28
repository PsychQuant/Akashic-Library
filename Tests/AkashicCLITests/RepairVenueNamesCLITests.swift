import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #575：`repair-venue-names` 的 CLI 面——乾跑真的印出「venue／清單[index]：before → after」與要人判斷的項目、`--apply` 真的寫、
/// 寫完 `validate` 對可修的那筆零 error。用真 binary（#101/#112 的沙箱紀律：`--library` 指 scratch、`AKASHIC_HOME` 指 scratch）。
final class RepairVenueNamesCLITests: XCTestCase {
    private var root: URL!
    private var home: URL!

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: ["AKASHIC_HOME": home.path])
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }   // #239：hook 環境帶 GIT_DIR
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    private var fixable: Venue!
    private var judged: Venue!

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-rvn-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        // 繞過寫入閘直接寫檔——舊 binary 或手改 YAML 的形狀
        fixable = Venue(key: "alpha", type: .periodical,
                        names: Timeline([TemporalValue(value: "Alpha\tJournal ")]), authorized: ["Alpha\tJournal "])
        judged = Venue(key: "beta", type: .periodical,
                       names: Timeline([TemporalValue(value: "Beta\u{200B}Journal")]))
        for v in [fixable!, judged!] {
            try VenueYAML.encode(v).write(to: root.appendingPathComponent("entities/\(v.id.uuidString).yaml"),
                                          atomically: true, encoding: .utf8)
        }
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "fixture"])
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    private func venue(_ key: String) throws -> Venue {
        try XCTUnwrap(LibraryStore(root: root, key: nil, environment: [:]).load().venues.first { $0.key == key })
    }

    func testDryRunPrintsRewritesAndJudgmentsAndWritesNothing() throws {
        let before = try Data(contentsOf: root.appendingPathComponent("entities/\(fixable.id.uuidString).yaml"))
        let r = try cli(["repair-venue-names"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("乾跑"), r.output)
        XCTAssertTrue(r.output.contains("alpha  names[0]") && r.output.contains("→ 「Alpha Journal」"), r.output)
        XCTAssertTrue(r.output.contains("尾隨空白"), "改動說明要印：\(r.output)")
        XCTAssertTrue(r.output.contains("要人判斷") && r.output.contains("U+200B"), r.output)
        XCTAssertFalse(r.output.contains("\u{200B}"), "原始不可見字元不得落到終端機：\(r.output)")
        XCTAssertTrue(r.output.contains("--apply"), r.output)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("entities/\(fixable.id.uuidString).yaml")), before, "乾跑零寫入")
    }

    func testApplyRewritesAndValidateIsCleanForThatVenue() throws {
        let r = try cli(["repair-venue-names", "--apply"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("已改寫"), r.output)
        let a = try venue("alpha")
        XCTAssertEqual(a.names.entries.map(\.value), ["Alpha Journal"])
        XCTAssertEqual(a.authorized, ["Alpha Journal"])
        XCTAssertEqual(try venue("beta").names.entries.map(\.value), ["Beta\u{200B}Journal"], "判斷項不動")
        let v = try cli(["validate"])
        XCTAssertFalse(v.output.contains("venue 'alpha'"), "修完的那筆不再有 error：\(v.output)")
        XCTAssertTrue(v.output.contains("venue 'beta'"), "判斷項仍由 validate 報：\(v.output)")
    }

    /// #298 閘真的接上了：假 home 的 registry 把 current 指到這個 scratch store，不帶 `--library` 的 `--apply` 拒絕且零寫入、
    /// 乾跑不被擋（它是用來確認目標的手段）、`--yes` 是知情同意的出路。
    func testApplyWithoutNamedTargetIsRefusedButDryRunIsNot() throws {
        try "files:\n  probe: \(root.path)\ncurrent: probe\n"
            .write(to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        let file = root.appendingPathComponent("entities/\(fixable.id.uuidString).yaml")
        let before = try Data(contentsOf: file)
        let bare = try CLITestHarness.run(["repair-venue-names", "--apply"], env: ["AKASHIC_HOME": home.path])
        XCTAssertNotEqual(bare.status, 0, bare.output)
        XCTAssertTrue(bare.output.contains("未指名目標 store") && bare.output.contains("dry-run"), bare.output)
        XCTAssertEqual(try Data(contentsOf: file), before, "被閘擋下＝零寫入")
        let dry = try CLITestHarness.run(["repair-venue-names"], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(dry.status, 0, dry.output)
        XCTAssertTrue(dry.output.contains("乾跑"), dry.output)
        let yes = try CLITestHarness.run(["repair-venue-names", "--apply", "--yes"], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(yes.status, 0, yes.output)
        XCTAssertEqual(try venue("alpha").names.entries.map(\.value), ["Alpha Journal"])
    }

    /// 帶了 --apply 而沒有可改的：標頭不得說「乾跑」也不得說「已寫入」。
    func testApplyWithNothingApplicableSaysSo() throws {
        XCTAssertEqual(try cli(["repair-venue-names", "--apply"]).status, 0)
        git(["add", "-A"]); git(["commit", "-q", "-m", "repaired"])
        let r = try cli(["repair-venue-names", "--apply"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("沒有可確定性改寫的項目"), r.output)
        XCTAssertFalse(r.output.contains("已寫入") || r.output.contains("乾跑"), r.output)
        XCTAssertTrue(r.output.contains("要人判斷"), "判斷項照列：\(r.output)")
    }

    func testApplyRefusesAnUncommittedStore() throws {
        let extra = Venue(key: "gamma", type: .periodical, names: Timeline([TemporalValue(value: " Gamma")]))
        try VenueYAML.encode(extra).write(to: root.appendingPathComponent("entities/\(extra.id.uuidString).yaml"),
                                          atomically: true, encoding: .utf8)
        let r = try cli(["repair-venue-names", "--apply"])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("#575"), r.output)
        XCTAssertEqual(try venue("alpha").names.entries.map(\.value), ["Alpha\tJournal "], "整批零寫入")
    }
}
