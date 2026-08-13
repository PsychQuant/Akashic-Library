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
        let cands = OrgResolver.candidates(people: people, organizations: [org], rejected: [])
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
        XCTAssertTrue(OrgResolver.candidates(people: people, organizations: [o1, o2], rejected: []).isEmpty,
                      "同名對 2+ org＝歧義，整組排除（絕不自動合併）")
    }

    /// #231：排除之後**要留下痕跡**。org 側與 person 側同形。
    ///
    /// `holder` 是 org 側獨有的必要資訊——同一個 literal 可能住在 person 的
    /// `affiliations`，也可能住在另一個 org 的 `parents`（#166）。少了它，報告
    /// 說不出「是誰的哪一段 literal 歧義」。
    func testResolveReportsAmbiguitiesWithHolder() {
        var o1 = Organization(key: "org-a")
        o1.names = TimelineOf([TemporalValue(value: "Sinica", range: DateRange())])
        var o2 = Organization(key: "org-b")
        o2.names = TimelineOf([TemporalValue(value: "Sinica", range: DateRange())])
        // 第三個 org 的 parents 也寫著同一個歧義 literal → 兩個不同 holder
        var child = Organization(key: "org-child")
        child.names = TimelineOf([TemporalValue(value: "Child Institute", range: DateRange())])
        child.parents = TimelineOf([TemporalValue(value: OrgRef.literal("Sinica"), range: DateRange())])
        let people = [personWith("a", affiliations: [.literal("Sinica")])]

        let r = OrgResolver.resolve(people: people, organizations: [o1, o2, child], rejected: [])
        XCTAssertTrue(r.candidates.isEmpty, "行為未變：歧義仍不出候選")
        XCTAssertEqual(r.ambiguities.count, 2, "person 的 affiliation 與 org 的 parents 各一")
        XCTAssertEqual(r.ambiguities.map(\.holder),
                       [.person("a"), .organization("org-child")],
                       "holder 必須分得出來，且 people 先於 organizations")
        XCTAssertTrue(r.ambiguities.allSatisfy { $0.literal == "Sinica" })
        XCTAssertTrue(r.ambiguities.allSatisfy { $0.orgKeys == ["org-a", "org-b"] },
                      "orgKeys 排序，輸出穩定")
    }

    /// `candidates` 是 `resolve` 的薄包裝，**不是第二支遍歷**——parents 側帶著
    /// 自我父權與環的排除，兩支遍歷分岔時那些排除只會存在於其中一支。
    func testOrgCandidatesIsExactlyResolveCandidates() {
        var parent = Organization(key: "org-parent")
        parent.names = TimelineOf([TemporalValue(value: "Academia", range: DateRange())])
        var child = Organization(key: "org-child")
        child.names = TimelineOf([TemporalValue(value: "Institute", range: DateRange())])
        child.parents = TimelineOf([TemporalValue(value: OrgRef.literal("Academia"), range: DateRange())])
        let people = [personWith("a", affiliations: [.literal("Academia")])]
        XCTAssertEqual(OrgResolver.candidates(people: people, organizations: [parent, child], rejected: []),
                       OrgResolver.resolve(people: people, organizations: [parent, child], rejected: []).candidates)
    }

    func testApplyMigratesOnlyMatchingLiteralPreservingRange() throws {
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "統計所", range: DateRange())])
        var p = Person(key: "a")
        p.profile.affiliations = TimelineOf([
            TemporalValue(value: OrgRef.literal("統計所"),
                          range: DateRange(start: "2003"), source: "roster"),
            TemporalValue(value: OrgRef.literal("別的機構"), range: DateRange())])
        let cands = OrgResolver.candidates(people: [p], organizations: [org], rejected: [])
        let updated = OrgResolver.apply(cands, to: [p], organizations: [org])
        let affs = updated.people.first!.profile.affiliations.entries
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

/// #166：兩步式流程的第二步對 `organization.parents` **結構上不存在**。
///
/// `bootstrap-organizations` 會**吃** parents 的 literal 並據此建 organization，
/// 但 `candidates` 只走 person 的 affiliations——剛為它建出來的那個 organization
/// 永遠配不上它。literal 進得去、出不來。
///
/// ## parents 側有 person 側沒有的兩個危害
///
/// person 的 affiliation 指向自己是**不可表達的**（型別不同），parents 則完全
/// 可能。而環在本 repo **沒有任何地方偵測**（`crossRecordIssues` 不查、載入不查），
/// 所以歸戶造出來的環不會有人擋——防護放在製造點。
extension OrgBootstrapResolveTests {

