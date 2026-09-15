import XCTest
@testable import AkashicCore
@testable import AkashicStoreIO

/// 頂層消毒不得弄壞合法反斜線，但也不得放行真控制字元（#297 item 1）。
///
/// 這兩條是同一個修法的兩面：`displaySafeAssembled` 從跳脫集合裡**只**拿掉反斜線
/// 一項。少了第一條，`StoreKey.pattern` 會顯示成 `\u{005C}A[a-z0-9]…`；少了第二條，
/// 修法就是安全性退化而非缺陷修復。
final class AssembledDisplaySafetyTests: XCTestCase {

    /// 合法反斜線原樣通過——`StoreKey.pattern` 是實際會出現在錯誤訊息裡的常量。
    func testAssembledKeepsLegitimateBackslashes() {
        let pattern = #"\A[a-z0-9][a-z0-9-]*\z"#
        let out = displaySafeAssembled("person key 不符合 \(pattern)，拒絕寫入")
        XCTAssertTrue(out.contains(pattern),
                      "帶合法反斜線的常量必須原樣顯示，實得：\(out)")
        XCTAssertFalse(out.contains("u{005C}"),
                       "不得把反斜線跳脫成 \\u{005C}：\(out)")
    }

    /// 已消毒片段不被二次消毒——`displaySafe` 刻意不冪等，所以這是必然而非意外。
    func testAssembledDoesNotDoubleEscapeAlreadySanitisedFragments() {
        let fragment = displaySafe("bad\u{001B}key")          // → bad\u{001B}key
        XCTAssertTrue(fragment.contains("u{001B}"), "前提：片段層應已跳脫 ESC")
        let out = displaySafeAssembled("citekey「\(fragment)」查無")
        XCTAssertTrue(out.contains("\\u{001B}"), "已跳脫的序列應原樣保留：\(out)")
        XCTAssertFalse(out.contains("u{005C}u{001B}"),
                       "不得二次消毒成 \\u{005C}u{001B}：\(out)")
    }

    /// **真**控制字元仍被跳脫——安全性不得因為去掉反斜線那一項而退化。
    ///
    /// 這是本修法最重要的一條：拿掉的必須只有反偽造性質，不是終端保護。
    func testAssembledStillEscapesRealControlCharacters() {
        for (name, scalar) in [("ESC", "\u{001B}"), ("BIDI-RLO", "\u{202E}"),
                               ("LS", "\u{2028}"), ("C1", "\u{0085}")] {
            let out = displaySafeAssembled("值：\(scalar)")
            XCTAssertFalse(out.unicodeScalars.contains(scalar.unicodeScalars.first!),
                           "\(name) 必須被跳脫，不得原樣送進終端：\(out.debugDescription)")
        }
    }

    /// 換行仍是合法的多行輸出——`displaySafeAssembled` 是 multiline 家族。
    func testAssembledPreservesRealNewlines() {
        let out = displaySafeAssembled("第一行\n第二行")
        XCTAssertTrue(out.contains("\n"), "多行輸出的 LF 必須保留：\(out.debugDescription)")
    }
}

/// `fmt` 不得繞過 person 的語意驗證（#297 item 2）。
final class CanonicalFormatValidationTests: XCTestCase {

    /// 語意矛盾的 person 檔——`authorized` 含一個不在 `names` 裡的字串。
    ///
    /// `fmt` 先前走 `atomicWrite` 直接落盤，會把它原樣重排後寫回：**排版對齊了，
    /// 矛盾還在，而且現在看起來像是工具背書過的**。
    func testNormalizedRejectsSemanticallyInvalidPerson() throws {
        let yaml = """
        person:
        id: \(UUID().uuidString)
        key: someone
        names:
          authorized:
          - Real Name
          variant:
          - Other
        """
        // 先確認這份 YAML 本身解得開（否則測的是 decode 失敗而非語意驗證）。
        XCTAssertNoThrow(try PersonYAML.decode(yaml), "前提：YAML 應可解析")

        var person = try PersonYAML.decode(yaml)
        person.names.authorized.append("Not In Variant Or Anywhere Else")
        // 直接以矛盾值重編出 YAML，模擬「磁碟上已有一份語意矛盾的檔」。
        let contradictory = try PersonYAML.encode(person)

        XCTAssertThrowsError(try CanonicalFormat.normalized(contradictory),
                             "語意矛盾的 person 不得通過 fmt 的正規化")
    }

    /// **`.venue` 分支與 `.person` 同一條紀律**（#554 R5 verify 第 9 列）：R5 之前 `fmt --apply` 的 venue
    /// 分支是裸 `encode(decode)`，直接 `atomicWrite`——`validate` 報 2 條 error 的 store，`fmt --check` 印
    /// 「✓ 全部已是 canonical form」、`fmt --apply` 把髒 venue 原樣寫回 rc=0。「手改的在下一次寫入被擋」
    /// 對 fmt 是反例。#297 對 person 修過同一件事，理由（`normalized()` 是解出型別值與寫回位元組之間
    /// **唯一**的交會點）對 venue 一字不差。
    func testNormalizedRejectsSemanticallyInvalidVenue() throws {
        var v = Venue(key: "j", type: .periodical,
                      names: Timeline([TemporalValue(value: "Psychometrika")]), authorized: ["Psychometrika"])
        v.id = UUID()
        let clean = try VenueYAML.encode(v)
        XCTAssertNoThrow(try CanonicalFormat.normalized(clean))
        let orphanAuthorized = clean.replacingOccurrences(of: "authorized:\n- Psychometrika", with: "authorized:\n- Elsewhere")
        XCTAssertNotEqual(orphanAuthorized, clean, "fixture：替換要命中")
        XCTAssertThrowsError(try CanonicalFormat.normalized(orphanAuthorized), "authorized ⊄ names 不得通過 fmt")
        let dirtyName = clean.replacingOccurrences(of: "- value: Psychometrika\n", with: "- value: 'Psychometrika '\n")
        XCTAssertNotEqual(dirtyName, clean, "fixture：替換要命中")
        XCTAssertThrowsError(try CanonicalFormat.normalized(dirtyName), "非 canonical 名字不得通過 fmt")
    }

    /// **`.organization` 分支與 `.person`／`.venue` 同一條紀律**（#554 R12 verify regression 第 32 列：三個同形的 shape 只修了兩個）。
    func testNormalizedRejectsSemanticallyInvalidOrganization() throws {
        var o = Organization(key: "iss", names: TimelineOf([TemporalValue(value: "Institute of Statistical Science")]))
        o.authorized = ["Institute of Statistical Science"]
        let clean = try OrganizationYAML.encode(o)
        XCTAssertNoThrow(try CanonicalFormat.normalized(clean))
        let orphan = clean.replacingOccurrences(of: "authorized:\n- Institute of Statistical Science", with: "authorized:\n- Elsewhere")
        XCTAssertNotEqual(orphan, clean, "fixture：替換要命中")
        XCTAssertThrowsError(try CanonicalFormat.normalized(orphan), "authorized ⊄ names 不得通過 fmt")
    }

    /// 語意合法的 person 照常正規化——不得因為加了驗證就把正常檔擋掉。
    func testNormalizedAcceptsValidPerson() throws {
        var person = Person(key: "someone", names: PersonNames(authorized: ["Real Name"],
                                                               variant: ["R. N."]))
        person.id = UUID()
        let yaml = try PersonYAML.encode(person)
        XCTAssertNoThrow(try CanonicalFormat.normalized(yaml))
    }
}
