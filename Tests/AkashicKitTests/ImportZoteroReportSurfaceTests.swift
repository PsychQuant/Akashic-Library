import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicSQLite
@testable import AkashicZoteroImport
@testable import AkashicMCPKit

/// MCP `akashic_import_zotero` 的 payload（#610、#610 R1 verify）：`ambiguousSourceClaims` 是使用者與 LLM 實際看到「這個條目本趟被整個略過」
/// 的地方，先前只有 importer 的 struct 欄位有測試——這一段被刪或改名沒有東西會紅。
///
/// 走 `AkashicService.importZotero`（MCP server 的分派只是把參數轉給它，`StdioE2ETests` 釘住分派）。
final class ImportZoteroReportSurfaceTests: XCTestCase {
    var dir: URL!
    var home: URL!
    var store: LibraryStore!
    var fixture: ZoteroFixture!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-zreport-\(UUID().uuidString)")
        home = dir.appendingPathComponent("home")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        store = LibraryStore(root: dir.appendingPathComponent("library"), key: nil, environment: ["AKASHIC_HOME": home.path])
        try store.ensureLayout()
        fixture = try ZoteroFixture(dir: dir)
        try fixture.seedStandard()
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: dir)
    }

    private var service: AkashicService {
        AkashicService(root: store.root, key: nil, environment: ["AKASHIC_HOME": home.path])
    }

    private func payload(_ text: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any], text)
    }

    private func importPayload() throws -> [String: Any] {
        try payload(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil))
    }

    /// 兩筆同來源的 entry：先匯入一次，再寫一筆同來源的複本。
    @discardableResult
    private func seedTwins() throws -> (a: Entry, b: Entry) {
        _ = try importPayload()
        let a = try XCTUnwrap(try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" })
        var twin = a
        twin.id = UUID()
        twin.citekey = "cheng2025twin"
        try store.writeEntry(twin)
        return (a, twin)
    }

    /// 只在非空時出現；出現時鍵是來源鍵、值是宣稱者的 citekeys。
    func testPayloadCarriesAmbiguousSourceClaimsOnlyWhenNonEmpty() throws {
        let clean = try importPayload()
        XCTAssertNil(clean["ambiguousSourceClaims"], "沒有歧義時不出現")
        let (a, b) = try seedTwins()
        let ambiguous = try importPayload()
        let claims = try XCTUnwrap(ambiguous["ambiguousSourceClaims"] as? [String: [String]], "\(ambiguous)")
        XCTAssertEqual(claims, ["1:KEYART01": [a.citekey, b.citekey].sorted()])
    }

    /// #608：附加來源「只有 hash 變了」的一格在 MCP payload 裡，與「內容變了」那一格分開、都在（空陣列也在，與其餘 `secondarySource*` 同形）。
    func testPayloadSeparatesHashOnlyFromContentChangeForAdditionalSources() throws {
        _ = try importPayload()
        let all = try store.load().entries
        var personal = try XCTUnwrap(all.first { $0.provenance?.zoteroKey == "KEYART01" })
        try fixture.db.execute("INSERT INTO items VALUES (31,1,'KEYGRP01',9,5)")
        try fixture.addField(item: 31, field: 1, value: "Group copy", valueID: 131)
        _ = try importPayload()
        let group = try XCTUnwrap(try store.load().entries.first { $0.provenance?.zoteroKey == "KEYGRP01" })
        personal.additionalProvenance = [group.provenance!]
        personal.additionalProvenance[0].zoteroHash = "stale"   // 只有 hash 不同、Zotero 的 version 沒動
        try store.writeEntry(personal)
        try FileManager.default.removeItem(at: store.entityURL(id: group.id))
        let first = try importPayload()
        XCTAssertEqual(first["secondarySourceHashOnly"] as? [String], [personal.citekey], "\(first)")
        XCTAssertEqual(first["secondarySourceChanged"] as? [String], [], "沒有人改內容：\(first)")
        // hash 已重算存回；這次 Zotero 端真的改了內容（version 前進）
        try fixture.db.execute("UPDATE items SET version = 12 WHERE itemID = 31")
        try fixture.db.execute("UPDATE itemDataValues SET value = 'Group edited' WHERE valueID = 131")
        let second = try importPayload()
        XCTAssertEqual(second["secondarySourceChanged"] as? [String], [personal.citekey], "\(second)")
        XCTAssertEqual(second["secondarySourceHashOnly"] as? [String], [], "\(second)")
    }

    /// 舊檔的裸 key 桶（`?:<key>`）同樣出現在 payload——與 composite 同一個欄位、同一份定義。
    func testPayloadCarriesTheLegacyBareKeyBucket() throws {
        _ = try importPayload()
        var a = try XCTUnwrap(try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" })
        a.provenance?.libraryID = nil
        a.provenance?.zoteroHash = nil
        try store.writeEntry(a)
        var twin = a
        twin.id = UUID()
        twin.citekey = "cheng2025legacytwin"
        try store.writeEntry(twin)
        let claims = try XCTUnwrap(try importPayload()["ambiguousSourceClaims"] as? [String: [String]])
        XCTAssertEqual(claims, ["?:KEYART01": [a.citekey, twin.citekey].sorted()])
    }

    /// 鍵消毒截到 120 字元後可能相撞（截斷不是單射，#669）：留第一個、不 trap。兩組舊檔的裸 key 共用 120 字元的前綴。
    func testSanitisedKeyCollisionKeepsTheFirstAndDoesNotTrap() throws {
        let prefix = String(repeating: "K", count: 125)
        for (n, item) in [(1, 40), (2, 41)] {
            try fixture.db.execute("INSERT INTO items VALUES (\(item),1,'\(prefix)\(n)',3,1)")
            try fixture.addField(item: item, field: 1, value: "Long key \(n)", valueID: 400 + item)
            for twin in ["a", "b"] {
                var e = Entry(id: UUID(), citekey: "longkey\(n)\(twin)", type: .periodicalArticle, title: "L\(n)\(twin)")
                e.provenance = Provenance(zoteroKey: "\(prefix)\(n)", zoteroVersion: 1)
                try store.writeEntry(e)
            }
        }
        let claims = try XCTUnwrap(try importPayload()["ambiguousSourceClaims"] as? [String: [String]])
        XCTAssertEqual(claims.count, 1, "兩個鍵消毒後相撞成一個：\(claims.keys)")
        XCTAssertEqual(claims.values.first, ["longkey1a", "longkey1b"], "留依原始鍵排序的第一個")
    }

    /// R10 的承諾：index rebuild 擲錯不得吞掉整份 import report。先前那條分支只帶 created／updated／orphaned／writeFailed 的計數，
    /// `ambiguousSourceClaims` 與 `secondarySource*` 都消失——而「有條目本趟被整個略過」與 writeFailed 同等重要。
    func testIndexRebuildFailureKeepsTheAmbiguousClaims() throws {
        let (a, b) = try seedTwins()
        // 讓 index rebuild 必然失敗：同一筆 entry 有兩份記錄檔（#631），citekey 在 index 裡 UNIQUE
        let dup = store.root.appendingPathComponent("entries")
        try FileManager.default.createDirectory(at: dup, withIntermediateDirectories: true)
        try EntryYAML.encode(b).write(to: dup.appendingPathComponent("\(b.citekey).yaml"), atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil)) { error in
            let text = "\(error)"
            XCTAssertTrue(text.contains("index rebuild 失敗"), text)
            XCTAssertTrue(text.contains("ambiguousSourceClaims"), "整份報告的歧義不得被吞掉：\(text)")
            XCTAssertTrue(text.contains("1:KEYART01") && text.contains(a.citekey) && text.contains(b.citekey), text)
        }
    }
}
