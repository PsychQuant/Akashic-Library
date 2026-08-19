import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO

/// #26：known 層演化語意的**現況釘樁**。
///
/// 這個測試檔不改行為——它把 v1.3 的實際行為釘住，讓 §5.9 的 v1.4 裁決有一個
/// 可對照的起點。實作 v1.4 時這些斷言會**故意失敗**，那正是它們的作用：
/// 逼實作者回來確認每一項都照裁決改了，而不是憑印象。
final class KnownLayerEvolutionTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-kle-\(UUID().uuidString)")
        store = LibraryStore(root: root)
        try store.ensureLayout()
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    /// **目錄由本 helper 保證**（#101）：fixture 繞過 store API 直接寫原始檔進 legacy 的
    /// `entries/`，而 `ensureLayout` 不再無條件建立它。
    private func writeEntry(_ name: String, extra: String) throws {
        try FileManager.default.createDirectory(at: store.entriesDir, withIntermediateDirectories: true)
        try """
        id: 11111111-1111-1111-1111-111111111111
        citekey: \(name)
        type: periodical-article
        title: T
        authors:
          - literal: X
        date: "2020"
        \(extra)
        """.write(to: store.entriesDir.appendingPathComponent("\(name).yaml"),
                  atomically: true, encoding: .utf8)
    }

    // MARK: - 現況：三個 strict 區塊整檔 quarantine（v1.4 要改成 tolerant）

    func testUnknownAttachmentKindQuarantinesWholeEntry_v13() throws {
        try writeEntry("att2020a", extra: "attachments:\n  - futurekind: files/x.pdf")
        let load = try store.load()
        XCTAssertEqual(load.quarantined.count, 1)
        XCTAssertEqual(load.entries.count, 0, "整筆書目資料因為一個未知 attachment kind 消失")
    }

    func testUnknownProvenanceFieldQuarantinesWholeEntry_v13() throws {
        try writeEntry("prov2020b",
                       extra: "provenance:\n  zotero_key: ABC\n  zotero_version: 1\n  future_field: v")
        XCTAssertEqual(try store.load().entries.count, 0)
    }

    /// R1 DA 指出「新 relation kind」是**最可能的 additive 演化**——而它的代價最大。
    func testUnknownRelationKindQuarantinesWholeEntry_v13() throws {
        try writeEntry("rel2020c", extra: "akashic:\n  relations:\n    futurekind: [other2020x]")
        XCTAssertEqual(try store.load().entries.count, 0,
                       "少一條邊 << 少一整筆——這是 §5.9 要改的不對稱")
    }

    /// 對照：tolerant 層的未知欄位只是 warning，記錄正常載入且欄位被保留。
    func testUnknownAkashicFieldIsToleratedAndPreserved() throws {
        try writeEntry("ok2020d", extra: "akashic:\n  tags: [t]\n  futureNested: v")
        let load = try store.load()
        XCTAssertEqual(load.entries.count, 1)
        XCTAssertEqual(load.unknownFieldFiles, ["entries/ok2020d.yaml"])
        let reencoded = try EntryYAML.encode(load.entries[0])
        XCTAssertTrue(reencoded.contains("futureNested"), "未知欄位必須逐字保留")
    }

    // MARK: - 已解決：shape 不符是 fail-loud，不是靜默剝除（#26 第 1 項）

    /// issue body 說「shape 不符 → decode 靜默略過 → re-encode 從磁碟抹除」。
    /// 那個**靜默資料遺失在 #23 的輪次中已修**——現在是 quarantine 且訊息明確。
    func testShapeMismatchIsFailLoudNotSilentStrip() throws {
        // fixture 手寫原始檔進 legacy 的 people/，需自己建目錄（#101）
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        try "id: 11111111-1111-4111-8111-111111111111\nkey: p-one\nnames: \"不是 sequence\"\norcid: \"0000-0001-2345-6789\"\n".write(
            to: store.peopleDir.appendingPathComponent("p-one.yaml"),
            atomically: true, encoding: .utf8)
        let load = try store.load()
        XCTAssertEqual(load.people.count, 0)
        XCTAssertEqual(load.quarantined.count, 1)
        XCTAssertTrue(load.quarantined[0].reason.contains("形狀不符"),
                      "訊息要說出是形狀問題：\(load.quarantined[0].reason)")
    }

    // MARK: - 保持 strict（v1.4 不改）

    /// `authors` 元素的 shape 未知**不是**「不理解」而是「無法安全處理」——
    /// 它決定這筆記錄的作者是誰。
    func testUnknownAuthorShapeStaysStrict() throws {
        try writeEntry("auth2020e", extra: "")
        try """
        id: 22222222-2222-2222-2222-222222222222
        citekey: auth2020e
        type: periodical-article
        title: T
        authors:
          - futureshape: someone
        date: "2020"
        """.write(to: store.entriesDir.appendingPathComponent("auth2020e.yaml"),
                  atomically: true, encoding: .utf8)
        XCTAssertEqual(try store.load().entries.count, 0, "作者的 shape 未知必須 fail-closed")
    }

    // MARK: - v9-only 語法的 format gate（#223）

    /// 同 ended（v6）／attested（v7）gate 的機制與理由：新語法在舊 store 上寫入即拒絕，
    /// 錯誤訊息要同時說出「需要幾」與「現在是幾」，否則使用者不知道要改什麼。
    func testCopyReferenceRefusedOnPreV9Store() throws {
        try StoreVersion.write(root: root, format: 8)
        var e = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T")
        e.akashic.sources = ["sha256:" + String(repeating: "ab", count: 32)]
        XCTAssertThrowsError(try store.writeEntry(e)) { error in
            let msg = "\(error)"
            XCTAssertTrue(msg.contains("9"), "要指出所需 format：\(msg)")
            XCTAssertTrue(msg.contains("8"), "也要說出本 store 現在是幾：\(msg)")
        }
    }

    func testCopyReferenceAcceptedOnV9Store() throws {
        try StoreVersion.write(root: root, format: 9)
        var e = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T")
        e.akashic.sources = ["sha256:" + String(repeating: "ab", count: 32)]
        XCTAssertNoThrow(try store.writeEntry(e))
    }

    /// 沒有副本清單的記錄不受 gate 影響——gate 只擋新語法，不改既有寫入路徑。
    func testEntryWithoutCopyReferenceStillWritesOnPreV9Store() throws {
        try StoreVersion.write(root: root, format: 7)
        let e = Entry(id: UUID(), citekey: "a2020b", type: .periodicalArticle, title: "T")
        XCTAssertNoThrow(try store.writeEntry(e))
    }

    /// 目前的精確 format 值（#131 verify 慣例：釘精確值防「意外多 bump 一次」，
    /// 每次刻意 bump 隨新 format 的測試搬家——#223 從 AttestedRangeTests 搬來，
    /// #323／#324 由 11 改為 12）。
    ///
    /// **函式名帶數字是刻意的**：改值時被迫連名字一起改，否則會留下
    /// 「`IsExactlyEleven` 斷言 12」這種名字與內容分岔——本 repo 已修過三次同型
    /// （CLAUDE.md 兩處摘要、`13 條` vs `14 條`）。
    func testCurrentSupportedFormatIsExactlyTwelve() {
        XCTAssertEqual(StoreVersion.supported, 12)
    }
}
