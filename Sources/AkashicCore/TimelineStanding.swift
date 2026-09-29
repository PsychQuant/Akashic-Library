/// 一條時間軸「現況怎麼說」——**唯一的推導**（#663）。
///
/// 在此之前這件事有四份：匯出端的 `researcherStatus`（#661），與 CLI、MCP、App 三個讀取面各自寫的
/// `current ?? latestPastSegment`。兩者對只被觀測到的隸屬（`attested`，#70）說不同的話：匯出說 `undetermined`
/// （被看到過不等於離開了），三個面說「曾隸屬」（一個離開的斷言）；混合情形（有 end 的段加上較晚的觀測段）
/// `latestPastSegment` 的分層規則讓有 end 的段勝過觀測段，三個面只剩「曾隸屬 NTU（2000–2010）」，2015 年在 ISS
/// 的觀測整個不見。`entity-backlink-completeness` 執行細節 2：一個讀取面只能有一條實作路徑。
///
/// ## 三個欄位各是一種不同的話
///
/// | 欄位 | 是什麼 | 措辭 |
/// |---|---|---|
/// | `current` | 開放的段（沒有 end、不是 ended-unknown、沒有觀測點）中最近的一段 | 「隸屬」 |
/// | `lastEnded` | 宣稱已結束的段（有已知 end，或 ended-unknown）中最近的一段 | 「曾隸屬」 |
/// | `lastObserved` | 只被觀測到的段（有觀測點、沒有 end）中最近的一段 | 「觀測到隸屬」——**不是**「曾隸屬」 |
///
/// **三者互不蘊含**：`lastObserved` 不代表結束（那是把被看到過誤當成離開了），也不代表現職（`isOpen` 的 #70
/// 裁決：有觀測不等於現況）。呼叫端各自決定要顯示哪幾個，但**不得**把 `lastObserved` 說成 `lastEnded`。
///
/// ## `status` 就是匯出端 `researcher.status`
///
/// 有現職 → `current`；沒有現職但有一段只被觀測到 → `undetermined`（混合情形也是——#661 刻意的保守裁決：
/// 較晚的觀測可能指出這個人還在）；其餘 → `retired`。**`undetermined` ⟺ 讀取面看得到 `lastObserved`**
/// （沒有現職時）——讀取面因此不需要另外打「未確定」的標籤，措辭本身就帶著它。
public struct TimelineStanding<V: Equatable & Comparable>: Equatable {
    /// 現況的三種說法。`rawValue` 是匯出端 `researcher.status` 的值。
    public enum Status: String, Sendable {
        case current
        case retired
        case undetermined
    }

    public let current: TemporalValue<V>?
    public let lastEnded: TemporalValue<V>?
    public let lastObserved: TemporalValue<V>?

    /// 由三個欄位導出，不另存——存了就是第二份會分岔的描述。
    public var status: Status {
        if current != nil { return .current }
        return lastObserved != nil ? .undetermined : .retired
    }
}

extension TimelineOf {
    /// 這條時間軸的現況。**沒有資料回 `nil`**——不猜成現職，也不猜成已結束（匯出端 `status` 因此是 NULL）。
    public var standing: TimelineStanding<V>? {
        isEmpty ? nil : TimelineStanding(current: current,
                                         lastEnded: latestEndedSegment,
                                         lastObserved: latestObservedSegment)
    }
}
