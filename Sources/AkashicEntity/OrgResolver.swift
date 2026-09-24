import Foundation
import AkashicCore

/// 機構解析原語（#70 第二題）——org 版的 `PersonResolver`。
///
/// 「從未見過的字串認出屬於哪個 org」的入口。與 person 側同鐵律：**只提名，
/// 絕不自動歸戶**——`candidates` 出候選、`apply` 是使用者顯式確認後的第二步。
/// 比對走 `NameNormalization.matchingKey`（#81，統一連字號家族／NFKC／Cf 剝除／
/// 空白收斂），命中且不歧義才提名；同鍵對到 2+ 個 org＝歧義，整組排除。
public struct OrgResolutionCandidate: Equatable {

    /// 這個 literal 住在誰身上。
    ///
    /// **#166 之前這裡是 `personKey: String`**，於是 `organization.parents` 的
    /// literal 在兩步式流程裡進得去、出不來：`bootstrap-organizations` **會吃**
    /// parents 的 literal 並據此建 organization，但 `candidates` 只走 person 的
    /// affiliations——剛為它建出來的那個 organization 永遠配不上它。
    ///
    /// 沒有沿用 `personKey` 再加一個 `orgHolderKey`：那會讓「這筆候選屬於誰」有
    /// 兩個答案，而兩個答案總有一天會分岔。
    public enum Holder: Equatable {
        case person(String)
        case organization(String)
        /// **作者位的團體 literal**（#378）：`entries/<citekey>` 的第 n 個作者。
        ///
        /// 需要索引而不只是 citekey——同一筆可以有多個團體作者，而 `Author` 是
        /// 位置序列（#69 特地不排序 `authors`）。用 literal 字串比對會在同一筆有
        /// 兩個同名團體時改錯位置。
        case work(citekey: String, authorIndex: Int)

        /// 這個 holder 寫進 verdict value 時的 kind（#483）。
        ///
        /// **住在型別上，不在呼叫端。** 兩個呼叫端（`resolve_organizations` 的 apply 與
        /// reject）先前各自推導：apply 用窮盡 switch（#378），reject 用
        /// `{ if case .person … else .org }`——於是一個 `.work` 候選被否決時寫出
        /// `org:<citekey>`，而那條 verdict 在死 verdict 掃描下**必然**變成死的，訊息還會
        /// 把成因說成「遷移漏了這一格」。同一件事的兩份描述，其中一份漏了一個 case。
        ///
        /// 窮盡 switch 不寫 `default`：值域加第四個成員時要編譯錯誤，不是靜默落到某一邊。
        public var verdictHolderKind: ProvenanceReference.VerdictHolderKind {
            switch self {
            case .person:       return .person
            case .organization: return .org
            case .work:         return .work
            }
        }

        public var key: String {
            switch self {
            case let .person(k), let .organization(k): return k
            case let .work(citekey, _): return citekey
            }
        }
    }
    // **不給 `Comparable`。** 第一版給了，doc 還寫著「person 排在 organization
    // 前——輸出順序穩定」。那句話是真的，但**不是它造成的**：順序來自
    // `candidates` 先跑完 people 再跑 organizations 的 append 次序，那個
    // `<` 從頭到尾沒有任何呼叫端。mutation 把它整個反過來，23 條全綠。
    // 一個沒人用的排序 + 一句把功勞算給它的註解＝下一個人會依賴一個不存在的保證。

    /// 哪個記錄的哪一段 literal（用**值**定位，不用索引——段可能重排）。
    public var holder: Holder
    public var literal: String
    public var orgKey: String
    public var reason: String

    public init(holder: Holder, literal: String, orgKey: String, reason: String) {
        self.holder = holder
        self.literal = literal
        self.orgKey = orgKey
        self.reason = reason
    }
}

