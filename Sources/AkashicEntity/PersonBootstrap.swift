import Foundation
import AkashicCore

/// 從 literal 作者名 bootstrap person 記錄（#34）。
///
/// ## 為什麼需要它：雞生蛋
///
/// `PersonResolver.candidates` 的比對基礎是**既有 person 的 `names`**。people 是 0 時
/// aliasMap 是空的，於是永遠 0 候選——`resolve-people` 無法自我啟動。實測：536 entries、
/// 1746 個 literal 作者、0 個 person 檔、解析率 0.0%。
///
/// ## 安全方向：寧可分割，絕不合併
///
/// **過度分割可回復**（發現是同一人就合併），**過度合併不可回復**（兩個人被併成一個，
/// 區別就此消失，而且沒有任何訊號說出它發生過）。所以：
///
/// - **只在機械可判時合併**：`Last, First` ↔ `First Last` 的重排是字串操作，不是猜測。
/// - **縮寫不與全名合併**：`Cheng, C` 與 `Cheng, Che` 看起來像同一人，但也可能是
///   `Cheng, Chao`。`WoSImport` 的兩欄同 index 對齊能給出這種配對，**因為來源保證了它**；
///   單靠名字本身猜不出來。
/// - **同姓氏 + 同名字首但全名不同 → 分開**，讓人決定。
///
/// 這與 `PersonResolver` 的「絕不自動合併」是同一條鐵律的兩面：那邊管 literal → 既有
/// person 的歸戶，這邊管 literal → 新 person 的建立。
public enum PersonBootstrap {

    public struct Candidate: Equatable {
        /// 建議的 person key（可改）。
        public var key: String
        /// 這一組的所有寫法——直接就是 `Person.names`。
        public var names: [String]
        /// 出現次數（多的先處理，投報率高）。
        public var occurrences: Int
    }

    /// 正規化走 `NameNormalization.matchingKey`（#140 verify F1）：曾自留一份舊版
    /// （trim+空白+lowercase，無 NFKC、不統一連字號），與 resolver 的新判準分裂——
    /// 後果是 bootstrap 對連字號變體建出**兩個** person，resolver 再把它們的 alias
    /// 判成塌縮歧義、整組排除：`bootstrap-people` → `resolve-people` 的文件化主流程
    /// 從 2 候選掉到 0，完全靜默。正規化只能有一份定義。
    /// **仍刻意不去連字號、不去點號**——`Jeng-Min` 與 `Jeng Min` 可能是同一人也
    /// 可能不是，去掉等於替人決定（matchingKey 統一連字號**變體**、不移除連字號）。
    static func normalize(_ s: String) -> String {
        NameNormalization.matchingKey(s)
    }

