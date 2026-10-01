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
        try fixture.setSynced(1)   // 已同步——#608 verify R1：沒有這一欄或 synced = 0 時不算「只有 hash 不同」
        let first = try importPayload()
        XCTAssertEqual(first["secondarySourceHashOnly"] as? [String], [personal.citekey], "\(first)")
        XCTAssertEqual(first["secondarySourceChanged"] as? [String], [], "version 沒前進，不列在內容變動那一格：\(first)")
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

    /// 讓 index rebuild 必然失敗：兩筆**不同**的記錄（id 不同）共用一個 citekey，index 的 UNIQUE 必撞。先前這裡用「同一筆 entry 有兩份
    /// 記錄檔」（#631）——#709 起那一對不再讓重建失敗（index 以 entities/ 那份為準、略過 legacy 拷貝）。兩筆都沒有 Zotero 來源，匯入不碰它們。
    private func breakIndexRebuild() throws {
        for title in ["A", "B"] {
            try store.writeEntry(Entry(id: UUID(), citekey: "rebuildbreaker2020", type: .periodicalArticle, title: title, date: "2020"))
        }
    }

    /// R10 的承諾：index rebuild 擲錯不得吞掉整份 import report。先前那條分支只帶 created／updated／orphaned／writeFailed 的計數，
    /// `ambiguousSourceClaims` 與 `secondarySource*` 都消失——而「有條目本趟被整個略過」與 writeFailed 同等重要。
    func testIndexRebuildFailureKeepsTheAmbiguousClaims() throws {
        let (a, b) = try seedTwins()
        try breakIndexRebuild()
        XCTAssertThrowsError(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil)) { error in
            let text = "\(error)"
            XCTAssertTrue(text.contains("index rebuild 失敗"), text)
            XCTAssertTrue(text.contains("ambiguousSourceClaims"), "整份報告的歧義不得被吞掉：\(text)")
            XCTAssertTrue(text.contains("1:KEYART01") && text.contains(a.citekey) && text.contains(b.citekey), text)
        }
    }

    // MARK: - #684：MCP 面的 ambiguousSourceClaims 有上限，截斷要說出來

    /// `count` 個來源、每個 `owners` 筆 entry 宣稱（同 library、同 key）。Zotero 端各有一個 item，所以匯入會把它們都判成歧義。
    private func seedClaimed(sources count: Int, owners: Int = 2) throws {
        for n in 1...count {
            let key = String(format: "KEYCAP%02d", n)
            let item = 500 + n
            try fixture.db.execute("INSERT INTO items VALUES (\(item),1,'\(key)',3,1)")
            try fixture.addField(item: item, field: 1, value: "Claimed \(n)", valueID: 5000 + item)
            for o in 1...owners {
                var e = Entry(id: UUID(), citekey: "claimed\(String(format: "%02d", n))o\(o)", type: .periodicalArticle, title: "C\(n)o\(o)")
                e.provenance = Provenance(zoteroKey: key, zoteroVersion: 1, libraryID: 1)
                try store.writeEntry(e)
            }
        }
    }

    private func claims(_ p: [String: Any]) throws -> [String: [String]] {
        try XCTUnwrap(p["ambiguousSourceClaims"] as? [String: [String]], "\(p)")
    }

    /// 上限之內：全列，而且**總數與截斷旗標仍然給**（呼叫端不必猜「沒有旗標＝沒有截」）。
    func testClaimsWithinTheLimitAreListedInFullWithTotalAndNoTruncation() throws {
        try seedClaimed(sources: 3)
        let out = try payload(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil, claimLimit: 5))
        XCTAssertEqual(try claims(out).keys.sorted(), ["1:KEYCAP01", "1:KEYCAP02", "1:KEYCAP03"])
        XCTAssertEqual(out["ambiguousSourceClaimsTotal"] as? Int, 3)
        XCTAssertEqual(out["ambiguousSourceClaimsTruncated"] as? Bool, false)
    }

    /// 超過上限：依來源鍵排序留前 N 個，`Total` 是完整的來源數，`Truncated` 為 true。
    func testClaimsBeyondTheLimitAreCutInKeyOrderAndTheCutIsDisclosed() throws {
        try seedClaimed(sources: 3)
        let out = try payload(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil, claimLimit: 2))
        XCTAssertEqual(try claims(out).keys.sorted(), ["1:KEYCAP01", "1:KEYCAP02"], "依原始鍵排序留前兩個，不是任意兩個")
        XCTAssertEqual(out["ambiguousSourceClaimsTotal"] as? Int, 3, "分母是完整的來源數，不是顯示的數")
        XCTAssertEqual(out["ambiguousSourceClaimsTruncated"] as? Bool, true)
    }

    /// 沒給上限（CLI 之外的呼叫端、既有測試）＝全列，行為與 #610 相同。
    func testWithoutALimitEveryClaimIsListed() throws {
        try seedClaimed(sources: 3)
        let out = try payload(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil))
        XCTAssertEqual(try claims(out).count, 3)
        XCTAssertEqual(out["ambiguousSourceClaimsTotal"] as? Int, 3)
        XCTAssertEqual(out["ambiguousSourceClaimsTruncated"] as? Bool, false)
    }

    /// 單一來源的宣稱者也有上限，並算進 `Truncated`——來源數在上限之內時，它仍可能被截。
    func testOwnersOfASingleSourceAreCappedAndCountAsTruncation() throws {
        try seedClaimed(sources: 1, owners: 4)
        let out = try payload(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil, claimLimit: 2))
        let owners = try XCTUnwrap(try claims(out)["1:KEYCAP01"])
        XCTAssertEqual(owners, ["claimed01o1", "claimed01o2"], "依 citekey 排序留前兩個")
        XCTAssertEqual(out["ambiguousSourceClaimsTotal"] as? Int, 1, "只有一個來源")
        XCTAssertEqual(out["ambiguousSourceClaimsTruncated"] as? Bool, true, "來源數沒超過、宣稱者被截了，仍是截斷")
    }

    /// 沒有歧義時三個鍵都不出現（「只在非空時出現」的既有慣例延伸到新鍵）。
    func testNoAmbiguityMeansNoneOfTheThreeKeysAppear() throws {
        let clean = try payload(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil, claimLimit: 20))
        XCTAssertNil(clean["ambiguousSourceClaims"])
        XCTAssertNil(clean["ambiguousSourceClaimsTotal"])
        XCTAssertNil(clean["ambiguousSourceClaimsTruncated"])
    }

    /// index rebuild 失敗的那條路徑帶同一份報告（R10、#610 R1 verify），所以同樣受上限——兩條路徑不得各漏各的。
    func testTheIndexRebuildFailurePathCarriesTheSameCap() throws {
        try seedClaimed(sources: 3)
        try breakIndexRebuild()
        XCTAssertThrowsError(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil, claimLimit: 1)) { error in
            // `\(error)` 是 Swift 的除錯描述：引號與換行被跳脫，還原後才看得出報告裡的 JSON
            let text = "\(error)".replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n")
            XCTAssertTrue(text.contains("index rebuild 失敗"), text)
            XCTAssertTrue(text.contains("\"ambiguousSourceClaimsTotal\" : 3"), "失敗路徑的報告也要說總數：\(text)")
            XCTAssertTrue(text.contains("\"ambiguousSourceClaimsTruncated\" : true"), text)
            XCTAssertTrue(text.contains("1:KEYCAP01") && !text.contains("1:KEYCAP02"), "只列上限內的來源：\(text)")
        }
    }

    /// 上限 < 1 沒有意義（0 不是「全部」也不是「一個都不要」）——比照 `enrich` 的 itemLimit，在動 store 之前拒絕。
    func testALimitBelowOneIsRefusedBeforeAnythingIsTouched() throws {
        try seedClaimed(sources: 1)
        let before = try store.load().entries.count
        XCTAssertThrowsError(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil, claimLimit: 0)) { error in
            XCTAssertTrue("\(error)".contains("claimLimit"), "\(error)")
        }
        XCTAssertEqual(try store.load().entries.count, before, "被拒絕的呼叫不得匯入任何東西")
    }
}