    private func org(_ key: String, names: [String] = [],
                     parents: [OrgRef] = []) -> Organization {
        var o = Organization(key: key)
        o.names = TimelineOf(names.map { TemporalValue(value: $0, range: DateRange()) })
        o.parents = TimelineOf(parents.map { TemporalValue(value: $0, range: DateRange()) })
        return o
    }

    /// 核心缺口：parents 的 literal 要出得來。
    func testParentsLiteralsProduceCandidates() {
        let parent = org("academia-sinica", names: ["中央研究院"])
        let child = org("stat-sinica", names: ["統計科學研究所"],
                        parents: [.literal("中央研究院")])
        let cands = OrgResolver.candidates(people: [], organizations: [parent, child], rejected: [])
        XCTAssertEqual(cands.count, 1, "parents 的 literal 進得去也要出得來：\(cands)")
        XCTAssertEqual(cands.first?.holder, .organization("stat-sinica"))
        XCTAssertEqual(cands.first?.orgKey, "academia-sinica")
        XCTAssertTrue(cands.first?.reason.contains("parents") == true,
                      "理由要說出這是哪一條路徑——兩類候選寫進不同記錄的不同欄位")
    }

    /// `apply` 要能改 organization（先前只改 person）。
    func testApplyMigratesOrganizationParents() {
        let parent = org("academia-sinica", names: ["中央研究院"])
        var child = org("stat-sinica", names: ["統計科學研究所"])
        child.parents = TimelineOf([
            TemporalValue(value: OrgRef.literal("中央研究院"),
                          range: DateRange(start: "1947"), source: "所史", note: "n"),
            TemporalValue(value: OrgRef.literal("別的機構"), range: DateRange())])
        let cands = OrgResolver.candidates(people: [], organizations: [parent, child], rejected: [])
        let out = OrgResolver.apply(cands, to: [], organizations: [parent, child])
        let ps = out.organizations.first { $0.key == "stat-sinica" }!.parents.entries
        XCTAssertEqual(ps.first?.value, .key("academia-sinica"), "命中的歸戶")
        XCTAssertEqual(ps.first?.range.start, "1947", "range 保留")
        XCTAssertEqual(ps.first?.source, "所史", "source 保留")
        XCTAssertEqual(ps.first?.note, "n", "note 保留")
        XCTAssertEqual(ps.last?.value, .literal("別的機構"), "未命中的不動")
        XCTAssertEqual(out.organizations.first { $0.key == "academia-sinica" }, parent,
                       "沒有候選指向它的記錄不得被動到")
    }

    /// **自我父權**：literal 命中自己的別名 → 不提名。那不是歸戶，是把記錄變成
    /// 自己的上級。手工資料把同一機構的別名順手寫進自己的 parents 是常見的。
    ///
    /// **歸因**：實際擋下它的是環的檢查（`reaches` 含自身），不是那行專門的自我
    /// 父權 guard——mutation 實測拿掉那行本條仍綠。那行是 defence-in-depth，
    /// 釘的是「`reaches` 把自身算在內」這個前提。歸因寫錯會讓日後改 `reaches`
    /// 的人以為這條還罩得住。
    func testSelfParentIsNeverProposed() {
        let o = org("stat-sinica", names: ["統計科學研究所", "統計所"],
                    parents: [.literal("統計所")])
        XCTAssertTrue(OrgResolver.candidates(people: [], organizations: [o], rejected: []).isEmpty,
                      "自我父權不是歸戶")
    }

    /// `apply` 也擋一次自我父權——它是 public 且收任何清單（手工組的、跨資料變動
    /// 的舊清單）。不可逆寫入的防護不該只放在提名端。
    func testApplyRefusesSelfParentEvenIfHandCrafted() {
        let o = org("stat-sinica", names: ["統計所"], parents: [.literal("統計所")])
        let hand = OrgResolutionCandidate(holder: .organization("stat-sinica"),
                                          literal: "統計所", orgKey: "stat-sinica",
                                          reason: "手工組的")
        let out = OrgResolver.apply([hand], to: [], organizations: [o])
        XCTAssertEqual(out.organizations.first?.parents.entries.first?.value, .literal("統計所"),
                       "apply 端也要擋——提名端的排除不是唯一防線")
    }

