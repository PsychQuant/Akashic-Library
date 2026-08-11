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
/// `nil` ＝ **仍在進行中**（除非另標 `endedUnknown`——「已結束、時點未知」是第三個
/// 一等狀態，#63）。用 `9999-12` 之類的哨兵會讓「現在還在」與「預計到 9999 年」
/// 無法區分，而且任何忘記處理哨兵的計算都會產生荒謬的區間長度。
///
/// ## 精度
///
/// 用**字串**而非 `Date`。來源資料是 `2003-01` 這種月精度，轉成 `Date` 得補一個
/// 不存在的「日」，之後就再也分不出「1 月」與「1 月 1 日」。字串保留來源的精度，
/// 比較用字典序（ISO 8601 的前綴特性讓它剛好正確）。
public struct DateRange: Equatable, Hashable, Comparable, Sendable {
    /// ISO 8601 前綴：`2003`、`2003-01`、`2003-01-15`。
    public var start: String?
    /// `nil` 且未標 `endedUnknown` ＝ 仍在進行中（**不是**「未知」）。
    /// 「已結束、時點未知」用 `endedUnknown`（#63）——那是一等的知識狀態，
    /// 不是髒資料；塞 `note` 不參與計算、捏日期是偽造。
    public var end: String?
    /// **已結束，但結束日期未知**（#63）。43 位退休 PI 只有「已退休」的事實、
    /// 沒有年份——`end: nil` 的既有語意（進行中）會把整批算成現職。
    /// `end` 有值時本欄位無意義（decode 拒絕矛盾組合）。
    /// **non-additive，format 6**：看似 additive 其實不是——tolerant-preserve 的
    /// 開放層只涵蓋記錄頂層與 `akashic` namespace，時間軸**段內**的鍵是 strict，
    /// 舊 binary 讀到本欄位是整檔 quarantine（人檔消失）而非保留（#74 判準的
    /// 實際教訓：判 additive 前先確認新鍵落在哪一層）。
    public var endedUnknown: Bool
    /// **觀測點列表**（#70）：「這幾個時點觀測到成立」——起訖皆不明時的一等知識
    /// 狀態，`ended`（#63）的鏡像。把發表年填 `start` 是「從那年起」的偽造斷言；
    /// 同人同機構 5 篇論文＝5 個觀測點，各點日後可掛 #66 的 reference 逐點溯源。
    /// 非空時 `start`／`end`／`endedUnknown` **必須**全缺席（encode/decode 拒矛盾）。
    /// **non-additive，format 7**：段內鍵是 strict（#63/#74 判準），舊 binary 讀到
    /// 即整檔 quarantine——write gate 對 format < 7 拒寫。
    public var attested: [String]

    public init(start: String? = nil, end: String? = nil, endedUnknown: Bool = false,
                attested: [String] = []) {
        self.start = start
        self.end = end
        self.endedUnknown = endedUnknown
        self.attested = attested
    }

    /// 是否仍在進行中——`current`／status 推導的根。
    /// attested-only 段不是進行中：有觀測不等於現況（#70）。
    public var isOpen: Bool { end == nil && !endedUnknown && attested.isEmpty }

    /// 字典序比較（ISO 8601 前綴的排序 == 時間順序）。`nil` start 排最後——
    /// 沒有起點的區間放前面會讓時間軸從一個未知開始。
    ///
    /// **必須是全序**（#100 系列，#131 verify F5）：`==` 看整個 range，`<` 若只比
    /// `start`，「同 start 不同 end」的兩段就互不相等又互不可比——`sorted` 不再是
    /// 它自稱的全序，`TimelineOf.==`（`a.sorted == b.sorted`）在這類段上變回順序
    /// 敏感，靠的只剩 Swift sort 對 incomparable 元素的**未文件化**穩定性——正是
    /// 本檔在 #69 拒絕依賴的那個性質。所以 start 之後比 end：具體日期（字典序）
    /// < 已結束未知（#63）< 進行中——這是全序的技術決定而非時間語意的斷言，但
    /// 順位可解釋：進行中的 end 對應 +∞ 理應最後，endedUnknown 已結束、只是不知
    /// 何時。三欄位比完仍平手 ⟺ 相等（synthesized `==` 的三個欄位正是這三個）。
    public static func < (a: DateRange, b: DateRange) -> Bool {
        if a.start != b.start {
            switch (a.start, b.start) {
            case let (l?, r?): return l < r
            case (nil, _):     return false
            case (_, nil):     return true
            }
        }
        // end 三態順位：0 = 具體日期、1 = 已結束未知、2 = 進行中（+∞）。
        // `endedUnknown` 也入 rank（#143 verify F1）：`end != nil` 時曾一律 rank 0，
        // 「同 start 同 end、不同 endedUnknown」的矛盾 in-memory 組合（encode/decode
        // 兩端都拒收，但 struct 公開可寫、構造得出來）互不可比又 !=——正是本修復
        // 要消滅的失敗模式。型別自己成立，比靠邊界守衛成立更穩。
        func endRank(_ r: DateRange) -> Int {
            if r.end != nil { return r.endedUnknown ? 1 : 0 }
            return r.endedUnknown ? 2 : 3
        }
        guard endRank(a) == endRank(b) else { return endRank(a) < endRank(b) }
        if let ae = a.end, let be = b.end, ae != be { return ae < be }
        // attested 也入序（#70；#143 的教訓：synthesized == 的**每個**欄位 < 都要
        // 比，否則 incomparable ⟹ equal 的全序性質破掉）。字典序陣列比較。
        if a.attested != b.attested {
            return a.attested.lexicographicallyPrecedes(b.attested)
        }
        return false   // 四欄位全等 → 相等
    }

