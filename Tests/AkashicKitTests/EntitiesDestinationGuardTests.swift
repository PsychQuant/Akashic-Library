import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit

/// #631：entities 佈局下，以 id 定檔的寫入在寫之前確認目的檔——要嘛不存在，要嘛是同一種記錄、同一個 id。
///
/// 先前五個寫入者都 `atomicWrite` 無條件覆寫 `entities/<id>.yaml`：被 quarantine 的記錄（load 不收，
/// 任何以載入母體為準的閘都看不到）或另一種記錄會被整個蓋掉；legacy 拷貝還在時寫入會造出同 id 的第二份，
/// rename 會造出兩個 citekey 共用一個 UUID（#627 R2／R3 verify 真 binary 重現）。只拒寫，不刪檔。
final class EntitiesDestinationGuardTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    let q = UUID()

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-destguard-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertTrue(store.usesEntitiesLayout, "前提：entities 佈局")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var dest: URL { store.entityURL(id: q) }

    /// 目的檔是一筆被 quarantine 的 work（type 是不存在的值——load 收不進來）。
    private func seedQuarantinedWork() throws -> Data {
        let text = "work:\nid: \(q.uuidString)\ncitekey: q2020\ntype: not-a-real-type\ntitle: Precious\n"
        try text.write(to: dest, atomically: true, encoding: .utf8)
        XCTAssertTrue(try store.load().quarantined.contains { $0.file.contains(q.uuidString) }, "前提：被 quarantine")
        return try Data(contentsOf: dest)
    }

    private func assertRefused(_ body: () throws -> Void, file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try body(), file: file, line: line) { err in
            let text = (err as? LocalizedError)?.errorDescription ?? "\(err)"
            XCTAssertTrue(text.contains("#631"), text, file: file, line: line)
        }
    }

    func testEveryWriterRefusesToOverwriteAQuarantinedRecord() throws {
        let before = try seedQuarantinedWork()
        assertRefused { _ = try self.store.writeEntry(Entry(id: self.q, citekey: "z2019", type: .periodicalArticle, title: "Z")) }
        assertRefused { _ = try self.store.writePerson(Person(key: "someone", names: ["Some One"], id: self.q)) }
        assertRefused {
            _ = try self.store.writeVenue(Venue(key: "alpha", type: .periodical,
                                                names: Timeline([TemporalValue(value: "Alpha Journal")]), authorized: [], id: self.q))
        }
        assertRefused { _ = try self.store.writeOrganization(Organization(key: "moe", id: self.q)) }
        assertRefused {
            _ = try self.store.writeDivergence(Divergence(id: self.q, question: "?", candidates: [
                DivergenceCandidate(key: "a", shape: .work), DivergenceCandidate(key: "b", shape: .work)]))
        }
        XCTAssertEqual(try Data(contentsOf: dest), before, "被 quarantine 的那筆一個位元都不動")
    }

    func testWriterRefusesToOverwriteARecordOfAnotherKind() throws {
        _ = try store.writePerson(Person(key: "someone", names: ["Some One"], id: q))
        let before = try Data(contentsOf: dest)
        assertRefused { _ = try self.store.writeEntry(Entry(id: self.q, citekey: "z2019", type: .periodicalArticle, title: "Z")) }
        XCTAssertEqual(try Data(contentsOf: dest), before)
    }

    private func writeLegacyEntry(_ e: Entry) throws -> URL {
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        let url = store.entriesDir.appendingPathComponent("\(e.citekey).yaml")
        try EntryYAML.encode(e).write(to: url, atomically: true, encoding: .utf8)
        return url
    }

    /// 只有 legacy 一份（使用者 2026-09-24 裁決：搬移）：寫入落到 entities/，legacy 檔隨之刪除——不留第二份。
    func testWriteEntryMovesALegacyOnlyRecord() throws {
        let legacy = Entry(id: q, citekey: "z2019", type: .periodicalArticle, title: "Legacy")
        let legacyURL = try writeLegacyEntry(legacy)
        var edited = legacy; edited.title = "Edited"
        XCTAssertNoThrow(try store.writeEntry(edited))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path), "搬移完成：legacy 檔已刪")
        XCTAssertEqual(try store.load().entries.map(\.title), ["Edited"], "只剩一份，而且是改過的")
    }

    /// 兩份都在（遷移做到一半、可能已分岔）：拒寫，兩份都不動。
    func testWriteEntryRefusesWhenBothCopiesExist() throws {
        let legacy = Entry(id: q, citekey: "z2019", type: .periodicalArticle, title: "Legacy")
        let legacyURL = try writeLegacyEntry(legacy)
        var modern = legacy; modern.title = "Modern"
        try EntryYAML.encode(modern).write(to: dest, atomically: true, encoding: .utf8)
        let (lb, db) = (try Data(contentsOf: legacyURL), try Data(contentsOf: dest))
        var edited = modern; edited.title = "Edited"
        assertRefused { _ = try self.store.writeEntry(edited) }
        XCTAssertEqual(try Data(contentsOf: legacyURL), lb)
        XCTAssertEqual(try Data(contentsOf: dest), db)
    }

    /// rename 對只住在 legacy 的記錄：改名後只剩 entities/ 的一份（不再造出兩個 citekey 共用一個 UUID）。
    func testRenameMovesALegacyOnlyRecord() throws {
        let oldURL = try writeLegacyEntry(Entry(id: q, citekey: "old2020", type: .periodicalArticle, title: "Legacy"))
        XCTAssertNoThrow(try store.renameEntry(from: "old2020", to: "new2020"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: oldURL.path))
        XCTAssertEqual(try store.load().entries.map(\.citekey), ["new2020"])
    }

    /// R1 verify 的撕裂重現：rename 要改寫的**另一筆** work 只住在 legacy——先前寫到一半才撞上拒絕，
    /// 留下改了名的本筆與仍指舊 citekey 的 relation。現在那一筆一併搬移，整個 rename 完成。
    func testRenameDoesNotTearWhenAnotherRewrittenWorkIsLegacyOnly() throws {
        _ = try store.writeEntry(Entry(id: q, citekey: "alpha2020", type: .periodicalArticle, title: "A"))
        var beta = Entry(id: UUID(), citekey: "beta2021", type: .periodicalArticle, title: "B")
        beta.akashic.relations.cites = ["alpha2020"]
        _ = try writeLegacyEntry(beta)
        XCTAssertNoThrow(try store.renameEntry(from: "alpha2020", to: "alpha2020b"))
        let load = try store.load()
        XCTAssertEqual(load.entries.first { $0.citekey == "beta2021" }?.akashic.relations.cites, ["alpha2020b"])
        XCTAssertEqual(load.entries.count, 2, "沒有第二份拷貝")
    }

    /// preflight：rename 要改寫的另一筆，其目的檔是被 quarantine 的記錄——在**任何寫入之前**拒絕，本筆不改名。
    func testRenameRefusesBeforeAnyWriteWhenAnotherTargetIsQuarantined() throws {
        let alpha = Entry(id: UUID(), citekey: "alpha2020", type: .periodicalArticle, title: "A")
        _ = try store.writeEntry(alpha)
        var beta = Entry(id: q, citekey: "beta2021", type: .periodicalArticle, title: "B")
        beta.akashic.relations.cites = ["alpha2020"]
        _ = try writeLegacyEntry(beta)
        let quarantined = try seedQuarantinedWork()
        let alphaURL = store.entityURL(id: alpha.id)
        let alphaBefore = try Data(contentsOf: alphaURL)
        assertRefused { _ = try self.store.renameEntry(from: "alpha2020", to: "alpha2020b") }
        XCTAssertEqual(try Data(contentsOf: alphaURL), alphaBefore, "本筆一個位元都不動——不是寫到一半才拒")
        XCTAssertEqual(try Data(contentsOf: dest), quarantined)
    }

    /// person 的 legacy 單份同樣搬移；rename-person 的舊 key legacy 單份也是。
    func testPersonLegacyOnlyRecordIsMovedOnWriteAndRename() throws {
        try FileManager.default.createDirectory(at: store.root.appendingPathComponent("people"), withIntermediateDirectories: true)
        let p = Person(key: "p-one", names: ["P One"], id: q)
        let legacyURL = store.personURL(key: "p-one")
        try PersonYAML.encode(p).write(to: legacyURL, atomically: true, encoding: .utf8)
        XCTAssertNoThrow(try store.renamePerson(from: "p-one", to: "p-two"))
        XCTAssertFalse(FileManager.default.fileExists(atPath: legacyURL.path))
        XCTAssertEqual(try store.load().people.map(\.key), ["p-two"])
    }

    /// 形狀標籤與 load 同一套嚴格度：缺標籤的 entities 檔被 load 隔離，也不得被當成同一筆而覆寫（R1 verify Codex）。
    func testUnlabelledDestinationIsNotOverwritten() throws {
        let text = "id: \(q.uuidString)\ncitekey: z2019\ntype: periodical-article\ntitle: Unlabelled\n"
        try text.write(to: dest, atomically: true, encoding: .utf8)
        let before = try Data(contentsOf: dest)
        assertRefused { _ = try self.store.writeEntry(Entry(id: self.q, citekey: "z2019", type: .periodicalArticle, title: "Z")) }
        XCTAssertEqual(try Data(contentsOf: dest), before)
    }

    /// 健康路徑：更新同一筆、rename（同 id 同種、citekey 改變）照常。
    func testNormalUpdateAndRenameStillWork() throws {
        var e = Entry(id: q, citekey: "a2020", type: .periodicalArticle, title: "A")
        _ = try store.writeEntry(e)
        e.title = "A2"
        XCTAssertNoThrow(try store.writeEntry(e))
        XCTAssertNoThrow(try store.renameEntry(from: "a2020", to: "b2020"))
        XCTAssertEqual(try store.load().entries.map(\.citekey), ["b2020"])
    }

    /// service 端：#627 R3 DA 的形狀——legacy z2019（id Q）＋ entities/Q 是被 quarantine 的另一筆。
    /// judge 對 z2019 不得把 entities/Q 蓋掉。
    func testResolvePeopleJudgeCannotOverwriteAQuarantinedSibling() throws {
        let before = try seedQuarantinedWork()
        try store.writePerson(Person(key: "olsson-ulf", names: ["Ulf Olsson"]))
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        let legacy = Entry(id: q, citekey: "z2019", type: .periodicalArticle, title: "Z",
                           authors: [.literal("Ulf Olsson")], date: "2019")
        try EntryYAML.encode(legacy).write(to: store.entriesDir.appendingPathComponent("z2019.yaml"),
                                           atomically: true, encoding: .utf8)
        let service = AkashicService(root: root, key: nil, environment: [:])
        _ = try? service.resolvePeople(apply: nil, judge: ["z2019:0:olsson-ulf=查證"])
        _ = try? service.dropAuthors(["z2019:Ulf Olsson=不是人"])
        XCTAssertEqual(try Data(contentsOf: dest), before, "被 quarantine 的兄弟一個位元都不動")
        let olsson = try XCTUnwrap(try store.load().people.first { $0.key == "olsson-ulf" })
        XCTAssertFalse(olsson.references.contains { ($0.value ?? "").contains("work:z2019 ") }, "沒落地就不得寫 verdict")
    }
}
