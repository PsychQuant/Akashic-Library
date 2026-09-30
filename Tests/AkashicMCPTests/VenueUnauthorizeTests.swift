import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #559：venue 的 `authorized` 撤回面（`update-venue --unauthorize`／`akashic_update_venue.unauthorize`）。
///
/// #554 的 `authorize` 是同書寫系統替換——只能換成另一個名字，回不到「不作任何宣稱」：只有一個名字的 venue，authorized 一旦在就永遠在。
/// 使用者 2026-10-01 裁決：逐名撤回，必須是現有 authorized 成員，移出後留在 names（未標）；比照 `clear_paginated`（#500）與 `demote`（#418）。
/// 替換與撤回共用 `AuthorizedDesignation`（#557 起 organization 也用它），所以撤回的相等與 `authorize` 同一條：`NameIdentity.canonical`。
final class VenueUnauthorizeTests: XCTestCase {
    private var root: URL!
    private var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-vun-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        service = AkashicService(root: root)
        _ = try service.addVenue(key: "some-journal", names: ["PSYCHOMETRIKA", "Psychometrika"], type: "periodical", note: nil, issn: nil)
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["Psychometrika"])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func venue() throws -> Venue {
        try XCTUnwrap(LibraryStore(root: root).load().venues.first { $0.key == "some-journal" })
    }
    private func payload(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    /// `authorizedWithdrawn` 的每一列是 `{name, index}`（index＝呼叫前在 authorized 裡的位置，R1 verify）。
    private func withdrawn(_ out: [String: Any], file: StaticString = #filePath, line: UInt = #line) throws -> [[String: Any]] {
        try XCTUnwrap(out["authorizedWithdrawn"] as? [[String: Any]], "\(out)", file: file, line: line)
    }
    private func names(_ rows: [[String: Any]]) -> [String] { rows.compactMap { $0["name"] as? String } }

    /// 撤回：移出 authorized、**留在 names、不標 variant**——回到「不作任何宣稱」；報告印 store 拼法。
    func testUnauthorizeMovesTheNameOutAndLeavesItUnclassified() throws {
        XCTAssertEqual(try venue().authorized, ["Psychometrika"], "fixture")
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"]))
        let v = try venue()
        XCTAssertEqual(v.authorized, [], "撤回之後 authorized 是空的")
        XCTAssertEqual(Set(v.names.entries.map(\.value)), ["PSYCHOMETRIKA", "Psychometrika"], "名字留在 names")
        XCTAssertEqual(v.variant, [], "不標 variant——程式不替呼叫端多說「它是異寫」")
        XCTAssertEqual(names(try withdrawn(out)), ["Psychometrika"])
        XCTAssertEqual(try withdrawn(out).first?["index"] as? Int, 0)
        XCTAssertEqual(out["authorizedTotal"] as? Int, 0)
        XCTAssertEqual(v.displayName, "PSYCHOMETRIKA", "沒有 authorized 時顯示名退到 names 的第一段")
        // 撤回最後一個退到 names 的 fallback，預設顯示名真的換了（Psychometrika → PSYCHOMETRIKA）——要說出來
        XCTAssertEqual((out["displayNameChanged"] as? [String: String]), ["before": "Psychometrika", "after": "PSYCHOMETRIKA"])
    }

    /// 相等看 canonical（同 `authorize`）：尾隨空白、NFD 的輸入撤回 store 裡的那一筆，報告印 store 拼法、不印輸入。
    func testUnauthorizeMatchesCanonicallyAndReportsTheStoredSpelling() throws {
        let nfd = "Psychometrika".decomposedStringWithCanonicalMapping + " "
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: [nfd]))
        XCTAssertEqual(try venue().authorized, [])
        XCTAssertEqual(names(try withdrawn(out)), ["Psychometrika"])
    }

    /// 不是現有成員 → 整批拒絕、零寫入（同一次呼叫的其他參數也不寫）。在 names 裡但沒有被指定、完全不在 names 裡，兩種都拒。
    func testNonMemberIsRefusedAndNothingIsWritten() throws {
        for name in ["PSYCHOMETRIKA", "Journal of Nothing"] {
            XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: ["Brand New Name"], note: nil, type: nil,
                                                         unauthorize: [name])) { e in
                let m = "\(e)"
                XCTAssertTrue(m.contains("不是這筆 venue 目前的 authorized") && m.contains("Psychometrika"), "要說出現有的對外形：\(m)")
            }
            let v = try venue()
            XCTAssertEqual(v.authorized, ["Psychometrika"], "零寫入")
            XCTAssertFalse(v.names.entries.contains { $0.value == "Brand New Name" }, "同一次呼叫的 add_names 也不寫")
        }
    }

    /// 撤回空的 authorized：訊息說「現有：無」，不是一句空括號。
    func testNonMemberOfAnEmptyAuthorizedSaysNone() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"])
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"])) { e in
            XCTAssertTrue("\(e)".contains("現有：無"), "\(e)")
        }
    }

    /// 同一個名字既 authorize 又 unauthorize 是兩句矛盾的話——讀 store 之前就擋（CLI 的 `validate()` 呼叫同一個函式）。相等看 canonical。
    func testSameNameToAuthorizeAndUnauthorizeIsAContradiction() throws {
        XCTAssertThrowsError(try AkashicService.checkUpdateVenueArguments(
            addNames: nil, type: nil, addISSN: nil, addVariant: nil, authorize: ["Psychometrika"], unauthorize: ["Psychometrika "],
            paginated: nil, clearPaginated: false, judgement: nil, restsOn: nil, removeISSN: nil)) { e in
            XCTAssertTrue("\(e)".contains("同時被送進 authorize 與 unauthorize"), "\(e)")
        }
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                                     authorize: ["Psychometrika"], unauthorize: ["Psychometrika"]))
        XCTAssertEqual(try venue().authorized, ["Psychometrika"], "零寫入")
    }

    /// 整項空白是「沒說話」：不寫、回報在 unauthorizeDropped（同 authorizeDropped），不拒絕整個呼叫。
    func testBlankItemsAreDroppedAndReported() throws {
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["  "]))
        XCTAssertEqual(out["unauthorizeDropped"] as? [String], ["  "])
        XCTAssertEqual(try withdrawn(out).count, 0)
        XCTAssertNil(out["displayNameChanged"], "什麼都沒撤回，顯示名不變")
        XCTAssertEqual(try venue().authorized, ["Psychometrika"], "空白項不撤回任何東西")
    }

    /// 被 `field: authorized` 的 reference 指著的名字：撤回之後它們成孤兒——具名拒絕、零寫入、指路 `--remove-reference`（`authorize` 換下舊指定那一格同一條）。
    func testPinnedByAReferenceIsRefusedWithTheWayOut() throws {
        var v = try venue()
        v.references = [ProvenanceReference(field: "authorized", value: "Psychometrika",
                                            kind: .retrieval(url: "https://example.org/masthead", retrieved: "2026-10-01", status: 200,
                                                             mediaType: "text/html", content: "sha256:" + String(repeating: "ab", count: 32)))]
        try LibraryStore(root: root).writeVenue(v)
        XCTAssertThrowsError(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"])) { e in
            let m = "\(e)"
            XCTAssertTrue(m.contains("field: authorized") && m.contains("--remove-reference") && m.contains("再重跑"), m)
        }
        let after = try venue()
        XCTAssertEqual(after.authorized, ["Psychometrika"], "零寫入")
        XCTAssertEqual(after.references.count, 1, "reference 不動——程式不替人改判定")
    }

    /// 撤回先於指定：成員資格看呼叫前的 authorized，「撤回 A、指定 B」不因兩條腿的順序而變——A 報在 authorizedWithdrawn，
    /// 不是 authorizedRemoved（它不是被 B 換下來的）。
    func testWithdrawAndAuthorizeInOneCall() throws {
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                                      authorize: ["PSYCHOMETRIKA"], unauthorize: ["Psychometrika"]))
        XCTAssertEqual(try venue().authorized, ["PSYCHOMETRIKA"])
        XCTAssertEqual(names(try withdrawn(out)), ["Psychometrika"])
        XCTAssertEqual(out["authorizedAdded"] as? [String], ["PSYCHOMETRIKA"])
        XCTAssertEqual(out["authorizedRemoved"] as? [String], [])
    }

    /// 與 add_variant 給同一個名字是明說「它不是對外形、它是異寫」——照做（不是矛盾）；只給 unauthorize 則不標。
    func testAddVariantWithUnauthorizeDemotesExplicitly() throws {
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil,
                                                      addVariant: ["Psychometrika"], unauthorize: ["Psychometrika"]))
        let v = try venue()
        XCTAssertEqual(v.authorized, [])
        XCTAssertEqual(v.variant, ["Psychometrika"])
        XCTAssertEqual(out["variantAdded"] as? [String], ["Psychometrika"])
        XCTAssertEqual(names(try withdrawn(out)), ["Psychometrika"])
    }

    /// 只撤回指名的那一個：雙語記錄撤回拉丁名，漢字名留著。
    func testOnlyTheNamedDesignationIsWithdrawn() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["心理計量學報"])
        XCTAssertEqual(Set(try venue().authorized), ["Psychometrika", "心理計量學報"], "fixture")
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"])
        XCTAssertEqual(try venue().authorized, ["心理計量學報"])
    }

    /// 撤回之後 `authorize` 把名字指定回來——名字與分類都回得來（名字一直在 names）。**不是精確逆操作**：位置回不來，見下一個測試。
    func testAuthorizeBringsAWithdrawnNameBack() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"])
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["Psychometrika"]))
        XCTAssertEqual(try venue().authorized, ["Psychometrika"])
        XCTAssertEqual(out["authorizedAdded"] as? [String], ["Psychometrika"])
        XCTAssertEqual(out["namesAdded"] as? [String], [], "名字一直在 names，不必再加")
    }

    /// R1 verify（#559 第 5／9／11／18／23 列）：**撤回再指定不是精確逆操作**——`authorize` 對不在 authorized 裡的名字接在尾端，
    /// `displayName` 取 `authorized.first`，多書寫系統 venue 的預設顯示名換了書寫系統。這個測試釘住那個事實（不是要它發生，是不讓文字再說成「逆操作」）；
    /// 撤回的報告因此帶原 index 與 `displayNameChanged`。
    func testUnauthorizeThenAuthorizeDoesNotRestoreThePosition() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["心理計量學報"])
        XCTAssertEqual(try venue().authorized, ["Psychometrika", "心理計量學報"], "fixture：Psychometrika 在第 0 個、是預設顯示名")
        XCTAssertEqual(try venue().displayName, "Psychometrika")
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"]))
        XCTAssertEqual(try withdrawn(out).first?["index"] as? Int, 0, "報告帶撤回前的位置")
        XCTAssertEqual(out["displayNameChanged"] as? [String: String], ["before": "Psychometrika", "after": "心理計量學報"],
                       "撤回 authorized 的第一個（≥2 個時）：預設顯示名換成下一個")
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["Psychometrika"])
        XCTAssertEqual(try venue().authorized, ["心理計量學報", "Psychometrika"], "指定回來接在尾端，不回原位")
        XCTAssertEqual(try venue().displayName, "心理計量學報", "預設顯示名沒有回來")
    }

    /// 一次撤回多個：位置都以**呼叫前**的清單算；撤回的不是第一個、顯示名不變時不報 `displayNameChanged`。
    func testIndexesAreReportedAgainstTheListBeforeTheCall() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["心理計量學報", "Мир"])
        XCTAssertEqual(try venue().authorized, ["Psychometrika", "心理計量學報", "Мир"], "fixture：三個書寫系統各一個")
        let second = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["心理計量學報"]))
        XCTAssertEqual(try withdrawn(second).first?["index"] as? Int, 1)
        XCTAssertNil(second["displayNameChanged"], "撤回的不是第一個，預設顯示名不變")
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["心理計量學報"])
        XCTAssertEqual(try venue().authorized, ["Psychometrika", "Мир", "心理計量學報"], "fixture：清單重排成 [Psychometrika, Мир, 心理計量學報]")
        let both = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["心理計量學報", "Psychometrika"]))
        let rows = try withdrawn(both)
        XCTAssertEqual(rows.compactMap { $0["index"] as? Int }.sorted(), [0, 2], "位置以呼叫前的清單算，不因先撤回哪一個而位移")
        XCTAssertEqual(try venue().authorized, ["Мир"])
    }

    /// 單獨呼叫的兩條腿（remove_reference、edit_name_segment）不與 unauthorize 組合。
    func testStandaloneLegsRefuseUnauthorize() throws {
        XCTAssertThrowsError(try AkashicService.checkUpdateVenueArguments(
            addNames: nil, type: nil, addISSN: nil, addVariant: nil, authorize: nil, unauthorize: ["Psychometrika"],
            paginated: nil, clearPaginated: false, judgement: nil, restsOn: nil, removeISSN: nil,
            editNameSegment: [["name": "Psychometrika", "set": ["note": "n"], "reason": "r"]])) { e in
            XCTAssertTrue("\(e)".contains("unauthorize"), "要點名衝突的參數：\(e)")
        }
    }
}
