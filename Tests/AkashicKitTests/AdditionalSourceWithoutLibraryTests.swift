import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicSQLite
@testable import AkashicZoteroImport
@testable import AkashicMCPKit

/// #679：沒記 `library_id` 的附加 Zotero 來源。匯入端以 `(library_id, zotero_key)` 比對附加來源，`ZoteroSourceClaims.claims(of:)` 不把
/// 這種來源算成宣稱——所以它對不回任何 Zotero 條目，再匯入時同一個條目會另建一筆 twin。decode 接受它（拒收會讓既有的檔整個被隔離），
/// 合併閘只擋合併新收這種來源，管不到手改與舊檔。`Entry.validate()` 對它報 warning，訊息說出後果與出路。
final class AdditionalSourceWithoutLibraryTests: XCTestCase {
    private func entry(additional: [Provenance], primary: Provenance? = Provenance(zoteroKey: "PRIMARY1", zoteroVersion: 1, libraryID: 1),
                        citekey: String = "cheng2025x") -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T")
        e.provenance = primary
        e.additionalProvenance = additional
        return e
    }

    private func warnings(_ e: Entry) -> [ValidationIssue] {
        e.validate().filter { $0.message.contains("附加 Zotero 來源沒記 library_id") }
    }

    /// 出聲：一則 warning、說出後果（再匯入會重造 twin）與兩條出路（補 library_id、移除那個附加來源——#680 的面），並給出移除面要的定位鍵。
    func testAnAdditionalSourceWithoutLibraryIDIsAWarningThatNamesTheConsequenceAndTheWayOut() throws {
        let issues = warnings(entry(additional: [Provenance(zoteroKey: "GROUPKEY", zoteroVersion: 3)]))
        XCTAssertEqual(issues.count, 1, "\(issues.map(\.message))")
        let issue = try XCTUnwrap(issues.first)
        XCTAssertEqual(issue.severity, .warning, "decode 不拒收，validate 出聲")
        XCTAssertTrue(issue.message.contains("?:GROUPKEY"), "要列出來源鍵（也是移除面的定位鍵）：\(issue.message)")
        XCTAssertTrue(issue.message.contains("twin") && issue.message.contains("再匯入"), "後果：\(issue.message)")
        // b13f R1 verify 第 36 列：單筆 validate 看不到別的 entry——「另建 twin」是有條件的（另一筆已宣稱那個條目時匯入路由到那一筆）
        XCTAssertTrue(issue.message.contains("若沒有別的 entry") && issue.message.contains("照常路由"), "後果是有條件的：\(issue.message)")
        XCTAssertTrue(issue.message.contains("補上") && issue.message.contains("library_id"), "出路一：補 library_id：\(issue.message)")
        XCTAssertTrue(issue.message.contains("remove-zotero-source") && issue.message.contains("remove_zotero_sources"),
                      "出路二：移除面（CLI 與 MCP 各一個名字）：\(issue.message)")
    }

    /// 不誤傷：有 library_id 的附加來源、以及沒有 library_id 的**主來源**（pre-Phase-2 舊檔，有自己的裸 key 桶與匯入路徑）都不在這一則裡。
    func testOnlyTheAdditionalShapeWithoutLibraryIDIsReported() {
        XCTAssertEqual(warnings(entry(additional: [Provenance(zoteroKey: "GROUPKEY", zoteroVersion: 3, libraryID: 5)])).count, 0)
        XCTAssertEqual(warnings(entry(additional: [], primary: Provenance(zoteroKey: "LEGACY01", zoteroVersion: 1))).count, 0,
                       "舊檔的主來源有裸 key 桶與 #607 的認領規則，不是這個形狀")
        XCTAssertEqual(warnings(entry(additional: [], primary: nil)).count, 0)
    }

    /// 一筆 entry 一則：多個沒記 library_id 的附加來源合成一則、列出至多 5 個並說出總數（讀取路徑上對未信任的 store 內容跑，不逐個各出一則）。
    func testManySourcesAreOneMessageWithABoundedList() throws {
        let extras = (0..<9).map { Provenance(zoteroKey: "KEY0000\($0)", zoteroVersion: 1) }
        let issues = warnings(entry(additional: extras))
        XCTAssertEqual(issues.count, 1)
        let message = try XCTUnwrap(issues.first?.message)
        XCTAssertTrue(message.contains("共 9 個"), message)
        XCTAssertTrue(message.contains("?:KEY00000") && message.contains("?:KEY00004"), message)
        XCTAssertFalse(message.contains("?:KEY00005"), "只列前 5 個：\(message)")
    }

    /// 來源鍵是 store 字串，經消毒才進訊息（控制字元不得原樣落在終端機）。
    func testTheSourceKeyIsSanitisedInTheMessage() throws {
        let issues = warnings(entry(additional: [Provenance(zoteroKey: "K\u{1B}[31mEY", zoteroVersion: 1)]))
        let message = try XCTUnwrap(issues.first?.message)
        XCTAssertFalse(message.contains("\u{1B}"), "ESC 不得原樣進訊息")
    }

    /// 宣稱者的定義只有一份：`sources(of:)` 列出一筆 entry 的全部來源（移除面要定位到每一個，含沒記 library_id 的附加來源），
    /// `claims(of:)` 是其中算宣稱的那些——沒記 library_id 的附加來源不算（匯入端對回不了它）。
    func testSourcesOfListsEverythingAndClaimsOfDropsTheUnclaimableAdditional() {
        let e = entry(additional: [Provenance(zoteroKey: "GROUPKEY", zoteroVersion: 3),
                                   Provenance(zoteroKey: "OTHERKEY", zoteroVersion: 3, libraryID: 5)])
        XCTAssertEqual(ZoteroSourceClaims.sources(of: e).map(\.key), ["1:PRIMARY1", "?:GROUPKEY", "5:OTHERKEY"])
        XCTAssertEqual(ZoteroSourceClaims.claims(of: e).map(\.key), ["1:PRIMARY1", "5:OTHERKEY"])
        XCTAssertEqual(ZoteroSourceClaims.sources(of: e).map(\.role), [.primary, .additional(0), .additional(1)])
    }

    /// 載入時就看得到（validate／doctor／App 都讀 `perRecordIssues`），不必等下一次匯入。
    func testItSurfacesThroughTheStoreHealthPerRecordIssues() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-noliblink-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(root: dir.appendingPathComponent("library"))
        try store.ensureLayout()
        try StoreVersion.write(root: store.root, format: StoreVersion.supported)
        let e = entry(additional: [Provenance(zoteroKey: "GROUPKEY", zoteroVersion: 3)])
        try store.writeEntry(e)
        let load = try store.load()
        let hit = store.health(from: load).perRecordIssues.filter { $0.issue.message.contains("附加 Zotero 來源沒記 library_id") }
        XCTAssertEqual(hit.count, 1, "\(hit.map(\.issue.message))")
        XCTAssertEqual(hit.first?.owner, e.citekey)
    }
}

