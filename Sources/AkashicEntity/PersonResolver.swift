import Foundation
import AkashicCore

public struct ResolutionCandidate: Equatable {
    public var citekey: String
    public var authorIndex: Int
    public var literal: String
    public var personKey: String
    public var reason: String

    public init(citekey: String, authorIndex: Int, literal: String,
                personKey: String, reason: String) {
        self.citekey = citekey
        self.authorIndex = authorIndex
        self.literal = literal
        self.personKey = personKey
        self.reason = reason
    }

    /// 這筆候選在一次解析內的唯一識別：`"<citekey>:<authorIndex>"`。
    ///
    /// **`citekey` 單獨不唯一**——同一篇文獻可以有多個 literal 作者各自出候選。
    /// 這個複合鍵先前在三個地方各寫一次（MCP 的 `withIDs`、AppKit 的 `id(of:)`、
    /// 以及 `--apply` 的解析），而 App 的 `ForEach(id: \.citekey)` **漏掉了**——
    /// 於是一篇兩個候選作者的文獻在 SwiftUI 產生兩列同 ID，掉列或錯配（#236 R4）。
    ///
    /// 定義在型別上而非各呼叫端：三份拷貝總有一天分岔，而這次分岔的方式是
    /// 「其中一個呼叫端根本沒複製」。
    public var rowID: String { "\(citekey):\(authorIndex)" }
}

/// 同一個 literal 在同一個作者位置對到 **2+ 個 person**——系統知道自己遇到了決定點。
///
/// **與「沒有任何 person 匹配」語意不同。** 後者是合法的長期狀態（`.literal` 未歸戶，
/// 見 `Author` 的 doc）；前者需要人判斷。#231 之前兩者走同一條 `continue`，於是後者
/// 不留任何痕跡——而它才是有情報價值的那個。
///
/// ## 回報它，不解決它
///
/// 形狀屬於 `LibraryStore` 那一族「**回報而非拒絕，判斷屬使用端**」
/// （`overlappingPairs` / `dateFieldAnomalies` / `recordsDeceasedWithOpenAffiliation`，
/// `DateFieldReportTests` 明寫它們同一形狀）。歧義不是錯誤——同名的人真實存在。
///
/// ## 讀的人要分辨兩個**需要相反行動**的子情況
///
/// | | 意思 | 正確處置 |
/// |---|---|---|
/// | (a) | 兩個真的不同的人剛好同名 | 每篇各自歸屬，**永遠不該合併** |
/// | (b) | 同一個人有兩筆記錄 | **應該合併** |
///
/// 兩者在這裡是**同一個表徵**，所以呈現層要為每個 `personKeys` 成員帶出區辨欄位
/// （`orcid` / `openalex` / 當前隸屬 / `died`）。**本型別刻意只帶 key**——組那些欄位
/// 要吃整個 `Person`，而這一層只吃 `names`，把 `Person` 拉進來會讓它不再純。
///
/// > **`names` 本身不具區辨力**：它們之所以能被比對到一起，正是因為正規化後相同。
/// > 它是歧義的**成因**，不是判準。真正能分辨的是 `orcid` / `openalex`（外部識別碼）
/// > 與 `died` / 隸屬（時空不相容）。
public struct AmbiguousMatch: Equatable {
    /// **entry 的機器身分。** `citekey` 不足以定位——store 可能含重複 citekey
    /// （`PersonResolver.apply` 的 `uniquingKeysWith` 明寫「損壞 store 出現重複
    /// citekey 時不 trap」），此時兩筆歧義在 `(citekey, authorIndex)` 上完全相同。
    ///
    /// 誠實邊界：帶了 id 讓**報告**可定位，但 `apply` 仍只寫得到重複 citekey 的
    /// 最後一筆——那是既有限制，不由本型別解決。
    public var entryID: UUID
    public var citekey: String
    public var authorIndex: Int
    public var literal: String
    /// 命中的 person key，**已排序**且 `count >= 2`。
    ///
    /// 排序是為了輸出穩定（同一份 store 兩次執行給同一份報告，不隨 `Set` 的雜湊擾動）。
    public var personKeys: [String]

    /// 少於兩個 key 回 `nil`——**「歧義只有一個候選」在型別層不可表達**。
    public init?(entryID: UUID, citekey: String, authorIndex: Int,
                 literal: String, personKeys: Set<String>) {
        guard personKeys.count >= 2 else { return nil }
        self.entryID = entryID
        self.citekey = citekey
        self.authorIndex = authorIndex
        self.literal = literal
        self.personKeys = personKeys.sorted()
    }

    /// 這筆歧義的唯一識別：`"<entryID>:<authorIndex>"`。
    ///
    /// **`entryID` 單獨不唯一**——一篇論文可以有兩個歧義作者。App 的
    /// `ForEach(id: \.entryID)` 因此在那種 entry 上產生重複 ID，SwiftUI 對重複
    /// 識別的行為是掉列／錯配（#236 R4）。同 `ResolutionCandidate.rowID` 的理由。
    public var rowID: String { "\(entryID.uuidString):\(authorIndex)" }
}