    /// `"Cheng, Che"` → `"Che Cheng"`。**只處理恰好一個逗號**的情形；
    /// 多逗號（`"Cheng, Che, Jr."`）語意不明，原樣回傳。
    static func reordered(_ s: String) -> String? {
        let parts = s.split(separator: ",", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        let last = parts[0].trimmingCharacters(in: .whitespaces)
        let first = parts[1].trimmingCharacters(in: .whitespaces)
        guard !last.isEmpty, !first.isEmpty else { return nil }
        return "\(first) \(last)"
    }

    /// `"Che Cheng"` → `"Cheng Che"`：把**最後一個 token 當姓**移到最前面。
    ///
    /// 與 `reordered` 互補——後者只認逗號形。少於兩個 token 回 `nil`（沒有可換的）。
    static func swappedOrder(_ s: String) -> String? {
        let tokens = s.split(whereSeparator: \.isWhitespace).map(String.init)
        guard tokens.count >= 2 else { return nil }
        return ([tokens.last!] + tokens.dropLast()).joined(separator: " ")
    }

    /// 身分鍵：同一鍵的名字視為同一人。**只做重排這一種機械等價。**
    ///
    /// ## 兩種輸入形式必須產生**同一組**候選（#226）
    ///
    /// 舊版只在逗號形上呼叫 `reordered`，於是候選集不對稱：
    ///
    /// | 輸入 | 候選集 |
    /// |---|---|
    /// | `Liang, Yu-Jen` | `{"liang, yu-jen", "yu-jen liang"}` → min = **`"liang, yu-jen"`** |
    /// | `Yu-Jen Liang` | `{"yu-jen liang"}` → **`"yu-jen liang"`** |
    ///
    /// 逗號形的 min 選中了**含逗號的那個**，而直式永遠產不出它。兩者要相等的條件是
    /// `mk(直式) < mk(逗號形)`，也就是「名的字典序 < 姓的字典序」——那是巧合，
    /// 不是不變式。真實 store 869 個 `Family, Given` 形有 **482 個（55.5%）**落在
    /// 失效側，`bootstrap-people` 為同一個人靜默建出兩個候選。
    ///
    /// 修法：**先把逗號形攤成空白形**（含逗號的字串從此不進候選集），再對空白形生成
    /// 兩種順序。這樣兩種輸入走到同一個空白形，候選集逐元素相同，min 必然相同。
    ///
    /// **不是**「兩邊都加 `reordered`」——那治不了病：直式沒有逗號，`reordered` 對它
    /// 恆回 nil。病灶是候選集裡混進了一個只有其中一種輸入產得出的元素。
    static func identity(_ s: String) -> String {
        // 逗號形先攤平：候選集只以空白形表示，杜絕「只有一邊產得出」的元素
        let spaced = reordered(s) ?? s
        let n = normalize(spaced)
        guard let swapped = swappedOrder(spaced) else { return n }
        return min(n, normalize(swapped))
    }

    /// ASCII slug：**先摺疊變音符號**，再把非 `[a-z0-9]` 轉 `-` 並收斂（#238）。
    ///
    /// 舊版是 `map { $0.isLetter || $0.isNumber ? $0 : "-" }`——`isLetter` 對**任何**
    /// Unicode 字母為真，於是 `Jörg` → `jörg`，而 `StoreKey.pattern` 是純 ASCII，
    /// `isValid` 失敗 → 整組候選被 `compactMap` **靜默丟棄**。實測真實 store 有 49 個
    /// 作者位置落在這條路上，其中約 33 個是本可自動處理的變音符號歐洲名。
    ///
    /// 摺疊的做法與 `Citekey.slug` 一致——**同一個 repo 不該有兩份行為不同的 slug**，
    /// 而那正是本 bug 的根因：解法已經在 repo 裡，只是這一份沒跟上。
    ///
    /// 與 `Citekey.slug` 的差別只在**連字號**：person key 是 `chen-yi-hau` 這種多段
    /// 形式，需要保留分隔；citekey 不需要。所以不能直接呼叫它，只能沿用它的摺疊。
    ///
    /// CJK 摺疊後仍是 CJK（`.diacriticInsensitive` 不做羅馬化），全部轉 `-` 後收斂成
    /// 空字串 → `suggestedKey` 回 `nil` → 由 `resolve` 記進 `unkeyable`。**那是對的**：
    /// `陳君厚` 沒有唯一正確的羅馬化，機器不該猜。
    static func asciiSlug(_ s: String) -> String {
        let folded = s.folding(options: [.diacriticInsensitive, .caseInsensitive],
                               locale: Locale(identifier: "en_US")).lowercased()
        let mapped = folded.map { ch -> Character in
            (ch.isASCII && (ch.isLetter || ch.isNumber)) ? ch : "-"
        }
        return String(mapped).split(separator: "-").joined(separator: "-")
    }

    /// 產不出 ASCII key 的一組名字——**回報，不丟棄**（#238）。
    ///
    /// 與「沒有作者」語意完全不同：這是「系統知道有這個人，但需要你指定 key」。
    /// 靜默丟棄讓使用者以為那些作者不存在——與 #231 的歧義同一個形狀。
    public struct UnkeyableGroup: Equatable {
        /// 這一組的所有寫法。
        public var names: [String]
        /// 出現次數。
        public var occurrences: Int
        /// 為什麼產不出 key（給人看，已是可直接顯示的說明）。
        public var reason: String

        public init(names: [String], occurrences: Int, reason: String) {
            self.names = names
            self.occurrences = occurrences
            self.reason = reason
        }
    }

    /// 一次 bootstrap 的完整結果。**兩個欄位而非 sum type**——`personsFor` 只吃
    /// `candidates`，於是「不小心替一個 unkeyable 建 person」在型別層寫不出來。
    public struct BootstrapReport: Equatable {
        public var candidates: [Candidate]
        public var unkeyable: [UnkeyableGroup]

        public init(candidates: [Candidate], unkeyable: [UnkeyableGroup]) {
            self.candidates = candidates
            self.unkeyable = unkeyable
        }
    }

    /// 建議的 person key：`<姓氏>-<名>` 小寫、非字母轉 `-`。
    static func suggestedKey(from name: String, taken: Set<String>) -> String? {
        let display = reordered(name) ?? name
        let tokens = display.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !tokens.isEmpty else { return nil }
        // 姓在後（已重排成 First Last）
        let surname = tokens.last!
        let given = tokens.dropLast().joined(separator: "-")
        func slug(_ s: String) -> String { Self.asciiSlug(s) }
        let base = given.isEmpty ? slug(surname) : "\(slug(surname))-\(slug(given))"
        guard !base.isEmpty, StoreKey.isValid(base) else { return nil }
        if !taken.contains(base) { return base }
        for i in 2...99 where StoreKey.isValid("\(base)-\(i)") && !taken.contains("\(base)-\(i)") {
            return "\(base)-\(i)"
        }
        return nil
    }

    /// 從 entries 的 literal 作者產出候選。
    ///
    /// **已存在的 person 不重複產出**——它們的 alias 已在 `PersonResolver` 的比對範圍內，
    /// 再造一個新 person 就是在製造重複。
    public static func candidates(entries: [Entry], existing: [Person]) -> [Candidate] {
        resolve(entries: entries, existing: existing).candidates
    }

    /// 單一 traversal，`candidates` 與 `unkeyable` 的 source of truth（#238）。
    ///
    /// 與 `PersonResolver.resolve` / `OrgResolver.resolve` 同理由：**不寫第二支遍歷**。
    /// 兩支會分岔，而分岔的方式通常是其中一支忘了某個排除條件（機構名、已存在的
    /// alias、空字串）。
    public static func resolve(entries: [Entry], existing: [Person]) -> BootstrapReport {
        // #227：已知 alias 是**全部**名字的聯集——排除條件不看指定與否。
        let knownAliases = Set(existing.flatMap { $0.names.all.map(identity) })
        var takenKeys = Set(existing.map(\.key))

        var groups: [String: (names: [String], count: Int)] = [:]
        for e in entries {
            for a in e.authors {
                guard case let .literal(raw) = a else { continue }
                // 機構名（#6 的 `{...}` 標記）不是人——不建 person
                guard !CorporateName.isMarked(raw) else { continue }
                let name = raw.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let id = identity(name)
                guard !knownAliases.contains(id) else { continue }
                var g = groups[id] ?? ([], 0)
                if !g.names.contains(name) { g.names.append(name) }
                g.count += 1
                groups[id] = g
            }
        }

        // 出現次數多的先——處理它們的投報率最高
        return groups.sorted { a, b in
            a.value.count == b.value.count ? a.key < b.key : a.value.count > b.value.count
        }.reduce(into: BootstrapReport(candidates: [], unkeyable: [])) { report, pair in
            let g = pair.value
            let sortedNames = g.names.sorted()
            guard let key = suggestedKey(from: sortedNames[0], taken: takenKeys) else {
                // **回報，不丟棄**（#238）。舊版是 `compactMap { … return nil }`——
                // 整組候選消失且不留任何痕跡，使用者以為那些作者不存在。
                report.unkeyable.append(UnkeyableGroup(
                    names: sortedNames, occurrences: g.count,
                    reason: asciiSlug(sortedNames[0]).isEmpty
                        ? "名字摺疊成 ASCII 後是空的（例如 CJK）——沒有唯一正確的羅馬化，需要人指定 key"
                        : "產不出未被占用的合法 key（同名已達 99 個上限）"))
                return
            }
            takenKeys.insert(key)
            report.candidates.append(Candidate(key: key, names: sortedNames, occurrences: g.count))
        }
    }

    /// 把候選寫成 person 記錄。**不改 entries**——歸戶是 `resolve-people` 的工作，
    /// 兩步分開讓每一步都可單獨檢查。
    public static func personsFor(_ candidates: [Candidate]) -> [Person] {
        // #227：bootstrap 產出的是**尚未指定對外名字**的候選——全部進 variant，
        // authorized 留空（「還沒指定」是有意義的狀態，不得由機械偽造指定）。
        candidates.map { Person(key: $0.key, names: PersonNames(variant: $0.names)) }
    }
}
