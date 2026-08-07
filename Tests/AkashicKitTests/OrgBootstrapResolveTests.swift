import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// #70 第二題（resolve-organizations）＋第三題（bootstrap-organizations）。
/// 平移 person 側的機制，共用 NameNormalization（#81）；同鐵律：只提名/建立、
/// 絕不自動歸戶。
final class OrgBootstrapResolveTests: XCTestCase {

    private func personWith(_ key: String, affiliations: [OrgRef]) -> Person {
        var p = Person(key: key)
        p.profile.affiliations = TimelineOf(
            affiliations.map { TemporalValue(value: $0, range: DateRange()) })
        return p
    }

    // MARK: - bootstrap

    func testBootstrapGroupsVariantsAndCountsOccurrences() {
        let people = [
            personWith("a", affiliations: [.literal("Institute of Statistical Science")]),
            personWith("b", affiliations: [.literal("Dept of Mathematics")]),
            personWith("c", affiliations: [.literal("Institute of Statistical Science")]),  // ×2
        ]
        let cands = OrgBootstrap.candidates(people: people, organizations: [])
        XCTAssertEqual(cands.count, 2)
        let top = cands.first { $0.names.contains("Institute of Statistical Science") }
        XCTAssertEqual(top?.occurrences, 2, "同寫法出現兩次")
    }

    func testBootstrapUnifiesHyphenAndSpaceVariants() {
        let people = [
            personWith("a", affiliations: [.literal("Academia Sinica")]),
            personWith("b", affiliations: [.literal("Academia  Sinica")]),   // 雙空白
        ]
        let cands = OrgBootstrap.candidates(people: people, organizations: [])
        XCTAssertEqual(cands.count, 1, "空白差異經 matchingKey 收斂成一組")
        XCTAssertEqual(cands.first?.occurrences, 2)
        // names 保留兩種原字串（variant）
        XCTAssertEqual(cands.first?.names.count, 2)
    }

    func testBootstrapSkipsExistingOrgVariants() {
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "中研院統計所", range: DateRange())])
        let people = [personWith("a", affiliations: [.literal("中研院統計所")])]
        XCTAssertTrue(OrgBootstrap.candidates(people: people, organizations: [org]).isEmpty,
                      "已有對應 org variant 不重造")
    }

    func testBootstrapAlsoScansOrgParents() {
        var child = Organization(key: "child")
        child.parents = TimelineOf([
            TemporalValue(value: OrgRef.literal("Academia Sinica"), range: DateRange())])
        let cands = OrgBootstrap.candidates(people: [], organizations: [child])
        XCTAssertEqual(cands.count, 1)
        XCTAssertEqual(cands.first?.names, ["Academia Sinica"])
    }

    /// **已知限制**（同 person bootstrap，#140 verify 附帶觀察）：純 CJK 機構名
    /// slug 後全是非 ASCII、產不出合法 StoreKey → 不出候選。真實 affiliation 常
    /// 有英文形式可用；中文-only 機構需人先給 key（或未來羅馬拼音支援）。
    func testBootstrapCJKOnlyNameProducesNoCandidate() {
        let people = [personWith("a", affiliations: [.literal("中央研究院統計科學研究所")])]
        XCTAssertTrue(OrgBootstrap.candidates(people: people, organizations: []).isEmpty,
                      "純 CJK 名產不出 ASCII key——已知限制")
    }

    func testOrganizationsForBuildsNamesTimeline() {
        let c = OrgBootstrap.Candidate(key: "x", names: ["A", "B"], occurrences: 3)
        let orgs = OrgBootstrap.organizationsFor([c])
        XCTAssertEqual(orgs.first?.names.entries.map(\.value), ["A", "B"])
    }

    // MARK: - resolve

    func testResolveMatchesLiteralToOrgName() {
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "中央研究院統計科學研究所", range: DateRange())])
        // literal 用不同空白——matchingKey 命中
        let people = [personWith("a", affiliations: [.literal("中央研究院統計科學研究所")])]
        let cands = OrgResolver.candidates(people: people, organizations: [org])
        XCTAssertEqual(cands.count, 1)
        XCTAssertEqual(cands.first?.orgKey, "stat-sinica")
        // 輸出保留原 literal
        XCTAssertEqual(cands.first?.literal, "中央研究院統計科學研究所")
    }

    func testResolveExcludesAmbiguousMatches() {
        var o1 = Organization(key: "org-a")
        o1.names = TimelineOf([TemporalValue(value: "Sinica", range: DateRange())])
        var o2 = Organization(key: "org-b")
        o2.names = TimelineOf([TemporalValue(value: "Sinica", range: DateRange())])
        let people = [personWith("a", affiliations: [.literal("Sinica")])]
        XCTAssertTrue(OrgResolver.candidates(people: people, organizations: [o1, o2]).isEmpty,
                      "同名對 2+ org＝歧義，整組排除（絕不自動合併）")
    }

    func testApplyMigratesOnlyMatchingLiteralPreservingRange() throws {
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "統計所", range: DateRange())])
        var p = Person(key: "a")
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("統計所"),
                          range: DateRange(start: "2003"), source: "roster"),
            TemporalValue(value: OrgRef.literal("別的機構"), range: DateRange())])
        let cands = OrgResolver.candidates(people: [p], organizations: [org])
        let updated = OrgResolver.apply(cands, to: [p])
        let affs = updated.first!.profile.affiliations.entries
        XCTAssertEqual(affs.first?.value, .key("stat-sinica"), "命中的歸戶")
        XCTAssertEqual(affs.first?.range.start, "2003", "range 保留")
        XCTAssertEqual(affs.first?.source, "roster", "source 保留")
        XCTAssertEqual(affs.last?.value, .literal("別的機構"), "未命中的不動")
    }
}