// MARK: - #694：主來源「只有 hash 不同」在 payload 裡是自己一格

extension ImportZoteroReportSurfaceTests {
    /// `updatedHashOnly` 與 `updated` 同形：永遠在（空陣列也在）。hash 不同而 Zotero 那一列已同步、version 沒變的主來源列在這裡、不列在 `updated`。
    func testPayloadSeparatesPrimaryHashOnlyFromUpdated() throws {
        let first = try importPayload()
        XCTAssertEqual(first["updatedHashOnly"] as? [String], [], "空的也要在：\(first)")
        var a = try XCTUnwrap(try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" })
        a.provenance?.zoteroHash = "stale"   // 只有 hash 不同、Zotero 的 version 沒動
        try store.writeEntry(a)
        try fixture.setSynced(1)
        let second = try importPayload()
        XCTAssertEqual(second["updatedHashOnly"] as? [String], [a.citekey], "\(second)")
        XCTAssertEqual(second["updated"] as? [String], [], "\(second)")
    }

    /// R1 verify：落在 `updatedHashOnly` 的那一筆與 `updated` 同一段整份替換——手加的欄位被拿掉、未歸戶的作者被覆寫。
    /// 先前 MCP payload 沒有 `authorsOverwritten`／`fieldsRemovedByPull`，呼叫端只看到一個讀起來無害的分類。
    func testHashOnlyUpdateStillShowsWhatThePullRemoved() throws {
        _ = try importPayload()
        var a = try XCTUnwrap(try store.load().entries.first { $0.provenance?.zoteroKey == "KEYART01" })
        a.fields["note"] = "hand-added"
        a.authors = [.literal("Someone Else")]
        a.provenance?.zoteroHash = "stale"
        try store.writeEntry(a)
        try fixture.setSynced(1)
        let out = try importPayload()
        XCTAssertEqual(out["updatedHashOnly"] as? [String], [a.citekey], "前提：落在只有 hash 不同那一格：\(out)")
        XCTAssertEqual(out["authorsOverwritten"] as? [String], [a.citekey], "\(out)")
        XCTAssertEqual(out["fieldsRemovedByPull"] as? [String: Int], ["note": 1], "\(out)")
    }
}

// MARK: - #696：其餘清單在 MCP 面同樣有上限

extension ImportZoteroReportSurfaceTests {
    /// MCP 面有上限的清單（#696）。後兩個只在非空時出現，其餘永遠在。它們描述的都是**寫進去了**的記錄——結果在 store 裡、
    /// 這一趟的改動在 store 的 git diff 裡看得到（R1 verify：`authorsOverwritten` 自此進 MCP payload，同一個上限）。
    static let cappedLists = ["created", "updated", "updatedHashOnly", "orphaned", "orphanCleared",
                              "secondarySourceChanged", "secondarySourceHashOnly", "secondarySourceOrphaned",
                              "secondarySourceRestored", "unnormalizedDates",
                              "authorsPreserved", "authorsOverwritten"]
    static let conditionalLists: Set<String> = ["authorsPreserved", "authorsOverwritten"]
    /// 一列是一個物件的清單（#611 `doiNominations`）：有上限、進 `listTotals`；歧異記錄在 store 裡的列（recorded／alreadyRecorded）
    /// 與沒記下來的列（unlocatable／failed／groupTooLarge）各自受同一個上限（R1 verify 第 5 列）。只在非空時出現。
    static let cappedRowLists = ["doiNominations"]
    static var allCappedNames: [String] { cappedLists + cappedRowLists }
    /// 失敗清單（R1 verify）：**不截**、只在非空時出現、不在 `listTotals`。沒寫進去的記錄在 store 裡沒有痕跡，
    /// 原因只在這份報告；重跑會再寫一次而不是重播，截掉的就拿不回來（`akashic_enrich` 的 writeFailed 同）。
    static let failureLists = ["writeFailed", "quarantineConflicts"]

