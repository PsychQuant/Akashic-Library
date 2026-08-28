import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicStoreIO
@testable import AkashicMCPKit
@testable import AkashicIndex

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

    private func twoVenuesAndAnEntry() throws -> Entry {
        _ = try service.addVenue(key: "wikipedia", names: ["Wikipedia"], type: "website", note: nil)
        _ = try service.addVenue(key: "wikipedia-zh", names: ["維基百科"], type: "website", note: nil)
        var e = Entry(id: UUID(), citekey: "w2020", type: .referenceWorkEntry, title: "條目")
        e.venues = [.key("wikipedia")]
        _ = try store.writeEntry(e)
        return e
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
