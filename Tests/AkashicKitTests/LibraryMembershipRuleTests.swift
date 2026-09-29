import XCTest
@testable import AkashicCore

/// #642：library 的成員性質是機器可讀的結構（主題型／規則型／文件型），不是寫在描述裡的自由文字。
/// 使用者 2026-09-28 照提案定案：規則型以 venue key（可加 type 集合與逐筆排除）界定、外部來源 id 只記來歷；
/// 文件型以一筆在庫的文件的 `cites` 界定；主題型的依據是使用者的選擇。
final class LibraryMembershipRuleTests: XCTestCase {

    // MARK: - YAML

    func testEachKindRoundTrips() throws {
        let cases: [Library] = [
            Library(key: "reading", name: "待讀", membership: .topic),
            Library(key: "pm-catalog", name: "Psychological Methods", description: "某刊全量",
                    membership: .rule(LibraryRule(venue: "psychological-methods", types: [.periodicalArticle],
                                                  excluded: ["appendix2020a"], source: "openalex:S45419345"))),
            Library(key: "pm-bare", name: "PM", membership: .rule(LibraryRule(venue: "psychological-methods"))),
            Library(key: "riclpm", name: "RI-CLPM", membership: .document(citekey: "cheng2026critique")),
        ]
        for lib in cases {
            let yaml = try LibraryYAML.encode(lib)
            XCTAssertEqual(try LibraryYAML.decode(yaml), lib, yaml)
            XCTAssertTrue(yaml.contains("membership:"), yaml)
        }
        // 未標性質的 library 不寫出 membership 鍵（既有檔零 diff）
        let bare = try LibraryYAML.encode(Library(key: "old", name: "舊"))
        XCTAssertFalse(bare.contains("membership"), bare)
        XCTAssertNil(try LibraryYAML.decode(bare).membership)
    }

    func testMembershipIsAKnownKeyNotAnUnknownField() throws {
        let lib = try LibraryYAML.decode("key: a\nname: A\nmembership:\n  kind: topic\n")
        XCTAssertEqual(lib.membership, .topic)
        XCTAssertTrue(lib.unknownFields.isEmpty, "membership 是 known 欄位，不得落進 tolerant-preserve")
    }

    /// 形狀是封閉的：每一種性質只收自己的鍵，值域與 key 文法都驗——不合法整檔拒讀（load 端 quarantine）。
    func testStrictShapeRejectsMalformedMembership() {
        let bad = [
            "membership: topic\n",                                              // 不是 mapping
            "membership:\n  kind: catalog\n",                                   // 值域外
            "membership:\n  venue: x\n",                                        // 缺 kind
            "membership:\n  kind: rule\n",                                      // rule 缺 venue
            "membership:\n  kind: topic\n  venue: x\n",                         // topic 不收 venue
            "membership:\n  kind: document\n",                                  // document 缺 document
            "membership:\n  kind: document\n  document: a\n  venue: x\n",       // document 不收 venue
            "membership:\n  kind: rule\n  venue: Bad Key\n",                    // venue 不是 StoreKey
            "membership:\n  kind: rule\n  venue: x\n  types: [no-such-type]\n", // type 值域外
            "membership:\n  kind: rule\n  venue: x\n  types: [book, book]\n",   // 重複
            "membership:\n  kind: rule\n  venue: x\n  excluded: [a, a]\n",      // 重複
            "membership:\n  kind: rule\n  venue: x\n  excluded: [Bad Key]\n",   // 不是 citekey
            "membership:\n  kind: rule\n  venue: x\n  source: ''\n",            // 空來歷
            "membership:\n  kind: rule\n  venue: x\n  color: red\n",            // 未知鍵
        ]
        for tail in bad {
            XCTAssertThrowsError(try LibraryYAML.decode("key: a\nname: A\n" + tail), "應拒讀：\(tail)")
        }
    }

    func testUnmarkedLibraryWarnsInValidate() {
        let unmarked = Library(key: "old", name: "舊").validate()
        XCTAssertTrue(unmarked.contains { $0.severity == .warning && $0.message.contains("set-kind") }, "\(unmarked)")
        XCTAssertTrue(Library(key: "r", name: "R", membership: .topic).validate().isEmpty)
    }

    // MARK: - 判定（決定論式：同輸入同輸出）

    private func work(_ ck: String, type: WorkType = .periodicalArticle, venues: [VenueRef] = [],
                      cites: [String] = []) -> Entry {
        var e = Entry(id: UUID(), citekey: ck, type: type, title: ck, venues: venues)
        e.akashic.relations.cites = cites
        return e
    }

