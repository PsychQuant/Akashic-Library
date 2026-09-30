import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #564（Spectra change `name-classification-judgement`）：名字分類的判定面一律留判定記錄——venue 的 `authorize`／`unauthorize`／`add_variant`、
/// organization 的 `authorize`（organization 的 `unauthorize` 已於 #557 R1 verify 之後拿掉，待裁）。理由必填、證據可空；確認既有值也留；被換下、被抬出 variant 的名字各留一筆撤回；
/// 位元組完全相同的不重寫。另驗記錄的保留：只由名字分類面寫、移除面不刪、pinned 檢查不被它擋。
final class NameClassificationJudgementTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!
    private let digest = "sha256:" + String(repeating: "cd", count: 32)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncj-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        _ = try service.addVenue(key: "some-journal", names: ["PSYCHOMETRIKA", "Psychometrika"], type: "periodical", note: nil, issn: nil)
        _ = try service.addOrganization(key: "iss", names: ["Institute of Statistical Science", "中央研究院統計科學研究所"])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue() throws -> Venue {
        try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "some-journal" })
    }
    private func org() throws -> Organization {
        try XCTUnwrap(LibraryStore(root: root).load().organizations.first { $0.key == "iss" })
    }
    private func payload(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    /// 名字分類記錄的 (field, value, statement, restsOn) 清單，依 references 的順序
    private func records(_ refs: [ProvenanceReference]) -> [[String]] {
        refs.filter(NameClassificationRecord.isRecord).map { r in
            guard case .judgement(let statement, let restsOn) = r.kind else { return [] }
            return [r.field, r.value ?? "", statement] + restsOn
        }
    }
    @discardableResult
    private func updateVenue(authorize: [String]? = nil, unauthorize: [String]? = nil, addVariant: [String]? = nil,
                             judgement: String?, restsOn: [String]? = nil) throws -> [String: Any] {
        try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, addVariant: addVariant,
                                            authorize: authorize, unauthorize: unauthorize, judgement: judgement, restsOn: restsOn))
    }

    // MARK: - 理由必填（spec「Every name-classification judgement SHALL leave a judgement record」）

    func testVenueLegsWithoutAReasonAreRefusedWithZeroWrites() throws {
        try updateVenue(authorize: ["Psychometrika"], judgement: "fixture")
        let before = try venue()
        let calls: [(String, () throws -> Any)] = [
            ("authorize", { try self.updateVenue(authorize: ["PSYCHOMETRIKA"], judgement: nil) }),
            ("unauthorize", { try self.updateVenue(unauthorize: ["Psychometrika"], judgement: nil) }),
            ("add_variant", { try self.updateVenue(addVariant: ["PSYCHOMETRIKA"], judgement: nil) }),
            ("空白理由", { try self.updateVenue(authorize: ["PSYCHOMETRIKA"], judgement: "  \n") }),
        ]
        for (label, call) in calls {
            XCTAssertThrowsError(try call(), label) { e in
                XCTAssertTrue("\(e)".contains("judgement"), "\(label)：\(e)")
            }
        }
        XCTAssertEqual(try venue(), before, "零寫入")
    }

    /// 只看參數的檢查：讀 store 之前就擋（CLI 的 `validate()` 呼叫同一個函式，#654）——對一個不存在的 store 也是這句話。
    func testReasonIsCheckedBeforeTheStoreIsRead() throws {
        XCTAssertThrowsError(try AkashicService.checkUpdateVenueArguments(
            addNames: nil, type: nil, addISSN: nil, addVariant: ["X"], authorize: nil,
            paginated: nil, clearPaginated: false, judgement: nil, restsOn: nil, removeISSN: nil)) { e in
            XCTAssertTrue("\(e)".contains("judgement"), "\(e)")
        }
        XCTAssertThrowsError(try AkashicService.checkUpdateOrganizationArguments(
            key: "iss", authorize: ["X"], judgement: nil, restsOn: nil)) { e in
            XCTAssertTrue("\(e)".contains("judgement"), "\(e)")
        }
        // organization 沒有要指定的名字時，理由單獨跟著是「沒有要改的」——沒有撤回腿可以不要理由
        XCTAssertThrowsError(try AkashicService.checkUpdateOrganizationArguments(
            key: "iss", authorize: [], judgement: "r", restsOn: nil)) { e in
            XCTAssertTrue("\(e)".contains("沒有要改的"), "\(e)")
        }
        XCTAssertNoThrow(try AkashicService.checkUpdateVenueArguments(
            addNames: nil, type: nil, addISSN: nil, addVariant: nil, authorize: ["X"],
            paginated: nil, clearPaginated: false, judgement: "r", restsOn: nil, removeISSN: nil))
    }

    /// 全部空白的腿沒有分類，不需要理由（空白項照舊回報在 *Dropped）。
    func testBlankOnlyLegsNeedNoReason() throws {
        let out = try updateVenue(authorize: ["  "], judgement: nil)
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 0)
        XCTAssertEqual(out["authorizeDropped"] as? [String], ["  "])
        XCTAssertTrue(records(try venue().references).isEmpty)
    }

    // MARK: - 每一種分類寫恰好的記錄（spec Example「records per classification」）

    func testAuthorizeWritesOneDesignationRecord() throws {
        let out = try updateVenue(authorize: ["Psychometrika"], judgement: "期刊官網刊頭")
        XCTAssertEqual(records(try venue().references), [["authorized", "Psychometrika", "指定：期刊官網刊頭"]])
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 1)
        XCTAssertEqual(try venue().authorized, ["Psychometrika"])
    }

    func testEvidenceIsCarriedOnEveryRecordOfTheCall() throws {
        try updateVenue(authorize: ["Psychometrika"], addVariant: ["PSYCHOMETRIKA"], judgement: "刊頭與 WoS 寫法", restsOn: [digest])
        XCTAssertEqual(records(try venue().references), [
            ["variant", "PSYCHOMETRIKA", "指定：刊頭與 WoS 寫法", digest],
            ["authorized", "Psychometrika", "指定：刊頭與 WoS 寫法", digest],
        ])
    }

    /// 對既有值再說一次：寫一筆「確認」（先前是無聲的 no-op）；分類不變。
    func testRestatingAnExistingDesignationWritesAConfirmation() throws {
        try updateVenue(authorize: ["Psychometrika"], judgement: "期刊官網刊頭")
        let out = try updateVenue(authorize: ["Psychometrika"], judgement: "查證後確認")
        XCTAssertEqual(out["alreadyAuthorized"] as? [String], ["Psychometrika"])
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 1)
        XCTAssertEqual(records(try venue().references), [
            ["authorized", "Psychometrika", "指定：期刊官網刊頭"],
            ["authorized", "Psychometrika", "確認：查證後確認"],
        ])
        XCTAssertEqual(try venue().authorized, ["Psychometrika"])
    }

    /// 與既有記錄位元組完全相同的不重寫。
    func testIdenticalConfirmationIsNotWrittenTwice() throws {
        try updateVenue(authorize: ["Psychometrika"], judgement: "r")
        try updateVenue(authorize: ["Psychometrika"], judgement: "查證後確認")
        let out = try updateVenue(authorize: ["Psychometrika"], judgement: "查證後確認")
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 0)
        XCTAssertEqual(records(try venue().references).count, 2)
    }

    /// 同書寫系統被換下的名字：寫一筆撤回，理由由程式組句（原因在前、呼叫端的理由在後）。
    func testDisplacedDesignationGetsAWithdrawal() throws {
        try updateVenue(authorize: ["PSYCHOMETRIKA"], judgement: "bootstrap 之後查證")
        let out = try updateVenue(authorize: ["Psychometrika"], judgement: "期刊官網刊頭")
        XCTAssertEqual(out["authorizedRemoved"] as? [String], ["PSYCHOMETRIKA"])
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 2)
        XCTAssertEqual(records(try venue().references), [
            ["authorized", "PSYCHOMETRIKA", "指定：bootstrap 之後查證"],
            ["authorized", "PSYCHOMETRIKA", "撤回：同書寫系統改指定「Psychometrika」——期刊官網刊頭"],
            ["authorized", "Psychometrika", "指定：期刊官網刊頭"],
        ])
    }

    /// 被抬出 variant 的名字：variant 那一側寫一筆撤回。
    func testNameLiftedOutOfVariantGetsAVariantWithdrawal() throws {
        try updateVenue(addVariant: ["PSYCHOMETRIKA"], judgement: "WoS 大寫形")
        let out = try updateVenue(authorize: ["PSYCHOMETRIKA"], judgement: "改以大寫形對外")
        XCTAssertEqual(out["liftedFromVariant"] as? [String], ["PSYCHOMETRIKA"])
        XCTAssertEqual(records(try venue().references), [
            ["variant", "PSYCHOMETRIKA", "指定：WoS 大寫形"],
            ["variant", "PSYCHOMETRIKA", "撤回：改指定為 authorized——改以大寫形對外"],
            ["authorized", "PSYCHOMETRIKA", "指定：改以大寫形對外"],
        ])
    }

    /// spec「A withdrawal keeps its history」：撤回之後兩筆都在，記錄照樣載入。
    func testWithdrawalKeepsHistory() throws {
        try updateVenue(authorize: ["Psychometrika"], judgement: "期刊官網刊頭")
        let out = try updateVenue(unauthorize: ["Psychometrika"], judgement: "官網已改名")
        let withdrawn = try XCTUnwrap(out["authorizedWithdrawn"] as? [[String: Any]], "\(out)")
        XCTAssertEqual(withdrawn.compactMap { $0["name"] as? String }, ["Psychometrika"], "報告與記錄說的是同一批名字（store 拼法）")
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 1)
        let v = try venue()
        XCTAssertEqual(v.authorized, [])
        XCTAssertEqual(records(v.references), [
            ["authorized", "Psychometrika", "指定：期刊官網刊頭"],
            ["authorized", "Psychometrika", "撤回：官網已改名"],
        ])
        XCTAssertTrue(try LibraryStore(root: root).load().quarantined.isEmpty)
    }

    /// #559／#564 整合：撤回的報告列（`authorizedWithdrawn` 的 `name`／`index`）與撤回記錄的 value 說的是同一批名字、都是 **store 拼法**——
    /// 輸入是 NFD 加尾隨空白時兩邊都不是輸入的拼法；多個名字一起撤回時每一列各有一筆記錄。
    func testWithdrawalRowsAndRecordsNameTheSameStoredSpellings() throws {
        try updateVenue(authorize: ["Psychometrika", "心理計量學報"], judgement: "r0")
        let nfd = "Psychometrika".decomposedStringWithCanonicalMapping + " "
        let out = try updateVenue(unauthorize: [nfd, "心理計量學報"], judgement: "官網已改名")
        let rows = try XCTUnwrap(out["authorizedWithdrawn"] as? [[String: Any]], "\(out)")
        XCTAssertEqual(rows.compactMap { $0["name"] as? String }, ["Psychometrika", "心理計量學報"])
        XCTAssertEqual(rows.compactMap { $0["index"] as? Int }, [0, 1], "位置是呼叫前在 authorized 裡的位置")
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 2)
        let withdrawals = records(try venue().references).filter { $0[2].hasPrefix("撤回：") }
        XCTAssertEqual(withdrawals.map { $0[1] }, ["Psychometrika", "心理計量學報"], "記錄的 value 與報告列的 name 同一批、同一個拼法")
    }

    func testAddVariantWritesDesignationThenConfirmation() throws {
        try updateVenue(addVariant: ["PSYCHOMETRIKA"], judgement: "WoS 大寫形")
        try updateVenue(addVariant: ["PSYCHOMETRIKA"], judgement: "再查一次")
        XCTAssertEqual(records(try venue().references), [
            ["variant", "PSYCHOMETRIKA", "指定：WoS 大寫形"],
            ["variant", "PSYCHOMETRIKA", "確認：再查一次"],
        ])
    }

    /// add_variant ＋ unauthorize 同一個名字（「它不是對外形、它是異寫」）：兩筆，各說各的分割。
    func testDemotionToVariantWritesBothRecords() throws {
        try updateVenue(authorize: ["PSYCHOMETRIKA"], judgement: "r0")
        try updateVenue(unauthorize: ["PSYCHOMETRIKA"], addVariant: ["PSYCHOMETRIKA"], judgement: "大寫形只是 WoS 的寫法")
        let v = try venue()
        XCTAssertEqual(v.authorized, [])
        XCTAssertEqual(v.variant, ["PSYCHOMETRIKA"])
        XCTAssertEqual(Array(records(v.references).dropFirst()), [
            ["variant", "PSYCHOMETRIKA", "指定：大寫形只是 WoS 的寫法"],
            ["authorized", "PSYCHOMETRIKA", "撤回：大寫形只是 WoS 的寫法"],
        ])
    }

    // MARK: - venue 的組合與上限（spec「Venue name-classification legs SHALL require a reason and SHALL NOT share a call with the paginated judgement」）

    func testPaginatedAndClassificationCannotShareACall() throws {
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                                     authorize: ["Psychometrika"], paginated: true,
                                                     judgement: "傳統頁碼刊", restsOn: [digest])) { e in
            XCTAssertTrue("\(e)".contains("paginated") && "\(e)".contains("authorize"), "\(e)")
        }
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                                     addVariant: ["PSYCHOMETRIKA"], clearPaginated: true,
                                                     judgement: "r", restsOn: [digest]))
        XCTAssertTrue(records(try venue().references).isEmpty, "零寫入")
    }

    func testReasonAndEvidenceLimits() throws {
        let long = String(repeating: "字", count: 1_400)   // 4,200 位元組
        let many = (1...21).map { "sha256:" + String(format: "%064x", $0) }
        let cases: [(String, String, [String]?)] = [
            ("理由超過 4,096 位元組", long, nil),
            ("超過 20 個 digest", "r", many),
            ("digest 形狀錯", "r", ["https://example.org"]),
            ("空內容的 digest", "r", [ProvenanceReference.emptyContentDigest]),
        ]
        for (label, judgement, restsOn) in cases {
            XCTAssertThrowsError(try updateVenue(authorize: ["Psychometrika"], judgement: judgement, restsOn: restsOn), label)
        }
        XCTAssertTrue(records(try venue().references).isEmpty, "零寫入")
    }

    /// spec「Designating on a format-21 store」。
    func testFormat21RefusesTheWrite() throws {
        try StoreVersion.write(root: root, format: 21)
        XCTAssertThrowsError(try updateVenue(authorize: ["Psychometrika"], judgement: "r")) { e in
            XCTAssertTrue("\(e)".contains("22"), "\(e)")
        }
        XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "r"))
        XCTAssertEqual(try venue().authorized, [], "零寫入")
        XCTAssertEqual(try org().authorized, [])
    }

    // MARK: - organization（spec「Organization name-classification legs SHALL require a reason」）

    func testOrganizationAuthorizeWritesARecordAndReportsIt() throws {
        let out = try payload(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"],
                                                             judgement: "所方正式英文名稱"))
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 1)
        XCTAssertEqual(records(try org().references),
                       [["authorized", "Institute of Statistical Science", "指定：所方正式英文名稱"]])
    }

    /// 指定、再確認各寫一筆；同書寫系統被換下的舊指定寫一筆撤回（authorize 的連帶後果，屬於已裁決的面）。
    func testOrganizationDesignationConfirmationAndDisplacement() throws {
        _ = try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "r1", restsOn: [digest])
        _ = try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "r2")
        _ = try service.updateOrganization(key: "iss", authorize: ["ISS"], judgement: "r3")
        XCTAssertEqual(records(try org().references), [
            ["authorized", "Institute of Statistical Science", "指定：r1", digest],
            ["authorized", "Institute of Statistical Science", "確認：r2"],
            ["authorized", "Institute of Statistical Science", "撤回：同書寫系統改指定「ISS」——r3"],
            ["authorized", "ISS", "指定：r3"],
        ])
        XCTAssertEqual(try org().authorized, ["ISS"])
    }

    func testOrganizationAuthorizeWithoutAReasonIsRefused() throws {
        XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"])) { e in
            XCTAssertTrue("\(e)".contains("judgement"), "\(e)")
        }
        XCTAssertEqual(try org().authorized, [])
        XCTAssertTrue(try org().references.isEmpty)
    }

    /// 沒有要指定的名字（沒給、空陣列、全是空白項）：沒有判定就沒有判定的理由——「沒有要改的」先拒絕，理由單獨跟著也一樣。
    /// organization 沒有撤回腿（`--unauthorize` 已於 #557 R1 verify 之後拿掉，待裁），所以理由不可能伴隨別的腿。
    func testOrganizationReasonWithoutNamesIsRefused() throws {
        _ = try service.updateOrganization(key: "iss", authorize: ["Institute of Statistical Science"], judgement: "r1")
        for names in [[], [" "]] as [[String]] {
            XCTAssertThrowsError(try service.updateOrganization(key: "iss", authorize: names, judgement: "r2"), "\(names)") { e in
                XCTAssertTrue("\(e)".contains("沒有要改的"), "\(e)")
            }
        }
        XCTAssertEqual(try org().authorized, ["Institute of Statistical Science"], "零寫入")
        XCTAssertEqual(records(try org().references), [["authorized", "Institute of Statistical Science", "指定：r1"]])
    }

    /// 證據沒有理由：拒絕（沒有判定就沒有判定的依據）。
    func testOrganizationEvidenceWithoutAReasonIsRefused() throws {
        XCTAssertThrowsError(try AkashicService.checkUpdateOrganizationArguments(
            key: "iss", authorize: ["Institute of Statistical Science"], judgement: nil, restsOn: [digest]))
    }

    // MARK: - 只由名字分類面寫入與保留（design「名字分類記錄只由名字分類面寫入與保留」）

    /// 名字分類記錄錨定 names，不是孤兒——被換下的舊指定帶著它時，替換照做（只有其他的 `field: authorized` reference 擋）。
    func testPinnedCheckIgnoresNameRecords() throws {
        try updateVenue(authorize: ["PSYCHOMETRIKA"], judgement: "r0")
        XCTAssertNoThrow(try updateVenue(authorize: ["Psychometrika"], judgement: "r1"))
        XCTAssertNoThrow(try updateVenue(unauthorize: ["Psychometrika"], judgement: "r2"))
    }

    /// `update-person` 的 references 不收名字分類記錄（只經 authorize-names）；帶 rests-on 的一般判斷照收。
    func testUpdatePersonRefusesNameRecords() throws {
        _ = try service.addPerson(key: "cheng-che", names: ["Che Cheng"], orcid: nil, openalex: nil)
        _ = try service.updatePerson(key: "cheng-che", fields: ["names": ["authorized": ["Che Cheng"], "variant": [String]()]], dryRun: false)
        let nameRecord: [String: Any] = ["field": "authorized", "value": "Che Cheng", "kind": "judgement",
                                         "statement": "指定：本人署名", "rests_on": [digest]]
        XCTAssertThrowsError(try service.updatePerson(key: "cheng-che", fields: ["references": [nameRecord]], dryRun: false)) { e in
            XCTAssertTrue("\(e)".contains("authorize-names"), "\(e)")
        }
        let general: [String: Any] = ["field": "authorized", "value": "Che Cheng", "kind": "judgement",
                                      "statement": "本人網頁的署名", "rests_on": [digest]]
        XCTAssertNoThrow(try service.updatePerson(key: "cheng-che", fields: ["references": [general]], dryRun: false))
    }

    /// venue 的移除面不刪名字分類記錄：`variant` 在解析時拒；`authorized` 只命中名字分類記錄時拒並指路。
    func testRemovalFaceDoesNotRemoveNameRecords() throws {
        try updateVenue(authorize: ["Psychometrika"], addVariant: ["PSYCHOMETRIKA"], judgement: "r")
        for field in ["authorized", "variant"] {
            let value = field == "authorized" ? "Psychometrika" : "PSYCHOMETRIKA"
            XCTAssertThrowsError(try service.committed(root).updateVenue(
                key: "some-journal", addNames: nil, note: nil, type: nil,
                removeReference: [["field": field, "value": value, "reason": "不要了"]])) { e in
                XCTAssertTrue("\(e)".contains("--unauthorize") || "\(e)".contains("unauthorize"), "\(field)：\(e)")
            }
        }
        XCTAssertEqual(records(try venue().references).count, 2, "零寫入")
    }

    /// 移除一個名字的最後一段：它若被名字分類記錄指著，具名拒絕（判定史不刪）。
    func testSegmentRemovalIsBlockedByNameRecords() throws {
        try updateVenue(authorize: ["Psychometrika"], judgement: "r0")
        try updateVenue(unauthorize: ["Psychometrika"], judgement: "r1")
        XCTAssertThrowsError(try service.committed(root).updateVenue(
            key: "some-journal", addNames: nil, note: nil, type: nil,
            editNameSegment: [["name": "Psychometrika", "remove": true, "reason": "拼錯"]])) { e in
            XCTAssertTrue("\(e)".contains("判定記錄"), "\(e)")
        }
        XCTAssertEqual(Set(try venue().names.entries.map(\.value)), ["PSYCHOMETRIKA", "Psychometrika"])
    }

    /// `repair-venue-names` 改寫一個名字的拼法時，指著那個拼法的名字分類記錄算 pinned，交給人判斷。
    func testRepairTreatsNameRecordsAsPinned() throws {
        var v = Venue(key: "k", type: .periodical, names: Timeline([TemporalValue(value: "Psychometrika "), TemporalValue(value: "PM")]),
                      authorized: ["PM"])
        v.references = [NameClassificationRecord.make(field: "authorized", name: "Psychometrika ", action: .withdraw,
                                                      reason: "r", restsOn: [])]
        let plan = try XCTUnwrap(VenueNameRepair.plan(v))
        XCTAssertNil(plan.repaired, "有判斷項就不寫")
        XCTAssertTrue(plan.judgments.contains { "\($0.reason)".contains("reference") }, "\(plan.judgments)")
    }
}
