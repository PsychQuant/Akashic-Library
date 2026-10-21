import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #564 b38 Z1 的修正（b39 P1）：
///
/// - 第 2／11 列：organization `remove_names` 的報告總量——b37 封了每個名字的段數與每段的 attested，名字數（一次至多 200）這一維仍沒有上限，
///   200 個各 20 段的名字一次回 3–4.7 MB。MCP 面的 `segments` 合計至多 `removalDetailCap` 段，`detailsTruncated`／`detailsListed` 揭露；CLI 全列。
/// - 第 4／8 列：`update-person --fields --dry-run` 對同一筆記錄的 legacy 拷貝說 `wouldChange`，實跑被 #631 前置拒絕——乾跑現在跑同一道前置。
/// - 第 5／13 列：venue 合併拒絕的兩句出口照做走不通（名字是對外形時 `--add-variant` 被拒；名字在 variant 時 `--authorize` 把它抬出去、
///   照做完分類與倖存者不同）。照新的出口用真的寫入面做完，合併通過。
final class NameClassificationB39Tests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private var service: AkashicService { AkashicService(root: root) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncb39-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func payload(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }
    private func withdrawn(_ name: String) -> ProvenanceReference {
        NameClassificationRecord.make(field: "authorized", name: name, action: .withdraw, reason: "打錯", restsOn: [])
    }
    private func record(_ field: String, _ name: String, _ action: NameClassificationRecord.Action, _ reason: String) -> ProvenanceReference {
        NameClassificationRecord.make(field: field, name: name, action: action, reason: reason, restsOn: [])
    }

    // MARK: - 第 2／11 列：organization 刪名字的報告總量

    /// 名字 A 有 15 段、B 有 10 段、C 有 1 段（每段都帶 note）：MCP 面列 A 的 15 段之後，B 的 10 段放不進剩下的 5 段——B 與 C 都不帶 segments，
    /// `detailsTruncated`／`detailsListed: 1`。CLI（nil）三個都列、沒有這兩個鍵。
    func testOrganizationRemovalSegmentsShareOneBudgetOnTheMCPFace() throws {
        func org(_ key: String) -> Organization {
            var entries = [TemporalValue(value: "Keep Inst")]
            for (name, n) in [("Typo A", 15), ("Typo B", 10), ("Typo C", 1)] {
                entries += (0..<n).map { TemporalValue(value: name, range: DateRange(start: String(1800 + $0)), note: "第 \($0) 段") }
            }
            var o = Organization(key: key, names: Timeline(entries))
            o.references = ["Typo A", "Typo B", "Typo C"].map(withdrawn)
            return o
        }
        try store.writeOrganization(org("om"))
        try store.writeOrganization(org("oc"))
        let specs = ["Typo A=x", "Typo B=x", "Typo C=x"]
        let mcp = try payload(try service.committed(root).updateOrganization(key: "om", authorize: [], removeNames: specs))
        let rows = try XCTUnwrap(mcp["namesRemoved"] as? [[String: Any]])
        XCTAssertEqual(rows.map { ($0["segments"] as? [Any])?.count }, [15, nil, nil], "合計至多 \(AkashicService.removalDetailCap) 段")
        XCTAssertEqual(rows.map { $0["segmentsRemoved"] as? Int }, [15, 10, 1], "總數照報")
        XCTAssertEqual(mcp["detailsTruncated"] as? Bool, true)
        XCTAssertEqual(mcp["detailsListed"] as? Int, 1, "帶 segments 的名字數")

        let cli = try payload(try service.committed(root).updateOrganization(key: "oc", authorize: [], removeNames: specs, removalDetailLimit: nil))
        XCTAssertEqual((cli["namesRemoved"] as? [[String: Any]])?.map { ($0["segments"] as? [Any])?.count }, [15, 10, 1], "CLI 全列")
        XCTAssertNil(cli["detailsTruncated"])
        XCTAssertNil(cli["detailsListed"])
    }

