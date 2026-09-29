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

// MARK: - #610：同一個來源被多筆 entry 宣稱

extension ZoteroSourceRoutingTests {
    private func article() throws -> Entry {
        try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" }!
    }

    /// 同一筆的複本：新 id、新 citekey，來源原樣。
    @discardableResult
    private func writeTwin(of entry: Entry, citekey: String) throws -> Entry {
        var twin = entry
        twin.id = UUID()
        twin.citekey = citekey
        try store.writeEntry(twin)
        return twin
    }

    /// 兩筆 entry 的主來源是同一個 `(library_id, zotero_key)`：先前以字典收索引，後讀到的覆蓋先讀到的，
    /// 路由安靜地只更新其中一筆。現在兩筆都不更新、報出來。
    func testSourceClaimedAsPrimaryByTwoEntriesIsNotRoutedToEither() throws {
        _ = try runImport()
        let a = try article()
        let b = try writeTwin(of: a, citekey: "cheng2025twin")
        try fixture.db.execute("UPDATE items SET version = 6 WHERE itemID = 10")
        try fixture.db.execute("UPDATE itemDataValues SET value = 'Edited upstream' WHERE valueID = 100")
        let report = try runImport(at: 1_753_100_000)
        let all = try store.load().entries
        XCTAssertEqual(all.first { $0.id == a.id }?.title, a.title, "不得猜是哪一筆：\(report.updated)")
        XCTAssertEqual(all.first { $0.id == b.id }?.title, b.title)
        XCTAssertEqual(report.ambiguousSourceClaims, ["1:KEYART01": [a.citekey, b.citekey].sorted()])
        XCTAssertEqual(report.created, [], "被多筆宣稱的來源不得再建第三筆")
        XCTAssertEqual(all.count, 4)
    }

    /// 一筆的主來源、另一筆的附加來源是同一個來源：先前主來源那筆安靜勝出。
    func testSourceClaimedAsPrimaryAndSecondaryIsNotRoutedToEither() throws {
        _ = try runImport()
        let all = try store.load().entries
        var personal = all.first { $0.provenance?.zoteroKey == "KEYART01" }!
        let group = all.first { $0.provenance?.zoteroKey == "KEYGRP01" }!
        personal.additionalProvenance = [group.provenance!]
        try store.writeEntry(personal)
        try fixture.db.execute("UPDATE items SET version = 12 WHERE itemID = 31")
        try fixture.db.execute("UPDATE itemDataValues SET value = 'Group edited title' WHERE valueID = 131")
        let report = try runImport(at: 1_753_100_000)
        let after = try store.load().entries
        XCTAssertEqual(after.first { $0.id == group.id }?.title, group.title, "\(report.updated)")
        XCTAssertEqual(after.first { $0.id == personal.id }?.additionalProvenance.first?.zoteroVersion, 9)
        XCTAssertEqual(report.ambiguousSourceClaims, ["5:KEYGRP01": [personal.citekey, group.citekey].sorted()])
    }

    /// 兩筆沒記 library_id 的舊檔宣稱同一個裸 key：先前後讀到的那筆被認領、改寫。
    func testTwoLegacyEntriesWithTheSameBareKeyAreNotClaimed() throws {
        _ = try runImport()
        var a = try article()
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        try store.writeEntry(a)
        let b = try writeTwin(of: a, citekey: "cheng2025legacytwin")
        let report = try runImport(at: 1_753_100_000)
        let all = try store.load().entries
        XCTAssertNil(all.first { $0.id == a.id }?.provenance?.libraryID, "\(report.updated)")
        XCTAssertNil(all.first { $0.id == b.id }?.provenance?.libraryID)
        XCTAssertEqual(report.ambiguousSourceClaims, ["?:KEYART01": [a.citekey, b.citekey].sorted()])
        XCTAssertEqual(report.created, [])
    }

