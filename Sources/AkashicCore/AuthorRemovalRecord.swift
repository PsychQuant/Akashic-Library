import Foundation

/// 作者位**移除**記錄的 statement 文法——**單一解析器**（#457）。
///
/// ## 為什麼需要它
///
/// `Author` 的三態（`.key`／`.organization`／`.literal`，#323）假設每個作者位背後都有一個
/// 作者。實測（2026-09-09，全庫 3,885 個 distinct literal）有一個不是：PsycInfo 的佔位字串
/// **`No authorship indicated`**，21 筆，全部只有那一個作者位。
///
/// 它今天的代價不是「還沒歸戶」，是**出貨的參考文獻裡有一個被捏造出來的人**：
///
/// ```bibtex
/// AUTHOR = {indicated, No authorship},
/// ```
///
/// citekey 也是照它生的（`indicated2002bpsychological` 一族）。APA7 §9.12 對無署名作品的
/// 處置是**以標題起首**，而那要求作者位是空的——不是裝一個說「沒有作者」的字串。
///
/// 在此之前**沒有任何面移除得了一個作者位**：`apply` 升格、`attribute_org` 改歸屬、
/// `split_author` 增加數量、`un_split` 減少到 1，沒有一個能到 0。唯一的路是手改 YAML
/// ——`mcp-cli-parity` 的識別碼那一節記著那條路 2026-08-28 差點弄丟一筆 DOI。
///
/// ## 形狀取自 #450
///
/// `Entry.references` 收一筆 `{field: authors, value: <被移除的 literal 逐字>,
/// judgement: "移除：<理由>", rests-on: []}`。與拆分記錄同住 `field: authors`——兩者的語意
/// 相同（**value 是已退役的值**），差別只在退役之後留下幾段：拆分留 N ≥ 2 段，移除留 0 段。
///
/// **為什麼不重用 `SplitRecordValue`**：它的 `init?` 要求段數 ≥ 2，而放寬到 0 會讓
/// `unsplitAuthors` 把一個「移除」讀成可還原的拆分並把字串塞回作者位——那正好是本面要
/// 消除的東西。兩種記錄要在文法上就分得開，不是靠呼叫端記得檢查（`entity-backlink-completeness`
/// 引 3.325 的同一個立場：讓錯誤在記法裡寫不出來）。
///
/// ## 誠實邊界：沒有具名逆操作
///
/// `split_author` 的逆是 `un_split`（#513），而**本面沒有**。理由不是「還沒做」：
/// 還原需要知道被移除的位置，而記錄**刻意不存索引**——拆分記錄同樣不存，理由已在
/// `unsplitAuthors` 寫下（「以值定位……索引在同一批的前一次還原之後會位移」）。
/// 移除之後作者位裡什麼都不剩，所以連「以值定位」都無從施力。
///
/// 被移除的字串逐字留在記錄的 `value` 裡，所以**資訊沒有丟**（`lossless-intake`）；
/// 缺的是把它放回**原位**的能力。真的出現要還原的需求時，那是一次顯式裁決
/// （要不要在文法裡加位置，以及位置過期時怎麼辦），不由本型別預先決定。
///
/// 文法：`移除：理由`——前綴 `移除`、全形 `：` 之後為理由、理由（trim 後）非空。
public struct AuthorRemovalRecordValue: Equatable, Sendable {
    public static let prefix = "移除"
    /// 全形冒號——與 `SplitRecordValue` 同一個分隔符，理由內的 ASCII `:` 與全形 `：` 都不再解讀。
    public static let reasonSeparator: Character = "："

    public let reason: String

    /// 回 nil＝這個理由寫不成合法的 statement（trim 後為空）。
    public init?(reason: String) {
        let trimmed = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        self.reason = trimmed
    }

    public var encoded: String { Self.prefix + String(Self.reasonSeparator) + reason }

    /// 回 nil＝不是移除記錄（可能是拆分記錄，也可能是 malformed——呼叫端合起來判斷）。
    public static func parse(_ statement: String) -> AuthorRemovalRecordValue? {
        let head = prefix + String(reasonSeparator)
        guard statement.hasPrefix(head) else { return nil }
        return AuthorRemovalRecordValue(
            reason: String(statement[statement.index(statement.startIndex, offsetBy: head.count)...]))
    }
}

/// 一筆移除記錄：被移除的原 literal ＋ 解析後的 statement。
public struct AuthorRemovalRecord: Equatable, Sendable {
    public let removed: String
    public let record: AuthorRemovalRecordValue
    public init(removed: String, record: AuthorRemovalRecordValue) {
        self.removed = removed; self.record = record
    }
}

extension Entry {
    /// 本 work 的作者位移除記錄（`field: authors` 的 reference，經唯一解析器）。
    ///
    /// 與 `splitRecords` **互斥**：兩者的 statement 前綴不同（`拆為 ` vs `移除：`），
    /// 所以同一筆 reference 不會同時被兩邊取到。decode 閘已保證每筆 `field: authors`
    /// 的 statement 至少解析得出其中一種。
    public var authorRemovalRecords: [AuthorRemovalRecord] {
        references.compactMap { r in
            guard r.field == "authors", let v = r.value,
                  case .judgement(let statement, _) = r.kind,
                  let parsed = AuthorRemovalRecordValue.parse(statement) else { return nil }
            return AuthorRemovalRecord(removed: v, record: parsed)
        }
    }
}