/// 同一個 literal 對到 **2+ 個 organization**——需要人判斷（#231）。
///
/// 與 person 側的 `AmbiguousMatch` 同形，但多帶 `holder`：org 的 literal 可能住在
/// person 的 `affiliations`，也可能住在另一個 org 的 `parents`（#166）。少了它，
/// 報告說不出「是誰的哪一段 literal 歧義」。
///
/// **與「沒有任何 org 匹配」語意不同**：後者是 `.literal` 的合法長期狀態（§8），
/// 前者是系統知道自己遇到了決定點。
public struct OrgAmbiguousMatch: Equatable {
    public var holder: OrgResolutionCandidate.Holder
    public var literal: String
    /// **這一段的效期。** 少了它，同一個 holder 的多段同名 literal 會產出完全相同、
    /// 不可裁決的重複紀錄——例如某人 2000–2005 與 2010–2015 兩段 affiliation 都寫
    /// `"Sinica"` 而它命中兩個 org 時，使用者無法**按時段**分別判給不同機構。
    ///
    /// `OrgResolutionCandidate` 刻意用**值**而非索引定位（段可能重排，且 `apply`
    /// 按值遷移所有仍為該 literal 的段）——那對「要套用什麼」是對的。但歧義是給**人**
    /// 看的報告，人需要知道是哪一段，所以這裡帶 range。
    public var range: DateRange
    /// 命中的 org key，**已排序**且 `count >= 2`。
    public var orgKeys: [String]

    /// 少於兩個 key 回 `nil`——「歧義只有一個候選」在型別層不可表達。
    public init?(holder: OrgResolutionCandidate.Holder, literal: String,
                 range: DateRange, orgKeys: Set<String>) {
        guard orgKeys.count >= 2 else { return nil }
        self.holder = holder
        self.literal = literal
        self.range = range
        self.orgKeys = orgKeys.sorted()
    }
}

/// 一次 org 解析的完整結果。**兩個欄位而非 sum type**——`apply` 只吃 `candidates`，
/// 於是「不小心 apply 一個歧義」在型別層寫不出來。
public struct OrgResolutionReport: Equatable {
    public var candidates: [OrgResolutionCandidate]
    public var ambiguities: [OrgAmbiguousMatch]

    public init(candidates: [OrgResolutionCandidate], ambiguities: [OrgAmbiguousMatch]) {
        self.candidates = candidates
        self.ambiguities = ambiguities
    }
}

public enum OrgResolver {
    /// 高信心候選：literal 與某 org 的 name variant 正規化後完全命中、且不歧義。
    ///
    /// 走兩處：person 的 `profile.affiliations` 與 **organization 的 `parents`**（#166）。
    ///
    /// ## parents 側多兩道排除，person 側不需要
    ///
    /// 1. **自我父權**：`org.parents` 的 literal 正規化後命中 org 自己。那不是
    ///    「歸戶」，是把記錄變成自己的上級。person 的 affiliation 指向自己是不可
    ///    表達的（型別不同），parents 則完全可能——同一個機構的別名寫在自己的
    ///    parents 裡（手工資料常見的順手記錄）就會撞上。
    /// 2. **環**：A 的 parent literal 命中 B、B 的 parent literal 命中 A。**本 repo
    ///    目前沒有任何地方偵測 org 階層的環**（`crossRecordIssues` 不查、載入不查），
    ///    所以歸戶造出來的環不會有人擋——它會安靜地存在，直到某個走 parents 的
    ///    消費端無限迴圈。歸戶是製造這種環最容易的路徑，防護就放在製造點。
    ///
    /// 環的判定包含**既有的 `.key` parents**與**本輪已接受的候選**：只看既有邊會
    /// 漏掉「兩個候選各自無害、湊在一起成環」。organizations 以 **key 排序**後依序
    /// 處理，所以「A→B 與 B→A 只能留一個」時留下的是哪一個是決定性的——不隨
    /// `load()` 的回傳順序或 Set 的雜湊擾動而變。
    public static func candidates(people: [Person],
                                  organizations: [Organization],
                                  rejected: Set<ResolutionPairing>,
                                  entries: [Entry] = []) -> [OrgResolutionCandidate] {
        resolve(people: people, organizations: organizations, rejected: rejected,
                entries: entries).candidates
    }