    /// doctor／validate／App 都讀 `crossRecordIssues`：多筆宣稱是一則 warning（載入時偵測，不等匯入）。
    func testMultiClaimIsACrossRecordWarning() throws {
        _ = try runImport()
        let a = try article()
        let b = try writeTwin(of: a, citekey: "cheng2025twin")
        let issues = store.health(from: try store.load()).crossRecordIssues
            .filter { $0.message.contains("1:KEYART01") }
        XCTAssertEqual(issues.count, 1, "\(issues.map(\.message))")
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertTrue(issues.first?.message.contains("被 2 筆 entry 宣稱") ?? false, issues.first?.message ?? "")
        XCTAssertTrue(issues.first?.message.contains(b.citekey) ?? false)
        XCTAssertTrue(issues.first?.message.contains("remove-zotero-source") == true
                      && issues.first?.message.contains("定位鍵 1:KEYART01") == true,
                      "記錯了的出路是移除面，並給出可貼上的定位鍵（#680）：\(issues.first?.message ?? "")")
    }

    /// 同一筆 entry 的主來源與附加來源恰好是同一個來源：那不是多筆宣稱，照主來源更新（負控：
    /// 宣稱者要以 entry 去重，否則同一筆會被數兩次）。
    func testSameEntryClaimingASourceTwiceIsNotAmbiguous() throws {
        _ = try runImport()
        var a = try article()
        a.additionalProvenance = [a.provenance!]
        try store.writeEntry(a)
        XCTAssertFalse(store.health(from: try store.load()).crossRecordIssues
            .contains { $0.message.contains("KEYART01") })
        try fixture.db.execute("UPDATE items SET version = 6 WHERE itemID = 10")
        try fixture.db.execute("UPDATE itemDataValues SET value = 'Edited upstream' WHERE valueID = 100")
        let report = try runImport(at: 1_753_100_000)
        XCTAssertEqual(report.ambiguousSourceClaims, [:])
        XCTAssertEqual(try store.load().entries.first { $0.id == a.id }?.title, "Edited upstream")
    }
}

// MARK: - #610 R1 verify：legacy 的重複也是宣稱、宣稱者的定義只有一份

extension ZoteroSourceRoutingTests {
    /// 舊佈局的複本（#631 的兩份並存）：同 id、同 citekey——`load()` 會把同一筆讀到兩次。
    private func writeLegacyCopy(of entry: Entry) throws {
        let dir = store.root.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try EntryYAML.encode(entry).write(
            to: dir.appendingPathComponent("\(entry.citekey).yaml"), atomically: true, encoding: .utf8)
    }

    private func crossRecordClaimWarnings() throws -> [ValidationIssue] {
        store.health(from: try store.load()).crossRecordIssues.filter { $0.message.contains("宣稱") }
    }

    /// Codex MEDIUM：兩筆 legacy 同裸 key，而**另一個 library 也持有同一個裸 key**。先前「其他 library 已持有」的條件把
    /// legacy 的數量檢查整個跳過，條目照走「建新 entry」，而且報告裡沒有歧義——#610 的契約在這個組合失效。
    /// 現在先問「有幾筆 legacy 宣稱」，再問「其他 library 是否持有」。
    func testTwoLegacyTwinsAreReportedEvenWhenAnotherLibraryHoldsTheKey() throws {
        _ = try runImport()
        var a = try article()
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        try store.writeEntry(a)
        let b = try writeTwin(of: a, citekey: "cheng2025legacytwin")
        // 另一個 library 的一筆以 composite 持有同一個裸 key
        var other = Entry(id: UUID(), citekey: "other2020holder", type: .periodicalArticle, title: "Held in lib 5")
        other.provenance = Provenance(zoteroKey: "KEYART01", zoteroVersion: 1, libraryID: 5)
        try store.writeEntry(other)
        let report = try runImport(at: 1_753_100_000)
        let all = try store.load().entries
        XCTAssertEqual(report.ambiguousSourceClaims["?:KEYART01"], [a.citekey, b.citekey].sorted(), "\(report.ambiguousSourceClaims)")
        XCTAssertFalse(all.contains { $0.provenance?.libraryID == 1 && $0.provenance?.zoteroKey == "KEYART01" },
                       "歧義的條目不得新建：\(report.created)")
        XCTAssertNil(all.first { $0.id == a.id }?.provenance?.libraryID, "兩筆 legacy 都不得被認領")
        XCTAssertNil(all.first { $0.id == b.id }?.provenance?.libraryID)
    }