    /// `ImportReport` 裡刻意**不**截的集合型欄位 → 理由。新增一個集合型欄位而沒有放進 `cappedLists`／`cappedRowLists` 或這裡，
    /// `testEveryReportCollectionIsCappedOrNamed` 會紅。
    static let uncappedCollections: [String: String] = [
        "ambiguousSourceClaims": "#684 另有上限與自己的鍵（ambiguousSourceClaimsTotal／ambiguousSourceClaimsTruncated）",
        "residualFields": "鍵是 Zotero 的欄位名，筆數受 Zotero schema 的欄位表限制、不隨一次匯入的筆數成長",
        "fieldsRemovedByPull": "鍵是被整份替換拿掉的欄位名、值是次數——筆數隨 store 的欄位種類、不隨一次匯入的筆數成長（同 residualFields）",
        "writeFailed": "失敗清單：沒寫進去的記錄在 store 裡沒有痕跡、原因只在這份報告，截掉就拿不回來",
        "quarantineConflicts": "失敗清單：同 writeFailed",
        "writtenWithLegacyCopy": "#705 R2 verify：另有上限與自己的鍵（writtenWithLegacyCopyTotal／writtenWithLegacyCopyTruncated，同 ambiguousSourceClaims）；截掉的由 akashic validate 逐筆列出",
    ]
    /// payload 裡是集合、但不是報告清單的鍵（#696 的揭露本身）。
    static let disclosureKeys: Set<String> = ["listTotals", "truncatedLists"]