    /// 40 個名字各 20 段、每段帶 300 字元的 source 與 note：MCP 回應在 `candidateByteBudget`（48 KiB）之內——b37 這個形一次回五十多萬位元組。
    /// **只在這個 fixture 下**（#564 b40 Z1 第 6／11／18 列）：b39 的段數上限不是位元組的不變式，逃脫放大與 attested 讓同樣 20 段回 30 多萬位元組；
    /// b41 起列出的 segments 以 compact JSON 另有位元組預算（`NameClassificationB41Tests` 的兩支），整份回應另含呼叫端送的名字與理由。
    func testOrganizationRemovalReportStaysWithinTheMCPBudget() throws {
        let long = String(repeating: "出處", count: 150)
        let names = (0..<40).map { "Typo Inst \($0)" }
        var entries = [TemporalValue(value: "Keep Inst")]
        for n in names {
            for i in 0..<20 {
                let year = String(1800 + i)
                entries.append(TemporalValue(value: n, range: DateRange(start: year, end: year), source: long, note: long))
            }
        }
        var o = Organization(key: "obig", names: Timeline(entries))
        o.references = names.map(withdrawn)
        try store.writeOrganization(o)
        let out = try service.committed(root).updateOrganization(key: "obig", authorize: [], removeNames: names.map { "\($0)=打錯" })
        XCTAssertLessThan(out.utf8.count, AkashicService.candidateByteBudget, "MCP 回應 \(out.utf8.count) 位元組")
        let p = try payload(out)
        XCTAssertEqual((p["namesRemoved"] as? [Any])?.count, 40, "每個名字都回報（名字、理由、計數）")
        XCTAssertEqual(p["detailsListed"] as? Int, 1)
    }

    // MARK: - 第 4／8 列：乾跑跑寫入當下的 #631 前置