    /// 只有一筆 legacy、而另一個 library 持有同一個裸 key：照 #607 的規則不認領、條目走建新——不是歧義，報告不列。
    func testSingleLegacyWithAnotherLibraryHoldingTheKeyIsNotAmbiguous() throws {
        _ = try runImport()
        var a = try article()
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        try store.writeEntry(a)
        var other = Entry(id: UUID(), citekey: "other2020holder", type: .periodicalArticle, title: "Held in lib 5")
        other.provenance = Provenance(zoteroKey: "KEYART01", zoteroVersion: 1, libraryID: 5)
        try store.writeEntry(other)
        let report = try runImport(at: 1_753_100_000)
        XCTAssertEqual(report.ambiguousSourceClaims, [:])
        XCTAssertNil(try store.load().entries.first { $0.id == a.id }?.provenance?.libraryID, "legacy 檔歸屬不明，不認領")
    }

    /// 宣稱者的定義只有一份：兩筆沒記 library_id 的舊檔宣稱同一個裸 key，載入時就是一則 warning（不必等匯入），
    /// 而且處置的兩條出路都說對。
    func testTwoLegacyTwinsAreACrossRecordWarning() throws {
        _ = try runImport()
        var a = try article()
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        try store.writeEntry(a)
        let b = try writeTwin(of: a, citekey: "cheng2025legacytwin")
        let issues = try crossRecordClaimWarnings().filter { $0.message.contains("KEYART01") }
        XCTAssertEqual(issues.count, 1, "\(issues.map(\.message))")
        let message = try XCTUnwrap(issues.first?.message)
        XCTAssertEqual(issues.first?.severity, .warning)
        XCTAssertTrue(message.contains("被 2 筆 entry 宣稱"), message)
        XCTAssertTrue(message.contains(a.citekey) && message.contains(b.citekey), message)
        XCTAssertTrue(message.contains("沒記 library_id 的 Zotero 來源（裸 key「KEYART01」）"), "要說出這是沒記 library_id 的來源：\(message)")
        XCTAssertTrue(message.contains("record-divergence") && message.contains("resolve-divergence"), "合併的出路：\(message)")
        XCTAssertTrue(message.contains("remove-zotero-source") && message.contains("定位鍵 ?:KEYART01"),
                      "記錯了的出路：移除面與它的定位鍵（#680）：\(message)")
        XCTAssertTrue(message.contains("library_id") && message.contains("YAML"), "另一條出路：補上真正的 library_id：\(message)")
    }

    /// 邊界（照舊）：一筆 legacy 與某個 library 的來源同裸 key 不算多筆宣稱——歸屬不明不是確定的重複。
    func testLegacyAndCompositeSharingABareKeyIsNotAMultiClaim() throws {
        _ = try runImport()
        var a = try article()
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        try store.writeEntry(a)
        var other = Entry(id: UUID(), citekey: "other2020holder", type: .periodicalArticle, title: "Held in lib 5")
        other.provenance = Provenance(zoteroKey: "KEYART01", zoteroVersion: 1, libraryID: 5)
        try store.writeEntry(other)
        XCTAssertEqual(try crossRecordClaimWarnings().filter { $0.message.contains("KEYART01") }.count, 0)
    }

