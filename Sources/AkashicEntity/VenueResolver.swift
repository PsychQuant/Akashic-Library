import Foundation
import AkashicCore

/// venue 的解析候選（鏡像 `ResolutionCandidate`，#304）。
///
/// **刻意不與 person 共用型別**：兩個定義域的候選在 apply 端走不同的改寫路徑
/// （`entry.venues` vs `entry.authors`），共用型別會讓「把 venue 候選 apply 到
/// authors」在型別層寫得出來。
public struct VenueResolutionCandidate: Equatable {
    public var citekey: String
    public var venueIndex: Int
    public var literal: String
    public var venueKey: String
    public var reason: String

    public init(citekey: String, venueIndex: Int, literal: String,
                venueKey: String, reason: String) {
        self.citekey = citekey
        self.venueIndex = venueIndex
        self.literal = literal
        self.venueKey = venueKey
        self.reason = reason
    }

    /// 唯一識別：`"<citekey>:<venueIndex>"`（同 `ResolutionCandidate.rowID` 的理由——
    /// 複合鍵住在型別上，不讓三個呼叫端各寫一次）。
    public var rowID: String { "\(citekey):\(venueIndex)" }   // display-safe-exempt: citekey：回程把手須逐字，消毒會讓 apply 對不上（且 displaySafe 不冪等）
}

/// 同一個 literal 對到 2+ 個 venue——需要人判斷（同 `AmbiguousMatch` 的立場：
/// 回報它，不解決它）。
public struct VenueAmbiguousMatch: Equatable {
    public var entryID: UUID
    public var citekey: String
    public var venueIndex: Int
    public var literal: String
    /// 命中的 venue key，已排序且 `count >= 2`。
    public var venueKeys: [String]

    public init?(entryID: UUID, citekey: String, venueIndex: Int,
                 literal: String, venueKeys: Set<String>) {
        guard venueKeys.count >= 2 else { return nil }
        self.entryID = entryID
        self.citekey = citekey
        self.venueIndex = venueIndex
        self.literal = literal
        self.venueKeys = venueKeys.sorted()
    }

    public var rowID: String { "\(entryID.uuidString):\(venueIndex)" }
}

/// 被**正規化配對**的否決壓掉的候選（#712）——它在 `candidates` 裡看不到，但不是因為有人否決了**它的**拼法：
/// 否決抑制自 #554 R12 起以 `NameNormalization.matchingKey` 為鍵，所以對同 work 同 venue 的**另一個拼法**的
/// `--reject`／`--demote` 會一併壓住它。那是提名面 recall 的收窄，本型別讓它出現在列表上（「沉底而非隱藏」），
/// **不改變抑制本身**。
///
/// **與 resolve-people 的 `rejected` 段不同**（#712 R1 verify 第 4／39 列）：那一段只列**逐字等於**被否決拼法的作者位，
/// 被同一筆否決以正規化鍵壓掉的兄弟拼法不在其中——people 與 organization 的列表對它們仍然沉默，追蹤在 #721。
/// 這裡報的正是那一類，所以不是「同 people 的 rejected 段」，是它沒涵蓋的那一半。
///
/// **進這個清單的判準只有一條**：它被某筆 rejected verdict 以 `matchingKey` 壓住，而**沒有任何**壓住它的 rejected
/// verdict 的 literal 與它自己的 literal 相等（Swift `String ==`，即 canonical equivalence）。換句話說：若抑制仍比
/// 逐字配對（R12 之前的行為），這個候選本來會列在 `candidates`——R12 隱藏的正是這一批。逐字相等的是普通的已否決
/// （列表從來不列它，維持原樣）；只差 NFC／NFD 的兩個拼法是同一個字串，R12 之前就壓得住，也不在這裡。
///
/// 只收 `keys.count == 1` 的候選：抑制只作用於不歧義的提名，歧義（對到 2+ venue）一向不被抑制、照列在 `ambiguities`。
/// **刻意不帶 `id`**：它不是可 apply 的候選（`candidates` 裡沒有這個 id，apply 會 notFound），給 id 會讓消費端以為可以送回去。
public struct VenueSuppressedCandidate: Equatable {
    public var citekey: String
    public var venueIndex: Int
    /// 被壓住的候選自己的 literal（work 上的那條邊）。
    public var literal: String
    public var venueKey: String
    /// 壓住它的 rejected verdict 的 literal：同 work、同 venue、`matchingKey` 相同而與 `literal` 不同的那些拼法，
    /// 去重（canonical）後依字串排序的**前 `VenueResolver.suppressedLiteralsPerRow` 個**，至少一個。使用者否決的是這些拼法。
    ///
    /// **在 resolver 裡就截**（#712 R1 verify 第 0／1 列）：第一版存全部 K 個、到 `suppressedPayload` 才截 5——N 列共用同一組
    /// K 個拼法時，記憶體是 N×K、每列還各排序一次，對未信任的 store 內容是二次方（實測 N=K=4000 時 16.9 秒、306 MB）。
    public var rejectedLiterals: [String]
    /// 壓住它的 rejected literal 總數（去重後）。`rejectedLiterals.count < rejectedLiteralsTotal` 即被截。
    public var rejectedLiteralsTotal: Int

