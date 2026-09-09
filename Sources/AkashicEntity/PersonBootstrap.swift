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

    /// 寬鬆鍵命中既有 person 的 literal 群（R1-fix B4／DA-2）——**先消歧、不建檔**。
    /// 建了會在既有記錄旁鑄造重複身分（`Chen, Y.-H.`×27 對 `chen-yi-hau` 的實例）；
    /// 全部配對經 reject 否決後，群組回到 `candidates`（生命週期閉環）。
    public struct PendingResolutionGroup: Equatable {
        public var names: [String]
        public var occurrences: Int
        /// 命中的既有 person key（排序）——給操作者看「跟誰撞」。
        public var matchedKeys: [String]
    }

    /// 彼此寬鬆共鍵、而**兩邊都還沒有記錄**的 literal 群（#547）——同樣**先消歧、不建檔**。
    ///
    /// 與 `PendingResolutionGroup` 是同一件事的兩半：那一半問「跟**既有 person**撞了嗎」，
    /// 這一半問「跟**本批的其他候選**撞了嗎」。在 #547 之前只有前一半存在，於是
    /// `LooseNameKey` 的索引只由 `existing` 建成——`Carol S Dweck` ／ `Carol S. Dweck`
    /// ／ `C. S. Dweck` 三者互為異寫卻零標示，`--apply` 會鑄出三個身分。
    /// （行為 oracle：只替其中一種建檔之後，另外兩種立刻落進 `pendingResolution`。）
    ///
    /// **它是提名不是判定**（`identity-is-judged-not-matched`）：同鍵只代表「值得給人看」。
    /// `wang-ch` 那組的 `Chien-Hsun Wang` ／ `Chung-Ho Wang` ／ `Chih-Hsiung Wang`
    /// 寬鬆共鍵而是三個不同的人——所以出口有兩個方向，見 CLI 的處置指引。
    ///
    /// **不涵蓋羅馬化異拼**（`Hsu↔Xu`）：`LooseNameKey` 檔頭明寫那是查表域、刻意不在
    /// 任何鍵空間收斂，重啟需要 spec 層的新裁決。這是已知邊界，不是這個桶漏了。
    public struct PendingMutualGroup: Equatable {
        /// 這一組的全部寫法（排序）。
        public var names: [String]
        /// 組內全部作者位的總和。
        public var occurrences: Int
        /// 造成連結的寬鬆鍵（排序）——給操作者看「為什麼它們被收在一起」。
        public var sharedKeys: [String]
    }

    /// 一次 bootstrap 的完整結果。**分欄位而非 sum type**——`personsFor` 只吃
    /// `candidates`，於是「不小心替一個 unkeyable／pending 建 person」在型別層寫不出來。
    public struct BootstrapReport: Equatable {
        public var candidates: [Candidate]
        public var unkeyable: [UnkeyableGroup]
        /// 寬鬆鍵命中既有 person、待 resolve 流程消歧的群（回報不丟棄——
        /// lossless-intake §3：靜默是最糟的形式）。
        public var pendingResolution: [PendingResolutionGroup]
        /// 彼此寬鬆共鍵、兩邊都還沒有記錄的群（#547）——同樣扣住不建檔。
        public var pendingMutual: [PendingMutualGroup]

        public init(candidates: [Candidate], unkeyable: [UnkeyableGroup],
                    pendingResolution: [PendingResolutionGroup] = [],
                    pendingMutual: [PendingMutualGroup] = []) {
            self.candidates = candidates
            self.unkeyable = unkeyable
            self.pendingResolution = pendingResolution
            self.pendingMutual = pendingMutual
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
    public static func candidates(entries: [Entry], existing: [Person],
                                  rejected: Set<ResolutionPairing>,
                                  confirmed: [ResolutionPairing: String]) -> [Candidate] {
        resolve(entries: entries, existing: existing,
                rejected: rejected, confirmed: confirmed).candidates
    }

    /// 單一 traversal，`candidates` 與 `unkeyable` 的 source of truth（#238）。
    ///
    /// 與 `PersonResolver.resolve` / `OrgResolver.resolve` 同理由：**不寫第二支遍歷**。
    /// 兩支會分岔，而分岔的方式通常是其中一支忘了某個排除條件（機構名、已存在的
    /// alias、空字串）。
    /// `rejected`／`confirmed`：與 `PersonResolver.resolve` 同源同義，**刻意必填**
    /// ——resolver 擴到寬鬆鍵空間後（#303），「已存在的 person 不重複產出」的排除面
    /// 必須跟上；R3 verify 抓到本檔曾持有提名空間的**第二份不同構拷貝**（reorder＋
    /// initials 鍵空間合併查找 → 幽靈 pending；不吃 confirmed → resolver 正提名的
    /// literal 被鑄成重複 person）——#140「不寫第二支遍歷」的教訓在空間定義層重演。
    /// 修法：逐 tier 查找與 resolver 同構，confirmed 同源餵入。
    /// - Parameter minOccurrences: 只有出現次數 ≥ 此值的群才進入**互連**索引（#547 verify V16）。
    ///   預設 1（＝全部），既有呼叫端不受影響。
    ///
    ///   **它只閘互連索引，不過濾 `candidates` ／ `unkeyable` ／ `pendingResolution`。**
    ///   那三個仍然回傳全部，由呼叫端自己濾（`Commands.swift` 的
    ///   `report.candidates.filter { $0.occurrences >= minOccurrences }`）。這個不對稱是
    ///   刻意的：改成連 `candidates` 一起濾會靜默改變既有 34 個呼叫端的回傳內容。
    ///   `PersonBootstrapTests.testSubThresholdNeighbourDoesNotWithholdAnAboveThresholdCandidate`
    ///   把它釘住。
    ///
    ///   **為什麼門檻要進來這裡，而不是留給呼叫端事後過濾**：扣留若發生在門檻過濾之前，
    ///   低於門檻的寫法就對高於門檻的候選有**絕對否決權**。實測門檻 10 時仍有 16 組被扣住，
    ///   其中 `Daniel McNeish`（18 次）被 `Daniel Muise`（2 次）單獨拖住——而那兩個是不同的人。
    ///   使用者說「只處理 ≥N 的」，卻被一個他明講不要處理的鄰居擋下，那個否決權沒有來源。
    public static func resolve(entries: [Entry], existing: [Person],
                               rejected: Set<ResolutionPairing>,
                               confirmed: [ResolutionPairing: String],
                               minOccurrences: Int = 1) -> BootstrapReport {
        // #227：已知 alias 是**全部**名字的聯集——排除條件不看指定與否。
        let knownAliases = Set(existing.flatMap { $0.names.all.map(identity) })
        // R5（R4L-2）：identity() 比 resolver 的 exact 鍵寬（它另做重排攤平）——
        // 「identity 命中但非 normalize 相等」的 literal 在 resolver 是 reorder 級
        // 提名，先前被本檔 continue 成隱形：否決該提名後兩面皆不可行動（死路）。
        // 拆兩層：normalize 相等（真 exact）照舊 continue；僅 identity 相等者
        // 路由 pending（同一否決回歸機制涵蓋）。
        let exactAliases = Set(existing.flatMap { $0.names.all.map(normalize) })
        var identityMap: [String: Set<String>] = [:]
        for p in existing {
            for n in p.names.all {
                identityMap[identity(n), default: []].insert(p.key)
            }
        }
        var takenKeys = Set(existing.map(\.key))
        // R1-fix B4＋R3-fix R4-6：既有 person 的寬鬆鍵空間，**逐 tier 分開**
        // （與 resolver 同構——合併成一張表會讓 literal 的 reorder 鍵撞上某名字的
        // initials 鍵，產生 resolver 永不提名的幽靈 pending）。exact 由 knownAliases
        // 涵蓋。命中者不建新 person——那是 resolve 流程的工作。
        var reorderSpace: [String: Set<String>] = [:]
        var initialsSpace: [String: Set<String>] = [:]
        for p in existing {
            for n in p.names.all {
                reorderSpace[LooseNameKey.reorderKey(n), default: []].insert(p.key)
                for k in LooseNameKey.initialsKeys(n) {
                    initialsSpace[k, default: []].insert(p.key)
                }
            }
        }
        // confirmed 同源（R4-6）：resolver 以 confirmed-elsewhere 提名中的 literal
        // 不得被鑄成新 person
        var confirmedByLiteral: [String: Set<String>] = [:]
        for (pairing, _) in confirmed where pairing.holderKind == .work {
            confirmedByLiteral[normalize(pairing.literal), default: []].insert(pairing.judgedKey)
        }
        // 否決比對與 resolver 同一套正規化（R1-fix I1 的一致性）
        var rejectedNorm = Set<String>()
        for pairing in rejected where pairing.holderKind == .work {
            rejectedNorm.insert("\(pairing.holder)|\(normalize(pairing.literal))|\(pairing.judgedKey)")
        }

        // R2-fix R3-4：pending 判定在**群組層**不在 occurrence 層——同一 literal
        // 只要還有任何一筆配對未出清（surviving loose hit），整組扣住不建檔。
        // per-occurrence 判定會讓「否決其中一筆」把同一身分分裂成
        // 「建檔候選＋pending 並排」——建下去就是 R1 B3 的鑄造重複身分，而 skill
        // 對 initials 明令逐 entry reject，走完必踩。全部配對否決後整組回歸。
        var allGroups: [String: (names: [String], count: Int, pendingKeys: Set<String>)] = [:]
        for e in entries {
            for a in e.authors {
                guard case let .literal(raw) = a else { continue }
                // 機構名（#6 的 `{...}` 標記）不是人——不建 person
                guard !CorporateName.isMarked(raw) else { continue }
                let name = raw.trimmingCharacters(in: .whitespaces)
                guard !name.isEmpty else { continue }
                let id = identity(name)
                // 真 exact（normalize 相等）→ resolver 會以 exact 提名，這裡照舊隱形
                guard !exactAliases.contains(normalize(name)) else { continue }
                var hits = reorderSpace[LooseNameKey.reorderKey(name)] ?? []
                for k in LooseNameKey.initialsKeys(name) { hits.formUnion(initialsSpace[k] ?? []) }
                hits.formUnion(confirmedByLiteral[normalize(name)] ?? [])
                // 僅 identity 相等（重排攤平才命中）→ 併入 loose hits（R4L-2）
                if knownAliases.contains(id) { hits.formUnion(identityMap[id] ?? []) }
                let surviving = hits.filter {
                    !rejectedNorm.contains("\(e.citekey)|\(normalize(name))|\($0)")
                }
                var g = allGroups[id] ?? ([], 0, [])
                if !g.names.contains(name) { g.names.append(name) }
                g.count += 1
                g.pendingKeys.formUnion(surviving)
                allGroups[id] = g
            }
        }
        var groups: [String: (names: [String], count: Int)] = [:]
        var pendingList: [PendingResolutionGroup] = []
        for (id, g) in allGroups {
            if g.pendingKeys.isEmpty {
                groups[id] = (g.names, g.count)
            } else {
                pendingList.append(PendingResolutionGroup(
                    names: g.names.sorted(), occurrences: g.count,
                    matchedKeys: g.pendingKeys.sorted()))
            }
        }
        let pending = pendingList.sorted { a, b in
            a.occurrences == b.occurrences
                ? a.names.first ?? "" < b.names.first ?? ""
                : a.occurrences > b.occurrences
        }

        // #547：第二段分流——彼此寬鬆共鍵、而**兩邊都還沒有記錄**的群。
        //
        // 上面那一段問的是「跟**既有 person** 撞了嗎」（`reorderSpace`／`initialsSpace`
        // 由 `existing` 建成）。這一段問「跟**本批的其他候選** 撞了嗎」——在 #547 之前
        // 沒有人問，於是三種 Dweck 寫法各自成家，而 `--apply` 的唯一守衛（目的檔存在
        // 檢查）看不見它們：key 不同就永遠不相撞。
        //
        // **鍵空間逐 tier 分開**，與上面同構——合併成一張表會讓某個名字的 reorder 鍵
        // 撞上另一個的 initials 鍵（本檔 R3-fix R4-6 記過那個幽靈命中）。
        //
        // **只有 ≥ `minOccurrences` 的群進得了這個索引**（#547 verify V16）。低於門檻的
        // 群既不被扣住、也不扣住別人——使用者說「只處理 ≥N 的」，一個他明講不要處理的
        // 鄰居不該有否決權。詳見 `resolve` 的參數說明。
        let eligible = groups.filter { $0.value.count >= minOccurrences }
        var mutualReorder: [String: Set<String>] = [:]
        var mutualInitials: [String: Set<String>] = [:]
        for (id, g) in eligible {
            for n in g.names {
                mutualReorder[LooseNameKey.reorderKey(n), default: []].insert(id)
                for k in LooseNameKey.initialsKeys(n) {
                    mutualInitials[k, default: []].insert(id)
                }
            }
        }
        // 連通分量：A 與 B 共鍵、B 與 C 共鍵時三者同組（同一人的三種寫法未必兩兩共鍵——
        // `Carol S Dweck` 與 `C. S. Dweck` 靠 initials 相連，各自又與 `Carol S. Dweck`
        // 靠 reorder 相連）。逐對輸出會讓同一個人出現在多列，人得自己拼。
        var parent: [String: String] = [:]
        for id in eligible.keys { parent[id] = id }
        func find(_ x: String) -> String {
            var root = x
            while let p = parent[root], p != root { root = p }
            var cur = x                                  // 路徑壓縮
            while let p = parent[cur], p != root { parent[cur] = root; cur = p }
            return root
        }
        func union(_ a: String, _ b: String) {
            let ra = find(a), rb = find(b)
            if ra != rb { parent[ra] = rb }
        }
        for owners in mutualReorder.values where owners.count >= 2 {
            let sorted = owners.sorted()
            for o in sorted.dropFirst() { union(sorted[0], o) }
        }
        for owners in mutualInitials.values where owners.count >= 2 {
            let sorted = owners.sorted()
            for o in sorted.dropFirst() { union(sorted[0], o) }
        }
        var components: [String: [String]] = [:]
        for id in eligible.keys { components[find(id), default: []].append(id) }

        var mutualList: [PendingMutualGroup] = []
        for (_, members) in components where members.count >= 2 {
            let memberSet = Set(members)
            var names: [String] = []
            var count = 0
            for m in members {
                guard let g = groups[m] else { continue }
                names.append(contentsOf: g.names)
                count += g.count
            }
            // 「為什麼收在一起」要說得出來——只列真的連到本組 ≥2 個成員的鍵。
            var shared = Set<String>()
            for (k, owners) in mutualReorder where owners.intersection(memberSet).count >= 2 {
                shared.insert("reorder:\(k)")
            }
            for (k, owners) in mutualInitials where owners.intersection(memberSet).count >= 2 {
                shared.insert("initials:\(k)")
            }
            mutualList.append(PendingMutualGroup(
                names: names.sorted(), occurrences: count, sharedKeys: shared.sorted()))
            // **扣住不建檔**（#547 D1(b)）：只回報不解決傷害——`--apply` 照樣鑄三個身分。
            for m in members { groups.removeValue(forKey: m) }
        }
        let mutual = mutualList.sorted { a, b in
            a.occurrences == b.occurrences
                ? a.names.first ?? "" < b.names.first ?? ""
                : a.occurrences > b.occurrences
        }

        // 出現次數多的先——處理它們的投報率最高
        return groups.sorted { a, b in
            a.value.count == b.value.count ? a.key < b.key : a.value.count > b.value.count
        }.reduce(into: BootstrapReport(candidates: [], unkeyable: [],
                                       pendingResolution: pending,
                                       pendingMutual: mutual)) { report, pair in
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
