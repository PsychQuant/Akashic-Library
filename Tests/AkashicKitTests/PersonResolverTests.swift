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
            rejected: [], confirmed: [])
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
            rejected: [], confirmed: [])
        XCTAssertEqual(r.candidates.map(\.personKey), ["chen-yi-hau"])
        XCTAssertEqual(r.candidates.first?.tier, .initials)
    }

    func testExactHitSuppressesLooserTiers() {
        // spec: Exact hit suppresses looser tiers——同一人同時 exact＋reorder 可達，
        // 只出一筆、tier=exact
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "Hsu, Yung-Fong")],
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong", "Yung-Fong Hsu"])],
            rejected: [], confirmed: [])
        XCTAssertEqual(r.candidates.count, 1)
        XCTAssertEqual(r.candidates.first?.tier, .exact)
    }

    func testRomanizationVariantDoesNotNominate() {
        // spec: Romanization variant does not nominate
        let r = PersonResolver.resolve(
            entries: [entry("x2025", literal: "Xu, Yung-Fong")],
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong"])],
            rejected: [], confirmed: [])
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
            rejected: [], confirmed: [])
        XCTAssertTrue(r.candidates.isEmpty)
        XCTAssertEqual(r.ambiguities.count, 1)
        XCTAssertEqual(r.ambiguities.first?.tier, .initials)
        XCTAssertEqual(r.ambiguities.first?.personKeys,
                       ["chen-chi-hsin", "chen-chun-houh"])
    }

    // MARK: - confirmed-elsewhere

    func testConfirmationElsewhereNominatesSameLiteral() {
        // spec: Confirmation in one entry nominates the same literal elsewhere
        let confirmed: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "x2020",
                              literal: "Yung-Fong Hsu", judgedKey: "hsu-yung-fong")]
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
        let confirmed: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "x2020",
                              literal: "Yung-Fong Hsu", judgedKey: "hsu-yung-fong")]
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
            rejected: rejected, confirmed: [])
        // x2025 被抑制（reorder 也不再提）；y2024 是另一次觀察，照提
        XCTAssertEqual(r.candidates.map(\.citekey), ["y2024"])
        XCTAssertEqual(r.candidates.first?.tier, .reorder)
    }

    // MARK: - 絕不自動合併

    func testNominationLeavesEntriesUnchanged() {
        // spec: High-confidence match still requires apply
        let entries = [entry("x2025", literal: "Hsu, Yung-Fong")]
        _ = PersonResolver.resolve(
            entries: entries,
            people: [person("hsu-yung-fong", names: ["Hsu, Yung-Fong"])],
            rejected: [], confirmed: [])
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
            rejected: [], confirmed: [])
        XCTAssertEqual(r.candidates.map(\.tier), [.exact, .reorder],
                       "exact 排最前，不受 citekey 字典序影響")
    }
}
