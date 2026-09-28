import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicSQLite
@testable import AkashicZoteroImport

/// 再匯入時，一個 Zotero 條目要對回哪一筆 entry（#607、#610）。
///
/// 比對的優先順序（#607）：
/// 1. 主來源的 `(library_id, zotero_key)` 完全相同
/// 2. 附加來源的 `(library_id, zotero_key)` 完全相同
/// 3. 沒記 `library_id` 的舊檔（legacy）以裸 key 比對——只在**沒有任何其他 library 的來源**
///    （主來源或附加來源）持有同一個裸 key 時才認領
///
/// 2 排在 3 之前的理由：附加來源的比對是完全相同的身分，legacy 是一個歸屬不明的猜測。
final class ZoteroSourceRoutingTests: XCTestCase {
    var dir: URL!
    var store: LibraryStore!
    var fixture: ZoteroFixture!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-zroute-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        store = LibraryStore(root: dir.appendingPathComponent("library"))
        try store.ensureLayout()
        fixture = try ZoteroFixture(dir: dir)
        try fixture.seedStandard()
        // 群組 library（lib 5）的同一作品
        try fixture.db.execute("INSERT INTO items VALUES (31,1,'KEYGRP01',9,5)")
        try fixture.addField(item: 31, field: 1, value: "Identifiability of polychoric models (group copy)", valueID: 131)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private func runImport(at t: TimeInterval = 1_753_000_000) throws -> ImportReport {
        try ZoteroImporter(store: store).run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: t))
    }

    /// 個人那份帶著群組那份的來源當附加來源、群組那筆已刪（#605 合併後的形狀）。
    @discardableResult
    private func seedMergedTwin() throws -> Entry {
        _ = try runImport()
        let all = try store.load().entries
        var personal = all.first { $0.provenance?.zoteroKey == "KEYART01" }!
        let group = all.first { $0.provenance?.zoteroKey == "KEYGRP01" }!
        personal.additionalProvenance = [group.provenance!]
        try store.writeEntry(personal)
        try FileManager.default.removeItem(at: store.entityURL(id: group.id))
        return personal
    }

    /// 一筆沒記 library_id 的舊檔，宣稱裸 key `key`。
    @discardableResult
    private func writeLegacy(citekey: String, key: String, title: String) throws -> Entry {
        var legacy = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: title)
        legacy.provenance = Provenance(zoteroKey: key, zoteroVersion: 1)
        try store.writeEntry(legacy)
        return legacy
    }

    // MARK: - #607

    /// 附加來源完全相同的比對，先於 legacy 的裸 key 猜測。先前 legacy 分支排在前面，
    /// 群組條目會被一筆恰好同裸 key 的舊檔認領、改寫成 lib 5，而真正持有它的那筆
    /// 附加來源從此不再被更新——同一個來源變成兩筆 entry 宣稱。
    func testSecondarySourceMatchComesBeforeLegacyBareKey() throws {
        let merged = try seedMergedTwin()
        let legacy = try writeLegacy(citekey: "legacy2020x", key: "KEYGRP01", title: "Legacy record")
        try fixture.db.execute("UPDATE items SET version = 12 WHERE itemID = 31")
        let report = try runImport(at: 1_753_100_000)
        let all = try store.load().entries
        let afterLegacy = all.first { $0.id == legacy.id }!
        XCTAssertNil(afterLegacy.provenance?.libraryID, "legacy 檔不得被認領：\(report.updated)")
        XCTAssertEqual(afterLegacy.title, "Legacy record")
        let afterMerged = all.first { $0.id == merged.id }!
        XCTAssertEqual(afterMerged.additionalProvenance.first?.zoteroVersion, 12,
                       "群組條目要對回持有它的附加來源")
    }

    /// 「其他 library 已持有同一個裸 key」要看附加來源。先前只看主來源，於是附加來源持有的
    /// 裸 key 被當成沒有人持有，legacy 檔被另一個 library 的同 key 條目認領。
    func testLegacyClaimRefusedWhenAnotherLibraryHoldsTheKeyAsSecondary() throws {
        try seedMergedTwin()
        let legacy = try writeLegacy(citekey: "legacy2020x", key: "KEYGRP01", title: "Legacy record")
        // 群組那份刪掉；個人 library 出現一個同裸 key 的不同條目
        try fixture.db.execute("INSERT INTO deletedItems VALUES (31)")
        try fixture.db.execute("INSERT INTO items VALUES (32,1,'KEYGRP01',3,1)")
        try fixture.addField(item: 32, field: 1, value: "Another paper that happens to share the key", valueID: 132)
        _ = try runImport(at: 1_753_100_000)
        let afterLegacy = try store.load().entries.first { $0.id == legacy.id }!
        XCTAssertNil(afterLegacy.provenance?.libraryID,
                     "裸 key 已由 lib 5 的附加來源持有，legacy 檔歸屬不明，不得被 lib 1 的條目認領")
        XCTAssertEqual(afterLegacy.title, "Legacy record")
    }

    /// 沒有任何來源持有同一個裸 key 時，legacy 檔照舊被認領並補上 library_id（回歸防線）。
    func testLegacyStillClaimedWhenNobodyElseHoldsTheKey() throws {
        _ = try runImport()
        var article = try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" }!
        article.provenance?.libraryID = nil
        article.provenance?.zoteroHash = nil
        try store.writeEntry(article)
        _ = try runImport(at: 1_753_100_000)
        let after = try store.load().entries.first { $0.id == article.id }!
        XCTAssertEqual(after.provenance?.libraryID, 1)
    }
}
