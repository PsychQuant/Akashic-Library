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
