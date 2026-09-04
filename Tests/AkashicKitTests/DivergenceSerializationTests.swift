import XCTest
import Foundation
@testable import AkashicCore

/// `divergence` 形狀的序列化正規性（#71）。
///
/// 新形狀的位元組形式必須從第一天就是正規的。理由不是潔癖：一旦同一份資料有兩種
/// 寫法，下次任何正規寫入碰到非正規的檔就會靜默重排，產生看起來像資料變更、實際
/// 只是排版的 diff——review 的人分不出來（見 Akashic-Library#69）。
final class DivergenceSerializationTests: XCTestCase {

    private func sample(judged: Bool) -> Divergence {
        Divergence(
            id: UUID(uuidString: "6577DE3B-DAFE-5CC0-A9DE-2E04030737B3")!,
            question: "是否為同一人",
            // 刻意以非排序順序建構——輸出必須與排序後建構的相同。
            candidates: [DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person),
                         DivergenceCandidate(key: "fann-cathy-s-j", shape: .person)],
            judgement: judged
                ? Judgement(statement: "兩者的姓與 given initials 一致",
                            restsOn: ["sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff", "sha256:0000000000000000000000000000000000000000000000000000000000000001"])
                : nil)
    }

    /// encode → decode → encode，兩次輸出位元組相同。
    func testRoundTripByteIdentical() throws {
        for judged in [false, true] {
            let first = try DivergenceYAML.encode(sample(judged: judged))
            let second = try DivergenceYAML.encode(try DivergenceYAML.decode(first))
            XCTAssertEqual(first, second, "judged=\(judged) 時位元組不穩定：\n\(first)\n---\n\(second)")
            XCTAssertTrue(first.hasPrefix("divergence:\n"), "應以裸標籤開頭：\n\(first)")
        }
    }

    /// 寫入順序不影響輸出——候選依 (shape, key) 排序，證據依字面排序。
    ///
    /// 這是「同一份資料只有一種位元組表示」的直接檢驗：同一組候選以相反順序建構，
    /// 兩者必須寫出相同的位元組。
    func testWriteOrderDoesNotAffectBytes() throws {
        let a = try DivergenceYAML.encode(sample(judged: true))
        let reversed = Divergence(
            id: UUID(uuidString: "6577DE3B-DAFE-5CC0-A9DE-2E04030737B3")!,
            question: "是否為同一人",
            candidates: [DivergenceCandidate(key: "fann-cathy-s-j", shape: .person),
                         DivergenceCandidate(key: "fann-cathy-s-j-2", shape: .person)],
            judgement: Judgement(statement: "兩者的姓與 given initials 一致",
                                 restsOn: ["sha256:0000000000000000000000000000000000000000000000000000000000000001", "sha256:ffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffffff"]))
        XCTAssertEqual(a, try DivergenceYAML.encode(reversed))
    }

    /// 本 binary 不認得的頂層區塊逐位元組保留（§5 tolerant-preserve）。
    ///
    /// 較新版本寫入的欄位不該因為經過一次舊 binary 就消失——那是不可逆的資料遺失，
    /// 而且是靜默的。
    func testUnknownFieldSurvives() throws {
        let input = """
        divergence:
        id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
        question: 是否為同一人
        candidates:
        - key: fann-cathy-s-j
          shape: person
        - key: fann-cathy-s-j-2
          shape: person
        confidence_note:
          scored_by: 後續版本
          value: 0.8

        """
        let out = try DivergenceYAML.encode(try DivergenceYAML.decode(input))
        XCTAssertTrue(out.contains("confidence_note:"), "未知區塊消失了：\n\(out)")
        XCTAssertTrue(out.contains("scored_by: 後續版本"), "未知區塊的子欄位消失了：\n\(out)")
        XCTAssertTrue(out.contains("value: 0.8"), "未知區塊的子欄位消失了：\n\(out)")
    }
}
