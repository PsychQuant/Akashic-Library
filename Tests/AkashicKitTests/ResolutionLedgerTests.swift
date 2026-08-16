import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// #232 task 2.x + verify 修訂：ResolutionLedger——verdict 讀寫的**唯一**封裝點
/// （design D4）。value 文法 `<kind>:<key> :: <literal>`（verify DA：kind token
/// 必填、兩族統一）、rule 尾註（D3）、三態計數（derived, never stored）。
final class ResolutionLedgerTests: XCTestCase {

    // MARK: - task 2.1：record／verdicts 對稱、怪 literal round-trip、malformed loud

    func testRecordEncodesFieldValueAndRuleTail() throws {
        let ref = ResolutionLedger.record(
            .rejected, holderKind: .work, holder: "cheng2025alpha", literal: "Cheng, C.",
            rule: ResolutionLedger.personRule, statement: "查過本人網頁，非本人")
        XCTAssertEqual(ref.field, "resolution-rejected")
        XCTAssertEqual(ref.value, "work:cheng2025alpha :: Cheng, C.")
        guard case .judgement(let statement, let restsOn) = ref.kind else {
            return XCTFail("verdict 必須是 judgement 型")
        }
        XCTAssertTrue(statement.hasSuffix("[rule: author-name-exact]"), statement)
        XCTAssertTrue(restsOn.isEmpty)
    }

    func testVerdictsParseIsInverseOfRecord() throws {
        let refs = [
            ResolutionLedger.record(.confirmed, holderKind: .work, holder: "a2020x",
                                    literal: "Wang, X.",
                                    rule: ResolutionLedger.personRule, statement: "apply 確認"),
            ResolutionLedger.record(.rejected, holderKind: .person, holder: "chen-h-y",
                                    literal: "統計科學研究所",
                                    rule: ResolutionLedger.orgRule, statement: "查過，不是"),
        ]
        let parsed = ResolutionLedger.verdicts(references: refs)
        XCTAssertTrue(parsed.malformed.isEmpty, "\(parsed.malformed)")
        XCTAssertEqual(parsed.verdicts.count, 2)
        XCTAssertEqual(parsed.verdicts[0].kind, .confirmed)
        XCTAssertEqual(parsed.verdicts[0].holderKind, .work)
        XCTAssertEqual(parsed.verdicts[0].holder, "a2020x")
        XCTAssertEqual(parsed.verdicts[0].literal, "Wang, X.")
        XCTAssertEqual(parsed.verdicts[0].rule, "author-name-exact")
        XCTAssertEqual(parsed.verdicts[1].kind, .rejected)
        XCTAssertEqual(parsed.verdicts[1].holderKind, .person)
        XCTAssertEqual(parsed.verdicts[1].rule, "org-name-exact")
    }

    /// literal 含空白、冒號、甚至 ` :: `——只有**第一個** ` :: ` 是分隔符。
    func testWeirdLiteralRoundTrips() throws {
        let weird = "von Neumann, J. : Jr.  ::  extra"
        let ref = ResolutionLedger.record(.rejected, holderKind: .work, holder: "n1955z",
                                          literal: weird,
                                          rule: ResolutionLedger.personRule, statement: "x")
        let parsed = ResolutionLedger.verdicts(references: [ref])
        XCTAssertEqual(parsed.verdicts.first?.literal, weird,
                       "分隔以第一個 ` :: ` 為準，literal 其餘內容原樣保留")
        XCTAssertEqual(parsed.verdicts.first?.holder, "n1955z")
        XCTAssertEqual(parsed.verdicts.first?.holderKind, .work)
    }

    /// rule 尾註缺席 → tolerant 依 **holderKind** 計入該族預設（族別在 value 裡，
    /// 不靠掛載脈絡推斷）。
    func testMissingRuleTailDefaultsByFamily() throws {
        let personSide = ProvenanceReference(
            field: "resolution-rejected", value: "work:c2019q :: Liu, B.",
            kind: .judgement(statement: "手寫判定，沒帶尾註", restsOn: []))
        let orgSide = ProvenanceReference(
            field: "resolution-rejected", value: "person:liu-b :: 統計所",
            kind: .judgement(statement: "手寫判定，沒帶尾註", restsOn: []))
        let parsed = ResolutionLedger.verdicts(references: [personSide, orgSide])
        XCTAssertEqual(parsed.verdicts.map(\.rule),
                       [ResolutionLedger.personRule, ResolutionLedger.orgRule])
    }

