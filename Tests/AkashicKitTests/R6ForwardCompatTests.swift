import XCTest
import Yams
@testable import AkashicCore

/// R6 修復的 regression（#23 verify R5 findings）。
/// 覆蓋：canary 不變式（F1）、known 形狀演化 fail-closed（F2/DA HIGH）、
/// tagged shadow key（F3/M5/M8）、行尾守衛限縮（F4/M11/M12）、
/// stream 標記變體（F5/M6/L14）、縮排平移 fail-closed（F6/M7）、
/// 驗證預算中性歸因（F8/M10）。
final class R6ForwardCompatTests: XCTestCase {

    // MARK: - F1：語意 canary 的正規化比較基準（R5 CRITICAL）

    /// 次秒精度 Date + 未知欄位——R5 的 identity canary 對此必拒寫
    /// （Zotero pull 主線 `now: Date()` 幾乎必然次秒非零）。
    func testSubSecondDateWithUnknownFieldEncodes() throws {
        var e = Entry(id: UUID(), citekey: "a2020b", type: "article", title: "T")
        e.provenance = Provenance(zoteroKey: "K", zoteroVersion: 1,
                                  importedAt: Date(timeIntervalSince1970: 1_753_000_000.987),
                                  orphanedAt: Date(timeIntervalSince1970: 1_753_100_000.5))
        e.unknownFields = [UnknownField(key: "rating", raw: "rating: 5\n")]
        let out = try EntryYAML.encode(e)
        let rd = try EntryYAML.decode(out)
        // store 只存秒精度（規格）：讀回的是截斷值
        XCTAssertEqual(rd.provenance?.importedAt,
                       Date(timeIntervalSince1970: 1_753_000_000))
        XCTAssertEqual(rd.provenance?.orphanedAt,
                       Date(timeIntervalSince1970: 1_753_100_000))
        XCTAssertEqual(rd.unknownFields.map(\.key), ["rating"])
    }

    // MARK: - F2：known 欄位形狀演化 fail-closed（DA R5 HIGH）

