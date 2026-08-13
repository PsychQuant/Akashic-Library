import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// #232 task 2.x：ResolutionLedger——verdict 讀寫的**唯一**封裝點（design D4）。
/// value 編碼（D2）、rule 尾註（D3）、三態計數（derived, never stored）。
final class ResolutionLedgerTests: XCTestCase {

    // MARK: - task 2.1：record／verdicts 對稱、怪 literal round-trip、malformed loud

    func testRecordEncodesFieldValueAndRuleTail() throws {
        let ref = ResolutionLedger.record(
            .rejected, holder: "cheng2025alpha", literal: "Cheng, C.",
            rule: "author-name-exact", statement: "查過本人網頁，非本人")
        XCTAssertEqual(ref.field, "resolution-rejected")
        XCTAssertEqual(ref.value, "cheng2025alpha :: Cheng, C.")
        guard case .judgement(let statement, let restsOn) = ref.kind else {
            return XCTFail("verdict 必須是 judgement 型")
        }
        XCTAssertTrue(statement.hasSuffix("[rule: author-name-exact]"), statement)
        XCTAssertTrue(restsOn.isEmpty)
    }

    func testVerdictsParseIsInverseOfRecord() throws {
        let refs = [
            ResolutionLedger.record(.confirmed, holder: "a2020x", literal: "Wang, X.",
                                    rule: "author-name-exact", statement: "apply 確認"),
            ResolutionLedger.record(.rejected, holder: "b2021y", literal: "Chen, H-Y.",
                                    rule: "author-name-exact", statement: "查過，不是"),
        ]
        let parsed = ResolutionLedger.verdicts(references: refs)
        XCTAssertTrue(parsed.malformed.isEmpty, "\(parsed.malformed)")
        XCTAssertEqual(parsed.verdicts.count, 2)
        XCTAssertEqual(parsed.verdicts[0].kind, .confirmed)
        XCTAssertEqual(parsed.verdicts[0].holder, "a2020x")
        XCTAssertEqual(parsed.verdicts[0].literal, "Wang, X.")
        XCTAssertEqual(parsed.verdicts[0].rule, "author-name-exact")
        XCTAssertEqual(parsed.verdicts[1].kind, .rejected)
    }

    /// literal 含空白、冒號、甚至「 : 」——只有第一個 ` :: ` 是分隔符。
    func testWeirdLiteralRoundTrips() throws {
        let weird = "von Neumann, J. : Jr.  ::  extra"
        let ref = ResolutionLedger.record(.rejected, holder: "n1955z", literal: weird,
                                          rule: "author-name-exact", statement: "x")
        let parsed = ResolutionLedger.verdicts(references: [ref])
        XCTAssertEqual(parsed.verdicts.first?.literal, weird,
                       "分隔以第一個 ` :: ` 為準，literal 其餘內容原樣保留")
        XCTAssertEqual(parsed.verdicts.first?.holder, "n1955z")
    }

    /// rule 尾註缺席 → tolerant 計入 author-name-exact（今日唯一合法值）。
    func testMissingRuleTailDefaultsToAuthorNameExact() throws {
        let ref = ProvenanceReference(
            field: "resolution-rejected", value: "c2019q :: Liu, B.",
            kind: .judgement(statement: "手寫判定，沒帶尾註", restsOn: []))
        let parsed = ResolutionLedger.verdicts(references: [ref])
        XCTAssertEqual(parsed.verdicts.first?.rule, "author-name-exact")
    }

