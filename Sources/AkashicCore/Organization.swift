import Foundation

/// 對某個機構的指涉，或一段尚未歸戶的字面文字。
///
/// 形狀刻意與 `Author` 相同（`.key` / `.literal`）——那是本專案已經解過一次的同型問題，
/// 而 `RelationalExport` 已經記下理由：**不需要「是否已歸戶」的旗標欄位，缺席本身就是資訊**。
/// 兩個欄位可以互相矛盾，一個 sum type 不會。
public enum OrgRef: Equatable, Comparable {
    /// 指向一筆 organization 記錄的 key。
    case key(String)
    /// 尚未歸戶的機構名稱原文。**這是合法的長期狀態**，不是待清理的髒資料（§8）。
    case literal(String)

    public var displayName: String {
        switch self {
        case .key(let k): return k
        case .literal(let s): return s
        }
    }

    /// 排序用。`.key` 排在 `.literal` 前面——已歸戶的先出現，讓未歸戶的集中在尾端好處理。
    public static func < (a: OrgRef, b: OrgRef) -> Bool {
        switch (a, b) {
        case (.key(let x), .key(let y)):         return x < y
        case (.literal(let x), .literal(let y)): return x < y
        case (.key, .literal):                   return true
        case (.literal, .key):                   return false
        }
    }
}

/// 機構（`entities/<uuid>.yaml`，形狀標籤 `organization:`）。
///
/// ## 為什麼它是第三種形狀
///
/// 它通過 §11 的必要條件：它決定了哪些欄位存在。機構沒有 citekey、沒有作者、沒有職級；
/// 它有成立年、上級機構、名稱變體。載入器為它分岔到不同的 decoder，所以它是形狀，
/// 不是某個既有形狀的一個屬性值。
///
/// ## identity 欄位就叫 `key`，與 person 同名
///
/// 這在形狀改用裸標籤之前是不可行的——當時形狀要靠欄位組成判別，同名的 identity 欄位
/// 會讓兩個形狀無法區分，於是必須發明 `orgkey` 之類的名字。改用標籤之後，判別由標籤負責，
/// `key` 得以回歸單一職責：一個實體的人類可讀鍵。**不必為了判別而扭曲欄位命名。**
public struct Organization: Equatable {
    /// 不變的機器身分。
    public var id: UUID
    /// 人類可讀鍵（`StoreKey` 規則）。
    public var key: String
    /// 名稱變體與各自的效期（改名、多語言、縮寫）。時間軸而非單值，因為
    /// **改名之後舊記錄仍指向同一個 identity**——名稱是可變描述，不是身分。
    public var names: TimelineOf<String>
    /// 對外可稱呼的名稱（#81）：從**當前有效**的名稱中指定，每個書寫系統至多一個。
    ///
    /// 與 `names` 的時間軸正交——改名記在時間軸上，「哪個名稱對外」記在這裡。空集合
    /// 合法，意思是還沒指定，此時 `displayName` 退回當前有效名稱。
    public var authorized: [String]
    /// 成立時間（ISO 8601 前綴，保留來源精度）。
    public var founded: String?
    /// 解散時間。`nil` ＝ 仍存續（**不是**未知）。
    public var dissolved: String?
    /// 上級機構的時間軸（統計所 → 中研院）。
    ///
    /// **這與人的隸屬刻意不共用型別。** 中文的「隸屬」與英文的 `affiliation` 在表層
    /// 文法上是同一個詞，深層文法卻是兩個 predicate：人與機構之間是**僱用／成員**關係
    /// （有任期、可中斷、可重複），機構與機構之間是**部分—整體**（通常隨機構存續）。
    /// 抽出一個共用的「隸屬關係」型別就是把兩個定義域攤平，等同於通用邊表的縮小版
    /// （§7 的 predicate 定義域規則）。表層文法相同不構成它們是同一個 predicate 的證據。
    public var parents: TimelineOf<OrgRef>
    public var note: String?
    /// 較新版本寫入、本 binary 不認得的欄位（§5 tolerant-preserve）。
    public var unknownFields: [UnknownField]

    public init(key: String, names: TimelineOf<String> = Timeline(),
                authorized: [String] = [],
                founded: String? = nil, dissolved: String? = nil,
                parents: TimelineOf<OrgRef> = TimelineOf(),
                note: String? = nil, id: UUID? = nil,
                unknownFields: [UnknownField] = []) {
        self.key = key
        self.names = names
        self.authorized = authorized
        self.founded = founded
        self.dissolved = dissolved
        self.parents = parents
        self.note = note
        self.id = id ?? DeterministicUUID.forOrganization(key: key)
        self.unknownFields = unknownFields
    }

    /// Schema 驗證（#81 起）。
    ///
    /// **`Validate` 子命令原本完全沒有走訪 organizations**——機構記錄從來沒有被驗證過。
    /// 加 `authorized` 的同時補上這個缺口，並與 person 對齊（key 格式 + 未知欄位 +
    /// 對外名字不變式），否則不變式只在型別層成立、使用層不成立。
    public func validate() -> [ValidationIssue] {
        var issues: [ValidationIssue] = []
        if !StoreKey.isValid(key) {
            issues.append(ValidationIssue(
                severity: .error,
                message: "organization key '\(displaySafe(key, max: 120))' 不符合 \(StoreKey.pattern)"))
        }
        issues += AuthorizedNames.validate(authorized: authorized,
                                           names: names.entries.map(\.value), ownerKey: key)
        for f in unknownFields {
            issues.append(ValidationIssue(severity: .warning,
                message: "未知欄位「\(displaySafe(f.key, max: 120))」——可能由較新版本寫入（已保留；升級 binary 或檢查 typo）"))
        }
        return issues
    }

    /// 目前生效的顯示名稱（`end == nil` 的最新一段）；沒有時間軸資訊時回 key。
    public var displayName: String { displayName(in: nil) }

    /// 對外可稱呼的名稱（#81）。比 person 多一階：
    ///
    /// 1. `authorized` 中書寫系統相符者
    /// 2. 任一 `authorized`
    /// 3. **當前有效名稱**（`names.current`）
    /// 4. `key`
    ///
    /// 第 3 階保留而 person 沒有，是因為它**不是位置式**——它是對名稱時間軸的查詢，
    /// 有明確語意（「現在叫什麼」）。被廢除的是「陣列第 0 個」那種沒有語意的位置。
    public func displayName(in script: WritingSystem?) -> String {
        if let script, let hit = authorized.first(where: { WritingSystem.of($0) == script }) {
            return hit
        }
        return authorized.first ?? names.current?.value ?? key
    }
}
