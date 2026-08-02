import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicSQLite
@testable import AkashicZoteroImport

/// Zotero fixture：以最小 schema 子集在 temp 目錄建 zotero.sqlite。
/// 只建 importer 會讀的表；schema 對齊實際 Zotero 7。
struct ZoteroFixture {
    let dbURL: URL
    let db: SQLiteDB

    init(dir: URL) throws {
        dbURL = dir.appendingPathComponent("zotero.sqlite")
        db = try SQLiteDB(path: dbURL.path, readOnly: false)
        for sql in [
            "CREATE TABLE itemTypes(itemTypeID INTEGER PRIMARY KEY, typeName TEXT)",
            "CREATE TABLE items(itemID INTEGER PRIMARY KEY, itemTypeID INT, key TEXT, version INT, libraryID INT)",
            "CREATE TABLE fields(fieldID INTEGER PRIMARY KEY, fieldName TEXT)",
            "CREATE TABLE itemDataValues(valueID INTEGER PRIMARY KEY, value TEXT)",
            "CREATE TABLE itemData(itemID INT, fieldID INT, valueID INT)",
            "CREATE TABLE creators(creatorID INTEGER PRIMARY KEY, firstName TEXT, lastName TEXT, fieldMode INT)",
            "CREATE TABLE creatorTypes(creatorTypeID INTEGER PRIMARY KEY, creatorType TEXT)",
            "CREATE TABLE itemCreators(itemID INT, creatorID INT, creatorTypeID INT, orderIndex INT)",
            "CREATE TABLE deletedItems(itemID INT)",
            "CREATE TABLE itemAttachments(itemID INT, parentItemID INT, path TEXT, contentType TEXT)",
            "CREATE TABLE tags(tagID INTEGER PRIMARY KEY, name TEXT)",
            "CREATE TABLE itemTags(itemID INT, tagID INT, type INT)",
        ] {
            try db.execute(sql)
        }
        try db.execute("INSERT INTO itemTypes VALUES (1,'journalArticle'),(2,'book'),(3,'attachment'),(4,'note')")
        try db.execute("INSERT INTO creatorTypes VALUES (1,'author'),(2,'editor')")
        try db.execute("INSERT INTO fields VALUES (1,'title'),(2,'date'),(3,'publicationTitle'),(4,'volume'),(5,'issue'),(6,'DOI'),(7,'pages')")
    }

    func addField(item: Int, field: Int, value: String, valueID: Int) throws {
        try db.execute("INSERT INTO itemDataValues VALUES (?,?)", bind: [valueID, value])
        try db.execute("INSERT INTO itemData VALUES (?,?,?)", bind: [item, field, valueID])
    }

    /// 標準 fixture：一篇 article（雙作者、tag、storage 附件）+ 一本 book。
    func seedStandard() throws {
        try db.execute("INSERT INTO items VALUES (10,1,'KEYART01',5,1)")
        try addField(item: 10, field: 1, value: "Identifiability of polychoric models", valueID: 100)
        try addField(item: 10, field: 2, value: "2025-04-01", valueID: 101)
        try addField(item: 10, field: 3, value: "Psychometrika", valueID: 102)
        try addField(item: 10, field: 4, value: "90", valueID: 103)
        try addField(item: 10, field: 5, value: "2", valueID: 104)
        try addField(item: 10, field: 6, value: "10.1017/psy.2025.1", valueID: 105)
        try db.execute("INSERT INTO creators VALUES (1,'Che','Cheng',0),(2,'Hau-Hung','Yang',0)")
        try db.execute("INSERT INTO itemCreators VALUES (10,1,1,0),(10,2,1,1)")
        try db.execute("INSERT INTO tags VALUES (1,'identifiability')")
        try db.execute("INSERT INTO itemTags VALUES (10,1,0)")
        // storage 附件（child item 20）
        try db.execute("INSERT INTO items VALUES (20,3,'KEYATT01',5,1)")
        try db.execute("INSERT INTO itemAttachments VALUES (20,10,'storage:paper.pdf','application/pdf')")
        // book（單作者 fieldMode 1）
        try db.execute("INSERT INTO items VALUES (11,2,'KEYBOOK1',7,1)")
        try addField(item: 11, field: 1, value: "Matrix Visualization", valueID: 110)
        try addField(item: 11, field: 2, value: "2004", valueID: 111)
        try db.execute("INSERT INTO creators VALUES (3,'','Chun-Houh Chen',1)")
        try db.execute("INSERT INTO itemCreators VALUES (11,3,1,0)")
    }
}