    public init(citekey: String, venueIndex: Int, literal: String, venueKey: String,
                rejectedLiterals: [String], rejectedLiteralsTotal: Int) {
        self.citekey = citekey
        self.venueIndex = venueIndex
        self.literal = literal
        self.venueKey = venueKey
        self.rejectedLiterals = rejectedLiterals
        self.rejectedLiteralsTotal = rejectedLiteralsTotal
    }
}

/// 一次 venue 解析的完整結果（candidates 可 apply、ambiguities 不可——
/// 「不小心 apply 一個歧義」在型別層寫不出來，同 `ResolutionReport`；`suppressed` 同樣不可 apply，見 `VenueSuppressedCandidate`）。
public struct VenueResolutionReport: Equatable {
    public var candidates: [VenueResolutionCandidate]
    public var ambiguities: [VenueAmbiguousMatch]
    /// 被正規化配對的否決壓掉的候選（#712），依 (citekey, venueIndex) 排序。
    public var suppressed: [VenueSuppressedCandidate]

    public init(candidates: [VenueResolutionCandidate], ambiguities: [VenueAmbiguousMatch],
                suppressed: [VenueSuppressedCandidate]) {
        self.candidates = candidates
        self.ambiguities = ambiguities
        self.suppressed = suppressed
    }
}

/// venue 解析原語。鐵律同 `PersonResolver`：**絕不自動合併**——`candidates` 只提名，
/// `apply` 是使用者顯式確認後的第二步（`literal-first-then-key` 的升格路徑）。
public enum VenueResolver {

    /// 一列 `suppressed` 最多帶幾個壓住它的 rejected literal（#712）。每個都是 store 字串，所以在 resolver 裡就截、
    /// 另記總數（`rejectedLiteralsTotal`）——截在輸出端擋不住建表時的 N×K（R1 verify 第 0／1 列）。
    public static let suppressedLiteralsPerRow = 5

    /// 同一個否決鍵的全部被否決拼法，建表時算一次、各列共用（#712 R1）。
    /// `spellings` 給「候選自己是不是其中之一」的 O(1) 判斷（`Set<String>` 的相等是 canonical equivalence，與 `String ==` 同一把）；
    /// `shown` 是依字串排序的前 `suppressedLiteralsPerRow` 個，只在第一次有列需要它時才排（列表腿以外不排）。
    private struct RejectedSpellings {
        var spellings: Set<String> = []
        var shown: [String]? = nil
    }

