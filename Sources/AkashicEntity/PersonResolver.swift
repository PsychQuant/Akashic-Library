import Foundation
import AkashicCore

/// 提名的信心層（#303 design D2）。**封閉四值，信心降冪**——不得依性質相似類推第五值；
/// 羅馬化異拼刻意不在任何 tier（spec person-resolution 的 closed-enumeration requirement）。
///
/// rawValue 即三面（CLI／MCP／App）的對外字串——單一定義，不讓序列化端各寫一份。
public enum ResolutionTier: String, CaseIterable, Comparable, Equatable {
    /// alias 正規化後完全命中（既有行為）
    case exact
    /// 同 literal 已在他處經 confirmed verdict 判給同一人（design D3）
    case confirmedElsewhere = "confirmed-elsewhere"
    /// token 重排相等（`Hsu, Yung-Fong` ↔ `Yung-Fong Hsu`）
    case reorder
    /// 姓＋首字母相等（`Chen, Y.-H.` ↔ `Chen, Yi-Hau`）——證據最弱，apply 前必查證
    case initials

    /// 信心降冪的全序（`exact` 最先）。給排序與「最高 tier 抑制」用。
    public static func < (a: ResolutionTier, b: ResolutionTier) -> Bool {
        let order = ResolutionTier.allCases
        return order.firstIndex(of: a)! < order.firstIndex(of: b)!
    }
}

public struct ResolutionCandidate: Equatable {
    public var citekey: String
    public var authorIndex: Int
    public var literal: String
    public var personKey: String
    public var reason: String
    /// 提名層（#303）。**刻意無預設值**（R1-fix I3）——預設 `.exact` 是往最高
    /// 信心值 fail-open，與同檔 `rejected`／`confirmed` 必填的裁決同一條理由：
    /// 位置決定了誰會走它，required 讓「忘了帶 tier」變成編譯錯誤。
    public var tier: ResolutionTier