final class ZoteroImportTests: XCTestCase {
    var dir: URL!
    var store: LibraryStore!
    var fixture: ZoteroFixture!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-zimport-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let libRoot = dir.appendingPathComponent("library")
        try FileManager.default.createDirectory(at: libRoot, withIntermediateDirectories: true)
        store = LibraryStore(root: libRoot)
        try store.ensureLayout()
        fixture = try ZoteroFixture(dir: dir)
        try fixture.seedStandard()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    /// 把 store 切成 **legacy 佈局**（`entries/<citekey>.yaml`）。
    ///
    /// 只給結構性依賴 legacy 檔名語意的測試用——它們直接往 `entriesDir` 寫 citekey 檔名
    /// 來製造 stem 不符。**不放 setUp**：其餘 25 個測試（idempotent re-import、version bump、
    /// orphan 標記、hash backfill、多 library scoping…）走的是格式無關的高階 API，
    /// 整組釘死會拿掉它們在**實際出貨格式**（entities）下的覆蓋（#56 verify DA 發現）。
    ///
    /// 呼叫時機必須在任何 import 之前——此時 store 還是空的，改格式標記不會造成混合佈局。
    private func useLegacyLayout() throws {
        try StoreVersion.write(root: store.root, format: 1)
    }

    private func runImport() throws -> ImportReport {
        let importer = ZoteroImporter(store: store)
        return try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_000_000))
    }

    func testFirstImportCreatesEntries() throws {
        let report = try runImport()
        XCTAssertEqual(report.created.sorted(), ["chen2004matrix", "cheng2025identifiability"])
        XCTAssertEqual(report.updated, [])
        XCTAssertEqual(report.orphaned, [])

        let load = try store.load()
        let article = load.entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(article.type, "article")
        XCTAssertEqual(article.title, "Identifiability of polychoric models")
        XCTAssertEqual(article.authors, [.literal("Che Cheng"), .literal("Hau-Hung Yang")])
        XCTAssertEqual(article.date, "2025-04-01")
        XCTAssertEqual(article.fields["journaltitle"], "Psychometrika")
        XCTAssertEqual(article.fields["volume"], "90")
        XCTAssertEqual(article.fields["number"], "2")
        XCTAssertEqual(article.fields["doi"], "10.1017/psy.2025.1")
        XCTAssertEqual(article.attachments, [AttachmentRef(kind: .zotero, path: "storage/KEYATT01/paper.pdf")])
        XCTAssertEqual(article.provenance?.zoteroKey, "KEYART01")
        XCTAssertEqual(article.provenance?.zoteroVersion, 5)
        XCTAssertEqual(article.akashic.tags, ["identifiability"])  // 建檔 seed

        let book = load.entries.first { $0.citekey == "chen2004matrix" }!
        XCTAssertEqual(book.type, "book")
        XCTAssertEqual(book.authors, [.literal("Chun-Houh Chen")])  // fieldMode 1
    }

    func testSecondImportIsIdempotent() throws {
        _ = try runImport()
        let before = try store.load().entries
        let report = try runImport()
        XCTAssertEqual(report.created, [])
        XCTAssertEqual(report.updated, [])
        XCTAssertEqual(report.orphaned, [])
        XCTAssertEqual(report.unchanged, 2)
        XCTAssertEqual(try store.load().entries, before)
    }

    func testVersionBumpUpdatesBiblatexButNotAkashic() throws {
        _ = try runImport()
        // 使用者在 akashic namespace 加了衍生資料
        var article = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        article.akashic.status = "reading"
        article.akashic.relations.cites = ["olsson1979maximum"]
        try store.writeEntry(article)
        // Zotero 端改 title + bump version
        try fixture.db.execute("UPDATE itemDataValues SET value='Updated title' WHERE valueID=100")
        try fixture.db.execute("UPDATE items SET version=9 WHERE itemID=10")

        let report = try runImport()
        XCTAssertEqual(report.updated, ["cheng2025identifiability"])
        let after = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(after.title, "Updated title")
        XCTAssertEqual(after.provenance?.zoteroVersion, 9)
        XCTAssertEqual(after.akashic.status, "reading")                       // akashic 不被覆寫
        XCTAssertEqual(after.akashic.relations.cites, ["olsson1979maximum"])
        XCTAssertEqual(after.id, article.id)                                   // UUID 不變
    }

    func testZoteroDeletionMarksOrphanNotDelete() throws {
        _ = try runImport()
        try fixture.db.execute("INSERT INTO deletedItems VALUES (11)")
        let report = try runImport()
        XCTAssertEqual(report.orphaned, ["chen2004matrix"])
        let book = try store.load().entries.first { $0.citekey == "chen2004matrix" }!
        XCTAssertNotNil(book.provenance?.orphanedAt)   // 標記，不刪檔
        // 再跑一次不重複 orphan
        let report2 = try runImport()
        XCTAssertEqual(report2.orphaned, [])
    }

    func testResolvedAuthorsArePreservedOnUpdate() throws {
        _ = try runImport()
        var article = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        article.authors[0] = .key("cheng-che")   // 使用者已解析第一作者
        try store.writeEntry(article)
        try fixture.db.execute("UPDATE items SET version=10 WHERE itemID=10")

        _ = try runImport()
        let after = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(after.authors.first, .key("cheng-che"))   // 解析成果不被 pull 摧毀
    }
}