    /// malformed（缺分隔符／缺 kind token）loud 回報，不靜默丟。
    func testMalformedValueIsReportedNotSilentlyDropped() throws {
        let noSep = ProvenanceReference(
            field: "resolution-rejected", value: "no-separator-here",
            kind: .judgement(statement: "x", restsOn: []))
        let noKind = ProvenanceReference(
            field: "resolution-rejected", value: "cheng2025alpha :: Cheng, C.",
            kind: .judgement(statement: "x", restsOn: []))
        let parsed = ResolutionLedger.verdicts(references: [noSep, noKind])
        XCTAssertTrue(parsed.verdicts.isEmpty)
        XCTAssertEqual(parsed.malformed.count, 2, "\(parsed.malformed)")
        XCTAssertTrue(parsed.malformed[0].contains("no-separator-here"), parsed.malformed[0])
    }

    /// 非 verdict 欄位的 references 完全不進 ledger（不算 verdict 也不算 malformed）。
    func testNonVerdictReferencesAreIgnored() throws {
        let other = ProvenanceReference(
            field: "orcid",
            kind: .retrieval(url: "https://example.org", retrieved: "2026-08-13",
                             status: 200, mediaType: nil,
                             content: "sha256:" + String(repeating: "ab", count: 32)))
        let parsed = ResolutionLedger.verdicts(references: [other])
        XCTAssertTrue(parsed.verdicts.isEmpty)
        XCTAssertTrue(parsed.malformed.isEmpty)
    }

    /// 寫入邊界冪等（verify F/S-6）：同 (field, value) 不重複附加。
    func testAppendIfAbsentIsIdempotent() throws {
        var refs: [ProvenanceReference] = []
        let ref = ResolutionLedger.record(.rejected, holderKind: .work, holder: "a1",
                                          literal: "L", rule: ResolutionLedger.personRule,
                                          statement: "s")
        XCTAssertTrue(ResolutionLedger.appendIfAbsent(ref, to: &refs))
        XCTAssertFalse(ResolutionLedger.appendIfAbsent(ref, to: &refs))
        XCTAssertEqual(refs.count, 1, "store 永不持有重複 verdict")
        // 相同配對、不同 kind 是兩筆（改變心意的歷史要留）
        let confirm = ResolutionLedger.record(.confirmed, holderKind: .work, holder: "a1",
                                              literal: "L", rule: ResolutionLedger.personRule,
                                              statement: "s")
        XCTAssertTrue(ResolutionLedger.appendIfAbsent(confirm, to: &refs))
        XCTAssertEqual(refs.count, 2)
    }

    // MARK: - task 2.2：rejectedPairings + counts（derived；三態；rejected ≠ absence）

    private func person(_ key: String, refs: [ProvenanceReference] = []) -> Person {
        var p = Person(key: key, names: ["N"])
        p.references = refs
        return p
    }

    /// R1-fix B2：verdict rule 由 tier 導出——寬鬆 tier 的校準史與 exact 分開計。
    func testPersonRuleForTierIsClosedMapping() throws {
        XCTAssertEqual(ResolutionLedger.personRule(for: .exact), "author-name-exact")
        XCTAssertEqual(ResolutionLedger.personRule(for: .confirmedElsewhere),
                       "author-name-confirmed-elsewhere")
        XCTAssertEqual(ResolutionLedger.personRule(for: .reorder), "author-name-reorder")
        XCTAssertEqual(ResolutionLedger.personRule(for: .initials), "author-name-initials")
        // 封閉四值全覆蓋（新 tier 忘了配 rule 會在這裡紅）
        for tier in ResolutionTier.allCases {
            XCTAssertFalse(ResolutionLedger.personRule(for: tier).isEmpty)
        }
    }