    /// 宣稱者的單一定義：主來源與附加來源以 `<library_id>:<zotero_key>`、沒記 library_id 的主來源以 `?:<zotero_key>`；
    /// 沒記 library_id 的**附加來源**不算（匯入端對回不了它，合併閘也不讓它進來）。
    func testClaimantsBucketsALegacyPrimaryByBareKey() {
        func entry(_ citekey: String, primary: Provenance?, additional: [Provenance] = []) -> Entry {
            var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: citekey)
            e.provenance = primary
            e.additionalProvenance = additional
            return e
        }
        let l1 = entry("l1", primary: Provenance(zoteroKey: "K", zoteroVersion: 1))
        let l2 = entry("l2", primary: Provenance(zoteroKey: "K", zoteroVersion: 1))
        let c = entry("c", primary: Provenance(zoteroKey: "K", zoteroVersion: 1, libraryID: 1),
                      additional: [Provenance(zoteroKey: "X", zoteroVersion: 1)])   // 沒記 library_id 的附加來源
        let claims = ZoteroSourceClaims.claimants([l1, l2, c])
        XCTAssertEqual(claims["?:K"], [l1.id, l2.id])
        XCTAssertEqual(claims["1:K"], [c.id])
        XCTAssertNil(claims["?:X"], "沒記 library_id 的附加來源不算")
        XCTAssertEqual(ZoteroSourceClaims.key(libraryID: nil, zoteroKey: "K"), "?:K")
        XCTAssertEqual(ZoteroSourceClaims.key(libraryID: 5, zoteroKey: "K"), "5:K")
    }

    /// LOW（regression／DA）：同一筆 entry 被 load 讀到兩次（#631 的兩份並存、同一個 id）不是它自己的攣生——
    /// 宣稱者以 entry id 去重。先前 validate 印「被 2 筆 entry 宣稱（x, x）」並建議把一筆 entry 和它自己合併。
    func testAnEntryLoadedTwiceIsNotItsOwnTwin() throws {
        _ = try runImport()
        let a = try article()
        try writeLegacyCopy(of: a)
        let load = try store.load()
        XCTAssertEqual(load.entries.filter { $0.id == a.id }.count, 2, "前提：同一筆讀到兩次")
        XCTAssertEqual(ZoteroSourceClaims.claimants(load.entries)["1:KEYART01"], [a.id])
        XCTAssertEqual(try crossRecordClaimWarnings().filter { $0.message.contains("KEYART01") }.count, 0)
        let report = try runImport(at: 1_753_100_000)
        XCTAssertEqual(report.ambiguousSourceClaims, [:], "同一筆的兩份複本不是多筆宣稱")
    }

    /// 同上，legacy 那一桶：同一筆 legacy 讀到兩次不算兩筆——匯入端照常認領它，不報歧義。
    func testALegacyEntryLoadedTwiceIsNotAmbiguous() throws {
        _ = try runImport()
        var a = try article()
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        try store.writeEntry(a)
        try writeLegacyCopy(of: a)
        XCTAssertEqual(ZoteroSourceClaims.claimants(try store.load().entries)["?:KEYART01"], [a.id])
        let report = try runImport(at: 1_753_100_000)
        XCTAssertEqual(report.ambiguousSourceClaims, [:])
    }

    /// 警告裡每一筆 entry 只列一次：一筆讀到兩次的 entry 加上真的攣生，名單是兩個 citekey，不是三個。
    func testWarningNamesEachEntryOnceWhenOneOfThemIsLoadedTwice() throws {
        _ = try runImport()
        let a = try article()
        let b = try writeTwin(of: a, citekey: "cheng2025twin")
        try writeLegacyCopy(of: a)
        let issues = try crossRecordClaimWarnings().filter { $0.message.contains("KEYART01") }
        XCTAssertEqual(issues.count, 1, "\(issues.map(\.message))")
        let message = try XCTUnwrap(issues.first?.message)
        XCTAssertTrue(message.contains("被 2 筆 entry 宣稱"), message)
        XCTAssertEqual(message.components(separatedBy: a.citekey).count - 1, 1, "\(a.citekey) 只列一次：\(message)")
        XCTAssertTrue(message.contains(b.citekey), message)
    }

    /// 警告說的合併出路是真的：兩筆都沒記 library_id 的舊檔（`isSameSource` 把 nil 視為同一 library）走 `record-divergence`
    /// ＋`resolve-divergence` 併成一筆，來源併成一份、警告消失。訊息與文件都寫了這條出路，這裡釘住它做得到。
    func testTwoLegacyTwinsCanBeMergedThroughTheDivergencePath() throws {
        _ = try runImport()
        var a = try article()
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        try store.writeEntry(a)
        let b = try writeTwin(of: a, citekey: "cheng2025legacytwin")
        try StoreVersion.write(root: store.root, format: StoreVersion.supported)
        GitFixture.initRepo(store.root)
        let d = try store.recordDivergence(
            question: "是否同一篇", candidates: [(a.citekey, .work), (b.citekey, .work)], judgement: nil, restsOn: [])
        GitFixture.commitAll(store.root, message: "seed")
        XCTAssertEqual(try crossRecordClaimWarnings().filter { $0.message.contains("KEYART01") }.count, 1, "前提：合併之前有警告")
        _ = try store.resolveDivergence(id: d.id, survivor: a.citekey)
        let after = try store.load().entries.filter { $0.provenance?.zoteroKey == "KEYART01" }
        XCTAssertEqual(after.map(\.citekey), [a.citekey], "被併者消失、倖存者留下")
        XCTAssertEqual(try crossRecordClaimWarnings().filter { $0.message.contains("KEYART01") }.count, 0, "警告隨合併消失")
    }
}