    /// **環**：既有的 `.key` 邊 A→B，再讓 B 的 literal 指回 A 就成環。
    ///
    /// 本 repo 沒有任何地方偵測 org 階層的環，所以造出來就會安靜存在，直到某個
    /// 走 parents 的消費端無限迴圈。
    func testCycleThroughExistingKeyEdgeIsRefused() {
        let a = org("a", names: ["A org"], parents: [.key("b")])
        let b = org("b", names: ["B org"], parents: [.literal("A org")])
        XCTAssertTrue(OrgResolver.candidates(people: [], organizations: [a, b], rejected: []).isEmpty,
                      "a→b 已存在，再加 b→a 就成環")
    }

    /// **兩個候選各自無害、湊在一起成環**——只看既有邊會漏掉這個。
    func testCycleFormedByTwoCandidatesTogetherIsRefused() {
        let a = org("a", names: ["A org"], parents: [.literal("B org")])
        let b = org("b", names: ["B org"], parents: [.literal("A org")])
        let cands = OrgResolver.candidates(people: [], organizations: [a, b], rejected: [])
        XCTAssertEqual(cands.count, 1,
                       "第一個可接受、第二個會閉環必須排除（本輪已接受的也算既有邊）：\(cands)")
        XCTAssertEqual(cands.first?.holder, .organization("a"),
                       "以 holder 排序後依序處理——哪一個被排除必須是決定性的")
    }

    /// 合法的深層階層不得被誤擋——環的判定不是「有祖先關係就拒」。
    func testLegitimateDeepHierarchyIsAllowed() {
        let top = org("top", names: ["Top"])
        let mid = org("mid", names: ["Mid"], parents: [.key("top")])
        let leaf = org("leaf", names: ["Leaf"], parents: [.literal("Mid")])
        let cands = OrgResolver.candidates(people: [], organizations: [top, mid, leaf], rejected: [])
        XCTAssertEqual(cands.count, 1, "leaf→mid→top 是合法的三層，不是環：\(cands)")
        XCTAssertEqual(cands.first?.orgKey, "mid")
    }

    /// person 側的既有行為不得被改動——本 issue 是**缺口**不是回歸。
    func testPersonSideBehaviourIsUnchanged() {
        let o = org("stat-sinica", names: ["統計所"])
        let p = personWith("a", affiliations: [.literal("統計所")])
        let cands = OrgResolver.candidates(people: [p], organizations: [o], rejected: [])
        XCTAssertEqual(cands.count, 1)
        XCTAssertEqual(cands.first?.holder, .person("a"))
        XCTAssertEqual(cands.first?.reason, "org name 完全命中",
                       "person 側的理由字串不得改變——它出現在既有輸出裡")
    }

    /// person 與 org 候選並存時，**person 排在前**——既有輸出的順序不該因為多了
    /// 一類就亂掉。
    func testPersonCandidatesComeBeforeOrganisationOnes() {
        let parent = org("academia-sinica", names: ["中央研究院"])
        let child = org("stat-sinica", names: ["統計所"], parents: [.literal("中央研究院")])
        let p = personWith("zzz-last-alphabetically", affiliations: [.literal("統計所")])
        let cands = OrgResolver.candidates(people: [p], organizations: [parent, child], rejected: [])
        XCTAssertEqual(cands.count, 2)
        XCTAssertEqual(cands.first?.holder, .person("zzz-last-alphabetically"))
        XCTAssertEqual(cands.last?.holder, .organization("stat-sinica"))
    }