    func testRuleChecksVenueTypeAndExclusions() {
        let lib = Library(key: "pm", name: "PM", membership: .rule(LibraryRule(
            venue: "psychological-methods", types: [.periodicalArticle], excluded: ["ruled2020out"])))
        let entries = [
            work("ok2020a", venues: [.key("psychological-methods")]),
            work("lit2020a", venues: [.literal("Psychological Methods")]),
            work("none2020a"),
            work("other2020a", venues: [.key("psychometrika")]),
            work("chapter2020a", type: .bookChapter, venues: [.key("psychological-methods")]),
            work("ruled2020out", venues: [.key("psychological-methods")]),
            work("two2020a", venues: [.key("publisher-x"), .key("psychological-methods")]),
        ]
        let check = LibraryMembershipCheck(library: lib, entries: entries, venues: [])
        func v(_ ck: String) -> LibraryMembershipViolation? { check.violation(of: entries.first { $0.citekey == ck }!) }
        XCTAssertNil(v("ok2020a"))
        XCTAssertNil(v("two2020a"), "多條 venue 邊只要一條 key 邊對上就符合")
        XCTAssertEqual(v("lit2020a"), .venueUnresolved)
        XCTAssertEqual(v("none2020a"), .noVenue)
        XCTAssertEqual(v("other2020a"), .otherVenue(["psychometrika"]))
        XCTAssertEqual(v("chapter2020a"), .typeNotAllowed(.bookChapter))
        XCTAssertEqual(v("ruled2020out"), .excluded)
        // 訊息逐條說得出原因（使用者從授權者變成稽核者，要看得見依據）
        XCTAssertTrue(check.basis.contains("psychological-methods"), check.basis)
        XCTAssertTrue(LibraryMembershipViolation.otherVenue(["psychometrika"]).message.contains("psychometrika"))
    }

    func testRuleWithoutTypesAcceptsAnyType() {
        let lib = Library(key: "pm", name: "PM", membership: .rule(LibraryRule(venue: "v")))
        let e = work("c2020a", type: .bookChapter, venues: [.key("v")])
        XCTAssertNil(LibraryMembershipCheck(library: lib, entries: [e], venues: []).violation(of: e))
    }

    func testDocumentMembersAreItsCites() {
        let lib = Library(key: "paper", name: "P", membership: .document(citekey: "draft2026a"))
        let doc = work("draft2026a", type: .unpublishedWork, cites: ["cited2020a"])
        let cited = work("cited2020a"), stray = work("stray2020a")
        let check = LibraryMembershipCheck(library: lib, entries: [doc, cited, stray], venues: [])
        XCTAssertNil(check.violation(of: cited))
        XCTAssertEqual(check.violation(of: stray), .notCitedByDocument("draft2026a"))
        XCTAssertEqual(check.violation(of: doc), .notCitedByDocument("draft2026a"), "文件自己不是它的文獻")

        // 文件不在庫 → 查不到它引了什麼 → 一律不符（不寫）
        let missing = LibraryMembershipCheck(library: lib, entries: [cited], venues: [])
        XCTAssertEqual(missing.violation(of: cited), .documentMissing("draft2026a"))
        // 文件 citekey 重複 → 分不出是哪一份 → 一律不符
        let dup = LibraryMembershipCheck(library: lib, entries: [doc, work("draft2026a", cites: []), cited], venues: [])
        XCTAssertEqual(dup.violation(of: cited), .documentAmbiguous("draft2026a"))
    }

    func testTopicAcceptsAnything() {
        let lib = Library(key: "t", name: "T", membership: .topic)
        let e = work("any2020a")
        XCTAssertNil(LibraryMembershipCheck(library: lib, entries: [e], venues: []).violation(of: e))
    }

    func testNonconformingMembersListsOnlyMembersInCitekeyOrder() {
        var lib = Library(key: "pm", name: "PM", membership: .rule(LibraryRule(venue: "v")))
        var a = work("b2020a"), b = work("a2020a"), ok = work("c2020a", venues: [.key("v")])
        let outsider = work("d2020a")
        a.akashic.libraries = ["pm"]; b.akashic.libraries = ["pm"]; ok.akashic.libraries = ["pm"]
        let list = LibraryMembershipCheck(library: lib, entries: [a, b, ok, outsider], venues: []).nonconformingMembers()
        XCTAssertEqual(list.map(\.citekey), ["a2020a", "b2020a"])
        XCTAssertEqual(list.map(\.violation), [.noVenue, .noVenue])
        // 未標性質：沒有依據，列不出「不符」——回空，由 validate 的未標 warning 說話
        lib.membership = nil
        XCTAssertTrue(LibraryMembershipCheck(library: lib, entries: [a, b], venues: []).nonconformingMembers().isEmpty)
    }

    func testReferencedKeysForLifecycleGuards() {
        XCTAssertEqual(LibraryMembership.document(citekey: "d").referencedCitekeys, ["d"])
        XCTAssertEqual(LibraryMembership.rule(LibraryRule(venue: "v", excluded: ["x", "y"])).referencedCitekeys, ["x", "y"])
        XCTAssertEqual(LibraryMembership.rule(LibraryRule(venue: "v")).referencedVenue, "v")
        XCTAssertNil(LibraryMembership.topic.referencedVenue)
        XCTAssertTrue(LibraryMembership.topic.referencedCitekeys.isEmpty)
    }