// MARK: - #682：多筆宣稱的來源，Zotero 端復原之後 orphan 標記照常清除

extension ZoteroSourceRoutingTests {
    private func firstArticle() throws -> Entry {
        try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" }!
    }

    @discardableResult
    private func twin(of entry: Entry, citekey: String) throws -> Entry {
        var copy = entry
        copy.id = UUID()
        copy.citekey = citekey
        try store.writeEntry(copy)
        return copy
    }

    private func entry(_ id: UUID) throws -> Entry {
        try XCTUnwrap(store.load().entries.first { $0.id == id })
    }

    /// orphan 標記說的是「Zotero 那個 item 在不在」，判它不需要先判定哪一筆是正主。先前多筆宣稱的來源在路由前就被略過，連
    /// 標記的清除一起略過：Zotero 端復原之後兩筆的 `orphanedAt` 都還在，App 的 Orphans 頁把它們列成「已刪除」，
    /// 而那一頁的動作是破壞性的（移到垃圾桶、脫鉤）。現在書目欄位與 version／hash 照舊不動，標記逐筆清掉、報告仍列歧義。
    func testRestoredItemClearsOrphanMarksOnEveryClaimantWhileTheSourceStaysAmbiguous() throws {
        _ = try runImport()
        let a = try firstArticle()
        let b = try twin(of: a, citekey: "cheng2025twin")

        // 反方向（現況，pin 住）：Zotero 端刪了 item，兩筆宣稱者都被標 orphan——偵測迴圈逐筆看每一筆的來源，不看宣稱者的數量
        try fixture.db.execute("INSERT INTO deletedItems VALUES (10)")
        let gone = try runImport(at: 1_753_100_000)
        XCTAssertEqual(gone.orphaned, [a.citekey, b.citekey].sorted(), "刪除時每一個宣稱者都要被標")
        XCTAssertNotNil(try entry(a.id).provenance?.orphanedAt)
        XCTAssertNotNil(try entry(b.id).provenance?.orphanedAt)

        // 復原，而且上游在這段期間改過（version、標題）——被多筆宣稱的來源不更新書目欄位
        try fixture.db.execute("DELETE FROM deletedItems WHERE itemID = 10")
        try fixture.db.execute("UPDATE items SET version = 6 WHERE itemID = 10")
        try fixture.db.execute("UPDATE itemDataValues SET value = 'Edited upstream' WHERE valueID = 100")
        let back = try runImport(at: 1_753_200_000)

        let afterA = try entry(a.id), afterB = try entry(b.id)
        XCTAssertNil(afterA.provenance?.orphanedAt, "a 的 orphan 標記要清")
        XCTAssertNil(afterB.provenance?.orphanedAt, "b 的 orphan 標記要清")
        XCTAssertEqual(afterA.title, a.title, "書目欄位不動")
        XCTAssertEqual(afterB.title, b.title)
        XCTAssertEqual(afterA.provenance?.zoteroVersion, a.provenance?.zoteroVersion, "version 不動：那是更新，不是清標記")
        XCTAssertEqual(afterB.provenance?.zoteroHash, b.provenance?.zoteroHash)
        XCTAssertEqual(back.ambiguousSourceClaims, ["1:KEYART01": [a.citekey, b.citekey].sorted()], "歧義照舊報")
        XCTAssertEqual(back.orphanCleared, [a.citekey, b.citekey].sorted(), "清掉的兩筆要列在報告")
        XCTAssertEqual(back.updated, [], "清標記不是更新")
        XCTAssertEqual(back.created, [], "不得為被多筆宣稱的來源再建一筆")
        // 標記清掉之後，Orphans 清單（`zoteroLinkState == .orphaned`）不再有這兩筆
        XCTAssertEqual(afterA.zoteroLinkState, .intact)
        XCTAssertEqual(afterB.zoteroLinkState, .intact)
    }

