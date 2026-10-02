import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #709 R2 verify（requirements／logic／regression／security／devils-advocate 五席，MEDIUM 2、3、5、7 與 LOW 17；MEDIUM 1、4、6 與 LOW 8）：
/// 「由記錄內容算出來的讀數以 entities/ 那份為準」先前只到 `StoreHealth` 的三項——
///
/// - CLI `akashic doctor` 的 `unresolved author literals` 自己從完整的 load 數（MCP 讀 `health`），`no authorized name`、`authorized only by
///   citation form`、`deceased with open affiliation`、`digest 形式的 source`、zero-dates 與日期值域的普查也吃完整的 load——同一份輸出
///   `entries: 1` 而 `unresolved author literals: 2`、`no authorized name` 把同一個 key 列兩次；
/// - `bootstrap-organizations` 只把 entries 換成視圖，person 的隸屬 literal 仍從完整的 load 來：拷貝獨有的機構名成為候選、
///   一次出現算兩次而越過 `--min-occurrences`；
/// - `library list` 把一對算成兩個成員。
///
/// 本檔走真 binary。doctor 那一支拿同一個 store 先跑一次（沒有拷貝）再加拷貝跑一次：`library:` 之後的普查段要逐行相同。
final class ShadowedPairCensusCLITests: XCTestCase {
    private var root: URL!
    private var fakeHome: URL!
    private var store: LibraryStore!

    private var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    private func cli(_ args: [String]) throws -> (status: Int32, output: String) {
        try CLITestHarness.run(args + ["--library", root.path], env: env)
    }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-709-census-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: fakeHome, withIntermediateDirectories: true)
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func writeEntities(_ e: Entry) throws {
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
    }

    private func writeEntities(_ p: Person) throws {
        try PersonYAML.encode(p).write(to: store.entityURL(id: p.id), atomically: true, encoding: .utf8)
    }

    private func writeLegacy(_ e: Entry) throws {
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"), atomically: true, encoding: .utf8)
    }

    private func writeLegacy(_ p: Person) throws {
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
    }

    /// `library:` 那一行之後的輸出（index 重建之後的統計與普查段）。
    private func census(_ output: String) -> [String] {
        let lines = output.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        guard let i = lines.firstIndex(where: { $0.hasPrefix("library: ") }) else { return lines }
        return Array(lines[(i + 1)...])
    }

    // MARK: - doctor

    func testDoctorCensusCountsAPairOnce() throws {
        let work = Entry(id: UUID(), citekey: "doe2020a", type: .periodicalArticle, title: "T",
                         authors: [.literal("Doe, A."), .literal("Roe, B.")], date: "2020")
        // 沒有對外名字、逝世卻有開放的隸屬段、隸屬的 source 是 digest、隸屬沒有日期、died 不合 ISO 8601——一筆觸發五項普查
        var unnamed = Person(key: "doe-a", names: PersonNames(variant: ["Doe, Alpha"]), died: "民國100")
        unnamed.profile.affiliations = TimelineOf<OrgRef>([
            TemporalValue(value: .literal("Institute of Testing"), source: "sha256:" + String(repeating: "a", count: 64))])
        let citationOnly = Person(key: "roe-b", names: PersonNames(authorized: ["Roe, B."]))
        try writeEntities(work)
        try writeEntities(unnamed)
        try writeEntities(citationOnly)

        let before = try cli(["doctor"])
        XCTAssertEqual(before.status, 0, before.output)
        // 前提：每一項普查在沒有拷貝時都有讀數（否則「相同」什麼都沒證）
        for expected in ["entries: 1", "people: 2", "unresolved author literals: 2", "no authorized name: 1 person / 0 organization（前 10：doe-a）",
                         "authorized only by citation form: 1 person", "deceased with open affiliation: 1 person", "digest 形式的 source: 1",
                         "timeline dimensions with zero dates: 1", "date-like values outside ISO 8601 prefix: 1"] {
            XCTAssertTrue(before.output.contains(expected), "前提：\(expected)\n\(before.output)")
        }

        try writeLegacy(work)
        try writeLegacy(unnamed)
        try writeLegacy(citationOnly)
        XCTAssertEqual(try store.load().entries.count, 2, "前提：完整的 load 兩份都在")
        XCTAssertEqual(try store.load().people.count, 4, "前提：完整的 load 兩份都在")

        let after = try cli(["doctor"])
        XCTAssertEqual(after.status, 0, after.output)
        XCTAssertTrue(after.output.contains("legacy 拷貝"), "前提：這一對有被認出來（crossRecordIssues 的 warning）：\(after.output)")
        XCTAssertEqual(census(after.output), census(before.output),
                       "同一筆記錄的 legacy 拷貝不讓 index 之後的任何讀數改變：\n--- 沒有拷貝 ---\n\(before.output)\n--- 有拷貝 ---\n\(after.output)")
    }

    // MARK: - bootstrap-organizations

    /// 兩份的隸屬 literal 不同：只取 entities/ 那份的。
    func testBootstrapOrganizationsTakesPersonLiteralsFromTheEntitiesCopyOnly() throws {
        var person = Person(key: "smith-j", names: PersonNames(authorized: ["Smith, John"]))
        person.profile.affiliations = TimelineOf<OrgRef>([TemporalValue(value: .literal("Institute of Real Things"))])
        var leftover = person
        leftover.profile.affiliations = TimelineOf<OrgRef>([TemporalValue(value: .literal("Institute of Real Things")),
                                                            TemporalValue(value: .literal("Ghost Institute Only In Legacy"))])
        try writeEntities(person)
        try writeLegacy(leftover)

        let r = try cli(["bootstrap-organizations", "--min-occurrences", "1"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("×1  Institute of Real Things"), "entities/ 那份的機構名是候選、只算一次：\(r.output)")
        XCTAssertFalse(r.output.contains("Ghost"), "legacy 拷貝獨有的機構名不該成為建檔候選：\(r.output)")
    }

    /// 兩份的隸屬 literal 相同：一次出現不因拷貝越過門檻。
    func testBootstrapOrganizationsDoesNotCountACopyTowardsTheThreshold() throws {
        var person = Person(key: "smith-j", names: PersonNames(authorized: ["Smith, John"]))
        person.profile.affiliations = TimelineOf<OrgRef>([TemporalValue(value: .literal("Institute of Real Things"))])
        try writeEntities(person)
        try writeLegacy(person)

        let r = try cli(["bootstrap-organizations", "--min-occurrences", "2"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertFalse(r.output.contains("Institute of Real Things"), "一次出現不該越過 --min-occurrences 2：\(r.output)")
        XCTAssertTrue(r.output.contains("無候選"), r.output)
    }

    // MARK: - library list

    func testLibraryListCountsAPairAsOneMember() throws {
        try store.writeLibrary(Library(key: "lib1", name: "L1", membership: .topic))
        var a = Entry(id: UUID(), citekey: "doe2020a", type: .periodicalArticle, title: "A", date: "2020")
        a.akashic.libraries = ["lib1"]
        var b = Entry(id: UUID(), citekey: "roe2021b", type: .periodicalArticle, title: "B", date: "2021")
        b.akashic.libraries = ["lib1"]
        try writeEntities(a)
        try writeEntities(b)
        try writeLegacy(a)

        let r = try cli(["library", "list"])
        XCTAssertEqual(r.status, 0, r.output)
        XCTAssertTrue(r.output.contains("L1（2 entries）"), "一對是一個成員：\(r.output)")
    }
}