    /// 每個清單都放 `n` 筆，citekey 依序遞增（`ck01`…）；刻意以逆序放入，驗證截的是**排序後**的前面。
    private func fullReport(_ n: Int) -> ImportReport {
        let keys = (1...n).map { String(format: "ck%02d", $0) }
        let reversed = Array(keys.reversed())
        var r = ImportReport()
        r.created = reversed; r.updated = reversed; r.updatedHashOnly = reversed
        r.orphaned = reversed; r.orphanCleared = reversed
        r.secondarySourceChanged = reversed; r.secondarySourceHashOnly = reversed
        r.secondarySourceOrphaned = reversed; r.secondarySourceRestored = reversed
        r.unnormalizedDates = reversed; r.authorsPreserved = reversed; r.quarantineConflicts = reversed
        r.writeFailed = Dictionary(uniqueKeysWithValues: keys.map { ($0, "boom") })
        r.ambiguousSourceClaims = ["1:KEY": ["a", "b"]]
        r.residualFields = ["extra": n]
        r.authorsOverwritten = reversed
        r.fieldsRemovedByPull = ["note": n]
        r.writtenWithLegacyCopy = keys.map { LegacyCopyLeft(kind: .work, key: $0, id: UUID(), legacyFile: "entries/\($0).yaml", detail: "d") }
        r.doiNominations = reversed.map { DOINomination(created: $0, other: "other", dois: ["10.1000/x"], status: .recorded, divergenceID: UUID()) }
        r.unchanged = 7
        return r
    }

    private func shown(_ p: [String: Any], _ key: String) throws -> [String] {
        if key == "writeFailed" { return try XCTUnwrap(p[key] as? [String: String], "\(key)：\(p)").keys.sorted() }
        return try XCTUnwrap(p[key] as? [String], "\(key)：\(p)")
    }

    private func nominationRows(_ p: [String: Any]) throws -> [[String: Any]] {
        try XCTUnwrap(p["doiNominations"] as? [[String: Any]], "doiNominations：\(p)")
    }

    private func totals(_ p: [String: Any]) throws -> [String: Int] {
        try XCTUnwrap(p["listTotals"] as? [String: Int], "listTotals：\(p)")
    }

    private func truncated(_ p: [String: Any]) throws -> [String] {
        try XCTUnwrap(p["truncatedLists"] as? [String], "truncatedLists：\(p)")
    }

    /// 超過上限：每個清單留排序後的前 N 筆；`listTotals` 給每個清單的完整筆數，`truncatedLists` 列出全部被截的清單（排序）。計數不受影響。
    func testEveryListIsCappedAndTheCutIsDisclosed() throws {
        let p = AkashicService.importReportPayload(fullReport(3), listLimit: 2)
        for key in Self.cappedLists {
            XCTAssertEqual(try shown(p, key), ["ck01", "ck02"], "\(key) 依 citekey 排序留前兩筆")
        }
        XCTAssertEqual(try totals(p), Dictionary(uniqueKeysWithValues: Self.allCappedNames.map { ($0, 3) }), "分母是完整筆數")
        XCTAssertEqual(try truncated(p), Self.allCappedNames.sorted())
        XCTAssertEqual(try nominationRows(p).map { $0["created"] as? String }, ["ck01", "ck02"], "doiNominations 依 (created, other) 排序留前兩列")
        XCTAssertEqual(p["unchanged"] as? Int, 7, "計數不截")
    }

