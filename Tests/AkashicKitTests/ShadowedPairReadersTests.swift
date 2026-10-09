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

    /// #709 第三次 verify（MEDIUM 1、4）：文件型 library 的文件自己有 legacy 拷貝時，依據不明確（「文件的 citekey 有不只一筆」）——
    /// `library add` 與 `validate` 看完整的 load 這樣說；`library check`／`list` 先前拿視圖建判定、說「全部符合」。依據看完整的 load，
    /// 成員數仍取視圖。
    func testLibraryCheckAndListSeeTheDocumentsLegacyCopyAsAnAmbiguousBasis() throws {
        try store.writeLibrary(Library(key: "docs", name: "Docs", membership: .document(citekey: "anon2020doc")))
        var doc = Entry(id: UUID(), citekey: "anon2020doc", type: .periodicalArticle, title: "Doc", date: "2020")
        doc.akashic.relations.cites = ["anon2021mem", "anon2021other"]
        var member = Entry(id: UUID(), citekey: "anon2021mem", type: .periodicalArticle, title: "Mem", date: "2021")
        member.akashic.libraries = ["docs"]
        let other = Entry(id: UUID(), citekey: "anon2021other", type: .periodicalArticle, title: "Other", date: "2021")
        try writeEntities(doc)
        try writeEntities(member)
        try writeEntities(other)
        try writeLegacy(doc)
        let service = AkashicService(root: root, key: nil, environment: [:])

        let check = try service.libraryViolations(key: "docs")
        XCTAssertEqual(check.basisProblem, .documentAmbiguous("anon2020doc"), "依據看完整的 load：\(check)")
        XCTAssertEqual(check.members, 1)
        XCTAssertEqual(check.violations.map(\.citekey), ["anon2021mem"], "依據不明確時現有成員無從查證：\(check.violations)")

        let list = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(try service.libraries(action: "list", key: nil, name: nil, description: nil, citekey: nil).utf8)) as? [[String: Any]])
        XCTAssertEqual(list.first?["members"] as? Int, 1, "\(list)")
        XCTAssertEqual(list.first?["nonconforming"] as? Int, 1, "list 與 check 同一個判定：\(list)")

        // 與寫入面、驗證面同一個答案（這三個面先前就看完整的 load）
        let add = try service.setMembership(action: "add", key: "docs", citekeys: ["anon2021other"])
        XCTAssertEqual(add.written, [], "\(add)")
        XCTAssertTrue(add.skipped.first?.reason.contains("不只一筆") ?? false, "\(add.skipped)")
        XCTAssertTrue(try store.load().crossRecordIssues().contains { $0.message.contains("library「docs」的成員規則依據不明確") })
    }

    /// #709 第三次 verify（LOW 5）：規則型 library 的成員兩份對規則的符合不同時，`check`、`list` 與 `set-kind` 的成員數與不符清單一致，
    /// 都只看 entities/ 那份（不符清單是讀數）；兩個方向各一筆。
    func testRuleLibraryViolationsAgreeAcrossCheckListAndSetKindWhenThePairDiffers() throws {
        _ = try store.writeVenue(Venue(key: "psy-j", type: .periodical, names: TimelineOf([TemporalValue(value: "Psy J")])))
        try store.writeLibrary(Library(key: "rl", name: "RL"))   // 未標性質，set-kind 不需要版控
        // 1. entities/ 那份符合、legacy 那份不符
        var conforming = Entry(id: UUID(), citekey: "a2020in", type: .periodicalArticle, title: "In", date: "2020")
        conforming.akashic.libraries = ["rl"]
        conforming.venues = [.key("psy-j")]
        var conformingLeftover = conforming
        conformingLeftover.venues = []
        // 2. entities/ 那份不符、legacy 那份符合
        var stray = Entry(id: UUID(), citekey: "c2020out", type: .periodicalArticle, title: "Out", date: "2020")
        stray.akashic.libraries = ["rl"]
        var strayLeftover = stray
        strayLeftover.venues = [.key("psy-j")]
        try writeEntities(conforming)
        try writeLegacy(conformingLeftover)
        try writeEntities(stray)
        try writeLegacy(strayLeftover)
        let service = AkashicService(root: root, key: nil, environment: [:])

        let kind = try service.setLibraryKind(key: "rl", membership: .init(kind: "rule", venue: "psy-j"))
        XCTAssertEqual(kind.members, 2)
        XCTAssertEqual(kind.violations.map(\.citekey), ["c2020out"], "\(kind.violations)")
        XCTAssertNil(kind.basisProblem)
        let check = try service.libraryViolations(key: "rl")
        XCTAssertEqual(check.members, 2)
        XCTAssertEqual(check.violations.map(\.citekey), ["c2020out"], "\(check.violations)")
        let list = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(try service.libraries(action: "list", key: nil, name: nil, description: nil, citekey: nil).utf8)) as? [[String: Any]])
        XCTAssertEqual(list.first?["members"] as? Int, 2, "\(list)")
        XCTAssertEqual(list.first?["nonconforming"] as? Int, 1, "\(list)")
    }

    /// #709 第三次 verify（MEDIUM 2、3，LOW 8、10）：`authorize-names` 是寫入面，計畫與拒絕都看完整的 load——同 key 的一對在寫入集合裡是兩筆、
    /// 兩筆都無法唯一定位；乾跑把它們列在 `blockedKeys`（與實跑同一組），`--apply` 整批拒絕、零寫入。
    func testAuthorizeNamesPlansFromTheFullLoadAndNamesTheBlockedPairInTheDryRun() throws {
        let id = UUID()
        let p = Person(key: "doe-a", names: PersonNames(variant: ["Doe, Alpha"]), id: id)
        try PersonYAML.encode(p).write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)

        let dry = try AuthorizedNameMigration.run(store: store, apply: false)
        XCTAssertEqual(dry.total, 2, "寫入面看完整的 load：兩份都在寫入集合裡")
        XCTAssertEqual(dry.blockedKeys, ["doe-a"], "乾跑說出 --apply 會擋的那一筆：\(dry)")
        let before = try personFileBytes()
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true, judgement: "測試")) {
            XCTAssertTrue("\($0)".contains("無法唯一定位"), "\($0)")
        }
        XCTAssertEqual(try personFileBytes(), before, "零寫入")
    }

    /// #709 第三次 verify（MEDIUM 2、3，LOW 8）：**改名**留下的 legacy 拷貝——entities/ 那份是新 key、legacy 那份是舊 key、同一個 id。
    /// entities/ 那份在完整的 load 上本來就寫得進去（`unlocatablePersonKeys` 刻意不收「共用 id」），擋住這次 apply 的是 legacy 那份被算進寫入集合；
    /// R2 讓計畫取視圖之後它被拿掉，`--apply` 從整批拒絕變成寫入 entities/ 那份、legacy 那份原封不動（真 binary 重現）。
    func testAuthorizeNamesStillRefusesWhenARenameLeftoverIsInTheWriteSet() throws {
        let id = UUID()
        let renamed = Person(key: "kim-c", names: PersonNames(variant: ["Kim, Chris"]), id: id)
        let leftover = Person(key: "old-kim", names: PersonNames(variant: ["Kim, Chris"]), id: id)
        try PersonYAML.encode(renamed).write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        try PersonYAML.encode(leftover).write(to: store.personURL(key: leftover.key), atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.shadowedLegacyCopies.map(\.key), ["old-kim"], "前提：load 認得出這是改名留下的拷貝")
        XCTAssertFalse(load.people.unlocatablePersonKeys.contains("kim-c"), "前提：entities/ 那份單獨看是寫得進去的")

        let dry = try AuthorizedNameMigration.run(store: store, apply: false)
        XCTAssertEqual(dry.total, 2, "\(dry)")
        // 第四次 verify（LOW 22）起 entities/ 那份也列：它的 id 還有 legacy 拷貝
        XCTAssertEqual(dry.blockedKeys, ["kim-c", "old-kim"], "乾跑說出 --apply 會擋的那幾筆：\(dry)")
        let before = try personFileBytes()
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true, judgement: "測試")) {
            XCTAssertTrue("\($0)".contains("無法唯一定位") && "\($0)".contains("old-kim"), "\($0)")
        }
        XCTAssertEqual(try personFileBytes(), before, "零寫入：entities/ 那份也不寫")
    }

    /// #709 第四次 verify（LOW 22）：改名一對、**legacy 那份已有 authorized**——只有 entities/ 那份在寫入集合裡、它單獨看寫得進去；先前 `--apply`
    /// 只寫 entities/ 那份、legacy 那份原封不動，兩份各帶不同的 authorized 狀態（真 binary 重現）。寫入集合的 id 還有 legacy 拷貝 → 整批拒絕。
    func testAuthorizeNamesRefusesWhenTheWriteSetsIDStillHasALegacyCopy() throws {
        let id = UUID()
        let renamed = Person(key: "smith-j", names: PersonNames(variant: ["Smith, John"]), id: id)
        let leftover = Person(key: "smith-old", names: PersonNames(authorized: ["Smith, John"]), id: id)
        try PersonYAML.encode(renamed).write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        try PersonYAML.encode(leftover).write(to: store.personURL(key: leftover.key), atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.shadowedLegacyCopies.map(\.key), ["smith-old"], "前提：load 認得出改名留下的拷貝")
        XCTAssertFalse(load.people.unlocatablePersonKeys.contains("smith-j"), "前提：entities/ 那份單獨看寫得進去")

        let dry = try AuthorizedNameMigration.run(store: store, apply: false)
        XCTAssertEqual(dry.alreadyDesignated, 1, "legacy 那份已指定、不在寫入集合：\(dry)")
        XCTAssertEqual(dry.blockedKeys, ["smith-j"], "乾跑說出 --apply 會擋的那一筆：\(dry)")
        // b36 verify（LOW 7、INFO 23）：validate 以 legacy 那份的 key（smith-old）列出兩份並存——點名 smith-j 時一併說出它的 legacy 檔，照訊息找得到
        XCTAssertEqual(dry.blockedCopyFiles, ["smith-j": "people/smith-old.yaml"], "\(dry)")
        XCTAssertEqual(AuthorizedNameMigration.blockedDisplay(dry), "smith-j（legacy 拷貝 people/smith-old.yaml）")
        XCTAssertTrue(try store.load().crossRecordIssues().contains { $0.message.contains("smith-old") }, "前提：validate 點名的是 legacy 那份的 key")
        let before = try personFileBytes()
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true, judgement: "測試")) {
            XCTAssertTrue("\($0)".contains("legacy 拷貝") && "\($0)".contains("smith-j（legacy 拷貝 people/smith-old.yaml）")
                          && "\($0)".contains("以 legacy 那份的 key 列出"), "\($0)")
        }
        XCTAssertEqual(try personFileBytes(), before, "零寫入")
    }

    /// 對照組：沒有拷貝時照常寫入，`blockedKeys` 是空的。
    func testAuthorizeNamesWritesWhenNothingIsBlocked() throws {
        let p = Person(key: "kim-c", names: PersonNames(variant: ["Kim, Chris"]))
        try PersonYAML.encode(p).write(to: store.entityURL(id: p.id), atomically: true, encoding: .utf8)
        let dry = try AuthorizedNameMigration.run(store: store, apply: false)
        XCTAssertEqual(dry.blockedKeys, [])
        let r = try AuthorizedNameMigration.run(store: store, apply: true, judgement: "測試")
        XCTAssertEqual(r.adopted, 1, "\(r)")
        XCTAssertEqual(try store.load().people.first?.names.authorized, ["Kim, Chris"])
    }

    /// `entities/` 與 `people/` 每個檔的位元組（相對路徑 → 內容）。
    private func personFileBytes() throws -> [String: Data] {
        var out: [String: Data] = [:]
        for dir in [store.entitiesDir, store.peopleDir] {
            for url in (try? FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil)) ?? [] {
                out[dir.lastPathComponent + "/" + url.lastPathComponent] = try Data(contentsOf: url)
            }
        }
        return out
    }

    /// #709 第三次 verify（LOW 7b）：`akashic_person` 的名字查找把一對 legacy 拷貝的篇數算兩次（`publications: 2`，key 查找同一個人列 1 篇）。
    /// 篇數是讀數，取視圖；literal 的篇數同。
    func testPersonNameLookupCountsAPairsPublicationsOnce() throws {
        let smith = Person(key: "smith-j", names: PersonNames(authorized: ["Smith, John"]))
        try PersonYAML.encode(smith).write(to: store.entityURL(id: smith.id), atomically: true, encoding: .utf8)
        let work = Entry(id: UUID(), citekey: "smith2020a", type: .periodicalArticle, title: "T",
                         authors: [.key("smith-j"), .literal("Smithson, Q.")], date: "2020")
        try writeEntities(work)
        try writeLegacy(work)
        let service = AkashicService(root: root, key: nil, environment: [:])
        let out = try XCTUnwrap(try JSONSerialization.jsonObject(
            with: Data(try service.person(key: nil, name: "smith", library: nil).utf8)) as? [String: Any])
        let candidates = try XCTUnwrap(out["candidates"] as? [[String: Any]], "\(out)")
        let person = try XCTUnwrap(candidates.first { $0["person_key"] as? String == "smith-j" }, "\(candidates)")
        XCTAssertEqual(person["publications"] as? Int, 1, "\(candidates)")
        let literal = try XCTUnwrap(candidates.first { $0["literal"] as? String == "Smithson, Q." }, "\(candidates)")
        XCTAssertEqual(literal["publications"] as? Int, 1, "\(candidates)")
    }

    /// #709 第三次 verify（LOW 19）：`enrich` 以 DOI 定位時，改名留下的拷貝（citekey 不同、id 相同）讓同一個 DOI 命中兩筆。定位看完整的 load
    /// （寫入面，照舊零寫入），理由說出那是同一筆記錄的拷貝——先前指向 #459 的攣生管線，而 resolve-divergence 對有拷貝的候選拒絕。
    ///
    /// #709 第四次 verify（MEDIUM 0、2、4，LOW 9、12、16）：哪一筆是拷貝**只問 load 的標記**（`shadowedLegacyFile`），所以本格走真的 load——
    /// 先前的版本用兩筆 id 相同的裸 `Entry`，只靠 id 相等也綠，擋不住「兩份都是 legacy」那一格。
    func testEnrichNamesARenameLeftoverInsteadOfPointingAtTheTwinPipeline() throws {
        let id = UUID()
        var renamed = Entry(id: id, citekey: "b2020beta", type: .periodicalArticle, title: "T", date: "2020")
        renamed.doi = [DOI("10.1234/abc.def")!]
        var leftover = renamed
        leftover.citekey = "b2020alpha"
        try writeEntities(renamed)
        try writeLegacy(leftover)
        let reason = try enrichReason(doi: "10.1234/abc.def", matches: ["b2020alpha", "b2020beta"])
        XCTAssertTrue(reason.contains("b2020alpha（legacy 檔 entries/b2020alpha.yaml；entities/ 那份是 b2020beta）"), reason)
        XCTAssertTrue(reason.contains("legacy 拷貝") && reason.contains("確認 entities/ 那份是新的之後"), reason)
        XCTAssertFalse(reason.contains("#459"), "拿掉拷貝之後只剩一筆，攣生管線不適用：\(reason)")

        // 對照組：兩筆不同的記錄（id 不同、都在 entities/）共用 DOI，照舊指向 #459、不提拷貝
        try FileManager.default.removeItem(at: store.entriesDir.appendingPathComponent("b2020alpha.yaml"))
        var other = leftover
        other.id = UUID()
        try writeEntities(other)
        let control = try enrichReason(doi: "10.1234/abc.def", matches: ["b2020alpha", "b2020beta"])
        XCTAssertTrue(control.contains("#459") && !control.contains("拷貝") && !control.contains("UUID"), control)
    }

    /// #709 第四次 verify（MEDIUM 0、2、4）：兩個 legacy 檔共用 UUID、entities/ 沒有那個 id——validate 判成兩筆不同記錄的 error，不是拷貝。
    /// 理由不得說它們是同一筆記錄的拷貝、「不是兩篇作品」，不得叫人刪 legacy 那份；要說 UUID 重複是 error、指向 validate。
    func testEnrichDoesNotCallTwoLegacyFilesSharingAnIDACopy() throws {
        let id = UUID()
        var a = Entry(id: id, citekey: "alpha2020", type: .periodicalArticle, title: "Cats", date: "2020")
        a.doi = [DOI("10.1234/abc.def")!]
        var b = a
        b.citekey = "beta2020"
        b.title = "Dogs"
        try writeLegacy(a)
        try writeLegacy(b)
        XCTAssertEqual(try store.load().shadowedLegacyCopies, [], "前提：load 不把它們標成拷貝")
        XCTAssertTrue(try store.load().crossRecordIssues().contains { $0.severity == .error && $0.message.contains("被 2 筆 entry 共用") },
                      "前提：validate 判成 error")

        let reason = try enrichReason(doi: "10.1234/abc.def", matches: ["alpha2020", "beta2020"])
        XCTAssertFalse(reason.contains("是同一筆記錄的 legacy 拷貝") || reason.contains("不是兩篇") || reason.contains("刪掉"), reason)
        XCTAssertTrue(reason.contains("1 組共用同一個 id，卻不是 load 認得的 legacy 拷貝") && reason.contains("共用 id：alpha2020、beta2020")
                      && reason.contains("UUID 重複是 error") && reason.contains("akashic validate"), reason)

        // MCP／CLI 共用的 service payload 也是這一句（CLI 印同一份 payload）
        let service = AkashicService(root: root, key: nil, environment: [:])
        let out = try service.enrich(proposals: [.init(doi: "10.1234/abc.def", fields: ["abstract": "A"])],
                                     dryRun: true, includeAbsentAuthors: false)
        XCTAssertTrue(out.contains("UUID 重複是 error") && !out.contains("刪掉"), out)
    }

    /// #709 第四次 verify（MEDIUM 4、LOW 9）：一對拷貝加另一筆 id 不同的記錄共用 DOI——刪掉拷貝之後仍歧義，#459 的指路不能丟。
    func testEnrichKeepsTheTwinPointerWhenACopyAndAnotherRecordShareTheDOI() throws {
        let id = UUID()
        var renamed = Entry(id: id, citekey: "b2021d", type: .periodicalArticle, title: "T", date: "2021")
        renamed.doi = [DOI("10.1234/abc.def")!]
        var leftover = renamed
        leftover.citekey = "oldcite2021"
        var twin = renamed
        twin.id = UUID()
        twin.citekey = "c2021d2"
        try writeEntities(renamed)
        try writeLegacy(leftover)
        try writeEntities(twin)
        let reason = try enrichReason(doi: "10.1234/abc.def", matches: ["b2021d", "c2021d2", "oldcite2021"])
        XCTAssertTrue(reason.contains("oldcite2021（legacy 檔 entries/oldcite2021.yaml；entities/ 那份是 b2021d）"), reason)
        XCTAssertTrue(reason.contains("拿掉 legacy 拷貝之後仍有 2 筆記錄帶這個 DOI") && reason.contains("#459"), reason)
        XCTAssertFalse(reason.contains("再跑"), "刪掉拷貝之後重跑仍歧義，不說「再跑」：\(reason)")
    }

    /// b36 verify（MEDIUM 2、5）：**同 citekey** 的 legacy 拷貝（#631 搬移中斷的主要殘留形）加一筆真孿生。先前 `plan` 以 `working[e.citekey] = e`
    /// 建表、同 citekey 後者勝，load 先 entities/ 後 legacy——命中只剩拷貝，理由說 entities/ 那份「它不帶這個 DOI」（假）、叫人刪拷貝「再跑」
    /// （刪了仍與真孿生歧義），#459 的指路不見。
    func testEnrichKeepsTheTwinPointerWhenASameCitekeyCopyAndAnotherRecordShareTheDOI() throws {
        var same = Entry(id: UUID(), citekey: "x2020same", type: .periodicalArticle, title: "T", date: "2020")
        same.doi = [DOI("10.1234/abc.def")!]
        var twin = same
        twin.id = UUID()
        twin.citekey = "y2020twin"
        try writeEntities(same)
        try writeLegacy(same)
        try writeEntities(twin)
        XCTAssertEqual(try store.load().shadowedLegacyCopies.map(\.legacyFile), ["entries/x2020same.yaml"], "前提：同 citekey 的拷貝")
        let reason = try enrichReason(doi: "10.1234/abc.def", matches: ["x2020same", "y2020twin"])
        XCTAssertTrue(reason.contains("x2020same（legacy 檔 entries/x2020same.yaml；entities/ 那份是 x2020same）"), reason)
        XCTAssertTrue(reason.contains("拿掉 legacy 拷貝之後仍有 2 筆記錄帶這個 DOI——不判定哪一筆才對（#459）"), reason)
        XCTAssertFalse(reason.contains("它不帶這個 DOI") || reason.contains("再跑"), reason)
    }

    /// b36 verify（MEDIUM 5 的副作用 t8）：entities/ 那份帶 DOI、同 citekey 的舊 legacy 拷貝沒有。先前字典留下拷貝，`enrich` 說「沒有記錄帶 DOI」
    /// （notFound），同一個 store 的 `create-entry --dry-run` 卻說「DOI 已在」。現在命中 entities/ 那份，而那個 citekey 無法唯一定位——零寫入、說出來。
    func testEnrichFindsTheDOIOnTheEntitiesCopyWhenTheSameCitekeyLegacyCopyLacksIt() throws {
        var current = Entry(id: UUID(), citekey: "x2020same", type: .periodicalArticle, title: "T", date: "2020")
        current.doi = [DOI("10.1234/abc.def")!]
        var stale = current
        stale.doi = []
        try writeEntities(current)
        try writeLegacy(stale)
        let plan = try AddOnlyEnrichment.plan(entries: try store.load().entries,
                                              proposals: [.init(doi: "10.1234/abc.def", fields: ["abstract": "A"])])
        let item = try XCTUnwrap(plan.items.first)
        XCTAssertEqual(item.category, .ambiguous, "不是 notFound：entities/ 那份帶這個 DOI：\(item)")
        XCTAssertEqual(item.matches, ["x2020same"])
        XCTAssertTrue((item.reason ?? "").contains("無法唯一定位"), "\(item)")
    }

    /// b36 verify（MEDIUM 0，LOW 9、13、15）：出口 `AkashicService.enrich` 對理由 `displaySafe(max: 512)`。先前逐份明細在前，四份以上拷貝或 citekey
    /// 較長時「確認 entities/ 那份是新的之後」、#459 與「零寫入」被截掉。走 service 出口：六份改名留下的拷貝（長 citekey、entities/ 那份不帶這個 DOI，
    /// 每份明細最長）加兩筆真孿生——截斷之後結論與處置仍在。
    func testTheEnrichReasonKeepsTheGuidanceAfterTheServiceTruncation() throws {
        let doi = "10.1234/abc.def"
        for i in 0..<6 {
            let current = Entry(id: UUID(), citekey: "newkey2019n\(i)", type: .periodicalArticle, title: "T\(i)", date: "2019")
            var leftover = current
            leftover.citekey = "smithjonesmillerwilliams2019oldkey\(i)"
            leftover.doi = [DOI(doi)!]
            try writeEntities(current)
            try writeLegacy(leftover)
        }
        for ck in ["twin2019a", "twin2019b"] {
            var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: "T", date: "2019")
            e.doi = [DOI(doi)!]
            try writeEntities(e)
        }
        let core = try enrichReason(doi: doi, matches: (0..<6).map { "smithjonesmillerwilliams2019oldkey\($0)" } + ["twin2019a", "twin2019b"])
        XCTAssertGreaterThan(core.count, 512, "前提：完整理由超過出口上限：\(core.count)")

        let service = AkashicService(root: root, key: nil, environment: [:])
        let out = try service.enrich(proposals: [.init(doi: doi, fields: ["abstract": "A"])], dryRun: true, includeAbsentAuthors: false)
        let obj = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any], out)
        let reason = try XCTUnwrap((obj["items"] as? [[String: Any]])?.first?["reason"] as? String, out)
        XCTAssertTrue(reason.hasSuffix("（已截斷）"), "前提：出口截斷了：\(reason)")
        XCTAssertTrue(reason.contains("零寫入") && reason.contains("拿掉 legacy 拷貝之後仍有 2 筆記錄帶這個 DOI——不判定哪一筆才對（#459）")
                      && reason.contains("確認 entities/ 那份是新的之後刪掉 legacy 那份"), "截斷後結論與處置仍在：\(reason)")
    }

    /// 以 DOI 定位一筆 enrich 提案、斷言歧義與命中，回傳理由（走真的 load：標記由 load 設定）。
    private func enrichReason(doi: String, matches: [String], file: StaticString = #filePath, line: UInt = #line) throws -> String {
        let plan = try AddOnlyEnrichment.plan(entries: try store.load().entries,
                                              proposals: [.init(doi: doi, fields: ["abstract": "A"])])
        let item = try XCTUnwrap(plan.items.first, file: file, line: line)
        XCTAssertEqual(item.category, .ambiguous, file: file, line: line)
        XCTAssertEqual(item.matches, matches, file: file, line: line)
        return try XCTUnwrap(item.reason, file: file, line: line)
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
