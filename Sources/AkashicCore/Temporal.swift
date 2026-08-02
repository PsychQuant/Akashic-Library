import Foundation

/// Valid-time temporal 屬性（#20）。
///
/// ## 為什麼是「各屬性自帶時間軸」而不是「一段隸屬 = 一組快照」
///
/// 使用者拍板 (b)。理由在資料裡：**職級與行政職的變動頻率差一個數量級**。行政職
/// （所長 / 副所長）任期約 3 年，職級升等可能十年一次。把它們綁進同一個「快照」，
/// 每次行政職更替都要複製一份職級——複製出來的那份不是新事實，是同一個事實的第二個
/// 副本，而副本會走樣。
///
/// ## 為什麼 `end` 是 optional 而不是用一個哨兵日期
///
/// `nil` ＝ **仍在進行中**。用 `9999-12` 之類的哨兵會讓「現在還在」與「預計到 9999 年」
/// 無法區分，而且任何忘記處理哨兵的計算都會產生荒謬的區間長度。
///
/// ## 精度
///
/// 用**字串**而非 `Date`。來源資料是 `2003-01` 這種月精度，轉成 `Date` 得補一個
/// 不存在的「日」，之後就再也分不出「1 月」與「1 月 1 日」。字串保留來源的精度，
/// 比較用字典序（ISO 8601 的前綴特性讓它剛好正確）。
public struct DateRange: Equatable, Comparable {
    /// ISO 8601 前綴：`2003`、`2003-01`、`2003-01-15`。
    public var start: String?
    /// `nil` ＝ 仍在進行中（**不是**「未知」——未知請用 `note` 說明）。
    public var end: String?

    public init(start: String? = nil, end: String? = nil) {
        self.start = start
        self.end = end
    }

    /// 是否仍在進行中。
    public var isOpen: Bool { end == nil }

    /// 字典序比較（ISO 8601 前綴的排序 == 時間順序）。`nil` start 排最後——
    /// 沒有起點的區間放前面會讓時間軸從一個未知開始。
    public static func < (a: DateRange, b: DateRange) -> Bool {
        switch (a.start, b.start) {
        case let (l?, r?): return l < r
        case (nil, _?):    return false
        case (_?, nil):    return true
        case (nil, nil):   return false
        }
    }

    /// 兩個區間是否重疊。**開放區間（`end == nil`）視為延伸到無限遠。**
    public func overlaps(_ other: DateRange) -> Bool {
        // a 完全在 b 之前 → 不重疊
        func before(_ x: DateRange, _ y: DateRange) -> Bool {
            guard let xe = x.end, let ys = y.start else { return false }
            return xe < ys
        }
        return !before(self, other) && !before(other, self)
    }
}

/// 一段有時間範圍的屬性值。
///
/// `value` 是什麼由使用端決定——職級是 `"研究員"`、行政職是 `"所長"`、隸屬是機構名。
/// **不做 enum**：值域來自外部機構且會變（新職稱、新單位），寫死 enum 會讓一個新職稱
/// 變成需要改 code 的事，而它應該只是一個新字串。
public struct TemporalValue<V: Equatable & Comparable>: Equatable, Comparable {
    public var value: V
    public var range: DateRange
    /// 這一筆的來源（爬取的網址、信件、人工輸入）。**保留來源是 temporal 資料的
    /// 半條命**——沒有它，一筆與現況不符的歷史記錄無法判斷是舊事實還是錯誤。
    public var source: String?
    public var note: String?

    public init(value: V, range: DateRange = DateRange(),
                source: String? = nil, note: String? = nil) {
        self.value = value
        self.range = range
        self.source = source
        self.note = note
    }

    public static func < (a: TemporalValue<V>, b: TemporalValue<V>) -> Bool {
        a.range == b.range ? a.value < b.value : a.range < b.range
    }
}

/// 一條時間軸：同一個屬性的多段值。
///
/// **相等性不看儲存順序。** 時間軸是一個「段落的集合」——同樣的段落用不同順序寫進來
/// 是同一條時間軸。這一點被 `PersonYAML` 的 encode canary 抓出來：encode 排序輸出、
/// decode 照檔案順序讀回，若比較順序，任何未排序的輸入都會讓自檢誤判成「寫壞了」。
public struct TimelineOf<V: Equatable & Comparable>: Equatable {
    public var entries: [TemporalValue<V>]

