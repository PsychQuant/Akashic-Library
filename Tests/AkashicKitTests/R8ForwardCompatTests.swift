import XCTest
import Yams
@testable import AkashicCore

/// R8 修復的 regression（#23 verify R7 findings——0 blocking 後的 MEDIUM/LOW 補完）。
final class R8ForwardCompatTests: XCTestCase {

    private let head = """
    id: 7C1F6C2E-0000-0000-0000-000000000001
    citekey: a2020b
    type: article
    title: T
    """

    // MARK: - M1/M4：毀字守衛全檔化（純 known 檔先前是半開的門）

    func testPureKnownFileWithNELQuarantines() {
        // R7 的守衛只長在切分路徑——純 known 檔被 libyaml 靜默摺疊毀字後寫回
        XCTAssertThrowsError(try PersonYAML.decode("key: a\nnames: ['Attention\u{85}Is All']\n")) {
            XCTAssertTrue(String(describing: $0).contains("NEL"), "\($0)")
        }
    }

    func testPureKnownFileWithBareCRQuarantines() {
        XCTAssertThrowsError(try PersonYAML.decode("key: a\nnames: ['A\rB']\n")) {
            XCTAssertTrue(String(describing: $0).contains("裸 CR"), "\($0)")
        }
    }

    /// v1.2 相容的關鍵反向面（DA R7 (b)）：CRLF **行尾**在純 known 檔由 libyaml
    /// 正規化為 LF、無資料損失——良性 CRLF 檔必須仍可讀。
    func testPureKnownCRLFFileStillLoads() throws {
        let p = try PersonYAML.decode("key: a\r\nnames: [A]\r\n")
        XCTAssertEqual(p.key, "a")
        XCTAssertEqual(p.names, ["A"])
    }

    /// 帶未知欄位時 CRLF 仍全面拒收（切分行模型分歧——結構性理由不變）
    func testCRLFWithUnknownFieldStillRejected() {
        XCTAssertThrowsError(try PersonYAML.decode("key: a\r\nnames: [A]\r\nextra: 1\r\n"))
    }

    // MARK: - M2：fields / attachments 的鍵層 guard

    func testTaggedFieldsKeyRejected() {
        XCTAssertThrowsError(try EntryYAML.decode(head + "\nfields:\n  !foo journal: JASA\n")) {
            XCTAssertTrue(String(describing: $0).contains("fields"), "\($0)")
        }
        XCTAssertThrowsError(try EntryYAML.decode(head + "\nfields:\n  ? {=: journal}\n  : JASA\n"))
    }

    func testTaggedAttachmentKeyRejected() {
        XCTAssertThrowsError(try EntryYAML.decode(head + "\nattachments:\n  - !bar zotero: p.pdf\n"))
    }

    // MARK: - M3：explicit/implicit null 的 known 欄位＝欄位不存在（v1.2 相容）

    func testNullKnownCollectionFieldsTreatedAsAbsent() throws {
        let e = try EntryYAML.decode(head + "\nakashic:\ndate:\nfields:\n")
        XCTAssertTrue(e.akashic.isEmpty)
        XCTAssertNil(e.date)
        XCTAssertTrue(e.fields.isEmpty)
        // RMW round-trip：null 行以「欄位不存在」重寫，無資料損失
        let rd = try EntryYAML.decode(try EntryYAML.encode(e))
        XCTAssertEqual(rd, e)
        let p = try PersonYAML.decode("key: a\nnames:\n")
        XCTAssertEqual(p.names, [])
    }

    func testNullRequiredFieldReportsMissing() {
        XCTAssertThrowsError(try EntryYAML.decode(
            "id: 7C1F6C2E-0000-0000-0000-000000000001\ncitekey: a2020b\ntype: article\ntitle:\n")) {
            XCTAssertEqual($0 as? StoreYAMLError, .missingField("title"))
        }
    }

    // MARK: - L31：深巢狀 → quarantine 而非 stack overflow

    func testDeeplyNestedUnknownSubtreeQuarantinesNotCrashes() {
        var value = "1"
        for _ in 0..<600 { value = "[\(value)]" }
        let yaml = head + "\ndeep: \(value)\n"
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    // MARK: - L13/L18：誤導診斷修正

    func testShapeMismatchNotReportedAsMissing() {
        XCTAssertThrowsError(try EntryYAML.decode(head + """

        provenance:
          zotero_key: {a: b}
          zotero_version: 1
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("形狀不符"), "\(error)")
        }
        XCTAssertThrowsError(try EntryYAML.decode(
            "id: not-a-uuid\ncitekey: a2020b\ntype: article\ntitle: T\n")) { error in
            XCTAssertTrue(String(describing: error).contains("不是 UUID"), "\(error)")
        }
    }

    // MARK: - L14：person canary 欄位指認

    func testPersonCanaryNamesMismatchingField() {
        var p = Person(key: "a", names: ["\u{FEFF}X"])
        p.unknownFields = [UnknownField(key: "extra", raw: "extra: 1\n")]
        XCTAssertThrowsError(try PersonYAML.encode(p)) { error in
            XCTAssertTrue(String(describing: error).contains("names"), "\(error)")
        }
    }
}
