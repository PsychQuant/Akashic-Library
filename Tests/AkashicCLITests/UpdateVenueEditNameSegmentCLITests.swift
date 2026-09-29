import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #675 的 CLI 面：`update-venue --edit-name-segment` 走真 binary。
///
/// 參數解析（JSON 字串 → 陣列）住在 CLI 的 `validate()`／`run()`，只測服務層測不到它；用法錯誤要是 exit 64、早於開 store；
/// 讀取面（`venue`）要看得到 `source`／`note`，人可讀與 `--json` 同源。
final class UpdateVenueEditNameSegmentCLITests: XCTestCase {
    private var tmp: URL!
    private var root: URL!

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-uvseg-\(UUID().uuidString)")
        root = tmp.appendingPathComponent("store")
        try LibraryStore(root: root).ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: tmp) }

    private func run(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
    }
    private func venue(_ key: String) throws -> Venue {
        try XCTUnwrap(try LibraryStore(root: root).load().venues.first { $0.key == key })
    }
    /// #239：hook 環境帶 `GIT_DIR`，`-C` 擋不住它——不剝的話 fixture 的 commit 會寫進使用者的 repo。
    private var scrubbedGitEnvironment: [String: String] {
        ProcessInfo.processInfo.environment.filter { !$0.key.hasPrefix("GIT_") }
    }
    private func commitStore() {
        for args in [["init", "-q"], ["add", "-A"], ["commit", "-q", "--allow-empty", "-m", "fixture"]] {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: "/usr/bin/git")
            p.arguments = ["-C", root.path, "-c", "user.email=t@t", "-c", "user.name=t"] + args
            p.environment = scrubbedGitEnvironment
            p.standardOutput = Pipe(); p.standardError = Pipe()
            try? p.run(); p.waitUntilExit()
        }
    }

    /// 改一段名字的時間與 source／note：未 commit 拒絕、commit 後成功、報告帶前後與理由、讀取面看得到 source 與 note。
    func testEditNameSegmentThroughTheCLI() throws {
        XCTAssertEqual(try run(["add-venue", "sankhya", "--names", "Sankhyā", "Sankhya Old", "--type", "periodical"]).status, 0)
        let edit = #"[{"name":"Sankhyā","set":{"start":"1933","end":"1960","source":"https://example.org/a","note":"官網"},"reason":"補上沿革的起訖"}]"#

        let notInGit = try run(["update-venue", "sankhya", "--edit-name-segment", edit])
        XCTAssertNotEqual(notInGit.status, 0, notInGit.output)
        XCTAssertTrue(notInGit.output.contains("git"), notInGit.output)
        XCTAssertNil(try venue("sankhya").names.entries.first { $0.value == "Sankhyā" }?.range.start, "被閘擋下的呼叫不得寫")

        commitStore()
        let done = try run(["update-venue", "sankhya", "--edit-name-segment", edit])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertTrue(done.output.contains("nameSegments") && done.output.contains("補上沿革的起訖") && done.output.contains("\"action\" : \"set\""), done.output)
        let seg = try XCTUnwrap(try venue("sankhya").names.entries.first { $0.value == "Sankhyā" })
        XCTAssertEqual(seg.range.start, "1933")
        XCTAssertEqual(seg.range.end, "1960")
        XCTAssertEqual(seg.source, "https://example.org/a")
        XCTAssertEqual(seg.note, "官網")

        let view = try run(["venue", "sankhya"])
        XCTAssertEqual(view.status, 0, view.output)
        XCTAssertTrue(view.output.contains("start 1933") && view.output.contains("source 「https://example.org/a」") && view.output.contains("note 「官網」"),
                      "人可讀面要看得到 source 與 note：\(view.output)")
        let viewJSON = try run(["venue", "sankhya", "--json"])
        XCTAssertTrue(viewJSON.output.contains("\"source\" : \"https:\\/\\/example.org\\/a\"") && viewJSON.output.contains("\"note\" : \"官網\""), "--json 同源：\(viewJSON.output)")

        // 再刪掉舊寫法那一段（需要先 commit：上一次寫入讓檔案變成未提交）
        let stillDirty = try run(["update-venue", "sankhya", "--edit-name-segment", #"[{"name":"Sankhya Old","remove":true,"reason":"誤植"}]"#])
        XCTAssertNotEqual(stillDirty.status, 0, "上一次的改寫還沒 commit：\(stillDirty.output)")
        commitStore()
        let removed = try run(["update-venue", "sankhya", "--edit-name-segment", #"[{"name":"Sankhya Old","remove":true,"reason":"誤植"}]"#])
        XCTAssertEqual(removed.status, 0, removed.output)
        XCTAssertEqual(try venue("sankhya").names.entries.map(\.value), ["Sankhyā"])
    }

    /// 只看參數的錯是用法錯誤（64）——不是 JSON 陣列、形狀不對、單獨呼叫。指向沒有佈局的目錄：缺佈局不得搶先。
    func testArgvErrorsAreUsageErrors() throws {
        let bare = tmp.appendingPathComponent("not-a-store")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        let cases: [([String], String)] = [
            (["update-venue", "v-one", "--edit-name-segment", "{}"], "--edit-name-segment 必須是 JSON 陣列"),
            (["update-venue", "v-one", "--edit-name-segment", "not json"], "--edit-name-segment 必須是 JSON 陣列"),
            (["update-venue", "v-one", "--edit-name-segment", "[]"], "空陣列"),
            (["update-venue", "v-one", "--edit-name-segment", #"[{"name":"X","set":{"note":"n"}}]"#], "缺理由"),
            (["update-venue", "v-one", "--edit-name-segment", #"[{"name":"X","reason":"r"}]"#], "缺 set"),
            (["update-venue", "v-one", "--edit-name-segment", #"[{"name":"X","set":{"note":"n"},"remove":true,"reason":"r"}]"#], "不得同時給"),
            (["update-venue", "v-one", "--edit-name-segment", #"[{"name":"X","set":{"start":1933},"reason":"r"}]"#], "必須是字串或 null"),
            (["update-venue", "v-one", "--edit-name-segment", #"[{"name":"X","set":{"ended_unknown":true},"reason":"r"}]"#], "不認得的鍵"),
            (["update-venue", "v-one", "--edit-name-segment", #"[{"name":"X","set":{"note":"n"},"reason":"r"}]"#, "--add-name", "Y"], "單獨呼叫"),
            (["update-venue", "v-one", "--edit-name-segment", #"[{"name":"X","set":{"note":"n"},"reason":"r"}]"#, "--authorize", "Y"], "單獨呼叫"),
            (["update-venue", "v-one", "--edit-name-segment", #"[{"name":"X","set":{"note":"n"},"reason":"r"}]"#,
              "--remove-reference", #"[{"field":"issn","value":"0003-066X","reason":"r"}]"#], "單獨呼叫"),
        ]
        for (args, needle) in cases {
            let r = try CLITestHarness.run(args + ["--library", bare.path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
            XCTAssertEqual(r.status, 64, "\(args)：\(r.output)")
            XCTAssertTrue(r.output.contains(needle), "\(args) 要說出「\(needle)」：\(r.output)")
            XCTAssertFalse(r.output.contains("不是 Akashic library"), "argv 錯誤不得被缺佈局搶先——\(args)：\(r.output)")
        }
    }
}
