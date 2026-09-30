import XCTest
import CryptoKit
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #703 R2 verify 第 2、17 則：同一筆 work 裡內容相同的第二個附件（follower）跟著第一個（lead）的**最終**結果走。
///
/// R2 之前第二個在計畫階段就進了「已連過」：第一個之後在實跑時補存失敗、計畫之後內容變了、或 work 寫不進去，同一份報告同時說同一份內容
/// 「完成」與「沒完成」。R1 的修正只涵蓋計畫階段的不符與判不出來。
///
/// 假的 Zotero 資料目錄與假 home；store 在真 git 裡（可回溯閘要它）。
final class ZoteroAttachmentFollowerTests: XCTestCase {
    private var base: URL!
    private var root: URL!
    private var home: URL!
    private var zdir: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        base = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-zfollow-\(UUID().uuidString)")
        root = base.appendingPathComponent("store")
        home = base.appendingPathComponent("home")
        zdir = base.appendingPathComponent("zotero")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: zdir.appendingPathComponent("storage"), withIntermediateDirectories: true)
        try Data().write(to: zdir.appendingPathComponent("zotero.sqlite"))
        try LibraryStore(root: root, key: nil, environment: ["AKASHIC_HOME": home.path]).ensureLayout()
        service = AkashicService(root: root, key: nil, environment: ["AKASHIC_HOME": home.path])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: base) }

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
    private func addWork(_ citekey: String, attachments: [String], sources: [String] = []) throws {
        var e = Entry(id: UUID(), citekey: citekey, type: .periodicalArticle, title: "T \(citekey)",
                      attachments: attachments.map { AttachmentRef(kind: .zotero, path: $0) })
        e.akashic.sources = sources
        _ = try store.writeEntry(e)
    }
    private func run(apply: Bool, afterPlanning: (() throws -> Void)? = nil,
                     beforeStore: ((ZoteroAttachmentCopyReport.Item) throws -> Void)? = nil) throws -> ZoteroAttachmentCopyReport {
        try service.copyZoteroAttachments(zoteroDb: zdir.appendingPathComponent("zotero.sqlite").path, citekeys: nil, apply: apply,
                                          now: Date(timeIntervalSince1970: 1_790_000_000),
                                          afterPlanning: afterPlanning, beforeStore: beforeStore)
    }

    /// 已連過、本機缺位元組、兩個內容相同的附件：第一個補存時 I/O 失敗——第二個不算已連過，跟著列在補存失敗。
    /// 乾跑時照舊是計畫：第一個要補存、第二個跟著它。
    func testALinkedFollowerIsNotDoneWhenTheLeadsRestoreFails() throws {
        let bytes = try put("storage/ABCD1234/a.pdf", "%PDF same bytes, restore fails")
        try put("storage/WXYZ5678/b.pdf", "%PDF same bytes, restore fails")
        try addWork("a2025", attachments: ["storage/ABCD1234/a.pdf", "storage/WXYZ5678/b.pdf"], sources: [digest(bytes)])
        StoreGitCommit.commitAll(root)
        let dry = try run(apply: false)
        XCTAssertEqual(dry.restoredLocally.map(\.path), ["storage/ABCD1234/a.pdf"])
        XCTAssertEqual(dry.alreadyLinked.map(\.path), ["storage/WXYZ5678/b.pdf"], "乾跑：跟著第一個的計畫")
        let r = try run(apply: true, beforeStore: { item in
            if item.path == "storage/ABCD1234/a.pdf" { throw CocoaError(.fileWriteOutOfSpace) }
        })
        XCTAssertEqual(r.alreadyLinked, [], "第一個沒補存成功——第二個不得報成已連過")
        XCTAssertEqual(r.restoredLocally, [])
        XCTAssertEqual(Set(r.restoreFailed.map(\.item.path)), ["storage/ABCD1234/a.pdf", "storage/WXYZ5678/b.pdf"])
    }

    /// 要新連、兩個內容相同的附件：第一個在存的時候 I/O 失敗（work 那一筆記進 `writeFailed`）——第二個不算已連過，列成
    /// `followsUnfinished`（原因不是它自己的檔，不照抄）。
    func testANewLinkFollowerIsNotDoneWhenTheLeadFails() throws {
        try put("storage/ABCD1234/a.pdf", "%PDF same bytes, new link fails")
        try put("storage/WXYZ5678/b.pdf", "%PDF same bytes, new link fails")
        try addWork("a2025", attachments: ["storage/ABCD1234/a.pdf", "storage/WXYZ5678/b.pdf"])
        StoreGitCommit.commitAll(root)
        let r = try run(apply: true, beforeStore: { item in
            if item.path == "storage/ABCD1234/a.pdf" { throw CocoaError(.fileWriteOutOfSpace) }
        })
        XCTAssertNotNil(r.writeFailed["a2025"])
        XCTAssertEqual(r.alreadyLinked, [], "第二個不得報成已連過")
        XCTAssertEqual(r.skipped.map(\.path), ["storage/WXYZ5678/b.pdf"])
        XCTAssertEqual(r.skipped.first?.reason, .followsUnfinished("storage/ABCD1234/a.pdf"))
        XCTAssertEqual(try store.load().entries.first?.akashic.sources, [])
    }

    /// 已連過、本機缺位元組：計畫之後第一個的檔被清空——第一個以 changedDuringRun 略過，第二個（它自己的檔沒變）不抄那個原因，
    /// 列成 `followsUnfinished`；不算已連過。
    func testAFollowerDoesNotInheritTheLeadsOwnFileReason() throws {
        let bytes = try put("storage/ABCD1234/a.pdf", "%PDF same bytes, lead changes")
        try put("storage/WXYZ5678/b.pdf", "%PDF same bytes, lead changes")
        try addWork("a2025", attachments: ["storage/ABCD1234/a.pdf", "storage/WXYZ5678/b.pdf"], sources: [digest(bytes)])
        StoreGitCommit.commitAll(root)
        let r = try run(apply: true, afterPlanning: {
            try Data("%PDF something else now".utf8).write(to: self.zdir.appendingPathComponent("storage/ABCD1234/a.pdf"))
        })
        XCTAssertEqual(r.alreadyLinked, [])
        let byPath = Dictionary(uniqueKeysWithValues: r.skipped.map { ($0.path, $0.reason) })
        XCTAssertEqual(byPath["storage/ABCD1234/a.pdf"], .changedDuringRun)
        XCTAssertEqual(byPath["storage/WXYZ5678/b.pdf"], .followsUnfinished("storage/ABCD1234/a.pdf"))
    }

    /// 正常情形不變：第一個補存成功，第二個是已連過。
    func testAFollowerIsDoneWhenTheLeadSucceeds() throws {
        let bytes = try put("storage/ABCD1234/a.pdf", "%PDF same bytes, all good")
        try put("storage/WXYZ5678/b.pdf", "%PDF same bytes, all good")
        try addWork("a2025", attachments: ["storage/ABCD1234/a.pdf", "storage/WXYZ5678/b.pdf"], sources: [digest(bytes)])
        StoreGitCommit.commitAll(root)
        let r = try run(apply: true)
        XCTAssertEqual(r.restoredLocally.map(\.path), ["storage/ABCD1234/a.pdf"])
        XCTAssertEqual(r.alreadyLinked.map(\.path), ["storage/WXYZ5678/b.pdf"])
        XCTAssertEqual(r.restoreFailed, [])
    }
}
