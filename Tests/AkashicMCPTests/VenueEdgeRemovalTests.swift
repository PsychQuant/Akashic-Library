import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO
@testable import AkashicEntity

/// #572：resolve-venues 的移除腿。契約見 `VenueEdgeRemoval.swift` 的檔頭；這裡逐條釘住：
/// 重複 key 邊可刪、唯一 key 邊拒絕（指向 demote）、literal 邊可刪、未 commit 拒絕、輸入錯整批拒絕零寫入、
/// 同一 work 多筆以原始 index 處理、單獨呼叫、理由只進報告且不截斷。
final class VenueEdgeRemovalTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-vedrop-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        _ = try service.addVenue(key: "some-journal", names: ["Some Journal"], type: "periodical", note: nil, issn: nil)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func work(_ venues: [VenueRef]) throws {
        // 同一筆 work 重寫時沿用 id——新 id 會造出兩筆同 citekey 的 work（#628 的形），測到的就不是本面
        let existing = try LibraryStore(root: root).load().entries.first { $0.citekey == "x2025" }
        var e = existing ?? Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = venues
        _ = try LibraryStore(root: root).writeEntry(e)
    }
    private func venues() throws -> [VenueRef] {
        try XCTUnwrap(LibraryStore(root: root).load().entries.first { $0.citekey == "x2025" }).venues
    }
    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func confirmedOnVenue() throws -> Int {
        let v = try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "some-journal" })
        return v.references.filter { $0.field == ProvenanceReference.resolutionConfirmedField }.count
    }
    private func addConfirmed() throws {
        let store = LibraryStore(root: root)
        var v = try XCTUnwrap(store.load().venues.first { $0.key == "some-journal" })
        v.references.append(ResolutionLedger.record(.confirmed, holderKind: .work, holder: "x2025", literal: "Some Journal",
                                                    rule: ResolutionLedger.venueRule, statement: "fixture"))
        try store.writeVenue(v)
    }

    func testDuplicateKeyEdgeCanBeDroppedAndTheVerdictStays() throws {
        try work([.key("some-journal"), .key("some-journal")])
        try addConfirmed()
        let reason = String(repeating: "理由", count: 400)   // 2,400 位元組：比 displaySafe 的預設上限長，不得被截
        let out = try json(try service.committed(root).resolveVenues(apply: nil, drop: ["x2025:1=\(reason)"]))
        XCTAssertEqual(try venues(), [.key("some-journal")])
        XCTAssertEqual(try confirmedOnVenue(), 1, "剩下的那條 key 邊仍實例化 confirmed verdict——不動它")
        let items = try XCTUnwrap(out["venueEdgesRemoved"] as? [[String: Any]])
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0]["id"] as? String, "x2025:1")
        XCTAssertEqual(items[0]["edge"] as? String, "key:some-journal")
        XCTAssertEqual(items[0]["reason"] as? String, reason, "理由只在報告裡，所以要全文")
        XCTAssertNil(out["emptied"])
        let e = try XCTUnwrap(LibraryStore(root: root).load().entries.first)
        XCTAssertFalse(e.validate().contains { $0.message.hasPrefix(Entry.duplicateVenueEdgePrefix) }, "warning 消失")
    }

    func testTheOnlyKeyEdgeIsRefusedAndPointsAtDemote() throws {
        try work([.key("some-journal"), .literal("Other")])
        try addConfirmed()
        XCTAssertThrowsError(try service.committed(root).resolveVenues(apply: nil, drop: ["x2025:0=錯的"])) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("--demote") && s.contains("唯一的 key 邊"), s)
        }
        XCTAssertEqual(try venues(), [.key("some-journal"), .literal("Other")], "零寫入")
        XCTAssertEqual(try confirmedOnVenue(), 1)
    }

    func testDroppingBothKeyEdgesIsRefused() throws {
        try work([.key("some-journal"), .key("some-journal")])
        XCTAssertThrowsError(try service.committed(root).resolveVenues(apply: nil, drop: ["x2025:0=a", "x2025:1=b"]))
        XCTAssertEqual(try venues(), [.key("some-journal"), .key("some-journal")], "零寫入")
    }

    func testLiteralEdgeCanBeDroppedAndEmptyingIsNamed() throws {
        try work([.literal("Some Journal")])
        let out = try json(try service.committed(root).resolveVenues(apply: nil, drop: ["x2025:0=出版社欄位推出來的，不是刊名"]))
        XCTAssertEqual(try venues(), [])
        XCTAssertEqual(out["emptied"] as? [String], ["x2025"])
        XCTAssertEqual((out["venueEdgesRemoved"] as? [[String: Any]])?.first?["edge"] as? String, "literal:Some Journal")
    }

    func testOriginalIndicesAreUsedForSeveralDropsOnOneWork() throws {
        try work([.literal("A"), .key("some-journal"), .key("some-journal"), .literal("B")])
        _ = try service.committed(root).resolveVenues(apply: nil, drop: ["x2025:3=b", "x2025:0=a"])
        XCTAssertEqual(try venues(), [.key("some-journal"), .key("some-journal")])
    }

    func testUncommittedWorkIsRefused() throws {
        try work([.literal("A"), .literal("B")])
        StoreGitCommit.commitAll(root)
        try work([.literal("A"), .literal("B"), .literal("C")])   // 未提交的修改
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, drop: ["x2025:0=a"])) { err in
            XCTAssertTrue(String(describing: err).contains("#572"), "\(err)")
        }
        XCTAssertEqual(try venues(), [.literal("A"), .literal("B"), .literal("C")], "零寫入")
    }

    func testMalformedInputRejectsTheWholeBatch() throws {
        try work([.literal("A"), .literal("B")])
        let svc = service.committed(root)
        for bad in [["x2025:0"],                 // 沒有理由
                    ["x2025:0=   "],             // 理由空白
                    ["x2025:0=a", "x2025:0=b"],  // 同一條邊兩次
                    ["x2025:5=a"],               // 越界
                    ["x2025=a"],                 // 不是 citekey:index
                    ["nope:0=a"],                // work 不存在
                    ["x2025:1=ok", "x2025:0=\(String(repeating: "x", count: 4_097))"]] {   // 第二筆理由過長，第一筆也不得寫
            XCTAssertThrowsError(try svc.resolveVenues(apply: nil, drop: bad), "\(bad)")
            XCTAssertEqual(try venues(), [.literal("A"), .literal("B")], "零寫入：\(bad)")
        }
    }

    func testDropIsCalledAlone() throws {
        try work([.literal("A"), .literal("B")])
        XCTAssertThrowsError(try service.committed(root).resolveVenues(apply: ["x2025:0"], drop: ["x2025:1=b"])) { err in
            XCTAssertTrue(String(describing: err).contains("單獨呼叫"), "\(err)")
        }
        XCTAssertThrowsError(try service.committed(root).resolveVenues(apply: nil, demote: ["x2025:0"], drop: ["x2025:1=b"]))
        XCTAssertEqual(try venues(), [.literal("A"), .literal("B")])
    }
}