    /// malformed（value 缺分隔符）loud 回報，不靜默丟。
    func testMalformedValueIsReportedNotSilentlyDropped() throws {
        let bad = ProvenanceReference(
            field: "resolution-rejected", value: "no-separator-here",
            kind: .judgement(statement: "x", restsOn: []))
        let parsed = ResolutionLedger.verdicts(references: [bad])
        XCTAssertTrue(parsed.verdicts.isEmpty)
        XCTAssertEqual(parsed.malformed.count, 1)
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

    // MARK: - task 2.2：rejectedPairings + counts（derived；三態；rejected ≠ absence）

    private func person(_ key: String, refs: [ProvenanceReference] = []) -> Person {
        var p = Person(key: key, names: ["N"])
        p.references = refs
        return p
    }

    func testRejectedPairingsComeFromReferences() throws {
        let p = person("che-cheng", refs: [
            ResolutionLedger.record(.rejected, holder: "cheng2025alpha", literal: "Cheng, C.",
                                    rule: "author-name-exact", statement: "非本人"),
            ResolutionLedger.record(.confirmed, holder: "cheng2024beta", literal: "Cheng, C.",
                                    rule: "author-name-exact", statement: "本人"),
        ])
        let rejected = ResolutionLedger.rejectedPairings(people: [p])
        XCTAssertEqual(rejected, [ResolutionPairing(holder: "cheng2025alpha",
                                                    literal: "Cheng, C.",
                                                    judgedKey: "che-cheng")])
    }

    /// 三態：rejected 配對（有 verdict）≠ pending 配對（無 verdict）——不可折疊。
    func testCountsDistinguishRejectedFromPending() throws {
        let p = person("che-cheng", refs: [
            ResolutionLedger.record(.confirmed, holder: "a1", literal: "L",
                                    rule: "author-name-exact", statement: "s"),
            ResolutionLedger.record(.rejected, holder: "a2", literal: "L",
                                    rule: "author-name-exact", statement: "s"),
        ])
        // 現有候選：a2（已否決——不 pending）、a3（無 verdict——pending）
        let candidates = [
            ResolutionPairing(holder: "a2", literal: "L", judgedKey: "che-cheng"),
            ResolutionPairing(holder: "a3", literal: "L", judgedKey: "che-cheng"),
        ]
        let c = ResolutionLedger.counts(people: [p], candidatePairings: candidates)
        let rule = c["author-name-exact"]
        XCTAssertEqual(rule?.confirmed, 1)
        XCTAssertEqual(rule?.rejected, 1)
        XCTAssertEqual(rule?.pending, 1, "pending 只算無 verdict 的候選")
    }

    // MARK: - task 3.1/3.2：resolver 跳過（design D5——恰跳同配對）

    func testRejectedPairingIsNotReproposed() throws {
        let e1 = Entry(id: UUID(), citekey: "a2020x", type: "article",
                       title: "T", authors: [.literal("Cheng, C.")], date: "2020")
        let p = person("che-cheng")
        var pNamed = p; pNamed.names = ["Cheng, C."]
        let rejected: Set<ResolutionPairing> = [
            ResolutionPairing(holder: "a2020x", literal: "Cheng, C.", judgedKey: "che-cheng")
        ]
        let report = PersonResolver.resolve(entries: [e1], people: [pNamed],
                                            rejected: rejected)
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
            ResolutionPairing(holder: "a2020x", literal: "Cheng, C.", judgedKey: "che-cheng")
        ]
        let report = PersonResolver.resolve(entries: [e1, e2], people: [p],
                                            rejected: rejected)
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
            ResolutionPairing(holder: "che-cheng", literal: "統計科學研究所",
                              judgedKey: "stat-sinica")
        ]
        let report = OrgResolver.resolve(people: [holder], organizations: [org],
                                         rejected: rejected)
        XCTAssertTrue(report.candidates.isEmpty,
                      "org 族同語意：已否決配對不重提：\(report.candidates)")
        // 對照：不帶 rejected 時要提得出來（防假綠）
        let baseline = OrgResolver.resolve(people: [holder], organizations: [org])
        XCTAssertEqual(baseline.candidates.count, 1)
    }

    /// derived：加一筆 verdict 後重算即反映——沒有任何 stored counter 可以過期。
    func testCountsAreRecomputedNotStored() throws {
        var p = person("k")
        let before = ResolutionLedger.counts(people: [p], candidatePairings: [])
        XCTAssertNil(before["author-name-exact"])
        p.references.append(ResolutionLedger.record(
            .confirmed, holder: "x1", literal: "L", rule: "author-name-exact", statement: "s"))
        let after = ResolutionLedger.counts(people: [p], candidatePairings: [])
        XCTAssertEqual(after["author-name-exact"]?.confirmed, 1)
    }
}