    /// R1 verify：失敗清單不截——上限之外的第 N 筆失敗與它的原因，呼叫端事後從哪裡都拿不回來。
    /// 也不在 `listTotals`／`truncatedLists`（那一對鍵只描述有上限的清單）。
    func testFailureListsAreNeverCapped() throws {
        let p = AkashicService.importReportPayload(fullReport(3), listLimit: 2)
        for key in Self.failureLists {
            XCTAssertEqual(try shown(p, key), ["ck01", "ck02", "ck03"], "\(key) 全列")
            XCTAssertNil(try totals(p)[key], "\(key) 沒有上限，不進 listTotals")
            XCTAssertFalse(try truncated(p).contains(key), key)
        }
        XCTAssertEqual((p["writeFailed"] as? [String: String])?["ck03"], "boom", "原因也在")
    }

    /// R1 verify（#694／#608 的 `updatedHashOnly` 讀起來像無害，而同一次改寫照樣拿掉手加的欄位、覆寫 literal 作者）：
    /// `authorsOverwritten` 與 `fieldsRemovedByPull` 在 MCP payload 裡——`lossless-intake`：丟棄必須可見，兩面都要看得到。
    func testPullOverwritesAreVisibleInThePayload() throws {
        let p = AkashicService.importReportPayload(fullReport(3), listLimit: 2)
        XCTAssertEqual(try shown(p, "authorsOverwritten"), ["ck01", "ck02"], "citekey 清單，同一個上限")
        XCTAssertEqual(try totals(p)["authorsOverwritten"], 3)
        XCTAssertEqual(p["fieldsRemovedByPull"] as? [String: Int], ["note": 3], "欄位名 → 次數，不截")
    }

    /// 上限之內：全列，`listTotals` 照給、`truncatedLists` 是空陣列（呼叫端不必猜「沒有鍵＝沒有截」，#684 同一條）。
    func testListsWithinTheLimitAreFullAndNothingIsListedAsTruncated() throws {
        let p = AkashicService.importReportPayload(fullReport(3), listLimit: 5)
        for key in Self.cappedLists {
            XCTAssertEqual(try shown(p, key), ["ck01", "ck02", "ck03"], key)
        }
        XCTAssertEqual(try totals(p).values.sorted(), Array(repeating: 3, count: Self.allCappedNames.count))
        XCTAssertEqual(try nominationRows(p).count, 3)
        XCTAssertEqual(try truncated(p), [])
    }

    /// 沒給上限（CLI 之外的呼叫端、既有測試）＝全列，兩個鍵照給。
    func testWithoutAListLimitEveryListIsFullAndTheTotalsAreStillGiven() throws {
        let p = AkashicService.importReportPayload(fullReport(3))
        for key in Self.cappedLists {
            XCTAssertEqual(try shown(p, key).count, 3, key)
        }
        XCTAssertEqual(try totals(p).count, Self.allCappedNames.count)
        XCTAssertEqual(try nominationRows(p).count, 3)
        XCTAssertEqual(try truncated(p), [])
    }

    /// 出現規則：兩個揭露鍵永遠在；`listTotals` 每個清單都有一格（空的是 0），只在非空時出現的三個清單空的時候本身不出現。
    func testEmptyListsKeepTheirPresenceRuleAndTotalsAreZero() throws {
        let p = AkashicService.importReportPayload(ImportReport(), listLimit: 20)
        for key in Self.cappedLists {
            if Self.conditionalLists.contains(key) {
                XCTAssertNil(p[key], key)
            } else {
                XCTAssertEqual(p[key] as? [String], [], key)
            }
        }
        for key in Self.failureLists + Self.cappedRowLists + ["fieldsRemovedByPull", "writtenWithLegacyCopy"] {
            XCTAssertNil(p[key], "\(key) 只在非空時出現")
        }
        XCTAssertEqual(try totals(p), Dictionary(uniqueKeysWithValues: Self.allCappedNames.map { ($0, 0) }))
        XCTAssertEqual(try truncated(p), [])
    }