    public init(_ entries: [TemporalValue<V>] = []) { self.entries = entries }

    public static func == (a: TimelineOf<V>, b: TimelineOf<V>) -> Bool { a.sorted == b.sorted }

    public var isEmpty: Bool { entries.isEmpty }

    /// 目前生效的值（`end == nil` 的最新一段）。多段同時開放時取 `start` 最晚的——
    /// 那是最近一次變更。
    public var current: TemporalValue<V>? {
        entries.filter(\.range.isOpen).max()
    }

    /// 依時間排序（穩定：同區間時按值排）。
    public var sorted: [TemporalValue<V>] { entries.sorted() }

    /// 重疊的段落。**回報而非拒絕**——重疊在真實資料裡可能是對的（一人同時兼兩個
    /// 行政職），也可能是錯的（爬取重複）。判斷屬於使用端，這裡只給事實。
    public func overlappingPairs() -> [(TemporalValue<V>, TemporalValue<V>)] {
        let s = sorted
        var out: [(TemporalValue<V>, TemporalValue<V>)] = []
        for i in s.indices {
            for j in s.index(after: i)..<s.endIndex where s[i].range.overlaps(s[j].range) {
                out.append((s[i], s[j]))
            }
        }
        return out
    }
}

/// Person 的機構與身分維度（#20）。**每個維度各自一條時間軸。**
///
/// ## `rank` 混三種語意的拆解（#20 的 scope 變更 3）
///
/// 來源資料的 `rank` 欄混了三件事，本結構把它們分開：
///
/// | 來源值 | 拆成 |
/// |---|---|
/// | `研究員` / `副研究員` / `助研究員` | `rank` |
/// | `研究員兼所長` | `rank: 研究員` + `administrative: 所長` |
/// | `兼任研究員` | `rank: 研究員` + `appointment: 兼任` |
///
/// 不拆的話，「歷任所長」這個查詢得對字串做子字串比對，而「兼任研究員」會被算成一種職級。
public struct PersonProfile: Equatable {
    /// 機構隸屬（可多段——實測資料裡有人兩段任期中間隔了 7 年）。
    ///
    /// **值是指涉或字面**，不是純字串：機構是世界裡的東西，它有身分、有歷史、
    /// 有東西指向它。純字串裝不下「這個名字指向誰」，於是「中央研究院」「中研院」
    /// 「Academia Sinica」在查詢時是三個不同的東西。未歸戶由 `.literal` 表達，
    /// **不加旗標欄位**——缺席本身就是資訊。
    public var affiliations: TimelineOf<OrgRef>
    /// 職級（升等時間軸）。
    public var ranks: Timeline
    /// 行政職。與職級**分離**——它是變動最頻繁的維度。
    public var administrative: Timeline
    /// 聘任類型（全職 / 兼任）。
    public var appointments: Timeline
    /// 研究領域（可多段、同時可多值）。
    public var fields: Timeline
    /// 聯絡資訊的變更歷史（office / phone / email / homepage）。
    public var contacts: [String: Timeline]

    public init(affiliations: TimelineOf<OrgRef> = TimelineOf(), ranks: Timeline = Timeline(),
                administrative: Timeline = Timeline(), appointments: Timeline = Timeline(),
                fields: Timeline = Timeline(), contacts: [String: Timeline] = [:]) {
        self.affiliations = affiliations
        self.ranks = ranks
        self.administrative = administrative
        self.appointments = appointments
        self.fields = fields
        self.contacts = contacts
    }

    public var isEmpty: Bool {
        affiliations.isEmpty && ranks.isEmpty && administrative.isEmpty
            && appointments.isEmpty && fields.isEmpty
            && contacts.allSatisfy { $0.value.isEmpty }
    }
}

/// 絕大多數維度（職級、行政職、聘任、研究領域、聯絡資訊）的值仍是純字串：
/// 值域來自外部且會變，寫死型別會讓一個新職稱變成需要改 code 的事。
/// 泛型化只為了讓**隸屬**能裝下指涉；其餘呼叫端逐字不變。
public typealias Timeline = TimelineOf<String>