extension ZoteroImportTests {
    // DA/Codex 確認的 data-loss 路徑：quarantined 檔絕不可被 import 覆寫
    func testQuarantinedFileIsNeverOverwritten() throws {
        let brokenURL = store.entriesDir.appendingPathComponent("cheng2025identifiability.yaml")
        let brokenContent = "this is: [not a valid entry\n"
        try brokenContent.write(to: brokenURL, atomically: true, encoding: .utf8)

        let report = try runImport()
        // 原檔一個 byte 都不能動
        XCTAssertEqual(try String(contentsOf: brokenURL, encoding: .utf8), brokenContent)
        // 新 entry 讓位：拿衝突後綴 key
        XCTAssertTrue(report.created.contains("cheng2025bidentifiability"), "\(report.created)")
    }

    func testOrphanClearedWhenItemReturnsAtSameVersion() throws {
        _ = try runImport()
        try fixture.db.execute("INSERT INTO deletedItems VALUES (11)")
        _ = try runImport()
        try fixture.db.execute("DELETE FROM deletedItems WHERE itemID = 11")
        let report = try runImport()
        XCTAssertEqual(report.orphanCleared, ["chen2004matrix"])
        let book = try store.load().entries.first { $0.citekey == "chen2004matrix" }!
        XCTAssertNil(book.provenance?.orphanedAt)
    }

    func testUnmappedZoteroFieldsAreReportedNotSilentlyDropped() throws {
        try fixture.db.execute("INSERT INTO fields VALUES (8,'extra')")
        try fixture.addField(item: 10, field: 8, value: "PMID: 12345", valueID: 199)
        let report = try runImport()
        XCTAssertEqual(report.droppedFields["extra"], 1)
    }

    func testDeletedAttachmentChildIsExcluded() throws {
        try fixture.db.execute("INSERT INTO deletedItems VALUES (20)")
        _ = try runImport()
        let article = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertTrue(article.attachments.isEmpty)
    }
}

