import XCTest
import Yams
@testable import AkashicCore

/// R7 修復的 regression（#23 verify R6 findings）。
/// 覆蓋：平移不變式對 indentless sequence / 空白行的誤殺（H1/H2）、
/// NEL 回歸守衛（DA M23）、closed-shape tagged-shadow（H5）、
/// `=` 假 scalar（M14）、fields 字串面撞名（M16）、BOM（M6/M13）、
/// 共用驗證預算（H4）。
final class R7ForwardCompatTests: XCTestCase {

    private let head = """
    id: 7C1F6C2E-0000-0000-0000-000000000001
    citekey: a2020b
    type: article
    title: T
    """

    // MARK: - H1：indentless sequence 平移合法（R6 的不變式誤殺）

    func testIndentlessSequenceUnknownFieldRoundTrips() throws {
        let yaml = head + """

        akashic:
            future:
            - one
            - two
        """
        let e = try EntryYAML.decode(yaml)
        XCTAssertEqual(e.akashic.unknownFields.map(\.key), ["future"])
        // encode 平移 4→2：sequence 行落在 targetIndent 是合法 indentless seq
        let out = try EntryYAML.encode(e)
        let rd = try EntryYAML.decode(out)
        XCTAssertEqual(rd.akashic.unknownFields.map(\.key), ["future"])
        XCTAssertEqual(rd, try EntryYAML.decode(try EntryYAML.encode(rd)), "再 RMW 一次仍穩定")
    }

    // MARK: - H2：空白-only 行不是語意續行

    func testWhitespaceOnlyLineInUnknownBlockRoundTrips() throws {
        let yaml = head + """

        akashic:
            future:
              value: 1
        \u{20}\u{20}\u{20}\u{20}
            status: active
        """
        let e = try EntryYAML.decode(yaml)
        XCTAssertEqual(e.akashic.unknownFields.map(\.key), ["future"])
        XCTAssertEqual(e.akashic.status, "active")
        _ = try EntryYAML.encode(e)   // R6 在此 throw（空白行被判語意續行）
    }

    // MARK: - DA M23：NEL 回歸守衛（有損通道，與 CR 同族）

