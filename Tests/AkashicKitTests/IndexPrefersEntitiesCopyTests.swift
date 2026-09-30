import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicIndex
@testable import AkashicSQLite

/// #709（使用者 2026-09-30 裁決）：index 重建遇到同一筆記錄兩份——一份在 `entities/`、一份是 #631 搬移後沒刪掉的 legacy 拷貝——
/// 以 `entities/` 那份為準、略過 legacy 拷貝並回報。
///
/// 「同一筆」的判準是 **同一種、同一個 id**（`LibraryStore.markLegacyCopiesShadowedByEntities`）。本檔釘住：
/// - work：一般寫入留下的（citekey 相同）與改名留下的（citekey 不同、id 相同）都只剩 entities/ 那一列，重建成功、報告具名；
/// - person：同 key 時 index 的名字取 entities/ 那一份；改名留下的舊 key 不進 index；
/// - 兩筆**不同**的記錄共用 citekey（id 不同）不在此列——重建照舊撞 UNIQUE；
/// - format 1 的 store 不套用（那裡 legacy 目錄是正典）；
/// - 記錄本身的寫入封鎖（#641）與 validate 的報告不變，warning 多說一句 index 取哪一份。
final class IndexPrefersEntitiesCopyTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-709-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        store = LibraryStore(root: root, key: nil, environment: [:])
        try store.ensureLayout()
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertTrue(store.usesEntitiesLayout, "前提：entities 佈局——legacy 目錄在這裡是殘留")
    }

    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    // MARK: - 夾具

    private func work(_ citekey: String, id: UUID = UUID(), title: String) -> Entry {
        Entry(id: id, citekey: citekey, type: .periodicalArticle, title: title, date: "2025")
    }

    /// `entities/<id>.yaml`——直接寫檔，不經 `writeEntry`（那會對 legacy 殘留跑 #631 的搬移前置）。
    private func writeEntities(_ e: Entry) throws {
        try EntryYAML.encode(e).write(to: store.entityURL(id: e.id), atomically: true, encoding: .utf8)
    }

    private func writeEntities(_ p: Person) throws {
        try PersonYAML.encode(p).write(to: store.entityURL(id: p.id), atomically: true, encoding: .utf8)
    }

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

    private func rows(_ sql: String, _ bind: [Any?] = []) throws -> [[String: Any]] {
        try SQLiteDB(path: store.indexURL.path, readOnly: true).query(sql, bind: bind)
    }

    // MARK: - work

    /// 一般寫入留下的：兩份共用 id 與 citekey。先前撞 `entries.citekey` UNIQUE、整次重建失敗。
    func testWorkLeftoverWithTheSameCitekeyIndexesTheEntitiesCopyAndReportsIt() throws {
        let id = UUID()
        try writeEntities(work("cheng2025identifiability", id: id, title: "Entities title"))
        try writeLegacy(work("cheng2025identifiability", id: id, title: "Legacy title"))

        let load = try store.load()
        XCTAssertEqual(load.entries.count, 2, "前提：load 兩份都讀到（validate 照舊報兩份並存）")
        XCTAssertEqual(load.shadowedLegacyCopies,
                       [ShadowedLegacyCopy(kind: .work, key: "cheng2025identifiability", id: id,
                                           legacyFile: "entries/cheng2025identifiability.yaml")])

        let stats = try LibraryIndex(store: store).rebuild()
        XCTAssertEqual(stats.entries, 1, "進 index 的只有一筆")
        XCTAssertEqual(stats.skippedLegacyCopies.map(\.legacyFile), ["entries/cheng2025identifiability.yaml"])
        XCTAssertEqual(stats.skippedLegacyCopies.first?.entitiesFile, "entities/\(id.uuidString).yaml")
        let indexed = try rows("SELECT uuid, citekey, title FROM entries WHERE uuid = ?", [id.uuidString])
        XCTAssertEqual(indexed.count, 1, "\(indexed)")
        XCTAssertEqual(indexed.first?["title"] as? String, "Entities title", "取 entities/ 那一份，不是 legacy 那一份")
        XCTAssertEqual(try rows("SELECT entry_count FROM index_identity").first?["entry_count"] as? Int, 1,
                       "身分戳記的筆數與 index 一致")
    }

    /// 改名留下的：legacy 那份是改名前的 citekey、id 相同。先前撞 `entries.uuid` PRIMARY KEY。
    func testWorkLeftoverFromARenameKeepsOnlyTheNewCitekey() throws {
        let id = UUID()
        try writeEntities(work("cheng2025renamed", id: id, title: "Renamed"))
        try writeLegacy(work("cheng2025identifiability", id: id, title: "Old name"))

        let stats = try LibraryIndex(store: store).rebuild()
        XCTAssertEqual(try rows("SELECT citekey FROM entries").map { $0["citekey"] as? String }, ["cheng2025renamed"])
        XCTAssertEqual(stats.skippedLegacyCopies,
                       [ShadowedLegacyCopy(kind: .work, key: "cheng2025identifiability", id: id,
                                           legacyFile: "entries/cheng2025identifiability.yaml")])
        // 寫入封鎖不變（#641）：兩個 citekey 都無法唯一定位——共用 id
        XCTAssertEqual(try store.load().entries.unlocatableCitekeys, ["cheng2025identifiability", "cheng2025renamed"])
    }

    /// 兩筆**不同**的記錄（id 不同）共用一個 citekey：真的重複，這條規則不替它選一筆——重建照舊失敗，也沒有任何一筆被標成拷貝。
    /// 一份在 entities/、一份在 legacy 的形狀與上面那一對長得最像，所以兩種擺法都測。
    func testDistinctRecordsSharingACitekeyStillFailTheRebuild() throws {
        try writeEntities(work("dup2020x", title: "A"))
        try writeLegacy(work("dup2020x", title: "B"))
        XCTAssertEqual(try store.load().shadowedLegacyCopies, [], "id 不同就不是同一筆")
        XCTAssertThrowsError(try LibraryIndex(store: store).rebuild(), "一份 entities、一份 legacy") { error in
            XCTAssertTrue("\(error)".contains("UNIQUE"), "\(error)")
        }

        try FileManager.default.removeItem(at: store.entriesDir)
        try writeEntities(work("dup2020x", title: "C"))
        XCTAssertEqual(try store.load().entries.filter { $0.citekey == "dup2020x" }.count, 2, "前提：兩筆都在 entities/")
        XCTAssertThrowsError(try LibraryIndex(store: store).rebuild(), "兩份都在 entities/")
    }

    /// 同一個 id、不同種：entities/ 那一份是 person，legacy 那份是 work——不是同一筆記錄（#631 的目的檔檢查當它是「另一種記錄」）。
    func testTheSameIDOfAnotherKindIsNotACopy() throws {
        let id = UUID()
        try writeEntities(Person(key: "cheng-che", names: PersonNames(authorized: ["Che Cheng"]), id: id))
        try writeLegacy(work("cheng2025identifiability", id: id, title: "W"))
        XCTAssertEqual(try store.load().shadowedLegacyCopies, [])
        let stats = try LibraryIndex(store: store).rebuild()
        XCTAssertEqual(stats.entries, 1, "legacy 那筆 work 沒有同種的 entities/ 記錄，照常進 index")
    }

    /// format 1 的 `entries/`／`people/` 是正典位置——即使 entities/ 有同一個 id 的檔，也不以它為準（規則限 format ≥ 2）。
    func testFormatOneStoresDoNotApplyTheRule() throws {
        let id = UUID()
        try writeEntities(work("cheng2025identifiability", id: id, title: "Entities title"))
        try writeLegacy(work("cheng2025identifiability", id: id, title: "Legacy title"))
        try StoreVersion.write(root: root, format: 1)
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 2, "前提：兩份都讀到")
        XCTAssertEqual(load.shadowedLegacyCopies, [], "format 1 不標")
    }

    // MARK: - person

    /// 同 key：先前 people 表 `INSERT OR IGNORE` 留下列舉順序的第一筆（#670）；現在由判準決定——entities/ 那一份。
    func testPersonLeftoverWithTheSameKeyIndexesTheEntitiesNames() throws {
        let id = UUID()
        try writeEntities(Person(key: "yang-hau-hung", names: PersonNames(authorized: ["Yang, Hau-Hung"]), id: id))
        try writeLegacy(Person(key: "yang-hau-hung", names: PersonNames(variant: ["Hau-Hung Yang (legacy)"]), id: id))
        let stats = try LibraryIndex(store: store).rebuild()
        XCTAssertEqual(stats.people, 1)
        XCTAssertEqual(stats.skippedLegacyCopies.map(\.legacyFile), ["people/yang-hau-hung.yaml"])
        let names = try rows("SELECT names FROM people WHERE key = 'yang-hau-hung'").first?["names"] as? String
        XCTAssertEqual(names, "Yang, Hau-Hung", "取 entities/ 那一份的名字")
    }

    /// 改名留下的：舊 key 先前另成一列（兩個 key 各一列、指向同一個人）；現在只剩新 key。
    func testPersonLeftoverFromARenameDoesNotIndexTheOldKey() throws {
        let id = UUID()
        try writeEntities(Person(key: "yang-h-h", names: PersonNames(authorized: ["Yang, H.-H."]), id: id))
        try writeLegacy(Person(key: "yang-hau-hung", names: PersonNames(variant: ["Hau-Hung Yang"]), id: id))
        let stats = try LibraryIndex(store: store).rebuild()
        XCTAssertEqual(try rows("SELECT key FROM people ORDER BY key").map { $0["key"] as? String }, ["yang-h-h"])
        XCTAssertEqual(stats.skippedLegacyCopies,
                       [ShadowedLegacyCopy(kind: .person, key: "yang-hau-hung", id: id, legacyFile: "people/yang-hau-hung.yaml")])
        XCTAssertEqual(try store.load().people.unlocatablePersonKeys, ["yang-hau-hung"],
                       "legacy 那份照舊寫不進去（#641）")
    }

    /// #645 的記錄位元組以 entities/ 那一份為準——legacy 那份先讀的話會蓋掉它，而預算預警量的是之後會長的那個檔。
    func testRecordBytesFollowTheEntitiesCopy() throws {
        let id = UUID()
        let fresh = Person(key: "yang-hau-hung", names: PersonNames(authorized: ["Yang, Hau-Hung"], variant: ["Hau-Hung Yang", "楊昊紘"]), id: id)
        try writeEntities(fresh)
        try writeLegacy(Person(key: "yang-hau-hung", names: PersonNames(variant: ["H. Yang"]), id: id))
        let entitiesBytes = try Data(contentsOf: store.entityURL(id: id)).count
        XCTAssertNotEqual(entitiesBytes, try Data(contentsOf: store.personURL(key: "yang-hau-hung")).count, "前提：兩份大小不同")
        XCTAssertEqual(try store.load().recordBytes[id], entitiesBytes)
    }

    // MARK: - validate 的報告

    /// 記錄本身照舊寫不進去、validate 照舊報兩份並存（#641 的 warning 與 UUID／citekey 的 error），warning 多說一句 index 取哪一份。
    func testValidateStillReportsBothCopiesAndSaysWhichOneTheIndexTakes() throws {
        let id = UUID()
        try writeEntities(work("cheng2025identifiability", id: id, title: "Entities title"))
        try writeLegacy(work("cheng2025identifiability", id: id, title: "Legacy title"))
        let load = try store.load()
        XCTAssertTrue(load.entries.unlocatableCitekeys.contains("cheng2025identifiability"), "寫入封鎖不變（#641）")
        let issues = load.crossRecordIssues()
        let warning = try XCTUnwrap(issues.first { $0.message.contains("work「cheng2025identifiability」的檔案寫入時會被拒") },
                                    "\(issues.map(\.message))")
        XCTAssertEqual(warning.severity, .warning)
        XCTAssertTrue(warning.message.contains("index 以 entities/ 那份為準、略過 legacy 拷貝"), warning.message)
        let uuidError = try XCTUnwrap(issues.first { $0.message.contains("UUID \(id.uuidString)") }, "\(issues.map(\.message))")
        XCTAssertEqual(uuidError.severity, .error, "error 照舊——它也擋改名與合併（#35）")
        XCTAssertTrue(uuidError.message.contains("legacy 拷貝由 index 略過"), uuidError.message)
        XCTAssertFalse(uuidError.message.contains("靜默丟掉"), "這一對不再是靜默的：\(uuidError.message)")
        XCTAssertTrue(issues.contains { $0.severity == .error && $0.message.contains("citekey「cheng2025identifiability」重複") })
    }

    /// 真的重複（id 不同）的 UUID 訊息不變——那一句說的不是 #709 那一對。
    func testADistinctSharedUUIDKeepsItsMessage() throws {
        try StoreVersion.write(root: root, format: 1)   // 兩筆不同 citekey 共用 UUID 只在 legacy 佈局寫得出來（entities 的檔名就是 id）
        let shared = UUID()
        try writeLegacy(work("a2020a", id: shared, title: "A"))
        try writeLegacy(work("b2020b", id: shared, title: "B"))
        let message = try XCTUnwrap(try store.load().crossRecordIssues().first { $0.message.contains("UUID \(shared.uuidString)") }?.message)
        XCTAssertFalse(message.contains("#709"), message)
    }
}
