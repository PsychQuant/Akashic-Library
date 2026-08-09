import XCTest
import AkashicCore
@testable import AkashicProposition

/// #198／#199／#200 的 vertical slice。
///
/// 這一層要守的不是「查得對」，是**「查不到不等於為假」**——所有測試都繞著
/// 那條線。
final class PropositionTests: XCTestCase {

    // MARK: - Fixture

    private let personKey = "cheng-che"
    private let workKey = "cheng2025identifiability"

    private func model(authorSlots: [AkashicCore.Author],
                       personNames: [String] = ["Che Cheng", "鄭澈"]) throws -> PropositionModel {
        var e = Entry(id: UUID(uuidString: "7C1F6C2E-0000-0000-0000-0000000002A1")!,
                      citekey: workKey, type: "article", title: "T",
                      authors: authorSlots, date: "2025")
        e.fields = [:]
        return try PropositionModel(entries: [e],
                                    people: [Person(key: personKey, names: personNames)])
    }

    private var authored: Proposition {
        .authored(person: .key(personKey), work: .key(workKey))
    }

    // MARK: - #198 構造驗證

    func testMalformedKeyIsRejectedAtConstruction() throws {
        XCTAssertThrowsError(try Proposition.makeAuthored(
            person: .key("Not A Key"), work: .key(workKey))) { e in
            XCTAssertEqual(e as? PropositionError, .malformedKey("Not A Key"))
        }
    }

    /// **空 literal 不是「未知」，是構造錯誤。** 未知有它自己的表示（非空 literal
    /// 就是「還不知道指誰」），把空字串也算進去會讓兩個狀態混成一個。
    func testEmptyLiteralIsRejected() throws {
        XCTAssertThrowsError(try Proposition.makeAuthored(
            person: .literal("   "), work: .key(workKey))) { e in
            XCTAssertEqual(e as? PropositionError, .emptyLiteral)
        }
    }

    func testWellFormedPropositionIsAccepted() throws {
        let p = try Proposition.makeAuthored(person: .key(personKey), work: .literal("some title"))
        XCTAssertEqual(p.arguments.count, 2, "arity 由型別固定")
        XCTAssertEqual(p.predicateName, "authored")
    }

    /// 方向不可交換——兩者是**不同的命題**。
    func testDirectionIsPartOfIdentity() throws {
        let a = Proposition.authored(person: .key("a"), work: .key("b"))
        let b = Proposition.authored(person: .key("b"), work: .key("a"))
        XCTAssertNotEqual(a, b)
    }

    // MARK: - #199 投射

    func testUnresolvedSymbolIsNotProjectable() throws {
        let p = Proposition.authored(person: .literal("Che Cheng"), work: .key(workKey))
        XCTAssertEqual(try p.project(in: try model(authorSlots: [.key(personKey)])),
                       .unprojectable(.unresolvedSymbol(role: "person", literal: "Che Cheng")))
    }

    func testUnknownIdentityIsNotProjectable() throws {
        let p = Proposition.authored(person: .key("nobody"), work: .key(workKey))
        XCTAssertEqual(try p.project(in: try model(authorSlots: [])),
                       .unprojectable(.unknownIdentity(role: "person", key: "nobody")))
    }

    /// 把 work 放進 person 的位置——**這條證明方向是有意義的**，而且錯誤訊息要
    /// 指出真正的問題（型別不對），不是語意較弱的「找不到」。
    func testReversedArgumentsReportWrongEntityKind() throws {
        let reversed = Proposition.authored(person: .key(workKey), work: .key(personKey))
        XCTAssertEqual(try reversed.project(in: try model(authorSlots: [])),
                       .unprojectable(.wrongEntityKind(role: "person", key: workKey, expected: "person")))
    }

    func testFullyResolvedProjects() throws {
        let projection = try authored.project(in: try model(authorSlots: [.key(personKey)]))
        guard case .projected = projection else {
            return XCTFail("兩個符號都有 identity，應該投射得出來")
        }
    }

    // MARK: - 核心不變式：投射不足 → 不宣稱真值

    func testUnprojectableNeverClaimsTruth() throws {
        for p in [Proposition.authored(person: .literal("X"), work: .key(workKey)),
                  Proposition.authored(person: .key("nobody"), work: .key(workKey)),
                  Proposition.authored(person: .key(personKey), work: .key("no-such-work"))] {
            let t = try p.evaluate(in: try model(authorSlots: [.key(personKey)]))
            guard case .undetermined(.notProjectable) = t else {
                return XCTFail("投射不足卻宣稱了真值：\(t)")
            }
        }
    }