    /// **不讓下一個清單安靜地長出來**：`ImportReport` 的每個集合型欄位不是有上限（`cappedLists`），就是在 `uncappedCollections`
    /// 具名寫了理由；payload 裡每個陣列／物件值同樣如此；`listTotals` 的名字恰好是 `cappedLists` 加 `cappedRowLists`。新增一個清單而忘了截，這裡會紅。
    func testEveryReportCollectionIsCappedOrNamed() throws {
        let capped = Set(Self.allCappedNames)
        var collections: [String] = []
        for child in Mirror(reflecting: ImportReport()).children {
            guard let label = child.label else { continue }
            if child.value is [Any] || child.value is [String: Any] { collections.append(label) }
        }
        XCTAssertGreaterThanOrEqual(collections.count, capped.count, "Mirror 掃不到集合欄位——空掃描不是通過：\(collections)")
        for label in collections {
            XCTAssertTrue(capped.contains(label) || Self.uncappedCollections[label] != nil,
                          "ImportReport.\(label) 是集合、沒有 MCP 上限也沒有具名理由——加進 cappedLists 或 uncappedCollections")
        }
        for key in Self.allCappedNames {
            XCTAssertTrue(collections.contains(key), "cappedLists／cappedRowLists 列了 ImportReport 沒有的欄位 \(key)")
        }
        let p = AkashicService.importReportPayload(fullReport(3), listLimit: 2)
        for (key, value) in p where value is [Any] || value is [String: Any] {
            XCTAssertTrue(capped.contains(key) || Self.uncappedCollections[key] != nil || Self.disclosureKeys.contains(key),
                          "payload 的 \(key) 是集合、沒有上限也沒有具名理由")
        }
        XCTAssertEqual(Set(try totals(p).keys), capped, "listTotals 的名字要恰好是有上限的清單")
        // 每個集合欄位都要進 payload——具名不截的理由不是「不給 MCP 看」（R1 verify：authorsOverwritten／fieldsRemovedByPull 曾經只在 CLI）
        for label in collections {
            XCTAssertNotNil(p[label], "ImportReport.\(label) 不在 MCP payload——兩面要看得到同一份報告")
        }
    }

    /// 服務層：上限只截報告，不截寫入——兩筆都建了，payload 只列一筆並說總數。
    func testServiceCapsTheListsButNotTheWrites() throws {
        let out = try payload(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil, listLimit: 1))
        XCTAssertEqual((out["created"] as? [String])?.count, 1, "\(out)")
        XCTAssertEqual(try totals(out)["created"], 2, "\(out)")
        XCTAssertEqual(try truncated(out), ["created"], "\(out)")
        XCTAssertEqual(try store.load().entries.count, 2, "上限只截報告，兩筆都要寫進去")
    }

    /// 上限 < 1 沒有意義——比照 `claimLimit`，在動 store 之前拒絕。
    func testAListLimitBelowOneIsRefusedBeforeAnythingIsTouched() throws {
        XCTAssertThrowsError(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil, listLimit: 0)) { error in
            XCTAssertTrue("\(error)".contains("listLimit"), "\(error)")
        }
        XCTAssertEqual(try store.load().entries.count, 0, "被拒絕的呼叫不得匯入任何東西")
    }

    /// index rebuild 失敗的那條路徑帶同一份報告，所以同樣受上限（#684 同一條）。
    func testTheIndexRebuildFailurePathCarriesTheListCaps() throws {
        _ = try seedTwins()
        for n in 1...2 {   // 這一趟新建兩筆，上限 1 → created 被截
            try fixture.db.execute("INSERT INTO items VALUES (\(60 + n),1,'KEYNEW0\(n)',3,1)")
            try fixture.addField(item: 60 + n, field: 1, value: "New paper \(n)", valueID: 600 + n)
        }
        try breakIndexRebuild()
        XCTAssertThrowsError(try service.importZotero(zoteroDb: fixture.dbURL.path, libraryID: nil, listLimit: 1)) { error in
            let text = "\(error)".replacingOccurrences(of: "\\\"", with: "\"").replacingOccurrences(of: "\\n", with: "\n")
            XCTAssertTrue(text.contains("index rebuild 失敗"), text)
            XCTAssertFalse(text.contains("完整報告"), "清單被截了，不能說是完整報告（R1 verify）：\(text)")
            XCTAssertTrue(text.contains("\"created\" : 2"), "失敗路徑的報告也要帶總數：\(text)")
            let cut = text.range(of: "\"truncatedLists\" : [").map { text[$0.upperBound...].prefix { $0 != "]" } }
            XCTAssertEqual(cut.map { $0.filter { !$0.isWhitespace } }, "\"created\"", "只有 created 被截：\(text)")
        }
    }
}