    /// 單一 traversal，`candidates` 與 `ambiguities` 的 source of truth（#231）。
    ///
    /// 與 person 側同理由：**不寫第二支遍歷**。這裡尤其重要——本函式的 parents 側
    /// 帶著自我父權與環的排除，兩支遍歷分岔時那些排除只會存在於其中一支。
    /// `rejected`：已否決配對（#232 design D5，語意同 `PersonResolver.resolve`）。
    /// holder 是持有 literal 的 person／organization key，judgedKey 是被判定的 org。
    /// **刻意無預設值**（同 `PersonResolver.resolve`——verify DA fix-10）。
    public static func resolve(people: [Person],
                               organizations: [Organization],
                               rejected: Set<ResolutionPairing>,
                               entries: [Entry] = []) -> OrgResolutionReport {
        // 正規化 org name variant → org keys（同名對 2+ org＝歧義）
        var nameMap: [String: Set<String>] = [:]
        for org in organizations {
            for seg in org.names.entries {
                nameMap[NameNormalization.matchingKey(seg.value), default: []].insert(org.key)
            }
        }
        // #231：歧義先前在這裡被靜默丟棄（`keys.count == 1 else { return nil }`）。
        // helper 保持回 `String?`——parents 側的環偵測吃的就是這個型別，而那段邏輯與
        // 歧義無關、不該被牽動。歧義改寫進捕獲的陣列。
        var ambiguities: [OrgAmbiguousMatch] = []
        /// **唯一性一律由原始命中集決定。** 過濾不得把「2+ 命中」變成「唯一命中」。
        ///
        /// R3 曾在這裡加一個 `admissible` 過濾器，理由是好的：parents 側有兩道 guard
        /// （自我父權、成環，#166 放在製造點），而歧義報告會把那兩道 guard **會拒絕**
        /// 的候選當成待人裁決的父機構。
        ///
        /// 但它是在**唯一性判定**上過濾，不只在報告上。R4 抓到兩個後果：
        ///
        /// 1. **`candidates()` 的行為變了**：base main 是「2+ 命中 → 不提名，交給人」，
        ///    過濾後變成「排除掉不可容許的、剩一個就自動提名」。`--apply` 會據此
        ///    **寫入**——而本 PR 的範圍是「讓歧義被看見」，不是改變消解語意。
        /// 2. **與順序相關**：`admissible` 裡的 `reaches` 讀 `edges`，而 `edges` 正是
        ///    這個迴圈在改的（`209` 行的「本輪已接受的也算數」是刻意的，環偵測需要
        ///    它）。於是「要不要問人」取決於 org key 的字母順序——同一份邏輯 store
        ///    換個 key 名字，答案就變。
        ///
        /// 第 2 點單獨就足以否決這個設計：**安全 guard 用會變動的 `edges` 是對的**
        /// （它只會多拒絕），但拿它決定「這是不是歧義」會讓非決定性洩進使用者看到
        /// 的東西。
        ///
        /// 因此回到原語意，代價是報告可能列出結構上不可能的候選（例如 holder 自己）。
        /// 那是**報告品質**問題，讓人多看一眼；前者是**寫入正確性**問題。兩害相權，
        /// 而且 `207`／`208` 兩道 guard 仍會擋住真的被套用的情形。
        ///
        /// 「自我父權該不該讓唯一性成立」是獨立的消解語意問題（它與順序無關，可以
        /// 單獨成立），但那要它自己的 issue 與 review，不該搭本 PR 的便車。
        func unambiguousMatch(_ literal: String, holder: OrgResolutionCandidate.Holder,
                              range: DateRange) -> String? {
            guard let raw = nameMap[NameNormalization.matchingKey(literal)] else { return nil }
            if raw.count == 1 { return raw.first }
            if let m = OrgAmbiguousMatch(holder: holder, literal: literal,
                                         range: range, orgKeys: raw) {
                ambiguities.append(m)
            }
            return nil
        }

        var result: [OrgResolutionCandidate] = []
        for person in people.sorted(by: { $0.key < $1.key }) {
            for seg in person.profile.affiliations.entries {
                guard case let .literal(literal) = seg.value,
                      let key = unambiguousMatch(literal, holder: .person(person.key), range: seg.range)
                else { continue }
                guard !rejected.contains(ResolutionPairing(
                    holderKind: .person, holder: person.key,
                    literal: literal, judgedKey: key)) else { continue }
                result.append(OrgResolutionCandidate(
                    holder: .person(person.key), literal: literal, orgKey: key,
                    reason: "org name 完全命中"))
            }
        }

        // #378：**作者位的團體 literal**。判準是大括號標記（`CorporateName.isMarked`）
        // ——WoS 的 `Group Authors` 與 biblatex 的 `author = {{Group Name}}` 共用的
        // **顯式**慣例（`Author` 型別的註解已載明）。不帶標記的 author literal 是人名，
        // 歸 `PersonResolver` 管，這裡一律不碰。
        //
        // 比對用**去標記後**的名字：organization 記錄的 `names` 不帶大括號（標記是
        // 傳輸慣例、不是名字的一部分），帶著它比對永遠不會命中。
        //
        // **range 傳空**：作者位沒有時間窗。affiliations 需要 range 是因為同一個
        // person 可能有多段同名 literal 要按時段分判（見 `OrgAmbiguousMatch.range`
        // 的 doc）；作者位的區辨是**索引**，而它已經在 holder 裡。
        //
        // citekey 排序：與 person 側同理由——輸出順序不隨 `load()` 的回傳順序擾動。
        for entry in entries.sorted(by: { $0.citekey < $1.citekey }) {
            for (i, author) in entry.authors.enumerated() {
                guard case let .literal(raw) = author,
                      CorporateName.isMarked(raw) else { continue }
                let literal = CorporateName.unmark(raw)
                let holder = OrgResolutionCandidate.Holder.work(citekey: entry.citekey,
                                                                authorIndex: i)
                guard let key = unambiguousMatch(literal, holder: holder,
                                                 range: DateRange()) else { continue }
                guard !rejected.contains(ResolutionPairing(
                    holderKind: .work, holder: entry.citekey,
                    literal: literal, judgedKey: key)) else { continue }
                result.append(OrgResolutionCandidate(
                    holder: holder, literal: literal, orgKey: key,
                    reason: "org name 完全命中（作者位的團體名）"))
            }
        }

        // 既有的 `.key` parents 邊：child → parents
        var edges: [String: Set<String>] = [:]
        for org in organizations {
            for seg in org.parents.entries {
                if case let .key(parent) = seg.value {
                    edges[org.key, default: []].insert(parent)
                }
            }
        }
        /// `from` 沿 parents 走得到 `target` 嗎（含自身）。
        func reaches(_ from: String, _ target: String) -> Bool {
            var seen: Set<String> = []
            var stack = [from]
            while let n = stack.popLast() {
                if n == target { return true }
                guard seen.insert(n).inserted else { continue }
                stack.append(contentsOf: edges[n] ?? [])
            }
            return false
        }

        for org in organizations.sorted(by: { $0.key < $1.key }) {
            for seg in org.parents.entries {
                guard case let .literal(literal) = seg.value,
                      let key = unambiguousMatch(
                        literal, holder: .organization(org.key), range: seg.range)
                else { continue }
                // **自我父權**。`reaches` 含自身，所以下一行其實也擋得住它——
                // 席位 mutation 實測：拿掉這行 23 條全綠，**它現行不可達**。
                // 保留而非刪除，因為它釘的是「`reaches` 把自身算在內」這個前提；
                // 有人把它改成「嚴格可達」（一個很自然的重構）時這行就會活起來。
                // **但測試不得宣稱在驗它**——`testSelfParentIsNeverProposed` 實際上
                // 是被下一行擋下的（同 `ISO8601Prefix.compatible` 的分隔點檢查）。
                guard key != org.key else { continue }
                guard !reaches(key, org.key) else { continue }  // 會成環（含自身）
                guard !rejected.contains(ResolutionPairing(
                    holderKind: .org, holder: org.key,
                    literal: literal, judgedKey: key)) else { continue }
                edges[org.key, default: []].insert(key)         // 本輪已接受的也算數
                result.append(OrgResolutionCandidate(
                    holder: .organization(org.key), literal: literal, orgKey: key,
                    reason: "org name 完全命中（parents）"))
            }
        }
        // ambiguities 不排序：holder 的走訪順序已經是決定性的（people 依 key 排序、
        // 再 organizations 依 key 排序），而同一 holder 內依 timeline 段的既有順序。
        // 加一層排序會覆蓋掉那個既有的、有意義的順序。
        return OrgResolutionReport(candidates: result, ambiguities: ambiguities)
    }

