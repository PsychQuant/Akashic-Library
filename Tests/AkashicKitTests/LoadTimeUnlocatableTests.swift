import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import AkashicWoSImport

/// #641：寫入當下的 #631 拒絕若發生在多檔寫入者的中途，前面幾筆已經落盤、store 被撕成一半。
///
/// 結構解（使用者 2026-09-28 裁決）：load 用 #631 的同一組前置判斷先標出**一定寫不進去**的 work／person，
/// 併進「無法唯一定位」的定義（`unlocatableCitekeys`／`unlocatablePersonKeys` 的第 3 類）。各面既有的 #627／#628 閘
/// 於是在第一次寫入之前拒絕或略過它們；寫入當下的檢查留著當最後一道防線。
///
/// 本檔的每一個寫入者測試都造「雙重損壞」——legacy 殘留，加上未受 git 追蹤、目的檔被隔離、或兩份並存——
/// 然後斷言受損記錄的檔案**一個位元都不動**（零寫入，不是寫到一半）。
final class LoadTimeUnlocatableTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private var service: AkashicService { AkashicService(root: root, key: nil, environment: [:]) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-641-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        GitFixture.initRepo(root)
        try "sources/\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertTrue(store.usesEntitiesLayout, "前提：entities 佈局——legacy 目錄在這裡是殘留")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - 夾具