extension ZoteroImportTests {
    // R2→#11 修訂：filename↔citekey 失衡的損壞 store 現在在 load() 就被 quarantine
    // （stem-mismatch 語意驗證），錯位 entry 不再進入 library。importer 視該 item 為
    // 缺席並重建 canonical 檔；兩個隔離檔（語法壞檔 + 錯位檔）一 byte 不動。
    func testMismatchedStemIsQuarantinedAtLoadAndReimportRebuildsCanonical() throws {
        try useLegacyLayout()   // 本測試直接往 entriesDir 寫 citekey 檔名（#56）
        _ = try runImport()
        let entries = store.entriesDir
        try "broken: [yaml\n".write(to: entries.appendingPathComponent("qtarget.yaml"),
                                    atomically: true, encoding: .utf8)
        var article = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        article.citekey = "qtarget"
        let mismatched = entries.appendingPathComponent("mismatch.yaml")
        let mismatchedText = try EntryYAML.encode(article)
        try mismatchedText.write(to: mismatched, atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(
            at: entries.appendingPathComponent("cheng2025identifiability.yaml"))
        try fixture.db.execute("UPDATE items SET version=99 WHERE itemID=10")

        let load = try store.load()
        XCTAssertEqual(load.quarantined.map(\.file).sorted(),
                       ["entries/mismatch.yaml", "entries/qtarget.yaml"],
                       "語法壞檔與 stem 錯位檔都必須 quarantine")

        let report = try runImport()
        XCTAssertTrue(report.created.contains("cheng2025identifiability"),
                      "被 quarantine 的 item 視為缺席，重建 canonical 檔：\(report.created)")
        XCTAssertEqual(try String(contentsOf: entries.appendingPathComponent("qtarget.yaml"),
                                  encoding: .utf8), "broken: [yaml\n")   // 隔離檔一 byte 不動
        XCTAssertEqual(try String(contentsOf: mismatched, encoding: .utf8), mismatchedText)
    }

    // R2：大小寫不敏感檔案系統上，大寫 quarantined basename 也要佔住 lowercase citekey
    func testQuarantineGuardIsCaseInsensitive() throws {
        let brokenURL = store.entriesDir.appendingPathComponent("Cheng2025identifiability.yaml")
        let broken = "this is: [not valid\n"
        try broken.write(to: brokenURL, atomically: true, encoding: .utf8)
        let report = try runImport()
        XCTAssertTrue(report.created.contains("cheng2025bidentifiability"), "\(report.created)")
        XCTAssertEqual(try String(contentsOf: brokenURL, encoding: .utf8), broken)
    }

    // R2：orphanCleared 不得同時計入 unchanged（報表語意）
    func testOrphanClearedNotCountedAsUnchanged() throws {
        _ = try runImport()
        try fixture.db.execute("INSERT INTO deletedItems VALUES (11)")
        _ = try runImport()
        try fixture.db.execute("DELETE FROM deletedItems WHERE itemID = 11")
        let report = try runImport()
        XCTAssertEqual(report.orphanCleared, ["chen2004matrix"])
        XCTAssertEqual(report.unchanged, 1)   // 只有 item 10
    }
}

extension ZoteroImportTests {
    // R3：大小寫變體副檔名的 quarantined 檔同樣佔住 citekey
    func testQuarantineGuardCoversUppercaseExtension() throws {
        let brokenURL = store.entriesDir.appendingPathComponent("cheng2025identifiability.YAML")
        let broken = "still: [broken\n"
        try broken.write(to: brokenURL, atomically: true, encoding: .utf8)
        let report = try runImport()
        XCTAssertTrue(report.created.contains("cheng2025bidentifiability"), "\(report.created)")
        XCTAssertEqual(try String(contentsOf: brokenURL, encoding: .utf8), broken)
    }

    // R3→#11 修訂：orphaned 錯位檔同樣在 load() 就 quarantine，不進 restore 路徑；
    // report 語意上該 item 是重建（created），不是 unchanged，也沒有寫入衝突。
    func testQuarantinedOrphanMismatchIsRebuiltNotUnchanged() throws {
        try useLegacyLayout()   // 本測試直接往 entriesDir 寫 citekey 檔名（#56）
        _ = try runImport()
        let entries = store.entriesDir
        try "broken: [yaml\n".write(to: entries.appendingPathComponent("qtarget.yaml"),
                                    atomically: true, encoding: .utf8)
        var article = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        article.citekey = "qtarget"
        article.provenance?.orphanedAt = Date(timeIntervalSince1970: 1_752_000_000)
        try EntryYAML.encode(article).write(
            to: entries.appendingPathComponent("mismatch.yaml"), atomically: true, encoding: .utf8)
        try FileManager.default.removeItem(
            at: entries.appendingPathComponent("cheng2025identifiability.yaml"))

        let report = try runImport()   // 錯位檔已 quarantine → item 10 重建
        XCTAssertTrue(report.created.contains("cheng2025identifiability"), "\(report.created)")
        XCTAssertEqual(report.unchanged, 1)   // 只有 item 11；重建的不是「無需變更」
    }
}

// ── Phase 2 schema 前置（#9）──

final class DateNormalizerTests: XCTestCase {
    func testZeroMonthDayTruncatesToYear() {
        XCTAssertEqual(DateNormalizer.normalize("1989-00-00 1989"), "1989")
    }
    func testFullISOKept() {
        XCTAssertEqual(DateNormalizer.normalize("2025-04-01"), "2025-04-01")
    }
    func testZeroDayTruncatesToYearMonth() {
        XCTAssertEqual(DateNormalizer.normalize("2020-05-00"), "2020-05")
    }
    func testYearOnlyKept() {
        XCTAssertEqual(DateNormalizer.normalize("2004"), "2004")
    }
    func testUnparseableReturnsNil() {
        XCTAssertNil(DateNormalizer.normalize("April 2020"))
        XCTAssertNil(DateNormalizer.normalize("circa 1990?"))
    }
}

extension ZoteroImportTests {
    func testImportNormalizesDatesAndReportsUnparseable() throws {
        try fixture.db.execute("UPDATE itemDataValues SET value='1989-00-00 1989' WHERE valueID=101")
        try fixture.db.execute("INSERT INTO items VALUES (12,1,'KEYWEIRD',3,1)")
        try fixture.addField(item: 12, field: 1, value: "Weird dated paper", valueID: 120)
        try fixture.addField(item: 12, field: 2, value: "April 2020", valueID: 121)

        let report = try runImport()
        let article = try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" }!
        XCTAssertEqual(article.date, "1989")                       // 正規化
        let weird = try store.load().entries.first { $0.provenance?.zoteroKey == "KEYWEIRD" }!
        XCTAssertEqual(weird.date, "April 2020")                   // 解析不了保留原字串
        XCTAssertEqual(report.unnormalizedDates, [weird.citekey])  // 且列入 report
    }

