import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicSQLite
@testable import AkashicZoteroImport

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
