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

    /// legacy 拷貝還在（遷移沒做完）：寫入不得在 entities/ 造出第二份。
    func testWriteEntryRefusesWhileALegacyCopyOfTheSameRecordExists() throws {
        let legacy = Entry(id: q, citekey: "z2019", type: .periodicalArticle, title: "Legacy")
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        let legacyURL = store.entriesDir.appendingPathComponent("z2019.yaml")
        try EntryYAML.encode(legacy).write(to: legacyURL, atomically: true, encoding: .utf8)
        let legacyBefore = try Data(contentsOf: legacyURL)
        var edited = legacy; edited.title = "Edited"
        assertRefused { _ = try self.store.writeEntry(edited) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path), "不得在 entities/ 造出第二份")
        XCTAssertEqual(try Data(contentsOf: legacyURL), legacyBefore)
    }

    /// rename 對只住在 legacy 的記錄：改名後兩個 citekey 會共用一個 UUID——在任何寫入之前擋下。
    func testRenameRefusesWhileTheOldLegacyCopyExists() throws {
        let legacy = Entry(id: q, citekey: "old2020", type: .periodicalArticle, title: "Legacy")
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        try EntryYAML.encode(legacy).write(to: store.entriesDir.appendingPathComponent("old2020.yaml"),
                                           atomically: true, encoding: .utf8)
        assertRefused { _ = try self.store.renameEntry(from: "old2020", to: "new2020") }
        XCTAssertFalse(FileManager.default.fileExists(atPath: dest.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: store.entriesDir.appendingPathComponent("old2020.yaml").path))
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
