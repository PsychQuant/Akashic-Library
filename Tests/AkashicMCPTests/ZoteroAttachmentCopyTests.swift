import XCTest
import CryptoKit
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO
@testable import AkashicZoteroImport

/// #606：`copy-zotero-attachments`——把 work 的 `zotero: storage/<KEY>/<檔名>` 附件的位元組複製進 `sources/`（經 `SourceStore.storeSource`，
/// 版控排除閘 fail-closed），再把 digest 連到那筆 work 的 `akashic.sources`（既有形狀，store-format §2.4.1，format ≥ 9）。
///
/// 全部用**假的 Zotero 資料目錄**（temp 目錄裡的 `zotero.sqlite` 空檔 ＋ `storage/`）與假 home；不碰真的 `~/Zotero` 與 `~/.akashic`。
/// store 放進真 git（`StoreGitCommit`）——可回溯閘與 `sources/` 排除驗證都要真的 git 才測得到。
final class ZoteroAttachmentCopyTests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!
    private var zdir: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-zcopy-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        zdir = base.appendingPathComponent("zotero")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zdir.appendingPathComponent("storage"), withIntermediateDirectories: true)
        try Data().write(to: zdir.appendingPathComponent("zotero.sqlite"))   // 只用它的位置（資料目錄）；不開它
        try LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": home.path]).ensureLayout()
        service = AkashicService(root: root, key: nil, environment: ["AKASHIC_HOME": home.path])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

    private var dbPath: String { zdir.appendingPathComponent("zotero.sqlite").path }
    private var store: LibraryStore { LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": home.path]) }

    @discardableResult
    private func put(_ rel: String, _ text: String) throws -> Data {
        let url = zdir.appendingPathComponent(rel)
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        let data = Data(text.utf8)
        try data.write(to: url)
        return data
    }

    private func digest(_ data: Data) -> String { "sha256:" + SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }

    @discardableResult
    private func addWork(_ citekey: String, attachments: [String], sources: [String] = []) throws -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T \(citekey)",
                      attachments: attachments.map { AttachmentRef(kind: .zotero, path: $0) })
        e.akashic.sources = sources
        _ = try store.writeEntry(e)
        return e
    }

    private func commit() { StoreGitCommit.commitAll(root) }
    private func work(_ citekey: String) throws -> Entry { try XCTUnwrap(store.load().entries.first { $0.citekey == citekey }) }
    private func blob(_ d: String) -> URL {
        let hex = String(d.dropFirst("sha256:".count))
        return root.appendingPathComponent("sources/\(hex.prefix(2))/\(hex.dropFirst(2))")
    }
    private func indexLines() -> [String] {
        let text = (try? String(contentsOf: root.appendingPathComponent("sources/index.jsonl"), encoding: .utf8)) ?? ""
        return text.split(separator: "\n").map(String.init)
    }
    private func entryFileBytes(_ e: Entry) throws -> Data { try Data(contentsOf: store.entityURL(id: e.id)) }
    private func run(apply: Bool, citekeys: [String]? = nil) throws -> ZoteroAttachmentCopyReport {
        try service.copyZoteroAttachments(zoteroDb: dbPath, citekeys: citekeys, apply: apply,
                                          now: Date(timeIntervalSince1970: 1_790_000_000))
    }

    // MARK: 乾跑

    func testDryRunListsThePlanAndWritesNothing() throws {
        let bytes = try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 the paper")
        let e = try addWork("a2025", attachments: ["storage/ABCD1234/paper.pdf"])
        commit()
        let before = try entryFileBytes(e)
        let r = try run(apply: false)
        XCTAssertFalse(r.applied)
        XCTAssertEqual(r.planned.map(\.digest), [digest(bytes)])
        XCTAssertEqual(r.planned.first?.citekey, "a2025")
        XCTAssertEqual(r.planned.first?.bytes, bytes.count)
        XCTAssertEqual(r.planned.first?.mediaType, "application/pdf")
        XCTAssertNil(r.applyRefusal, "gate 都過時乾跑不預告拒絕：\(r.applyRefusal ?? "")")
        XCTAssertEqual(try entryFileBytes(e), before, "乾跑零寫入")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blob(digest(bytes)).path), "乾跑不存檔")
        XCTAssertEqual(indexLines().count, 0)
    }

    // MARK: 實跑

    func testApplyCopiesBytesLinksTheDigestAndKeepsTheZoteroReference() throws {
        let bytes = try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 the paper")
        try addWork("a2025", attachments: ["storage/ABCD1234/paper.pdf"])
        commit()
        let r = try run(apply: true)
        let d = digest(bytes)
        XCTAssertTrue(r.applied)
        XCTAssertEqual(r.written, ["a2025"])
        XCTAssertEqual(r.exclusionVerified, true, "store 在 git 裡：排除驗證真的跑了")
        XCTAssertEqual(try Data(contentsOf: blob(d)), bytes, "位元組原樣複製進 sources/")
        let e = try work("a2025")
        XCTAssertEqual(e.akashic.sources, [d], "digest 連到記錄的 akashic.sources")
        XCTAssertEqual(e.attachments, [AttachmentRef(kind: .zotero, path: "storage/ABCD1234/paper.pdf")],
                       "zotero: 附件記錄原樣保留——它由 pull 管理（整批以 Zotero 為準），改寫它下一次 pull 就被還原；它同時就是這份副本的來源記錄")
        // 取得記錄：來源指向 Zotero 的 storage 路徑，取得方式自成一類
        let line = try XCTUnwrap(indexLines().first)
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any])
        XCTAssertEqual(obj["content"] as? String, d)
        XCTAssertEqual(obj["bytes"] as? Int, bytes.count)
        XCTAssertEqual(obj["media-type"] as? String, "application/pdf")
        XCTAssertEqual(obj["origin"] as? String, "zotero:storage/ABCD1234/paper.pdf")
        XCTAssertEqual(obj["acquisition"] as? String, "zotero-storage-copy")
        XCTAssertTrue((obj["note"] as? String)?.contains("a2025") == true, "note 記得是哪一筆 work、由哪個命令複製：\(obj)")
    }

    /// 可重跑：第二次沒有新東西——記錄檔位元組不變、index 不多一行、報告把已連過的列在 `alreadyLinked`。
    func testRerunIsANoOp() throws {
        let bytes = try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 the paper")
        try addWork("a2025", attachments: ["storage/ABCD1234/paper.pdf"])
        commit()
        _ = try run(apply: true)
        commit()
        let e = try work("a2025")
        let fileBefore = try entryFileBytes(e)
        let again = try run(apply: true)
        XCTAssertEqual(again.planned, [])
        XCTAssertEqual(again.alreadyLinked.map(\.digest), [digest(bytes)])
        XCTAssertEqual(again.written, [])
        XCTAssertEqual(try entryFileBytes(e), fileBefore, "沒有新東西就不寫")
        XCTAssertEqual(indexLines().count, 1, "index 不重複 append")
    }

    /// 兩筆 work 記著同一個 Zotero 附件（同一篇的個人與群組兩份——#605 的場景）：兩邊各連自己的 `akashic.sources`，blob 與 index 條目只有一份。
    func testTwoWorksSharingTheSameAttachmentStoreTheBlobOnce() throws {
        let bytes = try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 shared")
        try addWork("a2025", attachments: ["storage/ABCD1234/paper.pdf"])
        try addWork("b2025", attachments: ["storage/ABCD1234/paper.pdf"])
        commit()
        let r = try run(apply: true)
        XCTAssertEqual(r.written.sorted(), ["a2025", "b2025"])
        XCTAssertEqual(try work("a2025").akashic.sources, [digest(bytes)])
        XCTAssertEqual(try work("b2025").akashic.sources, [digest(bytes)])
        XCTAssertEqual(indexLines().count, 1, "同一份內容只記一條取得記錄（先到的為準）")
        XCTAssertEqual(r.blobsAlreadyStored, 1, "第二筆遇到已存的 blob：報出來，不重複寫")
    }

    /// 前一次跑到一半（blob 已存、work 還沒連）再跑：只補連結，不重存、不重複 index。
    func testResumesAfterABlobWasStoredButTheWorkWasNotLinked() throws {
        let bytes = try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 half done")
        try addWork("a2025", attachments: ["storage/ABCD1234/paper.pdf"])
        commit()
        _ = try store.storeSource(bytes, provenance: LibraryStore.SourceProvenance(
            mediaType: "application/pdf", retrieved: "2026-09-01T00:00:00Z", origin: "earlier run", acquisition: "manual"))
        let r = try run(apply: true)
        XCTAssertEqual(r.written, ["a2025"])
        XCTAssertEqual(try work("a2025").akashic.sources, [digest(bytes)])
        XCTAssertEqual(indexLines().count, 1, "既有的取得記錄不重寫")
        XCTAssertEqual(r.blobsAlreadyStored, 1)
    }

    /// 同一筆 work 記了兩個內容相同的附件（同一個檔被複製進兩個 KEY）：digest 只連一次。
    func testTwoAttachmentsWithIdenticalBytesLinkOneDigest() throws {
        let bytes = try put("storage/ABCD1234/a.pdf", "%PDF same bytes")
        try put("storage/WXYZ5678/b.pdf", "%PDF same bytes")
        try addWork("a2025", attachments: ["storage/ABCD1234/a.pdf", "storage/WXYZ5678/b.pdf"])
        commit()
        let r = try run(apply: true)
        XCTAssertEqual(try work("a2025").akashic.sources, [digest(bytes)])
        XCTAssertEqual(r.planned.count, 1)
        XCTAssertEqual(r.alreadyLinked.count, 1, "第二個附件內容相同——視為已連")
    }

    func testANewAttachmentIsAppendedAfterExistingSources() throws {
        let old = "sha256:" + String(repeating: "ab", count: 32)
        let bytes = try put("storage/ABCD1234/new.pdf", "%PDF new")
        try addWork("a2025", attachments: ["storage/ABCD1234/new.pdf"], sources: [old])
        commit()
        _ = try run(apply: true)
        XCTAssertEqual(try work("a2025").akashic.sources, [old, digest(bytes)], "追加在後、既有的不動")
    }

    // MARK: 逐筆略過（具名，其餘照跑）

    func testUnusableAttachmentsAreSkippedByNameAndTheRestProceed() throws {
        let good = try put("storage/GOODKEY1/ok.pdf", "%PDF good")
        try put("storage/EMPTYKEY/e.pdf", "")
        try FileManager.default.createDirectory(at: zdir.appendingPathComponent("storage/DIRKEY01/d.pdf"), withIntermediateDirectories: true)
        try put("secret.txt", "outside storage")
        try addWork("ok2025", attachments: ["storage/GOODKEY1/ok.pdf"])
        try addWork("bad2025", attachments: ["storage/GONEKEY1/gone.pdf", "storage/EMPTYKEY/e.pdf", "storage/DIRKEY01/d.pdf",
                                              "storage/../secret.txt", "/etc/hosts"])
        commit()
        let r = try run(apply: true)
        XCTAssertEqual(r.written, ["ok2025"])
        XCTAssertEqual(try work("ok2025").akashic.sources, [digest(good)])
        XCTAssertEqual(try work("bad2025").akashic.sources, [], "沒有可複製的附件就不動記錄")
        let reasons = Dictionary(r.skipped.map { ($0.path, $0.reason) }, uniquingKeysWith: { first, _ in first })
        XCTAssertEqual(reasons["storage/GONEKEY1/gone.pdf"], .file(.missing))
        XCTAssertEqual(reasons["storage/EMPTYKEY/e.pdf"], .file(.empty))
        XCTAssertEqual(reasons["storage/DIRKEY01/d.pdf"], .file(.notRegularFile("目錄")))
        XCTAssertEqual(reasons["storage/../secret.txt"], .file(.badPath))
        XCTAssertEqual(reasons["/etc/hosts"], .file(.badPath))
        XCTAssertEqual(r.skipped.count, 5)
    }

    func testWorksWithoutZoteroAttachmentsAreNotTouched() throws {
        let e = try addWork("plain2025", attachments: [])
        commit()
        let before = try entryFileBytes(e)
        let r = try run(apply: true)
        XCTAssertEqual(r.considered, 0)
        XCTAssertEqual(try entryFileBytes(e), before)
    }

    /// citekey 重複的記錄無法唯一定位（#627）：具名略過，其餘照跑。
    func testUnlocatableWorksAreSkippedByName() throws {
        try put("storage/DUPKEY01/x.pdf", "%PDF dup")
        let good = try put("storage/GOODKEY1/ok.pdf", "%PDF good")
        try addWork("dup2025", attachments: ["storage/DUPKEY01/x.pdf"])
        try addWork("dup2025", attachments: ["storage/DUPKEY01/x.pdf"])
        try addWork("ok2025", attachments: ["storage/GOODKEY1/ok.pdf"])
        commit()
        let r = try run(apply: true)
        XCTAssertEqual(r.unlocatable, ["dup2025"])
        XCTAssertEqual(r.written, ["ok2025"])
        XCTAssertEqual(try work("ok2025").akashic.sources, [digest(good)])
        XCTAssertFalse(FileManager.default.fileExists(atPath: blob(digest(Data("%PDF dup".utf8))).path), "無法定位的記錄連 blob 都不存")
    }

    func testCitekeyFilterRestrictsTheRunAndNamesUnknownOnes() throws {
        try put("storage/AAAAAAA1/a.pdf", "%PDF a")
        let b = try put("storage/BBBBBBB1/b.pdf", "%PDF b")
        try addWork("a2025", attachments: ["storage/AAAAAAA1/a.pdf"])
        try addWork("b2025", attachments: ["storage/BBBBBBB1/b.pdf"])
        commit()
        let r = try run(apply: true, citekeys: ["b2025", "ghost2025"])
        XCTAssertEqual(r.written, ["b2025"])
        XCTAssertEqual(r.notInStore, ["ghost2025"])
        XCTAssertEqual(try work("a2025").akashic.sources, [], "沒被點名的不動")
        XCTAssertEqual(try work("b2025").akashic.sources, [digest(b)])
    }

    // MARK: 閘（整批拒絕、零寫入）

    /// `sources/` 沒被版控排除：存檔是第三方逐字位元組，不得進 remote——fail-closed。乾跑預告、實跑拒絕、什麼都不存。
    func testSourcesNotExcludedByGitRefusesTheWholeBatchBeforeAnyWrite() throws {
        let bytes = try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 the paper")
        let e = try addWork("a2025", attachments: ["storage/ABCD1234/paper.pdf"])
        try "# 沒有 sources/ 的排除\n".write(to: root.appendingPathComponent(".gitignore"), atomically: true, encoding: .utf8)
        commit()
        let dry = try run(apply: false)
        XCTAssertTrue(dry.applyRefusal?.contains("sources") == true, "乾跑要預告實跑會被拒：\(dry.applyRefusal ?? "nil")")
        let before = try entryFileBytes(e)
        XCTAssertThrowsError(try run(apply: true)) { err in
            XCTAssertTrue(String(describing: err).contains("sources"), "\(err)")
        }
        XCTAssertEqual(try entryFileBytes(e), before, "零寫入")
        XCTAssertFalse(FileManager.default.fileExists(atPath: blob(digest(bytes)).path), "被拒時不留 blob")
        XCTAssertEqual(indexLines().count, 0)
    }

    /// 記錄檔有未 commit 的修改：實跑要求它已在 git 裡 commit、乾淨（它改寫既有記錄，舊版只剩 git 那一份）。
    func testUncommittedWorkFileRefusesTheWholeBatch() throws {
        let bytes = try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 the paper")
        let e = try addWork("a2025", attachments: ["storage/ABCD1234/paper.pdf"])
        commit()
        var edited = e
        edited.title = "uncommitted edit"
        _ = try store.writeEntry(edited)
        let dry = try run(apply: false)
        XCTAssertTrue(dry.applyRefusal?.contains("commit") == true, "\(dry.applyRefusal ?? "nil")")
        let before = try entryFileBytes(e)
        XCTAssertThrowsError(try run(apply: true)) { err in
            XCTAssertTrue(String(describing: err).contains("commit"), "\(err)")
        }
        XCTAssertEqual(try entryFileBytes(e), before)
        XCTAssertFalse(FileManager.default.fileExists(atPath: blob(digest(bytes)).path))
    }

    /// 只有真的要被改寫的記錄才要求 clean：沒有新東西的記錄（已全連過）有未 commit 的修改，不擋整批。
    func testGateOnlyCoversWorksThatWillBeRewritten() throws {
        let done = try put("storage/DONEKEY1/d.pdf", "%PDF done")
        try put("storage/TODOKEY1/t.pdf", "%PDF todo")
        let d = try addWork("done2025", attachments: ["storage/DONEKEY1/d.pdf"], sources: [digest(done)])
        try addWork("todo2025", attachments: ["storage/TODOKEY1/t.pdf"])
        commit()
        var edited = d
        edited.title = "uncommitted, but nothing to write here"
        _ = try store.writeEntry(edited)
        let r = try run(apply: true)
        XCTAssertEqual(r.written, ["todo2025"])
    }

    func testStoreOutsideGitRefusesApplyButDryRunStillReports() throws {
        try put("storage/ABCD1234/paper.pdf", "%PDF-1.7 the paper")
        try addWork("a2025", attachments: ["storage/ABCD1234/paper.pdf"])
        // 沒有 commit、也沒有 git init——store 不在 git 工作樹裡
        let dry = try run(apply: false)
        XCTAssertEqual(dry.planned.count, 1)
        XCTAssertNotNil(dry.applyRefusal, "store 不在 git 裡：實跑會被拒，乾跑要預告")
        XCTAssertThrowsError(try run(apply: true))
    }

    func testMissingZoteroDatabaseOrStorageIsANamedError() throws {
        XCTAssertThrowsError(try service.copyZoteroAttachments(zoteroDb: base.appendingPathComponent("nope/zotero.sqlite").path,
                                                               citekeys: nil, apply: false)) { err in
            XCTAssertTrue(String(describing: err).contains("zotero.sqlite"), "\(err)")
        }
        let bare = base.appendingPathComponent("bare")
        try FileManager.default.createDirectory(at: bare, withIntermediateDirectories: true)
        try Data().write(to: bare.appendingPathComponent("zotero.sqlite"))
        XCTAssertThrowsError(try service.copyZoteroAttachments(zoteroDb: bare.appendingPathComponent("zotero.sqlite").path,
                                                               citekeys: nil, apply: false)) { err in
            XCTAssertTrue(String(describing: err).contains("storage"), "資料目錄沒有 storage/：\(err)")
        }
    }

    /// 內容在計畫之後、複製之前被換掉：以實際存進去的為準——digest 對不上就略過那個檔、不寫連結，並具名（`changedDuringRun`）。
    /// 測試接縫是 service 的 internal 變體 `afterPlanning`（在計畫算完、第一次寫入之前呼叫），對外的 `copyZoteroAttachments` 沒有這個參數。
    func testAFileChangedBetweenPlanAndCopyIsSkippedNotMislinked() throws {
        try put("storage/STABLEK1/s.pdf", "%PDF stable")
        try put("storage/CHANGEK1/c.pdf", "%PDF before")
        try addWork("s2025", attachments: ["storage/STABLEK1/s.pdf"])
        try addWork("c2025", attachments: ["storage/CHANGEK1/c.pdf"])
        commit()
        let r = try service.copyZoteroAttachments(zoteroDb: dbPath, citekeys: nil, apply: true,
                                                  now: Date(timeIntervalSince1970: 1_790_000_000),
                                                  afterPlanning: { try self.put("storage/CHANGEK1/c.pdf", "%PDF AFTER the plan was made") })
        XCTAssertEqual(r.written, ["s2025"], "換掉內容的那一筆不寫連結")
        XCTAssertEqual(try work("c2025").akashic.sources, [], "不把計畫時的 digest 連到實際存下的另一份內容上")
        XCTAssertEqual(r.skipped.map(\.path), ["storage/CHANGEK1/c.pdf"])
        XCTAssertEqual(r.skipped.first?.reason, .changedDuringRun)
    }
}