    func testHashBackfillUpdatesOnceThenIdempotent() throws {
        _ = try runImport()
        // 模擬 pre-Phase-2 store：抹掉 hash
        for entry in try store.load().entries {
            var e = entry
            e.provenance?.zoteroHash = nil
            try store.writeEntry(e)
        }
        let backfill = try runImport()
        XCTAssertEqual(backfill.updated.count, 2)     // hash 缺 → 全量補建
        let again = try runImport()
        XCTAssertEqual(again.updated, [])
        XCTAssertEqual(again.unchanged, 2)
    }

    func testContentChangeWithoutVersionBumpIsCaught() throws {
        _ = try runImport()
        // Zotero 本機改 title 但 version 沒動（未同步）
        try fixture.db.execute("UPDATE itemDataValues SET value='Locally edited title' WHERE valueID=100")
        let report = try runImport()
        XCTAssertEqual(report.updated.count, 1)
        XCTAssertEqual(try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" }?.title,
                       "Locally edited title")
    }

    // #3 修訂（實庫反證 personal-only 預設）：預設拉全部 libraries，指定時才限縮
    func testAllLibrariesImportedByDefault() throws {
        try fixture.db.execute("INSERT INTO items VALUES (30,1,'KEYGROUP',2,5)")   // libraryID=5（group）
        try fixture.addField(item: 30, field: 1, value: "Group library paper", valueID: 130)
        let report = try runImport()
        XCTAssertEqual(report.created.count, 3)   // personal 兩筆 + group 一筆
        let group = try store.load().entries.first { $0.provenance?.zoteroKey == "KEYGROUP" }
        XCTAssertEqual(group?.provenance?.libraryID, 5)
    }

    func testExplicitLibraryIDRestricts() throws {
        try fixture.db.execute("INSERT INTO items VALUES (30,1,'KEYGROUP',2,5)")
        try fixture.addField(item: 30, field: 1, value: "Group library paper", valueID: 130)
        let report = try ZoteroImporter(store: store).run(
            zoteroDB: fixture.dbURL, libraryID: 1, now: Date(timeIntervalSince1970: 1_753_000_000))
        XCTAssertEqual(report.created.count, 2)   // 只有 personal
        XCTAssertNil(try store.load().entries.first { $0.provenance?.zoteroKey == "KEYGROUP" })
    }

    // 部分 import 的 orphan scoping：其他 library 的 entries 絕不被誤標
    func testPartialImportDoesNotOrphanOtherLibraries() throws {
        try fixture.db.execute("INSERT INTO items VALUES (30,1,'KEYGROUP',2,5)")
        try fixture.addField(item: 30, field: 1, value: "Group library paper", valueID: 130)
        _ = try runImport()   // 全庫：3 entries 入庫（含 group）
        // 只 import personal → group entry 不在視野內，不得 orphan
        let partial = try ZoteroImporter(store: store).run(
            zoteroDB: fixture.dbURL, libraryID: 1, now: Date(timeIntervalSince1970: 1_753_100_000))
        XCTAssertEqual(partial.orphaned, [])
        let group = try store.load().entries.first { $0.provenance?.zoteroKey == "KEYGROUP" }
        XCTAssertNil(group?.provenance?.orphanedAt)
    }

