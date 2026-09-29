import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// b13f R1 verify 第 1 列：移除面一族（`update-entry` 的三條移除腿、`update-venue --remove-reference`／`--edit-name-segment`）寫檔之後 `LibraryIndex.rebuild()` 若擲錯，
/// 移除已經落盤、理由只在報告裡（使用者 2026-09-27 的裁決：不寫進 store），重試又會因為東西已經不在而被拒——報告不得跟著消失。
/// 選的做法是**呼叫回成功、報告多 `indexRebuilt: false`／`indexRebuildError`／`indexNote`**（不是擲錯並把報告塞進錯誤訊息——
/// 那條路上錯誤出口逐行截 400 字元，一段長理由會被截掉；見 `RemovalReportSupport.swift`）。
///
/// 強迫重建失敗的方法：service 帶 registry key、`AKASHIC_HOME` 指向一個**普通檔**——已註冊 store 的 index 住在 `<home>/index/<key>.sqlite`，
/// 建不出那個目錄，`rebuild()` 必擲；而寫檔本身（`entities/`）不受影響。
final class RemovalIndexRebuildFailureTests: XCTestCase {
    private var root: URL!
    private var blocker: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-rmrebuild-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        blocker = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-rmrebuild-home-\(UUID().uuidString)")
        try Data("not a directory".utf8).write(to: blocker)
    }
    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: blocker)
    }

    private var environment: [String: String] { ["AKASHIC_HOME": blocker.path] }
    /// 寫檔成功、index 重建必失敗的 service。
    private var failing: AkashicService { AkashicService(root: root, key: "rebuildfail", environment: environment) }
    private var working: AkashicService { AkashicService(root: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    /// 一千兩百個字元（3,600 位元組，在入口 4,096 位元組的上限之內）的理由：比錯誤出口逐行 400 字元的截斷長得多——報告若走錯誤路徑，這段會被截掉。
    private let longReason = String(repeating: "記錯了", count: 400)

    /// 前提：這個 service 的 index 重建真的會失敗（不是測試設定壞了才「看起來」通過）。
    func testPremiseTheRebuildActuallyFails() throws {
        // `LibraryIndex.rebuild()` 第一步就是建這個目錄（不是 AkashicIndex 的公開依賴，測試 target 沒有宣告它，所以直接驗機制）
        XCTAssertThrowsError(try FileManager.default.createDirectory(
            at: failing.store.indexURL.deletingLastPathComponent(), withIntermediateDirectories: true))
        XCTAssertNoThrow(try FileManager.default.createDirectory(
            at: working.store.indexURL.deletingLastPathComponent(), withIntermediateDirectories: true), "對照：沒有擋住的 service 建得出來")
    }

    private func assertReportSurvives(_ out: [String: Any], file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertEqual(out["indexRebuilt"] as? Bool, false, "\(out)", file: file, line: line)
        XCTAssertNotNil(out["indexRebuildError"] as? String, file: file, line: line)
        let note = out["indexNote"] as? String ?? ""
        XCTAssertTrue(note.contains("報告") && note.contains("akashic doctor"), note, file: file, line: line)
    }

    private func entryYAML(_ citekey: String) throws -> String {
        let store = LibraryStore(root: root)
        let e = try XCTUnwrap(try store.load().entries.first { $0.citekey == citekey })
        return String(decoding: try Data(contentsOf: store.entityURL(id: e.id)), as: UTF8.self)
    }

    func testRemoveZoteroSourceKeepsTheFullReportWhenTheIndexRebuildFails() throws {
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.provenance = Provenance(zoteroKey: "PRIM0001", zoteroVersion: 5, libraryID: 1)
        e.additionalProvenance = [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)]
        _ = try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        let out = try json(try failing.updateEntry(citekey: "x2025", removeFields: nil, removeZoteroSources: ["5:GRP00001=\(longReason)"], dryRun: false))
        assertReportSurvives(out)
        let item = try XCTUnwrap((out["zoteroSourceRemovals"] as? [[String: Any]])?.first)
        XCTAssertEqual(item["reason"] as? String, longReason, "理由只在報告裡，全文都要在")
        XCTAssertEqual(try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == "x2025" }).additionalProvenance, [], "移除已經落盤")
    }

    func testRemoveSourceKeepsTheFullReportWhenTheIndexRebuildFails() throws {
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.akashic.sources = [digest]
        _ = try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        let out = try json(try failing.updateEntry(citekey: "x2025", removeFields: nil, removeSources: ["\(digest)=\(longReason)"], dryRun: false))
        assertReportSurvives(out)
        XCTAssertEqual((out["sourcesRemoved"] as? [[String: Any]])?.first?["reason"] as? String, longReason)
        XCTAssertFalse(try entryYAML("x2025").contains(digest), "移除已經落盤")
    }

    func testRemoveFieldKeepsTheFullReportWhenTheIndexRebuildFails() throws {
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T", fields: ["abstract": "錯誤頁", "volume": "3"])
        e.provenance = nil
        _ = try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        let out = try json(try failing.updateEntry(citekey: "x2025", removeFields: ["abstract=\(longReason)"], dryRun: false))
        assertReportSurvives(out)
        XCTAssertEqual((out["fieldRemovals"] as? [[String: Any]])?.first?["reason"] as? String, longReason)
        XCTAssertFalse(try entryYAML("x2025").contains("錯誤頁"), "移除已經落盤")
    }

    func testRemoveVenueReferenceKeepsTheFullReportWhenTheIndexRebuildFails() throws {
        _ = try working.addVenue(key: "ampsy", names: ["American Psychologist"], type: "periodical", note: nil, issn: ["0003-066X"])
        _ = try working.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: [
            ["field": "issn", "value": "0003-066X", "kind": "retrieval", "url": "https://portal.issn.org/resource/ISSN/0003-066X",
             "retrieved": "2026-09-29", "status": 200, "content": "sha256:" + String(repeating: "ab", count: 32)] as [String: Any],
        ])
        StoreGitCommit.commitAll(root)
        let out = try json(try failing.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, removeReference: [
            ["field": "issn", "value": "0003-066X", "reason": longReason] as [String: Any],
        ]))
        assertReportSurvives(out)
        XCTAssertEqual((out["referencesRemoved"] as? [[String: Any]])?.first?["reason"] as? String, longReason)
        let v = try XCTUnwrap(try LibraryStore(root: root).load().venues.first { $0.key == "ampsy" })
        XCTAssertEqual(v.references.filter { $0.field == "issn" }.count, 0, "移除已經落盤")
    }

    /// #675：名字段的編輯面是同一族——改寫已經落盤、理由只在報告裡，index 重建失敗時報告不得消失；`indexNote` 說的是「改寫」而不是「移除」。
    func testEditNameSegmentKeepsTheFullReportWhenTheIndexRebuildFails() throws {
        _ = try working.addVenue(key: "sankhya", names: ["Sankhyā", "Sankhya Old"], type: "periodical", note: nil)
        StoreGitCommit.commitAll(root)
        let out = try json(try failing.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil, editNameSegment: [
            ["name": "Sankhyā", "set": ["start": "1933", "end": "1960"], "reason": longReason] as [String: Any],
        ]))
        assertReportSurvives(out)
        XCTAssertTrue((out["indexNote"] as? String)?.contains("改寫已經寫入磁碟") == true, "\(out)")
        XCTAssertEqual((out["nameSegments"] as? [[String: Any]])?.first?["reason"] as? String, longReason, "理由只在報告裡，全文都要在")
        let v = try XCTUnwrap(try LibraryStore(root: root).load().venues.first { $0.key == "sankhya" })
        XCTAssertEqual(v.names.entries.first { $0.value == "Sankhyā" }?.range.start, "1933", "改寫已經落盤")
    }

    /// 成功路徑的報告不變：不多出 `indexRebuilt` 之類的鍵。
    func testTheSuccessPathPayloadCarriesNoIndexKeys() throws {
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.provenance = Provenance(zoteroKey: "PRIM0001", zoteroVersion: 5, libraryID: 1)
        e.additionalProvenance = [Provenance(zoteroKey: "GRP00001", zoteroVersion: 9, libraryID: 5)]
        _ = try LibraryStore(root: root).writeEntry(e)
        StoreGitCommit.commitAll(root)
        let out = try json(try working.updateEntry(citekey: "x2025", removeFields: nil, removeZoteroSources: ["5:GRP00001=記錯了"], dryRun: false))
        XCTAssertNil(out["indexRebuilt"])
        XCTAssertNil(out["indexRebuildError"])
        XCTAssertNil(out["indexNote"])
    }
}