/// 警告說的後果是真的：一筆帶著沒記 library_id 的附加來源的 entry，同一個 Zotero 條目再匯入時另建一筆 twin。
/// 訊息與行為分岔的話，這則警告就在說假話——所以把後果本身釘住。
final class AdditionalSourceWithoutLibraryReimportTests: XCTestCase {
    func testReimportRebuildsATwinForAnAdditionalSourceWithoutLibraryID() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-noliblink-imp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let store = LibraryStore(root: dir.appendingPathComponent("library"))
        try store.ensureLayout()
        let fixture = try ZoteroFixture(dir: dir)
        try fixture.seedStandard()
        try fixture.db.execute("INSERT INTO items VALUES (31,1,'KEYGRP01',9,5)")
        try fixture.addField(item: 31, field: 1, value: "Identifiability of polychoric models (group copy)", valueID: 131)
        let importer = ZoteroImporter(store: store)
        _ = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_000_000))
        let all = try store.load().entries
        var personal = all.first { $0.provenance?.zoteroKey == "KEYART01" }!
        let group = all.first { $0.provenance?.zoteroKey == "KEYGRP01" }!
        // 合併後的形狀，但附加來源沒記 library_id（手改或舊檔）
        personal.additionalProvenance = [Provenance(zoteroKey: "KEYGRP01", zoteroVersion: 9)]
        try store.writeEntry(personal)
        try FileManager.default.removeItem(at: store.entityURL(id: group.id))

        let report = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_100_000))
        XCTAssertEqual(report.created.count, 1, "警告說的後果：沒記 library_id 的附加來源對不回條目，另建了一筆：\(report.created)")
    }
}