    /// 同一筆 person 有 legacy `people/<key>.yaml` 與 `entities/<id>.yaml` 兩份（id 相同，上面那一道「不同 id 共用 key」不擋）：
    /// 乾跑與實跑都以同一句 #631 拒絕、零寫入——先前乾跑回 `wouldChange`。
    func testUpdatePersonDryRunRefusesALegacyCopyLikeTheRealRun() throws {
        let p = Person(key: "pz", names: PersonNames(authorized: ["Zhou, P."], variant: []))
        try store.writePerson(p)
        try FileManager.default.createDirectory(at: store.peopleDir, withIntermediateDirectories: true)
        try PersonYAML.encode(p).write(to: store.personURL(key: p.key), atomically: true, encoding: .utf8)
        StoreGitCommit.commitAll(root)
        let before = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path)
            .map { try Data(contentsOf: root.appendingPathComponent("entities").appendingPathComponent($0)) }
        for dryRun in [true, false] {
            XCTAssertThrowsError(try service.updatePerson(key: "pz", fields: ["note": "x"], dryRun: dryRun), "dryRun=\(dryRun)") { e in
                XCTAssertTrue(msg(e).contains("同一筆記錄有兩份"), "dryRun=\(dryRun)：\(msg(e))")
            }
        }
        let after = try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path)
            .map { try Data(contentsOf: root.appendingPathComponent("entities").appendingPathComponent($0)) }
        XCTAssertEqual(after, before, "零寫入")
    }

    /// 兩筆不同的 person 共用 key 的拒絕說出出口（DA 第 19 列的 INFO）。
    func testDuplicatedKeyRefusalNamesTheWayOut() throws {
        try store.writePerson(Person(key: "dup", names: PersonNames(authorized: ["Dan D"], variant: [])))
        try store.writePerson(Person(key: "dup", names: PersonNames(authorized: ["Dan D"], variant: ["Other"])))
        XCTAssertThrowsError(try service.updatePerson(key: "dup", fields: ["note": "x"], dryRun: true)) { e in
            XCTAssertTrue(msg(e).contains("無法唯一定位") && msg(e).contains("改掉其中一筆的 key"), msg(e))
        }
    }

    // MARK: - 第 5／13 列：venue 合併拒絕的出口照做走得通

    private func divergence(_ keys: [String]) throws -> Divergence {
        let d = Divergence(id: UUID(), question: "同一本刊嗎", candidates: keys.map { DivergenceCandidate(key: $0, shape: .venue) })
        try store.writeDivergence(d)
        return d
    }
    private func exits(_ id: UUID, survivor: String) -> [String] {
        do {
            _ = try store.previewResolveDivergence(id: id, survivor: survivor, overrideReason: nil)
            XCTFail("前提：合併要被拒")
            return []
        } catch DivergenceResolveError.wouldContradictClassificationTail(_, _, let exits) {
            return exits
        } catch {
            XCTFail("要是尾端矛盾，實得 \(error)")
            return []
        }
    }
    private func venueCall(_ key: String, authorize: [String]? = nil, unauthorize: [String]? = nil, addVariant: [String]? = nil,
                           judgement: String) throws {
        _ = try service.updateVenue(key: key, addNames: nil, note: nil, type: nil, addVariant: addVariant,
                                    authorize: authorize, unauthorize: unauthorize, judgement: judgement, restsOn: nil)
    }

    /// variant 欄「不在 variant 卻以指定結尾」而名字是對外形：先前兩條支線第一步 `--add-variant` 都被 store 拒（「同時出現在 authorized 與
    /// variant」）。新出口：在被併者上 --unauthorize、--add-variant、--authorize——照做完合併通過、尾端一致。
    func testTheVariantExitForAnAuthorizedNameWorks() throws {
        try store.writeVenue(Venue(key: "kv", type: .periodical, names: Timeline([TemporalValue(value: "Alpha J")]), authorized: ["Alpha J"]))
        var dv = Venue(key: "dv", type: .periodical, names: Timeline([TemporalValue(value: "Alpha J")]), authorized: ["Alpha J"])
        dv.references = [record("variant", "Alpha J", .designate, "手改")]
        try store.writeVenue(dv)
        let d = try divergence(["kv", "dv"])
        StoreGitCommit.commitAll(root)
        let found = exits(d.id, survivor: "kv")
        XCTAssertEqual(found.count, 1, "\(found)")
        XCTAssertTrue(found[0].contains("而它是對外形") && found[0].contains("--unauthorize 它、--add-variant 它、再 --authorize 它"), found[0])
        XCTAssertFalse(found[0].contains("被併者與倖存者兩邊都 --add-variant"), "那條支線對對外形走不通：\(found[0])")

        try venueCall("dv", unauthorize: ["Alpha J"], judgement: "清掉手改的異寫記錄一")
        try venueCall("dv", addVariant: ["Alpha J"], judgement: "清掉手改的異寫記錄二")
        try venueCall("dv", authorize: ["Alpha J"], judgement: "清掉手改的異寫記錄三")
        StoreGitCommit.commitAll(root)
        _ = try store.previewResolveDivergence(id: d.id, survivor: "kv", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "kv")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "kv" })
        XCTAssertTrue(LibraryStore.venueTailConflicts(k).isEmpty)
        XCTAssertEqual(k.authorized, ["Alpha J"], "名字仍是對外形")
    }

    /// authorized 欄「不在 authorized 卻以指定結尾」而名字在 variant：先前的出口（--authorize、--unauthorize、補回）照做完名字不在任何分割，
    /// 與倖存者的 variant 不同、合併改以「分類不同」拒絕。新出口最後 --add-variant 放回去——照做完合併通過。
    func testTheAuthorizedExitForAVariantNamePutsItBack() throws {
        try store.writeVenue({
            var v = Venue(key: "kv", type: .periodical, names: Timeline(["Main J", "N J"].map { TemporalValue(value: $0) }), authorized: ["Main J"])
            v.variant = ["N J"]
            return v
        }())
        var dv = Venue(key: "dv", type: .periodical, names: Timeline(["Main J", "N J"].map { TemporalValue(value: $0) }), authorized: ["Main J"])
        dv.variant = ["N J"]
        dv.references = [record("authorized", "N J", .designate, "手改")]
        try store.writeVenue(dv)
        let d = try divergence(["kv", "dv"])
        StoreGitCommit.commitAll(root)
        let found = exits(d.id, survivor: "kv")
        XCTAssertEqual(found.count, 1, "\(found)")
        XCTAssertTrue(found[0].contains("而它在 variant") && found[0].contains("再 --add-variant 它放回 variant") && found[0].contains("補回"), found[0])

        try venueCall("dv", authorize: ["N J"], judgement: "清掉手改的指定一")
        try venueCall("dv", unauthorize: ["N J"], judgement: "清掉手改的指定二")
        try venueCall("dv", addVariant: ["N J"], judgement: "清掉手改的指定三")
        try venueCall("dv", authorize: ["Main J"], judgement: "補回原本的對外形")
        StoreGitCommit.commitAll(root)
        _ = try store.previewResolveDivergence(id: d.id, survivor: "kv", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "kv")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "kv" })
        XCTAssertTrue(LibraryStore.venueTailConflicts(k).isEmpty)
        XCTAssertEqual(k.variant, ["N J"])
    }
}