    public init(citekey: String, authorIndex: Int, literal: String,
                personKey: String, reason: String, tier: ResolutionTier) {
        self.citekey = citekey
        self.authorIndex = authorIndex
        self.literal = literal
        self.personKey = personKey
        self.reason = reason
        self.tier = tier
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
    /// 碰撞發生在哪個提名層（#303）。initials 碰撞（93/724 的「姓＋首字母」共鍵）
    /// 與 exact 同名是不同的情報，呈現面要分得出來。
    public var tier: ResolutionTier

    /// 少於兩個 key 回 `nil`——**「歧義只有一個候選」在型別層不可表達**。
    public init?(entryID: UUID, citekey: String, authorIndex: Int,
                 literal: String, personKeys: Set<String>, tier: ResolutionTier) {
        guard personKeys.count >= 2 else { return nil }
        self.entryID = entryID
        self.citekey = citekey
        self.authorIndex = authorIndex
        self.literal = literal
        self.personKeys = personKeys.sorted()
        self.tier = tier
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
    /// 排除的是**恰為** (work, citekey, literal, personKey) 的配對：同 literal 在
    /// 別的 entry 是另一次觀察，照提。
    ///
    /// **刻意無預設值**（verify DA fix-10）：`= []` 曾讓 App 面（Adjudication）
    /// 靜默編過而完全略過否決史——位置決定了誰會走它，required 讓「第四個呼叫面
    /// 忘了帶」變成編譯錯誤而不是安靜的行為分岔。`confirmed`（#303 design D3）
    /// 同一條理由必填：缺省＝confirmed-elsewhere tier 靜默消失。
    public static func resolve(entries: [Entry], people: [Person],
                               rejected: Set<ResolutionPairing>,
                               confirmed: Set<ResolutionPairing>) -> ResolutionReport {
        // 各 tier 的比對地圖在同一次 people 遍歷建好（#140：不為任何 tier 另寫遍歷）。
        // #227：alias 對照要的是**全部**名字（authorized + variant）——歸戶比對
        // 不因指定與否而異；三個 tier 的鍵空間都吃 `names.all`。
        var exactMap: [String: Set<String>] = [:]
        var reorderMap: [String: Set<String>] = [:]
        var initialsMap: [String: Set<String>] = [:]
        for person in people {
            for name in person.names.all {
                exactMap[normalize(name), default: []].insert(person.key)
                reorderMap[LooseNameKey.reorderKey(name), default: []].insert(person.key)
                for k in LooseNameKey.initialsKeys(name) {
                    initialsMap[k, default: []].insert(person.key)
                }
            }
        }
        // confirmed verdicts → 正規化 literal → keys（design D3：verdict 知識再利用——
        // 同字串已在他處判給某人，別處的同字串值得以該知識提名）。
        // **只吃 work-holder**（R1-fix I2）：org 域 verdict（holderKind: .person）
        // 餵進 person 提名是類別錯誤——今天 benign（org verdict 住 org 記錄），
        // 但手改 store／合併外庫時就不是。
        var confirmedByLiteral: [String: Set<String>] = [:]
        for pairing in confirmed where pairing.holderKind == .work {
            confirmedByLiteral[normalize(pairing.literal), default: []].insert(pairing.judgedKey)
        }
        // 否決比對用**與提名同一套正規化**（R1-fix I1）：verdict 記原始字串
        // （lossless），但抑制若比原始位元組，EN DASH 變體的否決壓不住 ASCII 連字號
        // 的同一寫法——否決失效而確認生效的不對稱，方向正好是危險的那邊。
        var rejectedNorm = Set<String>()
        for pairing in rejected where pairing.holderKind == .work {
            rejectedNorm.insert("\(pairing.holder)|\(normalize(pairing.literal))|\(pairing.judgedKey)")
        }

        var candidates: [ResolutionCandidate] = []
        var ambiguities: [AmbiguousMatch] = []
        for entry in entries {
            for (i, author) in entry.authors.enumerated() {
                guard case .literal(let literal) = author else { continue }
                let norm = normalize(literal)
                // tier 依信心降冪逐層評估，**第一個有存活命中的 tier 提名、其餘抑制**
                // （spec: highest matching tier）。每 tier 先剔除已否決配對——被否決的
                // 是**配對**不是 literal：exact 命中被否決時，低 tier 若命中**別人**
                // 仍是合法提名；同人同配對在低 tier 同樣被剔除。
                //
                // 沒有任何 tier 命中＝合法長期狀態，**不回報**——報出來會讓報告被
                // 噪音淹沒，而被淹沒的報告等於沒有報告。
                let tiers: [(ResolutionTier, Set<String>, String)] = [
                    (.exact, exactMap[norm] ?? [], "alias 完全命中"),
                    (.confirmedElsewhere, confirmedByLiteral[norm] ?? [],
                     "同 literal 已於他處 confirmed"),
                    (.reorder, reorderMap[LooseNameKey.reorderKey(literal)] ?? [],
                     "token 重排命中"),
                    (.initials,
                     Set(LooseNameKey.initialsKeys(literal).flatMap { initialsMap[$0] ?? [] }),
                     "姓＋首字母命中"),
                ]
                for (tier, rawHits, reason) in tiers {
                    let hits = rawHits.filter { key in
                        !rejectedNorm.contains("\(entry.citekey)|\(norm)|\(key)")
                    }
                    guard !hits.isEmpty else { continue }
                    if hits.count == 1, let key = hits.first {
                        // **淘汰而得的唯一命中要留痕**（R1-fix B7）：同 tier 曾有
                        // 同名候選被否決時，這一筆是「否決後餘一」而非天然唯一——
                        // 讀報告的人（與 LLM 批次 triage）要能分辨兩者。
                        let removed = rawHits.count - hits.count
                        let disclosed = removed > 0
                            ? reason + "（同 tier \(removed) 個同名候選已被否決）"
                            : reason
                        candidates.append(ResolutionCandidate(
                            citekey: entry.citekey, authorIndex: i, literal: literal,
                            personKey: key, reason: disclosed, tier: tier))
                    } else if let m = AmbiguousMatch(entryID: entry.id, citekey: entry.citekey,
                                                     authorIndex: i, literal: literal,
                                                     personKeys: hits, tier: tier) {
                        ambiguities.append(m)
                    }
                    break   // 最高命中 tier 之後全部抑制——同配對不重複出現
                }
            }
        }
        // ambiguities 用 `entryID` 打破 tie——重複 citekey 是被支援的損壞態，
        // `(citekey, authorIndex)` 在那時不是全序，相等元素的相對順序未定義
        // （Swift 的 sort 不保證穩定）。candidates 自 #303 起以 tier（信心降冪）
        // 為第一鍵（design D4）——高信心批次浮上來，campaign 從上往下收。
        return ResolutionReport(
            candidates: candidates.sorted {
                ($0.tier, $0.citekey, $0.authorIndex) < ($1.tier, $1.citekey, $1.authorIndex)
            },
            ambiguities: ambiguities.sorted {
                ($0.citekey, $0.authorIndex, $0.entryID.uuidString)
                    < ($1.citekey, $1.authorIndex, $1.entryID.uuidString)
            })
    }

    /// 高信心候選：literal 與某人 alias 正規化後完全命中，且不歧義。
    ///
    /// 薄包裝。`rejected`／`confirmed` 同 `resolve`——刻意必填。
    public static func candidates(entries: [Entry], people: [Person],
                                  rejected: Set<ResolutionPairing>,
                                  confirmed: Set<ResolutionPairing>) -> [ResolutionCandidate] {
        resolve(entries: entries, people: people,
                rejected: rejected, confirmed: confirmed).candidates
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