    /// 宣稱者的角色不必相同：一筆是主來源、另一筆是附加來源，兩邊各自的標記都清（附加來源的清除進 `secondarySourceRestored`，
    /// 與 #605 的既有分工同一條）。
    func testRestoredItemClearsTheMarkOnAPrimaryAndOnAnAdditionalClaimant() throws {
        _ = try runImport()
        let all = try store.load().entries
        var personal = all.first { $0.provenance?.zoteroKey == "KEYART01" }!
        let group = all.first { $0.provenance?.zoteroKey == "KEYGRP01" }!
        personal.additionalProvenance = [group.provenance!]
        try store.writeEntry(personal)

        try fixture.db.execute("INSERT INTO deletedItems VALUES (31)")
        let gone = try runImport(at: 1_753_100_000)
        XCTAssertEqual(gone.orphaned, [group.citekey], "主來源那筆整筆 orphan")
        XCTAssertEqual(gone.secondarySourceOrphaned, [personal.citekey], "附加來源那筆只標那個來源")

        try fixture.db.execute("DELETE FROM deletedItems WHERE itemID = 31")
        try fixture.db.execute("UPDATE items SET version = 12 WHERE itemID = 31")
        try fixture.db.execute("UPDATE itemDataValues SET value = 'Group edited title' WHERE valueID = 131")
        let back = try runImport(at: 1_753_200_000)

        XCTAssertNil(try entry(group.id).provenance?.orphanedAt)
        XCTAssertNil(try entry(personal.id).additionalProvenance.first?.orphanedAt)
        XCTAssertEqual(try entry(group.id).title, group.title, "書目欄位不動")
        XCTAssertEqual(try entry(personal.id).additionalProvenance.first?.zoteroVersion, group.provenance?.zoteroVersion, "附加來源的 version 也不動")
        XCTAssertEqual(back.ambiguousSourceClaims, ["5:KEYGRP01": [personal.citekey, group.citekey].sorted()])
        XCTAssertEqual(back.orphanCleared, [group.citekey])
        XCTAssertEqual(back.secondarySourceRestored, [personal.citekey])
        XCTAssertEqual(back.updated, [])
    }

    /// 沒記 `library_id` 的舊檔那一桶（`?:<key>`）同理：兩筆舊檔宣稱同一個裸 key、都帶著 orphan 標記，全庫匯入時這個裸 key 的條目在，
    /// 標記清掉、欄位不動、歧義照舊報。
    func testRestoredItemClearsOrphanMarksOnTwoLegacyClaimants() throws {
        _ = try runImport()
        var a = try firstArticle()
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        a.provenance?.orphanedAt = Date(timeIntervalSince1970: 1_752_000_000)
        try store.writeEntry(a)
        let b = try twin(of: a, citekey: "cheng2025legacytwin")

        let report = try runImport(at: 1_753_100_000)

        XCTAssertNil(try entry(a.id).provenance?.orphanedAt)
        XCTAssertNil(try entry(b.id).provenance?.orphanedAt)
        XCTAssertNil(try entry(a.id).provenance?.libraryID, "舊檔照 #607 不認領：library_id 不補")
        XCTAssertEqual(try entry(a.id).title, a.title)
        XCTAssertEqual(report.ambiguousSourceClaims, ["?:KEYART01": [a.citekey, b.citekey].sorted()])
        XCTAssertEqual(report.orphanCleared, [a.citekey, b.citekey].sorted())
        XCTAssertEqual(report.updated, [])
        XCTAssertEqual(report.created, [])
    }