    /// 兩個區間是否重疊。**無端點的區間（`end == nil`，含 `endedUnknown`）視為
    /// 延伸到無限遠**——已結束但不知何時＝無從排除重疊，保守多報、交由人工裁決。
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

    /// 依時間排序（全序：同區間時按值排）。**供相等性使用**——`==` 定義為
    /// `a.sorted == b.sorted`，要讓「同樣的段落、不同的儲存順序」判為相等就必須是全序，
    /// 因此需要在 `range` 相同時以 `value` 決勝。
    ///
    /// **不要拿它當序列化順序**（#69）。序列化用 `inSerializationOrder`。
    public var sorted: [TemporalValue<V>] { entries.sorted() }

    /// 序列化順序：**依 `range` 排序，`range` 相同時保留寫入順序**（#69）。
    ///
    /// 與 `sorted` **並存且互不呼叫**。兩者是不同的函式，沒有必須共用比較器的理由：
    /// 相等性需要全序才能成立，序列化需要的只是「時間有話說時照時間排」。
    ///
    /// 分開之前，序列化是**順便繼承**相等性的比較器——沒有人決定過「檔案裡也要按字串
    /// 排」。後果在沒有日期的時間軸上顯現：`Organization.names` 三筆全部無 `range`，
    /// 排序完全由 `value` 決勝，於是主名（中文正式名）被推到英文名之後。工具每次把它
    /// 推到後面、人每次改回來，最後沒人執行正規化。
    ///
    /// **穩定性顯式構造，不依賴 `sorted()`**：Swift 標準函式庫未承諾排序穩定（現行為
    /// timsort，實務上穩定但非文件保證）。這裡以原始索引裝飾後比較，比較器本身即是
    /// 嚴格全序，穩定與否無關緊要——依賴未文件化的行為屬於「今天能跑、升版就壞」。
    ///
    /// **代價（明確接受）**：失去「一個值只有一種位元組表示」。兩個 `==` 成立的
    /// timeline 若 `entries` 順序不同，會寫出不同位元組。查證確認 store 內沒有任何機制
    /// 對 entity YAML 做內容雜湊（`sources/` 走內容定址，entities 走 UUID 定址），
    /// 因此此性質目前沒有依賴者。
    ///
    /// **冪等性不受影響**：序列化是 `entries` 陣列的純函式，decode 保留陣列順序，
    /// 故 `fmt(fmt(x)) == fmt(x)`。
    public var inSerializationOrder: [TemporalValue<V>] {
        entries.enumerated()
            .sorted { a, b in
                a.element.range == b.element.range
                    ? a.offset < b.offset
                    : a.element.range < b.element.range
            }
            .map(\.element)
    }

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

    /// 任一段標了 `endedUnknown`（#63 的 v6-only 語法）——寫入端的 format gate 用。
    /// 任何維度帶 attested 段（#70 的 v7 gate 用，與 `usesEndedUnknown` 同型）。
    public var usesAttested: Bool {
        let all: [Timeline] = [ranks, administrative, appointments, fields]
            + Array(contacts.values)
        return affiliations.entries.contains { !$0.range.attested.isEmpty }
            || all.contains { $0.entries.contains { !$0.range.attested.isEmpty } }
    }

    public var usesEndedUnknown: Bool {
        affiliations.entries.contains(where: \.range.endedUnknown)
            || ([ranks, administrative, appointments, fields] + Array(contacts.values))
                .contains { $0.entries.contains(where: \.range.endedUnknown) }
    }
}

/// 絕大多數維度（職級、行政職、聘任、研究領域、聯絡資訊）的值仍是純字串：
/// 值域來自外部且會變，寫死型別會讓一個新職稱變成需要改 code 的事。
/// 泛型化只為了讓**隸屬**能裝下指涉；其餘呼叫端逐字不變。
public typealias Timeline = TimelineOf<String>
