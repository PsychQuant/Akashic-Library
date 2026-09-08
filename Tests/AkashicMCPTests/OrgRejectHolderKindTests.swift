import XCTest
@testable import AkashicCore
@testable import AkashicEntity

/// `OrgResolutionCandidate.Holder` → verdict 的 kind 只有一份定義（#483）。
///
/// 兩個呼叫端（`resolve_organizations` 的 apply 與 reject）先前各自推導：apply 用窮盡
/// switch（#378），reject 用 `{ if case .person … else .org }`——於是一個 `.work` 候選
/// 被否決時寫出 `org:<citekey>`，而那條 verdict 在 #464 的死 verdict 掃描下**必然**變成
/// 死的（沒有任何 organization 叫那個 citekey），訊息還會把成因說成「遷移漏了這一格」。
///
/// 寫入面的 bug 偽裝成遷移面的缺口——修錯地方的成本比缺口本身高。
final class OrgRejectHolderKindTests: XCTestCase {

    func testEveryHolderCaseMapsToItsOwnKind() {
        XCTAssertEqual(OrgResolutionCandidate.Holder.person("p").verdictHolderKind, .person)
        XCTAssertEqual(OrgResolutionCandidate.Holder.organization("o").verdictHolderKind, .org)
        XCTAssertEqual(
            OrgResolutionCandidate.Holder.work(citekey: "k2020a", authorIndex: 0).verdictHolderKind,
            .work,
            "`.work` 曾被靜默算成 `.org`——那條 verdict 指向一個不存在的 organization")
    }

    /// 寫出來的 value 真的帶 `work:`——只驗 enum 對映不夠，錯的是最終那個字串。
    func testWorkHolderWritesWorkPrefixedValue() throws {
        let h = OrgResolutionCandidate.Holder.work(citekey: "k2020a", authorIndex: 0)
        let ref = ResolutionLedger.record(.rejected, holderKind: h.verdictHolderKind,
                                          holder: h.key, literal: "Some Org",
                                          rule: ResolutionLedger.orgRule,
                                          statement: "測試用")
        let v = try XCTUnwrap(ref.value)
        XCTAssertTrue(v.hasPrefix("work:k2020a :: "), v)
        let parsed = try XCTUnwrap(ProvenanceReference.VerdictPairingValue.parse(v))
        XCTAssertEqual(parsed.holderKind, .work)
        XCTAssertEqual(parsed.holder, "k2020a")
    }

    /// **全樹不得再出現兩路推導**：`.person` 以外一律歸某一邊的那種寫法。
    func testNoTwoWayHolderKindDerivationRemains() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("Sources")
        var offenders: [String] = []
        var scanned = 0
        let e = FileManager.default.enumerator(atPath: root.path)!
        while let rel = e.nextObject() as? String {
            guard rel.hasSuffix(".swift") else { continue }
            let text = try String(contentsOf: root.appendingPathComponent(rel), encoding: .utf8)
            scanned += 1
            for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
                let code = line.contains("//") ? line[..<line.range(of: "//")!.lowerBound] : line[...]
                guard code.contains("if case .person"), code.contains("else") else { continue }
                offenders.append("\(rel)：\(code.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertGreaterThan(scanned, 50, "掃到的檔太少——掃描壞了，不是沒有違規")
        XCTAssertTrue(offenders.isEmpty,
                      "holder → kind 只能走 verdictHolderKind 的窮盡 switch（#483）：\n"
                      + offenders.joined(separator: "\n"))
    }
}
