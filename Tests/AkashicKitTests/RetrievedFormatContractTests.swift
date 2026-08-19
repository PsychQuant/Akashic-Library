import XCTest
@testable import AkashicCore

/// `retrieved` 的格式契約（#262 裁決二）。
///
/// **契約**：`retrieved` MUST 是 ISO 8601 且帶 UTC offset（`2026-08-19T14:30:00+08:00`）。
///
/// 裸日期（`2026-08-19`）不合契約：它被讀成什麼時刻取決於讀的人在哪個時區，而 provenance
/// 的用途正是「在什麼時候看到的」——**一個會隨讀者漂移的時刻答不了那個問題**。全域規則
/// 對此有具名的踩坑實例（無 offset 的時間值被當成 UTC 解讀，實際生效時間差 8 小時）。
///
/// ## 這一組**刻意不**讓契約成為 decode 的硬閘
///
/// 實測 store 的 `index.jsonl` 有 **7 條** `retrieved`，**全部是裸日期**。若把契約做成
/// decode 端拒讀，那 7 條會讓整個 store 讀不進來——**用一條新契約把既有資料鎖在門外**，
/// 而那些資料本身沒有任何問題（只是格式較舊）。
///
/// 這是 `no-compat-fallback` 的例外判準所指的情形：「一次改不完（資料在別人手上、
/// 遷移需要人判斷）」。所以契約先以**可驗證的函式 ＋ 文件**存在，回填是資料工作；
/// 硬閘等回填完成後再上（退場條件見下）。
///
/// **退場條件**：當 store 的 `index.jsonl` 全部條目都帶 offset 時，把
/// `ProvenanceReference` 的 decode 改成拒讀裸日期，並刪掉本 doc 的這一段。量測：
///
/// ```bash
/// python3 -c "import json,sys; [print(json.loads(l).get('retrieved')) for l in open('$HOME/.akashic/sources/index.jsonl')]" | grep -cv '+\|Z'
/// ```
///
/// 回 0 即可上硬閘。
final class RetrievedFormatContractTests: XCTestCase {

    /// 契約的可執行形式。**這是唯一的判定實作**——文件、CLI 提示、日後的 decode 硬閘
    /// 都該呼叫它，不各自寫一份 regex（兩份會分岔）。
    static func isContractCompliant(_ retrieved: String) -> Bool {
        // ISO 8601 且帶 offset：`±HH:MM`、`±HHMM`，或 `Z`（UTC 的合法寫法）。
        // 只驗**有沒有 offset**，不驗日期本身合不合法——後者是 ISO 解析器的職責，
        // 而這裡要抓的是「時刻會隨讀者漂移」這一件事。
        let pattern = #"\AT?\d{4}-\d{2}-\d{2}T\d{2}:\d{2}(:\d{2})?([+-]\d{2}:?\d{2}|Z)\z"#
        return retrieved.range(of: pattern, options: .regularExpression) != nil
    }

    func testOffsetBearingFormsAreCompliant() {
        for s in ["2026-08-19T14:30:00+08:00",
                  "2026-08-19T14:30:00Z",
                  "2026-08-19T14:30+08:00",
                  "2026-08-19T06:30:00-05:00",
                  "2026-08-19T14:30:00+0800"] {
            XCTAssertTrue(Self.isContractCompliant(s), "\(s) 應合契約")
        }
    }

    /// **裸日期不合契約**——這是本契約唯一要防的形狀，也是實測 7/7 條的現況。
    func testBareDatesAreNotCompliant() {
        for s in ["2026-08-19", "2026-07-19", "2026-08-04"] {
            XCTAssertFalse(Self.isContractCompliant(s),
                           "\(s) 是裸日期，被讀成什麼時刻取決於讀的人在哪個時區")
        }
    }

    /// 有時刻但**沒有 offset** 同樣不合 —— 那是最容易誤以為「已經夠精確」的形狀。
    ///
    /// 全域規則記載的踩坑實例正是這個：`2027-02-01T00:00:00` 沒有 offset，被當成 UTC
    /// 解讀，實際生效時間比預期晚 8 小時。**加了時分秒不等於加了時區。**
    func testTimestampsWithoutOffsetAreNotCompliant() {
        for s in ["2026-08-19T14:30:00", "2026-08-19T14:30"] {
            XCTAssertFalse(Self.isContractCompliant(s),
                           "\(s) 有時刻但無 offset——加了時分秒不等於加了時區")
        }
    }

    /// **契約不是 decode 的硬閘**（暫時）：裸日期仍讀得進來。
    ///
    /// 沒有這條，日後有人「順手」把契約接上 decode 就會讓既有 7 條把整個 store 鎖在門外，
    /// 而那個後果在測試裡看不到（測試用的是自己造的資料，不是真 store）。
    func testBareDateStillDecodesForNow() throws {
        let ref = try ProvenanceReference(
            field: "authors", value: nil,
            url: "https://example.org/x", retrieved: "2026-08-04",
            status: 200, mediaType: "text/html",
            content: "sha256:" + String(repeating: "a", count: 64),
            judgement: nil, restsOn: [])
        XCTAssertNotNil(ref, "裸日期目前仍須可讀——回填完成前不得上硬閘")
    }
}