/// #680：移除面的報告（`reimportNote`）說「被移除的來源若在 Zotero 端仍有那個條目，下一次 import-zotero 會為它另建一筆新 entry」。
/// 說出口的後果要用行為釘住：移除之前匯入對回持有它的附加來源、不新建；移除之後沒有任何 entry 宣稱它，匯入新建一筆。
final class ZoteroSourceRemovalReimportTests: XCTestCase {
    func testRemovingALiveAdditionalSourceMakesTheNextImportCreateANewEntry() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-zrm-imp-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        let store = LibraryStore(root: dir.appendingPathComponent("library"), key: nil, environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        let fixture = try ZoteroFixture(dir: dir)
        try fixture.seedStandard()
        try fixture.db.execute("INSERT INTO items VALUES (31,1,'KEYGRP01',9,5)")
        try fixture.addField(item: 31, field: 1, value: "Identifiability of polychoric models (group copy)", valueID: 131)
        let importer = ZoteroImporter(store: store)
        _ = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_000_000))
        let all = try store.load().entries
        var personal = all.first { $0.provenance?.zoteroKey == "KEYART01" }!
        let group = all.first { $0.provenance?.zoteroKey == "KEYGRP01" }!
        personal.additionalProvenance = [group.provenance!]   // 合併後的形狀：個人那筆持有群組來源當附加來源
        try store.writeEntry(personal)
        try FileManager.default.removeItem(at: store.entityURL(id: group.id))

        let stable = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_100_000))
        XCTAssertEqual(stable.created, [], "前提：來源被持有時匯入對得回去，不新建")

        try StoreVersion.write(root: store.root, format: StoreVersion.supported)
        GitFixture.initRepo(store.root)
        GitFixture.commitAll(store.root, message: "seed")
        let service = AkashicService(root: store.root, key: nil, environment: ["AKASHIC_HOME": home.path])
        let out = try service.updateEntry(citekey: personal.citekey, removeFields: nil, addSources: nil,
                                          removeZoteroSources: ["5:KEYGRP01=群組那份屬於另一篇"], dryRun: false)
        XCTAssertTrue(out.contains("reimportNote"), "活著的來源被移除，報告要說再匯入會另建：\(out)")

        let after = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_200_000))
        XCTAssertEqual(after.created.count, 1, "報告說的後果是真的：沒有 entry 宣稱它了，匯入新建一筆：\(after.created)")
        let created = try XCTUnwrap(try store.load().entries.first { $0.citekey == after.created[0] })
        XCTAssertEqual(created.provenance?.zoteroKey, "KEYGRP01")
        XCTAssertEqual(created.provenance?.libraryID, 5)
    }
}