    // 同 bare key 跨 library：複合身分不互撞
    func testSameKeyAcrossLibrariesCoexists() throws {
        try fixture.db.execute("INSERT INTO items VALUES (31,1,'KEYART01',9,5)")   // group 撞 personal 的 key
        try fixture.addField(item: 31, field: 1, value: "Different paper same key", valueID: 131)
        let report = try runImport()
        XCTAssertEqual(report.created.count, 3)
        let both = try store.load().entries.filter { $0.provenance?.zoteroKey == "KEYART01" }
        XCTAssertEqual(both.count, 2)
        XCTAssertEqual(Set(both.compactMap { $0.provenance?.libraryID }), [1, 5])
    }

    func testProvenanceRecordsLibraryID() throws {
        _ = try runImport()
        let article = try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" }!
        XCTAssertEqual(article.provenance?.libraryID, 1)
        XCTAssertNotNil(article.provenance?.zoteroHash)
    }

    func testLinkedAttachmentsAreCountedNotSilent() throws {
        try fixture.db.execute("INSERT INTO items VALUES (21,3,'KEYATT02',5,1)")
        try fixture.db.execute("INSERT INTO itemAttachments VALUES (21,10,'attachments:linked.pdf','application/pdf')")
        let report = try runImport()
        XCTAssertEqual(report.skippedLinkedAttachments, 1)
    }
}

extension ZoteroImportTests {
    // Logic/DA CONFIRMED：scoped import 不得認領「已知屬於其他 library」的裸 key entry
    func testScopedImportDoesNotClaimAmbiguousLegacyKey() throws {
        // group library 有同 bare key 的 item，且已 backfill（composite 已知屬 lib 5）
        try fixture.db.execute("INSERT INTO items VALUES (31,1,'KEYART01',9,5)")
        try fixture.addField(item: 31, field: 1, value: "Group paper same key", valueID: 131)
        _ = try runImport()   // 全量：兩個 KEYART01（lib1、lib5）各自入庫

        // 模擬 legacy：把 lib1 的那筆抹掉 library_id/hash（回到裸 key 狀態）
        let store2 = LibraryStore(root: store.root)
        var legacy = try store2.load().entries.first {
            $0.provenance?.zoteroKey == "KEYART01" && $0.provenance?.libraryID == 1
        }!
        legacy.provenance?.libraryID = nil
        legacy.provenance?.zoteroHash = nil
        try store2.writeEntry(legacy)

        // scoped import lib 5：bare key KEYART01 對 store 是歧義（lib5 composite 已存在）
        // → legacy 檔絕不能被 lib5 的 item 認領改寫
        let report = try ZoteroImporter(store: store).run(
            zoteroDB: fixture.dbURL, libraryID: 5, now: Date(timeIntervalSince1970: 1_753_200_000))
        XCTAssertEqual(report.created, [])
        let after = try store.load().entries.first { $0.id == legacy.id }!
        XCTAssertNil(after.provenance?.libraryID)   // legacy 檔原封不動
    }
}

final class DateNormalizerBoundaryTests: XCTestCase {
    // Logic MEDIUM：非 dash 分隔（1989/05/15）不得靜默截成年份——應回 nil 進 report
    func testSlashSeparatedDateIsUnparseable() {
        XCTAssertNil(DateNormalizer.normalize("1989/05/15"))
    }
    // Codex MEDIUM：超界月/日不得保留（2025-99 非法）
    func testOutOfRangeMonthDayUnparseable() {
        XCTAssertNil(DateNormalizer.normalize("2025-99-01"))
        XCTAssertNil(DateNormalizer.normalize("2025-04-99"))
    }
    func testTrailingTextAfterISOStillAccepted() {
        XCTAssertEqual(DateNormalizer.normalize("1989-00-00 1989"), "1989")   // 空白邊界 OK
    }
}

final class HashCanonicalTests: XCTestCase {
    // DA CONFIRMED（LOW-MEDIUM）：canonical 序列化不得有結構碰撞
    func testConstructedFieldCollisionResolved() {
        var a = ZoteroItem(key: "K1", version: 1, libraryID: 1, typeName: "journalArticle",
                           fields: ["title": "T", "volume": "1\nfield:number=2"],
                           authors: [], tags: [], attachmentPaths: [])
        var b = ZoteroItem(key: "K1", version: 1, libraryID: 1, typeName: "journalArticle",
                           fields: ["title": "T", "volume": "1", "issue": "2"],
                           authors: [], tags: [], attachmentPaths: [])
        _ = a; _ = b
        XCTAssertNotEqual(ZoteroMapping.mappingHash(of: a), ZoteroMapping.mappingHash(of: b))
    }
}

// #13：Zotero 脫鉤的核心約束——pull update 不得動 akashic.libraries
extension ZoteroImportTests {
    func testPullUpdatePreservesLibraries() throws {
        _ = try runImport()
        var e = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        e.akashic.libraries = ["sinica"]
        try store.writeEntry(e)
        try fixture.db.execute("UPDATE items SET version=99 WHERE itemID=10")
        _ = try runImport()   // update wave
        let after = try store.load().entries.first { $0.citekey == "cheng2025identifiability" }!
        XCTAssertEqual(after.akashic.libraries, ["sinica"], "pull update 不得清掉 membership")
    }
}

// R6（#23 verify R5）：import 主線對 v1.3 encode 可失敗性的收容
extension ZoteroImportTests {
    /// F1：帶未知欄位的既有 entry + 次秒 `now`（真實 pull 的預設 `Date()`）——
    /// R5 的 identity canary 在此必拒寫並把整趟 import 打斷。
    func testUpdateWithUnknownFieldsAndSubSecondNowSucceeds() throws {
        let existing = """
        id: 7C1F6C2E-0000-0000-0000-00000000AA02
        citekey: prior1
        type: article
        title: Old
        provenance:
          zotero_key: KEYART01
          zotero_version: 1
          library_id: 1
        rating: 5
        """
        try (existing + "\n").write(
            to: store.entriesDir.appendingPathComponent("prior1.yaml"),
            atomically: true, encoding: .utf8)
        let report = try ZoteroImporter(store: store).run(
            zoteroDB: fixture.dbURL,
            now: Date(timeIntervalSince1970: 1_753_000_000.987))   // 次秒精度
        XCTAssertTrue(report.updated.contains("prior1"), "\(report)")
        XCTAssertTrue(report.writeFailed.isEmpty, "\(report.writeFailed)")
        let after = try store.load().entries.first { $0.citekey == "prior1" }!
        XCTAssertEqual(after.unknownFields.map(\.key), ["rating"], "未知欄位保留")
        XCTAssertEqual(after.provenance?.importedAt,
                       Date(timeIntervalSince1970: 1_753_000_000), "秒精度落地")
    }

