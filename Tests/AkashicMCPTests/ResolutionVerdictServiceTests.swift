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
        XCTAssertEqual(refs.map(\.value), ["work:a2020x :: Che Cheng"])
        // entry 完全不動——reject 是 verdict，不是套用
        let e = try LibraryStore(root: root).load().entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(e.authors, [.literal("Che Cheng")])
        // 重跑 resolve：該配對從 active candidates 消失（resolver 跳過），
        // 沉底進頂層 `rejected` 陣列（verify 修訂：獨立成段，candidates 形狀均勻）
        let out = try json(try service.resolvePeople(apply: nil))
        let active = out["candidates"] as! [[String: Any]]
        XCTAssertEqual(active.map { $0["id"] as? String }, ["b2021y:0"])
        let sunk = out["rejected"] as! [[String: Any]]
        XCTAssertEqual(sunk.map { $0["citekey"] as? String }, ["a2020x"])
    }

    func testApplyWritesConfirmedReferenceInSameOperation() throws {
        _ = try service.resolvePeople(apply: ["a2020x:0"])
        let p = try person()
        let refs = p.references.filter { $0.field == "resolution-confirmed" }
        XCTAssertEqual(refs.map(\.value), ["work:a2020x :: Che Cheng"])
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

    func testCountsSinkSectionPendingTotalAndNoRatioKeys() throws {
        _ = try service.resolvePeople(apply: nil, reject: ["a2020x:0"])
        let out = try json(try service.resolvePeople(apply: nil))
        // candidates 形狀均勻（每列都有 id/reason），已否決獨立成段帶標記與分母
        let rows = out["candidates"] as! [[String: Any]]
        XCTAssertEqual(rows.count, 1)
        XCTAssertEqual(rows[0]["citekey"] as? String, "b2021y")
        XCTAssertNotNil(rows[0]["id"]); XCTAssertNotNil(rows[0]["reason"])
        XCTAssertEqual(out["candidateTotal"] as? Int, 1, "candidateTotal 與陣列一致")
        let sunk = out["rejected"] as! [[String: Any]]
        XCTAssertEqual(sunk.count, 1)
        XCTAssertEqual(sunk[0]["citekey"] as? String, "a2020x")
        XCTAssertEqual(sunk[0]["verdict"] as? String, "rejected")
        XCTAssertNil(sunk[0]["id"], "已否決列不可攜 apply 把手")
        XCTAssertEqual(out["rejectedTotal"] as? Int, 1)
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

    /// verify A（4/4 席 + DA）：apply 與 reject 同呼叫曾以 stale 快照互相蓋寫——
    /// reject 剛寫的 verdict 被 confirm 的整檔改寫抹掉，回應還宣稱兩者都成功。
    /// 修法是禁止（DA (a)：組合語意要能按腿回報部分失敗，是它自己的設計題）。
    func testApplyAndRejectInOneCallIsRefused() throws {
        XCTAssertThrowsError(try service.resolvePeople(apply: ["b2021y:0"],
                                                       reject: ["a2020x:0"]))
        XCTAssertTrue(try person().references.isEmpty, "拒絕時不得有任何寫入")
    }

    /// verify F／S-6：重複 rowID 曾寫出 N 筆相同 verdict、計數灌水 N 倍。
    func testDuplicateRowIDsWriteExactlyOneVerdict() throws {
        _ = try service.resolvePeople(apply: nil,
                                      reject: ["a2020x:0", "a2020x:0", "a2020x:0"])
        let refs = try person().references.filter { $0.field == "resolution-rejected" }
        XCTAssertEqual(refs.count, 1, "同配對只落一筆：\(refs)")
        let out = try json(try service.resolvePeople(apply: nil))
        let counts = (out["candidates"] as! [[String: Any]])[0]["counts"] as! [String: Any]
        XCTAssertEqual(counts["rejected"] as? Int, 1, "計數不得灌水")
    }

    /// verify NEW-2：format < 8 的 store——reject 硬擋（指路訊息）、apply 照常
    /// 歸戶但 verdict 跳過並揭露。
    func testFormatGateRefusesRejectAndSkipsConfirm() throws {
        try StoreVersion.write(root: root, format: 7)
        XCTAssertThrowsError(try service.resolvePeople(apply: nil, reject: ["a2020x:0"])) { e in
            let msg = (e as? LocalizedError)?.errorDescription ?? "\(e)"
            XCTAssertTrue(msg.contains("format") && msg.contains("8"), msg)
        }
        let out = try json(try service.resolvePeople(apply: ["a2020x:0"]))
        XCTAssertNotNil(out["verdictsSkipped"], "verdict 跳過必須揭露：\(out)")
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.entries.first { $0.citekey == "a2020x" }?.authors,
                       [.key("cheng-che")], "apply 本身照常")
        XCTAssertTrue(load.people.first { $0.key == "cheng-che" }!.references.isEmpty,
                      "format < 8 不落 verdict（writePerson 閘的前置降級）")
    }

    /// verify G：malformed verdict（手改檔）**不得靜默**。store 閘對 verdict value
    /// 是 strict（decode 即驗）——手改壞的檔整筆 quarantine（doctor 可見、記錄從
    /// 查詢消失），比「載入後默默不計數不抑制」loud 得多。ledger 的 malformed
    /// 通道與 `verdictMalformed` payload 保留為縱深防禦（decode 閘之外的來源）。
    func testMalformedVerdictQuarantinesLoudly() throws {
        var p = try person()
        p.references.append(ProvenanceReference(
            field: "resolution-rejected", value: "work:a2020x :: Che Cheng",
            kind: .judgement(statement: "ok", restsOn: [])))
        try LibraryStore(root: root).writePerson(p)
        // 直接改磁碟成 malformed（繞過寫入閘——模擬手改／他庫匯入）
        let store = LibraryStore(root: root)
        let url = store.entityURL(id: p.id)
        let yaml = try String(contentsOf: url, encoding: .utf8)
            .replacingOccurrences(of: "work:a2020x :: Che Cheng", with: "no-separator-here")
        try yaml.write(to: url, atomically: true, encoding: .utf8)
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.quarantined.count, 1,
                       "解析不了的 verdict＝整筆 quarantine（loud），不是默默略過")
        XCTAssertTrue(load.people.isEmpty)
    }
}