    /// 套用結果。people 與 organizations **各自回傳新副本**，不動原陣列。
    public struct Applied: Equatable {
        public var people: [Person]
        public var organizations: [Organization]
        /// 作者位被歸戶的 entry（#378）。呼叫端沒傳 `entries` 時是空陣列。
        public var entries: [Entry] = []
    }

    /// 把已確認的候選套用到 people 與 organizations。
    ///
    /// **只改真的還是那個 literal 的段**（值比對；段被改過就跳過——避免套用一份
    /// 過期的候選）。這條在 org 側同樣重要：candidates 與 apply 之間可能隔著
    /// 使用者的確認時間。
    public static func apply(_ candidates: [OrgResolutionCandidate],
                             to people: [Person],
                             organizations: [Organization],
                             entries: [Entry] = []) -> Applied {
        var byPerson = Dictionary(people.map { ($0.key, $0) }, uniquingKeysWith: { _, last in last })
        var byOrg = Dictionary(organizations.map { ($0.key, $0) },
                               uniquingKeysWith: { _, last in last })

        /// 把 timeline 裡值仍是 `literal` 的段換成 `.key(orgKey)`；有沒有改回傳 Bool。
        /// 抽出來是因為 person 的 affiliations 與 org 的 parents 都是
        /// `TimelineOf<OrgRef>`——寫兩份的話兩份會分岔（`source`／`note` 保留與否
        /// 這種細節尤其容易只改一邊）。
        func migrate(_ timeline: TimelineOf<OrgRef>, literal: String,
                     to orgKey: String) -> TimelineOf<OrgRef>? {
            var changed = false
            let out = timeline.entries.map { seg -> TemporalValue<OrgRef> in
                if case let .literal(s) = seg.value, s == literal {
                    changed = true
                    return TemporalValue(value: .key(orgKey), range: seg.range,
                                         source: seg.source, note: seg.note)
                }
                return seg
            }
            return changed ? TimelineOf(out) : nil
        }

        // #628：作品側以陣列位置就地改寫，不經字典對應回輸出（同 #627 的 `PersonResolver.apply`）——
        // citekey 對應回輸出會把同 citekey 的每一筆換成同一份；無法唯一定位的位置一律不改
        let unlocatable = entries.unlocatableCitekeys
        var indexByCitekey: [String: Int] = [:]
        for (i, e) in entries.enumerated() where !unlocatable.contains(e.citekey) { indexByCitekey[e.citekey] = i }
        var outEntries = entries

        for c in candidates {
            switch c.holder {
            case let .work(citekey, index):
                // 作者位（#378）。三道保守側檢查，任一不成立就跳過：
                // 記錄還在／索引還有效／那個位置**仍然是**當初提名的那個 literal。
                // 第三道是關鍵——候選清單可能跨越資料變動（`apply` 是 public），
                // 而作者是位置序列，索引在別人插入後會指到另一個人。
                guard let i = indexByCitekey[citekey], index < outEntries[i].authors.count,
                      case let .literal(s) = outEntries[i].authors[index],
                      CorporateName.unmark(s) == CorporateName.unmark(c.literal)
                else { continue }
                outEntries[i].authors[index] = .organization(c.orgKey)
            case let .person(key):
                guard var person = byPerson[key],
                      let migrated = migrate(person.profile.affiliations,
                                             literal: c.literal, to: c.orgKey) else { continue }
                person.profile.affiliations = migrated
                byPerson[key] = person
            case let .organization(key):
                // **自我父權在這裡也擋一次。** `candidates` 已排除它，但 `apply` 是
                // public 且接受任何候選清單——使用者可以手工組一份、或套用一份跨越
                // 資料變動的舊清單。不可逆寫入的防護不該只放在提名端。
                guard c.orgKey != key, var org = byOrg[key],
                      let migrated = migrate(org.parents,
                                             literal: c.literal, to: c.orgKey) else { continue }
                org.parents = migrated
                byOrg[key] = org
            }
        }
        return Applied(people: people.map { byPerson[$0.key] ?? $0 },
                       organizations: organizations.map { byOrg[$0.key] ?? $0 },
                       entries: outEntries)
    }
}
