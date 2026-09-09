import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import akashic

/// #547：`bootstrap-people` 的第四段（彼此互為異寫、兩邊都還沒有記錄）與兩個出口。
///
/// **走真 binary**，經 `CLITestHarness`（不自己複製 `runCLI`——那個 harness 的檔頭
/// 記著它被複製成三份的教訓）。
///
/// 本檔測的是 model 層測不到的三件事：
/// 1. 那一段**真的被印出來**（`lossless-intake` 執行細節 3：只在 model 端加欄位而
///    沒有任何輸出讀它，與丟棄在效果上完全相同——本 repo 已在 #236 R3 踩過）
/// 2. 候選段的顯示上限**走 `AmbiguityDisplayLimit.rows` 而非寫死的 20**
/// 3. `--json` 與人可讀面**同源**
final class BootstrapPeopleMutualCLITests: XCTestCase {
    var root: URL!
    var fakeHome: URL!

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-bpm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        let store = LibraryStore(root: root)
        try store.ensureLayout()

        // 三種 Dweck 寫法，彼此共鍵而**都還沒有 person 記錄**
        for (ck, name) in [("a2020", "Carol S Dweck"),
                           ("b2021", "Carol S. Dweck"),
                           ("c2022", "C. S. Dweck")] {
            try store.writeEntry(Entry(id: UUID(), citekey: ck, type: .periodicalArticle,
                                       title: "T", authors: [.literal(name)], date: "2020"))
        }
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    /// 第四段真的被印出來，而且三個寫法在同一列。
    func testMutualSectionIsActuallyPrinted() throws {
        let r = try cli(["bootstrap-people", "--min-occurrences", "1"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("兩邊都還沒有記錄"),
                      "第四段沒有被印出來——只在 model 端加欄位等同丟棄：\n\(r.output)")
        XCTAssertTrue(r.output.contains("Carol S Dweck")
                        && r.output.contains("C. S. Dweck"),
                      "三個寫法要在同一組裡看得到：\n\(r.output)")
    }

    /// 扣住的成員不得同時出現在建檔候選段。
    func testWithheldMembersAreNotAlsoListedAsCandidates() throws {
        let r = try cli(["bootstrap-people", "--min-occurrences", "1"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertFalse(r.output.contains("dweck-carol-s"),
                       "被扣住的組不該有建檔 key 出現在候選段：\n\(r.output)")
    }

    /// 顯示上限走 `AmbiguityDisplayLimit.rows`，不是寫死的 20。
    ///
    /// **不比對數字字面**（那會在改常數時假綠），而是造 21 個彼此無關的候選：
    /// 寫死 20 時會出現截斷行，走 `rows`（50）時不會。
    func testCandidateDisplayCapFollowsAmbiguityDisplayLimit() throws {
        let store = LibraryStore(root: root)
        for i in 0..<21 {
            try store.writeEntry(Entry(id: UUID(), citekey: "z\(i)2020",
                                       type: .periodicalArticle, title: "T",
                                       authors: [.literal("Unique\(i) Surname\(i)")],
                                       date: "2020"))
        }
        let r = try cli(["bootstrap-people", "--min-occurrences", "1"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertGreaterThan(AmbiguityDisplayLimit.rows, 21,
                             "本測試的前提是上限 > 21；常數改小要重挑 fixture")
        XCTAssertFalse(r.output.contains("只列前 20"),
                       "候選段仍在用寫死的 20：\n\(r.output)")
    }

    /// `--json` 與人可讀面同源——四段都在，且 `pendingMutual` 有那一組。
    func testJSONCarriesAllFourSections() throws {
        let r = try cli(["bootstrap-people", "--min-occurrences", "1", "--json"])
        XCTAssertEqual(r.status, 0, r.output)
        let data = Data(r.output.utf8)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: data) as? [String: Any],
                                "--json 的輸出不是一個 JSON object：\n\(r.output)")
        for k in ["candidates", "unkeyable", "pendingResolution", "pendingMutual"] {
            XCTAssertNotNil(obj[k], "缺少 `\(k)` 段：\(obj.keys.sorted())")
        }
        let mutual = try XCTUnwrap(obj["pendingMutual"] as? [[String: Any]])
        XCTAssertEqual(mutual.count, 1, "三種 Dweck 寫法要收攏成一組：\(mutual)")
        let names = try XCTUnwrap(mutual.first?["names"] as? [String])
        XCTAssertEqual(Set(names), ["Carol S Dweck", "Carol S. Dweck", "C. S. Dweck"])
    }

    /// **`--json` 的 `display-safe-exempt` 前提，釘住。**
    ///
    /// 那四行豁免的理由是「消毒層是 `JSONSerialization` 自己」。豁免不能只是一句宣稱——
    /// 這條測試證明它：塞一個含裸 ESC／BEL 的作者名，斷言輸出裡**沒有任何裸控制位元組**，
    /// 而且那個名字**逐字**取得回來（消毒過就取不回來，`add-person` 會建錯名字）。
    ///
    /// 若哪天序列化選項改成不逃脫控制字元，這條會紅——那正是要它的時候。
    func testJSONOutputHasNoRawControlBytes() throws {
        let evil = "A\u{001B}[31mB\u{0007} Chen"
        let store = LibraryStore(root: root)
        try store.writeEntry(Entry(id: UUID(), citekey: "e2020evil", type: .periodicalArticle,
                                   title: "T", authors: [.literal(evil)], date: "2020"))

        let r = try cli(["bootstrap-people", "--min-occurrences", "1", "--json"])
        XCTAssertEqual(r.status, 0, r.output)

        let bytes = Array(r.output.utf8)
        let rawControl = bytes.filter { $0 < 0x20 && $0 != 0x0A && $0 != 0x09 }
        XCTAssertTrue(rawControl.isEmpty,
                      "JSON 輸出含裸控制位元組 \(rawControl.map { String(format: "0x%02x", $0) })"
                        + " —— display-safe-exempt 的前提不成立了")

        // 逐字取回：消毒過的字串在這裡會對不上
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(bytes)) as? [String: Any])
        let all = ((obj["candidates"] as? [[String: Any]]) ?? [])
            .compactMap { $0["names"] as? [String] }.flatMap { $0 }
        XCTAssertTrue(all.contains(evil),
                      "literal 必須逐字取得回來（消費端要拿它餵 add-person）：\(all)")
    }
}