    func testNELInKnownValueWithUnknownFieldQuarantines() {
        // quoted NEL：libyaml 讀取時摺疊毀字——R6 移除守衛後變靜默毀損，R7 回歸 fail-closed
        let yaml = "key: a\nnames: ['Attention\u{85}Is All']\nextra: 1\n"
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            XCTAssertTrue(String(describing: error).contains("NEL"), "\(error)")
        }
    }

    func testEmitterEscapesNELSoSelfWrittenFilesUnaffected() throws {
        // 自家產物永不含 raw NEL（emitter escape 成 \N）→ 守衛零誤殺
        var e = Entry(id: UUID(), citekey: "a2020b", type: "article",
                      title: "alpha\u{85}beta")
        e.unknownFields = [UnknownField(key: "rating", raw: "rating: 5\n")]
        let out = try EntryYAML.encode(e)
        XCTAssertFalse(out.unicodeScalars.contains(where: { $0 == "\u{85}" }))
        XCTAssertEqual(try EntryYAML.decode(out).title, e.title)
    }

    // MARK: - H5：closed-shape 層的 tagged-shadow 守衛

    func testTaggedShadowInClosedShapesFailsClosed() {
        // provenance optional 欄位——R6 前被靜默歸零、寫回即剝除
        XCTAssertThrowsError(try EntryYAML.decode(head + """

        provenance:
          zotero_key: K
          zotero_version: 1
          !foo zotero_hash: HASHVALUE
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("非字串 tag"), "\(error)")
        }
        // akashic.relations
        XCTAssertThrowsError(try EntryYAML.decode(head + """

        akashic:
          relations:
            !!int cites: [b2021c]
        """))
        // authors 元素
        XCTAssertThrowsError(try EntryYAML.decode(head + """

        authors:
          - !foo key: someone
            literal: Real Name
        """))
    }

    // MARK: - M14：`=`（!!value）鍵 mapping 假扮 scalar

    func testValueKeyMappingRejectedAsScalar() {
        XCTAssertThrowsError(try EntryYAML.decode("""
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title:
          =: real
        """)) { error in
            XCTAssertTrue(String(describing: error).contains("形狀不符"), "\(error)")
        }
        XCTAssertThrowsError(try EntryYAML.decode(head + "\ndate:\n  =: 2020\n"))
        XCTAssertThrowsError(try EntryYAML.decode(head + "\nakashic:\n  status:\n    =: read\n"))
        XCTAssertThrowsError(try PersonYAML.decode("key: a\nnote:\n  =: hello\n"))
        XCTAssertThrowsError(try EntryYAML.decode(head + "\nfields:\n  journal:\n    =: JASA\n"))
        XCTAssertThrowsError(try EntryYAML.decode(head + """

        provenance:
          zotero_key: K
          zotero_version: 1
          imported_at:
            =: 2025-07-20T08:26:40Z
        """))
    }

    // MARK: - M16：fields 字串面撞名

    func testFieldsStringFaceCollisionFailsClosed() {
        XCTAssertThrowsError(try EntryYAML.decode(head + """

        fields:
          '123': quoted
          123: plain
        """)) { error in
            // R9 re-pin（R8-verify M13）：core-resolved 鍵以字串面收下（等冪），
            // 撞名由字串面重複檢查擋——此路徑必須可達，不得被鍵層 guard 短路
            XCTAssertTrue(String(describing: error).contains("字串面重複"), "\(error)")
        }
    }

    /// R9（R8-verify HIGH-3）：emitter 對 fields 鍵輸出 plain 樣式，「2026」鍵
    /// re-parse resolve 成 int——core-schema 鍵必須以字串面收下，encode/decode
    /// 等冪（str-tag 檢查會讓自家產物寫得出、讀不回）。
    func testNumericFaceFieldsKeyRoundTrips() throws {
        var e = Entry(id: UUID(), citekey: "a2020b", type: "article", title: "T")
        e.fields = ["2026": "hello", "no": "bool-face", "1.5": "float-face"]
        let out = try EntryYAML.encode(e)
        XCTAssertEqual(try EntryYAML.decode(out), e)
    }

    // MARK: - M6/M13：BOM

    func testLeadingStreamBOMWithFirstKeyUnknownRoundTrips() throws {
        let yaml = "\u{FEFF}future: 1\n" + head + "\n"
        let e = try EntryYAML.decode(yaml)
        XCTAssertEqual(e.unknownFields.map(\.key), ["future"])
        XCTAssertFalse(e.unknownFields[0].raw.contains("\u{FEFF}"), "BOM 不入 raw")
        let out = try EntryYAML.encode(e)
        XCTAssertEqual(try EntryYAML.decode(out).unknownFields.map(\.key), ["future"])
    }

    /// canary 的契約是「**值活不下來就拒寫**」——不是「一定要拒寫」。
    ///
    /// 前導 BOM 能不能 round-trip 取決於 YAML 寫入端與平台的字串處理：Swift 6.3
    /// 上活不下來（canary 擲錯），6.1.2 上活得下來（canary 正確地不擲）。原本的
    /// 斷言釘住了前者這個分支，於是在較舊的 toolchain 上失敗——但那不是回歸，
    /// 是測試把實作細節寫成了契約。
    ///
    /// 改成斷言不變式本身：**要嘛拒寫並指認欄位，要嘛寫出去且值原封不動**。
    /// 兩者之外的第三種結果（悄悄寫出一個變了的值）才是真正的失敗。
    func testLeadingBOMInTitleEitherRefusesNamingFieldOrRoundTrips() throws {
        var e = Entry(id: UUID(), citekey: "a2020b", type: "article", title: "\u{FEFF}X")
        e.unknownFields = [UnknownField(key: "rating", raw: "rating: 5\n")]
        do {
            let out = try EntryYAML.encode(e)
            XCTAssertEqual(try EntryYAML.decode(out).title, e.title,
                           "沒有拒寫就必須原封不動——悄悄改掉值是最壞的結果")
        } catch {
            XCTAssertTrue(String(describing: error).contains("title"),
                          "拒寫時訊息應指認欄位：\(error)")
        }
    }

    // MARK: - H4：驗證預算單檔共用（不可 per-block 聚合放大）

    func testOracleBudgetSharedAcrossBlocks() {
        var yaml = head + "\n"
        for b in 0..<2 {
            yaml += "big\(b):\n"
            for i in 0..<40_000 { yaml += "- k\(i): 1\n" }
        }
        // 單塊 ~12 萬次比對＜20 萬（R6 的 per-block 重置會兩塊都過）；
        // 共用預算下第二塊必然耗盡 → quarantine
        XCTAssertThrowsError(try EntryYAML.decode(yaml)) { error in
            XCTAssertTrue(String(describing: error).contains("驗證預算"), "\(error)")
        }
    }
}
