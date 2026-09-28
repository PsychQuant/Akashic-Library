import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// `update-entry` 的 CLI 面（#544）：預設乾跑、`--apply` 走目標確認閘、指名之後照常寫。用真 binary
/// （#101/#112 的沙箱紀律：store 與 `AKASHIC_HOME` 都指 scratch）。服務層的契約由 `EntryFieldRemovalTests` 釘。
final class UpdateEntryCLITests: XCTestCase {
    private var root: URL!
    private var home: URL!
    private var file: URL!

    /// #239：hook 環境帶 `GIT_DIR`，`-C` 擋不住它——不剝的話 fixture 的 commit 會寫進使用者的 repo。
    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    override func setUpWithError() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-update-entry-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        let e = Entry(id: UUID(), citekey: "x2020y", type: .periodicalArticle, title: "T",
                      fields: ["abstract": "This DOI is not currently attached to any metadata records.", "volume": "3"])
        file = try store.writeEntry(e)
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "fixture"])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root.deletingLastPathComponent()) }

    private var unnamedEnv: [String: String] { ["AKASHIC_LIBRARY": root.path, "AKASHIC_HOME": home.path, "HOME": home.path] }
    private let removal = ["update-entry", "x2020y", "--remove-field", "abstract=Crossref 的錯誤頁，不是摘要"]

    func testDryRunIsTheDefault() throws {
        let before = try Data(contentsOf: file)
        let r = try CLITestHarness.run(removal + ["--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("\"dryRun\" : true"), r.output)
        XCTAssertEqual(try Data(contentsOf: file), before, "乾跑零寫入")
        // 乾跑不經過閘：未指名目標也照常印計畫
        let unnamed = try CLITestHarness.run(removal, env: unnamedEnv)
        XCTAssertEqual(unnamed.status, 0, unnamed.output)
        XCTAssertFalse(unnamed.output.contains("未指名目標 store"), unnamed.output)
    }

    func testApplyNeedsANamedTargetThenWrites() throws {
        let refused = try CLITestHarness.run(removal + ["--apply"], env: unnamedEnv)
        XCTAssertNotEqual(refused.status, 0, refused.output)
        XCTAssertTrue(refused.output.contains("update-entry --apply 拒絕執行：未指名目標 store"), refused.output)
        let store = LibraryStore(root: root, key: nil, environment: [:])
        XCTAssertNotNil(try store.load().entries.first?.fields["abstract"], "被擋的呼叫不得寫")

        let done = try CLITestHarness.run(removal + ["--apply", "--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertTrue(done.output.contains("\"dryRun\" : false"), done.output)
        let e = try XCTUnwrap(store.load().entries.first)
        XCTAssertNil(e.fields["abstract"])
        XCTAssertEqual(e.fields["volume"], "3")
    }

    /// #614：`--add-source` 把已存的內容寫進 `akashic.sources`——乾跑不寫、`--apply` 寫、再跑一次是 no-op。
    func testAddSourceLinksStoredContent() throws {
        let store = LibraryStore(root: root, key: nil, environment: [:])
        let receipt = try store.storeSource(Data("%PDF-1.7 fixture".utf8), provenance: .init(
            mediaType: "application/pdf", retrieved: "2026-09-29T10:00:00+08:00",
            origin: "https://example.org/x.pdf", acquisition: "browser-download"))
        let arg = ["update-entry", "x2020y", "--add-source", receipt.digest, "--library", root.path]
        let dry = try CLITestHarness.run(arg, env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(dry.status, 0, dry.output)
        XCTAssertTrue(dry.output.contains("example.org") && dry.output.contains("\"mediaType\" : \"application"), "乾跑帶 index 的取得記錄：\(dry.output)")
        XCTAssertEqual(try store.load().entries.first?.akashic.sources, [], "乾跑零寫入")

        let done = try CLITestHarness.run(arg + ["--apply"], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertEqual(try store.load().entries.first?.akashic.sources, [receipt.digest])
        let bytes = try Data(contentsOf: file)
        let again = try CLITestHarness.run(arg + ["--apply"], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(again.status, 0, again.output)
        XCTAssertTrue(again.output.contains("sourcesAlreadyPresent"), again.output)
        XCTAssertEqual(try Data(contentsOf: file), bytes, "冪等：沒有新東西就不寫")
    }
}
