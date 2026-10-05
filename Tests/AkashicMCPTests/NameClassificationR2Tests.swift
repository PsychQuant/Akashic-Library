import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #564 R2 verify（b29 V1）：修正輪之後的寫入面與刪名字面。
///
/// - person 以整份替換改正對外形拼寫（舊值沒有記錄）附理由就放行，離開的名字列在報告（第 4 列）；store format < 22 的拒絕說出寫入閘（第 5 列）。
/// - person 的一次上限只數 authorized（第 9 列）；刪名字不得把 person 刪到沒有名字（第 18 列）。
/// - 刪名字的拒絕依名字的處境給出口（第 6／7／23 列）；venue 的 variant 名字有一條工具面的出口（第 1／14／19 列）。
/// - organization 刪名字回報逐段的時間欄位、source、note（第 20 列）；理由開頭的檢查以性質判（第 15 列）；刪記錄是線性的（第 16 列）。
final class NameClassificationR2Tests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncr2-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        _ = try service.addVenue(key: "tg", names: ["Some Journal"], type: "periodical", note: nil, issn: nil)
        _ = try service.addOrganization(key: "org2", names: ["Alpha Institute", "Beta Institute"])
        _ = try service.addPerson(key: "pq", names: ["Quinn Q", "Q. Quinn"], orcid: nil, openalex: nil)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func load() throws -> LibraryLoad { try LibraryStore(root: root).load() }
    private func person(_ key: String = "pq") throws -> Person { try XCTUnwrap(load().people.first { $0.key == key }) }
    private func venue() throws -> Venue { try XCTUnwrap(load().venues.first { $0.key == "tg" }) }
    private func org() throws -> Organization { try XCTUnwrap(load().organizations.first { $0.key == "org2" }) }
    private func payload(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }
    private func statements(_ refs: [ProvenanceReference], name: String) -> [String] {
        refs.filter { NameClassificationRecord.isRecord($0) && $0.value == name }.compactMap { r in
            guard case .judgement(let statement, _) = r.kind else { return nil }
            return r.field + " " + statement
        }
    }
    @discardableResult
    private func personNames(_ key: String = "pq", authorized: [String], variant: [String], judgement: String? = nil,
                             dryRun: Bool = false) throws -> [String: Any] {
        try payload(try service.updatePerson(key: key, fields: ["names": ["authorized": authorized, "variant": variant]],
                                             dryRun: dryRun, judgement: judgement))
    }
    @discardableResult
    private func venueCall(authorize: [String]? = nil, unauthorize: [String]? = nil, addVariant: [String]? = nil,
                           judgement: String?) throws -> [String: Any] {
        try payload(try service.updateVenue(key: "tg", addNames: nil, note: nil, type: nil, addVariant: addVariant,
                                            authorize: authorize, unauthorize: unauthorize, judgement: judgement, restsOn: nil))
    }
    private func removePersonNames(_ specs: [String], key: String = "pq", dryRun: Bool = false) throws -> [String: Any] {
        try payload(try service.committed(root).updatePerson(key: key, fields: [:], dryRun: dryRun, fieldsGiven: false, removeNames: specs))
    }

    // MARK: - 第 4 列：整份替換改正對外形拼寫（b34：使用者 2026-10-05 裁決第 1 點改了這一格）

    /// 舊的對外形沒有任何記錄（機械值）：R2 讓它附理由就能一步整個離開 names、不寫撤回；2026-10-05 裁決改成「要 format ≥ 22，並替被移出的
    /// 名字寫一筆撤回」——記錄錨定 names，所以舊拼法留在 variant。改正拼寫仍是一次呼叫（撤回舊的、指定新的），之後要刪舊拼法再 --remove-name。
    func testCorrectingAnUnrecordedAuthorizedSpellingWritesAWithdrawal() throws {
        var p = try person()
        p.names = PersonNames(authorized: ["Quinn Q"], variant: ["Q. Quinn"])   // 手寫的舊值，零記錄（live store 4,575 筆機械值的形）
        _ = try LibraryStore(root: root).writePerson(p)
        XCTAssertThrowsError(try personNames(authorized: ["Quin Q"], variant: ["Q. Quinn"], judgement: "改正拼寫")) { e in
            let m = msg(e)
            XCTAssertTrue(m.contains("整個離開 names") && m.contains("Quinn Q") && m.contains("variant") && m.contains("--remove-name"), m)
        }
        XCTAssertEqual(try person(), p, "零寫入")
        let out = try personNames(authorized: ["Quin Q"], variant: ["Q. Quinn", "Quinn Q"], judgement: "改正拼寫")
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 2, "\(out)")
        XCTAssertNil(out["authorizedRemovedWithoutRecord"], "R2 的回應鍵退場")
        let after = try person()
        XCTAssertEqual(after.names.authorized, ["Quin Q"])
        XCTAssertEqual(statements(after.references, name: "Quinn Q"), ["authorized 撤回：改正拼寫"], "理由入庫、可追溯")
        XCTAssertEqual(statements(after.references, name: "Quin Q"), ["authorized 指定：改正拼寫"])
        let removed = try removePersonNames(["Quinn Q=打錯的舊拼法"])
        XCTAssertEqual((removed["namesRemoved"] as? [[String: Any]])?.first?["recordsRemoved"] as? Int, 1)
        XCTAssertFalse(try person().names.all.contains("Quinn Q"))
    }

    /// 有記錄的舊對外形仍然不能被整份替換拿掉（記錄會成孤兒）——那一格的拒絕不變。
    func testDroppingARecordedAuthorizedNameIsStillRefused() throws {
        try personNames(authorized: ["Quinn Q"], variant: ["Q. Quinn"], judgement: "本人網頁")
        XCTAssertThrowsError(try personNames(authorized: ["Quin Q"], variant: ["Q. Quinn"], judgement: "改正拼寫")) { e in
            XCTAssertTrue(msg(e).contains("--remove-name") && msg(e).contains("Quinn Q"), msg(e))
        }
    }

    // MARK: - 第 5 列：format < 22 的拒絕說出寫入閘

    func testAuthorizedChangeRefusalAtAnOldFormatNamesTheGate() throws {
        try StoreVersion.write(root: root, format: 18)
        XCTAssertThrowsError(try personNames(authorized: ["Quinn Q"], variant: ["Q. Quinn"])) { e in
            let m = msg(e)
            XCTAssertTrue(m.contains("judgement") && m.contains("format 18") && m.contains("22") && m.contains("store.yaml"), m)
        }
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        XCTAssertThrowsError(try personNames(authorized: ["Quinn Q"], variant: ["Q. Quinn"])) { e in
            XCTAssertFalse(msg(e).contains("format 18"), "format 夠的 store 不說：\(msg(e))")
        }
    }

    // MARK: - 第 9 列：上限只數 authorized

    func testPersonCapCountsOnlyAuthorizedNames() throws {
        let aliases = (1...231).map { "Alias \($0)" }
        XCTAssertNoThrow(try personNames(authorized: [], variant: aliases), "只動 variant、不寫記錄，不受 200 的限制")
        XCTAssertEqual(try person().names.variant.count, 231)
        XCTAssertThrowsError(try personNames(authorized: (1...201).map { "Auth \($0)" }, variant: [], judgement: "批次")) { e in
            XCTAssertTrue(msg(e).contains("200") && msg(e).contains("201") && msg(e).contains("authorized"), msg(e))
        }
    }

    // MARK: - 第 18 列：刪名字不得刪到沒有名字

    func testPersonRemoveNameRefusesToLeaveNoNames() throws {
        _ = try service.addPerson(key: "pb", names: ["Beta B"], orcid: nil, openalex: nil)
        try personNames("pb", authorized: ["Beta B"], variant: [], judgement: "指定")
        try personNames("pb", authorized: [], variant: ["Beta B"], judgement: "不對")
        for dry in [true, false] {
            XCTAssertThrowsError(try removePersonNames(["Beta B=打錯"], key: "pb", dryRun: dry)) { e in
                XCTAssertTrue(msg(e).contains("沒有任何名字"), msg(e))
            }
        }
        XCTAssertEqual(try person("pb").names.all, ["Beta B"], "零寫入")
    }

    // MARK: - 第 6／7／23 列：刪名字的拒絕依處境給出口

    /// person 沒有記錄的名字：出口是整份替換直接拿掉（不是「先撤回」——它沒有東西可撤回）。
    func testPersonNoRecordNameRefusalPointsAtTheReplacement() throws {
        XCTAssertThrowsError(try removePersonNames(["Q. Quinn=不要"])) { e in
            let m = msg(e)
            XCTAssertTrue(m.contains("沒有名字分類的判定記錄") && m.contains("整份替換"), m)
        }
    }

    /// person 的名字不在 authorized、最後一筆卻是指定（記錄與分類不一致）：先前叫人「把它從 authorized 移到 variant」——做不到。
    func testPersonInconsistentTailRefusalPointsAtRedesignation() throws {
        var p = try person()
        p.references.append(NameClassificationRecord.make(field: "authorized", name: "Q. Quinn", action: .designate, reason: "手改", restsOn: []))
        _ = try LibraryStore(root: root).writePerson(p)
        XCTAssertThrowsError(try removePersonNames(["Q. Quinn=不要"])) { e in
            let m = msg(e)
            XCTAssertTrue(m.contains("不在 authorized 裡") && m.contains("指定回去再撤回") && m.contains("放進 authorized"), m)
            // b33 X1 第 6／31 列：同書寫系統已有對外形時放不進第二個——出口要說交換與代價
            XCTAssertTrue(m.contains("交換") && m.contains("多一對撤回／指定"), m)
            XCTAssertFalse(m.contains("從 authorized 移到 variant"), "名字不在 authorized，這一步做不到：\(m)")
        }
    }

    /// organization 沒有記錄的名字：說出要先讓它有一筆撤回的做法與代價（organization 沒有一般的名字移除面）。
    func testOrganizationNoRecordNameRefusalNamesTheWayOut() throws {
        XCTAssertThrowsError(try service.committed(root).updateOrganization(key: "org2", authorize: [], removeNames: ["Beta Institute=不要"])) { e in
            let m = msg(e)
            XCTAssertTrue(m.contains("沒有名字分類的判定記錄") && m.contains("--authorize") && m.contains("撤不掉"), m)
            XCTAssertFalse(m.contains("手改 YAML"), "工具面走得通，「只能手改 YAML」是假話（b33 X1 第 29 列）：\(m)")
        }
    }

    /// venue 的 variant 名字（`--add-variant` 打錯字）：訊息不再說「只能手改 YAML」，而說出工具面的出口；照它走得通。
    func testVenueVariantTypoHasAToolExit() throws {
        try venueCall(addVariant: ["Some Jurnal"], judgement: "異寫")
        let spec: [[String: Any]] = [["name": "Some Jurnal", "remove": true, "reason": "打錯字"]]
        XCTAssertThrowsError(try service.committed(root).updateVenue(key: "tg", addNames: nil, note: nil, type: nil,
                                                                    editNameSegment: spec)) { e in
            let m = msg(e)
            XCTAssertTrue(m.contains("--authorize") && m.contains("--unauthorize") && m.contains("換下"), m)
            XCTAssertFalse(m.contains("只能手改 YAML"), m)
        }
        try venueCall(authorize: ["Some Jurnal"], judgement: "抬出 variant 以便撤回")
        try venueCall(unauthorize: ["Some Jurnal"], judgement: "打錯字")
        let out = try payload(try service.committed(root).updateVenue(key: "tg", addNames: nil, note: nil, type: nil, editNameSegment: spec))
        XCTAssertEqual(out["judgementRecordsRemoved"] as? Int, 4, "\(out)")
        XCTAssertFalse(try venue().names.entries.contains { $0.value == "Some Jurnal" })
        XCTAssertTrue(statements(try venue().references, name: "Some Jurnal").isEmpty)
    }

    // MARK: - 第 20 列：organization 刪名字回報逐段

    func testOrganizationRemovalReportsTheRemovedSegments() throws {
        var o = try org()
        o.names = Timeline([TemporalValue(value: "Alpha Institute"),
                            TemporalValue(value: "Old Name", range: DateRange(start: "1950", end: "1970"), source: "年報", note: "舊所名"),
                            TemporalValue(value: "Beta Institute")])
        _ = try LibraryStore(root: root).writeOrganization(o)
        _ = try service.updateOrganization(key: "org2", authorize: ["Old Name"], judgement: "舊所名")
        _ = try service.updateOrganization(key: "org2", authorize: ["Alpha Institute"], judgement: "現行所名")
        let out = try payload(try service.committed(root).updateOrganization(key: "org2", authorize: [], removeNames: ["Old Name=不要了"]))
        let removed = try XCTUnwrap((out["namesRemoved"] as? [[String: Any]])?.first, "\(out)")
        let segments = try XCTUnwrap(removed["segments"] as? [[String: Any]], "\(removed)")
        XCTAssertEqual(segments.count, 1)
        XCTAssertEqual(segments.first?["start"] as? String, "1950")
        XCTAssertEqual(segments.first?["end"] as? String, "1970")
        XCTAssertEqual(segments.first?["source"] as? String, "年報")
        XCTAssertEqual(segments.first?["note"] as? String, "舊所名")
    }

    // MARK: - 第 15 列：理由開頭以性質判

    /// Emoji modifier（GCB=Extend、類別 Sk）與 THAI SARA AM（SpacingMark、類別 Lo）都會與全形冒號併成同一個字——類別列舉放行了它們。
    func testReasonLeadingCharacterIsJudgedByThePropertyNotCategories() throws {
        for lead in ["\u{0E33}", "\u{0EB3}", "\u{1F3FB}", "\u{1F3FF}"] {
            XCTAssertNotNil(NameClassificationRecord.reasonIssue(lead + "check"), lead.unicodeScalars.map { String($0.value, radix: 16) }.joined())
        }
        XCTAssertThrowsError(try venueCall(authorize: ["Some Journal"], judgement: "\u{0E33}check"))
        XCTAssertTrue(statements(try venue().references, name: "Some Journal").isEmpty, "零寫入")
        XCTAssertNil(NameClassificationRecord.reasonIssue("ทำ check"), "SARA AM 在字中間是正常的泰文")
    }

    // MARK: - 第 16 列：刪記錄是線性的

    /// 一個名字來回指定撤回幾千次之後刪它：先前 O(R×K) 且每對重算 key（debug 建置實測 N=2000 要 6.5 秒、N=4000 要 24.7 秒）。
    func testRemovingANameWithAThousandsLongHistoryIsLinear() throws {
        var p = try person()
        var refs: [ProvenanceReference] = []
        for i in 0..<1_500 {
            refs.append(NameClassificationRecord.make(field: "authorized", name: "Q. Quinn", action: .designate, reason: "r\(i)", restsOn: []))
            refs.append(NameClassificationRecord.make(field: "authorized", name: "Q. Quinn", action: .withdraw, reason: "w\(i)", restsOn: []))
        }
        p.references = refs
        _ = try LibraryStore(root: root).writePerson(p)
        StoreGitCommit.commitAll(root)
        let start = Date()
        let out = try payload(try service.updatePerson(key: "pq", fields: [:], dryRun: true, fieldsGiven: false, removeNames: ["Q. Quinn=打錯"]))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertEqual((out["namesRemoved"] as? [[String: Any]])?.first?["recordsRemoved"] as? Int, 3_000)
        XCTAssertLessThan(elapsed, 5, "3,000 筆記錄的刪除要是線性的（實得 \(elapsed) 秒）")
    }
}