/// b13f R1 verify 第 2／4／6／11 列：#680 的 `reimportNote` 首版無條件說「下一次匯入會另建一筆新 entry（已沒有任何 entry 宣稱它）」。
/// 報告說出口的後果要用匯入的行為釘住——兩個首版說假話的形狀：
/// (1) #610 的主場景：兩筆宣稱同一個來源，從記錯的那一筆移除之後另一筆仍宣稱它，匯入路由到那一筆、**不新建**；
/// (2) #679 的出路：沒記 library_id 的附加來源本來就不算宣稱者，移除它**不改變任何匯入行為**。
final class ZoteroSourceRemovalReimportBehaviourTests: XCTestCase {
    private var dir: URL!
    private var store: LibraryStore!
    private var importer: ZoteroImporter!
    private var service: AkashicService!
    private var fixture: ZoteroFixture!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-zrm-imp2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        store = LibraryStore(root: dir.appendingPathComponent("library"), key: nil, environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        fixture = try ZoteroFixture(dir: dir)
        try fixture.seedStandard()
        try fixture.db.execute("INSERT INTO items VALUES (31,1,'KEYGRP01',9,5)")
        try fixture.addField(item: 31, field: 1, value: "Identifiability of polychoric models (group copy)", valueID: 131)
        importer = ZoteroImporter(store: store)
        _ = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_000_000))
        service = AkashicService(root: store.root, key: nil, environment: ["AKASHIC_HOME": home.path])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: dir) }

    private func entry(zoteroKey: String) throws -> Entry {
        try XCTUnwrap(try store.load().entries.first { $0.provenance?.zoteroKey == zoteroKey })
    }
    private func commit() throws {
        try StoreVersion.write(root: store.root, format: StoreVersion.supported)
        GitFixture.initRepo(store.root)
        GitFixture.commitAll(store.root, message: "seed")
    }
    private func removeSource(_ spec: String, from citekey: String) throws -> [String: Any] {
        let out = try service.updateEntry(citekey: citekey, removeFields: nil, addSources: nil, removeZoteroSources: [spec], dryRun: false)
        return try XCTUnwrap(JSONSerialization.jsonObject(with: Data(out.utf8)) as? [String: Any])
    }

    /// 兩筆都宣稱 `5:KEYGRP01`（個人那筆的附加來源＋群組那筆的主來源）：匯入不更新任何一筆、不新建。從個人那筆移除之後，
    /// 群組那筆是唯一宣稱者——匯入路由到它、不新建，歧義消失。報告的 `reimportEffect` 是 `routesToOther`，而不是 `newEntry`。
    func testRemovingFromOneOfTwoClaimantsMakesTheImportRouteToTheOtherAndCreateNothing() throws {
        var personal = try entry(zoteroKey: "KEYART01")
        let group = try entry(zoteroKey: "KEYGRP01")
        personal.additionalProvenance = [group.provenance!]
        try store.writeEntry(personal)   // 群組那筆的檔仍在——兩筆都宣稱同一個來源

        let before = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_100_000))
        XCTAssertEqual(before.ambiguousSourceClaims["5:KEYGRP01"]?.count, 2, "前提：兩筆宣稱，匯入報歧義")
        XCTAssertEqual(before.created, [])

        try commit()
        let out = try removeSource("5:KEYGRP01=群組那份屬於群組那筆", from: personal.citekey)
        let item = try XCTUnwrap((out["zoteroSourceRemovals"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["reimportEffect"] as? String, "routesToOther", "\(out)")
        XCTAssertTrue((out["reimportNote"] as? String)?.contains(group.citekey) == true, "\(out)")

        let entriesBefore = try store.load().entries.count
        let after = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_200_000))
        XCTAssertEqual(after.created, [], "報告說的後果是真的：另一筆仍宣稱它，匯入不新建")
        XCTAssertTrue(after.ambiguousSourceClaims.isEmpty, "歧義隨那一筆的移除消失：\(after.ambiguousSourceClaims)")
        XCTAssertEqual(try store.load().entries.count, entriesBefore)
    }

    /// #679 的形狀：沒記 library_id 的附加來源（`?:KEYGRP01`）。第一次匯入就已經另建過一筆 twin（宣稱 `5:KEYGRP01`）——移除這個附加來源之後，
    /// 再匯入**什麼都不改變**：報告說的 `notAClaim` 是真的。
    func testRemovingAnUnclaimableAdditionalSourceChangesNothingOnTheNextImport() throws {
        var personal = try entry(zoteroKey: "KEYART01")
        let group = try entry(zoteroKey: "KEYGRP01")
        personal.additionalProvenance = [Provenance(zoteroKey: "KEYGRP01", zoteroVersion: 9)]   // 沒記 library_id
        try store.writeEntry(personal)
        try FileManager.default.removeItem(at: store.entityURL(id: group.id))
        let first = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_100_000))
        XCTAssertEqual(first.created.count, 1, "前提：對不回附加來源，第一次匯入就造出 twin")

        try commit()
        let out = try removeSource("?:KEYGRP01=沒記 library_id、對不回任何條目", from: personal.citekey)
        XCTAssertEqual((out["zoteroSourceRemovals"] as? [[String: Any]])?.first?["reimportEffect"] as? String, "notAClaim", "\(out)")

        let entriesBefore = try store.load().entries.count
        let second = try importer.run(zoteroDB: fixture.dbURL, now: Date(timeIntervalSince1970: 1_753_200_000))
        XCTAssertEqual(second.created, [], "報告說的後果是真的：移除它不改變匯入行為，不再多造一筆")
        XCTAssertEqual(try store.load().entries.count, entriesBefore)
    }
}
