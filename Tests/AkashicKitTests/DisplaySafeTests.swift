import XCTest
@testable import AkashicCore

/// `displaySafe` 的 regression（R11，R10-verify M18/M19）。
///
/// store 檔案依 #23 的前提可能由別的 binary / 別人 / Dropbox 同步寫入，
/// 未知欄位的 key 與 quarantine reason 都是**未信任內容**。v1.2 時
/// `rejectUnknownKeys` 會先擋掉，v1.3 把它移到 happy path——顯示層因此
/// 需要自己的消毒。
final class DisplaySafeTests: XCTestCase {

    /// 終端跳脫序列：libyaml 擋輸入串流的裸 C0，但不擋 double-quoted scalar
    /// 的跳脫序列——`"\e[2J"` 解碼後就是真的 ESC。
    func testEscapeSequencesNeutralised() {
        let hostile = "\u{1B}[2J\u{1B}[1;31mPWNED\nquarantined: 99 files\u{1B}[0m"
        let safe = displaySafe(hostile)
        XCTAssertFalse(safe.unicodeScalars.contains { $0.value == 0x1B }, "不得殘留真 ESC")
        XCTAssertFalse(safe.contains("\n"), "不得殘留真換行（否則可偽造報告行）")
        XCTAssertTrue(safe.contains("\\u{001B}"), "應轉成可辨識的字面表示：\(safe)")
        XCTAssertTrue(safe.contains("PWNED"), "可見內容仍應保留，讓人看得出這裡有怪東西")
    }

    /// 換行是偽造報告行的載體——單獨釘住。
    func testNewlineNeutralised() {
        XCTAssertEqual(displaySafe("a\nb"), "a\\u{000A}b")
    }

    /// C1 與 bidi-override（Trojan-Source 家族）同樣中和。
    func testC1AndBidiOverrideNeutralised() {
        XCTAssertFalse(displaySafe("x\u{85}y").contains("\u{85}"))
        XCTAssertFalse(displaySafe("x\u{202E}y").unicodeScalars.contains { $0.value == 0x202E })
    }

    /// 長度上限：Yams 錯誤字串會展開成出錯那一行的逐字內容且不截斷；
    /// MCP 情境下那是直接灌進 LLM context 的無上限字串。
    func testTruncation() {
        let long = String(repeating: "a", count: 5000)
        let safe = displaySafe(long, max: 100)
        XCTAssertTrue(safe.hasSuffix("…（已截斷）"))
        XCTAssertLessThan(safe.count, 130)
    }

    /// **反向**：正常內容（含 CJK、emoji、期刊名裡的 `&`）不得被動到。
    func testOrdinaryContentUntouched() {
        for s in ["journaltitle", "Sociological Methods & Research",
                  "中文標題", "emoji 🎉 ok", "*Achievement *Mind"] {
            XCTAssertEqual(displaySafe(s), s, "不得改動正常內容：\(s)")
        }
    }

    /// 空字串與剛好等於上限的邊界。
    func testBoundaries() {
        XCTAssertEqual(displaySafe(""), "")
        let exact = String(repeating: "b", count: 50)
        XCTAssertEqual(displaySafe(exact, max: 50), exact, "剛好等於上限不應加截斷標記")
    }

    // MARK: - R12 補：R11 版本的三個實測缺陷

    /// **grapheme cluster 繞過**（R12 M13/M16）：R11 版逐 Character 檢查預算，
    /// 而一個 cluster 可含無上限的 combining mark——實測 `"a" + 50,000 個 U+0301`
    /// 在 max:200 下原樣通過。預算必須以 unicode scalar 計。
    func testGraphemeClusterCannotBypassBudget() {
        let bomb = "a" + String(repeating: "\u{0301}", count: 50_000)
        XCTAssertEqual(bomb.count, 1, "前提：這是單一 grapheme cluster")
        let safe = displaySafe(bomb, max: 200)
        XCTAssertLessThan(safe.unicodeScalars.count, 300,
                          "預算必須以 scalar 計，實得 \(safe.unicodeScalars.count)")
        XCTAssertTrue(safe.hasSuffix("…（已截斷）"))
    }

    /// **LS/PS**（R12 M14）：U+2028/U+2029 在 SwiftUI Text 與 JSON→JS/LLM
    /// context 都是換行——「不得殘留真換行」的不變式原本在那兩個 sink 上被繞過。
    func testLineAndParagraphSeparatorNeutralised() {
        for u in ["\u{2028}", "\u{2029}"] {
            let safe = displaySafe("a\(u)quarantined: 0 files")
            XCTAssertFalse(safe.unicodeScalars.contains { $0.value == 0x2028 || $0.value == 0x2029 },
                           "LS/PS 必須中和：\(safe)")
        }
    }

    /// 方向標記與 BOM（Trojan-Source 家族較弱的一半）。
    func testDirectionalMarksAndBOMNeutralised() {
        for v: UInt32 in [0x200E, 0x200F, 0x061C, 0xFEFF] {
            let ch = String(UnicodeScalar(v)!)
            XCTAssertFalse(displaySafe("a\(ch)b").unicodeScalars.contains { $0.value == v },
                           "U+\(String(format: "%04X", v)) 必須中和")
        }
    }

    /// **反斜線自身要跳脫**（R12）：否則內容裡的字面 `\u{001B}` 與本函式的輸出
    /// 無法區分，消毒後的字串反而可被偽造。
    func testBackslashEscapedSoOutputCannotBeForged() {
        let forged = "\\u{001B}[2J"          // 使用者內容裡的字面文字，不是真 ESC
        let safe = displaySafe(forged)
        XCTAssertTrue(safe.hasPrefix("\\u{005C}"), "反斜線應被跳脫：\(safe)")
    }
}
