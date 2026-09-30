import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #705：寫進 `entities/`、搬移後的 legacy 拷貝沒刪掉的那一筆，CLI 面記在成功那一側（`writtenWithLegacyCopy`）。
///
/// 兩條出口，各走真 binary：
/// - 直接印 service JSON 的寫入命令（`update-person`、`tag`……）：鍵進那份 JSON，stdout 仍是合法 JSON。
/// - 其餘命令：CLI 進入點（`AkashicCLI.main`）的收集範圍在命令結束後把它印在輸出末尾——命令後來失敗也照印，
///   寫進去的那一筆不跟著錯誤一起消失。
///
/// 刪不掉的造法同 #702：legacy 檔受 git 追蹤、乾淨，所在目錄唯讀。work 的兩份共用 citekey，之後的 index rebuild 撞重複——
/// 會重建 index 的命令因此以非零結束，這是 store 的真實狀態（刪掉 legacy 那份之前 index 重建不了），不是這一筆寫入失敗。
final class LegacyCopyCLITests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!

    private var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }   // #239：hook 環境帶 GIT_DIR
    }

    private func git(_ args: [String]) {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
        p.environment = scrubbedGitEnvironment
        p.standardOutput = Pipe(); p.standardError = Pipe()
        try? p.run(); p.waitUntilExit()
    }

    private var store: LibraryStore { LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": home.path]) }

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-705-cli-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        for dir in [store.entriesDir, store.peopleDir] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }

    override func tearDownWithError() throws {
        for dir in [store.entriesDir, store.peopleDir] {
            try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: dir.path)
        }
        try? FileManager.default.removeItem(at: base)
    }

    private func commitAndLock(_ dir: URL) throws {
        git(["init", "-q"])
        git(["add", "-A"])
        git(["commit", "-q", "-m", "fixture"])
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: dir.path)
        let probe = dir.appendingPathComponent("probe-\(UUID().uuidString)")
        if FileManager.default.createFile(atPath: probe.path, contents: Data()) {
            try? FileManager.default.removeItem(at: probe)
            throw XCTSkip("這個環境的權限擋不住刪檔（以 root 執行？），造不出「寫完之後刪 legacy 失敗」")
        }
    }

    private func legacyWork() throws -> Entry {
        let e = Entry(id: UUID(), citekey: "cheng2025identifiability", type: .periodicalArticle,
                      title: "Identifiability of polychoric models", authors: [.literal("Che Cheng")], date: "2025")
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"),
                                      atomically: true, encoding: .utf8)
        try commitAndLock(store.entriesDir)
        return e
    }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args, env: ["AKASHIC_HOME": home.path])
    }

    /// 直接印 service JSON 的命令：鍵進 JSON、stdout 仍能整份解析、結束碼 0（person 的兩份不擋 index 重建，#670）。
    func testUpdatePersonPutsItInTheJSONItPrints() throws {
        let p = Person(key: "yang-hau-hung", names: PersonNames(variant: ["Hau-Hung Yang"]))
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        try commitAndLock(store.peopleDir)

        let r = try cli(["update-person", "--library", root.path, "--key", p.key, "--fields", #"{"note":"改過"}"#])
        XCTAssertEqual(r.status, 0, r.output)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any],
                                "stdout 必須仍是一份 JSON：\(r.output)")
        let rows = try XCTUnwrap(obj["writtenWithLegacyCopy"] as? [[String: String]], r.output)
        XCTAssertEqual(rows.first?["key"], p.key)
        XCTAssertEqual(rows.first?["legacyFile"], "people/\(p.key).yaml")
        XCTAssertEqual(rows.first?["kind"], "person")
    }

    /// 直接印 JSON 的命令後來失敗（tag 之後的 index rebuild 撞重複的 citekey）：沒有 JSON 可放，收到的交給 CLI 進入點，
    /// 在錯誤之前印出來。
    func testTagThatFailsAfterWritingStillReportsIt() throws {
        let e = try legacyWork()
        let r = try cli(["tag", "--library", root.path, e.citekey, "--add", "x"])
        XCTAssertNotEqual(r.status, 0, "前提：兩份並存時 index rebuild 撞重複的 citekey：\(r.output)")
        let line = try XCTUnwrap(r.output.split(separator: "\n").first { $0.hasPrefix("writtenWithLegacyCopy") }, r.output)
        XCTAssertTrue(line.hasSuffix(": 1"), String(line))
        XCTAssertTrue(r.output.contains("work「\(e.citekey)」"), r.output)
        XCTAssertTrue(r.output.contains("entries/\(e.citekey).yaml"), r.output)
        let onDisk = try String(contentsOf: store.entityURL(id: e.id), encoding: .utf8)
        XCTAssertTrue(onDisk.contains("- x"), "寫了：\(onDisk)")
    }

    /// 印人可讀文字的命令：CLI 進入點的收集範圍收下它、印在輸出末尾；逐筆失敗清單（「寫入失敗」）不含這一筆。
    func testATextCommandPrintsItAtTheEnd() throws {
        let e = try legacyWork()
        let proposals = base.appendingPathComponent("p.json")
        try #"[{"citekey":"cheng2025identifiability","fields":{"abstract":"摘要"}}]"#
            .write(to: proposals, atomically: true, encoding: .utf8)
        let r = try cli(["enrich", "--library", root.path, "--from", proposals.path, "--apply"])
        XCTAssertTrue(r.output.contains("writtenWithLegacyCopy"), r.output)
        XCTAssertTrue(r.output.contains("work「\(e.citekey)」"), r.output)
        XCTAssertFalse(r.output.contains("writeFailed"), "不是寫入失敗：\(r.output)")
    }
}
