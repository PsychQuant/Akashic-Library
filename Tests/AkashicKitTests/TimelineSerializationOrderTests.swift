import XCTest
import Foundation
@testable import AkashicCore

/// #69：序列化順序由**時間**決定，不由值決定。
///
/// `TimelineOf.sorted` 目前同時承擔兩個互不相干的職責：
///
/// 1. **相等性的正規化** — `TimelineOf.==` 定義為 `a.sorted == b.sorted`。要讓
///    「同樣的段落、不同的儲存順序」判為相等，`sorted` 必須是**全序**，因此需要在
///    `range` 相同時以 `value` 決勝。
/// 2. **序列化的輸出順序** — `PersonYAML.timelineNode` 與 `orgTimelineNode` 直接吃
///    `t.sorted`。
///
/// 職責 2 是**順便繼承**職責 1 的比較器——沒有人決定過「檔案裡也要按字串排」。後果在
/// 沒有日期的時間軸上顯現：`Organization.names` 三筆全部無 `range`，排序完全由 `value`
/// 決勝，於是主名（中文正式名）被推到英文名之後。
///
/// **測試透過 encoder 的輸出而非內部存取點**：契約是「寫出去的位元組長什麼樣」，
/// 不是「哪個 property 被呼叫」。釘住存取點名稱會讓實作重構誤報成回歸。
final class TimelineSerializationOrderTests: XCTestCase {

    /// 從 encode 出來的 YAML 抽出某個 timeline 區塊裡的 value 順序。
    ///
    /// 走文字而非重新 decode：decode 會把順序丟進 `entries` 陣列，再問它等於在問
    /// decoder 而不是問**檔案**。這個測試要斷言的正是檔案裡的順序。
    /// **縮排無關**：`Person` 的 timeline 住在 `profile:` 底下（2 空格），`Organization`
    /// 的 `names` 在頂層（0 空格）。寫死縮排的第一版對 org 直接回空陣列——測試因此
    /// 「失敗」，但失敗的理由是 parser 壞了而不是順序錯，修好之後也一樣會紅。
    private func valueOrder(inYAML yaml: String, section: String,
                            file: StaticString = #filePath, line: UInt = #line) -> [String] {
        let lines = yaml.components(separatedBy: "\n")
        guard let head = lines.firstIndex(where: {
            $0.trimmingCharacters(in: .whitespaces) == "\(section):"
        }) else {
            XCTFail("YAML 裡找不到「\(section):」區塊——測到的不是這條路徑：\n\(yaml)",
                    file: file, line: line)
            return []
        }
        let sectionIndent = lines[head].prefix { $0 == " " }.count
        var out: [String] = []
        for raw in lines[(head + 1)...] {
            let t = raw.trimmingCharacters(in: .whitespaces)
            if t.isEmpty { continue }
            // 同層或更淺**且不是本區塊的項目** → 區塊結束
            if raw.prefix(while: { $0 == " " }).count <= sectionIndent, !t.hasPrefix("-") { break }
            if t.hasPrefix("- value:") {
                out.append(String(t.dropFirst("- value:".count))
                    .trimmingCharacters(in: .whitespaces))
            }
        }
        return out
    }

    // MARK: - 有日期時：照時間

    /// design「排序行為的判準」第 1 列：兩段都有 `range` → 依時間先後。
    func testDatedEntriesWriteChronologically() throws {
        var p = Person(key: "cheng", names: ["C"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "研究員", range: DateRange(start: "2013-07")),
            TemporalValue(value: "助研究員", range: DateRange(start: "2003-01", end: "2013-06")),
        ])
        let yaml = try PersonYAML.encode(p)
        XCTAssertEqual(valueOrder(inYAML: yaml, section: "ranks"), ["助研究員", "研究員"],
                       "有日期時必須照時間先後，早的在前：\n\(yaml)")
    }

    // MARK: - 無日期時：保留寫入順序

    /// design「排序行為的判準」第 2 列：全部無 `range` → 保留寫入順序。
    ///
    /// 這是本 change 的動機案例。現行實作由 `value` 決勝，於是中文正式名被英文名擠到後面
    /// ——工具每次把主名推到後面，人每次改回來，最後沒人執行正規化。
    func testUndatedEntriesKeepHeldOrder() throws {
        let names = ["中央研究院", "Academia Sinica", "中研院"]
        let org = Organization(key: "academia-sinica",
                               names: Timeline(names.map { TemporalValue(value: $0) }))
        let yaml = try OrganizationYAML.encode(org)
        XCTAssertEqual(valueOrder(inYAML: yaml, section: "names"), names,
                       "全部無日期時必須保留寫入順序，不得由值決勝：\n\(yaml)")
    }

    /// design「排序行為的判準」第 3 列：有日期的排在無日期的前面。
    ///
    /// 沿用 `DateRange.<` 對 `nil` 的既有處理（無 `start` 排最後）。**不改那個決定**
    /// ——另一種讀法（「不知道何時，可能很早」→ 排最前）與 `end: nil` 的語意歧義同源，
    /// 屬 #63 的範圍。
    func testUndatedEntriesFollowDatedOnes() throws {
        var p = Person(key: "cheng", names: ["C"])
        p.profile.ranks = Timeline([
            TemporalValue(value: "B-無日期"),
            TemporalValue(value: "A-有日期", range: DateRange(start: "2000")),
        ])
        let yaml = try PersonYAML.encode(p)
        XCTAssertEqual(valueOrder(inYAML: yaml, section: "ranks"), ["A-有日期", "B-無日期"],
                       "有日期的必須排在無日期的前面：\n\(yaml)")
    }

    // MARK: - 迴歸哨兵

    /// design 的 requirement「Equality remains blind to storage order」。
    ///
    /// **這個測試從一開始就該通過**——它是哨兵不是新功能。序列化順序改掉之後，
    /// 相等性必須**原封不動**：`TimelineOf.==` 仍是 `a.sorted == b.sorted`，而 `sorted`
    /// 仍是全序。任何把序列化順序誤接到 `==` 的改動都會讓它變紅。
    func testEqualityStillIgnoresStorageOrder() {
        let a = TemporalValue(value: "x", range: DateRange(start: "2000"))
        let b = TemporalValue(value: "y", range: DateRange(start: "2010"))
        XCTAssertEqual(Timeline([a, b]), Timeline([b, a]),
                       "同樣的段落、不同的儲存順序，仍是同一條時間軸")
    }
}