    func testPendingBucketsByPerCandidateRule() throws {
        let p = person("che-cheng")
        let exact = ResolutionPairing(holderKind: .work, holder: "a1",
                                      literal: "Che Cheng", judgedKey: "che-cheng")
        let loose = ResolutionPairing(holderKind: .work, holder: "b2",
                                      literal: "C. Cheng", judgedKey: "che-cheng")
        let c = ResolutionLedger.counts(people: [p], candidates: [
            (pairing: exact, rule: ResolutionLedger.personRule(for: .exact)),
            (pairing: loose, rule: ResolutionLedger.personRule(for: .initials)),
        ])
        XCTAssertEqual(c["author-name-exact"]?.pending, 1)
        XCTAssertEqual(c["author-name-initials"]?.pending, 1,
                       "initials 的 pending 不得混進 exact 的校準史")
    }

    /// #303 design D3：confirmed 側的鏡像——與 rejected 對稱、互不相含。
    func testConfirmedPairingsMirrorRejectedSide() throws {
        let p = person("che-cheng", refs: [
            ResolutionLedger.record(.rejected, holderKind: .work, holder: "cheng2025alpha",
                                    literal: "Cheng, C.",
                                    rule: ResolutionLedger.personRule, statement: "非本人"),
            ResolutionLedger.record(.confirmed, holderKind: .work, holder: "cheng2024beta",
                                    literal: "Cheng, C.",
                                    rule: ResolutionLedger.personRule, statement: "本人"),
        ])
        let confirmed = ResolutionLedger.confirmedPairings(people: [p])
        XCTAssertEqual(confirmed, [ResolutionPairing(holderKind: .work,
                                                     holder: "cheng2024beta",
                                                     literal: "Cheng, C.",
                                                     judgedKey: "che-cheng")])
        // 對稱且互斥：同一份 refs，兩側各取各的 kind，無交集
        XCTAssertTrue(confirmed.isDisjoint(with:
            ResolutionLedger.rejectedPairings(people: [p])))
    }

    func testRejectedPairingsComeFromReferences() throws {
        let p = person("che-cheng", refs: [
            ResolutionLedger.record(.rejected, holderKind: .work, holder: "cheng2025alpha",
                                    literal: "Cheng, C.",
                                    rule: ResolutionLedger.personRule, statement: "非本人"),
            ResolutionLedger.record(.confirmed, holderKind: .work, holder: "cheng2024beta",
                                    literal: "Cheng, C.",
                                    rule: ResolutionLedger.personRule, statement: "本人"),
        ])
        let rejected = ResolutionLedger.rejectedPairings(people: [p])
        XCTAssertEqual(rejected, [ResolutionPairing(holderKind: .work,
                                                    holder: "cheng2025alpha",
                                                    literal: "Cheng, C.",
                                                    judgedKey: "che-cheng")])
    }

    /// 三態：rejected 配對（有 verdict）≠ pending 配對（無 verdict）——不可折疊。
    func testCountsDistinguishRejectedFromPending() throws {
        let p = person("che-cheng", refs: [
            ResolutionLedger.record(.confirmed, holderKind: .work, holder: "a1", literal: "L",
                                    rule: ResolutionLedger.personRule, statement: "s"),
            ResolutionLedger.record(.rejected, holderKind: .work, holder: "a2", literal: "L",
                                    rule: ResolutionLedger.personRule, statement: "s"),
        ])
        // 現有候選：a2（已否決——不 pending）、a3（無 verdict——pending）
        let candidates = [
            ResolutionPairing(holderKind: .work, holder: "a2", literal: "L", judgedKey: "che-cheng"),
            ResolutionPairing(holderKind: .work, holder: "a3", literal: "L", judgedKey: "che-cheng"),
        ]
        let c = ResolutionLedger.counts(people: [p], candidates: candidates.map { ($0, ResolutionLedger.personRule) })
        let rule = c[ResolutionLedger.personRule]
        XCTAssertEqual(rule?.confirmed, 1)
        XCTAssertEqual(rule?.rejected, 1)
        XCTAssertEqual(rule?.pending, 1, "pending 只算無 verdict 的候選")
    }

