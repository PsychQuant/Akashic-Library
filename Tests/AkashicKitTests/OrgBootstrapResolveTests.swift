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

    /// **名字必須是「產得出 key」的**（#154 verify 154-10）：原本用純 CJK 的
    /// 「中研院統計所」，它通過**不是**因為 known-variant 守衛生效，而是那個名字
    /// 本來就產不出 key——拿掉 `guard !known.contains(id)` 全套仍綠。真 binary 下
    /// 的實際後果是替既有機構複製一個 `academia-sinica-2` 分身。
    func testBootstrapSkipsExistingOrgVariants() {
        var org = Organization(key: "academia-sinica")
        org.names = TimelineOf([TemporalValue(value: "Academia Sinica", range: DateRange())])
        let people = [personWith("a", affiliations: [.literal("Academia Sinica")])]
        let result = OrgBootstrap.result(people: people, organizations: [org])
        XCTAssertTrue(result.candidates.isEmpty, "已有對應 org variant 不重造：\(result.candidates)")
        XCTAssertTrue(result.dropped.isEmpty,
                      "也不該落進 dropped——它不是「產不出 key」而是「已經有了」：\(result.dropped)")
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

    /// #154 verify 154-1：雙語名（台灣機構最常見）用**英文 token** 產 key——
    /// 曾因含 CJK 讓整個候選被丟。
    func testBootstrapBilingualNameUsesAsciiTokens() {
        let people = [personWith("a", affiliations: [
            .literal("國立臺灣大學 National Taiwan University")])]
        let cands = OrgBootstrap.candidates(people: people, organizations: [])
        XCTAssertEqual(cands.count, 1, "雙語名不該被丟")
        XCTAssertEqual(cands.first?.key, "national-taiwan-university",
                       "key 取 ASCII token：\(cands)")
        XCTAssertEqual(cands.first?.names, ["國立臺灣大學 National Taiwan University"],
                       "names 保留原字串")
    }

    /// 全形拉丁要能產 key（#154 verify 154-5）——CJK 輸入法下全形英數是常見產物，
    /// 逐字元 `isASCII` 判斷會把整串濾掉、機構被誤丟。key 產生的正規化階梯要與
    /// 配對鍵（`NameNormalization.matchingKey`，第一步就是 NFKC）對齊，否則會出現
    /// 「配得上但建不出來」的錯位。
    func testFullwidthLatinStillProducesKey() {
        let people = [personWith("a", affiliations: [
            .literal("Ｎａｔｉｏｎａｌ　Ｔａｉｗａｎ　Ｕｎｉｖｅｒｓｉｔｙ")])]
        let result = OrgBootstrap.result(people: people, organizations: [])
        XCTAssertEqual(result.candidates.first?.key, "national-taiwan-university",
                       "全形拉丁 NFKC 後就是 ASCII：\(result)")
        XCTAssertTrue(result.dropped.isEmpty, "不該被丟：\(result.dropped)")
        XCTAssertEqual(result.candidates.first?.names,
                       ["Ｎａｔｉｏｎａｌ　Ｔａｉｗａｎ　Ｕｎｉｖｅｒｓｉｔｙ"],
                       "正規化只用於產 key，names 存原字串")
    }

    /// 純 CJK（無 ASCII token）仍產不出 key——但**不靜默丟**，進 result.dropped。
    func testCJKOnlyNameGoesToDroppedNotSilent() {
        let people = [personWith("a", affiliations: [.literal("中央研究院統計科學研究所")])]
        let result = OrgBootstrap.result(people: people, organizations: [])
        XCTAssertTrue(result.candidates.isEmpty, "純 CJK 產不出 key")
        XCTAssertEqual(result.dropped.count, 1, "但要進 dropped 讓 CLI 說出來")
        XCTAssertEqual(result.dropped.first?.name, "中央研究院統計科學研究所")
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

    /// **NFKC 不得讓符號殘渣變成 key**（#154 verify 154-7——NFKC 引入的回歸）。
    ///
    /// `℡`／`™`／`Ⅲ`／`①`／`２` 經 NFKC 折成 ASCII 後，純 CJK 名字突然「產得出
    /// key」。席位實測 8 個名字有 6 個從誠實 dropped 變成垃圾 key，且已用 `--apply`
    /// 實際寫進 store（`中央研究院℡`→`tel`、`國家衛生研究院℡`→`tel-2`——兩個不相干
    /// 的機構被一個符號綁進同一個 key 家族）。
    func testSymbolResidueDoesNotProduceKeys() {
        for name in ["中央研究院℡", "中央研究院™", "中研院①", "第２醫院",
                     "榮總２院區", "中央研究院（Ａ）", "國立臺灣大學Ⅲ"] {
            let result = OrgBootstrap.result(
                people: [personWith("a", affiliations: [.literal(name)])], organizations: [])
            XCTAssertTrue(result.candidates.isEmpty,
                          "「\(name)」的 ASCII 產出只是符號殘渣，不該當 key：\(result.candidates)")
            XCTAssertEqual(result.dropped.first?.name, name,
                           "要誠實列進 dropped（154-1 的目的），不是產一個假 key")
        }
    }

    /// 但 NFKC 的**真收穫**不能一起擋掉：全形拉丁、ligature、以及**短的**雙語名
    /// （`臺大 NTU` 只有 60% ASCII）仍要產得出 key。門檻上下有 23 個百分點的空隙。
    func testShortBilingualNamesStillProduceKeys() {
        for (name, key) in [("臺大 NTU", "ntu"),
                            ("中央研究院 Academia Sinica", "academia-sinica"),
                            ("國立臺灣大學 National Taiwan University",
                             "national-taiwan-university")] {
            let r = OrgBootstrap.result(
                people: [personWith("a", affiliations: [.literal(name)])], organizations: [])
            XCTAssertEqual(r.candidates.first?.key, key,
                           "「\(name)」是真雙語名，不得被殘渣閘誤擋：\(r)")
        }
    }

    func testNFKCStillFoldsRealLatin() {
        let result = OrgBootstrap.result(people: [
            personWith("a", affiliations: [.literal("ﬁnance Institute")]),
            personWith("b", affiliations: [.literal("finance Institute")]),
        ], organizations: [])
        XCTAssertEqual(result.candidates.count, 1, "ligature 與 ASCII 併成一組：\(result.candidates)")
        XCTAssertEqual(result.candidates.first?.key, "finance-institute")
        XCTAssertEqual(result.candidates.first?.names.count, 2, "兩種寫法都保留為 variant")
    }
}
