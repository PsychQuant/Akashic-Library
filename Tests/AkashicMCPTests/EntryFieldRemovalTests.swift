import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO
@testable import AkashicEntity

/// #544：`update-entry --remove-field`／`akashic_update_entry.remove_fields`。契約見 `EntryUpdate.swift` 的檔頭；這裡逐條釘住：
/// 預設乾跑零寫入、實跑移除值與它的 `fields.<鍵>` reference（別的 reference 不動）、理由只進報告且不截斷、未 commit 拒絕、
/// 輸入錯整批拒絕零寫入、無法唯一定位拒絕、由被移除值推導的 literal venue 邊具名但不動、Zotero 來源附註。
final class EntryFieldRemovalTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!
    private let crossrefErrorPage = "This DOI is not currently attached to any metadata records. DOIs can’t actually ever be deleted (they’re persistent)"
    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-fieldrm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func retrieval(_ field: String, value: String? = nil) throws -> ProvenanceReference {
        try ProvenanceReference(field: field, value: value, url: "https://example.org/x", retrieved: "2026-09-09",
                                status: 200, mediaType: "text/html", content: digest, judgement: nil, restsOn: [])
    }

    @discardableResult
    private func work(citekey: String = "x2025", fields: [String: String], venues: [VenueRef] = [],
                      references: [ProvenanceReference] = [], provenance: Provenance? = nil,
                      doi: [DOI] = []) throws -> Entry {
        let e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T", venues: venues,
                      fields: fields, provenance: provenance, doi: doi, references: references)
        _ = try LibraryStore(root: root).writeEntry(e)
        return e
    }
    private func stored(_ citekey: String = "x2025") throws -> Entry {
        try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == citekey })
    }
    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    func testDryRunWritesNothingAndNeedsNoGit() throws {
        try work(fields: ["abstract": crossrefErrorPage, "volume": "3"])
        // 不在 git 裡也能乾跑——乾跑不寫，不需要副本
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: ["abstract=Crossref 的錯誤頁"], dryRun: true))
        XCTAssertEqual(out["dryRun"] as? Bool, true)
        XCTAssertNotNil(out["dryRunNote"])
        XCTAssertEqual((out["fieldRemovals"] as? [[String: Any]])?.first?["field"] as? String, "abstract")
        XCTAssertEqual(try stored().fields["abstract"], crossrefErrorPage, "乾跑零寫入")
    }

    func testApplyRemovesTheValueAndItsFieldReferencesOnly() throws {
        try work(fields: ["abstract": crossrefErrorPage, "volume": "3"],
                 references: [try retrieval("fields.abstract"), try retrieval("fields.abstract"),
                              try retrieval("fields.volume"), try retrieval("doi", value: "10.1000/x")],
                 doi: [try XCTUnwrap(DOI("10.1000/x"))])
        let reason = String(repeating: "錯誤頁", count: 300)   // 2,700 位元組：比 displaySafe 的預設上限長，不得被截
        let out = try json(try service.committed(root).updateEntry(citekey: "x2025", removeFields: ["abstract=\(reason)"], dryRun: false))
        let e = try stored()
        XCTAssertNil(e.fields["abstract"])
        XCTAssertEqual(e.fields["volume"], "3", "沒點名的欄位不動")
        XCTAssertEqual(e.references.map(\.field), ["fields.volume", "doi"],
                       "只刪指向被移除鍵的 fields.<鍵> reference——留著它會從「值出自這份來源」翻成「查過了、沒有」")
        XCTAssertEqual(out["dryRun"] as? Bool, false)
        let item = try XCTUnwrap((out["fieldRemovals"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["reason"] as? String, reason, "理由只在報告裡，所以要全文")
        XCTAssertEqual(item["referencesRemoved"] as? Int, 2)
        XCTAssertEqual(item["valueBytes"] as? Int, crossrefErrorPage.utf8.count)
        XCTAssertTrue((item["value"] as? String)?.hasPrefix("This DOI is not currently attached") == true, "\(item)")
        XCTAssertNil(out["dryRunNote"])
        XCTAssertTrue((out["reasonNote"] as? String)?.contains("commit message") == true)
    }

    func testLongValuesArePreviewedNotDumped() throws {
        let long = String(repeating: "a", count: 5_000)
        try work(fields: ["abstract": long])
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: ["abstract=x"], dryRun: true))
        let item = try XCTUnwrap((out["fieldRemovals"] as? [[String: Any]])?.first)
        XCTAssertLessThan((item["value"] as? String ?? "").count, 400, "值只印前段（全文在 git）")
        XCTAssertEqual(item["valueBytes"] as? Int, 5_000)
    }

    func testUncommittedWorkIsRefusedAndNothingIsWritten() throws {
        try work(fields: ["abstract": crossrefErrorPage])
        StoreGitCommit.commitAll(root)
        var e = try stored()
        e.fields["volume"] = "9"   // 未提交的修改
        _ = try LibraryStore(root: root).writeEntry(e)
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: ["abstract=錯誤頁"], dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("#544"), "\(err)")
        }
        XCTAssertEqual(try stored().fields["abstract"], crossrefErrorPage, "零寫入")
    }

    func testStoreOutsideGitIsRefusedOnApply() throws {
        try work(fields: ["abstract": crossrefErrorPage])
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: ["abstract=錯誤頁"], dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("git"), "\(err)")
        }
        XCTAssertEqual(try stored().fields["abstract"], crossrefErrorPage)
    }

    func testMalformedInputRejectsTheWholeCall() throws {
        try work(fields: ["abstract": crossrefErrorPage, "volume": "3"])
        let svc = service.committed(root)
        let bad: [[String]?] = [nil, [],
                                ["abstract"],                               // 沒有理由
                                ["abstract=   "],                           // 理由空白
                                ["=理由"],                                   // 鍵空白
                                ["abstract=a", "abstract=b"],               // 同一鍵兩次
                                ["volume=ok", "nope=沒有這個鍵"],             // 第二筆鍵不存在，第一筆也不得寫
                                ["volume=ok", "abstract=\(String(repeating: "x", count: 4_097))"],   // 第二筆理由過長
                                (0...200).map { "k\($0)=r" }]               // 超過 200 個
        for b in bad {
            XCTAssertThrowsError(try svc.updateEntry(citekey: "x2025", removeFields: b, dryRun: false), "\(String(describing: b))")
            let e = try stored()
            XCTAssertEqual(e.fields["abstract"], crossrefErrorPage, "零寫入：\(String(describing: b))")
            XCTAssertEqual(e.fields["volume"], "3", "零寫入：\(String(describing: b))")
        }
    }

    func testMissingAndUnlocatableWorksAreRefused() throws {
        XCTAssertThrowsError(try service.updateEntry(citekey: "nope", removeFields: ["abstract=x"], dryRun: true)) { err in
            guard case ServiceError.notFound = err else { return XCTFail("\(err)") }
        }
        try work(citekey: "dup2025", fields: ["abstract": "A"])
        try work(citekey: "dup2025", fields: ["abstract": "B"])   // 兩筆同 citekey（#627 的形）
        XCTAssertThrowsError(try service.updateEntry(citekey: "dup2025", removeFields: ["abstract=x"], dryRun: true)) { err in
            XCTAssertTrue(String(describing: err).contains("無法唯一定位"), "\(err)")
        }
    }

    func testVenueEdgeDerivedFromTheRemovedValueIsNamedButLeftAlone() throws {
        try work(fields: ["journaltitle": "科技部大專生研究計畫"],
                 venues: [.literal("科技部大專生研究計畫"), .literal("Other")])
        let out = try json(try service.committed(root).updateEntry(citekey: "x2025",
                                                                   removeFields: ["journaltitle=補助計畫名稱，不是期刊"], dryRun: false))
        XCTAssertEqual(out["venueEdgesFromRemovedValues"] as? [String], ["x2025:0 literal:科技部大專生研究計畫"])
        XCTAssertTrue((out["venueEdgesNote"] as? String)?.contains("--drop-venue") == true)
        XCTAssertEqual(try stored().venues, [.literal("科技部大專生研究計畫"), .literal("Other")], "邊是另一個判定——本面不動")
    }

    /// **已歸戶的 `.key` 邊與它的 confirmed verdict 也要出聲**（b11c R1 verify 第 23／35 列）：`venueEdgesFromRemovedValues` 只看 `.literal`
    /// 邊，而 #544 針對的正是「補助計畫名稱被記成期刊」——若那個值先前已被 `resolve-venues apply` 升成 `.key` 邊，移除欄位後邊與 venue 上的
    /// `work:<citekey> :: <literal>` verdict 原封不動、報告一句話都沒有，錯的歸屬繼續有效。本面仍不動它們（那是另一個判定），但要具名並指路。
    func testAKeyEdgeResolvedFromTheRemovedValueIsNamedWithItsVerdict() throws {
        _ = try service.addVenue(key: "grant-programme", names: ["科技部大專生研究計畫"], type: "periodical", note: nil, issn: nil)
        try work(fields: ["journaltitle": "科技部大專生研究計畫"], venues: [.literal("科技部大專生研究計畫"), .literal("Other")])
        _ = try service.resolveVenues(apply: ["x2025:0"])
        let before = try stored()
        XCTAssertEqual(before.venues.first, .key("grant-programme"), "fixture：邊已升成 key")
        let out = try json(try service.committed(root).updateEntry(citekey: "x2025",
                                                                   removeFields: ["journaltitle=補助計畫名稱，不是期刊"], dryRun: false))
        let named = try XCTUnwrap(out["venueKeyEdgesFromRemovedValues"] as? [String], "\(out)")
        XCTAssertEqual(named, ["x2025:0 key:grant-programme literal:科技部大專生研究計畫"])
        XCTAssertTrue((out["venueEdgesNote"] as? String)?.contains("--demote") == true, "指路要指到 demote：\(out)")
        XCTAssertNil(out["venueEdgesFromRemovedValues"], "literal 邊那一族沒有東西——不憑空出現")
        XCTAssertEqual(try stored().venues, before.venues, "邊不動")
        let venue = try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "grant-programme" })
        XCTAssertTrue(ResolutionLedger.verdicts(references: venue.references).0.contains { $0.kind == .confirmed && $0.holder == "x2025" },
                      "venue 上的 confirmed verdict 也不動")
    }

    func testAKeyEdgeWhoseVerdictIsForAnotherLiteralIsNotNamed() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"], type: "periodical", note: nil, issn: nil)
        try work(fields: ["journaltitle": "Psychometrika", "publisher": "Some Publisher"], venues: [.literal("Psychometrika"), .literal("Some Publisher")])
        _ = try service.resolveVenues(apply: ["x2025:0"])
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: ["publisher=不是出版者"], dryRun: true))
        XCTAssertNil(out["venueKeyEdgesFromRemovedValues"], "被移除的是 publisher；key 邊的 verdict 是 journaltitle 那個字——與這次移除無關")
    }

    /// **三條會把值補回去的路徑都要說**（b11c R1 verify 第 7／14 列）：`zoteroNote` 只講 Zotero pull，而 `import-wos` 的回填（只多不少：
    /// 缺席的鍵會被補進去）與 `enrich`（add-only）在同一個鍵被移除之後同樣會把值補回來——store 裡沒有東西記得「這個值被判定過不屬於這裡」。
    func testEveryReintroductionPathIsNamedNotJustZotero() throws {
        try work(fields: ["abstract": crossrefErrorPage])
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: ["abstract=錯誤頁"], dryRun: true))
        let note = try XCTUnwrap(out["reintroductionNote"] as? String, "\(out)")
        for path in ["import-wos", "enrich", "Zotero"] {
            XCTAssertTrue(note.contains(path), "\(path) 沒被點名：\(note)")
        }
    }

    /// **移除 APA7 必要欄位時，乾跑就要提醒**（b11c R1 verify 第 36 列）：`validate` 不報、`export-bib` 才印 `[ERROR] Missing required field`，
    /// 而 `apa7-is-the-work-floor` 把「能產出正確 APA7」當下限。用既有的必要欄位表（`BibExport.apa7Report`），只報這次移除**新增**的缺漏。
    func testRemovingAnApa7RequiredFieldIsFlaggedOnTheDryRun() throws {
        try work(fields: ["journaltitle": "J One", "volume": "3", "abstract": "A"])
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: ["journaltitle=x", "abstract=y"], dryRun: true))
        let missing = try XCTUnwrap(out["apa7RequiredNowMissing"] as? [String], "\(out)")
        XCTAssertEqual(missing, ["JOURNALTITLE"], "abstract 不是必要欄位；AUTHOR 等移除前就缺的不算這次造成的")
        XCTAssertNotNil(out["apa7Note"])
        let quiet = try json(try service.updateEntry(citekey: "x2025", removeFields: ["abstract=y"], dryRun: true))
        XCTAssertNil(quiet["apa7RequiredNowMissing"], "沒有新增缺漏就不出聲")
    }

    func testNoVenueNoteWhenTheValueIsStillDerivable() throws {
        // publisher 與 journaltitle 同值：移除其中一個之後，另一個仍推導得出同一條邊
        try work(fields: ["journaltitle": "J", "publisher": "J"], venues: [.literal("J")])
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: ["publisher=x"], dryRun: true))
        XCTAssertNil(out["venueEdgesFromRemovedValues"])
    }

    func testZoteroSourcedRecordCarriesTheNote() throws {
        try work(fields: ["publisher": "華總一義字第10000015611號"], provenance: Provenance(zoteroKey: "6N2NKANB", zoteroVersion: 65))
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: ["publisher=總統令字號"], dryRun: true))
        XCTAssertTrue((out["zoteroNote"] as? String)?.contains("Zotero") == true, "\(out)")
        try work(citekey: "y2025", fields: ["publisher": "P"])
        let plain = try json(try service.updateEntry(citekey: "y2025", removeFields: ["publisher=x"], dryRun: true))
        XCTAssertNil(plain["zoteroNote"])
    }
}
