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

/// 一次歸戶寫入需要的**全部**資訊：定位一個作者位，並指出它是誰。
///
/// **抽成協定的理由**：`PersonResolver.apply` 實際只用到這四個欄位做寫入與三道守衛
/// （記錄存在／索引有效／該位置仍是那個 literal），`tier` 完全不參與。抽出來之後
/// **提名**（`ResolutionCandidate`，帶 tier）與**判定**（`JudgedPairing`，帶 judgement）
/// 可以共用同一條寫入路徑，而不必讓其中一方假裝成另一方。
///
/// **`AmbiguousMatch` 刻意不 conform，而且是結構上做不到**：它的欄位是
/// `personKeys: [String]`（複數）——歧義的「是哪一個人」尚未決定，所以單數的
/// `personKey` 在那個型別上不存在。既有的「兩個欄位而非 sum type」設計靠同一件事
/// 讓「不小心 apply 一個歧義」寫不出來；本協定沿用它，不另立守衛。
public protocol AuthorPairing {
    var citekey: String { get }
    var authorIndex: Int { get }
    var literal: String { get }
    var personKey: String { get }
}

/// 一次**判定**：這一篇的這個作者位是這個人，而這是憑什麼。
///
/// 與 `ResolutionCandidate` 的差別不在資料量，在**主張的種類**：
///
/// | | 主張 | 誰做的 | 作用範圍 |
/// |---|---|---|---|
/// | `ResolutionCandidate` | 「這個字串的鍵撞到這個人」 | 提名器（字串比對） | 那一個 occurrence |
/// | `JudgedPairing` | 「這個作者位**是**這個人」 | 人／AI（名字以外的證據） | 那一個 occurrence |
///
/// **無 `tier`**：tier 記的是「怎麼被提名的」且依信心排序；判定不是被提名出來的，
/// 給它一個 tier 會謊報來歷（`.claude/rules/identity-is-judged-not-matched.md`）。
///
/// **無 `restsOn`**：證據依 #280 的裁決住被判 person 的 `references`，verdict 刻意不攜
/// 第二個內容指標（`.claude/rules/entity-backlink-completeness.md` 封閉列舉第 13 條）。
public struct JudgedPairing: Equatable, AuthorPairing {
    public let citekey: String
    public let authorIndex: Int
    public let literal: String
    public let personKey: String

    /// 為什麼這樣判——**原文逐字保留**，不 trim、不改寫。
    public let judgement: String

    /// 空白 judgement 回 `nil`——那個狀態在型別層不存在。
    ///
    /// 判準是「去掉空白與換行後為空」，不是「等於空字串」：一個只有空格的 judgement
    /// 與沒有 judgement 在資訊上相同，而只擋 `""` 會讓前者穿過去。
    public init?(citekey: String, authorIndex: Int, literal: String,
                 personKey: String, judgement: String) {
        guard !judgement.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return nil }
        self.citekey = citekey
        self.authorIndex = authorIndex
        self.literal = literal
        self.personKey = personKey
        self.judgement = judgement
    }
}

public struct ResolutionCandidate: Equatable, AuthorPairing {
    public var citekey: String
    public var authorIndex: Int
    public var literal: String
    public var personKey: String
    public var reason: String
    /// 提名層（#303）。**刻意無預設值**（R1-fix I3）——預設 `.exact` 是往最高
    /// 信心值 fail-open，與同檔 `rejected`／`confirmed` 必填的裁決同一條理由：
    /// 位置決定了誰會走它，required 讓「忘了帶 tier」變成編譯錯誤。
    public var tier: ResolutionTier
    /// 這個位置被否決淘汰掉的候選數（去重的 person key，跨 tier fall-through 也算）。
    /// 大於 0 表示這筆是**淘汰而得的唯一命中**：原本有別的人選，被否決之後只剩它，
    /// 而沒有人判定過它是對的（#624）。
    ///
    /// 這件事原本只寫進 `reason`（給人讀），程式讀不到，於是 CLI 的篩選式批次
    /// `--apply` 會把它升格。**刻意無預設值**——理由同 `tier`：`= 0` 會往「不是
    /// 淘汰所得」fail-open。
    public var eliminatedPairings: Int