    /// org 族的 pending 歸入 org-name-exact——兩族的校準歷史分開計（verify REG-7）。
    func testOrgCountsPendingAttributedToOrgRule() throws {
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "統計所", range: DateRange(start: "1987"))])
        let candidates = [ResolutionPairing(holderKind: .person, holder: "che-cheng",
                                            literal: "統計所", judgedKey: "stat-sinica")]
        let c = ResolutionLedger.counts(organizations: [org], candidatePairings: candidates)
        XCTAssertEqual(c[ResolutionLedger.orgRule]?.pending, 1)
        XCTAssertNil(c[ResolutionLedger.personRule])
    }

    // MARK: - task 3.1/3.2：resolver 跳過（design D5——恰跳同配對）

    func testRejectedPairingIsNotReproposed() throws {
        let e1 = Entry(id: UUID(), citekey: "a2020x", type: "article",
                       title: "T", authors: [.literal("Cheng, C.")], date: "2020")
        var p = person("che-cheng"); p.names = ["Cheng, C."]
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "a2020x",
                              literal: "Cheng, C.", judgedKey: "che-cheng")
        ]
        let report = PersonResolver.resolve(entries: [e1], people: [p], rejected: rejected, confirmed: [])
        XCTAssertTrue(report.candidates.isEmpty,
                      "已否決配對不得重新提名：\(report.candidates)")
    }

    func testRejectionDoesNotBanLiteralGlobally() throws {
        let e1 = Entry(id: UUID(), citekey: "a2020x", type: "article",
                       title: "T", authors: [.literal("Cheng, C.")], date: "2020")
        let e2 = Entry(id: UUID(), citekey: "b2021y", type: "article",
                       title: "U", authors: [.literal("Cheng, C.")], date: "2021")
        var p = person("che-cheng"); p.names = ["Cheng, C."]
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .work, holder: "a2020x",
                              literal: "Cheng, C.", judgedKey: "che-cheng")
        ]
        let report = PersonResolver.resolve(entries: [e1, e2], people: [p], rejected: rejected, confirmed: [])
        XCTAssertEqual(report.candidates.map(\.citekey), ["b2021y"],
                       "同 literal 在另一個 entry 是另一次觀察，照提")
    }

    func testOrgResolverSkipsRejectedPairing() throws {
        var holder = person("che-cheng")
        holder.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("統計科學研究所"), range: DateRange(start: "2022")),
        ])
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "統計科學研究所",
                                              range: DateRange(start: "1987"))])
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .person, holder: "che-cheng",
                              literal: "統計科學研究所", judgedKey: "stat-sinica")
        ]
        let report = OrgResolver.resolve(people: [holder], organizations: [org],
                                         rejected: rejected)
        XCTAssertTrue(report.candidates.isEmpty,
                      "org 族同語意：已否決配對不重提：\(report.candidates)")
        // 對照：不帶 rejected 時要提得出來（防假綠）
        let baseline = OrgResolver.resolve(people: [holder], organizations: [org], rejected: [])
        XCTAssertEqual(baseline.candidates.count, 1)
    }

    /// verify C-3／S-3：person 與 organization 的 key 可合法同名——kind token 讓
    /// 「否決 person 側配對」**不**連帶抑制同名 org 側配對。
    func testNamespaceCollisionDoesNotCrossSuppress() throws {
        var holder = person("iss")
        holder.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("Institute of Statistics"),
                          range: DateRange(start: "2020")),
        ])
        var holderOrg = Organization(key: "iss")
        holderOrg.names = TimelineOf([TemporalValue(value: "ISS 統計組",
                                                    range: DateRange(start: "1990"))])
        holderOrg.parents = TimelineOf([
            TemporalValue(value: .literal("Institute of Statistics"),
                          range: DateRange(start: "1990")),
        ])
        var target = Organization(key: "target-org")
        target.names = TimelineOf([TemporalValue(value: "Institute of Statistics",
                                                 range: DateRange(start: "1987"))])
        // 只否決 person 側配對
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holderKind: .person, holder: "iss",
                              literal: "Institute of Statistics", judgedKey: "target-org")
        ]
        let report = OrgResolver.resolve(people: [holder],
                                         organizations: [holderOrg, target],
                                         rejected: rejected)
        XCTAssertEqual(report.candidates.count, 1, "\(report.candidates)")
        if case .organization(let k) = report.candidates.first?.holder {
            XCTAssertEqual(k, "iss", "org 側（parents）配對不受 person 側否決影響")
        } else {
            XCTFail("剩下的候選應是 org 側 holder：\(report.candidates)")
        }
    }

    // MARK: - 沉底列（design D7）

    /// verify C-4：同 entry 同 literal 的每個作者位置各一列。
    func testObservedRejectionsListEveryMatchingAuthorIndex() throws {
        let e = Entry(id: UUID(), citekey: "dup2020", type: "article", title: "T",
                      authors: [.literal("Che Cheng"), .literal("Che Cheng")], date: "2020")
        let p = person("cheng-che", refs: [
            ResolutionLedger.record(.rejected, holderKind: .work, holder: "dup2020",
                                    literal: "Che Cheng",
                                    rule: ResolutionLedger.personRule, statement: "s"),
        ])
        let sunk = ResolutionLedger.observedRejections(people: [p], entries: [e])
        XCTAssertEqual(sunk.map(\.authorIndex), [0, 1],
                       "一筆否決抑制同 entry 的兩個位置，兩個位置都要看得到")
        XCTAssertEqual(sunk.first?.rule, ResolutionLedger.personRule)
    }

    /// stale 否決（literal 已從 entry 移除）不列——ledger 仍記得、計數照算。
    func testStaleRejectionIsNotObserved() throws {
        let e = Entry(id: UUID(), citekey: "a2020x", type: "article", title: "T",
                      authors: [.literal("Someone Else")], date: "2020")
        let p = person("cheng-che", refs: [
            ResolutionLedger.record(.rejected, holderKind: .work, holder: "a2020x",
                                    literal: "Che Cheng",
                                    rule: ResolutionLedger.personRule, statement: "s"),
        ])
        XCTAssertTrue(ResolutionLedger.observedRejections(people: [p], entries: [e]).isEmpty)
        let counts = ResolutionLedger.counts(people: [p], candidates: [])
        XCTAssertEqual(counts[ResolutionLedger.personRule]?.rejected, 1, "計數照算歷史")
    }

    /// verify C-3：org 沉底列的 holder kind 來自 value 的 kind token——同名
    /// person/org 各自的否決各自成列，不再「先猜 person」。
    func testOrgObservedRejectionsKeepKindsSeparate() throws {
        var holder = person("iss")
        holder.profile.affiliations = TimelineOf([
            TemporalValue(value: .literal("Acme"), range: DateRange(start: "2020")),
        ])
        var holderOrg = Organization(key: "iss")
        holderOrg.names = TimelineOf([TemporalValue(value: "ISS", range: DateRange(start: "1990"))])
        holderOrg.parents = TimelineOf([
            TemporalValue(value: .literal("Acme"), range: DateRange(start: "1990")),
        ])
        var target = Organization(key: "acme-corp")
        target.names = TimelineOf([TemporalValue(value: "Acme", range: DateRange(start: "1980"))])
        target.references = [
            ResolutionLedger.record(.rejected, holderKind: .person, holder: "iss",
                                    literal: "Acme", rule: ResolutionLedger.orgRule,
                                    statement: "s"),
            ResolutionLedger.record(.rejected, holderKind: .org, holder: "iss",
                                    literal: "Acme", rule: ResolutionLedger.orgRule,
                                    statement: "s"),
        ]
        let sunk = ResolutionLedger.observedRejections(organizations: [holderOrg, target],
                                                       people: [holder])
        XCTAssertEqual(sunk.count, 2, "\(sunk)")
        XCTAssertEqual(sunk.map(\.holderKind), [.org, .person], "兩個 kind 各自成列")
    }

    /// 全庫 malformed 彙整（呈現面消費——丟棄必須可見）。
    func testMalformedVerdictsAggregatesAcrossRecords() throws {
        let p = person("k", refs: [
            ProvenanceReference(field: "resolution-rejected", value: "no-separator",
                                kind: .judgement(statement: "x", restsOn: [])),
        ])
        let out = ResolutionLedger.malformedVerdicts(people: [p])
        XCTAssertEqual(out.count, 1)
        XCTAssertTrue(out[0].contains("person k"), out[0])
    }

    /// derived：加一筆 verdict 後重算即反映——沒有任何 stored counter 可以過期。
    func testCountsAreRecomputedNotStored() throws {
        var p = person("k")
        let before = ResolutionLedger.counts(people: [p], candidates: [])
        XCTAssertNil(before[ResolutionLedger.personRule])
        p.references.append(ResolutionLedger.record(
            .confirmed, holderKind: .work, holder: "x1", literal: "L",
            rule: ResolutionLedger.personRule, statement: "s"))
        let after = ResolutionLedger.counts(people: [p], candidates: [])
        XCTAssertEqual(after[ResolutionLedger.personRule]?.confirmed, 1)
    }
}