    /// 舊檔那一桶的清除條件與單一舊檔認領同一條：別的 library 也持有同一個裸 key 時歸屬不明——條目在不在不能證明「這些舊檔的那個
    /// item 在」，所以標記留著（保守側；清錯的代價是 Orphans 頁少列一筆真的已刪除的）。歧義照舊報。
    func testLegacyClaimantsKeepTheirMarksWhenAnotherLibraryHoldsTheBareKey() throws {
        _ = try runImport()
        var a = try firstArticle()
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        a.provenance?.orphanedAt = Date(timeIntervalSince1970: 1_752_000_000)
        try store.writeEntry(a)
        let b = try twin(of: a, citekey: "cheng2025legacytwin")
        var other = Entry(id: UUID(), citekey: "other2020holder", type: .periodicalArticle, title: "Held in lib 5")
        other.provenance = Provenance(zoteroKey: "KEYART01", zoteroVersion: 1, libraryID: 5)
        try store.writeEntry(other)

        let report = try runImport(at: 1_753_100_000)

        XCTAssertNotNil(try entry(a.id).provenance?.orphanedAt, "歸屬不明，標記留著")
        XCTAssertNotNil(try entry(b.id).provenance?.orphanedAt)
        XCTAssertEqual(report.ambiguousSourceClaims["?:KEYART01"], [a.citekey, b.citekey].sorted())
        XCTAssertEqual(report.orphanCleared, [])
    }

    /// scoped import（`libraryID` 給定）下同樣清標記：清標記走的是與全量匯入同一條路（b13f R1 verify 第 15 列：先前只有全量匯入的測試）。
    func testScopedImportClearsOrphanMarksOnEveryClaimantToo() throws {
        _ = try runImport()
        var a = try firstArticle()
        a.provenance?.orphanedAt = Date(timeIntervalSince1970: 1_752_000_000)
        try store.writeEntry(a)
        let b = try twin(of: a, citekey: "cheng2025twin")   // 帶著同一個 orphan 標記

        let report = try ZoteroImporter(store: store).run(zoteroDB: fixture.dbURL, libraryID: 1, now: Date(timeIntervalSince1970: 1_753_100_000))

        XCTAssertNil(try entry(a.id).provenance?.orphanedAt)
        XCTAssertNil(try entry(b.id).provenance?.orphanedAt)
        XCTAssertEqual(report.ambiguousSourceClaims, ["1:KEYART01": [a.citekey, b.citekey].sorted()])
        XCTAssertEqual(report.orphanCleared, [a.citekey, b.citekey].sorted())
        XCTAssertEqual(report.updated, [])
        XCTAssertEqual(report.created, [])
    }

    /// 沒有標記就什麼都不寫：多筆宣稱的來源、兩筆都沒有 orphan 標記——檔案位元組不動（清標記不得順手改寫檔案）。
    func testAmbiguousSourceWithoutOrphanMarksWritesNothing() throws {
        _ = try runImport()
        let a = try firstArticle()
        let b = try twin(of: a, citekey: "cheng2025twin")
        let before = (try Data(contentsOf: store.entityURL(id: a.id)), try Data(contentsOf: store.entityURL(id: b.id)))
        try fixture.db.execute("UPDATE items SET version = 6 WHERE itemID = 10")
        let report = try runImport(at: 1_753_100_000)
        XCTAssertEqual(try Data(contentsOf: store.entityURL(id: a.id)), before.0)
        XCTAssertEqual(try Data(contentsOf: store.entityURL(id: b.id)), before.1)
        XCTAssertEqual(report.orphanCleared, [])
        XCTAssertEqual(report.secondarySourceRestored, [])
    }
}