    /// F7（M9）：單筆寫入失敗（encode 平移不變式 fail-closed）記入 writeFailed、
    /// 不中斷整趟 import——其他 item 照常入庫。
    func testWriteFailureContainedPerItem() throws {
        let frozen = """
        id: 7C1F6C2E-0000-0000-0000-00000000AA01
        citekey: frozen1
        type: article
        title: T
        provenance:
          zotero_key: KEYART01
          zotero_version: 1
          library_id: 1
        akashic:
            tags:
            - keep
            weird: [a,
          b]
        """
        try (frozen + "\n").write(
            to: store.entriesDir.appendingPathComponent("frozen1.yaml"),
            atomically: true, encoding: .utf8)
        let report = try runImport()   // 不得 throw
        XCTAssertNotNil(report.writeFailed["frozen1"], "\(report)")
        XCTAssertTrue(String(describing: report.writeFailed["frozen1"]!).contains("平移"))
        XCTAssertFalse(report.updated.contains("frozen1"))
        XCTAssertFalse(report.created.isEmpty, "其他 item 照常入庫")
        // 磁碟上的凍結檔原封不動（fail-closed 不毀檔）
        let onDisk = try String(
            contentsOf: store.entriesDir.appendingPathComponent("frozen1.yaml"),
            encoding: .utf8)
        XCTAssertTrue(onDisk.contains("weird: [a,"))
    }
}