    public init(citekey: String, authorIndex: Int, literal: String,
                personKey: String, reason: String, tier: ResolutionTier,
                eliminatedPairings: Int) {
        self.citekey = citekey
        self.authorIndex = authorIndex
        self.literal = literal
        self.personKey = personKey
        self.reason = reason
        self.tier = tier
        self.eliminatedPairings = eliminatedPairings
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
    public var rowID: String { "\(citekey):\(authorIndex)" }   // display-safe-exempt: 回程把手須逐字，消毒會讓 apply 對不上（且 displaySafe 不冪等）

    /// 釘 person 的三段 id（R1-fix B8／R2-fix R3-5）：apply/reject 的把手。
    /// **住在型別上**——service 列表與 CLI 送出必須是同一個定義（#236 R4 的
    /// 三份拷貝分岔教訓；R2 實測 CLI 自組 rowID 送出＝pin 整面失效）。
    public var pinnedID: String { "\(rowID):\(personKey)" }   // display-safe-exempt: 回程把手須逐字，消毒會讓 apply 對不上（且 displaySafe 不冪等）
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
    /// （被支援的損壞態），此時兩筆歧義在 `(citekey, authorIndex)` 上完全相同。
    ///
    /// 帶了 id 讓**報告**可定位；寫入面則一律不猜——`PersonResolver.apply` 對重複
    /// citekey 或重複 id 的位置都不改寫，resolve-people 各腿另行拒絕或具名略過（#627）。
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
                               confirmed: [ResolutionPairing: String]) -> ResolutionReport {
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
        // norm literal → person key → 來源 rules（R3-7：ancestry 隨提名可見）
        var confirmedByLiteral: [String: [String: Set<String>]] = [:]
        for (pairing, rule) in confirmed where pairing.holderKind == .work {
            confirmedByLiteral[normalize(pairing.literal), default: [:]][pairing.judgedKey, default: []]
                .insert(rule)
        }
        // 否決比對用**與提名同一套正規化**（R1-fix I1）：verdict 記原始字串
        // （lossless），但抑制若比原始位元組，EN DASH 變體的否決壓不住 ASCII 連字號
        // 的同一寫法——否決失效而確認生效的不對稱，方向正好是危險的那邊。
        var rejectedNorm = Set<RejectedPairKey>()   // struct 鍵、無分隔符（R25，R24 verify security 第 27 列；`|` 可出現在 literal 裡）
        for pairing in rejected where pairing.holderKind == .work {
            rejectedNorm.insert(RejectedPairKey(holder: pairing.holder, literal: normalize(pairing.literal), judged: pairing.judgedKey))
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
                    (.confirmedElsewhere, Set(confirmedByLiteral[norm]?.keys ?? [:].keys),
                     "同 literal 已於他處 confirmed"),
                    (.reorder, reorderMap[LooseNameKey.reorderKey(literal)] ?? [],
                     "token 重排命中"),
                    (.initials,
                     Set(LooseNameKey.initialsKeys(literal).flatMap { initialsMap[$0] ?? [] }),
                     "姓＋首字母命中"),
                ]
                // 跨 tier 淘汰累計（R2-fix R3-6，spec R7 後果 b）：高 tier 的命中
                // 被否決**清空**而 fall-through 時，低 tier 的提名同樣要留痕——
                // 「使用者的 no 變成對別人的 yes」不分層都要可見。
                // R3-fix R4-2：以**去重的 person key 集合**計淘汰——同一筆否決的
                // 對象幾乎必然同時住在多個鍵空間（exact 命中者的名字也在 reorder／
                // initials map 裡），逐 tier 累加會把 1 筆否決報成 3（R3 實測同畫面
                // 自相矛盾：reason 說 3、沉底列與三態計數說 1）。
                var eliminated = Set<String>()
                for (tier, rawHits, baseReason) in tiers {
                    let hits = rawHits.filter { key in
                        !rejectedNorm.contains(RejectedPairKey(holder: entry.citekey, literal: norm, judged: key))
                    }
                    eliminated.formUnion(rawHits.subtracting(hits))
                    guard !hits.isEmpty else { continue }
                    if hits.count == 1, let key = hits.first {
                        var reason = baseReason
                        // R3-7：confirmed-elsewhere 的弱血統可見——exact 血統不加噪音
                        if tier == .confirmedElsewhere,
                           let rules = confirmedByLiteral[norm]?[key] {
                            // R4-8：rule 尾註是 store 衍生自由文字——只 verbatim 已知
                            // 封閉形（^[a-z][a-z-]*$），異形夾住並標記，防偽造揭露樣式
                            // 混進 reason（R3 security 的 forged-disclosure probe）
                            let weak = rules.filter { $0 != ResolutionLedger.personRule }
                                .map { r -> String in
                                    r.range(of: "^[a-z][a-z-]{0,60}$",
                                            options: .regularExpression) != nil
                                        ? r : "非標準rule"
                                }.sorted()
                            if !weak.isEmpty {
                                reason += "（rule: \(weak.joined(separator: "、"))）"
                            }
                        }
                        // **淘汰而得的唯一命中要留痕**（R1-fix B7）：同 tier 餘一
                        // 與高 tier 全滅 fall-through 兩種來源都算——去重後計人
                        if !eliminated.isEmpty {
                            reason += "（此位置 \(eliminated.count) 個候選配對已被否決）"
                        }
                        candidates.append(ResolutionCandidate(
                            citekey: entry.citekey, authorIndex: i, literal: literal,
                            personKey: key, reason: reason, tier: tier,
                            eliminatedPairings: eliminated.count))
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
                                  confirmed: [ResolutionPairing: String]) -> [ResolutionCandidate] {
        resolve(entries: entries, people: people,
                rejected: rejected, confirmed: confirmed).candidates
    }

    /// 把已確認的候選套用到 entries（回傳新副本，不動原陣列）。
    /// 泛型化（change `per-work-judged-authorship`）：吃任何 `AuthorPairing`，
    /// 於是**提名**（`ResolutionCandidate`）與**判定**（`JudgedPairing`）共用同一條寫入
    /// 路徑與同一組守衛。寫入邏輯逐字不變——這裡只放寬入參型別，不放寬任何檢查。
    ///
    /// `AmbiguousMatch` 仍傳不進來：它沒有單數 `personKey`
    /// （`JudgedPairingTests.testAmbiguousMatchHasNoSingularPersonKey` 釘住這件事）。
    public static func apply<P: AuthorPairing>(_ candidates: [P], to entries: [Entry]) -> [Entry] {
        // #627：**就地以陣列位置改寫，不經任何字典對應回輸出**。先前兩版都經過字典：
        //   - 以 citekey 對應（#627 之前）：同 citekey 的每一筆都被換成同一份；
        //   - 以 id 對應（#627 R0）：同 id 的兩筆（半遷移留下的 entities／legacy 拷貝，或
        //     兩筆不同 citekey 共用 UUID）會互相覆寫，而 Dictionary 的 values 順序每個
        //     process 不同，選中誰是隨機的（R1 verify 以真 binary 重現 4/6）。
        // citekey 重複、或 entry id 重複的位置一律不改——以 citekey 定位會猜是哪一筆，以 id
        // 寫檔（entities/<id>.yaml）會寫到兄弟的檔。上游各腿另行拒絕或具名略過，這裡是最後
        // 一道防線：它保證輸出裡**只有候選命中的那一格**可能與輸入不同。
        let duplicatedCK = entries.duplicatedCitekeys
        var idCount: [UUID: Int] = [:]
        for e in entries { idCount[e.id, default: 0] += 1 }
        var indexByCitekey: [String: Int] = [:]
        for (i, e) in entries.enumerated()
        where !duplicatedCK.contains(e.citekey) && idCount[e.id] == 1 {
            indexByCitekey[e.citekey] = i
        }
        var out = entries
        for candidate in candidates {
            guard let i = indexByCitekey[candidate.citekey],
                  out[i].authors.indices.contains(candidate.authorIndex),
                  case .literal(let current) = out[i].authors[candidate.authorIndex],
                  current == candidate.literal else { continue }
            out[i].authors[candidate.authorIndex] = .key(candidate.personKey)
        }
        return out
    }

    /// 比對面吃正規化（#81：NFKC＋連字號家族＋空白收斂），輸出仍是原字串——
    /// 正規化只住在配對鍵裡，永不外洩成資料。
    static func normalize(_ s: String) -> String {
        NameNormalization.matchingKey(s)
    }
}
