import XCTest
import AkashicCore
@testable import AkashicProposition

/// #203：顯式否定命題，與**可證成**的否定答案。
final class NegationTests: XCTestCase {

    private let personKey = "cheng-che"
    private let workKey = "w1"

    private func model(_ slots: [AkashicCore.Author]) throws -> PropositionModel {
        var e = Entry(id: UUID(), citekey: workKey, type: "article", title: "T",
                      authors: slots, date: "2025")
        e.fields = [:]
        return try PropositionModel(entries: [e],
                                    people: [Person(key: personKey, names: ["Che Cheng"]),
                                             Person(key: "other", names: ["Other One"])])
    }

    private func attestation() throws -> AuthorListAttestation {
        try AuthorListAttestation(workCitekey: workKey, attestedBy: "che",
                                  attestedAt: "2026-08-09", basis: "出版社頁面核對")
    }

    private var authored: Proposition {
        .authored(person: .key(personKey), work: .key(workKey))
    }

    // MARK: - ¬p 是命題，不是立場也不是答案標籤

    /// `Stance.denied`（某人否認）與 `Answer.no`（對問句的回答）都**不是** `¬p`。
    /// `¬p` 自己可以被求值、組合。
    func testNegationIsAPropositionNotAStance() throws {
        let m = try model([.key(personKey)])
        XCTAssertEqual(try Formula.atom(authored).evaluate(in: m), .holds)
        XCTAssertEqual(try Formula.not(.atom(authored)).evaluate(in: m), .fails,
                       "p 成立 → ¬p 為假")
        // 雙重否定
        XCTAssertEqual(try Formula.not(.not(.atom(authored))).evaluate(in: m), .holds)
    }

    /// **`p` 未定時 `¬p` 也未定，不是 true。** 這是整個模組從第一天就在擋的
    /// closed-world 誤推——把「不知道 p」讀成「¬p 成立」。
    func testUndeterminedNegatesToUndetermined() throws {
        let m = try model([])
        XCTAssertEqual(try Formula.atom(authored).evaluate(in: m),
                       .undetermined(.noSupportingEvidence))
        guard case .undetermined = try Formula.not(.atom(authored)).evaluate(in: m) else {
            return XCTFail("未定的否定必須仍是未定——不得變成 true")
        }
    }

    // MARK: - `.fails` 現在可達，但要有證言

    /// **沒有證言 → 永遠不會 `.fails`**（PR #201 記錄的誠實邊界仍然成立）。
    func testWithoutAttestationFailsIsStillUnreachable() throws {
        let m = try model([.key("other")])
        XCTAssertEqual(try Formula.atom(authored).evaluate(in: m),
                       .undetermined(.noSupportingEvidence))
    }

    /// **有完備性證言 + 名單全部已歸戶 + 名單裡沒有他 → `.fails`。**
    /// 這是本 change 讓 `.fails` 可達的唯一路徑。
    func testAttestedCompleteListYieldsFails() throws {
        let m = try (model([.key("other")])).attesting([try attestation()])
        XCTAssertEqual(try Formula.atom(authored).evaluate(in: m), .fails)
        XCTAssertEqual(try Formula.not(.atom(authored)).evaluate(in: m), .holds,
                       "p 為假 → ¬p 成立")
    }

    /// **完備 ≠ 已歸戶。** 證言說名單完備，但槽位還是 literal 時我們**仍然不知道**
    /// 那個 literal 是不是他——不得回 `.fails`。
    ///
    /// 少了這個條件，一篇「已核對但都還沒歸戶」的 work 會對每個人回 `.fails`。
    func testAttestedButUnresolvedSlotsStaysUndetermined() throws {
        let m = try (model([.literal("Someone Else")])).attesting([try attestation()])
        guard case .undetermined = try Formula.atom(authored).evaluate(in: m) else {
            return XCTFail("還有未歸戶的槽位就不得宣稱反證")
        }
    }

    /// 有正面支持時，證言不改變答案（第 1 步優先於第 2 步）。
    func testAttestationDoesNotOverrideePositiveSupport() throws {
        let m = try (model([.key(personKey)])).attesting([try attestation()])
        XCTAssertEqual(try Formula.atom(authored).evaluate(in: m), .holds)
    }

    /// 別篇的證言不能用來否定這一篇。
    func testAttestationForAnotherWorkDoesNotApply() throws {
        let other = try AuthorListAttestation(workCitekey: "w2", attestedBy: "che",
                                              attestedAt: "2026-08-09", basis: "x")
        let m = try (model([.key("other")])).attesting([other])
        guard case .undetermined = try Formula.atom(authored).evaluate(in: m) else {
            return XCTFail("別篇的證言不得用於本篇")
        }
    }

    // MARK: - 證言本身的紀律

    /// **basis 必填**——沒有依據的完備性證言只是一句斷言，撐不起反證。
    func testAttestationRequiresBasis() {
        XCTAssertThrowsError(try AuthorListAttestation(
            workCitekey: workKey, attestedBy: "che", attestedAt: "2026", basis: "  ")) { e in
            XCTAssertEqual(e as? AttestationError, .basisRequired(workCitekey: workKey))
        }
    }

    /// 同 #205 的立場：歧義輸入 fail closed，不 last-wins。
    func testDuplicateAttestationIsRefused() throws {
        let a = try attestation()
        XCTAssertThrowsError(try (model([])).attesting([a, a])) { e in
            XCTAssertEqual(e as? AttestationError, .duplicateAttestation(workKey))
        }
    }

    // MARK: - 否定答案攜帶內容

    /// **`.no` 要帶 `¬p` 的內容**，不只是一個標籤（#203 的驗收條件）。
    func testNegativeAnswerCarriesTheNegatedProposition() throws {
        let m = try (model([.key("other")])).attesting([try attestation()])
        let a = try YesNoQuestion(authored).answer(in: m)
        XCTAssertEqual(a.answer, .no)
        XCTAssertEqual(a.truth, .fails)
        XCTAssertEqual(a.content, .not(.atom(authored)), "否定答案必須攜帶 ¬p")
    }

    func testPositiveAnswerCarriesP() throws {
        let m = try (model([.key(personKey)])).attesting([try attestation()])
        let a = try YesNoQuestion(authored).answer(in: m)
        XCTAssertEqual(a.answer, .yes)
        XCTAssertEqual(a.content, .atom(authored))
    }
}
