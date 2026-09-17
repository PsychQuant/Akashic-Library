import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #554 R28（R27 verify 第 8／18／26 列）：D78 把 `wouldContradictVerdicts` 的訊息在渲染前截（配對至多 5、每側至多 2、其餘計數），而四個既有
/// 測試只 `guard case`——把上限整段拿掉仍全綠。這裡直接對 `assertNoNewViolations` 斷言四件事，兄弟 case `wouldLeaveTwoConfirmedLiterals`
/// 自 R28 起同樣在擲出端截。
final class MergeRefusalCapTests: XCTestCase {
    private func verdict(_ field: String, work: String, literal: String) -> ProvenanceReference {
        ProvenanceReference(field: field,
                            value: ProvenanceReference.VerdictPairingValue(holderKind: .work, holder: work, literal: literal).encoded,
                            kind: .judgement(statement: "resolve apply", restsOn: []))
    }
    private func source(_ r: ProvenanceReference, record: String) -> LibraryStore.VerdictSource {
        LibraryStore.VerdictSource(record: record, kind: "venue", field: r.field, originalValue: r.value ?? "")
    }

    func testContradictionDetailsAreCappedBeforeRendering() throws {
        var after: [ProvenanceReference] = []
        for w in 0..<6 {
            for spelling in ["Lit", "LIT", "lit"] {
                after.append(verdict(ProvenanceReference.resolutionConfirmedField, work: "w\(w)", literal: spelling))
                after.append(verdict("resolution-rejected", work: "w\(w)", literal: spelling))
            }
        }
        let sources = after.map { source($0, record: "doomed") }
        XCTAssertThrowsError(try LibraryStore.assertNoNewViolations(after: after, prior: after.map { _ in nil }, sources: sources,
                                                                    record: "keeper", survivor: "keeper", literalUniqueness: false)) { err in
            guard case DivergenceResolveError.wouldContradictVerdicts(_, _, let details, let totalPairs) = err else { return XCTFail("\(err)") }
            XCTAssertEqual(details.count, 5, "配對至多 5")
            XCTAssertEqual(totalPairs, 6)
            for d in details {
                XCTAssertEqual(d.components(separatedBy: " ↔ ").count, 4, "每側至多 2：\(d)")
                XCTAssertTrue(d.contains("（同一配對另有 2 筆略）"), d)
                XCTAssertEqual(d.components(separatedBy: "的 confirmed ").count - 1, 2, d)
                XCTAssertEqual(d.components(separatedBy: "的 rejected ").count - 1, 2, d)
            }
            let text = err.localizedDescription
            XCTAssertTrue(text.contains("…共 6 個配對"), text)
            XCTAssertTrue(text.contains("標「另有 N 筆略」的配對要開持有記錄的 YAML 找其餘幾筆"), "出路不得再說「各筆的出處如上」：\(text)")
            XCTAssertFalse(text.contains("各筆的出處如上"), text)
        }
    }

    func testTwoLiteralSourcesAreCappedBeforeRendering() throws {
        let after = (0..<7).map { verdict(ProvenanceReference.resolutionConfirmedField, work: "w2020a", literal: "Literal \($0)") }
        let sources = after.map { source($0, record: "doomed") }
        XCTAssertThrowsError(try LibraryStore.assertNoNewViolations(after: after, prior: after.map { _ in nil }, sources: sources,
                                                                    record: "keeper", survivor: "keeper", literalUniqueness: true)) { err in
            guard case DivergenceResolveError.wouldLeaveTwoConfirmedLiterals(_, _, let ck, let brought, let existing, let broughtTotal, let existingTotal) = err
            else { return XCTFail("\(err)") }
            XCTAssertEqual(ck, "w2020a")
            XCTAssertEqual(brought.count, 5); XCTAssertEqual(broughtTotal, 7)
            XCTAssertEqual(existing, []); XCTAssertEqual(existingTotal, 0)
            XCTAssertTrue(err.localizedDescription.contains("…共 7 筆"), err.localizedDescription)
        }
    }
}
