import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #680：`update-entry --remove-zotero-source`／`akashic_update_entry.remove_zotero_sources`——移除面一族（#572／#588／#586 的形）套在
/// work 的 Zotero 來源上：`<來源鍵>=理由`（來源鍵是 `<library_id>:<zotero_key>` 或 `?:<zotero_key>`）、理由必填且只進報告、實跑要求 work 檔
/// 已 commit 且乾淨、預設乾跑、不改 store format。逐條釘住：乾跑零寫入、主來源與附加來源都能移除、沒記 library_id 的來源用 `?:` 定位
/// （#679 的出路）、移除主來源時附加來源不升格、連結狀態變化具名、輸入錯整批拒絕零寫入、不與其他三條腿組合（四條腿兩兩互斥，全部六對見 `EntrySourceRemovalTests.testAllFourLegsAreMutuallyExclusive`）。
final class EntryZoteroSourceRemovalTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-zsrcrm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private let t0 = Date(timeIntervalSince1970: 1_753_000_000)

    @discardableResult
    private func work(citekey: String = "x2025", primary: Provenance? = Provenance(zoteroKey: "PRIM0001", zoteroVersion: 5, libraryID: 1),
                      additional: [Provenance] = []) throws -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T", fields: ["volume": "3"])
        e.provenance = primary
        e.additionalProvenance = additional
        _ = try LibraryStore(root: root).writeEntry(e)
        return e
    }
    private func stored(_ citekey: String = "x2025") throws -> Entry {
        try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == citekey })
    }
    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func remove(_ specs: [String]?, dryRun: Bool, citekey: String = "x2025", via svc: AkashicService? = nil) throws -> [String: Any] {
        try json(try (svc ?? service!).updateEntry(citekey: citekey, removeFields: nil, addSources: nil, removeZoteroSources: specs, dryRun: dryRun))
    }
    private var entityFile: URL { get throws { try XCTUnwrap(FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("entities"), includingPropertiesForKeys: nil).first) } }

    // MARK: 乾跑與實跑

    func testDryRunWritesNothingNeedsNoGitAndDescribesTheRemoval() throws {
        try work(additional: [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)])
        let before = try Data(contentsOf: entityFile)
        let out = try remove(["5:GRP00001=這個來源記錯了，屬於另一篇"], dryRun: true)
        XCTAssertEqual(out["dryRun"] as? Bool, true)
        XCTAssertNotNil(out["dryRunNote"])
        let item = try XCTUnwrap((out["zoteroSourceRemovals"] as? [[String: Any]])?.first, "\(out)")
        XCTAssertEqual(item["source"] as? String, "5:GRP00001")
        XCTAssertEqual(item["role"] as? String, "additional")
        XCTAssertEqual(item["orphaned"] as? Bool, false)
        XCTAssertEqual(item["reason"] as? String, "這個來源記錯了，屬於另一篇")
        XCTAssertEqual(try Data(contentsOf: entityFile), before, "乾跑零寫入")
    }

    func testApplyRemovesAnAdditionalSourceAndKeepsTheRest() throws {
        try work(additional: [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5),
                              Provenance(zoteroKey: "GRP00002", zoteroVersion: 2, libraryID: 6)])
        let reason = String(repeating: "理由", count: 500)   // 3,000 位元組：只進報告，全文
        let out = try remove(["5:GRP00001=\(reason)"], dryRun: false, via: service.committed(root))
        let e = try stored()
        XCTAssertEqual(e.additionalProvenance.map(\.zoteroKey), ["GRP00002"])
        XCTAssertEqual(e.provenance?.zoteroKey, "PRIM0001", "主來源不動")
        XCTAssertEqual(e.fields["volume"], "3", "書目欄位不動")
        let item = try XCTUnwrap((out["zoteroSourceRemovals"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["reason"] as? String, reason, "理由只在報告裡，所以要全文")
        XCTAssertFalse(try String(contentsOf: entityFile, encoding: .utf8).contains("理由理由"), "理由不寫進 store")
        XCTAssertNil(out["dryRunNote"])
        XCTAssertTrue((out["reasonNote"] as? String)?.contains("commit message") == true)
        let state = try XCTUnwrap(out["zoteroLinkState"] as? [String: String])
        XCTAssertEqual(state, ["before": "intact", "after": "intact"])
        XCTAssertNotNil(out["reimportNote"], "活著的來源被移除：Zotero 端還有那個條目時再匯入會另建一筆——要說")
        XCTAssertEqual(out["zoteroSourcesRemaining"] as? [String], ["primary 1:PRIM0001", "additional 6:GRP00002"])
    }

    /// 移除主來源而附加來源仍在：**不升格**（升格會把書目欄位的改寫權交給另一個 library——與 App 的「與 Zotero 脫鉤」同一條裁決）。
    /// 沒有主來源、只有附加來源是合法狀態；連結狀態照 `Entry.zoteroLinkState` 的既有定義具名。
    func testRemovingThePrimaryDoesNotPromoteAnAdditionalSource() throws {
        try work(additional: [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)])
        let out = try remove(["1:PRIM0001=記錯了"], dryRun: false, via: service.committed(root))
        let e = try stored()
        XCTAssertNil(e.provenance, "主來源移除")
        XCTAssertEqual(e.additionalProvenance.map(\.zoteroKey), ["GRP00001"], "附加來源原樣留著、不升為主來源")
        XCTAssertEqual((out["zoteroSourceRemovals"] as? [[String: Any]])?.first?["role"] as? String, "primary")
        XCTAssertEqual(out["zoteroLinkState"] as? [String: String], ["before": "intact", "after": "intact"])
        let note = try XCTUnwrap(out["primaryRemovedNote"] as? String, "\(out)")
        XCTAssertTrue(note.contains("不升格"), note)
        XCTAssertEqual(out["zoteroSourcesRemaining"] as? [String], ["additional 5:GRP00001"])
    }

    /// 連結狀態的變化用既有定義判：移除主來源之後只剩已刪除的附加來源 → 整筆 orphan（裁決台看得到它）。報告要把這個變化說出來。
    func testTheLinkStateChangeIsNamedWhenTheRemovalMakesTheEntryOrphaned() throws {
        try work(additional: [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5, orphanedAt: t0)])
        let out = try remove(["1:PRIM0001=記錯了"], dryRun: true)
        XCTAssertEqual(out["zoteroLinkState"] as? [String: String], ["before": "additionalSourceOrphaned", "after": "orphaned"], "\(out)")
    }

    /// 已在 Zotero 端刪除的來源也能移除（App 的裁決台只處理附加來源那一條路；這個面不分活著與否）；已刪除的不必說再匯入會另建。
    func testAnOrphanedSourceCanBeRemovedAndNeedsNoReimportNote() throws {
        try work(additional: [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5, orphanedAt: t0)])
        let out = try remove(["5:GRP00001=Zotero 端已刪"], dryRun: false, via: service.committed(root))
        XCTAssertEqual((out["zoteroSourceRemovals"] as? [[String: Any]])?.first?["orphaned"] as? Bool, true)
        XCTAssertEqual(out["zoteroLinkState"] as? [String: String], ["before": "additionalSourceOrphaned", "after": "intact"])
        XCTAssertNil(out["reimportNote"])
        XCTAssertEqual(try stored().additionalProvenance, [])
    }

    // MARK: 沒記 library_id 的來源（#679 的出路）

    func testASourceWithoutLibraryIDIsAddressedAsQuestionMarkColonKey() throws {
        try work(additional: [Provenance(zoteroKey: "NOLIB001", zoteroVersion: 1),
                              Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)])
        XCTAssertFalse(try stored().validate().filter { $0.message.contains("附加 Zotero 來源沒記 library_id") }.isEmpty, "前提：#679 的 warning 在")
        _ = try remove(["?:NOLIB001=沒記 library_id、對不回任何條目"], dryRun: false, via: service.committed(root))
        let e = try stored()
        XCTAssertEqual(e.additionalProvenance.map(\.zoteroKey), ["GRP00001"])
        XCTAssertTrue(e.validate().filter { $0.message.contains("附加 Zotero 來源沒記 library_id") }.isEmpty, "移除之後 warning 消失")
    }

    func testALegacyPrimaryWithoutLibraryIDIsAddressedTheSameWay() throws {
        try work(primary: Provenance(zoteroKey: "LEGACY01", zoteroVersion: 1))
        let out = try remove(["?:LEGACY01=舊檔記錯"], dryRun: false, via: service.committed(root))
        XCTAssertNil(try stored().provenance)
        XCTAssertEqual(out["zoteroSourcesRemaining"] as? [String], [])
    }

    /// 一個來源鍵在同一筆 entry 裡出現在主來源與附加來源（`ZoteroSourceClaims` 的「同一筆只算一次」）：移除的是「這筆宣稱這個來源」，兩處都拿掉，
    /// 各自列在報告裡——只拿掉其中一處，這筆仍然宣稱它。
    func testASourceClaimedAsPrimaryAndAdditionalByTheSameEntryIsRemovedFromBoth() throws {
        let p = Provenance(zoteroKey: "PRIM0001", zoteroVersion: 5, libraryID: 1)
        try work(primary: p, additional: [p, Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)])
        let out = try remove(["1:PRIM0001=重複記了"], dryRun: false, via: service.committed(root))
        let e = try stored()
        XCTAssertNil(e.provenance)
        XCTAssertEqual(e.additionalProvenance.map(\.zoteroKey), ["GRP00001"])
        XCTAssertEqual((out["zoteroSourceRemovals"] as? [[String: Any]])?.map { $0["role"] as? String }, ["primary", "additional"])
    }

    // MARK: 拒絕（整批、零寫入）

    func testInputProblemsRejectTheWholeCallWithZeroWrites() throws {
        try work(additional: [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)])
        let svc = service.committed(root)
        let before = try Data(contentsOf: entityFile)
        // (輸入, 訊息必須含的片段)：片段釘住**為什麼**被拒——形狀錯與「這筆沒有這個來源」是兩件事，不能靠後者兜住前者
        let bad: [([String], String)] = [
            (["5:GRP00001"], "缺少 `=`"),
            (["5:GRP00001=   "], "理由是空白"),
            (["=理由"], "不是來源鍵"),
            (["GRP00001=理由"], "不是來源鍵"),                       // 沒有 library_id 前綴
            (["x:GRP00001=理由"], "不是來源鍵"),                     // library_id 不是數字
            (["-5:GRP00001=理由"], "不是來源鍵"),                    // 負號不是數字
            (["５:GRP00001=理由"], "不是來源鍵"),                    // 全形數字
            (["5:=理由"], "不是來源鍵"),                             // zotero_key 空
            (["5:GRP00001=a", "5:GRP00001=b"], "出現兩次"),
            (["05:GRP00001=a", "5:GRP00001=b"], "出現兩次"),        // 正規化後同一來源兩次
            (["5:GRP00001=\(String(repeating: "x", count: 4_097))"], "位元組"),
            (["5:NOSUCH01=理由"], "沒有來源"),
            (["5:GRP00001=ok", "5:NOSUCH01=第二筆不存在，第一筆也不得寫"], "沒有來源"),
            (["1:GRP00001=理由"], "沒有來源"),                       // library_id 不符不算同一個來源
            ((0...200).map { "1:K\($0)=r" }, "一次最多"),           // 超過 200 個
        ]
        for (b, expected) in bad {
            XCTAssertThrowsError(try remove(b, dryRun: false, via: svc), "\(b.prefix(2))") { err in
                XCTAssertTrue(String(describing: err).contains(expected), "\(b.prefix(2)) 要因「\(expected)」被拒：\(err)")
            }
            XCTAssertEqual(try Data(contentsOf: entityFile), before, "零寫入：\(b.prefix(2))")
        }
    }

    /// 找不到的來源鍵：訊息列出這筆現有的來源，讓人對得到（不是一句「找不到」）。
    func testAMissingSourceNamesTheEntrysCurrentSources() throws {
        try work(additional: [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)])
        XCTAssertThrowsError(try remove(["5:NOSUCH01=理由"], dryRun: true)) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("5:NOSUCH01") && s.contains("1:PRIM0001") && s.contains("5:GRP00001"), s)
        }
        try work(citekey: "plain2025", primary: nil)
        XCTAssertThrowsError(try remove(["1:PRIM0001=理由"], dryRun: true, citekey: "plain2025")) { err in
            XCTAssertTrue(String(describing: err).contains("沒有任何 Zotero 來源"), "\(err)")
        }
    }

    func testUncommittedWorkAndStoreOutsideGitAreRefusedOnApply() throws {
        try work(additional: [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)])
        XCTAssertThrowsError(try remove(["5:GRP00001=理由"], dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("git"), "\(err)")
        }
        StoreGitCommit.commitAll(root)
        var e = try stored()
        e.fields["volume"] = "9"   // 未提交的修改
        _ = try LibraryStore(root: root).writeEntry(e)
        XCTAssertThrowsError(try remove(["5:GRP00001=理由"], dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("#680"), "\(err)")
        }
        XCTAssertEqual(try stored().additionalProvenance.count, 1, "零寫入")
    }

    func testMissingAndUnlocatableWorksAreRefused() throws {
        XCTAssertThrowsError(try remove(["1:A=x"], dryRun: true, citekey: "nope")) { err in
            guard case ServiceError.notFound = err else { return XCTFail("\(err)") }
        }
        try work(citekey: "dup2025")
        try work(citekey: "dup2025")   // 兩筆同 citekey（#627 的形）
        XCTAssertThrowsError(try remove(["1:PRIM0001=x"], dryRun: true, citekey: "dup2025")) { err in
            XCTAssertTrue(String(describing: err).contains("無法唯一定位"), "\(err)")
        }
    }

    /// 四條腿兩兩各自單獨呼叫：移除 Zotero 來源是判定，不與 `remove_fields`（判定，另一份 git 閘語意）、`add_sources`（落地）或 `remove_sources`（判定）混在一次呼叫裡。這裡只釘它與前兩者的兩對，全部六對見 `EntrySourceRemovalTests`。
    func testTheThreeLegsDoNotCombine() throws {
        try work(additional: [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)])
        let d = "sha256:" + String(repeating: "ab", count: 32)
        for (rf, ad) in [(["volume=x"], nil as [String]?), (nil as [String]?, [d])] {
            XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: rf, addSources: ad,
                                                          removeZoteroSources: ["5:GRP00001=x"], dryRun: true)) { err in
                XCTAssertTrue(String(describing: err).contains("單獨呼叫"), "\(err)")
            }
        }
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: nil, removeZoteroSources: [], dryRun: true)) { err in
            XCTAssertTrue(String(describing: err).contains("沒有要做的事"), "\(err)")
        }
    }
}
