import XCTest
import AkashicCore
@testable import AkashicProposition

/// #202：求值結果必須說得出「對哪個世界、在哪個時間」。
final class ValuationContextTests: XCTestCase {

    private let personKey = "cheng-che"
    private let workKey = "w1"

    private func model(authorSlots: [AkashicCore.Author],
                       names: [String] = ["Che Cheng"]) throws -> PropositionModel {
        var e = Entry(id: UUID(), citekey: workKey, type: "article", title: "T",
                      authors: authorSlots, date: "2025")
        e.fields = [:]
        return try PropositionModel(entries: [e],
                                    people: [Person(key: personKey, names: names)])
    }

    private var authored: Proposition {
        .authored(person: .key(personKey), work: .key(workKey))
    }

    // MARK: - revision 是內容的身分

    /// **同樣的內容必得同樣的 revision。** 否則「記下 revision 以便重播」是假的。
    func testSameContentSameRevision() throws {
        let a = try model(authorSlots: [.key(personKey)])
        let b = try model(authorSlots: [.key(personKey)])
        XCTAssertEqual(a.contentRevision, b.contentRevision)
    }

    /// **求值讀得到的變動必須改變 revision**，否則兩個求值行為不同的世界會共用
    /// 同一個 revision，可重播性就是假的。
    func testRevisionCoversEverythingEvaluationReads() throws {
        let base = try model(authorSlots: [.key(personKey)])
        // 作者槽變了 → 求值結果會變 → revision 必須變
        XCTAssertNotEqual(base.contentRevision,
                          try model(authorSlots: []).contentRevision,
                          "作者槽是求值讀的，必須進 revision")
        // person 的 names 變了 → literal 比對結果會變 → revision 必須變
        XCTAssertNotEqual(base.contentRevision,
                          try model(authorSlots: [.key(personKey)], names: ["Other Name"]).contentRevision,
                          "names 是 literal 比對讀的，必須進 revision")
    }

    /// revision 與 model 不符 → 拒絕。標錯 revision 的結果不可重播，
    /// 而**假的可重播性比沒有更糟**。
    func testRevisionMismatchIsRefused() throws {
        let m = try model(authorSlots: [.key(personKey)])
        let wrong = ValuationContext(storeKey: "main", storeRevision: "deadbeefdeadbeef")
        XCTAssertThrowsError(try authored.evaluate(in: m, context: wrong)) { e in
            guard case .revisionMismatch = e as? ValuationError else {
                return XCTFail("應為 revisionMismatch，實際 \(e)")
            }
        }
    }

    // MARK: - 結果與世界綁在一起

    func testValuationCarriesItsContext() throws {
        let m = try model(authorSlots: [.key(personKey)])
        let ctx = ValuationContext(storeKey: "main", storeRevision: m.contentRevision)
        let v = try authored.evaluate(in: m, context: ctx)
        XCTAssertEqual(v.truth, .holds)
        XCTAssertEqual(v.context, ctx, "結果必須帶著它成立的世界")
        XCTAssertEqual(v.proposition, authored)
    }

    /// **不同 revision 的結果可區分且可追溯**——這是 #202 的驗收條件之一。
    func testDifferentRevisionsGiveDistinguishableResults() throws {
        let m1 = try model(authorSlots: [.key(personKey)])
        let m2 = try model(authorSlots: [])
        let v1 = try authored.evaluate(in: m1,
            context: ValuationContext(storeKey: "main", storeRevision: m1.contentRevision))
        let v2 = try authored.evaluate(in: m2,
            context: ValuationContext(storeKey: "main", storeRevision: m2.contentRevision))
        XCTAssertNotEqual(v1.truth, v2.truth, "兩個世界的真值不同")
        XCTAssertNotEqual(v1.context.storeRevision, v2.context.storeRevision,
                          "而且說得出是哪兩個世界")
    }

    // MARK: - 時間

    /// **`nil` ＝ 未指定，不是「現在」。** 沒有隱式讀 wall clock。
    func testNilValidTimeIsAcceptedAndMeansUnspecified() throws {
        let m = try model(authorSlots: [.key(personKey)])
        let v = try authored.evaluate(in: m,
            context: ValuationContext(storeKey: nil, storeRevision: m.contentRevision))
        XCTAssertNil(v.context.validTime)
        XCTAssertEqual(v.truth, .holds)
    }

    /// **不支援時間的 predicate 收到 validTime → 明確拒絕，不靜默忽略。**
    /// 忽略會讓呼叫端以為時間被納入考慮了。
    func testValidTimeOnTimelessPredicateIsRefusedNotIgnored() throws {
        let m = try model(authorSlots: [.key(personKey)])
        let ctx = ValuationContext(storeKey: "main", storeRevision: m.contentRevision,
                                   validTime: "2019")
        XCTAssertThrowsError(try authored.evaluate(in: m, context: ctx)) { e in
            XCTAssertEqual(e as? ValuationError, .timeNotSupported(predicate: "authored"))
        }
    }

    /// 三個時間**互相不能代替**——型別上就分屬三個地方。
    func testThreeTimesLiveInThreeDifferentPlaces() throws {
        let m = try model(authorSlots: [.key(personKey)])
        let ctx = ValuationContext(storeKey: "main", storeRevision: m.contentRevision)
        let a = Assertion(proposition: authored, stance: .asserted,
                          source: "import", recorded: "2026-08-09")
        let f = try adjudicate(a, in: m, acceptedBy: "che", acceptedAt: "2026-08-10")
        XCTAssertNil(ctx.validTime, "valid time 住 context")
        XCTAssertEqual(f.basis.recorded, "2026-08-09", "recorded 住 Assertion")
        XCTAssertEqual(f.acceptedAt, "2026-08-10", "accepted 住 AcceptedFact")
        XCTAssertNotEqual(f.basis.recorded, f.acceptedAt, "兩者不同且不可互代")
    }
}
