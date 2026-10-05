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
///   收回到完整的 load；使用者 2026-10-05 裁決維持它，並裁定計畫讀到拷貝時 `--apply` 整批拒絕；乾跑說出計畫讀到幾份拷貝）；
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

    /// #709 第三次 verify：寫入候選面看完整的 load（R3 曾改用視圖；使用者 2026-10-05 裁決不延伸視圖）——legacy 拷貝裡多出來的 literal 也是候選、
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

    /// 使用者 2026-10-05 裁決 2（#709 第四次 verify MEDIUM 5，LOW 6、13、15）：計畫讀到 legacy 拷貝時 `--apply` 整批拒絕、零寫入——先前附註之後照寫，
    /// 一篇 work 加它的拷貝讓 `Doe, A.` 以 ×2 越過 `--min-occurrences 2` 而建檔。乾跑照常列出並說明。
    func testBootstrapPeopleApplyIsRefusedWhenThePlanReadsAWorkCopy() throws {
        let canonical = Entry(id: UUID(), citekey: "doe2020a", type: .periodicalArticle, title: "T",
                              authors: [.literal("Doe, A.")], date: "2020")
        try writeEntities(canonical)
        try writeLegacy(canonical)

        let dry = try cli(["bootstrap-people", "--min-occurrences", "2"])
        XCTAssertEqual(dry.status, 0, dry.output)
        XCTAssertTrue(dry.output.contains("×2  Doe, A."), "乾跑照常列出：\(dry.output)")
        XCTAssertTrue(dry.output.contains("--apply 會整批拒絕、零寫入") && dry.output.contains("entries/doe2020a.yaml"), dry.output)

        let before = try storeFiles()
        let r = try cli(["bootstrap-people", "--min-occurrences", "2", "--apply"])
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("整批拒絕、零寫入") && r.output.contains("entries/doe2020a.yaml")
                      && r.output.contains("確認 entities/ 那份是新的之後"), r.output)
        XCTAssertEqual(try storeFiles(), before, "零寫入")
    }

    func testBootstrapVenuesApplyIsRefusedWhenThePlanReadsAWorkCopy() throws {
        var canonical = Entry(id: UUID(), citekey: "doe2020a", type: .periodicalArticle, title: "T", date: "2020")
        canonical.fields["journaltitle"] = "Journal of Alpha Things"
        try writeEntities(canonical)
        try writeLegacy(canonical)

        let before = try storeFiles()
        let r = try cli(["bootstrap-venues", "--min-occurrences", "2", "--apply"])
        XCTAssertEqual(r.status, 1, r.output)
        XCTAssertTrue(r.output.contains("bootstrap-venues --apply") && r.output.contains("整批拒絕、零寫入"), r.output)
        XCTAssertEqual(try storeFiles(), before, "零寫入")
    }

    /// #709 第四次 verify（MEDIUM 1、3，LOW 11）：只有一份改名留下的 **person** 拷貝——people／venues 的計畫只讀 entries，那份拷貝不在計畫裡：
    /// 不印附註、`--json` 沒有 `legacyCopiesInPlan`、`--apply` 照常寫入。先前兩個命令都說「計畫含 1 份、拷貝裡的 literal 也是候選」。
    func testAPersonOnlyCopyIsNotInThePeopleOrVenuesPlan() throws {
        let id = UUID()
        try PersonYAML.encode(Person(key: "kim-c", names: PersonNames(authorized: ["Kim, Chris"]), id: id))
            .write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        try PersonYAML.encode(Person(key: "old-kim", names: PersonNames(authorized: ["Kim, Chris"]), id: id))
            .write(to: store.personURL(key: "old-kim"), atomically: true, encoding: .utf8)
        var work = Entry(id: UUID(), citekey: "doe2020a", type: .periodicalArticle, title: "T",
                         authors: [.literal("Doe, A.")], date: "2020")
        work.fields["journaltitle"] = "Journal of Real Things"
        try writeEntities(work)
        XCTAssertEqual(try store.load().shadowedLegacyCopies.map(\.key), ["old-kim"], "前提：load 認得出這份 person 拷貝")

        let json = try cli(["bootstrap-people", "--json"])
        XCTAssertEqual(json.status, 0, json.output)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(json.output.utf8)) as? [String: Any], json.output)
        XCTAssertNil(obj["legacyCopiesInPlan"], "person 拷貝不進作者 literal 的來源：\(json.output)")
        for command in ["bootstrap-people", "bootstrap-venues"] {
            let dry = try cli([command])
            XCTAssertEqual(dry.status, 0, dry.output)
            XCTAssertFalse(dry.output.contains("legacy 拷貝"), "\(command)：\(dry.output)")
            let r = try cli([command, "--apply"])
            XCTAssertEqual(r.status, 0, "\(command) --apply 不被計畫沒讀到的拷貝擋：\(r.output)")
        }
        let load = try store.load()
        XCTAssertTrue(load.people.contains { $0.key == "doe-a" }, "bootstrap-people 寫入了")
        XCTAssertTrue(load.venues.contains { $0.key == "journal-of-real-things" }, "bootstrap-venues 寫入了")
    }

    /// store 裡每個 YAML 檔的位元組（相對路徑 → 內容）——零寫入的量法。
    private func storeFiles() throws -> [String: Data] {
        var out: [String: Data] = [:]
        for dir in [store.entitiesDir, store.entriesDir, store.peopleDir] {
            for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                out[dir.lastPathComponent + "/" + url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
        return out
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