    /// #236 R4：**過濾不得把「2+ 命中」變成「唯一命中」。**
    ///
    /// R3 曾讓 guard 的判準（自我父權／成環）先過濾候選集再判唯一性，理由是好的：
    /// 不要拿結構上不可能的候選去煩人。但那把 `candidates()` 的語意從「2+ 命中就
    /// 交給人」改成「剩一個就自動提名」——而 `--apply` 會據此**寫入**。更糟的是
    /// 成環判準讀的 `edges` 正是同一個迴圈在改的，於是「要不要問人」取決於 org key
    /// 的字母順序。
    ///
    /// 本測試釘住回退後的語意：**同名的兩個 org 就是歧義，即使其中一個是 holder
    /// 自己**。報告多列一個明顯錯的候選，比安靜地改變寫入行為好。
    func testFilteringNeverTurnsAmbiguityIntoAutoProposal() {
        // 兩個 org 共用名字 "Shared"，其中一個就是 holder 自己
        var me = Organization(key: "org-me")
        me.names = TimelineOf([TemporalValue(value: "Shared", range: DateRange())])
        me.parents = TimelineOf([TemporalValue(value: OrgRef.literal("Shared"), range: DateRange())])
        var other = Organization(key: "org-other")
        other.names = TimelineOf([TemporalValue(value: "Shared", range: DateRange())])

        let r = OrgResolver.resolve(people: [], organizations: [me, other], rejected: [])
        XCTAssertEqual(r.candidates.map(\.orgKey), [],
                       "2+ 命中就**不提名**——過濾掉一個之後自動提名剩下的，"
                       + "等於在一個「讓歧義被看見」的改動裡偷改了寫入語意")
        XCTAssertEqual(r.ambiguities.count, 1, "它是歧義，要被看見")
        XCTAssertEqual(r.ambiguities.first?.orgKeys, ["org-me", "org-other"],
                       "列出原始命中集。holder 自己在裡面是刺眼但誠實的——"
                       + "而且 207/208 兩道 guard 仍會擋住真的被套用的情形")
    }

    /// 順序無關性：同一份邏輯 store，**換 key 名字不得改變「要不要問人」**。
    ///
    /// parents 迴圈是 `organizations.sorted(by: key)`，所以處理順序由 key 的字母序
    /// 決定。R3 的過濾器裡有 `reaches`，它讀的 `edges` 正是這個迴圈在累積的——
    /// 環偵測需要那個累積（`209` 行「本輪已接受的也算數」是刻意的），但拿它決定
    /// **歧義與否**，就把非決定性洩進了使用者看到的東西。
    ///
    /// fixture 必須讓「先處理誰」真的改變 `edges`，否則這條測試在舊程式碼上也會綠
    /// （第一版就是這樣——差點成為本 PR 的第四個空洞守衛）：
    ///
    /// - `child` 的 parent literal 是 `"L"`，而 `"L"` 同時命中 `linker` 與 `third`
    /// - `linker` 的 parent literal 唯一命中 `child` → 一旦 linker 先被處理，
    ///   `edges[linker] ∋ child`，於是 `reaches(linker, child)` 成立、linker 變成
    ///   不可容許 → 過濾後只剩 third → **自動提名**
    /// - 反之若 child 先被處理，`edges` 還是空的 → 兩個都可容許 → **歧義**
    func testAmbiguityVerdictDoesNotDependOnOrgKeyOrdering() {
        func run(child: String, linker: String) -> (amb: Int, cands: [String]) {
            let c = org(child, names: ["ChildName"], parents: [.literal("L")])
            let l = org(linker, names: ["L"], parents: [.literal("ChildName")])
            let t = org("third-org", names: ["L"])
            let r = OrgResolver.resolve(people: [], organizations: [c, l, t], rejected: [])
            // 比**角色**不比字面 key——兩次跑刻意用不同 key 名，直接比字串必不相等
            let role = [child: "child", linker: "linker", "third-org": "third"]
            return (r.ambiguities.count, r.candidates.map { role[$0.orgKey] ?? $0.orgKey }.sorted())
        }
        // 邏輯結構完全相同，只有 key 的字母序讓處理順序相反
        let childFirst = run(child: "a-child", linker: "b-linker")
        let linkerFirst = run(child: "z-child", linker: "a-linker")
        XCTAssertEqual(childFirst.amb, linkerFirst.amb,
                       "換個 key 名字就從『需要人判斷』變成『自動提名』——"
                       + "child 先: \(childFirst)，linker 先: \(linkerFirst)")
        XCTAssertEqual(childFirst.cands, linkerFirst.cands, "提名結果也必須一致")
        XCTAssertEqual(childFirst.amb, 1, "「L」對到兩個 org，兩種順序都該是歧義")
    }

