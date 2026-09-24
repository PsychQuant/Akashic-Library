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
        try store.writeEntry(Entry(id: UUID(), citekey: "a2020x", type: .periodicalArticle,
                                   title: "T", authors: [.literal("Che Cheng")], date: "2020"))
        try store.writeEntry(Entry(id: UUID(), citekey: "b2021y", type: .periodicalArticle,
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

    // MARK: - #303 task 3.1：tier 欄（design D4，additive）

    func testCandidateRowsCarryTierAndSortByConfidence() throws {
        // 追加一筆 token 重排形：alias「Che Cheng」↔ literal「Cheng Che」
        try LibraryStore(root: root).writeEntry(
            Entry(id: UUID(), citekey: "c2022z", type: .periodicalArticle,
                  title: "V", authors: [.literal("Cheng Che")], date: "2022"))
        let out = try json(try service.resolvePeople(apply: nil))
        let rows = out["candidates"] as! [[String: Any]]
        let tierByCitekey = Dictionary(uniqueKeysWithValues:
            rows.map { ($0["citekey"] as! String, $0["tier"] as! String) })
        XCTAssertEqual(tierByCitekey["a2020x"], "exact")
        XCTAssertEqual(tierByCitekey["c2022z"], "reorder")
        // 信心降冪：exact 列全部排在 reorder 列之前（design D4）
        let tiers = rows.map { $0["tier"] as! String }
        XCTAssertEqual(tiers, ["exact", "exact", "reorder"])
    }

    // MARK: - R1-fix B8：id 釘 person（3-part），改指必須顯式失敗

    // #624：淘汰而得的唯一候選在 MCP 列表上是結構化欄位（兩面同一個事實）
    func testCandidateRowsCarryEliminatedPairings() throws {
        let plain = try json(try service.resolvePeople(apply: nil))
        let plainRows = plain["candidates"] as! [[String: Any]]
        XCTAssertFalse(plainRows.isEmpty)
        XCTAssertEqual(Set(plainRows.map { $0["eliminatedPairings"] as? Int }), [0],
                       "沒有否決史的候選帶 0：\(plainRows)")

        try LibraryStore(root: root).writePerson(Person(key: "cheng-che-2", names: ["Che Cheng"]))
        _ = try service.resolvePeople(apply: nil, refute: ["a2020x:0:cheng-che=機構不符"])
        let out = try json(try service.resolvePeople(apply: nil))
        let rows = out["candidates"] as! [[String: Any]]
        let a = rows.first { ($0["citekey"] as? String) == "a2020x" }
        XCTAssertEqual(a?["personKey"] as? String, "cheng-che-2", "\(rows)")
        XCTAssertEqual(a?["eliminatedPairings"] as? Int, 1, "\(rows)")
    }

    // #624 R1 verify：兩段 legacy id 只指到位置，沒點名人——對淘汰所得拒絕；三段形照寫
    func testTwoSegmentIDRefusesEliminatedSurvivorButPinnedIDWrites() throws {
        try LibraryStore(root: root).writePerson(Person(key: "cheng-che-2", names: ["Che Cheng"]))
        _ = try service.resolvePeople(apply: nil, refute: ["a2020x:0:cheng-che=機構不符"])
        XCTAssertThrowsError(try service.resolvePeople(apply: ["a2020x:0"])) { err in
            XCTAssertTrue("\(err)".contains("三段"), "\(err)")
        }
        let untouched = try LibraryStore(root: root).load().entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(untouched.authors, [.literal("Che Cheng")])

        _ = try service.resolvePeople(apply: ["a2020x:0:cheng-che-2"])
        let load = try LibraryStore(root: root).load()
        XCTAssertEqual(load.entries.first { $0.citekey == "a2020x" }!.authors, [.key("cheng-che-2")],
                       "三段形是顯式點名，照寫")
        let p = load.people.first { $0.key == "cheng-che-2" }!
        XCTAssertTrue(p.references.contains {
            $0.field == "resolution-confirmed" && $0.value == "work:a2020x :: Che Cheng" })
    }

    func testListedIDsArePinnedWithPersonKey() throws {
        let out = try json(try service.resolvePeople(apply: nil))
        let ids = (out["candidates"] as! [[String: Any]]).map { $0["id"] as! String }
        XCTAssertTrue(ids.contains("a2020x:0:cheng-che"), "\(ids)")
    }

    func testStalePinnedIDRefusesWhenNominationRetargeted() throws {
        // 釘住的 person 與現行提名不符 → 顯式拒絕、指名兩造（不安靜套到新對象）
        XCTAssertThrowsError(
            try service.resolvePeople(apply: ["a2020x:0:someone-else"])) { err in
            let msg = String(describing: err)
            XCTAssertTrue(msg.contains("已改指") && msg.contains("cheng-che"), msg)
        }
        // 沒有任何寫入發生
        let e = try LibraryStore(root: root).load().entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(e.authors, [.literal("Che Cheng")])
    }

    // MARK: - #308：references 的 append-only 寫入面

    func testUpdatePersonAppendsRetrievalReference() throws {
        let refs: [[String: Any]] = [[
            "field": "orcid",
            "kind": "retrieval",
            "url": "https://orcid.org/0000-0001-2345-6789",
            "retrieved": "2026-08-17",
            "status": 200,
            "content": "sha256:" + String(repeating: "ab", count: 32),
        ]]
        _ = try service.updatePerson(
            key: "cheng-che",
            fields: ["orcid": "0000-0001-2345-6789", "references": refs], dryRun: false)
        let p = try person()
        XCTAssertEqual(p.references.count, 1)
        XCTAssertEqual(p.references.first?.field, "orcid")
        // 冪等：同一筆再 append 不重複
        _ = try service.updatePerson(key: "cheng-che",
                                     fields: ["references": refs], dryRun: false)   // orcid 已在
        XCTAssertEqual(try person().references.count, 1, "append 冪等")
    }

    func testUpdatePersonRefusesVerdictFieldReferences() throws {
        let refs: [[String: Any]] = [[
            "field": "resolution-confirmed",
            "value": "work:a2020x :: Che Cheng",
            "kind": "judgement",
            "statement": "偽造判定",
        ]]
        XCTAssertThrowsError(try service.updatePerson(
            key: "cheng-che", fields: ["references": refs], dryRun: false)) { err in
            XCTAssertTrue(String(describing: err).contains("resolve"),
                          "verdict 欄位對只能經 resolve 流程寫：\(err)")
        }
        XCTAssertTrue(try person().references.isEmpty)
    }

    // MARK: - #307：MCP apply 的 tier-acknowledgment

    func testLooseTierApplyRequiresTierAcknowledgment() throws {
        try LibraryStore(root: root).writeEntry(
            Entry(id: UUID(), citekey: "c2022z", type: .periodicalArticle,
                  title: "V", authors: [.literal("Cheng Che")], date: "2022"))
        // 寬鬆 tier（reorder）候選、未帶 confirmTiers → 拒絕並指名缺席 tier
        XCTAssertThrowsError(
            try service.resolvePeople(apply: ["c2022z:0:cheng-che"])) { err in
            let msg = String(describing: err)
            XCTAssertTrue(msg.contains("reorder") && msg.contains("confirm_tiers"), msg)
        }
        // 零寫入
        let e = try LibraryStore(root: root).load().entries.first { $0.citekey == "c2022z" }!
        XCTAssertEqual(e.authors, [.literal("Cheng Che")])
        // 帶承認 → 落地
        let out = try json(try service.resolvePeople(
            apply: ["c2022z:0:cheng-che"], confirmTiers: ["reorder"]))
        XCTAssertEqual(out["applied"] as? [String], ["c2022z:0:cheng-che"])
    }

    func testExactApplyNeedsNoAcknowledgment() throws {
        let out = try json(try service.resolvePeople(apply: ["a2020x:0:cheng-che"]))
        XCTAssertEqual((out["applied"] as? [String])?.count, 1, "\(out)")
    }

    // MARK: - R1-fix B2：loose-tier verdict 帶 tier 導出的 rule

    func testLooseTierApplyWritesTierDerivedRule() throws {
        try LibraryStore(root: root).writeEntry(
            Entry(id: UUID(), citekey: "c2022z", type: .periodicalArticle,
                  title: "V", authors: [.literal("Cheng Che")], date: "2022"))
        _ = try service.resolvePeople(apply: ["c2022z:0"], confirmTiers: ["reorder"])
        let p = try person()
        let ref = try XCTUnwrap(p.references.first {
            $0.field == "resolution-confirmed" && ($0.value ?? "").contains("c2022z") })
        guard case .judgement(let statement, _) = ref.kind else { return XCTFail() }
        XCTAssertTrue(statement.hasSuffix("[rule: author-name-reorder]"),
                      "reorder tier 的 apply 不得寫進 exact 的校準史：\(statement)")
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
        XCTAssertEqual(active.map { $0["id"] as? String }, ["b2021y:0:cheng-che"])   // B8：id 釘 person
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

    /// #272 解禁（原 verify A 的禁令）：組合呼叫改兩段式——reject 腿完整提交後
    /// apply 腿重載重解析。**原事故形（stale 蓋寫）是本測試的核心斷言**：reject
    /// 剛寫的 verdict 必須在 apply 腿之後仍在（v1 的 bug 正是它被抹掉）。
    func testApplyAndRejectInOneCallReportsPerLeg() throws {
        let out = try json(try service.resolvePeople(apply: ["b2021y:0"],
                                                     reject: ["a2020x:0"]))
        let legs = out["legs"] as? [String: Any]
        XCTAssertNotNil(legs, "組合呼叫要按腿回報：\(out)")
        let rejectLeg = legs?["reject"] as? [String: Any]
        let applyLeg = legs?["apply"] as? [String: Any]
        XCTAssertEqual(rejectLeg?["rejected"] as? [String], ["a2020x:0:cheng-che"])   // R4-8 pinned 回音
        XCTAssertEqual(applyLeg?["applied"] as? [String], ["b2021y:0:cheng-che"])   // R3-1：applied 回音同列表用 pinned 形
        // 原事故形不再現：兩個 verdict 都在（reject 沒被 apply 的整檔改寫抹掉）
        let (vs, _) = ResolutionLedger.verdicts(references: try person().references)
        XCTAssertEqual(vs.count, 2, "reject 與 confirm 都要存活：\(vs)")
        XCTAssertTrue(vs.contains { $0.kind == .rejected && $0.holder == "a2020x" })
        XCTAssertTrue(vs.contains { $0.kind == .confirmed && $0.holder == "b2021y" })
    }

    /// 同一列兩邊都點到：reject 腿贏（先提交），apply 腿以 skippedBecauseRejected
    /// 回報——不是錯誤（LLM 一次 triage 常見）。
    /// R3-fix R4-1a：同列「reject A＋apply B（pinned 到不同 person）」——B 不得
    /// 被誤標 skipped；apply 腿在寫入後快照重解析，B 成立即落地。
    func testSameRowRejectAAndApplyBIsNotSkipped() throws {
        // A（cheng-che）exact 可達；B（cheng-che-2）僅 reorder 可達——
        // 初始提名是 A；reject A 後 fall-through 提名 B，同列 apply B 應落地
        try LibraryStore(root: root).writePerson(
            Person(key: "cheng-che-2", names: ["Cheng Che"]))
        let out = try json(try service.resolvePeople(
            apply: ["a2020x:0:cheng-che-2"],
            reject: ["a2020x:0:cheng-che"],
            confirmTiers: ["reorder"]))   // #307：B 是 reorder 提名，顯式承認
        let legs = out["legs"] as! [String: Any]
        let applyLeg = legs["apply"] as! [String: Any]
        XCTAssertNil(applyLeg["skippedBecauseRejected"],
                     "pinned 到不同 person 的同列 apply 不是同一配對：\(applyLeg)")
        XCTAssertEqual((applyLeg["applied"] as? [String])?.count, 1, "\(applyLeg)")
        let e = try LibraryStore(root: root).load().entries.first { $0.citekey == "a2020x" }!
        XCTAssertEqual(e.authors, [.key("cheng-che-2")])
    }

    /// R2-fix R3-1：三段 pinned id 下兩腿協調照常——跨腿比對以 rowID 前綴為準。
    func testCombinedLegsWorkWithPinnedIDs() throws {
        let out = try json(try service.resolvePeople(
            apply: ["a2020x:0:cheng-che", "b2021y:0:cheng-che"],
            reject: ["a2020x:0:cheng-che"]))
        let legs = out["legs"] as! [String: Any]
        let applyLeg = legs["apply"] as! [String: Any]
        XCTAssertEqual(applyLeg["skippedBecauseRejected"] as? [String],
                       ["a2020x:0:cheng-che"], "\(applyLeg)")
        XCTAssertEqual(applyLeg["applied"] as? [String], ["b2021y:0:cheng-che"],
                       "同批其他合法 apply 必須落地——R2 headline 的回歸守衛")
        let e = try LibraryStore(root: root).load().entries.first { $0.citekey == "b2021y" }!
        XCTAssertEqual(e.authors, [.key("cheng-che")])
    }

    func testSameRowInBothLegsIsSkippedNotError() throws {
        let out = try json(try service.resolvePeople(apply: ["a2020x:0"],
                                                     reject: ["a2020x:0"]))
        let legs = out["legs"] as! [String: Any]
        let applyLeg = legs["apply"] as! [String: Any]
        XCTAssertEqual(applyLeg["skippedBecauseRejected"] as? [String], ["a2020x:0"])
        XCTAssertEqual((applyLeg["applied"] as? [String]) ?? [], [])
        let (vs, _) = ResolutionLedger.verdicts(references: try person().references)
        XCTAssertEqual(vs.count, 1)
        XCTAssertEqual(vs.first?.kind, .rejected, "reject 腿先提交、apply 不得覆蓋")
    }

    /// apply 腿失敗不得掩蓋 reject 已提交的事實——錯誤收容進 legs.apply.error。
    func testApplyLegFailureDoesNotHideCommittedReject() throws {
        let out = try json(try service.resolvePeople(apply: ["stale-id:9"],
                                                     reject: ["a2020x:0"]))
        let legs = out["legs"] as! [String: Any]
        XCTAssertEqual((legs["reject"] as? [String: Any])?["rejected"] as? [String],
                       ["a2020x:0:cheng-che"], "reject 已提交（R4-8：回音三段 pinned 形）")
        let applyLeg = legs["apply"] as! [String: Any]
        XCTAssertNotNil(applyLeg["error"], "apply 腿的失敗要按腿收容：\(applyLeg)")
        let (vs, _) = ResolutionLedger.verdicts(references: try person().references)
        XCTAssertEqual(vs.first?.kind, .rejected, "reject 的寫入不受 apply 失敗影響")
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
