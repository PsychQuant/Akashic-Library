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

        public var key: String {
            switch self {
            case let .person(k), let .organization(k): return k
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
                                  organizations: [Organization]) -> [OrgResolutionCandidate] {
        // 正規化 org name variant → org keys（同名對 2+ org＝歧義，整組排除）
        var nameMap: [String: Set<String>] = [:]
        for org in organizations {
            for seg in org.names.entries {
                nameMap[NameNormalization.matchingKey(seg.value), default: []].insert(org.key)
            }
        }
        func unambiguousMatch(_ literal: String) -> String? {
            guard let keys = nameMap[NameNormalization.matchingKey(literal)],
                  keys.count == 1 else { return nil }
            return keys.first
        }

        var result: [OrgResolutionCandidate] = []
        for person in people.sorted(by: { $0.key < $1.key }) {
            for seg in person.profile.affiliations.entries {
                guard case let .literal(literal) = seg.value,
                      let key = unambiguousMatch(literal) else { continue }
                result.append(OrgResolutionCandidate(
                    holder: .person(person.key), literal: literal, orgKey: key,
                    reason: "org name 完全命中"))
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
                      let key = unambiguousMatch(literal) else { continue }
                // **自我父權**。`reaches` 含自身，所以下一行其實也擋得住它——
                // 席位 mutation 實測：拿掉這行 23 條全綠，**它現行不可達**。
                // 保留而非刪除，因為它釘的是「`reaches` 把自身算在內」這個前提；
                // 有人把它改成「嚴格可達」（一個很自然的重構）時這行就會活起來。
                // **但測試不得宣稱在驗它**——`testSelfParentIsNeverProposed` 實際上
                // 是被下一行擋下的（同 `ISO8601Prefix.compatible` 的分隔點檢查）。
                guard key != org.key else { continue }
                guard !reaches(key, org.key) else { continue }  // 會成環（含自身）
                edges[org.key, default: []].insert(key)         // 本輪已接受的也算數
                result.append(OrgResolutionCandidate(
                    holder: .organization(org.key), literal: literal, orgKey: key,
                    reason: "org name 完全命中（parents）"))
            }
        }
        return result
    }

    /// 套用結果。people 與 organizations **各自回傳新副本**，不動原陣列。
    public struct Applied: Equatable {
        public var people: [Person]
        public var organizations: [Organization]
    }

    /// 把已確認的候選套用到 people 與 organizations。
    ///
    /// **只改真的還是那個 literal 的段**（值比對；段被改過就跳過——避免套用一份
    /// 過期的候選）。這條在 org 側同樣重要：candidates 與 apply 之間可能隔著
    /// 使用者的確認時間。
    public static func apply(_ candidates: [OrgResolutionCandidate],
                             to people: [Person],
                             organizations: [Organization]) -> Applied {
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

        for c in candidates {
            switch c.holder {
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
                       organizations: organizations.map { byOrg[$0.key] ?? $0 })
    }
}
