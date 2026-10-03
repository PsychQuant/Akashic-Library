import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #564 修正輪（R1 verify b26 F1／F2；使用者 2026-10-02 的四點裁決）：
///
/// - 記錄只對**同一個名字同一個分割的最後一筆**去重——撤回之後以同一句理由再指定，會留第三筆（不是被當成重複丟掉）。
/// - 理由開頭不得是組合符號或不可見字元、要有字母或數字（記錄的文法讀得出來、必填不能以看不見的字串滿足）。
/// - 名字分類的寫入面一次至多 200 個名字（裁決第 4 點）。
/// - person 的 `fields.names` 動到 authorized 要理由並寫記錄（裁決第 1 點）。
/// - 最後一筆記錄是撤回的名字可以連同記錄一起刪：venue 走 `edit_name_segment` 的 remove、organization／person 走 `remove_names`（裁決第 2 點）。
final class NameClassificationCorrectionTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!
    private let digest = "sha256:" + String(repeating: "cd", count: 32)

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-ncc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        _ = try service.addVenue(key: "tg", names: ["Some Journal"], type: "periodical", note: nil, issn: nil)
        _ = try service.addOrganization(key: "org2", names: ["Alpha Institute", "Beta Institute"])
        _ = try service.addPerson(key: "smith-j", names: ["Smith, Jhon", "Smith, J."], orcid: nil, openalex: nil)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue() throws -> Venue { try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "tg" }) }
    private func org() throws -> Organization { try XCTUnwrap(LibraryStore(root: root).load().organizations.first { $0.key == "org2" }) }
    private func person() throws -> Person { try XCTUnwrap(LibraryStore(root: root).load().people.first { $0.key == "smith-j" }) }
    private func payload(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func msg(_ e: Error) -> String { (e as? LocalizedError)?.errorDescription ?? "\(e)" }
    /// 名字分類記錄的 [field, value, statement]，依 references 的順序
    private func records(_ refs: [ProvenanceReference]) -> [[String]] {
        refs.filter(NameClassificationRecord.isRecord).map { r in
            guard case .judgement(let statement, _) = r.kind else { return [] }
            return [r.field, r.value ?? "", statement]
        }
    }
    @discardableResult
    private func venueCall(authorize: [String]? = nil, unauthorize: [String]? = nil, addVariant: [String]? = nil,
                           judgement: String?, restsOn: [String]? = nil) throws -> [String: Any] {
        try payload(try service.updateVenue(key: "tg", addNames: nil, note: nil, type: nil, addVariant: addVariant,
                                            authorize: authorize, unauthorize: unauthorize, judgement: judgement, restsOn: restsOn))
    }
    @discardableResult
    private func personNames(authorized: [String], variant: [String], judgement: String? = nil, dryRun: Bool = false) throws -> [String: Any] {
        try payload(try service.updatePerson(key: "smith-j", fields: ["names": ["authorized": authorized, "variant": variant]],
                                             dryRun: dryRun, judgement: judgement))
    }

    // MARK: - 去重只比最後一筆（b26 F1 第 1／2／5／13 列、F2 第 3 列）

    /// 指定 R → 撤回 S → 再以 R 指定：第三筆要寫，最後一筆是「指定」（名字回到 authorized，記錄也要說回到了）。
    func testRedesignationAfterWithdrawalWithTheSameReasonIsRecorded() throws {
        try venueCall(authorize: ["Some Journal"], judgement: "官網確認")
        try venueCall(unauthorize: ["Some Journal"], judgement: "查錯了")
        let out = try venueCall(authorize: ["Some Journal"], judgement: "官網確認")
        XCTAssertEqual(out["authorizedAdded"] as? [String], ["Some Journal"])
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 1, "名字回到 authorized，記錄不能沒有寫")
        XCTAssertEqual(records(try venue().references), [
            ["authorized", "Some Journal", "指定：官網確認"],
            ["authorized", "Some Journal", "撤回：查錯了"],
            ["authorized", "Some Journal", "指定：官網確認"],
        ])
        XCTAssertEqual(NameClassificationRecord.latestAction(in: try venue().references, name: "Some Journal"), .designate)
    }

    /// organization 的「換下再換回」（同根）：換回的那筆「指定」要寫。
    func testOrganizationReplaceThenRestoreRecordsTheRestoredDesignation() throws {
        _ = try service.updateOrganization(key: "org2", authorize: ["Alpha Institute"], judgement: "官網")
        _ = try service.updateOrganization(key: "org2", authorize: ["Beta Institute"], judgement: "改名後官網")
        let out = try payload(try service.updateOrganization(key: "org2", authorize: ["Alpha Institute"], judgement: "官網"))
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 2, "Alpha 的指定與 Beta 的撤回各一筆：\(out)")
        XCTAssertEqual(try org().authorized, ["Alpha Institute"])
        XCTAssertEqual(NameClassificationRecord.latestAction(in: try org().references, name: "Alpha Institute"), .designate)
        XCTAssertEqual(NameClassificationRecord.latestAction(in: try org().references, name: "Beta Institute"), .withdraw)
    }

    /// 同一句理由連續確認兩次仍只留一筆（冪等不變）。
    func testRepeatedIdenticalConfirmationStaysSingle() throws {
        try venueCall(authorize: ["Some Journal"], judgement: "官網確認")
        let again = try venueCall(authorize: ["Some Journal"], judgement: "官網確認")
        XCTAssertEqual(again["judgementsRecorded"] as? Int, 1, "指定之後的確認是一次新的動作")
        let third = try venueCall(authorize: ["Some Journal"], judgement: "官網確認")
        XCTAssertEqual(third["judgementsRecorded"] as? Int, 0, "與最後一筆位元組相同才不寫")
        XCTAssertEqual(records(try venue().references).count, 2)
    }

    // MARK: - 理由的形狀（b26 F2 第 6／19／33／34 列）

    /// 開頭是組合符號（帶 rests_on 也一樣）：拒絕、零寫入——先前它會悄悄寫成一筆一般的 `field: authorized` reference。
    func testReasonStartingWithACombiningMarkIsRefused() throws {
        let before = try venue()
        for lead in ["\u{0301}", "\u{200C}", "\u{200D}", "\u{034F}", "\u{FE0F}", "\u{2060}"] {
            XCTAssertThrowsError(try venueCall(authorize: ["Some Journal"], judgement: lead + "原因", restsOn: [digest]),
                                 "U+\(String(lead.unicodeScalars.first!.value, radix: 16))") { e in
                XCTAssertTrue(msg(e).contains("開頭"), msg(e))
            }
            XCTAssertThrowsError(try service.updateOrganization(key: "org2", authorize: ["Alpha Institute"], judgement: lead + "原因"))
        }
        XCTAssertEqual(try venue(), before, "零寫入")
        XCTAssertTrue(try org().references.isEmpty)
    }

    /// 只有不可見字元的理由不算給了理由。
    func testInvisibleOnlyReasonIsRefused() throws {
        for reason in ["\u{2060}", "\u{FEFF}", "\u{3164}", "\u{2800}", "\u{00AD}", "\u{180E}"] {
            XCTAssertThrowsError(try venueCall(authorize: ["Some Journal"], judgement: reason), reason.unicodeScalars.map { String($0.value, radix: 16) }.joined())
        }
        XCTAssertNil(NameClassificationRecord.reasonIssue("期刊官網刊頭"))
        XCTAssertNil(NameClassificationRecord.reasonIssue("1843"))
        XCTAssertNotNil(NameClassificationRecord.reasonIssue("——"), "沒有字母或數字")
    }

    /// 解析在 scalar 上比前綴：已經在庫裡、理由以組合符號開頭的記錄仍被認成記錄（不會被當成可移除的一般 reference）。
    func testParseComparesThePrefixOnScalars() {
        let statement = "指定：" + "\u{0301}原因"
        XCTAssertFalse(statement.hasPrefix("指定："), "前提：Character 層的前綴比不上")
        XCTAssertEqual(NameClassificationRecord.parse(statement)?.action, .designate)
        XCTAssertEqual(NameClassificationRecord.parse(statement)?.reason, "\u{0301}原因")
    }

    // MARK: - 一次至多 200 個名字（裁決第 4 點）

    func testClassificationCallsAreCappedAtTwoHundredNames() throws {
        let many = (1...201).map { "Journal \($0)" }
        let before = try venue()
        XCTAssertThrowsError(try venueCall(addVariant: many, judgement: "批次")) { e in
            XCTAssertTrue(msg(e).contains("200") && msg(e).contains("201"), msg(e))
        }
        // 三條腿合計
        XCTAssertThrowsError(try venueCall(authorize: ["Some Journal"], addVariant: Array(many.prefix(200)), judgement: "批次"))
        XCTAssertEqual(try venue(), before, "零寫入")
        XCTAssertNoThrow(try venueCall(addVariant: Array(many.prefix(200)), judgement: "批次"), "剛好 200 個可以")
        XCTAssertThrowsError(try service.updateOrganization(key: "org2", authorize: many, judgement: "批次")) { e in
            XCTAssertTrue(msg(e).contains("200"), msg(e))
        }
        // person 只數 authorized（#564 R2 verify：b29 V1 第 9 列——variant 不寫記錄）
        XCTAssertThrowsError(try personNames(authorized: many, variant: [], judgement: "批次")) { e in
            XCTAssertTrue(msg(e).contains("200"), msg(e))
        }
    }

    /// add_variant 對已是異寫的名字寫「確認」，報告說是哪幾個（b26 F2 第 18 列）。
    func testVariantConfirmationIsNamedInTheReport() throws {
        try venueCall(addVariant: ["SOME JOURNAL"], judgement: "WoS 大寫形")
        let out = try venueCall(addVariant: ["SOME JOURNAL"], judgement: "再查一次")
        XCTAssertEqual(out["variantAdded"] as? [String], [])
        XCTAssertEqual(out["variantConfirmed"] as? [String], ["SOME JOURNAL"])
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 1)
    }

    // MARK: - person 的 fields.names（裁決第 1 點）

    func testPersonAuthorizedChangeNeedsAReason() throws {
        let before = try person()
        XCTAssertThrowsError(try personNames(authorized: ["Smith, Jhon"], variant: ["Smith, J."])) { e in
            XCTAssertTrue(msg(e).contains("judgement") && msg(e).contains("Smith, Jhon"), msg(e))
        }
        XCTAssertEqual(try person(), before, "零寫入")
        let out = try personNames(authorized: ["Smith, Jhon"], variant: ["Smith, J."], judgement: "本人網頁署名")
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 1)
        XCTAssertEqual(records(try person().references), [["authorized", "Smith, Jhon", "指定：本人網頁署名"]])
    }

    /// 只動 variant（authorized 不變）不需要理由、不寫記錄。
    func testPersonVariantOnlyChangeNeedsNoReason() throws {
        let out = try personNames(authorized: [], variant: ["Smith, Jhon", "Smith, J.", "J. Smith"])
        XCTAssertNil(out["judgementsRecorded"])
        XCTAssertTrue(records(try person().references).isEmpty)
    }

    /// 換對外形：舊的撤回、新的指定；附理由而 authorized 不變時是「確認」（person 的確認面）。
    func testPersonReplacementWritesWithdrawalDesignationAndConfirmation() throws {
        try personNames(authorized: ["Smith, Jhon"], variant: ["Smith, J."], judgement: "批次採用")
        let out = try personNames(authorized: ["Smith, John"], variant: ["Smith, J.", "Smith, Jhon"], judgement: "拼錯了")
        XCTAssertEqual(out["judgementsRecorded"] as? Int, 2)
        let again = try personNames(authorized: ["Smith, John"], variant: ["Smith, J.", "Smith, Jhon"], judgement: "查證後確認")
        XCTAssertEqual(again["judgementsRecorded"] as? Int, 1)
        XCTAssertEqual(records(try person().references), [
            ["authorized", "Smith, Jhon", "指定：批次採用"],
            ["authorized", "Smith, Jhon", "撤回：拼錯了"],
            ["authorized", "Smith, John", "指定：拼錯了"],
            ["authorized", "Smith, John", "確認：查證後確認"],
        ])
    }

    /// 替換拿掉一個有記錄的名字：具名拒絕並指出口（remove_names）——先前是附著驗證的錯誤，不給出路。
    func testPersonReplacementDroppingARecordedNameIsRefusedWithAWayOut() throws {
        try personNames(authorized: ["Smith, Jhon"], variant: ["Smith, J."], judgement: "批次採用")
        let before = try person()
        XCTAssertThrowsError(try personNames(authorized: ["Smith, John"], variant: ["Smith, J."], judgement: "拼錯了")) { e in
            XCTAssertTrue(msg(e).contains("--remove-name") && msg(e).contains("Smith, Jhon"), msg(e))
        }
        XCTAssertEqual(try person(), before, "零寫入")
    }

    /// 理由只伴隨 names；dry_run 預告會寫幾筆。
    func testPersonReasonWithoutNamesIsRefusedAndDryRunPreviewsRecords() throws {
        XCTAssertThrowsError(try service.updatePerson(key: "smith-j", fields: ["note": "n"], dryRun: false, judgement: "r")) { e in
            XCTAssertTrue(msg(e).contains("fields.names"), msg(e))
        }
        let before = try person()
        let preview = try personNames(authorized: ["Smith, Jhon"], variant: ["Smith, J."], judgement: "r", dryRun: true)
        XCTAssertEqual(preview["judgementsToRecord"] as? Int, 1)
        XCTAssertEqual(try person(), before, "dry_run 零寫入")
    }

    // MARK: - 最後一筆是撤回的名字可以連同記錄一起刪（裁決第 2 點）

    /// venue：打錯字的名字（`--authorize` 會一併加進 names）撤回之後，`edit_name_segment` 的 remove 連同記錄一起刪。
    func testVenueWithdrawnTypoIsRemovedWithItsRecords() throws {
        try venueCall(authorize: ["Psychometrka"], judgement: "oops")
        try venueCall(authorize: ["Some Journal"], judgement: "正式刊名")   // 換下 Psychometrka（同書寫系統）→ 撤回
        let out = try payload(try service.committed(root).updateVenue(
            key: "tg", addNames: nil, note: nil, type: nil,
            editNameSegment: [["name": "Psychometrka", "remove": true, "reason": "拼錯了"]]))
        XCTAssertEqual(out["judgementRecordsRemoved"] as? Int, 2, "\(out)")
        let v = try venue()
        XCTAssertFalse(v.names.entries.contains { $0.value == "Psychometrka" })
        XCTAssertEqual(records(v.references).map { $0[1] }, ["Some Journal"])
    }

    /// venue：最後一筆不是撤回（只可能是手改）——拒絕，並說「先撤回，再刪」。
    func testVenueNameWhoseLastRecordIsNotAWithdrawalIsRefused() throws {
        var v = try venue()
        v.names = Timeline(v.names.entries + [TemporalValue(value: "Hand Edited")])
        v.references.append(NameClassificationRecord.make(field: "authorized", name: "Hand Edited", action: .designate, reason: "手改", restsOn: []))
        try LibraryStore(root: root).writeVenue(v)
        XCTAssertThrowsError(try service.committed(root).updateVenue(
            key: "tg", addNames: nil, note: nil, type: nil,
            editNameSegment: [["name": "Hand Edited", "remove": true, "reason": "不要了"]])) { e in
            XCTAssertTrue(msg(e).contains("先撤回") && msg(e).contains("指定"), msg(e))
        }
        XCTAssertTrue(try venue().names.entries.contains { $0.value == "Hand Edited" }, "零寫入")
    }

    /// organization：被換下的名字（最後一筆是撤回）可以刪；還是對外名稱、沒有記錄的都拒絕；檔案要已 commit。
    func testOrganizationRemoveNamesOnlyTakesWithdrawnNames() throws {
        _ = try service.updateOrganization(key: "org2", authorize: ["Alpha Institutte"], judgement: "oops")
        _ = try service.updateOrganization(key: "org2", authorize: ["Alpha Institute"], judgement: "正式名稱")
        XCTAssertThrowsError(try service.updateOrganization(key: "org2", authorize: [], removeNames: ["Alpha Institutte=拼錯"])) { e in
            XCTAssertTrue(msg(e).contains("git") || msg(e).contains("commit"), "未 commit 要拒：\(msg(e))")
        }
        let committed = service.committed(root)
        XCTAssertThrowsError(try committed.updateOrganization(key: "org2", authorize: [], removeNames: ["Alpha Institute=不要"])) { e in
            XCTAssertTrue(msg(e).contains("authorized") && msg(e).contains("先撤回"), msg(e))
        }
        XCTAssertThrowsError(try committed.updateOrganization(key: "org2", authorize: [], removeNames: ["Beta Institute=不要"])) { e in
            XCTAssertTrue(msg(e).contains("沒有名字分類的判定記錄"), msg(e))
        }
        let out = try payload(try committed.updateOrganization(key: "org2", authorize: [], removeNames: ["Alpha Institutte=拼錯了"]))
        let removed = try XCTUnwrap(out["namesRemoved"] as? [[String: Any]], "\(out)")
        XCTAssertEqual(removed.first?["reason"] as? String, "拼錯了")
        XCTAssertEqual(removed.first?["recordsRemoved"] as? Int, 2)
        let o = try org()
        XCTAssertFalse(o.names.entries.contains { $0.value == "Alpha Institutte" })
        XCTAssertEqual(Set(records(o.references).map { $0[1] }), ["Alpha Institute"])
        // 單獨呼叫
        XCTAssertThrowsError(try AkashicService.checkUpdateOrganizationArguments(
            key: "org2", authorize: ["X"], judgement: "r", removeNames: ["Y=z"]))
    }

    /// person：先在 names 把錯拼法移到 variant（寫撤回），再 remove_names 連同記錄刪掉。
    func testPersonWithdrawnNameIsRemovedWithItsRecords() throws {
        try personNames(authorized: ["Smith, Jhon"], variant: ["Smith, J."], judgement: "批次採用")
        XCTAssertThrowsError(try service.committed(root).updatePerson(key: "smith-j", fields: [:], dryRun: false, fieldsGiven: false,
                                                                      removeNames: ["Smith, Jhon=拼錯"])) { e in
            XCTAssertTrue(msg(e).contains("authorized") && msg(e).contains("先撤回"), msg(e))
        }
        try personNames(authorized: ["Smith, John"], variant: ["Smith, J.", "Smith, Jhon"], judgement: "拼錯了")
        let preview = try payload(try service.updatePerson(key: "smith-j", fields: [:], dryRun: true, fieldsGiven: false,
                                                           removeNames: ["Smith, Jhon=拼錯了"]))
        XCTAssertEqual(preview["dryRun"] as? Bool, true)
        XCTAssertTrue(try person().names.variant.contains("Smith, Jhon"), "dry_run 零寫入")
        let out = try payload(try service.committed(root).updatePerson(key: "smith-j", fields: [:], dryRun: false, fieldsGiven: false,
                                                                       removeNames: ["Smith, Jhon=拼錯了"]))
        XCTAssertEqual((out["namesRemoved"] as? [[String: Any]])?.first?["recordsRemoved"] as? Int, 2, "\(out)")
        let p = try person()
        XCTAssertEqual(p.names.all.sorted(), ["Smith, J.", "Smith, John"])
        XCTAssertEqual(records(p.references).map { $0[1] }, ["Smith, John"])
        // 不與 fields 組合
        XCTAssertThrowsError(try service.updatePerson(key: "smith-j", fields: ["note": "n"], dryRun: false, removeNames: ["X=y"]))
    }
}