    /// DA 的實測毀損案例：names 由 sequence 演化為 mapping（較新 schema），
    /// R5 的 decode 靜默當成「沒有 names」→ 舊 binary 一次無害 RMW 把人名整段
    /// 刪除且全部檢查綠燈。R6：形狀不符 → decode throw → load quarantine
    /// （v1.2 級保護，檔案原封不動）。
    func testShapeEvolvedNamesFailsClosed() {
        let yaml = """
        id: 11111111-1111-4111-8111-111111111111
        key: cheng-che
        names:
          primary: 鄭澈
          romanized: Che Cheng
        affiliations:
          - organization: 中央研究院統計科學研究所
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            // #227：names 已是 mapping（authorized/variant 兩分割），未知分割鍵走
            // strict-schema 拒絕——fail-closed 的保護不變，訊息點名 names。
            XCTAssertTrue(String(describing: error).contains("person.names"))
        }
    }

    /// 同族（無未知欄位版）：只改形狀、不加 key——R5 連 unknownFieldFiles
    /// 可見性都沒有，re-encode 直接刪整個子樹。
    func testShapeEvolvedTagsWithoutNewKeysFailsClosed() {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        akashic:
          tags:
            values: [gap, eda]
            source: zotero
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    func testShapeMismatchFamilyFailsClosed() {
        let head = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        """
        XCTAssertThrowsError(try EntryYAML.decode(head + "\ndate: [2020]\n"))
        XCTAssertThrowsError(try EntryYAML.decode(head + "\nakashic:\n  status: [x]\n"))
        XCTAssertThrowsError(try EntryYAML.decode(head + "\nakashic:\n  relations: [x]\n"))
        XCTAssertThrowsError(try EntryYAML.decode(
            head + "\nakashic:\n  relations:\n    cites: {a: b}\n"))
        XCTAssertThrowsError(try EntryYAML.decode(
            head + "\nprovenance:\n  zotero_key: K\n  zotero_version: 1\n  imported_at: 不是時間\n"))
        XCTAssertThrowsError(try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\norcid: {x: y}\n"))
    }

    // MARK: - F3：tagged shadow key（M5/M8）

    /// 自訂 tag、字串與 known key 同名：`map[...]` 讀不到、又不被歸為 unknown
    /// ——R5 寫回即靜默剝除且 canary 看不見。R6 fail-closed。
    func testCustomTagShadowKnownKeyRejected() {
        XCTAssertThrowsError(
            try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\n!foo note: decoy\nnote: real\n")) { error in
            XCTAssertTrue(String(describing: error).contains("非字串 tag"))
        }
        // 無 plain 同名鍵的單獨 shadow 同樣拒收（單獨存在也讀不到、也會被剝）
        XCTAssertThrowsError(try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\n!foo note: x\n"))
        XCTAssertThrowsError(try EntryYAML.decode("""
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        !foo akashic:
          x: 1
        """))
    }

    /// 自訂 tag 的 unknown 鍵不受限——切分/oracle/寫回走文件序 index，
    /// tag 在 raw 內逐字保真。
    func testCustomTagUnknownKeyPreserved() throws {
        let person = try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\n!foo weird: 1\n")
        XCTAssertEqual(person.unknownFields.map(\.key), ["weird"])
        XCTAssertEqual(person.unknownFields.first?.raw, "!foo weird: 1\n")
        let out = try PersonYAML.encode(person)
        XCTAssertTrue(out.contains("!foo weird: 1\n"))
    }

    // MARK: - F4：行尾守衛限縮到 CR/CRLF（M11/M12、DA (b)+(c)）

    /// U+2028 是本 binary 的 emitter 自己會逐字寫出的內容字元（PDF 複製貼上的
    /// 常見產物），round-trip 無損。R5 的全文掃描把「帶未知欄位 + known 值含
    /// U+2028」的檔整份 quarantine 且永久不可寫。R6：讀寫皆正常。
    func testLineSeparatorInKnownValueWithUnknownFieldSurvives() throws {
        var e = Entry(id: UUID(), citekey: "a2020b", type: "article",
                      title: "Attention\u{2028}Is All You Need")
        e.unknownFields = [UnknownField(key: "rating", raw: "rating: 5\n")]
        let out = try EntryYAML.encode(e)
        let rd = try EntryYAML.decode(out)
        XCTAssertEqual(rd.title, e.title)
        XCTAssertEqual(rd.unknownFields.map(\.key), ["rating"])
        // RMW（再 encode 一次）也必須通——「永久不可寫」是 DA (c) 的構造
        _ = try EntryYAML.encode(rd)
    }

    func testCRLFStillRejectedWithHonestMessage() {
        let yaml = "key: a\r\nnames: {variant: [A]}\r\nextra: 1\r\n"
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { error in
            let msg = String(describing: error)
            XCTAssertTrue(msg.contains("CR/CRLF"), "訊息應指向行尾：\(msg)")
        }
    }

    // MARK: - F5：stream 標記變體（M6/L14）

    func testStreamMarkerVariantsTolerated() throws {
        // 尾隨空白的文件結束標記
        let p1 = try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nextra: 1\n... \n")
        XCTAssertEqual(p1.unknownFields.map(\.key), ["extra"])
        // 帶註解的結束標記
        let p2 = try PersonYAML.decode("id: 11111111-1111-4111-8111-111111111111\nkey: a\nnames: {variant: [A]}\nextra: 1\n... # done\n")
        XCTAssertEqual(p2.unknownFields.map(\.key), ["extra"])
        // %YAML directive + 帶註解的 --- 開頭
        let p3 = try PersonYAML.decode("%YAML 1.1\n--- # header\nid: 11111111-1111-4111-8111-111111111111\nkey: a\nextra: 1\n")
        XCTAssertEqual(p3.unknownFields.map(\.key), ["extra"])
        // 變體標記剝除後 round-trip 乾淨（不把 stream token 吸進 raw）
        let out = try PersonYAML.encode(p1)
        XCTAssertFalse(out.contains("..."))
        _ = try PersonYAML.decode(out)
    }

    // MARK: - F6：縮排平移 fail-closed（M7）

    /// decode 容忍的「續行縮排低於區塊基準」版面，平移後會把續行推到
    /// ≤ targetIndent（成為下一輪 decode 的 entry 起始）——R5 產出切不開的
    /// 產物或錯位訊息。R6：encode 端以平移不變式明確拒寫。
    func testUnderIndentedContinuationRefusedAtEncodeWithHonestMessage() throws {
        let yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        akashic:
            tags:
            - keep
            weird: [a,
          b]
        """
        let e = try EntryYAML.decode(yaml)   // 讀取面容忍（可用性）
        XCTAssertEqual(e.akashic.unknownFields.map(\.key), ["weird"])
        XCTAssertThrowsError(try EntryYAML.encode(e)) { error in
            XCTAssertTrue(String(describing: error).contains("平移"),
                          "訊息應指向平移不變式：\(error)")
        }
    }

    // MARK: - F8：驗證預算的中性歸因（M10）

    /// alias-free 的大型未知子樹同樣打穿預算（比對次數與節點數線性相關）——
    /// R5 訊息斷言「anchor/alias 重用、與檔案大小無關」是可證偽的誤導。
    func testAliasFreeBudgetExhaustionNeutralMessage() {
        var yaml = """
        id: 7C1F6C2E-0000-0000-0000-000000000001
        citekey: a2020b
        type: article
        title: T
        bigfield:
        """
        yaml += "\n"
        for i in 0..<70_000 { yaml += "- k\(i): 1\n" }
        XCTAssertThrowsError(try EntryYAML.decode(yaml)) { error in
            let msg = String(describing: error)
            XCTAssertTrue(msg.contains("驗證預算"), "應是預算路徑：\(msg)")
            XCTAssertFalse(msg.contains("與檔案大小無關"))
        }
    }
}
