import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicEntity
@testable import AkashicMCPKit

/// #232 task 4.1/4.2：resolve 面的 verdict 動作（design D6）與呈現形狀（design D7）。
/// reject 顯式、apply 同動作寫 confirmed、計數三態、已否決沉底不隱藏、無比率欄位。
final class ResolutionVerdictServiceTests: XCTestCase {
    var root: URL!
    var service: AkashicService!
    var fakeHome: URL!
    var env: [String: String] { ["AKASHIC_HOME": fakeHome.path] }

    override func setUpWithError() throws {
        fakeHome = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-home-\(UUID().uuidString)")
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-verdict-\(UUID().uuidString)")
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        for sub in ["entries", "people"] {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(sub), withIntermediateDirectories: true)
        }
        // 兩個候選：a2020x 與 b2021y 都有 literal "Che Cheng" → 各對到 cheng-che
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: "article",
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
        try store.writeEntry(Entry(id: UUID(), citekey: "b2021y", type: "article",
                                   title: "U", authors: [.literal("Che Cheng")], date: "2021"))
        try store.writePerson(Person(key: "cheng-che", names: ["Che Cheng"]))
        service = AkashicService(root: root, environment: env)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
        try? FileManager.default.removeItem(at: fakeHome)
    }

    private func json(_ s: String) throws -> [String: Any] {
        try JSONSerialization.jsonObject(with: Data(s.utf8)) as! [String: Any]
    }

    private func person() throws -> Person {
        try LibraryStore(root: root).load().people.first { $0.key == "cheng-che" }!
    }

    // MARK: - task 4.1：reject 寫 verdict、entry 不動；apply 同動作寫 confirmed

    func testRejectWritesVerdictAndLeavesEntryUntouched() throws {
        _ = try service.resolvePeople(apply: nil, reject: ["a2020x:0"])
        let p = try person()
        let refs = p.references.filter { $0.field == "resolution-rejected" }
        XCTAssertEqual(refs.map(\.value), ["a2020x :: Che Cheng"])
        // entry 完全不動——reject 是 verdict，不是套用
        let e = try LibraryStore(root: root).load().entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(e.authors, [.literal("Che Cheng")])
        // 重跑 resolve：該配對從 active candidates 消失（resolver 跳過）
        let out = try json(try service.resolvePeople(apply: nil))
        let active = (out["candidates"] as! [[String: Any]]).filter { $0["verdict"] == nil }
        XCTAssertEqual(active.map { $0["id"] as? String }, ["b2021y:0"])
    }

    func testApplyWritesConfirmedReferenceInSameOperation() throws {
        _ = try service.resolvePeople(apply: ["a2020x:0"])
        let p = try person()
        let refs = p.references.filter { $0.field == "resolution-confirmed" }
        XCTAssertEqual(refs.map(\.value), ["a2020x :: Che Cheng"])
        let e = try LibraryStore(root: root).load().entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(e.authors, [.key("cheng-che")], "apply 的既有行為不變")
    }

    func testNoRowIDMeansNoWrites() throws {
        _ = try service.resolvePeople(apply: nil, reject: nil)
        _ = try service.resolvePeople(apply: nil, reject: [])
        XCTAssertTrue(try person().references.isEmpty, "無 rowID 不發生任何寫入")
    }

    func testRejectUnknownRowIDFailsLoud() throws {
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, reject: ["nope:9"]))
        XCTAssertTrue(try person().references.isEmpty)
    }

    // MARK: - task 4.2：呈現形狀（design D7）

    func testCountsSinkOrderingPendingTotalAndNoRatioKeys() throws {
        _ = try service.resolvePeople(apply: nil, reject: ["a2020x:0"])
        let out = try json(try service.resolvePeople(apply: nil))
        let rows = out["candidates"] as! [[String: Any]]
        // 沉底不隱藏：active（b2021y）在前，已否決（a2020x）沉底、帶標記
        XCTAssertEqual(rows.count, 2)
        XCTAssertEqual(rows[0]["citekey"] as? String, "b2021y")
        XCTAssertNil(rows[0]["verdict"])
        XCTAssertEqual(rows[1]["citekey"] as? String, "a2020x")
        XCTAssertEqual(rows[1]["verdict"] as? String, "rejected")
        XCTAssertNil(rows[1]["id"], "已否決列不可攜 apply 把手")
        // 三態計數掛在候選列上（該列所屬 rule 的計數）
        let counts = rows[0]["counts"] as! [String: Any]
        XCTAssertEqual(counts["confirmed"] as? Int, 0)
        XCTAssertEqual(counts["rejected"] as? Int, 1)
        XCTAssertEqual(counts["pending"] as? Int, 1)
        // 未處理量頂層可見（censoring 不可隱藏）
        XCTAssertEqual(out["pendingTotal"] as? Int, 1)
        // 形狀上不存在比率欄位——遞迴掃全部鍵名
        var keys: [String] = []
        func collect(_ v: Any) {
            if let d = v as? [String: Any] { d.forEach { keys.append($0.key); collect($0.value) } }
            if let a = v as? [Any] { a.forEach(collect) }
        }
        collect(out)
        for k in keys {
            let lower = k.lowercased()
            XCTAssertFalse(lower.contains("ratio") || lower.contains("percent")
                           || lower.contains("probability") || lower.contains("confidence"),
                           "形狀上不得有比率／機率欄位：\(k)")
        }
    }

    /// 已否決配對的 literal 已從 entry 移除 → 沉底列也不再出現（不是候選就無處沉）。
    func testStaleRejectionDropsOutOfListing() throws {
        _ = try service.resolvePeople(apply: nil, reject: ["a2020x:0"])
        var e = try LibraryStore(root: root).load().entries.first { $0.citekey == "a2020x" }!
        e.authors = [.literal("Someone Else")]
        try LibraryStore(root: root).writeEntry(e)
        let out = try json(try service.resolvePeople(apply: nil))
        let rows = out["candidates"] as! [[String: Any]]
        XCTAssertEqual(rows.map { $0["citekey"] as? String }, ["b2021y"],
                       "ledger 仍記得否決，但列表只呈現仍在觀測中的配對")
    }
}
