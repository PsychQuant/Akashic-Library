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
}
