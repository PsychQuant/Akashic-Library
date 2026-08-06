import XCTest
import Yams
@testable import AkashicCore

/// #66：provenance reference——「路徑 + 內容」的雙半 provenance、欄位層附著、
/// 擷取型/判斷型互斥（D6）。
///
/// 測試逐項斷言**錯誤內容指名了出問題的欄位或值**（tasks 1.2 的驗證條款）——
/// 只斷言「有拋錯」不算通過：泛用錯誤讓修資料的人得逐欄猜。
final class ProvenanceTests: XCTestCase {

    private let digestA = "sha256:" + String(repeating: "ab", count: 32)
    private let digestB = "sha256:" + String(repeating: "cd", count: 32)

    private func message(_ error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? String(describing: error)
    }

    // MARK: - Failure mode 1：擷取型缺 content

    func testRetrievalWithoutContentIsRejectedNamingContent() {
        XCTAssertThrowsError(try ProvenanceReference(
            field: "orcid", value: nil,
            url: "https://example.org/x", retrieved: "2026-08-03", status: 200,
            mediaType: nil, content: nil, judgement: nil, restsOn: [])) { error in
            XCTAssertTrue(message(error).contains("content"),
                          "錯誤必須指名缺的是 content：\(message(error))")
        }
    }

    // MARK: - Failure mode 2：判斷型帶 content

    func testJudgementWithContentIsRejectedExplainingWhy() {
        XCTAssertThrowsError(try ProvenanceReference(
            field: "names", value: "Chen, H-Y.",
            url: nil, retrieved: nil, status: nil, mediaType: nil,
            content: digestA, judgement: "名冊內唯一", restsOn: [digestB])) { error in
            XCTAssertTrue(message(error).contains("判斷") && message(error).contains("content"),
                          "錯誤必須說明判斷型無自身位元組：\(message(error))")
        }
    }

    // MARK: - 判斷型的成對性（requirement：judgement 不是缺欄位的擷取型）

    func testJudgementWithoutRestsOnIsRejected() {
        XCTAssertThrowsError(try ProvenanceReference(
            field: "orcid", value: nil,
            url: nil, retrieved: nil, status: nil, mediaType: nil,
            content: nil, judgement: "推理", restsOn: [])) { error in
            XCTAssertTrue(message(error).contains("rests-on"), message(error))
        }
    }

    func testRestsOnWithoutJudgementIsRejected() {
        XCTAssertThrowsError(try ProvenanceReference(
            field: "orcid", value: nil,
            url: nil, retrieved: nil, status: nil, mediaType: nil,
            content: nil, judgement: nil, restsOn: [digestA])) { error in
            XCTAssertTrue(message(error).contains("judgement"), message(error))
        }
    }

    // MARK: - 兩側混用／皆空

    func testMixedSidesWithoutContentIsRejected() {
        XCTAssertThrowsError(try ProvenanceReference(
            field: "orcid", value: nil,
            url: "https://example.org/x", retrieved: nil, status: nil, mediaType: nil,
            content: nil, judgement: "推理", restsOn: [digestA])) { error in
            XCTAssertTrue(message(error).contains("互斥") || message(error).contains("混用"),
                          message(error))
        }
    }

    func testEmptyBothSidesIsRejected() {
        XCTAssertThrowsError(try ProvenanceReference(
            field: "orcid", value: nil,
            url: nil, retrieved: nil, status: nil, mediaType: nil,
            content: nil, judgement: nil, restsOn: [])) { error in
            XCTAssertTrue(message(error).contains("兩側") || message(error).contains("無法辨識"),
                          message(error))
        }
    }

    // MARK: - digest 形狀

    func testMalformedDigestIsRejectedNamingValue() {
        XCTAssertThrowsError(try ProvenanceReference(
            field: "orcid", value: nil,
            url: "https://example.org/x", retrieved: "2026-08-03", status: 200,
            mediaType: nil, content: "sha256:short", judgement: nil, restsOn: [])) { error in
            XCTAssertTrue(message(error).contains("sha256:short"),
                          "錯誤必須帶原值：\(message(error))")
        }
        XCTAssertFalse(ProvenanceReference.isValidDigest("md5:abc"))
        XCTAssertFalse(ProvenanceReference.isValidDigest(
            "sha256:" + String(repeating: "AB", count: 32)), "大寫 hex 不收——定址鍵只有一種寫法")
        XCTAssertTrue(ProvenanceReference.isValidDigest(digestA))
    }

    // MARK: - 合法建構

    func testValidRetrievalAndJudgementConstruct() throws {
        let r = try ProvenanceReference(
            field: "orcid", value: nil,
            url: "https://pub.orcid.org/v3.0/0000-0003-4038-9439", retrieved: "2026-08-03",
            status: 200, mediaType: "application/json", content: digestA,
            judgement: nil, restsOn: [])
        guard case .retrieval(_, _, let status, _, let content) = r.kind else {
            return XCTFail("應為擷取型")
        }
        XCTAssertEqual(status, 200)
        XCTAssertEqual(content, digestA)

        let j = try ProvenanceReference(
            field: "names", value: "Chen, H-Y.",
            url: nil, retrieved: nil, status: nil, mediaType: nil,
            content: nil, judgement: "名冊內 Chen 姓且 given initials H-Y 唯一", restsOn: [digestA, digestB])
        guard case .judgement(_, let restsOn) = j.kind else { return XCTFail("應為判斷型") }
        XCTAssertEqual(restsOn, [digestA, digestB])
        XCTAssertEqual(j.value, "Chen, H-Y.")
    }

