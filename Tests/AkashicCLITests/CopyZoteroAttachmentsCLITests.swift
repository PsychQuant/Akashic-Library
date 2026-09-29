import XCTest
import CryptoKit
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #606：`copy-zotero-attachments` 的 CLI 面——用真 binary（#101/#112 的沙箱紀律：`--library` 指 scratch、`AKASHIC_HOME` 指 scratch、Zotero 資料目錄是假的）。
/// 乾跑真的印計畫且零寫入、`--apply` 真的複製並連結、可重跑、目標確認閘（#298）真的接上、`--zotero-db` 指向沒有 storage/ 的目錄有具名錯誤。
final class CopyZoteroAttachmentsCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!
    private var zdir: URL!
    private var entry: Entry!
    private let pdf = Data("%PDF-1.7 cli copy".utf8)

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

    private var digest: String { "sha256:" + SHA256.hash(data: pdf).map { String(format: "%02x", $0) }.joined() }
    private func blob() -> URL {
        let hex = String(digest.dropFirst("sha256:".count))
        return root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
    }
    private var dbArgs: [String] { ["--zotero-db", zdir.appendingPathComponent("zotero.sqlite").path] }
    private func work() throws -> Entry {
        try XCTUnwrap(LibraryStore(root: root, key: nil, environment: [:]).load().entries.first { $0.citekey == "a2025" })
    }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-czacli-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        zdir = base.appendingPathComponent("zotero")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zdir.appendingPathComponent("storage/ABCD1234"), withIntermediateDirectories: true)
        try Data().write(to: zdir.appendingPathComponent("zotero.sqlite"))
        try pdf.write(to: zdir.appendingPathComponent("storage/ABCD1234/paper.pdf"))
        let store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        entry = Entry(id: UUID(), citekey: "a2025", type: .periodicalArticle, title: "T",
                      attachments: [AttachmentRef(kind: .zotero, path: "storage/ABCD1234/paper.pdf")])
        try store.writeEntry(entry)
        git(["init", "-q"]); git(["add", "-A"]); git(["commit", "-q", "-m", "fixture"])
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    func testDryRunPrintsThePlanAndWritesNothing() throws {
        let before = try Data(contentsOf: LibraryStore(root: root, key: nil, environment: [:]).entityURL(id: entry.id))
        let r = try cli(["copy-zotero-attachments"] + dbArgs)
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("乾跑"), r.output)
        XCTAssertTrue(r.output.contains("a2025") && r.output.contains("storage/ABCD1234/paper.pdf") && r.output.contains(digest), r.output)
        XCTAssertTrue(r.output.contains("--apply"), r.output)
        XCTAssertEqual(try Data(contentsOf: LibraryStore(root: root, key: nil, environment: [:]).entityURL(id: entry.id)), before, "乾跑零寫入")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blob().path))
    }

    func testApplyCopiesLinksAndValidateIsClean() throws {
        let r = try cli(["copy-zotero-attachments", "--apply"] + dbArgs)
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("已寫入") && r.output.contains("已改寫 1 筆"), r.output)
        XCTAssertTrue(r.output.contains("版控排除已驗證"), r.output)
        XCTAssertEqual(try Data(contentsOf: blob()), pdf)
        let e = try work()
        XCTAssertEqual(e.akashic.sources, [digest])
        XCTAssertEqual(e.attachments, entry.attachments, "zotero: 附件記錄原樣保留")
        let v = try cli(["validate"])
        XCTAssertEqual(v.status, 0, v.output)
        XCTAssertFalse(v.output.contains("本機缺承重存檔"), "連的 digest 在本機 sources/：\(v.output)")
    }

    func testRerunSaysThereIsNothingToCopy() throws {
        XCTAssertEqual(try cli(["copy-zotero-attachments", "--apply"] + dbArgs).status, 0)
        git(["add", "-A"]); git(["commit", "-q", "-m", "copied"])
        let r = try cli(["copy-zotero-attachments", "--apply"] + dbArgs)
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("沒有新東西要複製") && r.output.contains("已連過：1"), r.output)
        XCTAssertFalse(r.output.contains("已寫入") || r.output.contains("乾跑"), r.output)
    }

    /// #298 閘真的接上了：假 home 的 registry 把 current 指到這個 scratch store，不帶 `--library` 的 `--apply` 拒絕且零寫入、
    /// 乾跑不被擋（它是用來確認目標的手段）、`--yes` 是知情同意的出路。
    func testApplyWithoutNamedTargetIsRefusedButDryRunIsNot() throws {
        try "files:\n  probe: \(root.path)\ncurrent: probe\n"
            .write(to: home.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        let bare = try CLITestHarness.run(["copy-zotero-attachments", "--apply"] + dbArgs, env: ["AKASHIC_HOME": home.path])
        XCTAssertNotEqual(bare.status, 0, bare.output)
        XCTAssertTrue(bare.output.contains("未指名目標 store") && bare.output.contains("dry-run"), bare.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blob().path), "被閘擋下＝零寫入")
        let dry = try CLITestHarness.run(["copy-zotero-attachments"] + dbArgs, env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(dry.status, 0, dry.output)
        let yes = try CLITestHarness.run(["copy-zotero-attachments", "--apply", "--yes"] + dbArgs, env: ["AKASHIC_HOME": home.path])
        XCTAssertEqual(yes.status, 0, yes.output)
        XCTAssertEqual(try work().akashic.sources, [digest])
    }

    /// 被改寫的 work 檔有未 commit 的修改：實跑整批拒絕、零寫入；乾跑照印計畫並預告拒絕。
    func testApplyRefusesAnUncommittedWorkFile() throws {
        var edited = try work()
        edited.title = "uncommitted"
        try LibraryStore(root: root, key: nil, environment: [:]).writeEntry(edited)
        let dry = try cli(["copy-zotero-attachments"] + dbArgs)
        XCTAssertEqual(dry.status, 0, dry.output)
        XCTAssertTrue(dry.output.contains("--apply 會整批拒絕") && dry.output.contains("#606"), dry.output)
        let r = try cli(["copy-zotero-attachments", "--apply"] + dbArgs)
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("#606"), r.output)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blob().path))
        XCTAssertEqual(try work().akashic.sources, [])
    }

    func testMissingStorageDirectoryIsANamedError() throws {
        let bare = base.appendingPathComponent("bare")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try Data().write(to: bare.appendingPathComponent("zotero.sqlite"))
        let r = try cli(["copy-zotero-attachments", "--zotero-db", bare.appendingPathComponent("zotero.sqlite").path])
        XCTAssertNotEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("storage/"), r.output)
    }

    func testEmptyCitekeyListIsAUsageError() throws {
        let r = try cli(["copy-zotero-attachments", "--citekeys", " , "] + dbArgs)
        XCTAssertEqual(r.status, 64, r.output)
        XCTAssertTrue(r.output.contains("--citekeys"), r.output)
    }

    /// 略過的附件具名印出（檔案不在 Zotero 資料目錄裡），其餘照跑。
    func testSkippedAttachmentsAreNamedInTheOutput() throws {
        var e = try work()
        e.attachments.append(AttachmentRef(kind: .zotero, path: "storage/GONEKEY1/gone.pdf"))
        try LibraryStore(root: root, key: nil, environment: [:]).writeEntry(e)
        git(["add", "-A"]); git(["commit", "-q", "-m", "second attachment"])
        let r = try cli(["copy-zotero-attachments", "--apply"] + dbArgs)
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("storage/GONEKEY1/gone.pdf") && r.output.contains("沒有這個檔"), r.output)
        XCTAssertEqual(try work().akashic.sources, [digest], "另一個附件照複製")
    }
}
