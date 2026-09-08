import XCTest
@testable import AkashicCore
@testable import AkashicEntity
@testable import AkashicStoreIO

/// verdict 的相等只有一個定義（#470）。
///
/// 在此之前有兩個：寫入面（merge 的 `dedupKey`、rename 兩處 `seen`、`appendIfAbsent`）比
/// `value` 的**原字串**，讀取面（`PersonResolver` 的 `rejectedNorm`）比
/// `NameNormalization.matchingKey(literal)`。於是 `work:k :: Fann, C.` 與
/// `work:k :: Fann,  C.` 在寫入面是兩筆、讀取面是同一筆——「store 永不持有重複 verdict」
/// 在讀取面的意義上已經被違反，而兩面都不會出聲。
final class VerdictEqualityTests: XCTestCase {

    private func value(_ holder: String, _ literal: String,
                       kind: ProvenanceReference.VerdictHolderKind = .work) -> String {
        ProvenanceReference.VerdictPairingValue(
            holderKind: kind, holder: holder, literal: literal).encoded
    }
    private func key(_ field: String, _ v: String?) -> String {
        ProvenanceReference.verdictEqualityKey(field: field, value: v)
    }

    /// 只差空白／連字號家族／不可見格式字元的 literal 是**同一個** verdict。
    func testNormalisationCollapsesTheSamePairing() {
        let a = key("resolution-confirmed", value("k2020a", "Fann, C."))
        for variant in ["Fann,  C.", "Fann, C.\u{200B}", " Fann, C. ", "Fann,\tC."] {
            XCTAssertEqual(key("resolution-confirmed", value("k2020a", variant)), a,
                           "「\(variant)」應與「Fann, C.」同鍵")
        }
    }

    /// 但它**不得**把真的不同的東西塌在一起——holder、kind、field 三個維度各驗一次。
    func testDifferentPairingsStayDistinct() {
        let base = key("resolution-confirmed", value("k2020a", "Fann, C."))
        XCTAssertNotEqual(key("resolution-confirmed", value("k2020b", "Fann, C.")), base, "holder")
        XCTAssertNotEqual(key("resolution-confirmed", value("k2020a", "Fann, D.")), base, "literal")
        XCTAssertNotEqual(key("resolution-rejected", value("k2020a", "Fann, C.")), base, "field")
        XCTAssertNotEqual(key("resolution-confirmed", value("k2020a", "Fann, C.", kind: .person)),
                          base, "holderKind")
    }

    /// **非 verdict 欄位回退到原字串**——它們不在這條不變式的轄下，而正規化它們會擴大
    /// dedup 的作用面（`migratedVerdicts` 的既有立場：非 verdict 的 reference 原樣通過）。
    func testNonVerdictFieldsAreCompareByteWise() {
        XCTAssertNotEqual(key("affiliation", "Institute  of X"),
                          key("affiliation", "Institute of X"))
        // 文法不合的 verdict value 同樣回退——它到不了載入後的記錄，但縱深防禦要有定義
        XCTAssertNotEqual(key("resolution-confirmed", "not a pairing  value"),
                          key("resolution-confirmed", "not a pairing value"))
    }

    /// `appendIfAbsent` 用同一個定義——在此之前它比位元組，於是只差空白的重複判定寫得進去。
    func testAppendIfAbsentRefusesANormalisedDuplicate() {
        var refs: [ProvenanceReference] = []
        let first = ProvenanceReference(field: "resolution-rejected",
                                        value: value("k2020a", "Fann, C."),
                                        kind: .judgement(statement: "s", restsOn: []))
        XCTAssertTrue(ResolutionLedger.appendIfAbsent(first, to: &refs))
        let second = ProvenanceReference(field: "resolution-rejected",
                                         value: value("k2020a", "Fann,  C."),
                                         kind: .judgement(statement: "另一個理由", restsOn: []))
        XCTAssertFalse(ResolutionLedger.appendIfAbsent(second, to: &refs),
                       "只差空白的同一個配對不得寫進去")
        XCTAssertEqual(refs.count, 1)
        XCTAssertEqual(refs[0].value, value("k2020a", "Fann, C."),
                       "留首見，且**逐字**保留原字串——正規化只住在鍵裡，不外洩成資料")
    }

    /// 相等的定義只能有一份：全樹不得再出現 `<field>\u{0}<value>` 這種手寫的 verdict 鍵。
    ///
    /// **這條掃的是形狀不是名字**——把函式改名不會讓它失效，而複製一份實作會。
    func testNoHandRolledVerdictKeyRemains() throws {
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
                guard line.contains("\\u{0}"), line.contains(".value") else { continue }
                if line.contains("verdictEqualityKey") { continue }
                if rel.hasSuffix("Provenance.swift") { continue }   // 定義本身
                offenders.append("\(rel)：\(line.trimmingCharacters(in: .whitespaces))")
            }
        }
        XCTAssertGreaterThan(scanned, 50, "掃到的檔太少——掃描壞了，不是沒有違規")
        XCTAssertTrue(offenders.isEmpty,
                      "verdict 的相等鍵只能有一份定義（#470），這些是手寫的第二份：\n"
                      + offenders.joined(separator: "\n"))
    }
}