    // MARK: - Failure mode 3/4：field / value 存在性（decode 層——2.2/3.3 轉綠）

    private func personYAML(references: String) -> String {
        """
        person:
        id: 11111111-2222-3333-4444-555555555555
        key: chen-h-y
        names:
        - Chen, H-Y.
        \(references)
        """
    }

    func testReferenceNamingAbsentFieldRejectedAtDecode() {
        let yaml = personYAML(references: """
        references:
        - field: openalex
          url: https://example.org/x
          retrieved: 2026-08-03
          status: 200
          content: \(digestA)
        """)
        XCTAssertThrowsError(try PersonYAML.decode(yaml),
                             "指名記錄沒有的欄位（openalex 缺席）必須拒絕載入") { error in
            XCTAssertTrue(message(error).contains("openalex"),
                          "錯誤必須指名欄位：\(message(error))")
        }
    }

    func testReferenceNamingAbsentValueRejectedAtDecode() {
        let yaml = personYAML(references: """
        references:
        - field: names
          value: "Wang, X."
          judgement: 人工判定
          rests-on:
          - \(digestA)
        """)
        XCTAssertThrowsError(try PersonYAML.decode(yaml),
                             "value 在 collection 內找不到必須拒絕載入") { error in
            XCTAssertTrue(message(error).contains("names") && message(error).contains("Wang, X."),
                          "錯誤必須同時指名欄位與值：\(message(error))")
        }
    }
}

/// #66 task 2.x：references 清單的 YAML 編解碼（round-trip + 位元組確定性）。
extension ProvenanceTests {

    private var sampleRefs: [ProvenanceReference] {
        let dA = "sha256:" + String(repeating: "ab", count: 32)
        let dB = "sha256:" + String(repeating: "cd", count: 32)
        return [
            ProvenanceReference(field: "orcid", kind: .retrieval(
                url: "https://pub.orcid.org/v3.0/0000-0003-4038-9439",
                retrieved: "2026-08-03", status: 200,
                mediaType: "application/json", content: dA)),
            ProvenanceReference(field: "names", value: "Chen, H-Y.", kind: .judgement(
                statement: "名冊內 Chen 姓且 given initials H-Y 唯一",
                restsOn: [dA, dB])),
        ]
    }

    func testReferencesRoundTripAndDeterministicBytes() throws {
        let node = try ProvenanceYAML.node(sampleRefs)
        let text1 = try Yams.serialize(node: node, allowUnicode: true)
        let text2 = try Yams.serialize(node: try ProvenanceYAML.node(sampleRefs),
                                       allowUnicode: true)
        XCTAssertEqual(text1, text2, "同一份資料每次 encode 位元組相同——避免假 diff")

        guard let composed = try Yams.compose(yaml: text1) else {
            return XCTFail("serialize 後 compose 失敗")
        }
        let decoded = try ProvenanceYAML.decode(composed, context: "person")
        XCTAssertEqual(decoded, sampleRefs, "round-trip 必須回到原值")
    }

    func testReferencesDecodeRejectsNonSequence() {
        let node = try! Yams.compose(yaml: "just-a-scalar")!
        XCTAssertThrowsError(try ProvenanceYAML.decode(node, context: "person"))
    }
}

/// #66 task 2.3：向後相容——本變更對既有檔案零影響（D7）。
extension ProvenanceTests {

    /// 真實形狀的既有記錄（無 references、timeline 段帶 source 裸 URL）。
    private var legacyPersonYAML: String {
        """
        person:
        id: 22222222-3333-4444-5555-666666666666
        key: cheng-legacy
        names:
        - Cheng, L.
        profile:
          affiliations:
          - value:
              literal: 中央研究院統計科學研究所
            start: '2003'
            source: https://sites.stat.sinica.edu.tw/roster
        """
        }

    func testExistingRecordWithoutReferencesIsByteStableAndSourcePreserved() throws {
        let person = try PersonYAML.decode(legacyPersonYAML)
        XCTAssertEqual(person.references, [], "無 references 的既有記錄載入為空清單")
        // TemporalValue.source 原樣保留、未被轉成 reference（D7）
        XCTAssertEqual(person.profile.affiliations.entries.first?.source,
                       "https://sites.stat.sinica.edu.tw/roster")

        let canonical = try PersonYAML.encode(person)
        XCTAssertFalse(canonical.contains("references"),
                       "無 references 不寫出該鍵——既有檔案零 diff：\(canonical)")
        XCTAssertTrue(canonical.contains("source: https://sites.stat.sinica.edu.tw/roster"),
                      "source 必須原樣寫回：\(canonical)")
        // 寫回位元組穩定（canonical 形式的冪等）
        let again = try PersonYAML.encode(try PersonYAML.decode(canonical))
        XCTAssertEqual(canonical, again, "decode→encode 必須位元組冪等")
    }
}