    /// 單一 traversal（不為歧義另寫遍歷——#140 的分岔血案同適用）。
    /// `rejected` 刻意必填（同 PersonResolver：`= []` 會讓新呼叫面靜默略過否決史）。
    ///
    /// 正規化走 `NameNormalization.matchingKey`（NFKC＋lowercase＋空白收斂）——
    /// WoS 全大寫形（`PSYCHOMETRIKA`）與正式刊名因此同鍵，這正是 371 個 distinct
    /// journaltitle 的主要異形來源。
    ///
    /// `reportingSuppressed`：要不要組 `suppressed`（#712）。只有列表腿讀它；apply／reject 腿傳 `false`，連每個否決鍵的
    /// 排序都不做（R1 verify 第 0 列）。預設 `true`——新的列表面忘了傳時多做一點工，而不是安靜地少一段。
    /// **成本是線性的**：每個否決鍵的拼法集合建一次（O(R)，R＝rejected verdict 數），每條邊一次 O(1) 查找，每列至多帶
    /// `suppressedLiteralsPerRow` 個拼法；排序每個鍵至多一次（O(K log K)，各鍵加總 O(R log R)）。
    public static func resolve(entries: [Entry], venues: [Venue],
                               rejected: Set<ResolutionPairing>,
                               reportingSuppressed: Bool = true) -> VenueResolutionReport {
        var aliasMap: [String: Set<String>] = [:]
        for venue in venues {
            // 全部名字（時間軸各段——沿革中的舊刊名照樣配對；舊文章掛舊刊名是常態）。
            for seg in venue.names.entries {
                aliasMap[normalize(seg.value), default: []].insert(venue.key)
            }
        }

        // 否決比對用**與提名同一套正規化**（#554 R12——R11 verify logic 第 8 列、regression 第 11 列；`PersonResolver` 同一格
        // 早就這樣做且理由逐字寫在那裡）：verdict 記原始字串（lossless），而 `verdictEqualityKey`／#486 的矛盾掃描／D25 一族都以
        // `matchingKey` 定義「同一配對」。抑制若比原始位元組，`demote` 寫下的 `rejected(work, Psychometrika)` 壓不住同一 work 的
        // `PSYCHOMETRIKA` 邊——三步全工具面就造出永久的矛盾對（apply → demote → apply）。
        // 鍵的形狀：holder 與 judgedKey 都是 `StoreKey`（`[a-z0-9][a-z0-9-]*`），`\0` 不在字元集內，所以夾在中間的 literal
        // 即使含 U+0000 也移不動任何分隔點——碰撞不可達（R12 verify DA 第 43 列收窄 security 第 28 列）；與 `verdictEqualityKey`
        // 同一套拼接，刻意不改形狀。
        // 三段各自一個欄位、不拼接（R25；R24 verify security 第 27 列：`matchingKey` 不剝 Cc，U+0000 分隔可被 literal 內容撞上——
        // 與 `verdictEqualityKey` 對 malformed 鍵補過的同一道防禦；struct 鍵沒有分隔符可撞）
        // #712：值是壓住這個鍵的被否決拼法（原字串）——抑制本身只看「鍵在不在」，與先前的 `Set<RejectedPairKey>` 等價；
        // 值只用來回報「是誰壓住的」，並分辨逐字相等的普通已否決與被正規化壓掉的候選。
        var rejectedNorm: [RejectedPairKey: RejectedSpellings] = [:]
        for pairing in rejected where pairing.holderKind == .work {
            rejectedNorm[RejectedPairKey(holder: pairing.holder, literal: normalize(pairing.literal), judged: pairing.judgedKey), default: .init()]
                .spellings.insert(pairing.literal)
        }
        var candidates: [VenueResolutionCandidate] = []
        var ambiguities: [VenueAmbiguousMatch] = []
        var suppressed: [VenueSuppressedCandidate] = []
        for entry in entries {
            for (i, ref) in entry.venues.enumerated() {
                guard case .literal(let literal) = ref else { continue }
                // 無任何 venue 叫這個名字＝合法長期狀態，不回報（噪音紀律同 person）。
                let normalized = normalize(literal)
                guard let keys = aliasMap[normalized] else { continue }
                if keys.count == 1, let key = keys.first {
                    let rejectedKey = RejectedPairKey(holder: entry.citekey, literal: normalized, judged: key)
                    if let rejectedHere = rejectedNorm[rejectedKey] {
                        // 逐字相等的壓住者＝普通的已否決（列表一向不列，維持原樣）；否則是被正規化配對壓掉的——報出來（#712），抑制不變
                        if reportingSuppressed, !rejectedHere.spellings.contains(literal) {
                            let shown: [String]
                            if let cached = rejectedHere.shown {
                                shown = cached
                            } else {
                                shown = Array(rejectedHere.spellings.sorted().prefix(suppressedLiteralsPerRow))
                                rejectedNorm[rejectedKey]?.shown = shown
                            }
                            suppressed.append(VenueSuppressedCandidate(
                                citekey: entry.citekey, venueIndex: i, literal: literal, venueKey: key,
                                rejectedLiterals: shown, rejectedLiteralsTotal: rejectedHere.spellings.count))
                        }
                        continue
                    }
                    candidates.append(VenueResolutionCandidate(
                        citekey: entry.citekey, venueIndex: i, literal: literal,
                        venueKey: key, reason: "venue name 完全命中"))
                } else if let m = VenueAmbiguousMatch(entryID: entry.id, citekey: entry.citekey,
                                                      venueIndex: i, literal: literal,
                                                      venueKeys: keys) {
                    ambiguities.append(m)
                }
            }
        }
        return VenueResolutionReport(
            candidates: candidates.sorted { ($0.citekey, $0.venueIndex) < ($1.citekey, $1.venueIndex) },
            ambiguities: ambiguities.sorted {
                ($0.citekey, $0.venueIndex, $0.entryID.uuidString)
                    < ($1.citekey, $1.venueIndex, $1.entryID.uuidString)
            },
            suppressed: suppressed.sorted { ($0.citekey, $0.venueIndex, $0.literal) < ($1.citekey, $1.venueIndex, $1.literal) })
    }

