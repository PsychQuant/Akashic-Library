import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #642 R1 verify 的 CLI 面（真 binary）：`library check` 印出完整規則、`set-kind` 印出被換掉的舊規則且替換既有規則要求
/// registry 檔已 commit、依據不明確（venue key 重複）時 add 拒絕且 check 揭露、`rename` 同批遷移規則並逐條印出。
/// #101/#112 的沙箱紀律：`--library` 指 scratch、`AKASHIC_HOME` 指 scratch。
final class LibraryRuleCLITests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var store: LibraryStore!

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: ["AKASHIC_HOME": home.path])
    }

    /// #239：hook 環境帶 `GIT_DIR`，`-C` 擋不住它——不剝的話 fixture 的 commit 會寫進使用者的 repo。
    private var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    private func commit() { git(["add", "-A"]); git(["commit", "-q", "--allow-empty", "-m", "fixture"]) }

    private func work(_ ck: String, venues: [VenueRef] = [], libraries: [String] = []) -> Entry {
        var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: ck, venues: venues)
        e.akashic.libraries = libraries
        return e
    }

    private let excluded = ["ex1-2020a", "ex2-2020a", "ex3-2020a"]

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-lrc-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try store.writeVenue(Venue(key: "pm", type: .periodical, names: Timeline([TemporalValue(value: "PM")])))
        try store.writeEntry(work("keep2020a", venues: [.key("pm")], libraries: ["pm-catalog"]))
        for ck in excluded { try store.writeEntry(work(ck, venues: [.key("pm")])) }
        try store.writeLibrary(Library(key: "pm-catalog", name: "PM", membership: .rule(LibraryRule(
            venue: "pm", types: [.periodicalArticle], excluded: excluded, source: "openalex:S1"))))
        git(["init", "-q"]); commit()
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    private func registry() throws -> Data { try Data(contentsOf: store.libraryURL(key: "pm-catalog")) }

    /// `set-kind` 是整值替換：要改一條帶排除清單的規則，操作者得看得到現在的每一個 citekey（list 只說「排除 N 筆」）。
    func testCheckPrintsTheFullRuleIncludingEveryExcludedCitekey() throws {
        let r = try cli(["library", "check", "pm-catalog"])
        XCTAssertEqual(r.status, 0, r.output)
        for ck in excluded { XCTAssertTrue(r.output.contains("    · \(ck)"), "\(ck)：\(r.output)") }
        XCTAssertTrue(r.output.contains("type：periodical-article") && r.output.contains("來歷：openalex:S1"), r.output)
        XCTAssertTrue(r.output.contains("排除（3 筆"), r.output)
    }

    func testSetKindPrintsTheReplacedRuleAndTheNextReplacementNeedsACommit() throws {
        var r = try cli(["library", "set-kind", "pm-catalog", "--kind", "topic"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("先前（已被替換；舊版在 git 裡）"), r.output)
        for ck in excluded { XCTAssertTrue(r.output.contains("· \(ck)"), "被換掉的舊規則要完整印出：\(r.output)") }
        XCTAssertTrue(r.output.contains("現在：主題型"), r.output)
        // 剛改寫、尚未 commit：再替換一次要拒絕（舊版只剩磁碟上這份，git 裡是更舊的）
        let dirty = try registry()
        r = try cli(["library", "set-kind", "pm-catalog", "--kind", "rule", "--venue", "pm"])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("git") && r.output.contains("pm-catalog"), r.output)
        XCTAssertEqual(try registry(), dirty, "拒絕＝零寫入")
        commit()
        r = try cli(["library", "set-kind", "pm-catalog", "--kind", "rule", "--venue", "pm"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("先前（已被替換；舊版在 git 裡）") && r.output.contains("主題型"), r.output)
    }

    func testSetKindRefusesAnExcludedCitekeyThatIsNotInTheStore() throws {
        let before = try registry()
        let r = try cli(["library", "set-kind", "pm-catalog", "--kind", "rule", "--venue", "pm", "--exclude", "nope2020a"])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("nope2020a") && r.output.contains("不在庫"), r.output)
        XCTAssertEqual(try registry(), before)
    }

    /// 規則建好之後 venue key 變成重複：add 不寫（CLI 與 MCP 同一條路徑），`check` 揭露。
    func testAnAmbiguousRuleVenueRefusesAddAndCheckSaysSo() throws {
        try store.writeVenue(Venue(key: "pm", type: .periodical, names: Timeline([TemporalValue(value: "PM again")])))
        try store.writeEntry(work("new2020a", venues: [.key("pm")]))
        var r = try cli(["library", "add", "pm-catalog", "new2020a"])
        XCTAssertEqual(r.status, 1, "全部不符＝零寫入，非零結束：\(r.output)")
        XCTAssertTrue(r.output.contains("不只一筆"), r.output)
        let entry = try XCTUnwrap(try store.load().entries.first { $0.citekey == "new2020a" })
        XCTAssertEqual(entry.akashic.libraries, [], "不寫")
        r = try cli(["library", "check", "pm-catalog"])
        XCTAssertTrue(r.output.contains("⚠ 依據不明確") && r.output.contains("不只一筆"), r.output)
    }

    /// 改名同批遷移規則、逐條印出；registry 檔剛改寫（未 commit）時下一次要遷移的改名拒絕。
    func testRenameMigratesTheRuleAndPrintsIt() throws {
        var r = try cli(["rename", "ex1-2020a", "ex1-2020b"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("library 成員規則已遷移"), r.output)
        XCTAssertTrue(r.output.contains("library「pm-catalog」的排除：ex1-2020a → ex1-2020b"), r.output)
        let rule = try XCTUnwrap(try store.load().libraries.first?.membership)
        XCTAssertEqual(rule, .rule(LibraryRule(venue: "pm", types: [.periodicalArticle],
                                               excluded: ["ex1-2020b", "ex2-2020a", "ex3-2020a"], source: "openalex:S1")))
        r = try cli(["rename", "ex2-2020a", "ex2-2020b"])
        XCTAssertNotEqual(r.status, 0, "registry 檔剛改寫、尚未 commit：\(r.output)")
        XCTAssertTrue(r.output.contains("git") && r.output.contains("pm-catalog"), r.output)
        XCTAssertTrue(try store.load().entries.contains { $0.citekey == "ex2-2020a" }, "拒絕＝零寫入")
        commit()
        r = try cli(["rename", "ex2-2020a", "ex2-2020b"])
        XCTAssertEqual(r.status, 0, r.output)
    }
}
