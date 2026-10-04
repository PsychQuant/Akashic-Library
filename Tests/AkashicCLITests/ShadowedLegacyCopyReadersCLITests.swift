import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #709 R3 verify（requirements／logic／security／regression 四席）：「以 entities/ 那份為準」的視圖先前只到 index、三個匯出面與 App——
/// 同一筆記錄的 legacy 拷貝（`entries/`、`people/` 裡還在的那份）在別的讀取面照舊出現兩次，而且有一格是**寫入候選**：
/// `bootstrap-people` 對 legacy 拷貝裡多出來的作者 literal 建 person、每個 literal 的計數多算一份。
///
/// 本檔走真 binary：
/// - ~~`bootstrap-people`（與 `-organizations`、`-venues` 同一個作法）的 literal 來源只取 entities/ 那份~~（#709 第三次 verify：寫入候選面
///   收回到完整的 load，待使用者確認視圖的延伸；輸出說出計畫含幾份拷貝）；
/// - `view show --keys-only`（餵下游腳本）不列改名留下的舊 citekey。
final class ShadowedLegacyCopyReadersCLITests: XCTestCase {
    private var root: URL!
    private var fakeHome: URL!
    private var store: LibraryStore!

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-709-readers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func writeEntities(_ e: Entry) throws {
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
    }

    private func writeLegacy(_ e: Entry) throws {
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"), atomically: true, encoding: .utf8)
    }

    /// #709 第三次 verify：寫入候選面看完整的 load（R3 曾改用視圖，那一半待使用者確認、本輪收回）——legacy 拷貝裡多出來的 literal 也是候選、
    /// 一對相同的 literal 算兩次出現；輸出（`--json` 是 `legacyCopiesInPlan`）說出計畫含幾份拷貝。
    func testBootstrapPeopleReadsTheFullLoadAndSaysTheCopyIsInThePlan() throws {
        let id = UUID()
        let canonical = Entry(id: id, citekey: "doe2020a", type: .periodicalArticle, title: "T",
                              authors: [.literal("Doe, A.")], date: "2020")
        var leftover = canonical
        leftover.authors = [.literal("Doe, A."), .literal("Ghost, Zed.")]   // 只存在於 legacy 拷貝裡
        try writeEntities(canonical)
        try writeLegacy(leftover)

        let r = try cli(["bootstrap-people", "--json", "--min-occurrences", "1"])
        XCTAssertEqual(r.status, 0, r.output)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(r.output.utf8)) as? [String: Any], r.output)
        XCTAssertEqual(obj["legacyCopiesInPlan"] as? Int, 1, r.output)
        let candidates = try XCTUnwrap(obj["candidates"] as? [[String: Any]])
        XCTAssertTrue(candidates.contains { ($0["names"] as? [String])?.contains("Ghost, Zed.") == true }, "拷貝裡的 literal 不被安靜略過：\(candidates)")
        let doe = try XCTUnwrap(candidates.first { ($0["names"] as? [String])?.contains("Doe, A.") == true }, "\(candidates)")
        XCTAssertEqual(doe["occurrences"] as? Int, 2, "完整的 load：兩份各算一次")

        let text = try cli(["bootstrap-people", "--min-occurrences", "1"])
        XCTAssertTrue(text.output.contains("計畫含 1 份 legacy 拷貝"), text.output)
    }

    func testBootstrapVenuesReadsTheFullLoadAndSaysTheCopyIsInThePlan() throws {
        let id = UUID()
        var canonical = Entry(id: id, citekey: "doe2020a", type: .periodicalArticle, title: "T", date: "2020")
        canonical.fields["journaltitle"] = "Journal of Real Things"
        var leftover = canonical
        leftover.fields["journaltitle"] = "Ghost Quarterly"   // 手改過的 legacy 拷貝：index 與匯出看不到它，寫入候選面看得到
        try writeEntities(canonical)
        try writeLegacy(leftover)

        let r = try cli(["bootstrap-venues", "--min-occurrences", "1"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("Journal of Real Things"), r.output)
        XCTAssertTrue(r.output.contains("Ghost Quarterly"), "拷貝裡的刊名不被安靜略過：\(r.output)")
        XCTAssertTrue(r.output.contains("計畫含 1 份 legacy 拷貝"), r.output)
    }

    /// 改名留下的拷貝帶舊 citekey：`view show --keys-only` 餵下游腳本，不該把新舊兩個 citekey 並列。
    func testViewShowKeysOnlyDoesNotListTheOldCitekeyOfARenameLeftover() throws {
        try """
            views:
              iss:
                person-affiliation: iss
                work-has-author-in-view: true

            """.write(to: fakeHome.appendingPathComponent("config.yaml"), atomically: true, encoding: .utf8)
        var member = Person(key: "chen-c-h", names: PersonNames(authorized: ["Chen, C.-H."]))
        member.profile.affiliations = TimelineOf<OrgRef>([TemporalValue(value: OrgRef.key("iss"))])
        try PersonYAML.encode(member).write(to: store.entityURL(id: member.id), atomically: true, encoding: .utf8)
        let id = UUID()
        let renamed = Entry(id: id, citekey: "chen2020new", type: .periodicalArticle, title: "T",
                            authors: [.key("chen-c-h")], date: "2020")
        var oldName = renamed
        oldName.citekey = "chen2020old"
        try writeEntities(renamed)
        try writeLegacy(oldName)

        let r = try cli(["view", "show", "iss", "--keys-only"])
        XCTAssertEqual(r.status, 0, r.output)
        let lines = r.output.split(separator: "\n").map(String.init)
        XCTAssertTrue(lines.contains("chen2020new"), r.output)
        XCTAssertFalse(lines.contains("chen2020old"), "改名前的舊 citekey 是拷貝的，不該跟新的並列：\(r.output)")
    }
}
