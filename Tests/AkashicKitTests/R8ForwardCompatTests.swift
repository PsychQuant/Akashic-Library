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

    /// R9（R8-verify M11/L26 更正）：CR 系是行尾慣例、非毀字向量——classic-Mac
    /// lone-CR 行尾檔 v1.2 可無損載入，必須維持可讀；quoted 內 CR 摺疊 ≡ LF
    /// 摺疊（spec 語意）。純 known 檔的 entry 守衛只擋 NEL。
    func testClassicMacLoneCRLineEndingsStillLoad() throws {
        let p = try PersonYAML.decode("key: a\rnames: [A]\r")
        XCTAssertEqual(p.key, "a")
        XCTAssertEqual(p.names, ["A"])
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

    /// R9 限縮（R8-verify CRITICAL）：null-as-absent 只適用 collection 欄位；
    /// scalar 欄位（date）以字串面收下 null-face（R6 normative）。
    func testNullKnownCollectionFieldsTreatedAsAbsent() throws {
        let e = try EntryYAML.decode(head + "\nakashic:\nfields:\n")
        XCTAssertTrue(e.akashic.isEmpty)
        XCTAssertTrue(e.fields.isEmpty)
        // RMW round-trip：null 行以「欄位不存在」重寫，無資料損失
        let rd = try EntryYAML.decode(try EntryYAML.encode(e))
        XCTAssertEqual(rd, e)
        let p = try PersonYAML.decode("key: a\nnames:\n")
        XCTAssertEqual(p.names, [])
    }

    /// R8-verify CRITICAL 的直接 regression：Zotero 無標題 item
    /// （`entry.title = fields["title"] ?? ""`）必須寫得進 store、讀得回來。
    func testEmptyTitleRoundTripsThroughEncode() throws {
        let e = Entry(id: UUID(), citekey: "a2020b", type: "article", title: "")
        let out = try EntryYAML.encode(e)
        XCTAssertEqual(try EntryYAML.decode(out), e)
    }

    /// v1.2 檔的 `title: Null`（emitter 對字串「Null」的 plain 輸出）必須載入
    /// 為字面值——R8 把它 quarantine 是 #23 失敗模式的鏡像復發。
    func testNullFaceScalarValuesReadAsStringFace() throws {
        let e = try EntryYAML.decode(
            "id: 7C1F6C2E-0000-0000-0000-000000000001\ncitekey: a2020b\ntype: article\ntitle: Null\ndate:\n")
        XCTAssertEqual(e.title, "Null")
        XCTAssertEqual(e.date, "")   // scalar 欄位：null-face 的字串面
        // optional scalar：status/note 的 null-face 值可寫可讀（等冪）
        var e2 = Entry(id: UUID(), citekey: "b2020c", type: "article", title: "T")
        e2.akashic.status = ""
        XCTAssertEqual(try EntryYAML.decode(try EntryYAML.encode(e2)), e2)
        var p = Person(key: "a", note: "~")
        XCTAssertEqual(try PersonYAML.decode(try PersonYAML.encode(p)), p)
        p.note = "null"
        XCTAssertEqual(try PersonYAML.decode(try PersonYAML.encode(p)), p)
    }

    /// 檔案裡的 `note: ~` RMW 後不得被靜默刪行（R8-verify HIGH (b)）。
    func testNullFaceOptionalScalarSurvivesRMW() throws {
        let p = try PersonYAML.decode("key: a\nnote: ~\n")
        XCTAssertEqual(p.note, "~")
        let out = try PersonYAML.encode(p)
        XCTAssertEqual(try PersonYAML.decode(out).note, "~")
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

// R10（#23 verify R9）：CR 判別式、fields 鍵閉集、null 白名單 pin
extension R8ForwardCompatTests {
    /// R9-verify HIGH（DA 構造）：LF 檔的 quoted 內容 CR 是毀字向量——validate
    /// 全綠、一次良性寫入即靜默摺成空白。R8 擋、R9 誤拆、R10 以 LF 判別式回歸。
    func testBareCRInsideQuotedScalarOfLFFileQuarantines() {
        XCTAssertThrowsError(try EntryYAML.decode(
            "id: 7C1F6C2E-0000-0000-0000-000000000001\ncitekey: a2020b\ntype: article\ntitle: \"Attention\ris all\"\n")) {
            XCTAssertTrue(String(describing: $0).contains("裸 CR"), "\($0)")
        }
    }

    /// 判別式另一面：全檔無 LF ⇒ CR 是 classic-Mac 行尾，無損載入
    /// （testClassicMacLoneCRLineEndingsStillLoad 已覆蓋，此處 pin 值無損性）。
    func testLoneCRFileValuesLossless() throws {
        let p = try PersonYAML.decode("key: a\rnames: [Alpha Beta]\rnote: intact\r")
        XCTAssertEqual(p.names, ["Alpha Beta"])
        XCTAssertEqual(p.note, "intact")
    }

    /// R9-verify M4/M8：merge 面（`<<`）與 value 面（`=`）鍵不入 fields——
    /// 本 PR 各層明文拒收 merge；R9 的 namespace 前綴判準誤放行且會 emit。
    func testMergeAndValueFaceFieldsKeysRejected() {
        let head = "id: 7C1F6C2E-0000-0000-0000-000000000001\ncitekey: a2020b\ntype: article\ntitle: T\n"
        XCTAssertThrowsError(try EntryYAML.decode(head + "fields:\n  <<: x\n"))
        XCTAssertThrowsError(try EntryYAML.decode(head + "fields:\n  =: x\n"))
        var e = Entry(id: UUID(), citekey: "a2020b", type: "article", title: "T")
        e.fields = ["<<": "v"]
        XCTAssertThrowsError(try EntryYAML.encode(e), "encode 側同樣拒絕（canary 反射）")
    }

    /// R9-verify L14：帶內容的顯式 !!null 不入 face 白名單（collection 欄位）
    func testExplicitNullWithContentNotAbsorbed() {
        XCTAssertThrowsError(try EntryYAML.decode(
            "id: 7C1F6C2E-0000-0000-0000-000000000001\ncitekey: a2020b\ntype: article\ntitle: T\nakashic: !!null foo\n"))
    }

    /// R9-verify M12：missingField 的等價 pin（R9 刪了唯一測試）
    func testAbsentTitleReportsMissingField() {
        XCTAssertThrowsError(try EntryYAML.decode(
            "id: 7C1F6C2E-0000-0000-0000-000000000001\ncitekey: a2020b\ntype: article\n")) {
            XCTAssertEqual($0 as? StoreYAMLError, .missingField("title"))
        }
    }
}
