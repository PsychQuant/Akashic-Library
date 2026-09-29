import XCTest
@testable import AkashicCore
@testable import AkashicMCPKit
@testable import AkashicStoreIO

/// #673：`update-venue --remove-reference`／`akashic_update_venue.remove_reference`，以及 venue 讀取面的 `references`。
/// 契約見 `VenueReferenceRemoval.swift` 的檔頭。逐條釘住：只移除被定位到的那一筆（別的 reference、號與名字本身都不動）、
/// 理由只進報告且不截斷、未 commit／不在 git 拒絕、輸入錯與定位不到／定位到多筆整批拒絕零寫入、verdict 與 `paginated` 具名拒絕並指路、
/// 不與任何其他腿組合、key 重複時拒絕、venue 讀取面看得到通用 references。
final class VenueReferenceRemovalTests: XCTestCase {
    private var root: URL!
    private var store: LibraryStore!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("akashic-venue-refrm-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private var service: AkashicService { AkashicService(root: root) }
    private let digest = "sha256:" + String(repeating: "ab", count: 32)
    private let otherDigest = "sha256:" + String(repeating: "cd", count: 32)

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }
    private func venue(_ key: String = "ampsy") throws -> Venue {
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
    private func retrieval(field: String = "issn", value: String? = "0003-066X", url: String = "https://portal.issn.org/resource/ISSN/0003-066X",
                           retrieved: String = "2026-09-29") -> [String: Any] {
        var d: [String: Any] = ["field": field, "kind": "retrieval", "url": url, "retrieved": retrieved, "status": 200,
                                "media_type": "text/html", "content": digest]
        if let value { d["value"] = value }
        return d
    }
    private func judgement(field: String = "names", value: String = "American Psychologist", statement: String = "ISSN Portal 的刊名") -> [String: Any] {
        ["field": field, "value": value, "kind": "judgement", "statement": statement, "rests_on": [digest]]
    }
    /// 種一筆 venue，帶兩個 ISSN、一個 name 的來源、一個第二次取得的 issn 來源。
    private func seed() throws {
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"], type: "periodical", note: nil,
                                 issn: ["0003-066X (print)", "1935-990X (electronic)"])
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: [
            retrieval(), retrieval(value: "1935-990X", url: "https://portal.issn.org/resource/ISSN/1935-990X"), judgement(),
        ])
    }
    private func remove(_ items: [Any], on svc: AkashicService? = nil) throws -> [String: Any] {
        try json(try (svc ?? service).updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, removeReference: items))
    }
    private func item(_ field: String, _ value: String?, reason: String = "寫錯了", extra: [String: Any] = [:]) -> [String: Any] {
        var d: [String: Any] = ["field": field, "reason": reason]
        if let value { d["value"] = value }
        return d.merging(extra) { _, new in new }
    }

    // MARK: - 移除

    func testRemovesOnlyTheLocatedReferenceAndLeavesTheValueItPointedAt() throws {
        try seed()
        let out = try remove([item("issn", "1935-990X", reason: "這個號的來源網址貼錯本刊")], on: service.committed(root))
        let v = try venue()
        XCTAssertEqual(v.references.map(\.field), ["issn", "names"], "另外兩筆 reference 不動")
        XCTAssertEqual(v.references.first?.value, "0003-066X")
        XCTAssertEqual(v.issn.map(\.normalized), ["0003-066X", "1935-990X"], "只移除 reference，它指的號仍在——移除號是 --remove-issn 的事")
        XCTAssertEqual(v.names.entries.map(\.value), ["American Psychologist"])
        let removed = try XCTUnwrap((out["referencesRemoved"] as? [[String: Any]])?.first)
        XCTAssertEqual(removed["field"] as? String, "issn")
        XCTAssertEqual(removed["value"] as? String, "1935-990X")
        XCTAssertEqual(removed["kind"] as? String, "retrieval")
        XCTAssertEqual(removed["url"] as? String, "https://portal.issn.org/resource/ISSN/1935-990X", "報告要讓人認得出移除的是哪一筆——它只剩 git 那份副本")
        XCTAssertEqual(removed["reason"] as? String, "這個號的來源網址貼錯本刊")
        XCTAssertEqual(out["referencesTotal"] as? Int, 2)
        XCTAssertTrue((out["reasonNote"] as? String)?.contains("commit message") == true)
    }

    func testJudgementReferencesAreRemovableAndReportedWithTheirStatement() throws {
        try seed()
        let out = try remove([item("names", "American Psychologist")], on: service.committed(root))
        XCTAssertEqual(try venue().references.map(\.field), ["issn", "issn"])
        let removed = try XCTUnwrap((out["referencesRemoved"] as? [[String: Any]])?.first)
        XCTAssertEqual(removed["kind"] as? String, "judgement")
        XCTAssertEqual(removed["statement"] as? String, "ISSN Portal 的刊名")
        XCTAssertEqual(removed["rests_on"] as? [String], [digest])
    }

    func testSeveralInOneCallAreAllRemoved() throws {
        try seed()
        let out = try remove([item("issn", "0003-066X", reason: "a"), item("names", "American Psychologist", reason: "b")], on: service.committed(root))
        XCTAssertEqual(try venue().references.map(\.value), ["1935-990X"])
        XCTAssertEqual((out["referencesRemoved"] as? [[String: Any]])?.compactMap { $0["reason"] as? String }, ["a", "b"])
    }

    func testReasonIsInTheReportInFullAndNotInTheStore() throws {
        try seed()
        let reason = String(repeating: "貼錯了", count: 400)   // 3,600 位元組：比 displaySafe 的預設上限長，不得被截
        let out = try remove([item("issn", "0003-066X", reason: reason)], on: service.committed(root))
        XCTAssertEqual((out["referencesRemoved"] as? [[String: Any]])?.first?["reason"] as? String, reason, "理由只在報告裡，所以要全文")
        let file = try XCTUnwrap(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("entities").path).first)
        XCTAssertFalse(try String(contentsOf: root.appendingPathComponent("entities/\(file)"), encoding: .utf8).contains("貼錯了貼錯了"), "理由不寫進 store")
    }

    /// 定位用**位元組**：canonical 相等而位元組不同的 value 是另一筆（與寫入面的去重同一把）。
    func testLocationIsByBytesNotCanonicalEquivalence() throws {
        _ = try service.addVenue(key: "ampsy", names: ["Sankhyā"], type: "periodical", note: nil)
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: [judgement(value: "Sankhyā")])
        // NFD 拼法（a + U+0304）與 store 上的 NFC 拼法 canonical 相等、位元組不同
        let nfd = "Sankhya\u{0304}"
        XCTAssertEqual(nfd, "Sankhyā", "前提：Swift 的 == 把兩者視為相等")
        StoreGitCommit.commitAll(root)
        XCTAssertThrowsError(try remove([item("names", nfd)])) { err in
            XCTAssertTrue(String(describing: err).contains("沒有"), "\(err)")
        }
        XCTAssertEqual(try venue().references.count, 1)
    }

    /// 同一 (field, value) 兩筆而位元組不同（兩次取得）：不加縮小的鍵就拒絕並列出區別；加 `url` 縮小之後定位得到。
    func testSeveralMatchesAreRefusedUntilNarrowed() throws {
        try seed()
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: [
            retrieval(url: "https://www.crossref.org/x", retrieved: "2026-09-30")])
        let svc = service.committed(root)
        let before = try snapshot()
        XCTAssertThrowsError(try remove([item("issn", "0003-066X")], on: svc)) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("2 筆"), s)
            XCTAssertTrue(s.contains("portal.issn.org") && s.contains("crossref.org"), "要列出各筆的區別：\(s)")
            XCTAssertFalse(s.contains("寫不出「沒有 media_type」"), "這兩筆的差別是 url，不是 media_type 的有無——不提那個限制：\(s)")
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
        _ = try remove([item("issn", "0003-066X", extra: ["url": "https://www.crossref.org/x"])], on: svc)
        XCTAssertEqual(try venue().references.compactMap { r -> String? in
            if case .retrieval(let url, _, _, _, _) = r.kind, r.field == "issn", r.value == "0003-066X" { return url } else { return nil }
        }, ["https://portal.issn.org/resource/ISSN/0003-066X"], "只移除縮小到的那一筆")
    }

    /// 同一 (field, value) 一筆 retrieval、一筆 judgement：`kind` 縮小到那一種；不縮小就是多筆、拒絕。
    func testKindNarrowsBetweenARetrievalAndAJudgement() throws {
        try seed()
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: [judgement(field: "issn", value: "0003-066X", statement: "Portal 頁面的號")])
        let svc = service.committed(root)
        XCTAssertThrowsError(try remove([item("issn", "0003-066X")], on: svc)) { err in
            XCTAssertTrue(String(describing: err).contains("2 筆"), "\(err)")
        }
        _ = try remove([item("issn", "0003-066X", extra: ["kind": "judgement"])], on: svc)
        let kinds = try venue().references.filter { $0.field == "issn" && $0.value == "0003-066X" }.map { r -> String in
            if case .retrieval = r.kind { return "retrieval" } else { return "judgement" }
        }
        XCTAssertEqual(kinds, ["retrieval"], "只移除縮小到的那一筆")
    }

    /// 移除面只動被定位到的通用 reference：`paginated` 的判定與 verdict 原封不動（各有自己的面）。
    func testPaginatedJudgementAndVerdictsSurviveARemoval() throws {
        try seed()
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, paginated: true, judgement: "頁碼制", restsOn: [digest])
        var v = try venue()
        v.references.append(try ProvenanceReference(field: "resolution-confirmed", value: "work:x2025 :: Am Psychol", url: nil, retrieved: nil, status: nil,
                                                    mediaType: nil, content: nil, judgement: "完全命中 [rule: venue-name-exact]", restsOn: []))
        _ = try store.writeVenue(v)
        let before = try venue().references.filter { $0.field == "paginated" || $0.field.hasPrefix("resolution-") }
        XCTAssertEqual(before.count, 2, "前提：兩筆")
        _ = try remove([item("issn", "0003-066X"), item("issn", "1935-990X"), item("names", "American Psychologist")], on: service.committed(root))
        let after = try venue().references
        XCTAssertEqual(after.map(\.field), before.map(\.field), "只剩 paginated 與 verdict，且逐筆相同")
        XCTAssertEqual(after.map(\.byteExactKey), before.map(\.byteExactKey))
    }

    func testNotFoundIsRefusedByNameWithWhatIsThere() throws {
        try seed()
        let before = try snapshot()
        XCTAssertThrowsError(try remove([item("issn", "0000-0000")], on: service.committed(root))) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("0000-0000"), s)
            XCTAssertTrue(s.contains("0003-066X"), "要列出這個欄位現有的 value 讓人對照：\(s)")
        }
        XCTAssertThrowsError(try remove([item("note", nil)], on: service.committed(root))) { err in
            XCTAssertTrue(String(describing: err).contains("沒有"), "\(err)")
        }
        // 第二筆找不到，第一筆也不得寫
        XCTAssertThrowsError(try remove([item("issn", "0003-066X"), item("issn", "0000-0000")], on: service.committed(root)))
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    func testTwoLocatorsPointingAtTheSameReferenceAreRefused() throws {
        try seed()
        let before = try snapshot()
        XCTAssertThrowsError(try remove([item("issn", "0003-066X", reason: "a"), item("issn", "0003-066X", reason: "b", extra: ["kind": "retrieval"])],
                                        on: service.committed(root))) { err in
            XCTAssertTrue(String(describing: err).contains("同一筆"), "\(err)")
        }
        XCTAssertEqual(try snapshot(), before)
    }

    // MARK: - git 閘

    func testUncommittedVenueFileIsRefusedAndNothingIsWritten() throws {
        try seed()
        StoreGitCommit.commitAll(root)
        _ = try service.updateVenue(key: "ampsy", addNames: ["Am Psychol"], note: nil, type: nil)   // 未提交的修改
        let before = try snapshot()
        XCTAssertThrowsError(try remove([item("issn", "0003-066X")])) { err in
            XCTAssertTrue(String(describing: err).contains("#673"), "\(err)")
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    func testStoreOutsideGitIsRefused() throws {
        try seed()
        XCTAssertThrowsError(try remove([item("issn", "0003-066X")])) { err in
            XCTAssertTrue(String(describing: err).contains("git"), "\(err)")
        }
        XCTAssertEqual(try venue().references.count, 3)
    }

    // MARK: - 不在本面的欄位

    func testVerdictsAndPaginatedAreRefusedWithAPointerToTheirOwnFace() throws {
        try seed()
        let svc = service.committed(root)
        for f in ["resolution-confirmed", "resolution-rejected", "resolution-undecided"] {
            XCTAssertThrowsError(try remove([item(f, "work:x2025 :: Foo")], on: svc)) { err in
                let s = String(describing: err)
                XCTAssertTrue(s.contains("resolve-venues"), "要指路：\(s)")
                XCTAssertTrue(s.contains(f), s)
            }
        }
        XCTAssertThrowsError(try remove([item("paginated", "true")], on: svc)) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("clear_paginated") || s.contains("--clear-paginated"), "要指路：\(s)")
        }
        XCTAssertThrowsError(try remove([item("doi", "10.1/x")], on: svc)) { err in
            XCTAssertTrue(String(describing: err).contains("names、authorized、issn、note"), "\(err)")
        }
        XCTAssertEqual(try venue().references.count, 3)
    }

    // MARK: - 輸入錯：整批拒絕、零寫入

    func testMalformedInputRejectsTheWholeCall() throws {
        try seed()
        let svc = service.committed(root)
        let before = try snapshot()
        let bad: [[Any]] = [[],                                                           // 空陣列
                            ["issn"],                                                     // 不是物件
                            [item("issn", "0003-066X", extra: ["bogus": 1])],              // 不認得的鍵
                            [["value": "0003-066X", "reason": "r"]],                      // 缺 field
                            [item("issn", nil)],                                          // issn 要帶 value
                            [["field": "issn", "value": "0003-066X"]],                    // 缺理由
                            [item("issn", "0003-066X", reason: "   ")],                    // 理由空白
                            [item("issn", "0003-066X", reason: String(repeating: "x", count: 4_097))],   // 理由過長
                            [item("issn", "0003-066X", extra: ["status": "200"])],         // status 不是整數
                            [item("issn", "0003-066X", extra: ["kind": "guess"])],         // kind 不在兩值內
                            [item("issn", "0003-066X", reason: "a"), item("issn", "1935-990X", reason: String(repeating: "x", count: 4_097))],   // 第二筆才錯
                            (0...200).map { _ in item("issn", "0003-066X") }]             // 超過 200 筆
        for b in bad {
            XCTAssertThrowsError(try remove(b, on: svc), "\(b.prefix(2))")
            XCTAssertEqual(try snapshot(), before, "零寫入：\(b.prefix(2))")
        }
    }

    func testRemoveReferenceIsStandaloneAndRefusesEveryOtherLeg() throws {
        try seed()
        let svc = service.committed(root)
        let before = try snapshot()
        let one: [Any] = [item("issn", "0003-066X")]
        let combos: [(String, () throws -> String)] = [
            ("add_names", { try svc.updateVenue(key: "ampsy", addNames: ["X"], note: nil, type: nil, removeReference: one) }),
            ("note", { try svc.updateVenue(key: "ampsy", addNames: nil, note: "n", type: nil, removeReference: one) }),
            ("type", { try svc.updateVenue(key: "ampsy", addNames: nil, note: nil, type: "periodical", removeReference: one) }),
            ("add_issn", { try svc.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, addISSN: ["1234-5679"], removeReference: one) }),
            ("remove_issn", { try svc.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, removeISSN: ["1935-990X=r"], removeReference: one) }),
            ("references", { try svc.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: [self.retrieval()], removeReference: one) }),
            ("authorize", { try svc.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, authorize: ["American Psychologist"], removeReference: one) }),
            ("paginated", { try svc.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, paginated: true, judgement: "j", restsOn: [self.digest], removeReference: one) }),
        ]
        for (leg, run) in combos {
            XCTAssertThrowsError(try run(), leg) { err in
                XCTAssertTrue(String(describing: err).contains("單獨呼叫"), "\(leg)：\(err)")
            }
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
    }

    func testUnlocatableVenueKeyIsRefused() throws {
        try seed()
        // 第二筆同 key 的 venue 檔（手改／舊 binary 的形，#670）
        var dup = try venue()
        dup.id = UUID()
        _ = try store.writeVenue(dup)
        XCTAssertThrowsError(try remove([item("issn", "0003-066X")])) { err in
            XCTAssertTrue(String(describing: err).contains("無法唯一定位"), "\(err)")
        }
    }

    func testMissingVenueIsNotFound() throws {
        XCTAssertThrowsError(try service.updateVenue(key: "nope", addNames: nil, note: nil, type: nil, removeReference: [item("issn", "0003-066X")])) { err in
            guard case ServiceError.notFound = err else { return XCTFail("\(err)") }
        }
    }

    // MARK: - 已存在的 authorized／note reference（通用寫入面拒收，但手改或舊資料可能有）

    func testAuthorizedAndNoteReferencesAreRemovable() throws {
        try seed()
        var v = try venue()
        v.authorized = ["American Psychologist"]
        v.note = "n"
        v.references.append(try ProvenanceReference(field: "authorized", value: "American Psychologist", url: nil, retrieved: nil, status: nil,
                                                    mediaType: nil, content: nil, judgement: "對外形", restsOn: [digest]))
        v.references.append(try ProvenanceReference(field: "note", value: nil, url: nil, retrieved: nil, status: nil,
                                                    mediaType: nil, content: nil, judgement: "備註出處", restsOn: [digest]))
        _ = try store.writeVenue(v)
        _ = try remove([item("authorized", "American Psychologist"), item("note", nil)], on: service.committed(root))
        XCTAssertEqual(try venue().references.map(\.field), ["issn", "issn", "names"])
    }


    // MARK: - b13f R1 verify

    /// 第 20 列：縮小鍵只能指名有值的欄位——沒給的鍵是「不參與比對」，不是「要求缺席」，所以**寫不出「沒有 media_type」**。
    /// 同一 (field, value) 兩筆 retrieval、只差其中一筆帶 media_type 時：拒絕訊息要說出這個限制（首版叫人「加鍵縮小」，而那個形狀加什麼鍵都選不到沒有的那一筆），
    /// 並列出各筆的 media_type；實際的出路是兩次呼叫（先移除帶的、再移除剩下的）。
    func testTheLocatorCannotExpressAnAbsentMediaTypeAndTheMessageSaysSo() throws {
        try seed()
        var noMedia = retrieval()
        noMedia["media_type"] = nil   // 與 seed 的第一筆逐欄相同，只差沒有 media_type
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: [noMedia])
        let svc = service.committed(root)
        let before = try snapshot()
        XCTAssertThrowsError(try remove([item("issn", "0003-066X")], on: svc)) { err in
            let s = String(describing: err)
            XCTAssertTrue(s.contains("2 筆") && s.contains("寫不出「沒有 media_type」"), "要說出限制：\(s)")
            XCTAssertTrue(s.contains("media_type=text/html") && s.contains("media_type=（無）"), "要列出各筆的 media_type 讓人看得到差別：\(s)")
        }
        XCTAssertEqual(try snapshot(), before, "零寫入")
        // 給 media_type 只選得到帶的那一筆
        _ = try remove([item("issn", "0003-066X", extra: ["media_type": "text/html"])], on: svc)
        let left = try venue().references.filter { $0.field == "issn" && $0.value == "0003-066X" }
        XCTAssertEqual(left.count, 1)
        if case .retrieval(_, _, _, let media, _) = try XCTUnwrap(left.first).kind { XCTAssertNil(media, "剩下的是沒有 media_type 的那一筆") } else { XCTFail("retrieval") }
        // 第二次呼叫：現在只剩一筆，不縮小就定位得到（上一次寫入之後要重新 commit，閘看的是工作樹乾不乾淨）
        _ = try remove([item("issn", "0003-066X")], on: service.committed(root))
        XCTAssertEqual(try venue().references.filter { $0.field == "issn" && $0.value == "0003-066X" }.count, 0)
    }

    /// 第 30 列：MCP 面的移除報告每一筆都列（`field`／`value`／`reason`——理由只在報告裡有一份，不截），只有前 `removalDetailCap` 筆多帶 reference 的其餘內容
    /// （第三方字串）；其後的省略並以 `detailsTruncated`／`detailsListed` 揭露。CLI（`removalDetailLimit: nil`）全列。
    func testTheMCPReportKeepsEveryReasonButOnlyTheFirstTwentyDetails() throws {
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"], type: "periodical", note: nil)
        var v = try venue()
        let total = AkashicService.removalDetailCap + 2
        for i in 0..<total {
            v.references.append(try ProvenanceReference(field: "names", value: "American Psychologist", url: "https://example.org/\(i)",
                                                        retrieved: "2026-09-29", status: 200, mediaType: nil, content: digest, judgement: nil, restsOn: []))
        }
        _ = try store.writeVenue(v)
        let svc = service.committed(root)
        let items: [Any] = (0..<total).map { i in item("names", "American Psychologist", reason: "理由 \(i)", extra: ["url": "https://example.org/\(i)"]) }
        let out = try json(try svc.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, removeReference: items))
        let removed = try XCTUnwrap(out["referencesRemoved"] as? [[String: Any]])
        XCTAssertEqual(removed.count, total, "每一筆都列")
        XCTAssertEqual(removed.map { $0["reason"] as? String }, (0..<total).map { "理由 \($0)" }, "理由是唯一的一份，逐筆都在、不截")
        XCTAssertEqual(removed.map { $0["field"] as? String }, Array(repeating: "names", count: total))
        XCTAssertNotNil(removed[AkashicService.removalDetailCap - 1]["url"], "前 20 筆帶完整內容")
        XCTAssertNil(removed[AkashicService.removalDetailCap]["url"], "第 21 筆起只回 field／value／reason")
        XCTAssertNil(removed[total - 1]["kind"])
        XCTAssertEqual(removed[total - 1]["value"] as? String, "American Psychologist")
        XCTAssertEqual(out["detailsTruncated"] as? Bool, true)
        XCTAssertEqual(out["detailsListed"] as? Int, AkashicService.removalDetailCap)
        XCTAssertEqual(try venue().references.count, 0)
    }

    func testTheCLIReportListsEveryDetail() throws {
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"], type: "periodical", note: nil)
        var v = try venue()
        let total = AkashicService.removalDetailCap + 2
        for i in 0..<total {
            v.references.append(try ProvenanceReference(field: "names", value: "American Psychologist", url: "https://example.org/\(i)",
                                                        retrieved: "2026-09-29", status: 200, mediaType: nil, content: digest, judgement: nil, restsOn: []))
        }
        _ = try store.writeVenue(v)
        let items: [Any] = (0..<total).map { i in item("names", "American Psychologist", reason: "理由 \(i)", extra: ["url": "https://example.org/\(i)"]) }
        let out = try json(try service.committed(root).updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, removeReference: items, removalDetailLimit: nil))
        let removed = try XCTUnwrap(out["referencesRemoved"] as? [[String: Any]])
        XCTAssertEqual(removed.count, total)
        XCTAssertTrue(removed.allSatisfy { $0["url"] != nil && $0["kind"] as? String == "retrieval" }, "CLI 全列")
        XCTAssertNil(out["detailsTruncated"])
    }

    // MARK: - 讀取面

    func testVenueReadSurfaceListsTheGenericReferencesButNotVerdictsOrPaginated() throws {
        try seed()
        let out = try json(try service.venue(key: "ampsy"))
        let refs = try XCTUnwrap(out["references"] as? [[String: Any]])
        XCTAssertEqual(refs.map { $0["field"] as? String }, ["issn", "issn", "names"])
        XCTAssertEqual(refs.map { $0["value"] as? String }, ["0003-066X", "1935-990X", "American Psychologist"])
        XCTAssertEqual(refs[0]["kind"] as? String, "retrieval")
        XCTAssertEqual(refs[0]["url"] as? String, "https://portal.issn.org/resource/ISSN/0003-066X")
        XCTAssertEqual(refs[0]["retrieved"] as? String, "2026-09-29")
        XCTAssertEqual(refs[0]["status"] as? Int, 200)
        XCTAssertEqual(refs[0]["media_type"] as? String, "text/html")
        XCTAssertEqual(refs[0]["content"] as? String, digest)
        XCTAssertEqual(refs[2]["kind"] as? String, "judgement")
        XCTAssertEqual(refs[2]["statement"] as? String, "ISSN Portal 的刊名")
        XCTAssertEqual(refs[2]["rests_on"] as? [String], [digest])
        XCTAssertEqual(out["referencesTotal"] as? Int, 3)

        // verdict 與 paginated 的判定各有自己的鍵，不重列在 references 裡
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, paginated: true, judgement: "頁碼制", restsOn: [digest])
        let again = try json(try service.venue(key: "ampsy"))
        XCTAssertEqual((again["references"] as? [[String: Any]])?.count, 3)
        XCTAssertNotNil(again["paginatedJudgements"])
    }

    /// `rests_on` 有界：只列前幾個 digest、總數揭露（同 `verdicts` 的未決記錄）——單筆 reference 的上界不隨 rests-on 的個數長。
    func testReadSurfaceListsOnlyTheFirstRestsOnDigests() throws {
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"], type: "periodical", note: nil)
        let digests = (1...8).map { "sha256:" + String(format: "%064x", $0) }
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil, references: [
            ["field": "names", "value": "American Psychologist", "kind": "judgement", "statement": "s", "rests_on": digests]])
        let ref = try XCTUnwrap((try json(try service.venue(key: "ampsy"))["references"] as? [[String: Any]])?.first)
        XCTAssertEqual(ref["rests_on"] as? [String], Array(digests.prefix(5)))
        XCTAssertEqual(ref["rests_on_total"] as? Int, 8)
        // 縮小定位要給逐字的完整陣列：前 5 個不足以命中
        StoreGitCommit.commitAll(root)
        XCTAssertThrowsError(try remove([item("names", "American Psychologist", extra: ["rests_on": Array(digests.prefix(5))])]))
        _ = try remove([item("names", "American Psychologist", extra: ["rests_on": digests])])
        XCTAssertEqual(try venue().references.count, 0)
    }

    func testVenueReadSurfaceOmitsTheKeyWhenThereAreNone() throws {
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"], type: "periodical", note: nil)
        let out = try json(try service.venue(key: "ampsy"))
        XCTAssertNil(out["references"])
        XCTAssertNil(out["referencesTotal"])
    }

    func testVenueReadSurfaceCapsAndDiscloses() throws {
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"], type: "periodical", note: nil)
        var v = try venue()
        for i in 0..<(AkashicService.venueReferencesCap + 5) {
            v.references.append(try ProvenanceReference(field: "names", value: "American Psychologist", url: "https://example.org/\(i)",
                                                        retrieved: "2026-09-29", status: 200, mediaType: nil, content: digest, judgement: nil, restsOn: []))
        }
        _ = try store.writeVenue(v)
        let out = try json(try service.venue(key: "ampsy"))
        XCTAssertEqual((out["references"] as? [[String: Any]])?.count, AkashicService.venueReferencesCap)
        XCTAssertEqual(out["referencesTotal"] as? Int, AkashicService.venueReferencesCap + 5)
        XCTAssertEqual(out["referencesTruncated"] as? Bool, true)
    }
}