// MARK: - #611：DOI 提名在 payload 裡

extension ImportZoteroReportSurfaceTests {
    /// 兩種列各自受上限（R1 verify 第 5 列：先前沒記下來的三種不截，legacy 佈局上一個大群組會回出數十萬列）：歧異記錄在 store 裡的
    /// （recorded／alreadyRecorded，`akashic_divergences` 列得出來）留前 N 列、沒記下來的（unlocatable／failed／groupTooLarge）也留前 N 列。
    /// `listTotals` 是全部列數，被截時進 `truncatedLists`；`doiNominationsUnrecorded` 是沒記下來的列數，永遠完整。
    /// `divergence` 只在有記錄時出現、`error` 只在 failed 時出現、`groupSize` 只在 groupTooLarge 時出現，groupTooLarge 不帶 `other`。
    func testDOINominationRowsAreCappedPerKindAndTheUnrecordedCountIsComplete() throws {
        var r = ImportReport()
        let id = UUID()
        r.doiNominations = [
            DOINomination(created: "n1", other: "w", dois: ["10.1000/x"], status: .recorded, divergenceID: id),
            DOINomination(created: "n2", other: "w", dois: ["10.1000/x"], status: .alreadyRecorded, divergenceID: id),
            DOINomination(created: "n3", other: "w", dois: ["10.1000/x"], status: .recorded, divergenceID: UUID()),
            DOINomination(created: "n4", other: "w", dois: ["10.1000/x"], status: .unlocatable),
            DOINomination(created: "n5", other: "w", dois: ["10.1000/x"], status: .failed, error: "legacy 佈局"),
            DOINomination(created: "n6", other: "", dois: ["10.1000/big"], status: .groupTooLarge, groupSize: 80),
        ]
        let p = AkashicService.importReportPayload(r, listLimit: 1)
        let rows = try nominationRows(p)
        XCTAssertEqual(rows.map { $0["created"] as? String }, ["n1", "n4"], "在 store 裡的留一列、沒記下來的也留一列")
        XCTAssertEqual(rows.map { $0["status"] as? String }, ["recorded", "unlocatable"])
        guard rows.count == 2 else { return XCTFail("列數不對，以下逐列的斷言不跑：\(rows)") }   // 不讓越界讓整個測試行程崩潰
        XCTAssertEqual(rows[0]["divergence"] as? String, id.uuidString)
        XCTAssertEqual(rows[0]["dois"] as? [String], ["10.1000/x"])
        XCTAssertNil(rows[1]["divergence"], "沒有記錄就沒有 divergence")
        XCTAssertNil(rows[1]["error"])
        XCTAssertEqual(try totals(p)["doiNominations"], 6, "分母是全部列數")
        XCTAssertTrue(try truncated(p).contains("doiNominations"))
        XCTAssertEqual(p["doiNominationsUnrecorded"] as? Int, 3, "沒記下來的列數永遠完整：unlocatable、failed、groupTooLarge")

        let all = AkashicService.importReportPayload(r, listLimit: 10)
        let allRows = try nominationRows(all)
        XCTAssertEqual(allRows.map { $0["created"] as? String }, ["n1", "n2", "n3", "n4", "n5", "n6"])
        XCTAssertEqual(allRows[4]["error"] as? String, "legacy 佈局")
        XCTAssertEqual(allRows[5]["groupSize"] as? Int, 80)
        XCTAssertEqual(allRows[5]["dois"] as? [String], ["10.1000/big"])
        XCTAssertNil(allRows[5]["other"], "群組過大的列沒有另一筆")
        XCTAssertFalse(try truncated(all).contains("doiNominations"))
    }

