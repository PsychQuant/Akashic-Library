import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #709 R3 verify：同一筆記錄的 legacy 拷貝（同一種、同一個 id，一份在 `entities/`）在讀取面的三處不一致。
///
/// 1. `validate` 的「DOI 被 N 筆 work 共用」與「標題與年份相同但 DOI 不同」把拷貝算成另一筆——一對就多報一則（甚至在拷貝連 DOI 都沒有時
///    說「DOI 不同」），12 對就是 12 則誤導的警告，還把整合性警告擠出 MCP 的前 20 則（requirements／regression 兩席）；
/// 2. `StoreHealth` 的未歸戶作者讀數（`literal-first-then-key` 的進度量測）把拷貝算兩次，doctor 印 `entries: 1` 而 `unresolved author literals: 2`；
/// 3. `akashic people`／`akashic_people` 把同一個 person key 列兩次，其中一份是舊名字。
///
/// 真的重複（兩筆**不同**的記錄）照舊要報——本檔每一格都有對照組。
final class ShadowedPairReadersTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-709-readers-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func writeEntities(_ e: Entry) throws {
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
    }

    private func writeLegacy(_ e: Entry) throws {
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        try EntryYAML.encode(e).write(to: store.entriesDir.appendingPathComponent("\(e.citekey).yaml"), atomically: true, encoding: .utf8)
    }

    private func messages() throws -> [String] { try store.load().crossRecordIssues().map(\.message) }

    // MARK: - 1. 重複 DOI／標題偵測

    func testAPairWithoutADOIIsNotReportedAsTheSameTitleWithDifferentDOIs() throws {
        let e = Entry(id: UUID(), citekey: "anon2021work", type: .periodicalArticle, title: "A Shared Title", date: "2021")
        try writeEntities(e)
        try writeLegacy(e)
        let all = try messages()
        XCTAssertFalse(all.contains { $0.contains("標題與年份相同但 DOI 不同") }, "拷貝不是另一筆：\(all)")
        XCTAssertTrue(all.contains { $0.contains("citekey「anon2021work」重複") }, "一對本身仍報一次（warning）：\(all)")
    }

    func testAPairWithTheSameDOIIsNotReportedAsADOIShared() throws {
        var e = Entry(id: UUID(), citekey: "anon2021work", type: .periodicalArticle, title: "T", date: "2021")
        e.doi = [DOI("10.1234/x")!]
        try writeEntities(e)
        try writeLegacy(e)
        let all = try store.load().crossRecordIssues()
        XCTAssertFalse(all.contains { $0.message.contains("被 2 筆 work 共用") }, "\(all.map(\.message))")
    }

    /// 對照組：兩筆**不同**的記錄（id 不同）同標題同年、DOI 不同，照舊報；同 DOI 照舊報。
    func testRealDuplicatesAreStillReported() throws {
        var a = Entry(id: UUID(), citekey: "anon2021a", type: .periodicalArticle, title: "Same Title", date: "2021")
        a.doi = [DOI("10.1234/a")!]
        var b = Entry(id: UUID(), citekey: "anon2021b", type: .periodicalArticle, title: "Same Title", date: "2021")
        b.doi = [DOI("10.1234/b")!]
        try writeEntities(a)
        try writeEntities(b)
        var c = Entry(id: UUID(), citekey: "anon2022c", type: .periodicalArticle, title: "Other", date: "2022")
        c.doi = [DOI("10.1234/shared")!]
        var d = Entry(id: UUID(), citekey: "anon2022d", type: .periodicalArticle, title: "Another", date: "2022")
        d.doi = [DOI("10.1234/shared")!]
        try writeEntities(c)
        try writeEntities(d)
        let all = try messages()
        XCTAssertTrue(all.contains { $0.contains("標題與年份相同但 DOI 不同") }, "\(all)")
        XCTAssertTrue(all.contains { $0.contains("被 2 筆 work 共用") }, "\(all)")
    }

    // MARK: - 2. 健康讀數

    func testHealthCountsFromTheEntitiesCopyOnly() throws {
        let e = Entry(id: UUID(), citekey: "anon2021work", type: .periodicalArticle, title: "T",
                      authors: [.literal("Doe, A.")], date: "2021")
        try writeEntities(e)
        try writeLegacy(e)
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 2, "前提：完整的 load 兩份都在")
        XCTAssertEqual(store.health(from: load).unresolvedAuthorLiterals, 1, "同一筆記錄的兩份只算一次")

        let service = AkashicService(root: root, key: nil, environment: [:])
        let doctor = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try service.doctor().utf8)) as? [String: Any])
        XCTAssertEqual(doctor["entries"] as? Int, 1)
        XCTAssertEqual(doctor["unresolvedAuthorLiterals"] as? Int, 1, "與 entries 同一個視圖：\(doctor)")
    }

    /// 對照組：兩筆不同的記錄各一個 literal 就是 2。
    func testTwoDistinctRecordsStillCountTwice() throws {
        try writeEntities(Entry(id: UUID(), citekey: "anon2021a", type: .periodicalArticle, title: "A",
                                authors: [.literal("Doe, A.")], date: "2021"))
        try writeEntities(Entry(id: UUID(), citekey: "anon2021b", type: .periodicalArticle, title: "B",
                                authors: [.literal("Roe, B.")], date: "2021"))
        XCTAssertEqual(store.health(from: try store.load()).unresolvedAuthorLiterals, 2)
    }

    /// #709 R2 verify（MEDIUM 2、3、5、7）：MCP `akashic_doctor` 的普查讀數也取 entities/ 那份——先前 `people: 1` 與
    /// `noAuthorizedName.people: 2` 出現在同一份 payload。
    func testMCPDoctorCensusCountsAPersonPairOnce() throws {
        let id = UUID()
        var p = Person(key: "doe-a", names: PersonNames(variant: ["Doe, Alpha"]), died: "2001", id: id)
        p.profile.affiliations = TimelineOf<OrgRef>([
            TemporalValue(value: .literal("Institute of Testing"), source: "sha256:" + String(repeating: "a", count: 64))])
        let q = Person(key: "roe-b", names: PersonNames(authorized: ["Roe, B."]))
        try PersonYAML.encode(p).write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
        try PersonYAML.encode(q).write(to: store.entityURL(id: q.id), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        for x in [p, q] {
            try PersonYAML.encode(x).write(to: store.personURL(key: x.key), atomically: true, encoding: .utf8)
        }
        XCTAssertEqual(try store.load().people.count, 4, "前提：兩份並存")

        let service = AkashicService(root: root, key: nil, environment: [:])
        let doctor = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try service.doctor().utf8)) as? [String: Any])
        XCTAssertEqual(doctor["people"] as? Int, 2)
        let gaps = try XCTUnwrap(doctor["noAuthorizedName"] as? [String: Any], "\(doctor)")
        XCTAssertEqual(gaps["people"] as? Int, 1, "與 people 同一個視圖：\(doctor)")
        XCTAssertEqual(gaps["firstPeople"] as? [String], ["doe-a"])
        XCTAssertEqual(doctor["authorizedOnlyByCitationForm"] as? Int, 1)
        XCTAssertEqual(doctor["deceasedWithOpenAffiliation"] as? [String], ["doe-a"])
        XCTAssertEqual((doctor["digestSources"] as? [String])?.count, 1, "\(doctor)")
    }

    /// #709 R2 verify（LOW 22）：`create-entry` 的 DOI 命中把一對列成「已在：k、k」；citekey 的佔用照舊看完整的 load。
    func testCreateEntryDOIHitNamesAPairOnce() throws {
        var e = Entry(id: UUID(), citekey: "a2020doi", type: .periodicalArticle, title: "T", date: "2020")
        e.doi = [DOI("10.1234/abc.def")!]
        try writeEntities(e)
        try writeLegacy(e)
        let service = AkashicService(root: root, key: nil, environment: [:])
        let report = try service.createEntries([.init(type: "periodical-article", title: "Other", authors: ["Doe, B."],
                                                      date: "2021", doi: ["10.1234/abc.def"])], dryRun: true)
        XCTAssertEqual(report.doiHits.map(\.existing), [["a2020doi"]], "\(report.doiHits)")
    }

    /// #709 R2 verify（LOW 19）：`akashic_libraries` 的 list 與 check 把一對算成兩個成員。
    func testLibraryMemberCountsTakeThePairOnce() throws {
        try store.writeLibrary(Library(key: "lib1", name: "L1", membership: .topic))
        var a = Entry(id: UUID(), citekey: "doe2020a", type: .periodicalArticle, title: "A", date: "2020")
        a.akashic.libraries = ["lib1"]
        var b = Entry(id: UUID(), citekey: "roe2021b", type: .periodicalArticle, title: "B", date: "2021")
        b.akashic.libraries = ["lib1"]
        try writeEntities(a)
        try writeEntities(b)
        try writeLegacy(a)
        let service = AkashicService(root: root, key: nil, environment: [:])
        let list = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(try service.libraries(action: "list", key: nil, name: nil, description: nil, citekey: nil).utf8)) as? [[String: Any]])
        XCTAssertEqual(list.first?["members"] as? Int, 2, "\(list)")
        XCTAssertEqual(try service.libraryViolations(key: "lib1").members, 2)
    }

    /// #709 R2 verify（LOW 22）：`authorize-names` 的計畫把一對算成兩個人；`--apply` 對這一對照舊整批拒絕（過濾不讓任何一筆變得可寫）。
    func testAuthorizeNamesPlansAPairOnceAndStillRefusesToWriteIt() throws {
        let id = UUID()
        let p = Person(key: "doe-a", names: PersonNames(variant: ["Doe, Alpha"]), id: id)
        try PersonYAML.encode(p).write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)

        let dry = try AuthorizedNameMigration.run(store: store, apply: false)
        XCTAssertEqual(dry.total, 1, "person 總數只算一次")
        XCTAssertEqual(dry.adopted, 1, "\(dry)")
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true, judgement: "測試")) {
            XCTAssertTrue("\($0)".contains("無法唯一定位"), "\($0)")
        }
    }

    // MARK: - 3. people 列表

    func testThePeopleListShowsAPersonPairOnceAndTakesTheEntitiesCopy() throws {
        let id = UUID()
        try PersonYAML.encode(Person(key: "yang-hau-hung", names: PersonNames(authorized: ["Yang, Hau-Hung"]), id: id))
            .write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        try PersonYAML.encode(Person(key: "yang-hau-hung", names: PersonNames(variant: ["Yang, Hau-Hung-LEGACY"]), id: id))
            .write(to: store.personURL(key: "yang-hau-hung"), atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().people.count, 2, "前提：兩份並存")

        let service = AkashicService(root: root, key: nil, environment: [:])
        let list = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(try service.people(query: nil).utf8)) as? [[String: Any]])
        XCTAssertEqual(list.compactMap { $0["key"] as? String }, ["yang-hau-hung"], "同一筆 person 只列一次")
        let names = try XCTUnwrap(list.first?["names"] as? [String])
        XCTAssertFalse(names.contains { $0.contains("LEGACY") }, "取 entities/ 那份：\(names)")
    }
}
