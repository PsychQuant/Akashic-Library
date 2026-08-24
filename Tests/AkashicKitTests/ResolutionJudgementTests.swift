import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// #232：消解判定的載體——verdict 欄位封閉對（resolution-confirmed／resolution-rejected）
/// 的驗證規則與 round-trip。spec：resolution-judgement + provenance-reference（修改）。
final class ResolutionJudgementTests: XCTestCase {

    private let digestA = "sha256:" + String(repeating: "ab", count: 32)

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    private func verdictRef(_ field: String, value: String? = "work:cheng2025alpha :: Cheng, C.",
                            restsOn: [String] = []) -> ProvenanceReference {
        ProvenanceReference(field: field, value: value,
                            kind: .judgement(statement: "查過本人網頁，判定 [rule: author-name-exact]",
                                             restsOn: restsOn))
    }

    // MARK: - task 1.1：verdict 欄位對合法、value 必填、封閉性不鬆動

    func testVerdictFieldsAcceptedWithValue() throws {
        var p = Person(key: "che-cheng", names: ["Cheng, Che"])
        p.references = [verdictRef("resolution-confirmed"), verdictRef("resolution-rejected")]
        XCTAssertNoThrow(try p.validateReferenceAttachment())

        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "統計所", range: DateRange(start: "1987"))])
        org.references = [verdictRef("resolution-confirmed", value: "person:che-cheng :: 統計科學研究所"),
                          verdictRef("resolution-rejected", value: "person:che-cheng :: 統計科學研究所")]
        XCTAssertNoThrow(try org.validateReferenceAttachment())
    }

    func testVerdictFieldWithoutValueRejected() {
        var p = Person(key: "che-cheng", names: ["Cheng, Che"])
        p.references = [verdictRef("resolution-rejected", value: nil)]
        XCTAssertThrowsError(try p.validateReferenceAttachment(),
                             "verdict 沒有配對（value）即無錨，必須拒收") { e in
            XCTAssertTrue(message(e).contains("resolution-rejected"), message(e))
        }
        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "統計所", range: DateRange(start: "1987"))])
        org.references = [verdictRef("resolution-confirmed", value: nil)]
        XCTAssertThrowsError(try org.validateReferenceAttachment()) { e in
            XCTAssertTrue(message(e).contains("resolution-confirmed"), message(e))
        }
    }

    /// 封閉性：verdict 例外只有兩值，其他不存在的欄位照拒（不得類推第三個）。
    func testNonVerdictAbsentFieldStillRejected() {
        var p = Person(key: "che-cheng", names: ["Cheng, Che"])
        p.references = [verdictRef("resolution-maybe")]
        XCTAssertThrowsError(try p.validateReferenceAttachment()) { e in
            XCTAssertTrue(message(e).contains("resolution-maybe"), message(e))
        }
    }

    // MARK: - task 1.1（design D8）：verdict 允許空 restsOn；非 verdict 維持拒收

    func testVerdictEmptyRestsOnAcceptedAtDecode() throws {
        var p = Person(key: "che-cheng", names: ["Cheng, Che"])
        p.references = [verdictRef("resolution-rejected")]
        let yaml = try PersonYAML.encode(p)
        XCTAssertNoThrow(try PersonYAML.decode(yaml),
                         "verdict 空 restsOn 必須可載入（裁決本身即一階證據）")
    }

    func testNonVerdictEmptyRestsOnStillRejectedAtDecode() {
        var p = Person(key: "che-cheng", names: ["Cheng, Che"])
        p.orcid = ORCID("0000-0002-1825-0097")
        p.references = [ProvenanceReference(field: "orcid",
                                            kind: .judgement(statement: "推理", restsOn: []))]
        // 驗證住 throwing init（encode round-check 也會過它）——encode 或 decode
        // 哪端先拋都算：例外不外溢是唯一斷言
        XCTAssertThrowsError(try PersonYAML.decode(try PersonYAML.encode(p)),
                             "非 verdict 欄位的空 restsOn 維持拒收——例外不外溢") { e in
            XCTAssertTrue(message(e).contains("rests-on"), message(e))
        }
    }

    // MARK: - task 1.2：round-trip 位元組穩定、format 標記不變

    func testVerdictReferencesRoundTripByteStable() throws {
        var p = Person(key: "che-cheng", names: ["Cheng, Che"])
        p.references = [verdictRef("resolution-confirmed"),
                        verdictRef("resolution-rejected", restsOn: [digestA])]
        let encoded = try PersonYAML.encode(p)
        let decoded = try PersonYAML.decode(encoded)
        XCTAssertEqual(try PersonYAML.encode(decoded), encoded, "encode→decode→encode 位元組冪等")

        var org = Organization(key: "stat-sinica")
        org.names = TimelineOf([TemporalValue(value: "統計所", range: DateRange(start: "1987"))])
        org.references = [verdictRef("resolution-rejected", value: "person:x-person :: 統計所籌備處")]
        let e2 = try OrganizationYAML.encode(org)
        XCTAssertEqual(try OrganizationYAML.encode(try OrganizationYAML.decode(e2)), e2)
    }
}