    func testSupportingEvidenceHolds() throws {
        XCTAssertEqual(try authored.evaluate(in: try model(authorSlots: [.key(personKey)])), .holds)
    }

    /// 作者槽是 literal 且字面對得上——**「像」不是「是」**。這要回未定，而且
    /// 原因要帶得出那個 literal，否則使用者無從判斷該不該去歸戶。
    func testLookalikeLiteralIsUndeterminedNotTrue() throws {
        let t = try authored.evaluate(in: try model(authorSlots: [.literal("Che Cheng")]))
        XCTAssertEqual(t, .undetermined(.supportingEvidenceUnresolved(literal: "Che Cheng")))
    }

    /// **本模組的中心主張。** 名單裡沒有他 → 未定，**不是為假**。
    ///
    /// store 不是封閉世界：作者槽可能還沒歸戶、可能匯入來源只給了前三位、可能
    /// 別名沒對上。「找不到」只支持未定。
    func testAbsenceIsUndeterminedNotFalse() throws {
        let t = try authored.evaluate(in: try model(authorSlots: [.key("someone-else")]))
        XCTAssertEqual(t, .undetermined(.noSupportingEvidence))
        XCTAssertNotEqual(t, .fails, "查不到不等於為假")
    }

    /// **誠實邊界，用測試釘住**：`authored` 目前**沒有任何輸入**會回 `.fails`。
    ///
    /// `.fails` 需要正面反證，而 store 沒有欄位能表達「這篇的作者名單已完備」。
    /// 型別留著 `.fails` 是因為答案空間需要它可被表達；規則產生不了它，是模型的
    /// 真實極限。哪天加了「名單完備」的證言型別，這條會紅——那時該連同 doc 一起改。
    func testAuthoredNeverReturnsFails() throws {
        let cases: [[AkashicCore.Author]] = [
            [], [.key(personKey)], [.key("other")], [.literal("Che Cheng")], [.literal("Someone")],
        ]
        for slots in cases {
            XCTAssertNotEqual(try authored.evaluate(in: try model(authorSlots: slots)), .fails,
                              "slots=\(slots) 產生了 .fails——若這是刻意的，doc 與本測試要一起改")
        }
    }

    // MARK: - #205 fail closed：非 canonical 輸入不得產生真值

    /// **公開 enum case 繞得過 factory 驗證**，而所有消費端都沒補驗。
    /// 實測（修前）：`.authored(person: .key("Not A Key"), …)` 配一個含同樣
    /// malformed key 的手工 model → `evaluate` 回 **`.holds`**，再被 `adjudicate`
    /// 接受成 `AcceptedFact`。
    ///
    /// 修法是在信任邊界 `validate()`；**throw 而非 `.undetermined`**——
    /// 「這不是合法命題」與「我不知道真假」是兩件事，把前者說成後者等於宣稱
    /// 一個語法錯誤只是「還沒歸戶」。
    func testDirectEnumBypassIsRefusedNotEvaluated() throws {
        let bad = Proposition.authored(person: .key("Not A Key"), work: .key(workKey))
        var e = Entry(id: UUID(), citekey: workKey, type: "article", title: "T",
                      authors: [.key("Not A Key")], date: "2025")
        e.fields = [:]
        let m = try PropositionModel(entries: [e],
                                     people: [Person(key: "Not A Key", names: ["X"])])
        XCTAssertThrowsError(try bad.evaluate(in: m)) { err in
            XCTAssertEqual(err as? PropositionError, .malformedKey("Not A Key"))
        }
        XCTAssertThrowsError(try bad.project(in: m))
        XCTAssertThrowsError(try YesNoQuestion(bad).answer(in: m))
        XCTAssertThrowsError(try adjudicate(
            Assertion(proposition: bad, stance: .asserted, source: "s", recorded: "2026-08-09"),
            in: m, acceptedBy: "che", acceptedAt: "2026-08-09"))
    }

    /// 空 literal 同理——構造錯誤不得被折成 open-world 的 unresolved symbol。
    func testEmptyLiteralIsRefusedAtEvaluation() throws {
        let bad = Proposition.authored(person: .literal("   "), work: .key(workKey))
        let m = try model(authorSlots: [])
        XCTAssertThrowsError(try bad.evaluate(in: m)) { err in
            XCTAssertEqual(err as? PropositionError, .emptyLiteral)
        }
    }