    /// 沒記下來的列單獨超過上限（記錄在 store 裡的很少）：同樣被截、要說出來；`doiNominationsUnrecorded` 仍是完整的數。
    func testUnrecordedRowsAloneAreCappedAndDisclosed() throws {
        var r = ImportReport()
        r.doiNominations = (1...5).map { DOINomination(created: String(format: "n%02d", $0), other: "w", dois: ["10.1000/x"], status: .failed, error: "e") }
        let p = AkashicService.importReportPayload(r, listLimit: 2)
        XCTAssertEqual(try nominationRows(p).count, 2)
        XCTAssertEqual(try totals(p)["doiNominations"], 5)
        XCTAssertTrue(try truncated(p).contains("doiNominations"))
        XCTAssertEqual(p["doiNominationsUnrecorded"] as? Int, 5)
        let uncapped = AkashicService.importReportPayload(r)
        XCTAssertEqual(try nominationRows(uncapped).count, 5, "沒給上限＝全列")
    }

    /// 記下來的提名不帶 `doiNominationsUnrecorded`：只在有沒記下來的列時出現。
    func testUnrecordedCountIsAbsentWhenEveryNominationWasRecorded() throws {
        var r = ImportReport()
        r.doiNominations = [DOINomination(created: "n1", other: "w", dois: ["10.1000/x"], status: .recorded, divergenceID: UUID())]
        XCTAssertNil(AkashicService.importReportPayload(r, listLimit: 20)["doiNominationsUnrecorded"])
        XCTAssertNil(AkashicService.importReportPayload(ImportReport(), listLimit: 20)["doiNominationsUnrecorded"])
    }

    /// 服務層：匯入新建的一筆與既有的一筆共用 DOI——payload 的那一列指向真的寫進 store 的那筆歧異記錄。
    func testImportPayloadCarriesTheNominationWrittenToTheStore() throws {
        var wos = Entry(id: UUID(), citekey: "wos2025identifiability", type: .periodicalArticle, title: "From WoS")
        wos.doi = [try XCTUnwrap(DOI("10.1017/psy.2025.1"))]   // `seedStandard` 那篇 article 的 DOI
        try store.writeEntry(wos)
        let p = try importPayload()
        let rows = try nominationRows(p)
        XCTAssertEqual(rows.count, 1, "\(p)")
        guard rows.count == 1 else { return }
        let d = try XCTUnwrap(try store.load().divergences.first)
        XCTAssertEqual(rows[0]["status"] as? String, "recorded")
        XCTAssertEqual(rows[0]["divergence"] as? String, d.id.uuidString)
        XCTAssertEqual(rows[0]["other"] as? String, "wos2025identifiability")
        XCTAssertEqual(try totals(p)["doiNominations"], 1)
        XCTAssertNil(p["doiNominationsUnrecorded"], "都記下來了")
    }

    /// 服務層：共用同一個 DOI 的 work 超過門檻——payload 的那一列是 groupTooLarge、帶共用的 work 數，`doiNominationsUnrecorded` 說有 1 列沒記
    /// （重新匯入不會再提名）；匯入照建、store 裡沒有任何歧異記錄。
    func testImportPayloadSaysWhenNominationsWereNotRecorded() throws {
        for n in 1...10 {   // 門檻 10（字面值：引用常數的測試在常數被改大時跟著變大）
            var e = Entry(id: UUID(), citekey: String(format: "wos2025n%02d", n), type: .periodicalArticle, title: "WoS \(n)")
            e.doi = [try XCTUnwrap(DOI("10.1017/psy.2025.1"))]   // `seedStandard` 那篇 article 的 DOI
            try store.writeEntry(e)
        }
        let p = try importPayload()
        let rows = try nominationRows(p)
        XCTAssertEqual(rows.map { $0["status"] as? String }, ["groupTooLarge"], "\(p)")
        XCTAssertEqual(rows.first?["groupSize"] as? Int, 11)
        XCTAssertEqual(p["doiNominationsUnrecorded"] as? Int, 1)
        XCTAssertEqual(try totals(p)["doiNominations"], 1)
        XCTAssertEqual(try store.load().divergences, [])
    }
}