    /// #236 R3：`latestPastSegment` 不得用 `entries.max()`。
    ///
    /// `DateRange.<` 是**相等性用的全序**，其中 `nil` start **排最後**——`.max()`
    /// 回傳的是「起點未知」那段，不是最近的一段。五條 finding 命中這個誤用。
    func testMostRecentlyEndedIsNotTheComparatorMax() {
        let tl = TimelineOf([
            TemporalValue(value: "old", range: DateRange(start: "1990", end: "1995")),
            TemporalValue(value: "recent", range: DateRange(start: "2010", end: "2015")),
            TemporalValue(value: "undated", range: DateRange()),      // nil start → `.max()` 取它
        ])
        XCTAssertEqual(tl.entries.max()?.value, "undated",
                       "前提：`.max()` 走相等性全序，nil start 排最後")
        XCTAssertEqual(tl.latestPastSegment?.value, "recent",
                       "**近時判準**要取真正最近結束的那段，不是無日期那段")
    }

    /// #236 R4：`current` 犯的是與 `latestPastSegment` **一模一樣**的 `.max()` 誤用，
    /// 而 R3 只修了 fallback 那一支。
    ///
    /// `.max()` 走 `DateRange.<`，`nil` start 排最後 → 起點未知的段贏過 `start:2020`
    /// 的段。後果：一個只有無日期隸屬的人被報成有「現職」，而那個現職是按**值的
    /// 字母序**選出來的——一個沒有根據的答案，卻長得像事實。
    func testCurrentPrefersKnownStartOverUnknown() {
        let tl = TimelineOf([
            TemporalValue(value: "aaa-undated", range: DateRange()),          // 無 start，仍 open
            TemporalValue(value: "zzz-since-2020", range: DateRange(start: "2020")),
        ])
        XCTAssertEqual(tl.entries.filter(\.range.isOpen).max()?.value, "aaa-undated",
                       "前提：`.max()` 讓 nil start 勝出（且字母序決勝）")
        XCTAssertEqual(tl.current?.value, "zzz-since-2020",
                       "起點未知不能宣稱較晚——doc 寫的是「取 start 最晚的」")
    }

    /// #236 R4：**觀測點不是結束**。第一版把 `end`／`start`／`attested` 塞進同一個
    /// 字串比大小，於是「2020 年被看到過」蓋掉「2010 年確實離開」——把「被看到」
    /// 誤當成「離開了」。
    func testEndedSegmentOutranksLaterAttestedObservation() {
        let tl = TimelineOf([
            TemporalValue(value: "really-ended", range: DateRange(start: "2005", end: "2010")),
            TemporalValue(value: "only-observed", range: DateRange(attested: ["2020"])),
        ])
        XCTAssertEqual(tl.latestPastSegment?.value, "really-ended",
                       "第 1 層存在時第 3 層不參與——後者根本沒宣稱結束")
    }

    /// #236 R4 回歸：只有 `endedUnknown`（#63：已結束、時點未知）的段被**整個丟掉**，
    /// 因為第一版的 `recencyKey` 對它回 `nil`、被 `compactMap` 濾除。
    ///
    /// 後果不是少印一行，是 CLI 印出**假話**：43 位退休 PI 會得到
    /// 「⚠ 無任何區辨欄位」，而 store 裡明明記著他們的隸屬。
    func testEndedUnknownWithNoDatesIsStillReturned() {
        var r = DateRange()
        r.endedUnknown = true
        let tl = TimelineOf([TemporalValue(value: "retired-pi-affiliation", range: r)])
        XCTAssertEqual(tl.latestPastSegment?.value, "retired-pi-affiliation",
                       "已結束但時點未知＝有隸屬資訊，不是沒有")
    }

    /// 層內同分要**穩定**。先前靠 `max` 的未定行為決勝，兩個 `==` 相等的時間軸
    /// 會報出不同的隸屬（R4 MEDIUM）。這裡只要求可重現，不宣稱哪一段「較近」。
    func testTiesAreResolvedDeterministically() {
        let mk = { TimelineOf([
            TemporalValue(value: "a", range: DateRange(start: "2000", end: "2010")),
            TemporalValue(value: "b", range: DateRange(start: "2001", end: "2010")),
        ]) }
        let first = mk().latestPastSegment?.value
        XCTAssertNotNil(first)
        for _ in 0..<20 {
            XCTAssertEqual(mk().latestPastSegment?.value, first, "同一輸入必須每次同答案")
        }
    }
}