    @discardableResult
    private func writeLegacy(_ e: Entry) throws -> URL {
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        let url = store.entriesDir.appendingPathComponent("\(e.citekey).yaml")
        try EntryYAML.encode(e).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    @discardableResult
    private func writeLegacy(_ p: Person) throws -> URL {
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        let url = store.personURL(key: p.key)
        try PersonYAML.encode(p).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 目的檔 `entities/<id>.yaml` 是一筆被隔離的記錄（type 不是合法值——load 收不進來）。
    private func quarantineDestination(_ id: UUID) throws {
        let text = "work:\nid: \(id.uuidString)\ncitekey: q2000\ntype: not-a-real-type\ntitle: Precious\n"
        try text.write(to: store.entityURL(id: id), atomically: true, encoding: .utf8)
    }

    private func commit() { GitFixture.commitAll(root) }

    /// 記錄檔的快照（entities／entries／people）——index 不在內，那是衍生層。
    private func recordFiles() throws -> [String: Data] {
        var out: [String: Data] = [:]
        for dir in ["entities", "entries", "people"] {
            let d = root.appendingPathComponent(dir)
            guard let names = try? FileManager.default.contentsOfDirectory(atPath: d.path) else { continue }
            for n in names where n.hasSuffix(".yaml") {
                out["\(dir)/\(n)"] = try Data(contentsOf: d.appendingPathComponent(n))
            }
        }
        return out
    }

    private func json(_ s: String) -> [String: Any] {
        (try? JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any]) ?? [:]
    }

    private func assertRefused641(_ body: () throws -> Any, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { err in
            let text = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(text.contains("#641"), text, file: file, line: line)
        }
    }

    private func skippedWhys(_ payload: [String: Any]) -> [String] {
        (payload["skipped"] as? [[String: Any]] ?? []).compactMap { $0["why"] as? String }
    }

    /// resolve-people 的共用夾具：一筆健康的 work，作者是只住在 legacy、沒 commit 的 person。
    private func seedWorkWithUntrackedLegacyPerson() throws -> [String: Data] {
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020", type: .periodicalArticle, title: "A",
                                   authors: [.literal("Ulf Olsson")], date: "2020"))
        commit()
        try writeLegacy(Person(key: "olsson-ulf", names: ["Ulf Olsson"]))   // 沒 commit：搬移刪了回不來
        XCTAssertEqual(try store.load().people.unlocatablePersonKeys, ["olsson-ulf"], "前提：load 已標出")
        return try recordFiles()
    }

    // MARK: - 定義：load 時標出第 3 類

    /// 三種雙重損壞（未追蹤的 legacy 單份、legacy ＋ 被隔離的目的檔、兩份並存）都算無法唯一定位；
    /// 受 git 追蹤且乾淨的 legacy 單份**不算**——它寫入時會被搬移，那是合法的路。
    func testEveryDoubleDamageShapeIsUnlocatableAtLoadAndAMovableLegacyCopyIsNot() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "h2020", type: .periodicalArticle, title: "Healthy"))
        try writeLegacy(Entry(id: UUID(), citekey: "m2020", type: .periodicalArticle, title: "Movable"))
        let q = UUID()
        try writeLegacy(Entry(id: q, citekey: "q2020", type: .periodicalArticle, title: "Quarantined dest"))
        try quarantineDestination(q)
        let both = Entry(id: UUID(), citekey: "b2020", type: .periodicalArticle, title: "Both")
        try store.writeEntry(both)
        try writeLegacy(both)

        try store.writePerson(Person(key: "h-person", names: ["H"]))
        try writeLegacy(Person(key: "m-person", names: ["M"]))
        let pq = UUID()
        try writeLegacy(Person(key: "q-person", names: ["Q"], id: pq))
        try "person:\nid: \(pq.uuidString)\nkey: Not Valid Key\n".write(
            to: store.entityURL(id: pq), atomically: true, encoding: .utf8)
        let pBoth = Person(key: "b-person", names: ["B"])
        try store.writePerson(pBoth)
        try writeLegacy(pBoth)
        commit()
        try writeLegacy(Entry(id: UUID(), citekey: "u2020", type: .periodicalArticle, title: "Untracked"))
        try writeLegacy(Person(key: "u-person", names: ["U"]))

        let load = try store.load()
        XCTAssertEqual(load.entries.unlocatableCitekeys, ["u2020", "q2020", "b2020"])
        XCTAssertEqual(load.people.unlocatablePersonKeys, ["u-person", "q-person", "b-person"])
        XCTAssertNil(load.entries.first { $0.citekey == "m2020" }?.fileSituation.unwritableReason, "可搬移的 legacy 單份不擋")
        XCTAssertNil(load.people.first { $0.key == "m-person" }?.fileSituation.unwritableReason)
        XCTAssertNil(load.entries.first { $0.citekey == "h2020" }?.fileSituation.unwritableReason)
        // 可搬移的那一筆真的寫得進去（搬移）——第 3 類只收一定會被拒的
        var m = try XCTUnwrap(load.entries.first { $0.citekey == "m2020" })
        m.title = "Moved"
        XCTAssertNoThrow(try store.writeEntry(m))
    }

    /// 第 1 類不需要 load：key 重複由集合本身看得出來。作品側的「共用 id」**不收**（理由在 `unlocatablePersonKeys` 的 doc）。
    func testDuplicatedPersonKeysAreUnlocatableButASharedIdentifierAloneIsNot() {
        let shared = UUID()
        let people = [Person(key: "a", id: shared), Person(key: "b", id: shared),
                      Person(key: "c"), Person(key: "c"), Person(key: "d")]
        XCTAssertEqual(people.unlocatablePersonKeys, ["c"])
        XCTAssertEqual(people.duplicatedPersonKeys, ["c"])
    }

    /// entities 佈局下共用 id 必然有一筆是 legacy 殘留：那一筆寫入當下會被 #631 拒，load 已標出；住在 `entities/` 的那一筆
    /// 寫的是它自己的檔，照寫。
    func testASharedPersonIdentifierBlocksOnlyTheCopyThatCannotBeWritten() throws {
        let shared = UUID()
        try store.writePerson(Person(key: "a-person", names: ["A"], id: shared))
        try writeLegacy(Person(key: "b-person", names: ["B"], id: shared))
        commit()
        let load = try store.load()
        XCTAssertEqual(load.people.unlocatablePersonKeys, ["b-person"])
        var a = try XCTUnwrap(load.people.first { $0.key == "a-person" })
        a.note = "寫得進去"
        XCTAssertNoThrow(try store.writePerson(a), "住在 entities/ 的那一筆寫的是它自己的檔")
        let b = try XCTUnwrap(load.people.first { $0.key == "b-person" })
        XCTAssertThrowsError(try store.writePerson(b), "legacy 那一筆寫入當下被 #631 拒——load 已把它標出來")
    }

    /// 兩筆**都還是** legacy、共用同一個 id（#641 C2b verify，Codex HIGH）：目的檔 `entities/<id>.yaml` 此刻不存在，逐筆的
    /// #631 檢查各自通過；第一筆搬進去之後第二筆才撞上。load 要把兩筆都標出來，不讓 preflight-then-write 在中途撕裂。
    func testTwoLegacyPeopleSharingAnIdentifierAreBothUnlocatable() throws {
        let shared = UUID()
        try writeLegacy(Person(key: "a-person", names: ["A"], id: shared))
        try writeLegacy(Person(key: "b-person", names: ["B"], id: shared))
        commit()   // 兩份都受追蹤且乾淨：逐筆看都「可以搬移」
        let load = try store.load()
        XCTAssertEqual(load.people.unlocatablePersonKeys, ["a-person", "b-person"])
        let why = try XCTUnwrap(load.people.first { $0.key == "b-person" }?.fileSituation.unwritableReason)
        XCTAssertTrue(why.contains("a-person") && why.contains(shared.uuidString), why)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.entityURL(id: shared).path), "load 不寫")
    }

    /// 沒有 legacy 殘留時什麼都不標（live store 的現況：零成本、零誤報）。
    func testNoLegacyResidueMeansNoAnnotation() throws {
        try store.writeEntry(Entry(id: UUID(), citekey: "h2020", type: .periodicalArticle, title: "H"))
        try store.writePerson(Person(key: "h-person", names: ["H"]))
        let load = try store.load()
        XCTAssertTrue(load.entries.allSatisfy { $0.fileSituation.unwritableReason == nil })
        XCTAssertTrue(load.people.allSatisfy { $0.fileSituation.unwritableReason == nil })
    }

    /// 檔案處境不是內容：兩筆內容相同的記錄相等，不論 load 當時看到什麼。
    func testFileSituationDoesNotParticipateInEquality() {
        let e = Entry(id: UUID(), citekey: "k", type: .periodicalArticle, title: "T")
        var marked = e
        marked.fileSituation.unwritableReason = "x"
        XCTAssertEqual(e, marked)
        let p = Person(key: "p")
        var pm = p
        pm.fileSituation.unwritableReason = "x"
        XCTAssertEqual(p, pm)
    }

    /// validate 說得出是哪一筆、為什麼：warning 級（記錄讀得到，擋的是寫入），兩份並存的同一則只出一次。
    func testValidateNamesEachUnwritableRecordOnce() throws {
        let both = Entry(id: UUID(), citekey: "b2020", type: .periodicalArticle, title: "Both")
        try store.writeEntry(both)
        try writeLegacy(both)
        commit()
        try writeLegacy(Person(key: "u-person", names: ["U"]))
        let issues = try store.load().crossRecordIssues()
        let work = issues.filter { $0.message.contains("work「b2020」的檔案寫入時會被拒") }
        XCTAssertEqual(work.count, 1, "兩份並存時 load 讀到兩筆、原因相同——只出一次：\(issues.map(\.message))")
        XCTAssertEqual(work.first?.severity, .warning)
        let person = issues.filter { $0.message.contains("person「u-person」的檔案寫入時會被拒") }
        XCTAssertEqual(person.count, 1, "\(issues.map(\.message))")
        XCTAssertEqual(person.first?.severity, .warning)
    }

    // MARK: - resolve-people 各腿（先寫 work 再寫 person 的是 judge／apply）

    func testJudgeSkipsAnUnwritablePersonBeforeAnyWrite() throws {
        let before = try seedWorkWithUntrackedLegacyPerson()
        let out = json(try service.resolvePeople(apply: nil, judge: ["a2020:0:olsson-ulf=論文署名的機構相符"]))
        XCTAssertTrue(skippedWhys(out).contains { $0.contains("#641") }, "\(out)")
        XCTAssertEqual(try recordFiles(), before, "work 不得先升格——零寫入")
    }

    func testRefuteSkipsAnUnwritablePersonBeforeAnyWrite() throws {
        let before = try seedWorkWithUntrackedLegacyPerson()
        let out = json(try service.resolvePeople(apply: nil, refute: ["a2020:0:olsson-ulf=不是他"]))
        XCTAssertTrue(skippedWhys(out).contains { $0.contains("#641") }, "\(out)")
        XCTAssertEqual(try recordFiles(), before)
    }

    func testApplyAndRejectRefuseAnUnwritablePersonWholeBatch() throws {
        let before = try seedWorkWithUntrackedLegacyPerson()
        let listed = json(try service.resolvePeople(apply: nil))
        let row = (listed["candidates"] as? [[String: Any]] ?? []).first { ($0["id"] as? String) == "a2020:0:olsson-ulf" }
        XCTAssertEqual(row?["unlocatablePersonKey"] as? Bool, true, "列表先標出：\(listed)")
        assertRefused641 { try self.service.resolvePeople(apply: ["a2020:0:olsson-ulf"]) }
        assertRefused641 { try self.service.resolvePeople(apply: nil, reject: ["a2020:0:olsson-ulf"]) }
        XCTAssertEqual(try recordFiles(), before)
    }

    func testUndecidedSkipsAnUnwritablePerson() throws {
        let before = try seedWorkWithUntrackedLegacyPerson()
        let out = json(try service.resolvePeople(apply: nil, undecided: ["a2020:0:olsson-ulf=查了機構，判不出來"]))
        XCTAssertTrue(skippedWhys(out).contains { $0.contains("#641") }, "\(out)")
        XCTAssertEqual(try recordFiles(), before)
    }

    // MARK: - resolve-organizations

    private func org(_ key: String, _ name: String) throws {
        var o = Organization(key: key)
        o.names = TimelineOf([TemporalValue(value: name, range: DateRange())])
        try store.writeOrganization(o)
    }

    private func affiliated(_ key: String, _ literal: String) -> Person {
        var p = Person(key: key, names: [key])
        p.profile.affiliations = TimelineOf([TemporalValue(value: OrgRef.literal(literal), range: DateRange())])
        return p
    }

    func testOrganizationLegsRefuseOrSkipAnUnwritablePersonHolder() throws {
        try org("apa", "APA")
        commit()
        try writeLegacy(affiliated("pp", "APA"))   // 沒 commit
        let before = try recordFiles()
        let listed = json(try service.resolveOrganizations(apply: nil))
        let row = (listed["candidates"] as? [[String: Any]] ?? []).first { ($0["holder"] as? String) == "pp" }
        XCTAssertEqual(row?["unlocatablePersonKey"] as? Bool, true, "\(listed)")
        assertRefused641 { try self.service.resolveOrganizations(apply: ["pp::APA"]) }
        assertRefused641 { try self.service.resolveOrganizations(apply: nil, reject: ["pp::APA"]) }
        XCTAssertTrue(skippedWhys(json(try service.resolveOrganizations(apply: nil, judge: ["pp::APA@apa=所方名冊"])))
                      .contains { $0.contains("#641") })
        XCTAssertTrue(skippedWhys(json(try service.resolveOrganizations(apply: nil, undecided: ["pp::APA@apa=查了"])))
                      .contains { $0.contains("#641") })
        XCTAssertEqual(try recordFiles(), before)
    }

    /// 撕裂的原形（R2 verify）：apply 先前重寫**每一筆** person——與候選無關、排在後面的一筆寫不進去時，
    /// 前面已經寫了隸屬歸戶、verdict 卻沒寫。現在只寫真的改到的記錄，而且先驗整個寫入集合。
    func testOrganizationApplyDoesNotTouchAnUnrelatedUnwritablePerson() throws {
        try org("apa", "APA")
        try store.writePerson(affiliated("aa-person", "APA"))
        commit()
        let zzURL = try writeLegacy(affiliated("zz-person", "Elsewhere"))   // 沒 commit、與這次的候選無關
        let zzBefore = try Data(contentsOf: zzURL)
        let out = json(try service.resolveOrganizations(apply: ["aa-person::APA"]))
        XCTAssertEqual(out["peopleRewritten"] as? Int, 1, "只數真的改寫的：\(out)")
        XCTAssertEqual(try Data(contentsOf: zzURL), zzBefore, "無關的那一筆一個位元都不動")
        let aa = try XCTUnwrap(try store.load().people.first { $0.key == "aa-person" })
        XCTAssertEqual(aa.profile.affiliations.entries.first?.value, .key("apa"))
        let apa = try XCTUnwrap(try store.load().organizations.first { $0.key == "apa" })
        XCTAssertTrue(apa.references.contains { $0.field == ProvenanceReference.resolutionConfirmedField }, "歸戶與 verdict 一起落地")
    }

    // MARK: - resolve-venues（work 側由既有的 #628 閘接住——第 3 類併進定義之後不必改任何一面）

    func testVenueLegsRefuseOrSkipAnUnwritableWork() throws {
        for (k, n) in [("alpha", "Alpha Journal"), ("beta", "Beta Journal")] {
            try store.writeVenue(Venue(key: k, type: .periodical, names: Timeline([TemporalValue(value: n)]), authorized: []))
        }
        commit()
        var keyed = Entry(id: UUID(), citekey: "w2020", type: .periodicalArticle, title: "W", date: "2020")
        keyed.venues = [.key("alpha")]
        try writeLegacy(keyed)   // 沒 commit
        var literal = Entry(id: UUID(), citekey: "l2020", type: .periodicalArticle, title: "L", date: "2020")
        literal.venues = [.literal("Alpha Journal")]
        try writeLegacy(literal)
        let before = try recordFiles()
        assertRefused641 { try self.service.resolveVenues(apply: nil, repoint: ["w2020:0:beta"]) }
        assertRefused641 { try self.service.resolveVenues(apply: nil, demote: ["w2020:0"]) }
        assertRefused641 { try self.service.resolveVenues(apply: nil, drop: ["w2020:0=多餘的邊"]) }
        let applied = json(try service.resolveVenues(apply: ["l2020:0"]))
        let skipped = applied["skippedUnlocatable"] as? [[String: Any]] ?? []
        XCTAssertTrue(skipped.contains { ($0["reason"] as? String ?? "").contains("#641") }, "\(applied)")
        XCTAssertEqual(try recordFiles(), before)
    }

    // MARK: - migrate-identifiers

    /// R2 verify 的形狀：前一筆的 ISSN 已從 work 移除、venue 還沒寫，下一筆才被拒——號兩邊都沒有。
    /// 現在無法唯一定位的那一筆整筆略過並列進 blockers，其餘照遷，號照樣進 venue。
    func testMigrateIdentifiersBlocksAnUnlocatableWorkWithoutLosingTheNumber() throws {
        try store.writeVenue(Venue(key: "psychometrika", type: .periodical,
                                   names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: []))
        var a = Entry(id: UUID(), citekey: "a2020", type: .periodicalArticle, title: "A")
        a.venues = [.key("psychometrika")]
        a.fields["issn"] = "0033-3123"
        try store.writeEntry(a)
        var z = Entry(id: UUID(), citekey: "z2020", type: .periodicalArticle, title: "Z")
        z.venues = [.key("psychometrika")]
        z.fields["issn"] = "0033-3123"
        try store.writeEntry(z)
        try writeLegacy(z)   // 兩份並存：entities 那份受追蹤，寫入當下 #631 拒（legacyCopyPresent）
        commit()
        let zFiles = try recordFiles().filter { $0.key.contains("z2020") || $0.key.contains(z.id.uuidString) }
        var report: IdentifierMigration.Report?
        XCTAssertNoThrow(report = try IdentifierMigration.run(store: store, apply: true), "不得寫到一半才擲出")
        XCTAssertTrue(report?.blockers.contains { $0.contains("z2020") && $0.contains("#641") } == true,
                      "\(report?.blockers ?? [])")
        XCTAssertEqual(try recordFiles().filter { zFiles.keys.contains($0.key) }, zFiles, "無法唯一定位的那一筆一個位元都不動")
        let after = try store.load()
        XCTAssertNil(after.entries.first { $0.citekey == "a2020" && $0.id == a.id }?.fields["issn"], "健康的那一筆照遷")
        let venue = try XCTUnwrap(after.venues.first { $0.key == "psychometrika" })
        XCTAssertEqual(venue.issn.map(\.normalized), ["0033-3123"], "號沒有消失")
    }

    // MARK: - authorize-names

    /// 逐筆寫 person、最後才 bump marker：中途被拒會留下已指定卻沒 bump 的 store。
    func testAuthorizeNamesRefusesBeforeAnyWrite() throws {
        try store.writePerson(Person(key: "a-person", names: ["Guan, Yongtao"]))
        commit()
        try writeLegacy(Person(key: "z-person", names: ["Zed, Zoe"]))   // 沒 commit
        let before = try recordFiles()
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true)) { err in
            let text = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(text.contains("#641") && text.contains("z-person"), text)
        }
        XCTAssertEqual(try recordFiles(), before, "a-person 不得先寫")
        XCTAssertNoThrow(try AuthorizedNameMigration.run(store: store, apply: false), "乾跑照常出報告")
    }

    /// 寫入集合裡有一筆指定之後會超過讀取上限（#648）：整批零寫入、marker 不動（#648 C2b verify）。
    func testAuthorizeNamesWritesNothingWhenAnyPersonWouldExceedTheReadLimit() throws {
        try store.writePerson(Person(key: "a-person", names: ["Guan, Yongtao"]))
        // z-person 的檔恰在讀取上限之下：指定 authorized 會多出幾十個位元組，寫出後超過上限
        var z = Person(key: "z-person", names: ["Zed, Zoe"])
        z.note = ""
        let overhead = try PersonYAML.encode(z).utf8.count
        z.note = String(repeating: "a", count: Int(AliasEventBudget.maxBytes) - overhead - 1)   // 實測：檔恰等於上限（指定只多 3 個位元組）
        let size = try PersonYAML.encode(z).utf8.count
        XCTAssertTrue(size <= Int(AliasEventBudget.maxBytes) && size > Int(AliasEventBudget.maxBytes) - 32, "前提：\(size)")
        try store.writePerson(z)
        commit()
        let before = try recordFiles()
        let markerBefore = try StoreVersion.read(root: root)
        XCTAssertThrowsError(try AuthorizedNameMigration.run(store: store, apply: true))
        XCTAssertEqual(try recordFiles(), before, "a-person 不得先寫")
        XCTAssertEqual(try StoreVersion.read(root: root), markerBefore)
    }

    // MARK: - import-wos

    /// 回填（只多不少）要改寫既有記錄——寫不進去的那一筆先前在寫入當下擲出，整趟匯入中斷、報告丟掉。
    func testWoSImportSkipsAnUnwritableExistingWorkAndKeepsGoing() throws {
        let header = "Authors\tArticle Title\tPublication Year\tDOI\tSource Title\tResearch Areas\n"
        let row = "Cheng, Che\tA Paper\t2025\t10.1/x\tJournal A\tPsychology\n"
        _ = try WoSImport.run(text: header + row, store: store)
        var existing = try XCTUnwrap(try store.load().entries.first)
        existing.fields["research_areas"] = nil   // 模擬 #206 之前匯入的記錄——重跑時走「只多不少」的回填
        try FileManager.default.removeItem(at: store.entityURL(id: existing.id))
        let legacyURL = try writeLegacy(existing)   // 只住在 legacy、沒 commit：搬移刪了回不來
        let legacyBefore = try Data(contentsOf: legacyURL)
        XCTAssertEqual(try store.load().entries.unlocatableCitekeys, [existing.citekey], "前提：load 已標出")
        let tsv = header
            + "Olsson, Ulf\tAnother Paper\t2024\t10.1/y\tJournal B\tPsychology\n"   // 新的一篇，照建
            + row                                                                          // 對到那筆 → 回填
        var report: WoSImport.Report?
        XCTAssertNoThrow(report = try WoSImport.run(text: tsv, store: store), "不得寫到一半才擲出")
        XCTAssertTrue(report?.skippedRows.contains { $0.contains(existing.citekey) && $0.contains("#641") } == true,
                      "\(report?.skippedRows ?? [])")
        XCTAssertEqual(report?.enriched, [])
        XCTAssertEqual(report?.created.count, 1, "其餘照寫")
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBefore)
        XCTAssertFalse(FileManager.default.fileExists(atPath: store.entityURL(id: existing.id).path), "沒有寫出第二份")
    }

    /// 寫入集合裡有一筆寫出後會超過讀取上限（#648）：整趟零寫入（#648 C2b verify，DA HIGH）。
    /// 先前逐列寫：第一列的新作品已落盤，第二列才在寫入當下被拒、報告隨 throw 丟掉。
    func testWoSImportWritesNothingWhenAnyRowWouldBeRefusedOnWrite() throws {
        let header = "Authors\tArticle Title\tPublication Year\tDOI\tSource Title\tAbstract\n"
        let huge = String(repeating: "a", count: Int(AliasEventBudget.maxBytes) + 1_024)
        let tsv = header
            + "Olsson, Ulf\tFirst Paper\t2024\t10.1/first\tJournal B\tshort\n"
            + "Cheng, Che\tSecond Paper\t2025\t10.1/second\tJournal A\t\(huge)\n"
        let before = try recordFiles()
        XCTAssertThrowsError(try WoSImport.run(text: tsv, store: store)) { err in
            let text = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(text.contains("cheng2025"), "拒絕要具名那一筆：\(text.prefix(400))")
        }
        XCTAssertEqual(try recordFiles(), before, "第一列不得先落盤")
    }
}
