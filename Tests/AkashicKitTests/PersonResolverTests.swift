import XCTest
import Foundation
@testable import AkashicCore
@testable import AkashicEntity

/// 四 tier 提名（#303；spec person-resolution 逐 scenario）。
/// 既有 exact 行為的守衛住 `EntityTests`——本檔只管寬鬆 tier 與抑制序。
final class PersonResolverTests: XCTestCase {

    private func entry(_ citekey: String, literal: String) -> Entry {
        var e = Entry(id: UUID(), citekey: citekey, type: "article", title: "T")
        e.authors = [.literal(literal)]
        return e
    }

    private func person(_ key: String, names: [String]) -> Person {
        Person(key: key, names: PersonNames(variant: names))
    }

    // MARK: - 提名 tier

    func testTokenReorderNominatesAtReorderTier() {
        // spec: Token reorder nominates at reorder tier
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "Yung-Fong Hsu")],
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong"])],
            rejected: [], confirmed: [:])
        XCTAssertEqual(r.candidates.count, 1)
        XCTAssertEqual(r.candidates.first?.personKey, "hsu-yung-fong")
        XCTAssertEqual(r.candidates.first?.tier, .reorder)
        XCTAssertTrue(r.ambiguities.isEmpty)
    }

    func testInitialsFormNominatesAtInitialsTier() {
        // spec: Initials form nominates at initials tier
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "Chen, Y.-H.")],
            people: [person("chen-yi-hau", names: ["Chen, Yi-Hau"])],
            rejected: [], confirmed: [:])
        XCTAssertEqual(r.candidates.map(\.personKey), ["chen-yi-hau"])
        XCTAssertEqual(r.candidates.first?.tier, .initials)
    }

    func testExactHitSuppressesLooserTiers() {
        // spec: Exact hit suppresses looser tiers——同一人同時 exact＋reorder 可達，
        // 只出一筆、tier=exact
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "Hsu, Yung-Fong")],
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong", "Yung-Fong Hsu"])],
            rejected: [], confirmed: [:])
        XCTAssertEqual(r.candidates.count, 1)
        XCTAssertEqual(r.candidates.first?.tier, .exact)
    }

    func testRomanizationVariantDoesNotNominate() {
        // spec: Romanization variant does not nominate
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "Xu, Yung-Fong")],
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong"])],
            rejected: [], confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty)
        XCTAssertTrue(r.ambiguities.isEmpty)
    }

    // MARK: - 歧義

    func testInitialsCollisionBecomesAmbiguityWithTier() {
        // spec: Initials collision becomes ambiguity——兩人 initials 鍵同為 chen ch
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "C-H Chen")],
            people: [person("chen-chun-houh", names: ["Chen, Chun-Houh"]),
                     person("chen-chi-hsin", names: ["Chen, Chi-Hsin"])],
            rejected: [], confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty)
        XCTAssertEqual(r.ambiguities.count, 1)
        XCTAssertEqual(r.ambiguities.first?.tier, .initials)
        XCTAssertEqual(r.ambiguities.first?.personKeys,
                       ["chen-chi-hsin", "chen-chun-houh"])
    }

    // MARK: - confirmed-elsewhere

    func testConfirmationElsewhereNominatesSameLiteral() {
        // spec: Confirmation in one entry nominates the same literal elsewhere
        let confirmed: [ResolutionPairing: String] = [
            ResolutionPairing(holderKind: .work, holder: "x2020",
                              literal: "Yung-Fong Hsu",
                              judgedKey: "hsu-yung-fong"): ResolutionLedger.personRule]
        // person 的 alias **不含**這個寫法（正是 alias 未收斂的情境）——
        // 但因他處 confirmed，照樣提名
        let people = [person("hsu-yung-fong", names: ["徐永豐"])]
        let r = PersonResolver.resolve(
            entries: [entry("y2024", literal: "Yung-Fong Hsu")],
            people: people, rejected: [], confirmed: confirmed)
        XCTAssertEqual(r.candidates.count, 1)
        XCTAssertEqual(r.candidates.first?.tier, .confirmedElsewhere)
        XCTAssertEqual(r.candidates.first?.personKey, "hsu-yung-fong")
        // apply 不改寫 person 的 names（spec 同 requirement 尾句）——
        // apply 只動 entries，people 陣列根本不進 apply
        let applied = PersonResolver.apply(r.candidates,
                                           to: [entry("y2024", literal: "Yung-Fong Hsu")])
        XCTAssertEqual(applied.first?.authors, [.key("hsu-yung-fong")])
        XCTAssertEqual(people.first?.names.all, ["徐永豐"], "names 原樣")
    }

    func testConfirmedElsewhereRanksAboveReorder() {
        // 同 literal 同人同時可由 confirmed 與 reorder 到達 → 只出一筆、tier=confirmed-elsewhere
        let confirmed: [ResolutionPairing: String] = [
            ResolutionPairing(holderKind: .work, holder: "x2020",
                              literal: "Yung-Fong Hsu",
                              judgedKey: "hsu-yung-fong"): ResolutionLedger.personRule]
        let r = PersonResolver.resolve(
            entries: [entry("y2024", literal: "Yung-Fong Hsu")],
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong"])],
            rejected: [], confirmed: confirmed)
        XCTAssertEqual(r.candidates.count, 1)
        XCTAssertEqual(r.candidates.first?.tier, .confirmedElsewhere)
    }

    // MARK: - rejected 全 tier 抑制

    func testRejectionSuppressesLooseRenominationButOtherEntryStillNominates() {
        // spec: Rejection suppresses loose re-nomination
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "x2025",
                              literal: "Yung-Fong Hsu", judgedKey: "hsu-yung-fong")]
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "Yung-Fong Hsu"),
                      entry("y2024", literal: "Yung-Fong Hsu")],
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong"])],
            rejected: rejected, confirmed: [:])
        // x2025 被抑制（reorder 也不再提）；y2024 是另一次觀察，照提
        XCTAssertEqual(r.candidates.map(\.citekey), ["y2024"])
        XCTAssertEqual(r.candidates.first?.tier, .reorder)
    }

    // MARK: - R1-fix B7：reject-then-count 的兩個後果顯式 spec 化＋揭露

    func testRejectionCollapsesTwoHitTierToDisclosedSurvivor() {
        // exact 2-hit 其一被否決 → 另一人成為可 apply 候選，但 reason 揭露淘汰史
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "x2025",
                              literal: "Che Cheng", judgedKey: "cheng-che")]
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "Che Cheng")],
            people: [person("cheng-che", names: ["Che Cheng"]),
                     person("cheng-che-2", names: ["Che Cheng"])],
            rejected: rejected, confirmed: [:])
        XCTAssertEqual(r.candidates.map(\.personKey), ["cheng-che-2"])
        XCTAssertEqual(r.candidates.first?.tier, .exact)
        XCTAssertTrue(r.candidates.first?.reason.contains("已被否決") == true,
                      "淘汰而得的唯一命中必須留痕：\(r.candidates.first?.reason ?? "")")
        XCTAssertTrue(r.ambiguities.isEmpty)
    }

    func testRejectionFallThroughNominationIsDisclosed() {
        // 否決 exact 唯一命中 → 低 tier 為**另一個人**造出的新提名也要留痕
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "e1",
                              literal: "Chen, Yi-Hau", judgedKey: "chen-yi-hau")]
        let r = PersonResolver.resolve(
            entries: [entry("e1", literal: "Chen, Yi-Hau")],
            people: [person("chen-yi-hau", names: ["Chen, Yi-Hau"]),
                     person("chen-yu-hsuan", names: ["Chen, Yu-Hsuan"])],
            rejected: rejected, confirmed: [:])
        XCTAssertEqual(r.candidates.map(\.personKey), ["chen-yu-hsuan"])
        XCTAssertEqual(r.candidates.first?.tier, .initials)
        XCTAssertTrue(r.candidates.first?.reason.contains("已被否決") == true,
                      "\(r.candidates.first?.reason ?? "")")
    }

    // MARK: - R3-fix R4-2：淘汰計數去重（1 筆否決不得報成 3）

    func testEliminationCountIsDeduplicatedAcrossTiers() {
        // 被否決者的名字同時住 exact／reorder／initials 三個鍵空間——計人不計 tier
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "x2025",
                              literal: "Che Cheng", judgedKey: "cheng-che")]
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "Che Cheng")],
            people: [person("cheng-che", names: ["Che Cheng"]),
                     person("cheng-che-2", names: ["Che Cheng"])],
            rejected: rejected, confirmed: [:])
        let reason = r.candidates.first?.reason ?? ""
        XCTAssertTrue(reason.contains("1 個候選配對已被否決"),
                      "同一否決跨多鍵空間只計一次：\(reason)")
        XCTAssertFalse(reason.contains("2 個") || reason.contains("3 個"), reason)
    }

    // MARK: - R1-fix I1：否決比對與提名同一套正規化

    func testRejectionSuppressionMatchesNormalizedLiteral() {
        // verdict 記的是 EN DASH（U+2013）、entry 是 ASCII 連字號——同一寫法，
        // 否決必須壓得住（正規化不對稱曾讓否決失效而確認生效）
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "f1",
                              literal: "Cheng\u{2013}Der Fuh", judgedKey: "fuh-cheng-der")]
        let r = PersonResolver.resolve(
            entries: [entry("f1", literal: "Cheng-Der Fuh")],
            people: [person("fuh-cheng-der", names: ["Cheng-Der Fuh"])],
            rejected: rejected, confirmed: [:])
        XCTAssertTrue(r.candidates.isEmpty, "\(r.candidates)")
    }

    // MARK: - R1-fix I2：confirmed 提名只吃 work-holder 的 verdict

    func testConfirmedElsewhereIgnoresNonWorkHolders() {
        let confirmed: [ResolutionPairing: String] = [
            ResolutionPairing(holderKind: .person, holder: "some-one",
                              literal: "Yung-Fong Hsu",
                              judgedKey: "hsu-yung-fong"): ResolutionLedger.personRule]
        let r = PersonResolver.resolve(
            entries: [entry("y2024", literal: "Yung-Fong Hsu")],
            people: [person("hsu-yung-fong", names: ["徐永豐"])],
            rejected: [], confirmed: confirmed)
        XCTAssertTrue(r.candidates.isEmpty,
                      "org/person-holder 的 verdict 不得餵 person 提名：\(r.candidates)")
    }

    // MARK: - R2-fix R3-6：跨 tier fall-through 揭露（spec R7 後果 b）

    func testFallThroughAfterConfirmedElsewhereEliminationIsDisclosed() {
        // confirmed-elsewhere 命中被否決清空 → reorder 對另一人提名也要留痕
        let confirmed: [ResolutionPairing: String] = [
            ResolutionPairing(holderKind: .work, holder: "x2020",
                              literal: "Yung-Fong Hsu",
                              judgedKey: "alpha"): "author-name-exact"]
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "y2024",
                              literal: "Yung-Fong Hsu", judgedKey: "alpha")]
        let r = PersonResolver.resolve(
            entries: [entry("y2024", literal: "Yung-Fong Hsu")],
            people: [person("alpha", names: ["名不相干"]),
                     person("bravo", names: ["Hsu, Yung-Fong"])],
            rejected: rejected, confirmed: confirmed)
        XCTAssertEqual(r.candidates.map(\.personKey), ["bravo"])
        XCTAssertEqual(r.candidates.first?.tier, .reorder)
        XCTAssertTrue(r.candidates.first?.reason.contains("已被否決") == true,
                      "高 tier 全滅後的 fall-through 提名必須留痕：\(r.candidates.first?.reason ?? "")")
    }

    // MARK: - R2-fix R3-7：confirmed-elsewhere 的 ancestry 揭露

    func testConfirmedElsewhereDisclosesWeakSourceRule() {
        let confirmed: [ResolutionPairing: String] = [
            ResolutionPairing(holderKind: .work, holder: "x2020",
                              literal: "Chen, Y.-H.",
                              judgedKey: "chen-yi-hau"): "author-name-initials"]
        let r = PersonResolver.resolve(
            entries: [entry("y2024", literal: "Chen, Y.-H.")],
            people: [person("chen-yi-hau", names: ["名不相干"])],
            rejected: [], confirmed: confirmed)
        XCTAssertEqual(r.candidates.first?.tier, .confirmedElsewhere)
        XCTAssertTrue(r.candidates.first?.reason.contains("author-name-initials") == true,
                      "弱血統要可見：\(r.candidates.first?.reason ?? "")")
    }

    func testConfirmedElsewhereFromExactRuleHasNoAncestryNoise() {
        let confirmed: [ResolutionPairing: String] = [
            ResolutionPairing(holderKind: .work, holder: "x2020",
                              literal: "Yung-Fong Hsu",
                              judgedKey: "hsu-yung-fong"): "author-name-exact"]
        let r = PersonResolver.resolve(
            entries: [entry("y2024", literal: "Yung-Fong Hsu")],
            people: [person("hsu-yung-fong", names: ["徐永豐"])],
            rejected: [], confirmed: confirmed)
        XCTAssertEqual(r.candidates.first?.tier, .confirmedElsewhere)
        XCTAssertFalse(r.candidates.first?.reason.contains("author-name") == true,
                       "exact 血統不加噪音：\(r.candidates.first?.reason ?? "")")
    }

    // MARK: - 絕不自動合併

    func testNominationLeavesEntriesUnchanged() {
        // spec: High-confidence match still requires apply
        let entries = [entry("x2025", literal: "Hsu, Yung-Fong")]
        _ = PersonResolver.resolve(
            entries: entries,
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong"])],
            rejected: [], confirmed: [:])
        XCTAssertEqual(entries.first?.authors, [.literal("Hsu, Yung-Fong")],
                       "resolve 是純函式——提名不改寫")
    }

    // MARK: - 排序（design D4：tier 信心降冪 → citekey → index）

    func testCandidatesSortByTierThenCitekey() {
        let r = PersonResolver.resolve(
            entries: [entry("b2020", literal: "Yung-Fong Hsu"),     // reorder
                      entry("a2021", literal: "Lay, Keng-Ling")],   // exact
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong"]),
                     person("lay-keng-ling", names: ["Lay, Keng-Ling"])],
            rejected: [], confirmed: [:])
        XCTAssertEqual(r.candidates.map(\.tier), [.exact, .reorder],
                       "exact 排最前，不受 citekey 字典序影響")
    }
}
