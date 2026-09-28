import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

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