    /// 把已確認的候選套用到 entries（回傳新副本，不動原陣列；同 PersonResolver.apply）。
    public static func apply(_ candidates: [VenueResolutionCandidate], to entries: [Entry]) -> [Entry] {
        // #628：以陣列位置就地改寫，不經字典對應回輸出（同 #627 的 `PersonResolver.apply`）——citekey 對應回輸出
        // 會把同 citekey 的每一筆換成同一份；citekey 重複或 id 與另一筆共用的位置一律不改（寫入以 id 定檔）
        let unlocatable = entries.unlocatableCitekeys
        var indexByCitekey: [String: Int] = [:]
        for (i, e) in entries.enumerated() where !unlocatable.contains(e.citekey) { indexByCitekey[e.citekey] = i }
        var out = entries
        for candidate in candidates {
            guard let i = indexByCitekey[candidate.citekey],
                  out[i].venues.indices.contains(candidate.venueIndex),
                  case .literal(let current) = out[i].venues[candidate.venueIndex],
                  current == candidate.literal else { continue }
            out[i].venues[candidate.venueIndex] = .key(candidate.venueKey)
        }
        return out
    }

    static func normalize(_ s: String) -> String {
        NameNormalization.matchingKey(s)
    }
}

/// 否決抑制的鍵：(holder, 正規化 literal, judged key) 三段各自一個欄位——沒有分隔符可被 literal 內容撞上（R25，R24 verify security 第 27 列）。
/// `VenueResolver` 與 `PersonResolver` 共用。
public struct RejectedPairKey: Hashable {
    public let holder: String
    public let literal: String
    public let judged: String
    public init(holder: String, literal: String, judged: String) { self.holder = holder; self.literal = literal; self.judged = judged }
}
