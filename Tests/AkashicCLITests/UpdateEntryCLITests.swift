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
    private var zFile: URL!

    /// #239：hook 環境帶 `GIT_DIR`，`-C` 擋不住它——不剝的話 fixture 的 commit 會寫進使用者的 repo。
    private var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }

    /// fixture 的 git：固定 `/usr/bin/git`（不經 PATH）、以 `-C` 指向 store、環境用上面剝掉 `GIT_*` 的那份。
    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = scrubbedGitEnvironment
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
        // #680：帶兩個 Zotero 來源的 work（主來源 1:PRIM0001、附加來源 5:GRP00001）
        var withSources = Entry(id: UUID(), citekey: "z2020y", type: .periodicalArticle, title: "Z")
        withSources.provenance = Provenance(zoteroKey: "PRIM0001", zoteroVersion: 5, libraryID: 1)
        withSources.additionalProvenance = [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)]
        zFile = try store.writeEntry(withSources)
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
        // b11c R1 verify 第 11 列：連好的副本讀得出來（人可讀面與 --json 面）
        let got = try CLITestHarness.run(["get-entry", "x2020y", "--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(got.status, 0, got.output)
        XCTAssertTrue(got.output.contains("sources\t\(receipt.digest)"), "get-entry 要看得到連好的副本：\(got.output)")
        let gotJSON = try CLITestHarness.run(["get-entry", "x2020y", "--json", "--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertTrue(gotJSON.output.contains(receipt.digest), gotJSON.output)
    }

    /// #677：`--remove-source` 收回一條副本宣告——乾跑不寫、`--apply` 要指名目標、實寫只移除宣告（blob 與 index 不動）、理由只進報告。
    /// 用真 binary：CLI 的選項名、`validate()` 早退（64）與 `run()` 的閘都只有實際呼叫抓得到。
    func testRemoveSourceRetractsTheDeclarationOnly() throws {
        let store = LibraryStore(root: root, key: nil, environment: [:])
        let receipt = try store.storeSource(Data("%PDF-1.7 fixture".utf8), provenance: .init(
            mediaType: "application/pdf", retrieved: "2026-09-29T10:00:00+08:00",
            origin: "https://example.org/x.pdf", acquisition: "browser-download"))
        let link = try CLITestHarness.run(["update-entry", "x2020y", "--add-source", receipt.digest, "--apply", "--library", root.path],
                                          env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(link.status, 0, link.output)
        git(["add", "-A"]); git(["commit", "-q", "-m", "linked"])   // 實跑要求 work 檔已 commit、乾淨
        let indexBefore = try Data(contentsOf: root.appendingPathComponent("sources/index.jsonl"))
        let arg = ["update-entry", "x2020y", "--remove-source", "\(receipt.digest)=連到別篇的 PDF"]

        let dry = try CLITestHarness.run(arg + ["--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(dry.status, 0, dry.output)
        XCTAssertTrue(dry.output.contains("example.org") && dry.output.contains("連到別篇的 PDF"), "乾跑帶取得記錄與理由：\(dry.output)")
        XCTAssertEqual(try store.load().entries.first?.akashic.sources, [receipt.digest], "乾跑零寫入")

        let refused = try CLITestHarness.run(arg + ["--apply"], env: unnamedEnv)
        XCTAssertNotEqual(refused.status, 0, refused.output)
        XCTAssertTrue(refused.output.contains("update-entry --apply 拒絕執行：未指名目標 store"), refused.output)
        XCTAssertEqual(try store.load().entries.first?.akashic.sources, [receipt.digest], "被閘擋下的呼叫不得寫")

        let done = try CLITestHarness.run(arg + ["--apply", "--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertEqual(try store.load().entries.first?.akashic.sources, [], "宣告收回了")
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("sources/index.jsonl")), indexBefore, "取得記錄不動")
        let hex = String(receipt.digest.dropFirst("sha256:".count))
        XCTAssertTrue(FileManager.default.fileExists(atPath: root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))").path), "blob 不動")
        XCTAssertFalse(try String(contentsOf: file, encoding: .utf8).contains("連到別篇的 PDF"), "理由不寫進 store")
    }

    /// **CLI 全列、MCP 面才截**（b11c R1 verify 第 29／31 列）：21 份內容一次連，CLI 的報告要有全部 21 筆、`truncated` 是 false。
    func testAddSourceListsEverythingOnTheCLI() throws {
        let store = LibraryStore(root: root, key: nil, environment: [:])
        let digests = try (0..<21).map { i in
            try store.storeSource(Data("%PDF-1.7 blob \(i)".utf8), provenance: .init(
                mediaType: "application/pdf", retrieved: "2026-09-29T10:00:00+08:00",
                origin: "https://example.org/\(i).pdf", acquisition: "browser-download")).digest
        }
        let r = try CLITestHarness.run(["update-entry", "x2020y", "--add-source"] + digests + ["--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertEqual(digests.filter { r.output.contains($0) }.count, 21, "CLI 不截：\(r.output)")
        XCTAssertTrue(r.output.contains("\"sourcesAddedTotal\" : 21") && r.output.contains("\"truncated\" : false"), r.output)
    }

    /// #680：`--remove-zotero-source`——乾跑不寫也不過閘、`--apply` 未指名目標被閘擋下（拒絕在讀 store 之前）、指名之後照常寫，
    /// 理由只在報告裡（檔案裡找不到），報告帶連結狀態前後。用真 binary。
    func testRemoveZoteroSourceDryRunGateAndApply() throws {
        let args = ["update-entry", "z2020y", "--remove-zotero-source", "5:GRP00001=這個來源屬於另一篇，CLI 測試"]
        let before = try Data(contentsOf: zFile)
        let dry = try CLITestHarness.run(args + ["--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(dry.status, 0, dry.output)
        XCTAssertTrue(dry.output.contains("\"dryRun\" : true") && dry.output.contains("\"source\" : \"5:GRP00001\""), dry.output)
        XCTAssertEqual(try Data(contentsOf: zFile), before, "乾跑零寫入")
        let unnamedDry = try CLITestHarness.run(args, env: unnamedEnv)
        XCTAssertEqual(unnamedDry.status, 0, "乾跑不經過閘：\(unnamedDry.output)")

        let refused = try CLITestHarness.run(args + ["--apply"], env: unnamedEnv)
        XCTAssertNotEqual(refused.status, 0, refused.output)
        XCTAssertTrue(refused.output.contains("update-entry --apply 拒絕執行：未指名目標 store"), refused.output)
        XCTAssertEqual(try Data(contentsOf: zFile), before, "被擋的呼叫不得寫")

        let done = try CLITestHarness.run(args + ["--apply", "--library", root.path], env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertTrue(done.output.contains("\"dryRun\" : false") && done.output.contains("zoteroLinkState"), done.output)
        let store = LibraryStore(root: root, key: nil, environment: [:])
        let z = try XCTUnwrap(store.load().entries.first { $0.citekey == "z2020y" })
        XCTAssertEqual(z.additionalProvenance, [], "附加來源移除")
        XCTAssertEqual(z.provenance?.zoteroKey, "PRIM0001", "主來源不動")
        XCTAssertFalse(try String(contentsOf: zFile, encoding: .utf8).contains("CLI 測試"), "理由不寫進 store")
    }

    /// #680：未 commit 的修改讓 `--apply` 被拒（走真 binary，證明 CLI 面接到同一道閘）。
    func testRemoveZoteroSourceApplyRefusesAnUncommittedWork() throws {
        var z = try XCTUnwrap(LibraryStore(root: root, key: nil, environment: [:]).load().entries.first { $0.citekey == "z2020y" })
        z.fields["volume"] = "9"   // 未提交的修改
        _ = try LibraryStore(root: root, key: nil, environment: [:]).writeEntry(z)
        let r = try CLITestHarness.run(["update-entry", "z2020y", "--remove-zotero-source", "5:GRP00001=x", "--apply", "--library", root.path],
                                       env: ["AKASHIC_HOME": home.path])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("#680"), r.output)
        let after = try XCTUnwrap(LibraryStore(root: root, key: nil, environment: [:]).load().entries.first { $0.citekey == "z2020y" })
        XCTAssertEqual(after.additionalProvenance.count, 1, "零寫入")
    }
}
