import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #564 b36 Y1 的修正（b37 N1）：
///
/// - 報告裡一段名字的 `attested` 有上限（第 0／1／13 列）：organization `remove_names` 的 `segments` 與 venue `edit_name_segment` 的
///   before／after 先前只截段數，一段兩萬個觀測點時一次回 46 萬位元組。讀取面照舊全列（`match` 要逐項相同）。
/// - `update-person --fields` 對同 key 兩筆的 person 拒絕（第 2／14 列）：先前寫進先載入的那一筆，名字分類記錄也一樣；乾跑同樣拒。
/// - organization `--remove-name` 的拒絕在 format < 22 說出寫入閘（第 7 列）。
/// - 替換的孤兒掃描是線性的（第 8 列）。
final class NameClassificationB37Tests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!
    private var service: AkashicService { AkashicService(root: root) }

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncb37-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func payload(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }
    /// 整個 entities 目錄的位元組——「零寫入」比位元組，不比挑出來的欄位。
    private func snapshot() throws -> [String: Data] {
        let dir = root.appendingPathComponent("entities")
        var out: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            out[name] = try Data(contentsOf: dir.appendingPathComponent(name))
        }
        return out
    }
    private func points(_ n: Int) -> [String] { (0..<n).map { String(1700 + $0) } }

    // MARK: - 第 0／1／13 列：報告裡的 attested 有上限

    /// organization 刪名字的報告：一段 300 個觀測點只列 `nameSegmentAttestedListedCap` 個，最後一項說出省略數與總數；沒有新增回應鍵。
    func testOrganizationRemovalCapsAttestedPerSegment() throws {
        var org = Organization(key: "og", names: Timeline([TemporalValue(value: "Keep Inst"),
                                                           TemporalValue(value: "Typo Inc", range: DateRange(attested: points(300)))]))
        org.references = [NameClassificationRecord.make(field: "authorized", name: "Typo Inc", action: .withdraw, reason: "x", restsOn: [])]
        try store.writeOrganization(org)
        let out = try payload(try service.committed(root).updateOrganization(key: "og", authorize: [], removeNames: ["Typo Inc=打錯"]))
        let row = try XCTUnwrap((out["namesRemoved"] as? [[String: Any]])?.first)
        XCTAssertEqual(Set(row.keys), ["name", "reason", "segmentsRemoved", "recordsRemoved", "segments"], "不新增回應鍵")
        let seg = try XCTUnwrap((row["segments"] as? [[String: Any]])?.first)
        let attested = try XCTUnwrap(seg["attested"] as? [String])
        let cap = AkashicService.nameSegmentAttestedListedCap
        XCTAssertEqual(attested.count, cap + 1, "列 \(cap) 個加一句省略說明")
        XCTAssertEqual(Array(attested.prefix(cap)), Array(points(300).prefix(cap)))
        XCTAssertEqual(attested.last, "…另 \(300 - cap) 個觀測點未列出（共 300 個）")
    }

    /// venue `edit_name_segment` 的 before／after：同一個上限；讀取面（`akashic_venue`）照舊全列。
    func testVenueEditReportCapsAttestedButTheReadFaceListsAll() throws {
        try store.writeVenue(Venue(key: "jv", type: .periodical, names: Timeline([
            TemporalValue(value: "Journal V", range: DateRange(attested: points(300))),
        ]), authorized: ["Journal V"]))
        let view = try payload(try service.venue(key: "jv"))
        let readSeg = try XCTUnwrap((view["names"] as? [[String: Any]])?.first)
        XCTAssertEqual((readSeg["attested"] as? [String])?.count, 300, "讀取面全列：match 要逐項相同")

        let out = try payload(try service.committed(root).updateVenue(key: "jv", addNames: nil, note: nil, type: nil,
                                                                      editNameSegment: [["name": "Journal V", "set": ["note": "n"], "reason": "補註"]]))
        let item = try XCTUnwrap((out["nameSegments"] as? [[String: Any]])?.first)
        let cap = AkashicService.nameSegmentAttestedListedCap
        for side in ["before", "after"] {
            let attested = try XCTUnwrap((item[side] as? [String: Any])?["attested"] as? [String], side)
            XCTAssertEqual(attested.count, cap + 1, side)
            XCTAssertEqual(attested.last, "…另 \(300 - cap) 個觀測點未列出（共 300 個）", side)
        }
        XCTAssertEqual(try store.load().venues.first { $0.key == "jv" }?.names.entries.first?.range.attested.count, 300,
                       "報告截，store 不截")
    }

    /// 剛好在上限的不加說明（off-by-one）。
    func testAttestedAtTheCapIsListedWithoutANote() {
        let cap = AkashicService.nameSegmentAttestedListedCap
        let d = AkashicService.nameSegmentFieldsDict(TemporalValue(value: "N", range: DateRange(attested: points(cap))), attestedCap: cap)
        XCTAssertEqual(d["attested"] as? [String], points(cap))
    }

    // MARK: - 第 2／14 列：同 key 兩筆的 person

    /// 兩筆 person 共用 key「dup」：`--fields` 的一般欄位、names 附理由、乾跑，三者都拒絕、零寫入——與同一個命令的 `--remove-name` 同一道。
    func testUpdatePersonRefusesADuplicatedKeyOnEveryFieldsPath() throws {
        try store.writePerson(Person(key: "dup", names: PersonNames(authorized: ["Dan D"], variant: [])))
        try store.writePerson(Person(key: "dup", names: PersonNames(authorized: ["Dan D"], variant: ["Other"])))
        XCTAssertEqual(try store.load().people.duplicatedPersonKeys, ["dup"], "前提：load 看得出 key 重複")
        let before = try snapshot()
        let calls: [(String, () throws -> String)] = [
            ("note", { try self.service.updatePerson(key: "dup", fields: ["note": "x"], dryRun: false) }),
            ("note dry-run", { try self.service.updatePerson(key: "dup", fields: ["note": "x"], dryRun: true) }),
            ("names＋judgement", { try self.service.updatePerson(key: "dup", fields: ["names": ["authorized": ["Eve E"], "variant": ["Dan D"]]],
                                                                 dryRun: false, judgement: "reason r1") }),
            ("names＋judgement dry-run", { try self.service.updatePerson(key: "dup", fields: ["names": ["authorized": ["Eve E"], "variant": ["Dan D"]]],
                                                                         dryRun: true, judgement: "reason r1") }),
        ]
        for (label, call) in calls {
            XCTAssertThrowsError(try call(), label) { e in
                XCTAssertTrue(msg(e).contains("無法唯一定位") && msg(e).contains("零寫入"), "\(label)：\(msg(e))")
            }
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    // MARK: - 第 7 列：organization 的拒絕說出寫入閘

    /// format 18：organization `--remove-name` 的三種拒絕（還在 authorized、沒有記錄、記錄與分類不一致）出口都經 `--authorize` 寫記錄——
    /// 訊息說出 format 與門檻；format 22 不說。記錄讀不出動作的那一格沒有出口，不加。
    func testOrganizationRemovalRefusalsNameTheGateAtAnOldFormat() throws {
        var org = Organization(key: "oa", names: Timeline(["Real Inst", "Typo Institue", "Mis Inst", "Odd Inst"].map { TemporalValue(value: $0) }))
        org.authorized = ["Real Inst"]
        org.references = [NameClassificationRecord.make(field: "authorized", name: "Mis Inst", action: .designate, reason: "手改", restsOn: [])]
        try store.writeOrganization(org)
        let cases = ["Real Inst=x": "還在 authorized", "Typo Institue=x": "沒有名字分類的判定記錄", "Mis Inst=x": "不一致"]
        try StoreVersion.write(root: root, format: 18)
        for (spec, shape) in cases {
            XCTAssertThrowsError(try service.updateOrganization(key: "oa", authorize: [], removeNames: [spec]), spec) { e in
                let m = msg(e)
                XCTAssertTrue(m.contains(shape), "\(spec)：\(m)")
                XCTAssertTrue(m.contains("format 18") && m.contains("format: 改成 \(StoreVersion.nameClassificationRecordFormat)"), "\(spec)：\(m)")
                XCTAssertFalse(displaySafeErrorMultiline(e).contains("已截斷"), "寫入閘那句自成一行，不被長拒絕擠掉")
            }
        }
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        for spec in cases.keys {
            XCTAssertThrowsError(try service.updateOrganization(key: "oa", authorize: [], removeNames: [spec]), spec) { e in
                XCTAssertFalse(msg(e).contains("format 18"), msg(e))
            }
        }
    }

    /// 同一個判斷的 venue 那一條（查同判斷路徑時補上）：`edit_name_segment` 的 remove 被拒、出口要經 `--authorize`／`--unauthorize` 寫記錄的三種
    /// （還在 authorized、還在 variant、最後一筆不是撤回）在 format 18 說出寫入閘；format 22 不說。
    func testVenueRemovalRefusalsNameTheGateAtAnOldFormat() throws {
        var v = Venue(key: "vg", type: .periodical,
                      names: Timeline(["Real J", "Alt J", "Hist J", "Keep J"].map { TemporalValue(value: $0) }), authorized: ["Real J"])
        v.variant = ["Alt J"]
        v.references = [NameClassificationRecord.make(field: "authorized", name: "Hist J", action: .designate, reason: "手改", restsOn: [])]
        try store.writeVenue(v)
        let cases = ["Real J": "authorized 裡成孤兒", "Alt J": "variant 裡成孤兒", "Hist J": "最後一筆不是「撤回」"]
        func remove(_ name: String) throws {
            _ = try service.updateVenue(key: "vg", addNames: nil, note: nil, type: nil,
                                        editNameSegment: [["name": name, "remove": true, "reason": "打錯"]])
        }
        try StoreVersion.write(root: root, format: 18)
        for (name, shape) in cases {
            XCTAssertThrowsError(try remove(name), name) { e in
                let m = msg(e)
                XCTAssertTrue(m.contains(shape) && m.contains("format 18"), "\(name)：\(m)")
            }
        }
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        for name in cases.keys {
            XCTAssertThrowsError(try remove(name), name) { e in XCTAssertFalse(msg(e).contains("format 18"), msg(e)) }
        }
    }

    // MARK: - 第 8 列：孤兒掃描線性

    /// 兩萬個名字各一筆撤回、替換拿掉全部：孤兒掃描先前以陣列 contains 去重，O(N²)（debug build 一萬筆 2.4 秒）。只量這個函式，不經 YAML。
    func testOrphanScanIsLinear() {
        let n = 20_000
        let names = (0..<n).map { "Name \($0)" }
        var p = Person(key: "big", names: PersonNames(authorized: ["Alice A"], variant: names))
        p.references = names.map { NameClassificationRecord.make(field: "authorized", name: $0, action: .withdraw, reason: "r", restsOn: []) }
        let before = p.names
        p.names = PersonNames(authorized: ["Alice A"], variant: ["Zed"])
        let start = Date()
        XCTAssertThrowsError(try AkashicService.recordPersonNameClassification(before: before, person: &p, judgement: nil, key: "big",
                                                                               storeFormat: StoreVersion.supported)) { e in
            XCTAssertTrue(msg(e).contains("名字分類的判定記錄"), msg(e))
        }
        XCTAssertLessThan(Date().timeIntervalSince(start), 2.0, "孤兒掃描要線性")
    }
}
