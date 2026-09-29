import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #587 的 CLI 面：`update-venue --references` 與 `--add-issn "NNNN-NNNN (print)"` 走真 binary。
///
/// 參數解析（JSON 字串 → 陣列）住在 CLI 的 `validate()`／`run()`，只測服務層測不到它；用法錯誤要是 exit 64、早於開 store。
final class UpdateVenueReferencesCLITests: XCTestCase {
    private var tmp: URL!
    private var root: URL!
    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    override func setUpWithError() throws {
        tmp = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-uvref-\(UUID().uuidString)")
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

    /// #673：讀取面列出通用 references（人可讀與 --json 同源），`--remove-reference` 移除被定位到的那一筆——未 commit 拒絕、commit 後成功、
    /// 只移除 reference（號仍在）、理由只進報告。用真 binary：CLI 的選項名、`validate()` 的 JSON 解析與 `run()` 的轉送都只有實際呼叫抓得到。
    func testRemoveReferenceThroughTheCLI() throws {
        XCTAssertEqual(try run(["add-venue", "ampsy", "--names", "American Psychologist", "--type", "periodical", "--issn", "0003-066X (print)"]).status, 0)
        let refs = #"[{"field":"issn","value":"0003-066X","kind":"retrieval","url":"https://portal.issn.org/resource/ISSN/0003-066X","retrieved":"2026-09-29","status":200,"media_type":"text/html","content":"\#(digest)"}]"#
        XCTAssertEqual(try run(["update-venue", "ampsy", "--references", refs]).status, 0)

        let view = try run(["venue", "ampsy"])
        XCTAssertEqual(view.status, 0, view.output)
        XCTAssertTrue(view.output.contains("references（1）") && view.output.contains("portal.issn.org") && view.output.contains("retrieval"), "人可讀面：\(view.output)")
        let viewJSON = try run(["venue", "ampsy", "--json"])
        XCTAssertTrue(viewJSON.output.contains("\"references\"") && viewJSON.output.contains("\"referencesTotal\" : 1"), "--json 同源：\(viewJSON.output)")

        let removal = #"[{"field":"issn","value":"0003-066X","reason":"來源網址貼錯本刊"}]"#
        let notInGit = try run(["update-venue", "ampsy", "--remove-reference", removal])
        XCTAssertNotEqual(notInGit.status, 0, notInGit.output)
        XCTAssertTrue(notInGit.output.contains("git"), notInGit.output)
        XCTAssertEqual(try venue("ampsy").references.count, 1, "被閘擋下的呼叫不得寫")

        commitStore()
        let done = try run(["update-venue", "ampsy", "--remove-reference", removal])
        XCTAssertEqual(done.status, 0, done.output)
        XCTAssertTrue(done.output.contains("referencesRemoved") && done.output.contains("來源網址貼錯本刊"), done.output)
        XCTAssertEqual(try venue("ampsy").references.count, 0)
        XCTAssertEqual(try venue("ampsy").issn.map(\.normalized), ["0003-066X"], "只移除 reference，號仍在")
        let after = try run(["venue", "ampsy"])
        XCTAssertFalse(after.output.contains("references（"), "沒有通用 reference 時不印這一段：\(after.output)")
    }

    /// b13f R1 verify 第 17 列：`referenceDict` 的 `rests_on` 只列前 5 個、總數在 `rests_on_total`；人可讀面數陣列長度會在超過 5 個時印出「證據 5 份」。
    func testTheHumanReadableEvidenceCountUsesTheTotalNotTheCappedList() throws {
        XCTAssertEqual(try run(["add-venue", "ampsy", "--names", "American Psychologist", "--type", "periodical", "--issn", "0003-066X (print)"]).status, 0)
        let digests = (0..<7).map { "\"sha256:" + String(format: "%02x", $0 + 1) + String(repeating: "ef", count: 31) + "\"" }.joined(separator: ",")
        let refs = #"[{"field":"issn","value":"0003-066X","kind":"judgement","statement":"七份證據","rests_on":[\#(digests)]}]"#
        let added = try run(["update-venue", "ampsy", "--references", refs])
        XCTAssertEqual(added.status, 0, added.output)
        let view = try run(["venue", "ampsy"])
        XCTAssertEqual(view.status, 0, view.output)
        XCTAssertTrue(view.output.contains("證據 7 份"), "總數不是被截到 5 的陣列長度：\(view.output)")
        XCTAssertTrue(view.output.contains("只列前 5 個"), "被截時要說：\(view.output)")
        XCTAssertFalse(view.output.contains("證據 5 份"), view.output)
        let json = try run(["venue", "ampsy", "--json"])
        XCTAssertTrue(json.output.contains("\"rests_on_total\" : 7"), json.output)
    }

    func testMediumAndProvenanceLandThroughTheCLI() throws {
        let created = try run(["add-venue", "ampsy", "--names", "American Psychologist", "--type", "periodical",
                               "--issn", "0003-066X (print)"])
        XCTAssertEqual(created.status, 0, created.output)
        XCTAssertEqual(try venue("ampsy").issn.first?.medium, .print)

        let refs = #"[{"field":"issn","value":"0003-066x","kind":"retrieval","url":"https://portal.issn.org/resource/ISSN/0003-066X","retrieved":"2026-09-29","status":200,"media_type":"text/html","content":"\#(digest)"}]"#
        let updated = try run(["update-venue", "ampsy", "--add-issn", "1935-990X (electronic)", "--references", refs])
        XCTAssertEqual(updated.status, 0, updated.output)
        XCTAssertTrue(updated.output.contains("\"referencesAdded\" : 1") || updated.output.contains("\"referencesAdded\":1"),
                      updated.output)
        let v = try venue("ampsy")
        XCTAssertEqual(v.issn.map(\.medium), [.print, .electronic])
        XCTAssertEqual(v.references.first?.value, "0003-066X")
    }

    /// 只看參數的錯是用法錯誤（64）——`--references` 不是 JSON 陣列、歸屬不對、角色不在三值內。指向沒有佈局的目錄：
    /// 缺佈局不得搶先。
    func testArgvErrorsAreUsageErrors() throws {
        let bare = tmp.appendingPathComponent("not-a-store")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        let cases: [([String], String)] = [
            (["update-venue", "v-one", "--references", "{}"], "--references 必須是 JSON 陣列"),
            (["update-venue", "v-one", "--references", "not json"], "--references 必須是 JSON 陣列"),
            (["update-venue", "v-one", "--references",
              #"[{"field":"paginated","value":"true","kind":"judgement","statement":"s","rests_on":["\#(digest)"]}]"#],
             "clear_paginated"),
            (["update-venue", "v-one", "--references", #"[{"field":"issn","value":"0003-066X","kind":"retrieval","url":"u","retrieved":"d","content":"\#(digest)"}]"#],
             "status"),
            (["update-venue", "v-one", "--add-issn", "0003-066X (Online)"], "不是 ISSN 標準的三個角色"),
            // #673：--remove-reference 的 JSON、形狀、單獨呼叫
            (["update-venue", "v-one", "--remove-reference", "{}"], "--remove-reference 必須是 JSON 陣列"),
            (["update-venue", "v-one", "--remove-reference", #"[{"field":"issn","value":"0003-066X"}]"#], "缺理由"),
            (["update-venue", "v-one", "--remove-reference", #"[{"field":"resolution-confirmed","value":"work:x :: Y","reason":"r"}]"#], "resolve-venues"),
            (["update-venue", "v-one", "--remove-reference", #"[{"field":"paginated","value":"true","reason":"r"}]"#], "--clear-paginated"),
            (["update-venue", "v-one", "--remove-reference", #"[{"field":"issn","value":"0003-066X","reason":"r"}]"#, "--add-name", "X"], "單獨呼叫"),
            (["update-venue", "v-one", "--remove-reference", #"[{"field":"issn","value":"0003-066X","reason":"r"}]"#, "--note", "n"], "單獨呼叫"),
            (["add-venue", "v-one", "--names", "X", "--type", "periodical", "--issn", "0003-066X (print) (electronic)"],
             "不是合法的 ISSN"),
        ]
        for (args, needle) in cases {
            let r = try CLITestHarness.run(args + ["--library", bare.path], env: ["HOME": tmp.path, "AKASHIC_HOME": tmp.path])
            XCTAssertEqual(r.status, 64, "\(args)：\(r.output)")
            XCTAssertTrue(r.output.contains(needle), "\(args) 要說出「\(needle)」：\(r.output)")
            XCTAssertFalse(r.output.contains("不是 Akashic library"), "argv 錯誤不得被缺佈局搶先——\(args)：\(r.output)")
        }
    }
}
