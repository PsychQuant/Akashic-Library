import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import AkashicIndex
@testable import AkashicExport

/// venue／org 的 service 面（#304 task 4.1）——CLI 與 MCP 的唯一實作路徑。
final class VenueServiceTests: XCTestCase {
    var root: URL!
    var store: LibraryStore!
    var service: AkashicService!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory
            .appendingPathComponent("akashic-vsvc-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("entities"), withIntermediateDirectories: true)
        try StoreVersion.write(root: root, format: StoreVersion.supported)
        store = LibraryStore(root: root)
        service = AkashicService(root: root, key: nil, environment: [:])
    }
    override func tearDownWithError() throws { try? FileManager.default.removeItem(at: root) }

    private func json(_ s: String) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: Data(s.utf8)) as? [String: Any])
    }

    func testAddVenueThenViewWithZeroWorks() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        let d = try json(try service.venue(key: "psychometrika"))
        XCTAssertEqual(d["type"] as? String, "periodical")
        XCTAssertEqual(d["workCount"] as? Int, 0, "零篇是答案不是缺席")
        XCTAssertNotNil(d["works"], "空陣列也要出現")
    }

    func testVenueNotFoundVsUndeterminable() throws {
        XCTAssertThrowsError(try service.venue(key: "nope")) { err in
            guard case ServiceError.notFound = err else { return XCTFail("預期 notFound") }
        }
        // quarantined 檔在場 → 無法判定
        try "venue:\nid: \(UUID().uuidString)\nkey: broken\ntype: series\n"
            .write(to: root.appendingPathComponent("entities/\(UUID().uuidString).yaml"),
                   atomically: true, encoding: .utf8)
        XCTAssertThrowsError(try service.venue(key: "nope")) { err in
            guard case ServiceError.undeterminable = err else {
                return XCTFail("quarantine 在場時應 undeterminable，實得 \(err)")
            }
        }
    }

    func testAddVenueRejectsUnknownType() throws {
        XCTAssertThrowsError(try service.addVenue(key: "x", names: ["X"],
                                                  type: "series", note: nil))
    }

    func testChronologicalWorksInVenueView() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        var e1 = Entry(id: UUID(), citekey: "b2020", type: .periodicalArticle, title: "後")
        e1.venues = [.key("psychometrika")]; e1.date = "2020"
        var e2 = Entry(id: UUID(), citekey: "a2015", type: .periodicalArticle, title: "前")
        e2.venues = [.key("psychometrika")]; e2.date = "2015"
        _ = try store.writeEntry(e1); _ = try store.writeEntry(e2)
        try LibraryIndex(store: store).rebuild()
        let d = try json(try service.venue(key: "psychometrika"))
        let works = try XCTUnwrap(d["works"] as? [[String: Any]])
        XCTAssertEqual(works.map { $0["citekey"] as? String }, ["a2015", "b2020"], "依年升冪")
    }

    func testResolveVenuesFullCycle() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("PSYCHOMETRIKA")]   // WoS 大寫形——正規化命中
        _ = try store.writeEntry(e)
        // 候選列舉
        let list = try json(try service.resolveVenues(apply: nil))
        let cands = try XCTUnwrap(list["candidates"] as? [[String: Any]])
        XCTAssertEqual(cands.count, 1)
        let id = try XCTUnwrap(cands[0]["id"] as? String)
        XCTAssertEqual(id, "x2025:0")
        // apply：literal 升格 key＋confirmed verdict
        let applied = try json(try service.resolveVenues(apply: [id]))
        XCTAssertEqual(applied["entriesRewritten"] as? Int, 1)
        let after = try store.load()
        XCTAssertEqual(after.entries[0].venues, [.key("psychometrika")])
        let venue = try XCTUnwrap(after.venues.first)
        XCTAssertTrue(venue.references.contains { $0.field == "resolution-confirmed" },
                      "confirmed verdict 落被判定的 venue 記錄")
        // idempotent：再解析零候選
        let again = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((again["candidates"] as? [[String: Any]])?.count, 0)
    }

    func testResolveVenuesRejectSuppressesCandidate() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("Psychometrika")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: nil, reject: ["x2025:0"])
        let after = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((after["candidates"] as? [[String: Any]])?.count, 0,
                       "已否決配對不再被提名")
        // entry 的 literal 原樣（reject 不動 entry）
        XCTAssertEqual(try store.load().entries[0].venues, [.literal("Psychometrika")])
    }

    // MARK: - #306：update-venue（異名補寫——append 語意）

    func testUpdateVenueAppendsNamesWithoutClobbering() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        let out = try json(try service.updateVenue(
            key: "psychometrika", addNames: ["PSYCHOMETRIKA", "Psychometrika"],
            note: nil, type: nil))
        XCTAssertEqual(out["namesAdded"] as? [String], ["PSYCHOMETRIKA"],
                       "重複異名不重加：\(out)")
        let v = try XCTUnwrap(try store.load().venues.first)
        XCTAssertEqual(Set(v.names.entries.map(\.value)),
                       ["Psychometrika", "PSYCHOMETRIKA"], "既有名字不得被洗掉")
        // 沿革補全後 resolver 立即受益：WoS 大寫形 exact 命中
        var e = Entry(id: UUID(), citekey: "x2025", type: .periodicalArticle, title: "T")
        e.venues = [.literal("PSYCHOMETRIKA")]
        _ = try store.writeEntry(e)
        let list = try json(try service.resolveVenues(apply: nil))
        XCTAssertEqual((list["candidates"] as? [[String: Any]])?.count, 1)
    }

    func testUpdateVenueRejectsUnknownKeyAndBadType() throws {
        XCTAssertThrowsError(try service.updateVenue(
            key: "nope", addNames: ["X"], note: nil, type: nil))
        _ = try service.addVenue(key: "v1", names: ["V"], type: "periodical", note: nil)
        XCTAssertThrowsError(try service.updateVenue(
            key: "v1", addNames: nil, note: nil, type: "series"))
    }

    // MARK: - #406：venue.paginated 的判定面與 floor 接線

    /// 判定要留 verdict 與**證據**——judgement 或 rests-on 缺任一都拒、零寫入。
    /// 孤兒 judgement（沒有 paginated 卻給理由）同拒。
    func testUpdateVenuePaginatedRequiresJudgementAndEvidence() throws {
        _ = try service.addVenue(key: "fp", names: ["Frontiers in Psychology"],
                                 type: "periodical", note: nil)
        XCTAssertThrowsError(try service.updateVenue(
            key: "fp", addNames: nil, note: nil, type: nil, paginated: false))
        XCTAssertThrowsError(try service.updateVenue(
            key: "fp", addNames: nil, note: nil, type: nil,
            paginated: false, judgement: "artnum 制", restsOn: nil))
        XCTAssertThrowsError(try service.updateVenue(
            key: "fp", addNames: nil, note: nil, type: nil,
            paginated: false, judgement: "artnum 制", restsOn: ["sha256:xyz"]))
        XCTAssertNil(try store.load().venues.first?.paginated, "拒絕必須零寫入")
        XCTAssertThrowsError(try service.updateVenue(
            key: "fp", addNames: nil, note: nil, type: nil, judgement: "孤兒理由"))
    }

    /// 判定寫入：值＋判斷型 reference；(field, value, kind) 冪等；翻轉判定
    /// 是**新判定**，舊判定留史（判定會錯，錯了要能回溯）。
    func testUpdateVenuePaginatedWritesValueAndVerdict() throws {
        _ = try service.addVenue(key: "fp", names: ["Frontiers in Psychology"],
                                 type: "periodical", note: nil)
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        let out = try json(try service.updateVenue(
            key: "fp", addNames: nil, note: nil, type: nil,
            paginated: false, judgement: "Crossref 抽樣 0/80 page、42/80 artnum",
            restsOn: [digest]))
        XCTAssertEqual(out["paginated"] as? Bool, false)
        let v = try XCTUnwrap(try store.load().venues.first)
        XCTAssertEqual(v.paginated, false)
        let ref = try XCTUnwrap(v.references.first { $0.field == "paginated" })
        guard case .judgement(let stmt, let ro) = ref.kind else {
            return XCTFail("判定必須是判斷型")
        }
        XCTAssertTrue(stmt.contains("Crossref"))
        XCTAssertEqual(ro, [digest])
        _ = try service.updateVenue(
            key: "fp", addNames: nil, note: nil, type: nil,
            paginated: false, judgement: "Crossref 抽樣 0/80 page、42/80 artnum",
            restsOn: [digest])
        XCTAssertEqual(try store.load().venues.first?.references
                        .filter { $0.field == "paginated" }.count, 1,
                       "同 (field,value,kind) 冪等")
        _ = try service.updateVenue(
            key: "fp", addNames: nil, note: nil, type: nil,
            paginated: true, judgement: "改判：出版商頁逐篇有頁碼", restsOn: [digest])
        let v2 = try XCTUnwrap(try store.load().venues.first)
        XCTAssertEqual(v2.paginated, true)
        XCTAssertEqual(v2.references.filter { $0.field == "paginated" }.count, 2,
                       "翻轉是新判定，舊判定留史")
    }

    /// **floor 三態**（欄位契約的核心）：`false` 抑制缺 PAGES 的警告；`nil`（未判定）
    /// 與 `true` **照報**——「未判定折成任何預設值，會讓所有未查的刊靜默通過下限檢查」。
    func testFloorSuppressesMissingPagesOnlyForJudgedUnpaginatedVenues() throws {
        _ = try service.addVenue(key: "vfalse", names: ["ArtNum J"], type: "periodical", note: nil)
        _ = try service.addVenue(key: "vtrue", names: ["Paged J"], type: "periodical", note: nil)
        _ = try service.addVenue(key: "vnil", names: ["Unjudged J"], type: "periodical", note: nil)
        let digest = "sha256:" + String(repeating: "cd", count: 32)
        _ = try service.updateVenue(key: "vfalse", addNames: nil, note: nil, type: nil,
                                    paginated: false, judgement: "artnum 制", restsOn: [digest])
        _ = try service.updateVenue(key: "vtrue", addNames: nil, note: nil, type: nil,
                                    paginated: true, judgement: "傳統頁碼刊", restsOn: [digest])
        func entry(_ ck: String, venue: String) -> Entry {
            var e = Entry(id: UUID(), citekey: ck, type: .periodicalArticle, title: "T")
            e.venues = [.key(venue)]
            e.authors = [.literal("A B")]
            e.date = "2020"
            e.fields = ["journaltitle": "J", "volume": "1"]
            return e
        }
        let venues = try store.load().venues
        let report = BibExport.apa7Report(
            entries: [entry("efalse", venue: "vfalse"),
                      entry("enil", venue: "vnil"),
                      entry("etrue", venue: "vtrue")],
            people: [], venues: venues)
        let pagesWarnings = report.issues.filter { $0.message.contains("PAGES") }
        XCTAssertEqual(Set(pagesWarnings.map(\.citekey)), ["enil", "etrue"],
                       "false 抑制；nil 與 true 照報")
    }

    /// venue 附著驗證的 `paginated` case——**#500 改了兩條規則，本測試跟著改**。
    ///
    /// 被拿掉的兩條原本寫著「純量不收 value」與「欄位缺席不該有判定證據」，而**它們正是
    /// (b)『撤回判定』寫不出來的原因**：撤回之後欄位就是 nil，而判定史要留著——舊規則下
    /// 這個狀態載入不了，只剩「丟掉全部 reference」（違反留史）一條路。
    ///
    /// 現行規則：value 若在必須是封閉三值（`true`／`false`／`nil`＝撤回）；舊筆（value
    /// 缺席）放行（相容路徑，退場量測寫在 `Provenance.swift`）；判定仍必須是判斷型。
    /// D69（R25；R24 verify regression 第 29 列）：`paginated` 的冪等閘比位元組——canonical `==` 會把只差 NFC／NFD 的 judgement
    /// 靜默吞掉、零回報，那是 D65 在寫入面的同一個缺陷。
    func testPaginatedJudgementsThatDifferOnlyInBytesAreBothKept() throws {
        _ = try service.addVenue(key: "fp", names: ["Frontiers in Psychology"], type: "periodical", note: nil)
        let digest = "sha256:" + String(repeating: "ab", count: 32)
        for stmt in ["\u{00E1} 判定", "a\u{0301} 判定", "\u{00E1} 判定"] {
            _ = try service.updateVenue(key: "fp", addNames: nil, note: nil, type: nil,
                                        paginated: false, judgement: stmt, restsOn: [digest])
        }
        let stmts = try store.load().venues.first?.references.filter { $0.field == "paginated" }
            .compactMap { r -> [UInt8]? in if case .judgement(let s, _) = r.kind { return Array(s.utf8) } else { return nil } } ?? []
        XCTAssertEqual(stmts.count, 2, "NFC 與 NFD 各一筆；逐位元組相同的第三次不寫")
        XCTAssertEqual(Set(stmts), Set([Array("\u{00E1} 判定".utf8), Array("a\u{0301} 判定".utf8)]))
    }

    /// R24 verify Codex 第 2 列：`verdictsRetired` 的描述要印 rests-on——兩筆只差證據 digest 的退役判定否則不可區分。
    /// 這是 R20（`describeCollapsedVerdict`）→ R23（`describeDedupedVerdict`）之後同一族的第三個生產者。
    func testDescribeRetiredNamesRestsOnDigests() throws {
        let d1 = "sha256:" + String(repeating: "ab", count: 32), d2 = "sha256:" + String(repeating: "cd", count: 32)
        func ref(_ ro: [String]) -> ProvenanceReference {
            ProvenanceReference(field: "resolution-rejected", value: "work:w2020a :: Alpha", kind: .judgement(statement: "同一句", restsOn: ro))
        }
        let a = AkashicService.describeRetired(ref([d1]), on: "alpha"), b = AkashicService.describeRetired(ref([d2]), on: "alpha")
        XCTAssertNotEqual(a, b, "只差 rests-on 的兩筆要分得開")
        XCTAssertTrue(a.contains("rests-on 1 筆") && a.contains(String(d1.prefix(20))), a)
    }

    func testVenuePaginatedReferenceAttachmentRules() throws {
        _ = try service.addVenue(key: "v9", names: ["V9"], type: "periodical", note: nil)
        var v = try XCTUnwrap(try store.load().venues.first { $0.key == "v9" })
        func set(_ value: String?) {
            let ref = ProvenanceReference(field: "paginated", value: value,
                                          kind: .judgement(statement: "x", restsOn: []))
            if v.references.last?.field == "paginated" { v.references[v.references.count - 1] = ref }
            else { v.references.append(ref) }
        }
        // 撤回態：欄位 nil ＋ value「nil」——**這一格在 #500 之前載入不了**
        set("nil")
        XCTAssertNil(v.paginated)
        XCTAssertNoThrow(try v.validateReferenceAttachment(), "撤回是合法狀態，判定史留著")
        // 帶值的判定
        v.paginated = false
        set("false")
        XCTAssertNoThrow(try v.validateReferenceAttachment())
        // 舊筆（value 缺席）放行——33 筆 live 記錄不得因此拒讀
        set(nil)
        XCTAssertNoThrow(try v.validateReferenceAttachment())
        // 三值以外拒絕——`nil` 是撤回，不是「隨便什麼字串」
        set("maybe")
        XCTAssertThrowsError(try v.validateReferenceAttachment(), "value 必須是封閉三值之一")
        // 判定仍必須是判斷型
        v.references[v.references.count - 1] = ProvenanceReference(
            field: "paginated", value: "true",
            kind: .retrieval(url: "https://example.org", retrieved: "2026-09-09",
                             status: 200, mediaType: "text/html", content: "sha256:" + String(repeating: "a", count: 64)))
        XCTAssertThrowsError(try v.validateReferenceAttachment(), "擷取型帶不動人為裁決")
    }

    // MARK: - #394：venue 的 ISSN 寫入面

    /// **查到一個 ISSN 之後，有一條路把它寫進去。**
    ///
    /// #394 把識別碼升格為一等公民，但**只給了遷移路徑**——`migrate-identifiers` 從
    /// `fields` 殘留搬值。查到一個**新的** ISSN（不在任何殘留裡）時，該 issue 自己記著
    /// 沒有任何面寫得進去，唯一的路是手改 YAML。那一列被標為「最弱的一列」。
    ///
    /// 本測試釘住那條路現在存在。**append 語意**與 `addNames` 一致：ISSN 本來就是清單
    /// （print 與 electronic 是兩個真的號），而整組替換會讓「補一個」變成「先讀再全寫」
    /// ——那是 #306 已經裁決過不提供的形狀。
    func testUpdateVenueAppendsISSN() throws {
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"],
                                 type: "periodical", note: nil)
        let out = try json(try service.updateVenue(
            key: "ampsy", addNames: nil, note: nil, type: nil,
            addISSN: ["0003-066X"]))
        XCTAssertEqual(out["issnAdded"] as? [String], ["0003-066X"], "回報加了什麼：\(out)")
        XCTAssertEqual(try store.load().venues.first?.issn.map(\.normalized), ["0003-066X"])
    }

    /// **正規形決定相等**——`0003-066x` 與 `0003-066X` 是同一個號，不得變成兩筆。
    ///
    /// 這與 `IdentifierMigration.normalizedUnique` 的既有立場一致（那裡的 doc 逐字寫著
    /// 「否則 `0003-066x` 與 `0003-066X` 會被當成兩個號」）。寫入面走同一條規則，
    /// 否則兩個面對「這本刊有幾個 ISSN」會給出不同答案。
    func testUpdateVenueDeduplicatesISSNByNormalisedForm() throws {
        _ = try service.addVenue(key: "ampsy", names: ["American Psychologist"],
                                 type: "periodical", note: nil)
        _ = try service.updateVenue(key: "ampsy", addNames: nil, note: nil, type: nil,
                                    addISSN: ["0003-066X"])
        let out = try json(try service.updateVenue(
            key: "ampsy", addNames: nil, note: nil, type: nil,
            addISSN: ["0003-066x", "1935-990X"]))
        XCTAssertEqual(out["issnAdded"] as? [String], ["1935-990X"],
                       "大小寫異寫法不是新號：\(out)")
        XCTAssertEqual(try store.load().venues.first?.issn.count, 2)
    }

    /// 不合法的 ISSN **整個呼叫拒絕**，零寫入。
    ///
    /// 與 `type: "series"` 那條（`testUpdateVenueRejectsUnknownKeyAndBadType`）同型：
    /// 寫入面對值域的違反是拒絕，不是「收下來再說」。識別碼尤其如此——它**終結指涉**，
    /// 一個壞掉的號寫進去之後，用它做的每一次配對都建立在假的身分宣稱上。
    func testUpdateVenueRejectsMalformedISSN() throws {
        _ = try service.addVenue(key: "ampsy", names: ["V"], type: "periodical", note: nil)
        XCTAssertThrowsError(try service.updateVenue(
            key: "ampsy", addNames: nil, note: nil, type: nil, addISSN: ["not-an-issn"]))
        XCTAssertTrue(try store.load().venues.first?.issn.isEmpty ?? false,
                      "拒絕必須零寫入")
    }

    // MARK: - #394：建檔時就能帶識別碼

    /// `add-venue --issn` ／ `akashic_add_venue` 的 `issn`。
    ///
    /// **為什麼建檔面也要**：少了它得「先建再更新」——一次操作變兩次，中間有一個
    /// ISSN 不在的狀態。而建檔時本來就知道刊物的 ISSN。
    ///
    /// **誠實記錄**：本測試是**實作之後**補的（違反 TDD 的先寫測試）。所以它附一個
    /// 負控——見 `testAddVenueISSNGuardActuallyFires`。一個從沒紅過的檢查與一個不存在
    /// 的檢查，在報告上長得一模一樣。
    func testAddVenueAcceptsISSNAtCreation() throws {
        let out = try json(try service.addVenue(
            key: "ampsy", names: ["American Psychologist"], type: "periodical",
            note: nil, issn: ["0003-066X", "1935-990X"]))
        XCTAssertEqual(out["issn"] as? [String], ["0003-066X", "1935-990X"], "回報：\(out)")
        XCTAssertEqual(try store.load().venues.first?.issn.count, 2)
    }

    /// 不合法的 ISSN → 整個建檔拒絕，**venue 也不該存在**。
    ///
    /// 這比 `updateVenue` 那條更強：那裡拒絕的是一次更新，這裡拒絕的是整筆記錄的誕生。
    /// 若守衛只擋 ISSN 而讓 venue 建了出來，結果是一筆「使用者以為帶 ISSN、實際沒有」
    /// 的記錄——比明確失敗更糟。
    func testAddVenueISSNGuardActuallyFires() throws {
        XCTAssertThrowsError(try service.addVenue(
            key: "bad", names: ["V"], type: "periodical", note: nil, issn: ["not-an-issn"]))
        XCTAssertTrue(try store.load().venues.isEmpty,
                      "拒絕必須零寫入——連 venue 本身都不該存在")
    }

    /// ROR 是**純量不是清單**——一個機構只有一個 ROR ID，而 ISSN 的多值是真的
    /// （print 與 electronic）。兩者形狀不同是刻意的。
    func testAddOrganizationAcceptsROR() throws {
        let out = try json(try service.addOrganization(
            key: "academia-sinica", names: ["中央研究院"], parentKey: nil, note: nil,
            ror: "https://ror.org/03rmrcq20"))
        XCTAssertNotNil(out["ror"], "回報：\(out)")
        XCTAssertNotNil(try store.load().organizations.first?.ror)
    }

    func testAddOrganizationRORGuardActuallyFires() throws {
        XCTAssertThrowsError(try service.addOrganization(
            key: "bad", names: ["X"], parentKey: nil, note: nil, ror: "not-a-ror"))
        XCTAssertTrue(try store.load().organizations.isEmpty, "拒絕必須零寫入")
    }

    // MARK: - #443：`.literal` → `.organization` 的升格面

    /// **`Author` 有三態，而在此之前只有兩態接得起來。**
    ///
    /// `resolve-people` 的 apply 把 `.literal` 升格成 `.key`（人）。團體作者
    /// （`.organization`，#323）**只能在建檔時指定**——既有記錄改不了，唯一出路是手改
    /// YAML，而那是 #394 差點弄丟一筆 DOI 的那條路。
    ///
    /// 實測（#443，2026-08-28）：`Center for History and New Media` 與 `教育部` 兩筆
    /// 機構被記成 `.literal` 作者，修不了。
    ///
    /// **這不是消歧**：org key 是呼叫端**顯式給的**，不是提名出來的。所以沒有 tier、
    /// 沒有候選清單——與 #386 的 `judge` 同型（per-id 顯式指名，judgement 必填）。
    func testAttributeAuthorToOrganisation() throws {
        _ = try service.addOrganization(key: "moe", names: ["教育部"],
                                        parentKey: nil, note: nil)
        var e = Entry(id: UUID(), citekey: "moe2011", type: .book, title: "T")
        e.authors = [.literal("教育部")]
        _ = try store.writeEntry(e)

        let out = try json(try service.attributeToOrganizations(
            ["moe2011:0:moe=名字是政府機關，不是人"]))
        XCTAssertEqual((out["attributed"] as? [[String: Any]])?.count, 1, "\(out)")

        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "moe2011" })
        guard case .organization(let k) = after.authors[0] else {
            return XCTFail("該位應該是 .organization，實際是 \(after.authors[0])")
        }
        XCTAssertEqual(k, "moe")

        // verdict 落在**被判定的記錄**上（封閉列舉第 13 條的既有立場）
        let org = try XCTUnwrap(try store.load().organizations.first { $0.key == "moe" })
        XCTAssertTrue(org.references.contains { $0.field == "resolution-confirmed" },
                      "判定要留 verdict——錯了要能回溯與逆轉")
    }

    /// **judgement 必填**——與 #386 的 `judge` 同一條紀律。
    ///
    /// 判定會錯，而錯了要能回溯。一個沒有理由的判定在事後與「不知道為什麼這樣」
    /// 無法區分。空字串在這一層拒絕，不是靠呼叫端自律。
    func testAttributeToOrganizationRequiresJudgement() throws {
        _ = try service.addOrganization(key: "moe", names: ["教育部"], parentKey: nil, note: nil)
        var e = Entry(id: UUID(), citekey: "moe2011", type: .book, title: "T")
        e.authors = [.literal("教育部")]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.attributeToOrganizations(["moe2011:0:moe="]))
    }

    /// **前提不符 → 整批拒絕、零寫入**（同 `judge` 與 `repoint` 的失敗語意）。
    ///
    /// 這裡刻意驗**第二筆**壞掉：第一筆完全合法，若實作是逐筆寫入，它會先寫成功再失敗
    /// ——留下一個「一半套用」的狀態，而那比整批失敗難修得多。
    func testAttributeToOrganizationRejectsWholeBatchOnUnknownOrg() throws {
        _ = try service.addOrganization(key: "moe", names: ["教育部"], parentKey: nil, note: nil)
        var e = Entry(id: UUID(), citekey: "moe2011", type: .book, title: "T")
        e.authors = [.literal("教育部"), .literal("Center for History and New Media")]
        _ = try store.writeEntry(e)

        XCTAssertThrowsError(try service.attributeToOrganizations(
            ["moe2011:0:moe=合法的一筆", "moe2011:1:no-such-org=不存在的 org"]))

        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "moe2011" })
        guard case .literal = after.authors[0] else {
            return XCTFail("整批拒絕時第一筆也不該被寫入——實際是 \(after.authors[0])")
        }
    }

    /// 已歸戶的位置不得被覆寫——`.key`（人）與 `.organization` 都是。
    func testAttributeToOrganizationRefusesAnAlreadyResolvedSlot() throws {
        _ = try service.addOrganization(key: "moe", names: ["教育部"], parentKey: nil, note: nil)
        _ = try service.addPerson(key: "a-b", names: ["A B"], orcid: nil, openalex: nil)
        var e = Entry(id: UUID(), citekey: "x2011", type: .book, title: "T")
        e.authors = [.key("a-b")]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.attributeToOrganizations(["x2011:0:moe=想覆寫"]))
    }

    /// **同一筆 work 的多個作者位一起升格**——實測 crash（#443）。
    ///
    /// 實作用 `Dictionary(uniqueKeysWithValues:)` 建 citekey → entry 的對照，而同一個
    /// work 的三個作者位產生**三筆同 citekey 的 plan** → `Fatal error: Duplicate values
    /// for key`。
    ///
    /// **三個既有的負向測試都沒抓到它**：每個只用一筆 plan，或用不同的 citekey。我測了
    /// 「第二筆壞掉」卻沒測「兩筆都好而且在同一筆 work 上」——而後者是這個功能最自然的
    /// 用法（《Standards for Educational and Psychological Testing》有三個共同出版者）。
    func testAttributeMultipleAuthorSlotsOnTheSameWork() throws {
        for k in ["aera", "apa", "ncme"] {
            _ = try service.addOrganization(key: k, names: [k.uppercased()],
                                            parentKey: nil, note: nil)
        }
        var e = Entry(id: UUID(), citekey: "std1966", type: .book, title: "Standards")
        e.authors = [.literal("AERA"), .literal("APA"), .literal("NCME")]
        _ = try store.writeEntry(e)

        let out = try json(try service.attributeToOrganizations([
            "std1966:0:aera=學會不是人", "std1966:1:apa=同上", "std1966:2:ncme=同上",
        ]))
        XCTAssertEqual((out["attributed"] as? [[String: Any]])?.count, 3, "\(out)")

        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "std1966" })
        let keys: [String] = after.authors.compactMap {
            if case .organization(let k) = $0 { return k } else { return nil }
        }
        XCTAssertEqual(keys, ["aera", "apa", "ncme"], "三個作者位都要升格，順序不變")
    }

    // MARK: - #443：把黏在一起的作者位拆開

    /// **一個 literal 裝了兩個人時，沒有任何面拆得開。**
    ///
    /// 實測（#443）：4 筆「某人與雷庚玲」——同一個指導教授的四篇合著，匯入時整個作者欄
    /// 被當成一個 literal。`resolve-people --apply` 只能把它整個升格成**一個** person，
    /// 而那會建出一個不存在的人。
    ///
    /// ## 為什麼用分隔符而不是自由文字
    ///
    /// 收「拆成哪兩個名字」的自由文字，等於讓呼叫端**編造**——打錯一個字就寫進 store
    /// 而沒有任何東西擋得住。收**分隔符**則讓拆出的每一段必然是原文的子字串：零編造，
    /// 且錯了看得出來（切出空段就拒絕）。
    ///
    /// 分隔符本身被丟棄，而那是可見的——報告逐筆印出「用什麼切、切成什麼」。
    func testSplitAuthorBySeparator() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal("鄭澈與雷庚玲")]
        _ = try store.writeEntry(e)

        let out = try json(try service.splitAuthors(["a2014:0:與=兩個人被匯入成一個 literal"]))
        XCTAssertEqual((out["split"] as? [[String: Any]])?.count, 1, "\(out)")

        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "a2014" })
        XCTAssertEqual(after.authors.count, 2, "一個作者位拆成兩個")
        let names: [String] = after.authors.compactMap {
            if case .literal(let s) = $0 { return s } else { return nil }
        }
        XCTAssertEqual(names, ["鄭澈", "雷庚玲"], "拆出的名字必然是原文的子字串")
    }

    /// **切出空段 → 整批拒絕**。`「與雷庚玲」` 用 `與` 切會得到一個空的前段。
    func testSplitRejectsEmptySegment() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal("與雷庚玲")]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.splitAuthors(["a2014:0:與=理由"]))
        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "a2014" })
        XCTAssertEqual(after.authors.count, 1, "拒絕必須零寫入")
    }

    /// 分隔符不在該 literal 裡 → 拒絕（而不是靜默不拆）。
    func testSplitRejectsAbsentSeparator() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal("鄭澈")]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.splitAuthors(["a2014:0:與=理由"]))
    }

    /// **只作用於 `.literal`**——已歸戶的位置拆開會讓那個 key 的身分不明。
    func testSplitRefusesAResolvedSlot() throws {
        _ = try service.addPerson(key: "a-b", names: ["A B"], orcid: nil, openalex: nil)
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.key("a-b")]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.splitAuthors(["a2014:0:與=理由"]))
    }

    /// **同一筆 work 的多個作者位一起拆**——index 會位移，而實作必須處理。
    ///
    /// 這是 #443 的 `attributeToOrganizations` 踩過的形狀（`Dictionary(uniqueKeysWithValues:)`
    /// 對重複 citekey 直接 crash），但這裡更尖：**拆開會改變後續 index**。
    func testSplittingTwoSlotsOnTheSameWorkAccountsForIndexShift() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal("甲與乙"), .literal("丙與丁")]
        _ = try store.writeEntry(e)

        _ = try service.splitAuthors(["a2014:0:與=理由", "a2014:1:與=理由"])
        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "a2014" })
        let names: [String] = after.authors.compactMap {
            if case .literal(let s) = $0 { return s } else { return nil }
        }
        XCTAssertEqual(names, ["甲", "乙", "丙", "丁"],
                       "兩個位置都要拆，且順序保持——index 位移由實作處理，不由呼叫端")
    }

    /// **同一個作者位被指定兩次 → 整批拒絕**（R1 verify HIGH）。字面去重擋不住
    /// 「同 slot 配不同分隔符」：兩筆都對 pristine entry 驗證通過，寫入時第二筆
    /// 對已改寫的陣列套用預先算好的 parts——長度不對的靜默毀損。
    func testSplitRejectsTheSameSlotGivenTwice() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal("甲與乙X丙")]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.splitAuthors(
            ["a2014:0:與=理由甲", "a2014:0:X=理由乙"]))
        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "a2014" })
        XCTAssertEqual(after.authors.count, 1, "拒絕必須零寫入")
    }

    /// 同 slot 的**另一種拼法**也要擋：`0` 與 `+0` 解析成同一個 Int。以字面
    /// 去重修上一條會被這條繞回（R1 verify DA）——去重必須用解析後的值。
    ///
    /// **驗的是拒絕的理由**（R2 verify）：只驗「有丟錯」的話，日後 parser 若改成
    /// 直接拒收 `+0`，本測試照綠、去重那一格卻沒了覆蓋。
    func testSplitRejectsTheSameSlotSpelledDifferently() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal("甲與乙X丙")]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.splitAuthors(
            ["a2014:0:與=理由甲", "a2014:+0:X=理由乙"])) { error in
            XCTAssertTrue(String(describing: error).contains("被指定了兩次"),
                          "要因 slot 重複被拒，不是因 +0 被 parser 拒收：\(error)")
        }
        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "a2014" })
        XCTAssertEqual(after.authors.count, 1, "拒絕必須零寫入")
        if case .literal(let s) = after.authors[0] {
            XCTAssertEqual(s, "甲與乙X丙", "原 literal 一個字都不能動")
        } else { XCTFail("作者位形狀被改了") }
    }

    /// **上界的兩側**（R2 verify）：只測 40 段會失敗的話，上限錯成 35 也照綠。
    /// 32 段是允許的最大值、33 段拒絕——且拒絕發生在 materialization 之前
    /// （病態 literal 不得先被切成無界陣列再拒）。
    func testSplitBoundaryExactlyThirtyTwoPassesThirtyThreeFails() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal(Array(repeating: "人", count: 32).joined(separator: "與"))]
        _ = try store.writeEntry(e)
        _ = try service.splitAuthors(["a2014:0:與=32 段是允許的最大值"])
        var after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "a2014" })
        XCTAssertEqual(after.authors.count, 32)

        var e2 = Entry(id: UUID(), citekey: "b2014", type: .periodicalArticle, title: "T")
        e2.authors = [.literal(Array(repeating: "人", count: 33).joined(separator: "與"))]
        _ = try store.writeEntry(e2)
        XCTAssertThrowsError(try service.splitAuthors(["b2014:0:與=33 段要拒"]))
        after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "b2014" })
        XCTAssertEqual(after.authors.count, 1, "拒絕必須零寫入")
    }

    /// **語法限制的釘住**（R2 verify）：分隔符無法含 `=`——第一個 `=` 之後一律是
    /// 理由。`w:0:x=y=理由` 解析成分隔符 `x`、理由 `y=理由`，而不是分隔符 `x=y`。
    /// 這是既定語法不是 bug，但它必須**看得出來**：報告的 separator／judgement 欄
    /// 逐筆揭露實際的解析結果。根治需要結構化參數（follow-up）。
    func testSplitSeparatorCannotContainEquals() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal("甲x乙")]
        _ = try store.writeEntry(e)
        let out = try json(try service.splitAuthors(["a2014:0:x=y=理由"]))
        let row = try XCTUnwrap((out["split"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["separator"] as? String, "x", "第一個 = 之前的第三段才是分隔符")
        XCTAssertEqual(row["judgement"] as? String, "y=理由", "第一個 = 之後整段是理由")
    }

    /// 換行段不是名字：`.whitespaces` 不含 `\n`，修掉前「甲與\n」會拆出一個
    /// 名字是換行符的作者（R1 verify，regression 席實測）。
    func testSplitRejectsNewlineOnlySegment() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal("甲與\n")]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.splitAuthors(["a2014:0:與=理由"]))
        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "a2014" })
        XCTAssertEqual(after.authors.count, 1, "拒絕必須零寫入")
    }

    /// **段數上界**：literal 來自 store（未信任輸入），高頻分隔符可把一個作者位
    /// 炸成無界多個 `.literal`——寫入不可逆、回傳無預算（R1 verify）。
    func testSplitRejectsPathologicalOversplit() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal(Array(repeating: "人", count: 40).joined(separator: "與"))]
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.splitAuthors(["a2014:0:與=理由"]))
        let after = try XCTUnwrap(try store.load().entries.first { $0.citekey == "a2014" })
        XCTAssertEqual(after.authors.count, 1, "拒絕必須零寫入")
    }

    /// **原文與理由進報告**——store 不留它們（誠實邊界），所以報告是唯一的
    /// 揭露面；先前只揭露了分隔符的丟棄（R1 verify HIGH 的可修一半）。
    func testSplitReportCarriesOriginalAndJudgement() throws {
        var e = Entry(id: UUID(), citekey: "a2014", type: .periodicalArticle, title: "T")
        e.authors = [.literal("鄭澈與雷庚玲")]
        _ = try store.writeEntry(e)
        let out = try json(try service.splitAuthors(["a2014:0:與=兩個人黏在一個 literal"]))
        let row = try XCTUnwrap((out["split"] as? [[String: Any]])?.first)
        XCTAssertEqual(row["original"] as? String, "鄭澈與雷庚玲")
        XCTAssertEqual(row["judgement"] as? String, "兩個人黏在一個 literal")
    }

    // MARK: - org MCP 面（#304 移轉）

    func testAddOrganizationWithParent() throws {
        _ = try service.addOrganization(key: "academia-sinica", names: ["中央研究院"],
                                        parentKey: nil, note: nil)
        _ = try service.addOrganization(key: "institute-of-statistical-science",
                                        names: ["統計科學研究所"],
                                        parentKey: "academia-sinica", note: nil)
        let load = try store.load()
        XCTAssertEqual(load.organizations.count, 2)
        let iss = try XCTUnwrap(load.organizations.first {
            $0.key == "institute-of-statistical-science" })
        XCTAssertEqual(iss.parents.entries.first?.value, .key("academia-sinica"))
        // 未知 parent 拒絕
        XCTAssertThrowsError(try service.addOrganization(
            key: "x", names: ["X"], parentKey: "nope", note: nil))
    }

    func testResolveOrganizationsCandidatesAndApply() throws {
        _ = try service.addOrganization(key: "institute-of-statistical-science",
                                        names: ["Institute of Statistical Science"],
                                        parentKey: nil, note: nil)
        var p = Person(key: "some-one", names: PersonNames(variant: ["Some One"]))
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("Institute of Statistical Science"))])
        try store.writePerson(p)
        let list = try json(try service.resolveOrganizations(apply: nil))
        let cands = try XCTUnwrap(list["candidates"] as? [[String: Any]])
        XCTAssertEqual(cands.count, 1)
        let id = try XCTUnwrap(cands[0]["id"] as? String)
        _ = try json(try service.resolveOrganizations(apply: [id]))
        let after = try store.load()
        let person = try XCTUnwrap(after.people.first { $0.key == "some-one" })
        XCTAssertEqual(person.profile.affiliations.entries.first?.value,
                       .key("institute-of-statistical-science"), "literal 升格 key")
    }

    // MARK: - 歸錯戶的退路（#418）

    /// 走真的升格路徑：literal 進庫、`--apply` 升成 key 並在 venue 上留 confirmed verdict——
    /// #554 R8 起 `repoint` 從那筆 verdict 逐字取回原 literal（不拿 title 頂替），手造的裸 key 邊會被拒。
    private func twoVenuesAndAnEntry() throws -> Entry {
        _ = try service.addVenue(key: "wikipedia", names: ["Wikipedia"], type: "website", note: nil)
        _ = try service.addVenue(key: "wikipedia-zh", names: ["維基百科"], type: "website", note: nil)
        var e = Entry(id: UUID(), citekey: "w2020", type: .referenceWorkEntry, title: "條目")
        e.venues = [.literal("Wikipedia")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["w2020:0"])
        return try XCTUnwrap(store.load().entries.first { $0.citekey == "w2020" })
    }

    /// **`--repoint` 把一條已經是 key 的邊改指到另一個 venue**（#418）。
    ///
    /// `resolve-venues --apply` 只做 literal → key 的升格。歸錯戶之後**沒有任何命令**
    /// 改得回來——person 域有 `resolve-divergence` 當退路，venue 域沒有。而
    /// `literal-first-then-key` 的整套論證建立在「漏可逆、誤不可逆」的不對稱上，
    /// 並為 person 域提供了退路；venue 域缺這一格。
    func testRepointMovesAKeyedEdgeToAnotherVenue() throws {
        _ = try twoVenuesAndAnEntry()
        let d = try json(try service.resolveVenues(apply: nil, reject: nil,
                                                   repoint: ["w2020:0:wikipedia-zh"]))
        XCTAssertEqual(d["entriesRewritten"] as? Int, 1)
        let after = try store.load().entries.first { $0.citekey == "w2020" }
        XCTAssertEqual(after?.venues, [.key("wikipedia-zh")])
    }

    /// **兩側都要留 verdict**——改指是一個身分判定，而判定會錯、錯了要能回溯
    /// （`identity-is-judged-not-matched`：判定要留 verdict、要可回溯與逆轉）。
    func testRepointWritesVerdictsOnBothVenues() throws {
        _ = try twoVenuesAndAnEntry()
        _ = try service.resolveVenues(apply: nil, reject: nil, repoint: ["w2020:0:wikipedia-zh"])
        let venues = try store.load().venues
        let old = try XCTUnwrap(venues.first { $0.key == "wikipedia" })
        let new = try XCTUnwrap(venues.first { $0.key == "wikipedia-zh" })
        XCTAssertTrue(old.references.contains { $0.field == "resolution-rejected" },
                      "舊 venue 要留 rejected——否則下次提名會再把它提出來：\(old.references)")
        XCTAssertTrue(new.references.contains { $0.field == "resolution-confirmed" },
                      "新 venue 要留 confirmed：\(new.references)")
    }

    /// **前提不符要具名略過，不得靜默**：那一格不是 key、index 越界、新 key 不存在。
    func testRepointRefusesWhenThePreconditionDoesNotHold() throws {
        _ = try twoVenuesAndAnEntry()
        // 新 key 不存在 → 整批拒絕（同 apply 的 notFound 語意）
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, reject: nil,
                                                       repoint: ["w2020:0:nope"]))
        // index 越界 → 拒絕
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, reject: nil,
                                                       repoint: ["w2020:9:wikipedia-zh"]))
        // 語法錯 → 拒絕
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, reject: nil,
                                                       repoint: ["w2020:0"]))
        // 全部拒絕後，資料不得被動過
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "w2020" }?.venues,
                       [.key("wikipedia")], "整批拒絕即零寫入")
    }

    /// **改指到自己是 no-op，不是錯誤**——冪等，重跑同一個 id 不會累積 verdict。
    func testRepointToTheSameVenueIsANoOp() throws {
        _ = try twoVenuesAndAnEntry()
        let d = try json(try service.resolveVenues(apply: nil, reject: nil,
                                                   repoint: ["w2020:0:wikipedia"]))
        XCTAssertEqual(d["entriesRewritten"] as? Int, 0)
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "w2020" }?.venues,
                       [.key("wikipedia")])
    }

    /// **降格：把誤升的 key 邊變回 literal**（#418 的第二半）。
    ///
    /// `--repoint` 只能改指到**既有**的 venue。若正確答案是「現有的都不對」——例如
    /// 那個刊名根本還沒建檔——就回不去了。`literal-first-then-key` 說 literal 是
    /// **誠實狀態**而非壞掉的 key，所以「退回誠實狀態」必須是可能的。
    ///
    /// **literal 字串從 verdict 取回**：`--apply` 寫的 `resolution-confirmed` 的
    /// value 裡逐字帶著原本的 literal（`<kind>:<key> :: <literal>` 文法，第 13 條邊）。
    /// 所以降格是**無損**的——不需要猜，也不需要拿 venue 的顯示名冒充。
    func testDemoteTurnsAKeyedEdgeBackIntoTheOriginalLiteral() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        var e = Entry(id: UUID(), citekey: "x2020", type: .periodicalArticle, title: "T")
        e.fields["journaltitle"] = "PSYCHOMETRIKA"     // WoS 全大寫形
        e.venues = [.literal("PSYCHOMETRIKA")]
        _ = try store.writeEntry(e)
        // 先升格（verdict 因此帶著原 literal）
        _ = try service.resolveVenues(apply: ["x2020:0"], reject: nil)
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "x2020" }?.venues,
                       [.key("psychometrika")], "前提：已升格")

        let d = try json(try service.resolveVenues(apply: nil, reject: nil, demote: ["x2020:0"]))
        XCTAssertEqual(d["entriesRewritten"] as? Int, 1)
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "x2020" }?.venues,
                       [.literal("PSYCHOMETRIKA")],
                       "要回到**原本的** literal，不是 venue 的顯示名")
    }

    /// **降格也要留 verdict**——否則下一輪 `--apply` 會把同一個配對再提名一次，
    /// 而使用者剛剛才說它是錯的。
    func testDemoteWritesARejectedVerdict() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        var e = Entry(id: UUID(), citekey: "x2020", type: .periodicalArticle, title: "T")
        e.venues = [.literal("PSYCHOMETRIKA")]
        _ = try store.writeEntry(e)
        _ = try service.resolveVenues(apply: ["x2020:0"], reject: nil)
        _ = try service.resolveVenues(apply: nil, reject: nil, demote: ["x2020:0"])
        let v = try XCTUnwrap(try store.load().venues.first { $0.key == "psychometrika" })
        XCTAssertTrue(v.references.contains { $0.field == "resolution-rejected" },
                      "降格要留 rejected：\(v.references)")
    }

    /// **沒有 verdict 可依據時要拒絕，不得猜**。
    ///
    /// 一條 key 邊若不是經 `--apply` 來的（例如手寫的 YAML），verdict 裡沒有它的
    /// literal。那時**拒絕**而非拿 venue 的顯示名頂替——顯示名不是那筆記錄原本寫的字，
    /// 用它會安靜改寫書目資料。
    func testDemoteRefusesWhenTheOriginalLiteralIsUnknown() throws {
        _ = try service.addVenue(key: "psychometrika", names: ["Psychometrika"],
                                 type: "periodical", note: nil)
        var e = Entry(id: UUID(), citekey: "x2020", type: .periodicalArticle, title: "T")
        e.venues = [.key("psychometrika")]            // 直接就是 key，沒有 apply 過
        _ = try store.writeEntry(e)
        XCTAssertThrowsError(try service.resolveVenues(apply: nil, reject: nil,
                                                       demote: ["x2020:0"])) { err in
            guard case ServiceError.invalid = err else { return XCTFail("預期 invalid：\(err)") }
        }
        XCTAssertEqual(try store.load().entries.first { $0.citekey == "x2020" }?.venues,
                       [.key("psychometrika")], "拒絕即零寫入")
    }
}
