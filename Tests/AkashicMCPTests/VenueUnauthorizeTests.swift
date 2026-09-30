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

    /// 撤回：移出 authorized、**留在 names、不標 variant**——回到「不作任何宣稱」；報告印 store 拼法。
    func testUnauthorizeMovesTheNameOutAndLeavesItUnclassified() throws {
        XCTAssertEqual(try venue().authorized, ["Psychometrika"], "fixture")
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"]))
        let v = try venue()
        XCTAssertEqual(v.authorized, [], "撤回之後 authorized 是空的")
        XCTAssertEqual(Set(v.names.entries.map(\.value)), ["PSYCHOMETRIKA", "Psychometrika"], "名字留在 names")
        XCTAssertEqual(v.variant, [], "不標 variant——程式不替呼叫端多說「它是異寫」")
        XCTAssertEqual(out["authorizedWithdrawn"] as? [String], ["Psychometrika"])
        XCTAssertEqual(out["authorizedTotal"] as? Int, 0)
        XCTAssertEqual(v.displayName, "PSYCHOMETRIKA", "沒有 authorized 時顯示名退到 names 的第一段")
    }

    /// 相等看 canonical（同 `authorize`）：尾隨空白、NFD 的輸入撤回 store 裡的那一筆，報告印 store 拼法、不印輸入。
    func testUnauthorizeMatchesCanonicallyAndReportsTheStoredSpelling() throws {
        let nfd = "Psychometrika".decomposedStringWithCanonicalMapping + " "
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: [nfd]))
        XCTAssertEqual(try venue().authorized, [])
        XCTAssertEqual(out["authorizedWithdrawn"] as? [String], ["Psychometrika"])
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
        XCTAssertEqual(out["authorizedWithdrawn"] as? [String], [])
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
        XCTAssertEqual(out["authorizedWithdrawn"] as? [String], ["Psychometrika"])
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
        XCTAssertEqual(out["authorizedWithdrawn"] as? [String], ["Psychometrika"])
    }

    /// 只撤回指名的那一個：雙語記錄撤回拉丁名，漢字名留著。
    func testOnlyTheNamedDesignationIsWithdrawn() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["心理計量學報"])
        XCTAssertEqual(Set(try venue().authorized), ["Psychometrika", "心理計量學報"], "fixture")
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"])
        XCTAssertEqual(try venue().authorized, ["心理計量學報"])
    }

    /// 撤回可逆：`authorize` 把它指定回來。
    func testAuthorizeRestoresAWithdrawnName() throws {
        _ = try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, unauthorize: ["Psychometrika"])
        let out = try payload(try service.updateVenue(key: "some-journal", addNames: nil, note: nil, type: nil, authorize: ["Psychometrika"]))
        XCTAssertEqual(try venue().authorized, ["Psychometrika"])
        XCTAssertEqual(out["authorizedAdded"] as? [String], ["Psychometrika"])
        XCTAssertEqual(out["namesAdded"] as? [String], [], "名字一直在 names，不必再加")
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