    /// **重複 citekey 必須 fail closed。** 修前是 last-wins：同一組輸入的兩種
    /// 排列得到 `.holds` 與 `.undetermined`，`AcceptedFact` 因此取決於陣列順序。
    func testDuplicateEntryCitekeyIsRefused() {
        func mk(_ authors: [AkashicCore.Author]) -> Entry {
            var e = Entry(id: UUID(), citekey: "dup", type: "article", title: "T",
                          authors: authors, date: "2025")
            e.fields = [:]
            return e
        }
        XCTAssertThrowsError(try PropositionModel(
            entries: [mk([]), mk([.key(personKey)])],
            people: [Person(key: personKey, names: ["P"])])) { err in
            XCTAssertEqual(err as? ModelError, .duplicateEntryCitekey("dup"))
        }
    }

    func testDuplicatePersonKeyIsRefused() {
        XCTAssertThrowsError(try PropositionModel(
            entries: [], people: [Person(key: "p", names: ["A"]), Person(key: "p", names: ["B"])])) { err in
            XCTAssertEqual(err as? ModelError, .duplicatePersonKey("p"))
        }
    }

    /// **排列不得改變結果。** 這是 fail-closed 的行為面：既然歧義 model 一律被
    /// 拒絕，同一組輸入的任何排列都得到同一個結果（都是拒絕）。
    ///
    /// 直接測「兩種排列的 truth value 相同」——修前這條會紅，因為一邊 `.holds`
    /// 一邊 `.undetermined`。
    func testPermutationDoesNotChangeOutcome() {
        func mk(_ authors: [AkashicCore.Author]) -> Entry {
            var e = Entry(id: UUID(), citekey: "dup", type: "article", title: "T",
                          authors: authors, date: "2025")
            e.fields = [:]
            return e
        }
        let a = mk([]), b = mk([.key(personKey)])
        let people = [Person(key: personKey, names: ["P"])]
        let p = Proposition.authored(person: .key(personKey), work: .key("dup"))

        func outcome(_ entries: [Entry]) -> String {
            do {
                let m = try PropositionModel(entries: entries, people: people)
                return String(describing: try p.evaluate(in: m))
            } catch { return "refused: \(error)" }
        }
        XCTAssertEqual(outcome([a, b]), outcome([b, a]),
                       "同一組輸入的兩種排列必須得到同一個結果")
        XCTAssertTrue(outcome([a, b]).hasPrefix("refused"), "歧義 model 應被拒絕")
    }

    // MARK: - #200 答案空間

    /// yes/no 問句有**三個**答案。少掉未定，問句就退化成「有沒有查到」。
    func testAnswerSpaceIncludesUndetermined() throws {
        let q = YesNoQuestion(authored)
        XCTAssertEqual(q.answerSpace, [.yes, .no, .undetermined])
        XCTAssertEqual(Set(q.answerSpace).count, 3, "互斥")
        XCTAssertEqual(Set(YesNoQuestion.Answer.allCases), Set(q.answerSpace), "窮盡")
    }

    func testAnswerMapsTruthWithoutFlattening() throws {
        XCTAssertEqual(try YesNoQuestion(authored)
            .answer(in: try model(authorSlots: [.key(personKey)])).answer, .yes)
        XCTAssertEqual(try YesNoQuestion(authored)
            .answer(in: try model(authorSlots: [])).answer, .undetermined)
    }

    // MARK: - 保存 ≠ 接受

    private func assertion(_ stance: Stance) -> Assertion {
        Assertion(proposition: authored, stance: stance,
                  source: "conversation", recorded: "2026-08-09")
    }

    func testAdjudicationRefusesUndetermined() throws {
        XCTAssertThrowsError(try adjudicate(assertion(.asserted),
                                            in: try model(authorSlots: []),
                                            acceptedBy: "che", acceptedAt: "2026-08-09")) { e in
            guard case .notEstablished(.undetermined) = e as? AdjudicationRefusal else {
                return XCTFail("未定必須被拒絕，實際：\(e)")
            }
        }
    }

    /// **提問不得升格為主張。** 把一個問句記進系統，不能讓它的主題命題變成被接受。
    func testQuestionedStanceCannotBecomeFact() throws {
        for s in [Stance.questioned, .denied] {
            XCTAssertThrowsError(try adjudicate(assertion(s),
                                                in: try model(authorSlots: [.key(personKey)]),
                                                acceptedBy: "che", acceptedAt: "2026-08-09")) { e in
                XCTAssertEqual(e as? AdjudicationRefusal, .stanceIsNotAssertion(s))
            }
        }
    }

    func testAdjudicationAcceptsEstablishedAssertion() throws {
        let f = try adjudicate(assertion(.asserted), in: try model(authorSlots: [.key(personKey)]),
                               acceptedBy: "che", acceptedAt: "2026-08-09")
        XCTAssertEqual(f.proposition, authored)
        XCTAssertEqual(f.basis.stance, .asserted)
        XCTAssertEqual(f.acceptedBy, "che")
    }
}