/// 一次解析的完整結果。
///
/// **兩個欄位而不是給 `ResolutionCandidate` 一個 sum type**：`apply` 只該吃唯一命中。
/// 分開之後「不小心 apply 一個歧義」在**型別層寫不出來**。
public struct ResolutionReport: Equatable {
    /// 唯一命中，可 `apply`。
    public var candidates: [ResolutionCandidate]
    /// 2+ 命中，**不可** `apply`，要人看。
    public var ambiguities: [AmbiguousMatch]

    public init(candidates: [ResolutionCandidate], ambiguities: [AmbiguousMatch]) {
        self.candidates = candidates
        self.ambiguities = ambiguities
    }
}

/// 人物解析原語。鐵律：**絕不自動合併**——`candidates` 只提名，
/// `apply` 是使用者顯式確認後才呼叫的第二步。
public enum PersonResolver {

    /// 單一 traversal，`candidates` 與 `ambiguities` 的 **source of truth**。
    ///
    /// **不要為歧義另寫一支遍歷。** repo 有現成的血案：#140 的 bootstrap 與 resolver
    /// 各留一份正規化，分裂後文件化主流程對連字號變體從 2 候選掉到 0、**完全靜默**
    /// （`testBootstrapAndResolverShareNormalization` 是那次的 regression 守衛）。
    /// 兩支遍歷會分岔，而分岔的方式是安靜的。
    /// `rejected`：已否決配對（#232 design D5）。呼叫端從 verdict references 算出
    /// （`ResolutionLedger.rejectedPairings`）後傳入——resolver 保持純函式，不讀 store。
    /// 排除的是**恰為** (citekey, literal, personKey) 的三元組：同 literal 在別的
    /// entry 是另一次觀察，照提。
    public static func resolve(entries: [Entry], people: [Person],
                               rejected: Set<ResolutionPairing> = []) -> ResolutionReport {
        // 正規化 alias → person keys
        var aliasMap: [String: Set<String>] = [:]
        for person in people {
            for name in person.names {
                aliasMap[normalize(name), default: []].insert(person.key)
            }
        }

        var candidates: [ResolutionCandidate] = []
        var ambiguities: [AmbiguousMatch] = []
        for entry in entries {
            for (i, author) in entry.authors.enumerated() {
                guard case .literal(let literal) = author else { continue }
                // 沒有任何人叫這個名字＝合法長期狀態，**不回報**——把它也報出來會讓
                // 報告被噪音淹沒，而被淹沒的報告等於沒有報告。
                guard let keys = aliasMap[normalize(literal)] else { continue }
                if keys.count == 1, let key = keys.first {
                    guard !rejected.contains(ResolutionPairing(
                        holder: entry.citekey, literal: literal, judgedKey: key)) else { continue }
                    candidates.append(ResolutionCandidate(
                        citekey: entry.citekey, authorIndex: i, literal: literal,
                        personKey: key, reason: "alias 完全命中"))
                } else if let m = AmbiguousMatch(entryID: entry.id, citekey: entry.citekey,
                                                 authorIndex: i, literal: literal,
                                                 personKeys: keys) {
                    ambiguities.append(m)
                }
            }
        }
        // ambiguities 用 `entryID` 打破 tie——重複 citekey 是被支援的損壞態，
        // `(citekey, authorIndex)` 在那時不是全序，相等元素的相對順序未定義
        // （Swift 的 sort 不保證穩定）。candidates 的排序是**既有行為**，不在本次
        // 改動範圍內，刻意不動。
        return ResolutionReport(
            candidates: candidates.sorted { ($0.citekey, $0.authorIndex) < ($1.citekey, $1.authorIndex) },
            ambiguities: ambiguities.sorted {
                ($0.citekey, $0.authorIndex, $0.entryID.uuidString)
                    < ($1.citekey, $1.authorIndex, $1.entryID.uuidString)
            })
    }

    /// 高信心候選：literal 與某人 alias 正規化後完全命中，且不歧義。
    ///
    /// 薄包裝——**行為與簽名皆未改變**。歧義走 `resolve`。
    public static func candidates(entries: [Entry], people: [Person]) -> [ResolutionCandidate] {
        resolve(entries: entries, people: people).candidates
    }

    /// 把已確認的候選套用到 entries（回傳新副本，不動原陣列）。
    public static func apply(_ candidates: [ResolutionCandidate], to entries: [Entry]) -> [Entry] {
        // uniquingKeysWith：損壞 store 出現重複 citekey 時不 trap（後者勝，validate 另行報告）
        var byCitekey = Dictionary(entries.map { ($0.citekey, $0) }, uniquingKeysWith: { _, last in last })
        for candidate in candidates {
            guard var entry = byCitekey[candidate.citekey],
                  entry.authors.indices.contains(candidate.authorIndex),
                  case .literal(let current) = entry.authors[candidate.authorIndex],
                  current == candidate.literal else { continue }
            entry.authors[candidate.authorIndex] = .key(candidate.personKey)
            byCitekey[candidate.citekey] = entry
        }
        return entries.map { byCitekey[$0.citekey] ?? $0 }
    }

    /// 比對面吃正規化（#81：NFKC＋連字號家族＋空白收斂），輸出仍是原字串——
    /// 正規化只住在配對鍵裡，永不外洩成資料。
    static func normalize(_ s: String) -> String {
        NameNormalization.matchingKey(s)
    }
}