    // MARK: - fail-closed 與依據不明確（#642 R1 verify）

    private func venue(_ key: String) -> Venue {
        Venue(key: key, type: .periodical, names: Timeline([TemporalValue(value: key)]))
    }

    /// 未標性質不是「符合」：判定本身 fail-closed，未來的寫入面只問這個函式也不會誤放行。
    func testAnUnmarkedLibraryIsAViolationNotAConforming() {
        let lib = Library(key: "old", name: "舊")
        let e = work("any2020a")
        let check = LibraryMembershipCheck(library: lib, entries: [e], venues: [])
        XCTAssertEqual(check.violation(of: e), .libraryUnmarked)
        XCTAssertTrue(LibraryMembershipViolation.libraryUnmarked.message.contains("set-kind"))
        XCTAssertNil(check.basisProblem, "未標性質由 violation 說話，不是「依據有問題」")
    }

    /// 同一個不明確的依據，設定規則時被拒絕、使用規則時就不能放行：規則的 venue key 有不只一筆記錄 → 每一筆都不符。
    func testARuleWhoseVenueKeyIsDuplicatedRefusesEverything() {
        let lib = Library(key: "pm", name: "PM", membership: .rule(LibraryRule(venue: "psychological-methods")))
        let e = work("ok2020a", venues: [.key("psychological-methods")])
        let unique = LibraryMembershipCheck(library: lib, entries: [e], venues: [venue("psychological-methods")])
        XCTAssertNil(unique.violation(of: e)); XCTAssertNil(unique.basisProblem)
        let dup = LibraryMembershipCheck(library: lib, entries: [e],
                                         venues: [venue("psychological-methods"), venue("psychological-methods")])
        XCTAssertEqual(dup.violation(of: e), .ruleVenueAmbiguous("psychological-methods"))
        XCTAssertEqual(dup.basisProblem, .ruleVenueAmbiguous("psychological-methods"))
        XCTAssertTrue(LibraryMembershipViolation.ruleVenueAmbiguous("psychological-methods").message.contains("不只一筆"))
        // 別的 venue key 重複與這條規則無關
        let other = LibraryMembershipCheck(library: lib, entries: [e],
                                           venues: [venue("psychological-methods"), venue("x"), venue("x")])
        XCTAssertNil(other.violation(of: e))
    }

    func testTheUnmarkedMessageSaysWhoDecidesAndWhyNotTopic() {
        let m = Library.unmarkedMessage
        XCTAssertTrue(m.contains("使用者決定"), m)
        XCTAssertTrue(m.contains("store format ≥ \(LibraryMembership.requiredStoreFormat)"), m)
        XCTAssertTrue(m.contains("不要改標 topic"), m)
        XCTAssertTrue(m.contains("topic 不檢查成員"), m)
    }

    /// `basis` 只說「排除 N 筆」；完整規則（含每一個 citekey）由 `details` 給——set-kind 是整值替換，要改得先看得到全部。
    func testDetailsListsEveryExcludedCitekey() {
        let m = LibraryMembership.rule(LibraryRule(venue: "v", types: [.periodicalArticle, .book],
                                                   excluded: (0..<60).map { "ex\($0)-2020" }, source: "openalex:S1"))
        let lines = LibraryMembershipCheck.details(of: m)
        XCTAssertEqual(lines.filter { $0.hasPrefix("    · ex") }.count, 60, "不截：\(lines.count) 行")
        XCTAssertTrue(lines.contains("  type：periodical-article、book"), "\(lines)")
        XCTAssertTrue(lines.contains { $0.contains("openalex:S1") })
        XCTAssertEqual(LibraryMembershipCheck.details(of: .document(citekey: "d")).last, "  文件：d（它的 cites 即成員）")
        XCTAssertEqual(LibraryMembershipCheck.details(of: nil), ["未標性質"])
    }

    /// 排除清單是 Set 比對：大清單逐成員比對不再是 O(成員數 × 清單長度)（功能等價；效能由建構時的 `Set` 保證）。
    func testAVeryLongExcludedListStillMatchesExactly() {
        let excluded = (0..<20_000).map { "ex\($0)-2020" }
        let lib = Library(key: "pm", name: "PM", membership: .rule(LibraryRule(venue: "v", excluded: excluded)))
        let hit = work("ex19999-2020", venues: [.key("v")]), miss = work("ex20000-2020", venues: [.key("v")])
        let check = LibraryMembershipCheck(library: lib, entries: [hit, miss], venues: [])
        XCTAssertEqual(check.violation(of: hit), .excluded)
        XCTAssertNil(check.violation(of: miss))
    }
}
