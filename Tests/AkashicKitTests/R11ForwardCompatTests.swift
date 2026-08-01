import XCTest
import Yams
@testable import AkashicCore

/// R11 修復的 regression（#23 verify R10 的三個 HIGH）。
///
/// 這一組刻意**測 spec 不測實作**——R10-verify 的 DA 指出既有的
/// `testMergeAndValueFaceFieldsKeysRejected` 只測程式化路徑並斷言
/// 「encode 應該 throw」，等於把「讀得到但寫不回」的凍結行為當成正確答案釘住。
/// 這裡改成從**檔案文字**進 decode，斷言「載入時就該拒收」。
final class R11ForwardCompatTests: XCTestCase {

    private let entryHead = """
    id: 7C1F6C2E-0000-0000-0000-000000000001
    citekey: a2020b
    type: article
    title: T
    """

    // MARK: - H1：merge/value 判 tag，不判鍵名字串

    /// 顯式 `!!merge` 加在非 `<<` 的鍵名上——字串比對看不到，tag 看得到。
    /// 修復前：被當普通未知欄位收下並原樣寫回，merge-aware loader 讀同一份
    /// 檔案會展開成另一份記錄（可注入 known 欄位）。
    func testExplicitMergeTagOnArbitraryKeyRejected() throws {
        let yaml = """
        key: p
        names: [A]
        !!merge foo: {orcid: SMUGGLED}
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { err in
            guard case StoreYAMLError.invalidField(_, let msg) = err else {
                return XCTFail("預期 invalidField，得到 \(err)")
            }
            XCTAssertTrue(msg.contains("merge"), "訊息應指出 merge 面：\(msg)")
        }
    }

    /// 顯式 `!!value` 同理（R10-verify DA 實測頂層 `=` 被收下並原樣寫回）。
    func testExplicitValueTagKeyRejected() throws {
        let yaml = """
        key: p
        names: [A]
        !!value bar: x
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml))
    }

    /// 裸 `<<` 仍然要擋（plain scalar resolve 成 merge tag）——修復不得放寬這條。
    func testPlainMergeKeyStillRejected() throws {
        let yaml = """
        key: p
        names: [A]
        <<: {orcid: X}
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml))
    }

    /// **反向**：quoted `'<<'` 依 YAML 是普通字串（tag = str），不得誤拒。
    /// 修復前的字串比對把它一起擋掉了（過擋）。
    func testQuotedMergeFaceKeyIsOrdinaryString() throws {
        let yaml = """
        key: p
        names: [A]
        '<<': ordinary-string-key
        """
        let person = try PersonYAML.decode(yaml)
        XCTAssertEqual(person.key, "p")
        XCTAssertEqual(person.unknownFields.map(\.key), ["<<"],
                       "quoted '<<' 應被當成普通未知欄位保留")
    }

    // MARK: - H2：顯式 complex key 在 compose 之前擋下

    /// alias 置於 complex key 位置 → 展開發生在 `Yams.compose` **內部**
    /// （`checkDuplicates` 遞迴 hash key node），早於本檔所有預算守衛。
    /// 實測修復前：636 bytes 的檔案讓 doctor 燒 36 s CPU 後 timeout。
    /// 本測試不比時間（CI 機器差異大），只斷言「decode 直接 throw」——
    /// 若守衛失效，這條測試會 hang 而非 fail，那本身就是訊號。
    func testExplicitComplexKeyAliasBombRejectedBeforeCompose() throws {
        var lines = ["key: bomb", "names: [A]", "a0: &a0 [x,x,x,x,x,x,x,x,x]"]
        for i in 1...12 {
            let refs = (1...9).map { _ in "*a\(i - 1)" }.joined(separator: ",")
            lines.append("a\(i): &a\(i) [\(refs)]")
        }
        lines.append("? *a12")
        lines.append(": 1")
        let yaml = lines.joined(separator: "\n")

        XCTAssertThrowsError(try PersonYAML.decode(yaml)) { err in
            guard case StoreYAMLError.invalidField(_, let msg) = err else {
                return XCTFail("預期 invalidField，得到 \(err)")
            }
            XCTAssertTrue(msg.contains("complex key"), "應由 complex-key 守衛擋下：\(msg)")
        }
    }

    /// 無害的 complex key（不含 alias）同樣拒收——守衛是語法層 fail-closed，
    /// 不試圖分辨「這個 complex key 危不危險」（分辨需要 compose，已經太遲）。
    func testPlainExplicitComplexKeyRejected() throws {
        let yaml = """
        key: p
        names: [A]
        ? plain
        : value
        """
        XCTAssertThrowsError(try PersonYAML.decode(yaml))
    }

    /// **反向**：值裡出現的 `?` 不得誤判（只有行首 + 空白才是 indicator）。
    func testQuestionMarkInValueNotTreatedAsComplexKey() throws {
        let yaml = """
        key: p
        names: [A]
        note: "why? because."
        """
        let person = try PersonYAML.decode(yaml)
        XCTAssertEqual(person.note, "why? because.")
    }

    /// **反向**：`?` 開頭但後面直接接字元（如 `?foo:`）不是 explicit key indicator。
    func testQuestionMarkPrefixedKeyNotTreatedAsComplexKey() throws {
        let yaml = """
        key: p
        names: [A]
        ?foo: bar
        """
        let person = try PersonYAML.decode(yaml)
        XCTAssertEqual(person.unknownFields.map(\.key), ["?foo"])
    }

    // MARK: - H3：fields 鍵的字串面 fail-closed（decode 端）

    /// quoted `'<<'` 的 tag 是 str → 通過 R10 的 tag 閉集 → decode 收下；
    /// 但 encode 時 `Node("<<")` implicit resolve 成 merge → emit 裸 `<<:` →
    /// 內層 canary decode 撞閉集 → 永遠 throw。淨結果是「讀得到但永遠寫不回」
    /// 且零可見性。decode 端補字串面拒收後，這種檔案在載入時就 quarantine。
    func testFieldsQuotedMergeFaceKeyRejectedAtDecode() throws {
        let yaml = entryHead + """

        fields:
          '<<': smuggled
          journaltitle: JASA
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml)) { err in
            guard case StoreYAMLError.invalidField(let ctx, _) = err else {
                return XCTFail("預期 invalidField，得到 \(err)")
            }
            XCTAssertEqual(ctx, "fields")
        }
    }

    func testFieldsQuotedValueFaceKeyRejectedAtDecode() throws {
        let yaml = entryHead + """

        fields:
          '=': smuggled
        """
        XCTAssertThrowsError(try EntryYAML.decode(yaml))
    }

    /// **不變式**：decode 拒收的檔案，encode 端不會有機會產生它——
    /// 兩側對稱是 §7「自我一致性」要的。這裡驗正常 fields 仍 round-trip。
    func testOrdinaryFieldsKeysStillRoundTrip() throws {
        let yaml = entryHead + """

        fields:
          journaltitle: JASA
          volume: "90"
          "2026": year-like-key
        """
        let entry = try EntryYAML.decode(yaml)
        XCTAssertEqual(entry.fields["journaltitle"], "JASA")
        XCTAssertEqual(entry.fields["2026"], "year-like-key")
        let out = try EntryYAML.encode(entry)
        let back = try EntryYAML.decode(out)
        XCTAssertEqual(back.fields, entry.fields)
    }
}
