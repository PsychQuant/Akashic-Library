import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #614：`update-entry --add-source`／`akashic_update_entry.add_sources`——把已存進 `sources/` 的內容宣告為某篇 work 的副本
/// （`akashic.sources`，store-format §2.4.1）。逐條釘住：預設乾跑零寫入、報告帶 index 的取得記錄、實跑走編碼器寫入、冪等、
/// 本機沒有存檔／孤兒 blob／index 腐壞／digest 不合法／同一次重複都整批拒絕零寫入、不與 remove_fields 組合、無法唯一定位拒絕。
final class EntrySourceLinkTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!
    private var entryFile: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-srclink-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        entryFile = try LibraryStore(root: root).writeEntry(
            Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T", fields: ["volume": "3"]))
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// 經正規入口存一份內容，回 digest。
    private func stored(_ text: String, origin: String = "https://example.org/x.pdf") throws -> String {
        let f = root.appendingPathComponent("in-\(UUID().uuidString).pdf")
        try Data(text.utf8).write(to: f)
        let out = try json(try service.storeSource(path: f.path, mediaType: "application/pdf", retrieved: "2026-09-29T10:00:00+08:00",
                                                   origin: origin, acquisition: "browser-download", note: "version of record"))
        try FileManager.default.removeItem(at: f)
        return try XCTUnwrap(out["digest"] as? String)
    }
    private func sources() throws -> [String] {
        try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == "x2025" }).akashic.sources
    }
    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    func testDryRunNamesTheContentAndWritesNothing() throws {
        let d = try stored("%PDF-1.7 a")
        let before = try Data(contentsOf: entryFile)
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [d], dryRun: true))
        XCTAssertEqual(out["dryRun"] as? Bool, true)
        let item = try XCTUnwrap((out["sourcesAdded"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["digest"] as? String, d)
        XCTAssertEqual(item["origin"] as? String, "https://example.org/x.pdf", "乾跑要讓人認得出這份內容是什麼")
        XCTAssertEqual(item["mediaType"] as? String, "application/pdf")
        XCTAssertEqual(item["note"] as? String, "version of record")
        XCTAssertEqual(try Data(contentsOf: entryFile), before, "乾跑零寫入")
    }

    func testApplyWritesThroughTheEncoderAndIsIdempotent() throws {
        let a = try stored("%PDF-1.7 a"), b = try stored("%PDF-1.7 b")
        _ = try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [a], dryRun: false)
        XCTAssertEqual(try sources(), [a])
        let bytes = try Data(contentsOf: entryFile)
        let again = try json(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [a], dryRun: false))
        XCTAssertEqual(again["sourcesAlreadyPresent"] as? [String], [a])
        XCTAssertEqual((again["sourcesAdded"] as? [[String: Any]])?.count, 0)
        XCTAssertEqual(try Data(contentsOf: entryFile), bytes, "沒有新東西就不寫")
        let both = try json(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [a, b], dryRun: false))
        XCTAssertEqual(try sources(), [a, b], "追加在後、既有的不動")
        XCTAssertEqual(both["sourcesTotal"] as? Int, 2)
        XCTAssertEqual(try LibraryStore(root: root).load().entries.first?.fields["volume"], "3", "其餘欄位不動")
    }

    /// 已連過的 digest 是 no-op——閘守的是寫入，沒有寫入就不需要本機有位元組（別台 clone 上 `sources/` 不在，#223 的既有契約）。
    func testAlreadyLinkedDigestIsANoOpEvenWithoutLocalContent() throws {
        let a = try stored("%PDF-1.7 a")
        _ = try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [a], dryRun: false)
        let hex = String(a.dropFirst("sha256:".count))
        try FileManager.default.removeItem(at: root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))"))
        let out = try json(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [a], dryRun: false))
        XCTAssertEqual(out["sourcesAlreadyPresent"] as? [String], [a])
        XCTAssertEqual(try sources(), [a])
    }

    func testDigestWithoutLocalContentIsRefused() throws {
        let absent = "sha256:" + String(repeating: "cd", count: 32)
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [absent], dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("本機沒有"), "\(err)")
        }
        XCTAssertEqual(try sources(), [], "零寫入")
    }

    func testOrphanBlobWithoutAnIndexEntryIsRefused() throws {
        let hex = String(repeating: "ef", count: 32)
        let blob = root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
        try FileManager.default.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("orphan".utf8).write(to: blob)
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: ["sha256:\(hex)"], dryRun: true)) { err in
            XCTAssertTrue(String(describing: err).contains("取得記錄"), "\(err)")
        }
    }

    func testCorruptIndexIsUndecidableWhenTheDigestIsNotOnAReadableLine() throws {
        let good = try stored("%PDF-1.7 a")
        let hex = String(repeating: "ab", count: 32)
        let blob = root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
        try FileManager.default.createDirectory(at: blob.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data("x".utf8).write(to: blob)
        let index = root.appendingPathComponent("sources/index.jsonl")
        let h = try FileHandle(forWritingTo: index); try h.seekToEnd(); try h.write(contentsOf: Data("{not json\n".utf8)); try h.close()
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: ["sha256:\(hex)"], dryRun: true)) { err in
            XCTAssertTrue(String(describing: err).contains("無法解析"), "\(err)")
        }
        // 在可解析的行上找得到的 digest 仍然判得出來
        XCTAssertNoThrow(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [good], dryRun: true))
    }

    /// **blob 的位置只能是普通檔**（b11c R1 verify 第 3 列，Codex）：`fileExists(atPath:)` 對目錄也回 true，於是「已存的 blob 被換成同名目錄、
    /// index 條目還在」時閘仍判 `.stored`——`--add-source --apply` 宣告了一份讀不到的副本。symlink 同理（`sources/` 由本工具寫成普通檔，
    /// 位置上出現別的東西就是有人動過）。乾跑與實跑都拒絕、work 不變。
    func testABlobPathThatIsNotARegularFileIsRefused() throws {
        for kind in ["directory", "symlink"] {
            let d = try stored("%PDF-1.7 \(kind)")
            let hex = String(d.dropFirst("sha256:".count))
            let blob = root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
            try FileManager.default.removeItem(at: blob)
            if kind == "directory" {
                try FileManager.default.createDirectory(at: blob, withIntermediateDirectories: true)
            } else {
                let target = root.appendingPathComponent("elsewhere-\(UUID().uuidString)")
                try Data("%PDF-1.7 target".utf8).write(to: target)
                try FileManager.default.createSymbolicLink(at: blob, withDestinationURL: target)
            }
            let before = try Data(contentsOf: entryFile)
            for dryRun in [true, false] {
                XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [d], dryRun: dryRun), "\(kind) dryRun=\(dryRun)") { err in
                    let s = String(describing: err)
                    XCTAssertTrue(s.contains("不是普通檔"), "\(kind)：\(s)")
                    XCTAssertTrue(s.contains(kind == "directory" ? "目錄" : "symlink"), "訊息要說是哪一種：\(s)")
                }
            }
            XCTAssertEqual(try Data(contentsOf: entryFile), before, "\(kind)：零寫入")
            XCTAssertEqual(try sources(), [])
        }
    }

    /// **全是已連過的 digest 時不讀 index**（b11c R1 verify 第 4／20／30 列）：文件與 parity 列都說「已連過的是 no-op、不檢查」，
    /// 而 `sourcePresence` 一開頭就 `scanIndex()`——index 不可讀時 no-op 呼叫反而失敗。空集合直接略過。
    func testAllAlreadyLinkedDigestsNeverTouchTheIndex() throws {
        let a = try stored("%PDF-1.7 a")
        _ = try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [a], dryRun: false)
        let index = root.appendingPathComponent("sources/index.jsonl")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)   // index 位置被目錄佔了：讀它會擲錯
        for dryRun in [true, false] {
            let out = try json(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [a], dryRun: dryRun))
            XCTAssertEqual(out["sourcesAlreadyPresent"] as? [String], [a], "dryRun=\(dryRun)")
            XCTAssertEqual((out["sourcesAdded"] as? [[String: Any]])?.count, 0)
        }
    }

    /// index 讀不到（而這次真的要新加）時，錯誤要具名——不是裸的 Foundation 訊息（不含 `sources/index.jsonl`、也不說怎麼辦）。
    func testUnreadableIndexIsNamedNotARawFoundationError() throws {
        let fresh = try stored("%PDF-1.7 fresh")
        let index = root.appendingPathComponent("sources/index.jsonl")
        try FileManager.default.removeItem(at: index)
        try FileManager.default.createDirectory(at: index, withIntermediateDirectories: true)
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [fresh], dryRun: true)) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("sources/index.jsonl") && s.contains("讀不到"), s)
            XCTAssertFalse(s.contains("NSCocoaErrorDomain") || s.contains("couldn’t be opened") || s.contains("couldn't be opened"), s)
        }
        XCTAssertEqual(try sources(), [], "零寫入")
    }

    /// **MCP 面截 `sourcesAdded`、CLI 面全列**（b11c R1 verify 第 29／31 列）：每個 item 帶 index 的五個第三方字串（至多約 2 KB），
    /// 一次至多 200 個 digest，輸出進 LLM context、呼叫端無法在收到後丟棄已付的代價——`akashic_enrich` 的 items 與 `verdictsRetired`
    /// 的既有形：截 20 筆、`sourcesAddedTotal`／`truncated` 揭露。實跑照寫全部（截的只是報告，不是寫入）。
    func testSourcesAddedIsCappedOnTheDefaultFaceAndListedInFullWhenAsked() throws {
        let digests = try (0..<25).map { try stored("%PDF-1.7 blob \($0)") }
        let capped = try json(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: digests, dryRun: true))
        XCTAssertEqual((capped["sourcesAdded"] as? [[String: Any]])?.count, AkashicService.sourcesAddedCap)
        XCTAssertEqual(capped["sourcesAddedTotal"] as? Int, 25)
        XCTAssertEqual(capped["truncated"] as? Bool, true)
        let full = try json(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: digests, dryRun: true, sourcesLimit: nil))
        XCTAssertEqual((full["sourcesAdded"] as? [[String: Any]])?.count, 25)
        XCTAssertEqual(full["sourcesAddedTotal"] as? Int, 25)
        XCTAssertEqual(full["truncated"] as? Bool, false)
        _ = try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: digests, dryRun: false)
        XCTAssertEqual(try sources().count, 25, "截的只是報告——實跑寫進全部")
    }

    /// **讀取面看得到連好的副本**（b11c R1 verify 第 11 列）：#614 讓 store 第一次出現帶 `akashic.sources` 的記錄，而
    /// `get-entry`／`akashic_get_entry` 一直看不到它——能寫不能讀（#218／#219 的同一個形狀）。
    func testGetEntryShowsTheLinkedSources() throws {
        let a = try stored("%PDF-1.7 a"), b = try stored("%PDF-1.7 b")
        let bare = try json(try service.getEntry(citekey: "x2025"))
        XCTAssertNil((bare["akashic"] as? [String: Any])?["sources"], "沒有連過就不輸出這個鍵")
        _ = try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [a, b], dryRun: false)
        let got = try json(try service.getEntry(citekey: "x2025"))
        XCTAssertEqual((got["akashic"] as? [String: Any])?["sources"] as? [String], [a, b])
    }

    func testMalformedInputRejectsTheWholeCall() throws {
        let good = try stored("%PDF-1.7 a")
        let bad: [[String]] = [["sha256:" + String(repeating: "AB", count: 32)],          // 大寫：不是合法 digest
                               ["https://example.org/x.pdf"],                             // URL 不是 digest
                               [ProvenanceReference.emptyContentDigest],                  // 空內容的 digest（#654）
                               [good, good],                                              // 同一次重複
                               [good, "sha256:" + String(repeating: "cd", count: 32)]]   // 第二筆本機沒有，第一筆也不得寫
        for b in bad {
            XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: b, dryRun: false), "\(b)")
            XCTAssertEqual(try sources(), [], "零寫入：\(b)")
        }
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: ["volume=x"], addSources: [good], dryRun: true)) { err in
            XCTAssertTrue(String(describing: err).contains("單獨呼叫"), "\(err)")
        }
    }

    func testUnlocatableWorkIsRefused() throws {
        let d = try stored("%PDF-1.7 a")
        _ = try LibraryStore(root: root).writeEntry(Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "U"))
        XCTAssertThrowsError(try service.updateEntry(citekey: "x2025", removeFields: nil, addSources: [d], dryRun: true)) { err in
            XCTAssertTrue(String(describing: err).contains("無法唯一定位"), "\(err)")
        }
    }
}
