import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #675：`update-venue --edit-name-segment`／`akashic_update_venue.edit_name_segment`。契約見 `VenueNameSegmentEdit.swift` 的檔頭。
/// 逐條釘住：只改被定位到的那一段（別的段、名字本身、分類都不動）、`null` 是清除與「要求缺席」、同名多段時定位歧義具名拒絕並列出區別、
/// 改完的時間欄位要成立、這次造出的 store 不變式違反在寫之前歸因到這次呼叫、移除名字的最後一段時不留孤兒、理由只進報告且不截斷、
/// 未 commit／不在 git 拒絕（沒有變動時不過閘）、輸入錯整批拒絕零寫入、單獨呼叫、key 重複時拒絕。
final class VenueNameSegmentEditTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-venue-segedit-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var service: AkashicService { AkashicService(root: root) }
    private let digest = "sha256:" + String(repeating: "ab", count: 32)

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func venue(_ key: String = "sankhya") throws -> Venue {
        try XCTUnwrap(try store.load().venues.first { $0.key == key })
    }
    /// 整個 entities 目錄的位元組——「零寫入」要比位元組，不比挑出來的欄位。
    private func snapshot() throws -> [String: Data] {
        let dir = root.appendingPathComponent("entities")
        var out: [String: Data] = [:]
        for name in try FileManager.default.contentsOfDirectory(atPath: dir.path) {
            out[name] = try Data(contentsOf: dir.appendingPathComponent(name))
        }
        return out
    }
    private func seg(_ v: String, start: String? = nil, end: String? = nil, ended: Bool = false, attested: [String] = [],
                     source: String? = nil, note: String? = nil) -> TemporalValue<String> {
        TemporalValue(value: v, range: DateRange(start: start, end: end, endedUnknown: ended, attested: attested), source: source, note: note)
    }
    /// Sankhyā：兩段同名的沿革（1933–1960、2002–2007，後一段帶 source 與 note）、一個不帶時間的舊寫法。
    private func seedSankhya() throws {
        try store.writeVenue(Venue(key: "sankhya", type: .periodical, names: Timeline([
            seg("Sankhyā", start: "1933", end: "1960"),
            seg("Sankhyā", start: "2002", end: "2007", source: "https://example.org/a", note: "重新合併"),
            seg("Sankhya Old"),
        ]), authorized: ["Sankhyā"]))
    }
    private func seedVenue(_ v: Venue) throws { try store.writeVenue(v) }

    /// 錯誤的訊息本文（`String(describing:)` 會把引號印成 `\"`，含引號的需要對照原文）
    private func msg(_ err: Error) -> String { (err as? LocalizedError)?.errorDescription ?? String(describing: err) }
    private func item(_ name: String, match: [String: Any]? = nil, set: [String: Any]? = nil, remove: Bool = false,
                      reason: String = "來源寫錯了") -> [String: Any] {
        var d: [String: Any] = ["name": name, "reason": reason]
        if let match { d["match"] = match }
        if let set { d["set"] = set }
        if remove { d["remove"] = true }
        return d
    }
    private func edit(_ items: [Any], key: String = "sankhya", on svc: AkashicService? = nil) throws -> [String: Any] {
        try json(try (svc ?? service).updateVenue(key: key, addNames: nil, note: nil, type: nil, editNameSegment: items))
    }
    private func segments(_ key: String = "sankhya") throws -> [TemporalValue<String>] { try venue(key).names.entries }

    // MARK: - 改

    func testSetsOnlyTheLocatedSegmentAndReportsBeforeAndAfter() throws {
        try seedSankhya()
        let out = try edit([item("Sankhyā", match: ["start": "1933"], set: ["end": "1961"], reason: "官網寫 1961")], on: service.committed(root))
        let segs = try segments()
        XCTAssertEqual(segs.filter { $0.value == "Sankhyā" }.map(\.range.end), ["1961", "2007"], "只改被定位到的那一段：\(segs)")
        XCTAssertEqual(segs.first { $0.range.start == "2002" }?.source, "https://example.org/a", "別的段連 source 都不動")
        XCTAssertEqual(try venue().authorized, ["Sankhyā"], "分類不動")
        XCTAssertEqual(segs.count, 3)
        let r = try XCTUnwrap((out["nameSegments"] as? [[String: Any]])?.first)
        XCTAssertEqual(r["name"] as? String, "Sankhyā")
        XCTAssertEqual(r["action"] as? String, "set")
        XCTAssertEqual((r["before"] as? [String: Any])?["end"] as? String, "1960")
        XCTAssertEqual((r["after"] as? [String: Any])?["end"] as? String, "1961")
        XCTAssertEqual((r["after"] as? [String: Any])?["start"] as? String, "1933", "沒給的鍵不動")
        XCTAssertEqual(r["reason"] as? String, "官網寫 1961")
        XCTAssertEqual(out["written"] as? Bool, true)
        XCTAssertEqual(out["namesTotal"] as? Int, 3)
        XCTAssertTrue((out["reasonNote"] as? String)?.contains("commit message") == true)
    }

    func testNullClearsAndAGivenStringSets() throws {
        try seedSankhya()
        _ = try edit([item("Sankhyā", match: ["start": "2002"], set: ["source": NSNull(), "note": "新的備註"])], on: service.committed(root))
        let s = try XCTUnwrap(try segments().first { $0.range.start == "2002" })
        XCTAssertNil(s.source, "null 是清除")
        XCTAssertEqual(s.note, "新的備註")
        XCTAssertEqual(s.range.end, "2007")
    }

    /// `null` 在 match 裡是「要求缺席」：`{end: 1960}`（沒有起點）與 `{start: 2002}` 是兩段有效的同名沿革，前者只能靠 `start: null` 選到。
    func testNullInMatchSelectsTheSegmentWithoutThatField() throws {
        try seedVenue(Venue(key: "jx", type: .periodical, names: Timeline([
            seg("Journal X", end: "1960"), seg("Journal X", start: "2002"), seg("Other X")]), authorized: ["Other X"]))
        _ = try edit([item("Journal X", match: ["start": NSNull()], set: ["note": "前身"])], key: "jx", on: service.committed(root))
        func notes() throws -> [String: String?] {   // 序列化順序依 range 排（沒有起點的排最後），所以用 range 認段、不靠位置
            let segs = try segments("jx")
            return ["end1960": segs.first { $0.range.end == "1960" }?.note, "start2002": segs.first { $0.range.start == "2002" }?.note,
                    "other": segs.first { $0.value == "Other X" }?.note]
        }
        XCTAssertEqual(try notes(), ["end1960": "前身", "start2002": nil, "other": nil], "只有沒有起點的那一段被改")
        // 反過來：沒有 end 的那一段
        _ = try edit([item("Journal X", match: ["end": NSNull()], set: ["note": "後身"])], key: "jx", on: service.committed(root))
        XCTAssertEqual(try notes(), ["end1960": "前身", "start2002": "後身", "other": nil])
    }

    func testNameIsLocatedByCanonicalEqualityAndMatchByBytes() throws {
        try seedVenue(Venue(key: "cf", type: .periodical, names: Timeline([seg("Sankhyā", source: "Résumé")]), authorized: ["Sankhyā"]))
        let nfdName = "Sankhya\u{0304}"
        XCTAssertEqual(nfdName, "Sankhyā", "前提：Swift 的 == 把兩者視為相等")
        _ = try edit([item(nfdName, set: ["note": "n"])], key: "cf", on: service.committed(root))
        XCTAssertEqual(try segments("cf").first?.note, "n", "名字用 canonical 相等定位")
        // match 的字串比位元組：NFD 拼法的 source 不命中 store 上的 NFC 拼法
        let nfdSource = "Re\u{0301}sume\u{0301}"
        XCTAssertEqual(nfdSource, "Résumé")
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("Sankhyā", match: ["source": nfdSource], set: ["note": "m"])], key: "cf", on: service.committed(root))) { err in
            XCTAssertTrue(msg(err).contains("沒有一段符合 match"), "\(err)")
        }
        XCTAssertEqual(try snapshot(), before)
    }

    func testAttestedAndEndedAreEditableAndContradictionsAreRefusedWithAWayOut() throws {
        try seedVenue(Venue(key: "solo", type: .periodical, names: Timeline([seg("Solo", start: "1933", end: "1960")]), authorized: ["Solo"]))
        let svc = service.committed(root)
        let before = try snapshot()
        // end 有值時 ended: true 是矛盾——訊息說出怎麼同時清掉 end
        XCTAssertThrowsError(try edit([item("Solo", set: ["ended": true])], key: "solo", on: svc)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("edit_name_segment[0]") && s.contains("end 與 endedUnknown 並存是矛盾"), s)
            XCTAssertTrue(s.contains("end: null"), "要說出同一個 set 裡給 null 的出路：\(s)")
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
        // 同一個 set 裡把矛盾清掉就成立
        _ = try edit([item("Solo", set: ["end": NSNull(), "ended": true])], key: "solo", on: svc)
        var s = try XCTUnwrap(try segments("solo").first)
        XCTAssertNil(s.range.end)
        XCTAssertTrue(s.range.endedUnknown)
        XCTAssertEqual(s.range.start, "1933")
        // attested 與起訖不得並存；清掉起訖之後才收
        XCTAssertThrowsError(try edit([item("Solo", set: ["attested": ["1950"]])], key: "solo", on: service.committed(root))) { err in
            XCTAssertTrue(msg(err).contains("attested 與 start/end/ended 並存是矛盾"), "\(err)")
        }
        _ = try edit([item("Solo", set: ["start": NSNull(), "ended": false, "attested": ["1950", "2005"]])], key: "solo", on: service.committed(root))
        s = try XCTUnwrap(try segments("solo").first)
        XCTAssertEqual(s.range.attested, ["1950", "2005"])
        XCTAssertNil(s.range.start)
        XCTAssertFalse(s.range.endedUnknown)
        // null 清掉 attested
        _ = try edit([item("Solo", set: ["attested": NSNull(), "start": "1933"])], key: "solo", on: service.committed(root))
        s = try XCTUnwrap(try segments("solo").first)
        XCTAssertEqual(s.range.attested, [])
        XCTAssertEqual(s.range.start, "1933")
    }

    func testTimeFieldsMustBeAValidIntervalOfISOPrefixes() throws {
        try seedVenue(Venue(key: "solo", type: .periodical, names: Timeline([seg("Solo")]), authorized: ["Solo"]))
        let svc = service.committed(root)
        let before = try snapshot()
        let bad: [([String: Any], String)] = [
            (["start": "民國49"], "不是 ISO 8601 前綴"),
            (["end": "1960-13"], "不是 ISO 8601 前綴"),
            (["start": "1960-1"], "不是 ISO 8601 前綴"),
            (["start": "2000", "end": "1999"], "晚於 end"),
            (["attested": ["1950", "abc"]], "attested 的觀測點"),
        ]
        for (set, needle) in bad {
            XCTAssertThrowsError(try edit([item("Solo", set: set)], key: "solo", on: svc), "\(set)") { err in
                let s = msg(err)
                XCTAssertTrue(s.contains(needle) && s.contains("edit_name_segment[0]"), "\(set)：\(s)")
            }
            XCTAssertEqual(try snapshot(), before, "零寫入：\(set)")
        }
        // 同年內的細粒度 end 合法（較粗粒度截斷後比較）
        _ = try edit([item("Solo", set: ["start": "1960", "end": "1960-06"])], key: "solo", on: svc)
        XCTAssertEqual(try segments("solo").first?.range.end, "1960-06")
    }

    /// 只改 source／note 時不重驗區間：手改出來的非 ISO 日期照樣載入（#85），本面不替它歸咎；改到時間欄位才驗。
    func testEditingOnlySourceOrNoteDoesNotRevalidateAHandEditedDate() throws {
        try seedVenue(Venue(key: "odd", type: .periodical, names: Timeline([seg("Odd Journal", start: "1933")]), authorized: ["Odd Journal"]))
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path).first)
        let url = root.appendingPathComponent("entities/\(file)")
        let text = try String(contentsOf: url, encoding: .utf8)
        XCTAssertTrue(text.contains("1933"), "fixture")
        try text.replacingOccurrences(of: "1933", with: "民國22").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try segments("odd").first?.range.start, "民國22", "fixture：載入照收")
        let svc = service.committed(root)
        _ = try edit([item("Odd Journal", set: ["note": "來源用民國紀年"])], key: "odd", on: svc)
        XCTAssertEqual(try segments("odd").first?.note, "來源用民國紀年")
        XCTAssertEqual(try segments("odd").first?.range.start, "民國22", "沒動到的時間欄位原樣")
        _ = try edit([item("Odd Journal", set: ["start": "1933"])], key: "odd", on: service.committed(root))
        XCTAssertEqual(try segments("odd").first?.range.start, "1933", "改到時間欄位時驗改完的值，合法就收")
    }

    // MARK: - 這次造出的 store 不變式違反：寫之前歸因到這次呼叫

    /// variant 的名字不得帶時間（異寫法沒有生效期間）：寫入閘本來就擋；這裡在寫之前具名，並說是這次編輯造成的。
    func testATimeOnAVariantNameIsRefusedAndAttributedToTheEdit() throws {
        try seedVenue(Venue(key: "plos", type: .periodical, names: Timeline([seg("PLOS ONE"), seg("PLoS One")]), authorized: ["PLOS ONE"]))
        var v = try venue("plos")
        v.variant = ["PLoS One"]
        try store.writeVenue(v)
        let svc = service.committed(root)
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("PLoS One", set: ["start": "2006"])], key: "plos", on: svc)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("edit_name_segment 改完之後") && s.contains("venue「plos」") && s.contains("帶時間欄位"), s)
            XCTAssertTrue(s.contains("零寫入"), s)
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
        // 只改 source／note 不是時間宣稱，收
        _ = try edit([item("PLoS One", set: ["note": "WoS 的大寫形"])], key: "plos", on: svc)
        XCTAssertEqual(try segments("plos").last?.note, "WoS 的大寫形")
    }

    /// 改完讓兩段同名的沿革重疊 → 同名近重複（error）：拒絕並說出是哪一項。同一次呼叫把兩段一起改成不相交就成立（定位在呼叫前的記錄上、驗在全部改完之後）。
    func testAnOverlapCreatedByOneEditIsRefusedButTwoEditsInOneCallMayFixItTogether() throws {
        try seedSankhya()
        let svc = service.committed(root)
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("Sankhyā", match: ["start": "1933"], set: ["end": "2003"])], on: svc)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("edit_name_segment 改完之後") && s.contains("近重複") && s.contains("Sankhyā"), s)
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
        _ = try edit([item("Sankhyā", match: ["start": "1933"], set: ["end": "2003"]),
                      item("Sankhyā", match: ["start": "2002"], set: ["start": "2004"])], on: svc)
        XCTAssertEqual(try segments().filter { $0.value == "Sankhyā" }.map { "\($0.range.start ?? "")-\($0.range.end ?? "")" }, ["1933-2003", "2004-2007"])
    }

    /// 記錄原本就違反不變式（手改出來的同名近重複：兩段不帶時間的同名段）：修得掉它的編輯照收；修不掉的，寫入閘照舊擋、
    /// 訊息不把原本就有的違反歸咎到這次編輯（「這次造出的」才歸因）。
    func testAnEditMayFixAPreExistingViolationButIsNotBlamedForOne() throws {
        try seedVenue(Venue(key: "dup", type: .periodical, names: Timeline([seg("TwinA", note: "a"), seg("TwinB", note: "b"), seg("Other")]), authorized: ["Other"]))
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path).first)
        let url = root.appendingPathComponent("entities/\(file)")
        try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "TwinB", with: "TwinA").write(to: url, atomically: true, encoding: .utf8)
        XCTAssertTrue(try venue("dup").validate().contains { $0.severity == .error && $0.message.contains("近重複") }, "fixture：兩段不帶時間的同名段是近重複 error")
        let svc = service.committed(root)
        let before = try snapshot()
        // 改一段的 source：違反仍在——寫入閘擋下，訊息不歸咎到這次編輯
        XCTAssertThrowsError(try edit([item("TwinA", match: ["note": "a"], set: ["source": "s"])], key: "dup", on: svc)) { err in
            XCTAssertFalse(msg(err).contains("edit_name_segment 改完之後"), "原本就有的違反不歸咎：\(msg(err))")
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
        // 刪掉其中一段：違反消失，寫得進去
        _ = try edit([item("TwinA", match: ["note": "b"], remove: true, reason: "重複")], key: "dup", on: svc)
        XCTAssertEqual(try segments("dup").filter { $0.value == "TwinA" }.map(\.note), ["a"])
        XCTAssertFalse(try venue("dup").validate().contains { $0.severity == .error })
    }

    // MARK: - 移除

    func testRemovingOneOfTwoSegmentsOfTheSameNameKeepsTheName() throws {
        try seedSankhya()
        let out = try edit([item("Sankhyā", match: ["start": "2002"], remove: true, reason: "這一段是誤植")], on: service.committed(root))
        XCTAssertEqual(try segments().map(\.value), ["Sankhyā", "Sankhya Old"])
        XCTAssertEqual(try venue().authorized, ["Sankhyā"], "名字還有一段，分類不動")
        let r = try XCTUnwrap((out["nameSegments"] as? [[String: Any]])?.first)
        XCTAssertEqual(r["action"] as? String, "remove")
        XCTAssertEqual((r["before"] as? [String: Any])?["source"] as? String, "https://example.org/a", "報告要讓人認得出移除的是哪一段——它只剩 git 那份副本")
        XCTAssertNil(r["after"])
        XCTAssertEqual(out["namesTotal"] as? Int, 2)
    }

    func testRemovingTheLastSegmentOfAnUnreferencedNameIsAllowed() throws {
        try seedSankhya()
        _ = try edit([item("Sankhya Old", remove: true)], on: service.committed(root))
        XCTAssertEqual(try segments().map(\.value), ["Sankhyā", "Sankhyā"])
    }

    /// 移除讓名字整個消失：不留 authorized／variant／`field: names` reference 的孤兒——具名拒絕並指路，程式不替人改那些判定。
    func testRemovingAWholeNameIsRefusedWhileItIsAuthorizedVariantOrPinnedByAReference() throws {
        try seedVenue(Venue(key: "ab", type: .periodical, names: Timeline([seg("Alpha"), seg("Beta"), seg("BETA")]), authorized: ["Alpha"]))
        var v = try venue("ab")
        v.variant = ["BETA"]
        try store.writeVenue(v)
        _ = try service.updateVenue(key: "ab", addNames: nil, note: nil, type: nil, references: [
            ["field": "names", "value": "Beta", "kind": "judgement", "statement": "Beta 的來源", "rests_on": [digest]]])
        let svc = service.committed(root)
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("Alpha", remove: true)], key: "ab", on: svc)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("authorized") && s.contains("--authorize"), "要指路：\(s)")
        }
        XCTAssertThrowsError(try edit([item("BETA", remove: true)], key: "ab", on: svc)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("variant") && s.contains("手改 YAML"), "variant 沒有移除面，要老實說：\(s)")
        }
        XCTAssertThrowsError(try edit([item("Beta", remove: true)], key: "ab", on: svc)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("field: names") && s.contains("--remove-reference"), "要指路：\(s)")
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    func testRemovingEveryNameLeavesTheVenueWithNoNameAndIsRefused() throws {
        try seedVenue(Venue(key: "one", type: .periodical, names: Timeline([seg("Solo")])))
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("Solo", remove: true)], key: "one", on: service.committed(root))) { err in
            XCTAssertTrue(msg(err).contains("沒有任何名字"), "\(err)")
        }
        XCTAssertEqual(try snapshot(), before)
    }

    // MARK: - 定位

    func testSeveralSegmentsOfTheNameAreRefusedUntilNarrowed() throws {
        try seedSankhya()
        let svc = service.committed(root)
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("Sankhyā", set: ["note": "x"])], on: svc)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("edit_name_segment[0]") && s.contains("定位到 2 段"), s)
            XCTAssertTrue(s.contains("start 1933") && s.contains("start 2002"), "要列出各段的區別：\(s)")
            XCTAssertTrue(s.contains("match") && s.contains("start: null"), "要說怎麼縮小、含 null 的用法：\(s)")
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
        _ = try edit([item("Sankhyā", match: ["source": "https://example.org/a"], set: ["note": "x"])], on: svc)
        XCTAssertEqual(try segments().first { $0.range.start == "2002" }?.note, "x")
    }

    func testANameThatIsNotThereAndAMatchThatHitsNothingAreRefusedByNameWithWhatIsThere() throws {
        try seedSankhya()
        let svc = service.committed(root)
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("No Such Name", set: ["note": "x"])], on: svc)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("沒有「No Such Name」") && s.contains("Sankhya Old"), "要列出現有的名字：\(s)")
        }
        XCTAssertThrowsError(try edit([item("Sankhyā", match: ["start": "1999"], set: ["note": "x"])], on: svc)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("沒有一段符合 match") && s.contains("start 1933") && s.contains("start 2002"), "要列出同名各段：\(s)")
        }
        // 第二項找不到，第一項也不得寫
        XCTAssertThrowsError(try edit([item("Sankhya Old", set: ["note": "a"]), item("No Such Name", set: ["note": "b"])], on: svc))
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    func testTwoItemsPointingAtTheSameSegmentAreRefused() throws {
        try seedSankhya()
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("Sankhya Old", set: ["note": "a"]), item("Sankhya Old", set: ["source": "s"])], on: service.committed(root))) { err in
            XCTAssertTrue(msg(err).contains("指到同一段"), "\(err)")
        }
        XCTAssertEqual(try snapshot(), before)
    }

    /// 逐位元組完全相同的重複段（手改出來的；validate 的近重複檢查會報）：match 分不出它們，本面不替呼叫端挑。
    func testByteIdenticalDuplicateSegmentsAreRefused() throws {
        try seedVenue(Venue(key: "twin", type: .periodical, names: Timeline([
            seg("Twin", start: "1933", end: "1960", note: "n"), seg("Twin", start: "2002", end: "2007", note: "n"), seg("Other")]), authorized: ["Other"]))
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path).first)
        let url = root.appendingPathComponent("entities/\(file)")
        try String(contentsOf: url, encoding: .utf8).replacingOccurrences(of: "2002", with: "1933").replacingOccurrences(of: "2007", with: "1960")
            .write(to: url, atomically: true, encoding: .utf8)
        XCTAssertEqual(try segments("twin").filter { $0.value == "Twin" }.map { "\($0.range.start ?? "")-\($0.range.end ?? "")" }, ["1933-1960", "1933-1960"], "fixture")
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("Twin", set: ["note": "x"])], key: "twin", on: service.committed(root))) { err in
            XCTAssertTrue(msg(err).contains("逐位元組完全相同"), "\(err)")
        }
        XCTAssertEqual(try snapshot(), before)
    }

    // MARK: - 沒有變動

    func testAnEditThatChangesNothingWritesNothingAndSkipsTheGitGate() throws {
        try seedSankhya()   // 不在 git 裡：有變動的編輯會停在 git 閘（下一個測試）
        let before = try snapshot()
        let out = try edit([item("Sankhyā", match: ["start": "1933"], set: ["end": "1960", "note": NSNull()])])
        XCTAssertEqual(out["written"] as? Bool, false)
        XCTAssertEqual((out["nameSegments"] as? [[String: Any]])?.first?["action"] as? String, "unchanged")
        XCTAssertNotNil(out["writeNote"])
        XCTAssertEqual(try snapshot(), before, "沒有變動就不寫")
    }

    // MARK: - git 閘

    func testUncommittedVenueFileIsRefusedAndNothingIsWritten() throws {
        try seedSankhya()
        StoreGitCommit.commitAll(root)
        _ = try service.updateVenue(key: "sankhya", addNames: ["Sankhya Ancient"], note: nil, type: nil)   // 未提交的修改
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("Sankhya Old", set: ["note": "x"])])) { err in
            XCTAssertTrue(msg(err).contains("#675"), "\(err)")
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    func testStoreOutsideGitIsRefused() throws {
        try seedSankhya()
        let before = try snapshot()
        XCTAssertThrowsError(try edit([item("Sankhya Old", set: ["note": "x"])])) { err in
            XCTAssertTrue(msg(err).contains("git"), "\(err)")
        }
        XCTAssertEqual(try snapshot(), before)
    }

    // MARK: - 理由

    func testReasonIsInTheReportInFullAndNotInTheStore() throws {
        try seedSankhya()
        let reason = String(repeating: "貼錯了", count: 400)   // 3,600 位元組：比 displaySafe 的預設上限長，不得被截
        let out = try edit([item("Sankhya Old", set: ["note": "n"], reason: reason)], on: service.committed(root))
        XCTAssertEqual((out["nameSegments"] as? [[String: Any]])?.first?["reason"] as? String, reason, "理由只在報告裡，所以要全文")
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path).first)
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("entities/\(file)"), encoding: .utf8).contains("貼錯了貼錯了"), "理由不寫進 store")
    }

    // MARK: - 輸入錯：整批拒絕、零寫入

    func testMalformedInputRejectsTheWholeCall() throws {
        try seedSankhya()
        let svc = service.committed(root)
        let before = try snapshot()
        func x(_ overrides: [String: Any]) -> [String: Any] { item("Sankhya Old", set: ["note": "n"]).merging(overrides) { _, new in new } }
        let bad: [(String, [Any])] = [
            ("空陣列", []),
            ("不是物件", ["Sankhya Old"]),
            ("不認得的鍵", [x(["bogus": 1])]),
            ("缺 name", [["set": ["note": "n"], "reason": "r"]]),
            ("name 是空白", [x(["name": "  \t"])]),
            ("name 不是字串", [x(["name": 3])]),
            ("缺理由", [["name": "Sankhya Old", "set": ["note": "n"]]]),
            ("理由空白", [x(["reason": "   "])]),
            ("理由過長", [x(["reason": String(repeating: "x", count: 4_097)])]),
            ("set 與 remove 都沒有", [["name": "Sankhya Old", "reason": "r"]]),
            ("set 與 remove 都給", [x(["remove": true])]),
            ("set 是空物件", [x(["set": [String: Any]()])]),
            ("set 不是物件", [x(["set": "note"])]),
            ("remove 不是布林", [["name": "Sankhya Old", "remove": "true", "reason": "r"]]),
            ("remove: 1", [["name": "Sankhya Old", "remove": 1, "reason": "r"]]),
            ("match 不是物件", [x(["match": "start"])]),
            ("set 有不認得的鍵", [x(["set": ["note": "n", "ended_unknown": true]])]),
            ("match 有不認得的鍵", [x(["match": ["value": "x"]])]),
            ("時間寫成數字", [x(["set": ["start": 1933]])]),
            ("ended 不是布林", [x(["set": ["ended": "true"]])]),
            ("ended: null", [x(["set": ["ended": NSNull()]])]),
            ("attested 不是陣列", [x(["set": ["attested": "1950"]])]),
            ("attested 有非字串", [x(["set": ["attested": [1950]]])]),
            ("attested 重複", [x(["set": ["attested": ["1950", "1950"]]])]),
            ("source 是空白", [x(["set": ["source": "  "]])]),
            ("note 過長", [x(["set": ["note": String(repeating: "x", count: 65_537)]])]),
            ("attested 的一個點過長", [x(["set": ["attested": [String(repeating: "1", count: 65_537)]]])]),
            ("match 的 attested 一個點過長", [x(["match": ["attested": [String(repeating: "1", count: 65_537)]]])]),
            ("第二筆才錯", [x([:]), x(["reason": String(repeating: "x", count: 4_097)])]),
            ("超過 200 筆", (0...200).map { _ in x([:]) }),
        ]
        for (label, b) in bad {
            XCTAssertThrowsError(try edit(b, on: svc), label)
            XCTAssertEqual(try snapshot(), before, "零寫入：\(label)")
        }
    }

    // MARK: - 單獨呼叫

    func testEditNameSegmentIsStandaloneAndRefusesEveryOtherLeg() throws {
        try seedSankhya()
        let svc = service.committed(root)
        let before = try snapshot()
        let one: [Any] = [item("Sankhya Old", set: ["note": "n"])]
        let combos: [(String, () throws -> String)] = [
            ("add_names", { try svc.updateVenue(key: "sankhya", addNames: ["X"], note: nil, type: nil, editNameSegment: one) }),
            ("note", { try svc.updateVenue(key: "sankhya", addNames: nil, note: "n", type: nil, editNameSegment: one) }),
            ("type", { try svc.updateVenue(key: "sankhya", addNames: nil, note: nil, type: "periodical", editNameSegment: one) }),
            ("add_issn", { try svc.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil, addISSN: ["1234-5679"], editNameSegment: one) }),
            ("remove_issn", { try svc.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil, removeISSN: ["1935-990X=r"], editNameSegment: one) }),
            ("add_variant", { try svc.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil, addVariant: ["Sankhya Old"], judgement: "fixture", editNameSegment: one) }),
            ("authorize", { try svc.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil, authorize: ["Sankhya Old"], judgement: "fixture", editNameSegment: one) }),
            ("references", { try svc.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil, references: [["field": "names", "value": "Sankhyā", "kind": "judgement", "statement": "s", "rests_on": [self.digest]]], editNameSegment: one) }),
            ("paginated", { try svc.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil, paginated: true, judgement: "j", restsOn: [self.digest], editNameSegment: one) }),
            ("remove_reference", { try svc.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil,
                                                       removeReference: [["field": "names", "value": "Sankhyā", "reason": "r"]], editNameSegment: one) }),
        ]
        for (leg, run) in combos {
            XCTAssertThrowsError(try run(), leg) { err in
                let s = msg(err)
                XCTAssertTrue(s.contains("單獨呼叫") && s.contains(leg), "\(leg)：\(s)")
            }
        }
        // 反方向：remove_reference 也把 edit_name_segment 算成「其他腿」
        XCTAssertThrowsError(try svc.updateVenue(key: "sankhya", addNames: nil, note: nil, type: nil,
                                                 removeReference: [["field": "names", "value": "Sankhyā", "reason": "r"]], editNameSegment: one)) { err in
            XCTAssertTrue(msg(err).contains("edit_name_segment"), "\(err)")
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    func testUnlocatableVenueKeyIsRefused() throws {
        try seedSankhya()
        var dup = try venue()
        dup.id = UUID()
        try store.writeVenue(dup)   // 第二筆同 key 的 venue 檔（手改／舊 binary 的形，#670）
        XCTAssertThrowsError(try edit([item("Sankhya Old", set: ["note": "n"])])) { err in
            XCTAssertTrue(msg(err).contains("無法唯一定位"), "\(err)")
        }
    }

    func testMissingVenueIsNotFound() throws {
        XCTAssertThrowsError(try service.updateVenue(key: "nope", addNames: nil, note: nil, type: nil, editNameSegment: [item("X", set: ["note": "n"])])) { err in
            guard case ServiceError.notFound = err else { return XCTFail("\(err)") }
        }
    }

    // MARK: - 報告的上限（MCP 面截、CLI 全列）

    private func seedManyNames(_ n: Int) throws -> [Any] {
        try seedVenue(Venue(key: "many", type: .periodical, names: Timeline((0..<n).map { seg("Name \($0)", source: "https://example.org/\($0)") }),
                            authorized: ["Name 0"]))
        return (0..<n).map { i in item("Name \(i)", set: ["note": "備註 \(i)"], reason: "理由 \(i)") }
    }

    func testTheMCPReportKeepsEveryReasonButOnlyTheFirstTwentyDetails() throws {
        let total = AkashicService.removalDetailCap + 2
        let items = try seedManyNames(total)
        let out = try edit(items, key: "many", on: service.committed(root))
        let rows = try XCTUnwrap(out["nameSegments"] as? [[String: Any]])
        XCTAssertEqual(rows.count, total, "每一項都列")
        XCTAssertEqual(rows.map { $0["reason"] as? String }, (0..<total).map { "理由 \($0)" }, "理由是唯一的一份，逐項都在、不截")
        XCTAssertNotNil(rows[AkashicService.removalDetailCap - 1]["before"], "前 20 項帶改寫前後的內容")
        XCTAssertNil(rows[AkashicService.removalDetailCap]["before"], "第 21 項起只回 name／action／reason")
        XCTAssertNil(rows[total - 1]["after"])
        XCTAssertEqual(rows[total - 1]["name"] as? String, "Name \(total - 1)")
        XCTAssertEqual(rows[total - 1]["action"] as? String, "set")
        XCTAssertEqual(out["detailsTruncated"] as? Bool, true)
        XCTAssertEqual(out["detailsListed"] as? Int, AkashicService.removalDetailCap)
    }

    func testTheCLIReportListsEveryDetail() throws {
        let total = AkashicService.removalDetailCap + 2
        let items = try seedManyNames(total)
        let out = try json(try service.committed(root).updateVenue(key: "many", addNames: nil, note: nil, type: nil, editNameSegment: items, removalDetailLimit: nil))
        let rows = try XCTUnwrap(out["nameSegments"] as? [[String: Any]])
        XCTAssertEqual(rows.count, total)
        XCTAssertTrue(rows.allSatisfy { $0["before"] != nil && $0["after"] != nil }, "CLI 全列")
        XCTAssertNil(out["detailsTruncated"])
    }

    // MARK: - 讀取面

    func testTheReadSurfaceShowsSourceAndNoteOfEachNameSegment() throws {
        try seedSankhya()
        let names = try XCTUnwrap(try json(try service.venue(key: "sankhya"))["names"] as? [[String: Any]])
        let dated = try XCTUnwrap(names.first { $0["start"] as? String == "2002" })
        XCTAssertEqual(dated["source"] as? String, "https://example.org/a", "match／set 收 source 與 note，讀取面就要看得到——同名的段只差它們時才認得出區別")
        XCTAssertEqual(dated["note"] as? String, "重新合併")
        XCTAssertEqual(dated["value"] as? String, "Sankhyā")
        let plain = try XCTUnwrap(names.first { $0["value"] as? String == "Sankhya Old" })
        XCTAssertNil(plain["source"])
        XCTAssertNil(plain["note"])
        XCTAssertNil(plain["start"], "沒有的鍵不輸出")
    }

    // MARK: - 與 #565 的合併拒絕接起來

    /// 兩筆 venue 各有一段同名、只差 source 的段：合併具名拒絕，訊息指向這個面；用它刪掉被併者那一段之後合併成立。
    func testTheMergeRefusalPointsHereAndTheEditMakesTheMergeGo() throws {
        try store.writeVenue(Venue(key: "k", type: .periodical, names: Timeline([seg("Keeper Journal"), seg("Shared Title", source: "https://a.example")]),
                                   authorized: ["Keeper Journal"]))
        try store.writeVenue(Venue(key: "d", type: .periodical, names: Timeline([seg("Doomed Journal"), seg("Shared Title", source: "https://b.example")]),
                                   authorized: ["Doomed Journal"]))
        let dv = Divergence(id: UUID(), question: "同一本刊嗎",
                            candidates: [DivergenceCandidate(key: "k", shape: .venue), DivergenceCandidate(key: "d", shape: .venue)])
        try store.writeDivergence(dv)
        StoreGitCommit.commitAll(root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: dv.id, survivor: "k", overrideReason: nil)) { err in
            let s = (err as? LocalizedError)?.errorDescription ?? msg(err)
            XCTAssertTrue(s.contains("update-venue --edit-name-segment") && s.contains("#675"), "拒絕訊息要指向編輯面：\(s)")
            XCTAssertTrue(s.contains("手改 YAML"), "沒有這個 binary 的人仍有出路：\(s)")
        }
        // 以倖存者那一段為準：刪掉被併者那一段
        _ = try edit([item("Shared Title", remove: true, reason: "以倖存者的來源為準")], key: "d", on: service)
        StoreGitCommit.commitAll(root)
        let report = try store.resolveDivergence(id: dv.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let merged = try venue("k")
        XCTAssertEqual(merged.names.entries.filter { $0.value == "Shared Title" }.map(\.source), ["https://a.example"])
        XCTAssertTrue(merged.names.entries.contains { $0.value == "Doomed Journal" })
    }

    /// 兩段都改成帶不相交時間的沿革：另一條出路，合併把兩段都搬進倖存者。
    func testTheOtherWayOutMakesBothSegmentsDisjointHistoryAndTheMergeKeepsBoth() throws {
        try store.writeVenue(Venue(key: "k", type: .periodical, names: Timeline([seg("Keeper Journal"), seg("Shared Title", source: "https://a.example")]),
                                   authorized: ["Keeper Journal"]))
        try store.writeVenue(Venue(key: "d", type: .periodical, names: Timeline([seg("Doomed Journal"), seg("Shared Title", source: "https://b.example")]),
                                   authorized: ["Doomed Journal"]))
        let dv = Divergence(id: UUID(), question: "同一本刊嗎",
                            candidates: [DivergenceCandidate(key: "k", shape: .venue), DivergenceCandidate(key: "d", shape: .venue)])
        try store.writeDivergence(dv)
        StoreGitCommit.commitAll(root)
        _ = try edit([item("Shared Title", set: ["start": "1933", "end": "1960"], reason: "前一段沿革")], key: "k", on: service)
        StoreGitCommit.commitAll(root)
        _ = try edit([item("Shared Title", set: ["start": "2002", "end": "2007"], reason: "後一段沿革")], key: "d", on: service)
        StoreGitCommit.commitAll(root)
        let report = try store.resolveDivergence(id: dv.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        let shared = try venue("k").names.entries.filter { $0.value == "Shared Title" }
        XCTAssertEqual(shared.map { "\($0.range.start ?? "")-\($0.range.end ?? "")" }.sorted(), ["1933-1960", "2002-2007"])
    }

    // MARK: - R1 verify（#675）

    /// 第 12 列：兩筆重複的 venue 通常以同一個名字當對外形——衝突的正是被併者的 authorized（也是它唯一的名字）。
    /// 以前拒絕訊息推薦 `remove`，而編輯面必拒；現在推薦 `set`（改成與倖存者那一段逐字相同），照做之後合併走得過。
    func testTheMergeRefusalRecommendsSetWhenTheDoomedSegmentIsItsAuthorizedName() throws {
        try store.writeVenue(Venue(key: "k", type: .periodical, names: Timeline([seg("Sankhya")]), authorized: ["Sankhya"]))
        try store.writeVenue(Venue(key: "d", type: .periodical, names: Timeline([seg("Sankhya", start: "1933", end: "1960")]),
                                   authorized: ["Sankhya"]))
        let dv = Divergence(id: UUID(), question: "同一本刊嗎",
                            candidates: [DivergenceCandidate(key: "k", shape: .venue), DivergenceCandidate(key: "d", shape: .venue)])
        try store.writeDivergence(dv)
        StoreGitCommit.commitAll(root)
        var refusal = ""
        XCTAssertThrowsError(try store.previewResolveDivergence(id: dv.id, survivor: "k", overrideReason: nil)) { refusal = msg($0) }
        XCTAssertTrue(refusal.contains("set 成與倖存者那一段逐字相同"), "刪不掉時要推薦 set：\(refusal)")
        XCTAssertFalse(refusal.contains("刪掉它那一段（remove）"), "不得推薦編輯面會拒絕的那一條：\(refusal)")
        XCTAssertTrue(refusal.contains("remove）會被拒"), "要說 remove 為什麼不行：\(refusal)")
        // 訊息說的 remove 確實會被拒（同一份判準）
        XCTAssertThrowsError(try edit([item("Sankhya", remove: true)], key: "d"))
        // 照訊息做：set 成與倖存者那一段逐字相同（倖存者沒有起訖，給 null）
        _ = try edit([item("Sankhya", set: ["start": NSNull(), "end": NSNull()], reason: "以倖存者為準")], key: "d")
        StoreGitCommit.commitAll(root)
        let report = try store.resolveDivergence(id: dv.id, survivor: "k")
        XCTAssertFalse(report.hasFailures, report.failures.joined(separator: "\n"))
        XCTAssertEqual(try venue("k").names.entries.map(\.value), ["Sankhya"])
    }

    /// 兩個被併者互相衝突、兩段都是各自的對外形：訊息不推薦 remove，推薦 set。
    func testTheMergeRefusalBetweenTwoDoomedRecordsOnlyOffersRemoveWhereItWorks() throws {
        try store.writeVenue(Venue(key: "k", type: .periodical, names: Timeline([seg("Keeper Journal")]), authorized: ["Keeper Journal"]))
        try store.writeVenue(Venue(key: "d1", type: .periodical, names: Timeline([seg("Shared", source: "https://a.example")]), authorized: ["Shared"]))
        try store.writeVenue(Venue(key: "d2", type: .periodical, names: Timeline([seg("Shared", source: "https://b.example")]), authorized: ["Shared"]))
        let dv = Divergence(id: UUID(), question: "同一本刊嗎", candidates: ["k", "d1", "d2"].map { DivergenceCandidate(key: $0, shape: .venue) })
        try store.writeDivergence(dv)
        StoreGitCommit.commitAll(root)
        XCTAssertThrowsError(try store.previewResolveDivergence(id: dv.id, survivor: "k", overrideReason: nil)) { err in
            let s = msg(err)
            XCTAssertTrue(s.contains("set 成與另一段逐字相同"), s)
            XCTAssertFalse(s.contains("刪掉不要的那一段（remove）"), "兩段都刪不掉：\(s)")
            XCTAssertTrue(s.contains("remove）會被拒"), s)
        }
    }

    /// 第 27 列：git 閘通過之後、寫入之前，另一個寫入者改了這筆 venue 並 commit——不以閘之前讀到的內容覆寫。
    func testAnEditCommittedDuringTheGateIsNotOverwritten() throws {
        try seedSankhya()
        StoreGitCommit.commitAll(root)
        let specs = try AkashicService.parseNameSegmentEditSpecs([item("Sankhya Old", set: ["note": "舊寫法"], reason: "補註")])
        XCTAssertThrowsError(try service.editVenueNameSegments(key: "sankhya", specs: specs, afterRecoverabilityGate: {
            var v = try self.venue()
            v.note = "另一個寫入者剛改的"
            try self.store.writeVenue(v)
            StoreGitCommit.commitAll(self.root)
        })) { err in
            XCTAssertTrue(msg(err).contains("檢查期間被改過"), msg(err))
        }
        XCTAssertEqual(try venue().note, "另一個寫入者剛改的", "那次修改不得被覆寫")
        XCTAssertNil(try segments().first { $0.value == "Sankhya Old" }?.note, "這次的編輯沒有寫")
    }

    /// 第 34 列：`set` 的 source／note 不收控制、格式、方向與不可見字元（寫進 YAML 後看不出來）；散文用得到的 ZWNJ 與私用區照收；
    /// `match` 照收（修手改進來的髒值要逐字比到它）。
    func testSourceAndNoteRefuseControlFormatAndInvisibleScalarsInSetButNotInMatch() throws {
        try seedSankhya()
        let svc = service.committed(root)
        let before = try snapshot()
        for (label, value, code) in [("NUL", "a\u{0}b", "U+0000"), ("RLO", "a\u{202E}b", "U+202E"), ("ZWSP", "a\u{200B}b", "U+200B"),
                                     ("TAB", "a\tb", "U+0009"), ("LS", "a\u{2028}b", "U+2028"), ("TAG", "a\u{E0041}b", "U+E0041")] {
            for key in ["source", "note"] {
                XCTAssertThrowsError(try edit([item("Sankhya Old", set: [key: value])], on: svc), "\(key)：\(label)") { err in
                    XCTAssertTrue(msg(err).contains("set.\(key)") && msg(err).contains(code), "要指名欄位與碼位：\(msg(err))")
                }
            }
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
        _ = try edit([item("Sankhya Old", set: ["note": "نشریه\u{200C}روان", "source": "造字\u{E000}"])], on: svc)
        XCTAssertEqual(try segments().first { $0.value == "Sankhya Old" }?.note, "نشریه\u{200C}روان")
        // 手改進來的髒值：match 照收，才修得掉它
        var v = try venue()
        var entries = v.names.entries
        let i = try XCTUnwrap(entries.firstIndex { $0.value == "Sankhya Old" })
        entries[i].note = "a\u{202E}b"
        v.names = Timeline(entries)
        try store.writeVenue(v)
        _ = try edit([item("Sankhya Old", match: ["note": "a\u{202E}b"], set: ["note": NSNull()], reason: "清掉 RLO")], on: service.committed(root))
        XCTAssertNil(try segments().first { $0.value == "Sankhya Old" }?.note)
    }

    /// 第 35 列：沒有 authorized 的 venue，只編一個時間欄位就可能換掉顯示名——報告要說出前後。有 authorized 的不會變，也不出這個鍵。
    func testAChangedDisplayNameIsReported() throws {
        try seedVenue(Venue(key: "e", type: .periodical, names: Timeline([seg("Alpha Journal"), seg("Beta Journal")])))
        let before = try venue("e").displayName
        let out = try edit([item("Beta Journal", set: ["start": "1990"], reason: "1990 年起用這個名字")], key: "e", on: service.committed(root))
        let change = try XCTUnwrap(out["displayNameChanged"] as? [String: Any], "\(out)")
        XCTAssertEqual(change["before"] as? String, before)
        XCTAssertEqual(change["after"] as? String, try venue("e").displayName)
        XCTAssertNotEqual(before, try venue("e").displayName, "前提：顯示名真的換了")
        try seedSankhya()
        let steady = try edit([item("Sankhya Old", set: ["note": "n"])], on: service.committed(root))
        XCTAssertNil(steady["displayNameChanged"], "顯示名沒變就不出這個鍵")
    }

    /// 第 43 列：`attested` 的每個點也有 65,536 位元組上限，在解析時就拒（先前只有個數上限，超長的點要到 ISO 檢查或定位時才失敗）。
    func testAnOversizedAttestedPointIsRefusedWhileParsing() throws {
        for part in ["set", "match"] {
            var d: [String: Any] = ["name": "Sankhya Old", "reason": "r", "set": ["note": "n"]]
            d[part] = ["attested": [String(repeating: "1", count: 65_537)]]
            XCTAssertThrowsError(try AkashicService.parseNameSegmentEditSpecs([d]), part) { err in
                XCTAssertTrue(msg(err).contains("\(part).attested[0] 超過"), msg(err))
            }
        }
    }
}
