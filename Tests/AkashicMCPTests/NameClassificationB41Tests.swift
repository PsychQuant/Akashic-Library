import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #564 b40 Z1 的修正（b41 Q1）：
///
/// - 第 0 列（MEDIUM，Codex）：venue 合併拒絕的 variant 出口叫人「--unauthorize 它、--add-variant 它、再 --authorize 它」——名字的段帶時間欄位時，
///   第一步寫入、撤掉了對外形，第二步才被 dated-variant 不變式拒絕。真 binary 在 scratch store 重現（2026-10-19）。現在名字有帶時間的段時，
///   出口在任何一步之前說工具面走不通、只能手改，並說出手改什麼；照那個手改做，合併通過。
/// - 第 14 列：「三次都附 --judgement」之後還要第四步補回對外形，第四步也要附理由。
/// - 第 6／11／18 列：organization `remove_names` 的 MCP 報告只封段數、沒有封位元組——現在列出的 segments 以 compact JSON 計合計至多
///   `candidateByteBudget`，放不下的名字照段數那一軸的形不帶 segments。
/// - 第 4／7／17 列的同判斷路徑：`update-person --remove-name` 的乾跑也跑 `writePerson` 的前置（`--fields` 那條見 CLI 的真 binary 測試）。
final class NameClassificationB41Tests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private var service: AkashicService { AkashicService(root: root) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncb41-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func payload(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }
    private func record(_ field: String, _ name: String, _ action: NameClassificationRecord.Action, _ reason: String) -> ProvenanceReference {
        NameClassificationRecord.make(field: field, name: name, action: action, reason: reason, restsOn: [])
    }
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
    /// 磁碟上 key 是 `key` 的那筆記錄檔。
    private func recordFile(key: String) throws -> URL {
        let dir = root.appendingPathComponent("entities")
        for f in try FileManager.default.contentsOfDirectory(at: dir, includingPropertiesForKeys: nil) where f.pathExtension == "yaml" {
            if try String(contentsOf: f, encoding: .utf8).contains("\nkey: \(key)\n") { return f }
        }
        throw NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "找不到 key \(key) 的檔"])
    }

    /// 倖存者與被併者都有「Alpha J」（對外形、名字段從 1990 起），被併者另有一筆手改的 variant 指定。
    private func seedDatedAuthorizedPair() throws -> Divergence {
        let segment = TemporalValue(value: "Alpha J", range: DateRange(start: "1990"))
        try store.writeVenue(Venue(key: "kv", type: .periodical, names: Timeline([segment]), authorized: ["Alpha J"]))
        var dv = Venue(key: "dv", type: .periodical, names: Timeline([segment]), authorized: ["Alpha J"])
        dv.references = [record("variant", "Alpha J", .designate, "手改")]
        try store.writeVenue(dv)
        let d = try divergence(["kv", "dv"])
        StoreGitCommit.commitAll(root)
        return d
    }

    // MARK: - 第 0 列：名字段帶時間時，variant 出口在任何一步之前說只能手改

    /// 名字是對外形、段帶時間：出口不再叫人 --unauthorize（那一步會寫入、撤掉對外形，下一步 --add-variant 被 dated-variant 不變式拒絕），
    /// 改說工具面沒有出口、只能手改，並說出手改的內容。照那個手改（在被併者的 references 末尾補一筆 variant 的撤回）做完，合併通過、
    /// 倖存者的對外形與名字段的時間都還在。
    func testTheVariantExitForADatedAuthorizedNameSaysOnlyAHandEditWorks() throws {
        let d = try seedDatedAuthorizedPair()
        let found = exits(d.id, survivor: "kv")
        XCTAssertEqual(found.count, 1, "\(found)")
        XCTAssertTrue(found[0].contains("有帶時間欄位的段") && found[0].contains("工具面沒有出口") && found[0].contains("只能手改"), found[0])
        XCTAssertTrue(found[0].contains("不要先 --unauthorize 它"), "在任何一步之前說：\(found[0])")
        XCTAssertFalse(found[0].contains("--unauthorize 它、--add-variant 它"), "那條路對帶時間的名字走不通：\(found[0])")

        // 照出口說的手改：被併者的 references 末尾補一筆 field: variant、judgement「撤回：理由」
        let file = try recordFile(key: "dv")
        let text = try String(contentsOf: file, encoding: .utf8)
        try (text + "- field: variant\n  value: Alpha J\n  judgement: 撤回：手改的異寫記錄不成立\n  rests-on: []\n")
            .write(to: file, atomically: true, encoding: .utf8)
        StoreGitCommit.commitAll(root)
        _ = try store.previewResolveDivergence(id: d.id, survivor: "kv", overrideReason: nil)
        let report = try store.resolveDivergence(id: d.id, survivor: "kv")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let k = try XCTUnwrap(store.load().venues.first { $0.key == "kv" })
        XCTAssertTrue(LibraryStore.venueTailConflicts(k).isEmpty)
        XCTAssertEqual(k.authorized, ["Alpha J"], "名字仍是對外形")
        XCTAssertEqual(k.names.entries.map(\.range.start), ["1990"], "名字段的時間還在")
    }

    /// 先前那句出口照做走不通的原因，釘在這裡：第一步 --unauthorize 寫入成功（對外形撤掉），第二步 --add-variant 被拒。
    func testTheOldVariantExitWritesStepOneThenFailsStepTwoOnADatedName() throws {
        _ = try seedDatedAuthorizedPair()
        try venueCall("dv", unauthorize: ["Alpha J"], judgement: "出口一")
        XCTAssertEqual(try XCTUnwrap(store.load().venues.first { $0.key == "dv" }).authorized, [], "第一步已寫入")
        XCTAssertThrowsError(try venueCall("dv", addVariant: ["Alpha J"], judgement: "出口二")) { e in
            XCTAssertTrue(msg(e).contains("帶時間欄位"), msg(e))
        }
    }

    /// 名字未標（不是對外形也不是異寫）、段帶時間：「要它是異寫，兩邊都 --add-variant」與「要它不是異寫，--add-variant、--authorize、--unauthorize」
    /// 的第一步都被拒——同一句只能手改。
    func testTheVariantExitForADatedUnmarkedNameSaysOnlyAHandEditWorks() throws {
        let segments = [TemporalValue(value: "Main J"), TemporalValue(value: "Old J", range: DateRange(start: "1950", end: "1960"))]
        try store.writeVenue(Venue(key: "kv", type: .periodical, names: Timeline(segments), authorized: ["Main J"]))
        var dv = Venue(key: "dv", type: .periodical, names: Timeline(segments), authorized: ["Main J"])
        dv.references = [record("variant", "Old J", .designate, "手改")]
        try store.writeVenue(dv)
        let d = try divergence(["kv", "dv"])
        StoreGitCommit.commitAll(root)
        let found = exits(d.id, survivor: "kv")
        XCTAssertEqual(found.count, 1, "\(found)")
        XCTAssertTrue(found[0].contains("有帶時間欄位的段") && found[0].contains("只能手改"), found[0])
        XCTAssertFalse(found[0].contains("兩邊都 --add-variant"), found[0])
        XCTAssertThrowsError(try venueCall("dv", addVariant: ["Old J"], judgement: "第一步")) { e in
            XCTAssertTrue(msg(e).contains("帶時間欄位"), "那兩條支線的第一步確實被拒：\(msg(e))")
        }
    }

    // MARK: - 第 14 列：補回對外形那一步也要附理由

    func testTheReplacementStepIsSaidToNeedAJudgementToo() {
        let exits = LibraryStore.tailConflictExits([
            .init(field: "authorized", name: "N J", last: .designate, broughtBy: "dv", inOtherPartition: true),
            .init(field: "variant", name: "S J", last: .designate, broughtBy: "dv"),
            .init(field: "authorized", name: "T J", last: .designate, broughtBy: "dv"),
        ], kind: "venue")
        XCTAssertEqual(exits.count, 3, "\(exits)")
        for e in exits {
            XCTAssertTrue(e.contains("同書寫系統原本有別的對外形時") && e.contains("補回（同樣附 --judgement）"), e)
            XCTAssertFalse(e.contains("三次都附 --judgement——"), "字面讀成「只有前三次要附」：\(e)")
        }
    }

    // MARK: - 第 6／11／18 列：organization remove_names 的報告有位元組預算

    /// 兩個已撤回的名字各 5 段、每段的 source 與 note 各 300 個 U+0001（逃脫後每段約 5.4 KB compact JSON）：段數那一軸（20 段）放得下兩個，
    /// 位元組放不下第二個——MCP 只有第一個帶 segments、`detailsListed: 1`；列出的 segments 合計不超過 `candidateByteBudget`。CLI（nil）兩個都列。
    func testOrganizationRemovalSegmentsAreBoundedInBytesOnTheMCPFace() throws {
        let control = String(repeating: "\u{0001}", count: 300)
        func org(_ key: String) -> Organization {
            var entries = [TemporalValue(value: "Keep Inst")]
            for name in ["Typo A", "Typo B"] {
                for i in 0..<5 {
                    let year = String(1800 + i)
                    entries.append(TemporalValue(value: name, range: DateRange(start: year, end: year), source: control, note: control))
                }
            }
            var o = Organization(key: key, names: Timeline(entries))
            o.references = ["Typo A", "Typo B"].map { record("authorized", $0, .withdraw, "打錯") }
            return o
        }
        try store.writeOrganization(org("om"))
        try store.writeOrganization(org("oc"))
        let mcp = try payload(try service.committed(root).updateOrganization(key: "om", authorize: [], removeNames: ["Typo A=x", "Typo B=x"]))
        let rows = try XCTUnwrap(mcp["namesRemoved"] as? [[String: Any]])
        XCTAssertEqual(rows.map { ($0["segments"] as? [Any])?.count }, [5, nil], "段數放得下、位元組放不下第二個")
        XCTAssertEqual(mcp["detailsTruncated"] as? Bool, true)
        XCTAssertEqual(mcp["detailsListed"] as? Int, 1)
        let listedBytes = rows.compactMap { $0["segments"] }.map { AkashicService.jsonBytes($0) }.reduce(0, +)
        XCTAssertLessThanOrEqual(listedBytes, AkashicService.candidateByteBudget, "列出的 segments 合計 \(listedBytes) 位元組")

        let cli = try payload(try service.committed(root).updateOrganization(key: "oc", authorize: [], removeNames: ["Typo A=x", "Typo B=x"],
                                                                            removalDetailLimit: nil))
        XCTAssertEqual((cli["namesRemoved"] as? [[String: Any]])?.map { ($0["segments"] as? [Any])?.count }, [5, 5], "CLI 全列")
        XCTAssertNil(cli["detailsTruncated"])
    }

    /// security 席的形（逃脫放大）：40 個名字各 20 段，每段的 source 與 note 各 300 個 U+0001、attested 20 個各 40 個 U+0001。b39 只封段數，
    /// MCP 回應 318,939 位元組（security 席，同形 40 名時 325,644）。現在第一個名字的 20 段就放不進 48 KiB，沒有任何名字帶 segments——
    /// 列出的 segments 合計 0、`detailsListed: 0`；報告其餘的部分是 40 個名字的名字、理由與計數。
    func testOrganizationRemovalReportWithEscapeHeavySegmentsStaysBounded() throws {
        let control = String(repeating: "\u{0001}", count: 300)
        let point = String(repeating: "\u{0001}", count: 40)
        let names = (0..<40).map { "Typo Inst \($0)" }
        var entries = [TemporalValue(value: "Keep Inst")]
        for n in names {
            entries += (0..<20).map { _ in
                TemporalValue(value: n, range: DateRange(attested: Array(repeating: point, count: 20)), source: control, note: control)
            }
        }
        var o = Organization(key: "obig", names: Timeline(entries))
        o.references = names.map { record("authorized", $0, .withdraw, "打錯") }
        try store.writeOrganization(o)
        let out = try service.committed(root).updateOrganization(key: "obig", authorize: [], removeNames: names.map { "\($0)=打錯" })
        let p = try payload(out)
        let rows = try XCTUnwrap(p["namesRemoved"] as? [[String: Any]])
        XCTAssertEqual(rows.count, 40, "每個名字都回報（名字、理由、計數）")
        XCTAssertEqual(p["detailsTruncated"] as? Bool, true)
        XCTAssertEqual(p["detailsListed"] as? Int, 0)
        XCTAssertTrue(rows.allSatisfy { $0["segments"] == nil })
        XCTAssertEqual(rows.map { $0["segmentsRemoved"] as? Int }, Array(repeating: 20, count: 40), "總數照報")
        XCTAssertLessThan(out.utf8.count, AkashicService.candidateByteBudget, "MCP 回應 \(out.utf8.count) 位元組（理由是呼叫端送的「打錯」）")
    }

    // MARK: - 第 4／7／17 列的同判斷路徑：remove_names 的乾跑跑寫入前置

    /// format 21 的 store：刪掉已撤回的「Lin M.」之後，person 仍持有「Mei Lin」的名字分類記錄——實跑在 `writePerson` 被 format ≥ 22 的閘拒絕。
    /// 乾跑先前回 `dryRun: true`，現在以同一句拒絕。
    func testRemoveNamesDryRunRefusesWhatTheRealRunRefuses() throws {
        var p = Person(key: "pl", names: PersonNames(authorized: ["Mei Lin"], variant: ["Lin M."]))
        p.references = [record("authorized", "Lin M.", .designate, "r"), record("authorized", "Lin M.", .withdraw, "打錯"),
                        record("authorized", "Mei Lin", .designate, "對外形")]
        try store.writePerson(p)
        try StoreVersion.write(root: root, format: StoreVersion.nameClassificationRecordFormat - 1)
        StoreGitCommit.commitAll(root)
        XCTAssertEqual(try store.load().people.map(\.key), ["pl"], "前提：format 21 的 store 載得進這筆")
        for dryRun in [true, false] {
            XCTAssertThrowsError(try service.updatePerson(key: "pl", fields: [:], dryRun: dryRun, fieldsGiven: false,
                                                          removeNames: ["Lin M.=打錯"]), "dryRun=\(dryRun)") { e in
                XCTAssertTrue(msg(e).contains("\(StoreVersion.nameClassificationRecordFormat)"), "dryRun=\(dryRun)：\(msg(e))")
            }
        }
    }
}
