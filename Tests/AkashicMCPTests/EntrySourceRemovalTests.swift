import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #677：`update-entry --remove-source`／`akashic_update_entry.remove_sources`——收回 `akashic.sources` 的一條副本宣告。
/// 契約見 `EntryUpdate.swift` 的檔頭。逐條釘住：預設乾跑零寫入、實跑只移除宣告（blob 與 index 條目原封不動）、理由只進報告且不截斷、
/// 未 commit／不在 git 拒絕、輸入錯與定位不到整批拒絕零寫入、與另外三條腿兩兩互斥（六對全釘）、無法唯一定位拒絕。
final class EntrySourceRemovalTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!
    private var entryFile: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-srcrm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        entryFile = try LibraryStore(root: root).writeEntry(
            Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T", fields: ["volume": "3"]))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 經正規入口存一份內容並宣告為 x2025 的副本，回 digest。
    private func linked(_ text: String) throws -> String {
        let f = root.appendingPathComponent("in-\(UUID().uuidString).pdf")
        try Data(text.utf8).write(to: f)
        let out = try json(try service.storeSource(path: f.path, mediaType: "application/pdf", retrieved: "2026-09-29T10:00:00+08:00",
                                                   origin: "https://example.org/\(text).pdf", acquisition: "browser-download", note: "version of record"))
        try FileManager.default.removeItem(at: f)
        let d = try XCTUnwrap(out["digest"] as? String)
        _ = try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [d], dryRun: false)
        return d
    }
    private func sources() throws -> [String] {
        try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == "x2025" }).akashic.sources
    }
    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func blobURL(_ digest: String) -> URL {
        let hex = String(digest.dropFirst("sha256:".count))
        return root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
    }

    func testDryRunNamesTheContentAndWritesNothing() throws {
        let d = try linked("a")
        let before = try Data(contentsOf: entryFile)
        // 乾跑不需要 git——不寫，不需要副本
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: nil,
                                                   removeSources: ["\(d)=連到別篇的 PDF"], dryRun: true))
        XCTAssertEqual(out["dryRun"] as? Bool, true)
        XCTAssertNotNil(out["dryRunNote"])
        let item = try XCTUnwrap((out["sourcesRemoved"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["digest"] as? String, d)
        XCTAssertEqual(item["reason"] as? String, "連到別篇的 PDF")
        XCTAssertEqual(item["origin"] as? String, "https://example.org/a.pdf", "乾跑要讓人認得出是哪份內容")
        XCTAssertEqual(item["mediaType"] as? String, "application/pdf")
        XCTAssertEqual(try Data(contentsOf: entryFile), before, "乾跑零寫入")
        XCTAssertEqual(try sources(), [d])
    }

    func testApplyRemovesOnlyTheDeclarationAndLeavesTheBlobAndIndex() throws {
        let a = try linked("a"), b = try linked("b")
        let indexBefore = try Data(contentsOf: root.appendingPathComponent("sources/index.jsonl"))
        let blobBefore = try Data(contentsOf: blobURL(a))
        let reason = String(repeating: "連錯了", count: 300)   // 2,700 位元組：比 displaySafe 的預設上限長，不得被截
        let out = try json(try service.committed(root).updateEntry(citekey: "x2025", removeFields: nil, addSources: nil,
                                                                   removeSources: ["\(a)=\(reason)"], dryRun: false))
        XCTAssertEqual(try sources(), [b], "只移除被點名的那一條，其餘不動、順序不變")
        XCTAssertEqual(try LibraryStore(root: root).load().entries.first?.fields["volume"], "3", "其餘欄位不動")
        XCTAssertEqual(out["dryRun"] as? Bool, false)
        XCTAssertNil(out["dryRunNote"])
        XCTAssertEqual(out["sourcesTotal"] as? Int, 1)
        let item = try XCTUnwrap((out["sourcesRemoved"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["reason"] as? String, reason, "理由只在報告裡，所以要全文")
        XCTAssertTrue((out["reasonNote"] as? String)?.contains("commit message") == true)
        XCTAssertTrue((out["blobNote"] as? String)?.contains("sources/") == true, "報告要說 blob 沒動")
        // 宣告是記錄側的事：內容與它的取得記錄住在 sources/，可能被別筆引用——本面不碰
        XCTAssertEqual(try Data(contentsOf: blobURL(a)), blobBefore)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent("sources/index.jsonl")), indexBefore)
    }

    func testRemovingTheLastSourceLeavesAnEmptyList() throws {
        let a = try linked("a")
        _ = try service.committed(root).updateEntry(citekey: "x2025", removeFields: nil, addSources: nil,
                                                    removeSources: ["\(a)=r"], dryRun: false)
        XCTAssertEqual(try sources(), [])
        // 空清單與缺席等價（§2.4.1）：encode 不 emit 空鍵
        XCTAssertFalse(try String(contentsOf: entryFile, encoding: .utf8).contains("sources:"))
    }

    func testReasonIsInTheReportNotInTheStore() throws {
        let a = try linked("a")
        _ = try service.committed(root).updateEntry(citekey: "x2025", removeFields: nil, addSources: nil,
                                                    removeSources: ["\(a)=獨一無二的理由字串"], dryRun: false)
        XCTAssertFalse(try String(contentsOf: entryFile, encoding: .utf8).contains("獨一無二的理由字串"), "理由不寫進 store")
    }

    func testUncommittedWorkIsRefusedAndNothingIsWritten() throws {
        let a = try linked("a")
        StoreGitCommit.commitAll(root)
        var e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        e.fields["volume"] = "9"   // 未提交的修改
        _ = try LibraryStore(root: root).writeEntry(e)
        let before = try Data(contentsOf: entryFile)
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: nil,
                                                     removeSources: ["\(a)=r"], dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("#677"), "\(err)")
        }
        XCTAssertEqual(try Data(contentsOf: entryFile), before, "零寫入")
    }

    func testStoreOutsideGitIsRefusedOnApply() throws {
        let a = try linked("a")
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: nil,
                                                     removeSources: ["\(a)=r"], dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("git"), "\(err)")
        }
        XCTAssertEqual(try sources(), [a])
    }

    func testADigestNotOnTheListIsRefusedByName() throws {
        let a = try linked("a")
        let other = "sha256:" + String(repeating: "cd", count: 32)
        for dryRun in [true, false] {
            XCTAssertThrowsError(try service.committed(root).updateEntry(citekey: "x2025", removeFields: nil, addSources: nil,
                                                                         removeSources: ["\(a)=ok", "\(other)=沒有這一條"], dryRun: dryRun)) { err in
                let s = String(describing: err)
                XCTAssertTrue(s.contains(other), "要具名是哪個 digest：\(s)")
                XCTAssertTrue(s.contains("akashic.sources"), s)
            }
            XCTAssertEqual(try sources(), [a], "第二筆不在清單上，第一筆也不得寫（dryRun=\(dryRun)）")
        }
    }

    func testMalformedInputRejectsTheWholeCall() throws {
        let a = try linked("a"), b = try linked("b")
        let svc = service.committed(root)
        let bad: [[String]] = [["\(a)"],                                    // 沒有理由
                               ["\(a)=   "],                                // 理由空白
                               ["=理由"],                                    // digest 空
                               ["sha256:bad=r"],                            // digest 形狀不對
                               ["\(a)=x", "\(a)=y"],                        // 同一個 digest 兩次
                               ["\(b)=ok", "\(a)=\(String(repeating: "x", count: 4_097))"],   // 第二筆理由過長
                               (0...200).map { _ in "\(a)=r" }]             // 超過 200 個
        for input in bad {
            XCTAssertThrowsError(try svc.updateEntry(citekey: "x2025", removeFields: nil, addSources: nil, removeSources: input, dryRun: false),
                                 "\(input.prefix(2))")
            XCTAssertEqual(try sources(), [a, b], "零寫入：\(input.prefix(2))")
        }
    }

    /// **四條腿任兩條組合都被拒**（#680／#677）：`remove_fields`、`add_sources`、`remove_zotero_sources`、`remove_sources`，C(4,2)＝6 對。
    /// 每一對都是同一句具名拒絕、零寫入（work 檔位元組不變）。
    func testAllFourLegsAreMutuallyExclusive() throws {
        let a = try linked("a")
        // 每條腿的參數各自合法：拒絕只能來自「不得組合」，不是來自形狀檢查
        let fields = ["volume=x"], adds = [a], zotero = ["5:GRP00001=x"], removals = ["\(a)=x"]
        let legs: [(name: String, fields: [String]?, adds: [String]?, zotero: [String]?, removals: [String]?)] = [
            ("remove_fields", fields, nil, nil, nil),
            ("add_sources", nil, adds, nil, nil),
            ("remove_zotero_sources", nil, nil, zotero, nil),
            ("remove_sources", nil, nil, nil, removals),
        ]
        func merged(_ x: (name: String, fields: [String]?, adds: [String]?, zotero: [String]?, removals: [String]?),
                    _ y: (name: String, fields: [String]?, adds: [String]?, zotero: [String]?, removals: [String]?)) -> (fields: [String]?, adds: [String]?, zotero: [String]?, removals: [String]?) {
            (x.fields ?? y.fields, x.adds ?? y.adds, x.zotero ?? y.zotero, x.removals ?? y.removals)
        }
        let svc = service.committed(root)
        let before = try Data(contentsOf: entryFile)
        var pairs = 0
        for i in legs.indices {
            for j in legs.indices where j > i {
                let m = merged(legs[i], legs[j])
                for dryRun in [true, false] {
                    XCTAssertThrowsError(try svc.updateEntry(citekey: "x2025", removeFields: m.fields, addSources: m.adds,
                                                             removeZoteroSources: m.zotero, removeSources: m.removals, dryRun: dryRun),
                                         "\(legs[i].name)＋\(legs[j].name) dryRun=\(dryRun)") { err in
                        XCTAssertTrue(String(describing: err).contains("兩兩各自單獨呼叫"), "\(legs[i].name)＋\(legs[j].name)：\(err)")
                    }
                }
                pairs += 1
            }
        }
        XCTAssertEqual(pairs, 6)
        XCTAssertEqual(try Data(contentsOf: entryFile), before, "零寫入")
        XCTAssertEqual(try sources(), [a])
        // 四條腿都沒給：另一句話
        XCTAssertThrowsError(try svc.updateEntry(citekey: "x2025", removeFields: nil, addSources: nil, removeZoteroSources: nil,
                                                 removeSources: nil, dryRun: true)) { err in
            XCTAssertTrue(String(describing: err).contains("沒有要做的事"), "\(err)")
        }
    }

    func testMissingAndUnlocatableWorksAreRefused() throws {
        let a = "sha256:" + String(repeating: "ab", count: 32)
        XCTAssertThrowsError(try service.updateEntry(citekey: "nope", removeFields: nil, addSources: nil,
                                                     removeSources: ["\(a)=r"], dryRun: true)) { err in
            guard case ServiceError.notFound = err else { return XCTFail("\(err)") }
        }
        _ = try LibraryStore(root: root).writeEntry(
            Entry(id: UUID(), citekey: "dup2025", type: .periodicalArticle, title: "A", akashic: AkashicMeta(sources: [a])))
        _ = try LibraryStore(root: root).writeEntry(
            Entry(id: UUID(), citekey: "dup2025", type: .periodicalArticle, title: "B", akashic: AkashicMeta(sources: [a])))   // 兩筆同 citekey（#627 的形）
        XCTAssertThrowsError(try service.updateEntry(citekey: "dup2025", removeFields: nil, addSources: nil,
                                                     removeSources: ["\(a)=r"], dryRun: true)) { err in
            XCTAssertTrue(String(describing: err).contains("無法唯一定位"), "\(err)")
        }
    }

    /// 移除是宣告的事，不改 `Entry.references`（欄位層級的 digest 證據是另一種關係，§2.4.1 的第一條）。
    func testFieldLevelReferencesToTheSameDigestAreUntouched() throws {
        let a = try linked("a")
        var e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        e.fields["abstract"] = "A"
        e.references = [try ProvenanceReference(field: "fields.abstract", value: nil, url: "https://example.org/x", retrieved: "2026-09-29",
                                                status: 200, mediaType: "text/html", content: a, judgement: nil, restsOn: [])]
        _ = try LibraryStore(root: root).writeEntry(e)
        _ = try service.committed(root).updateEntry(citekey: "x2025", removeFields: nil, addSources: nil,
                                                    removeSources: ["\(a)=r"], dryRun: false)
        let after = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        XCTAssertEqual(after.akashic.sources, [])
        XCTAssertEqual(after.references.map(\.field), ["fields.abstract"])
    }

    /// 移除不依賴本機有位元組：別台 clone 上 `sources/` 本來就可能不在（§2.4.1），連錯的宣告在那裡照樣要收得回來。
    func testRemovalDoesNotNeedTheBlobToBeLocal() throws {
        let a = try linked("a")
        try FileManager.default.removeItem(at: blobURL(a))
        let out = try json(try service.committed(root).updateEntry(citekey: "x2025", removeFields: nil, addSources: nil,
                                                                   removeSources: ["\(a)=r"], dryRun: false))
        XCTAssertEqual(try sources(), [])
        XCTAssertNil((out["sourcesRemoved"] as? [[String: Any]])?.first?["origin"], "本機沒有存檔就沒有取得記錄可印")
    }
}
