import Foundation
import AkashicCore

/// 從 `Entry.venues` 的 literal 建 venue 記錄（#367）。
///
/// 平移 `PersonBootstrap`／`OrgBootstrap` 的機制到載體面。**這個檔案先前不存在**，
/// 而那個缺席在檔案層就看得見：`Sources/AkashicEntity/` 有 `PersonBootstrap.swift`、
/// `OrgBootstrap.swift`、`VenueResolver.swift`，唯獨沒有它。
///
/// ## 缺的是鏈條的第一環
///
/// ```
/// migrate-venues ──→ 803 筆 literal ──→ ??? ──→ venue entity ──→ resolve-venues
///      ✅ 已做            ✅ 已有        ❌ 缺        ❌ 0 個         ✅ 已實作但空轉
/// ```
///
/// 實測（2026-08-19）：`resolve-venues` 的 dry-run **回零候選**——那不是 bug，它的工作是
/// 拿 literal 去比對**既有的** venue entity，而 entity 有 0 個。唯一的建檔路徑
/// `add-venue` 一次一筆，**441 個 distinct 刊名要手打 441 次**。
///
/// 所以 `literal-first-then-key` 的 campaign 在 venue 域**結構上無法離開第 0 步**。
///
/// ## `VenueType` 從哪來——這是本型別唯一的設計問題
///
/// `VenueType` 是封閉列舉（#324；值域見該型別），而批次建檔必須給每個 venue 一個值。
///
/// **答案是「讀它從哪個欄位來」，不是猜。** `VenueDerivation.literals(for:)` 是產生
/// 那些 literal 的**唯一**來源，而它逐欄位取值：`journaltitle` → `.periodical`、
/// `booktitle`（僅 `conferenceSession`）→ `.conference`、`publisher` → `.publisher`。
/// literal 從哪個欄位來，那個欄位的**意思**就決定了載體種類。
///
/// 注意 `journaltitle` 對到的是 **`.periodical` 而不是 `.journal`**——#324 把 journal
/// 併進 periodical（APA7 的 periodical 涵蓋 journal／magazine／newspaper／newsletter／
/// blog，**索取同一組欄位**）。biblatex 的欄位名與我們的值域**不是同一套詞彙**。
///
/// 實測支持這一點：441 個 distinct literal 裡 **402 來自 `journaltitle`、36 來自
/// `publisher`**，各自只對應一個欄位；**零個** literal 同時來自兩種欄位。
///
/// ### 這不牴觸 D4「type 推定不寫進 ref，歸戶時人裁」
///
/// D4 說的是 **`VenueRef` 不攜帶 type 猜測**——ref 只有 `.key`／`.literal` 兩態。
/// 它沒有說建實體時不能從來源判定；而「歸戶時人裁」指的正是**建實體／升格這一步**，
/// 也就是本型別產出候選、由人審過 dry-run 後才 `--apply` 的那一步。
///
/// 同 `bootstrap-people` 的既有形狀：機械產候選、dry-run 預設、人審後才寫入。
///
/// ## 鐵律（與 person／org 側相同）
///
/// **只建立、不歸戶。** 歸戶是 `resolve-venues` 的第二步、交人確認。本型別產出的
/// venue entity 不會去動任何 entry 的 `venues:`——那些 literal 原樣留著，直到有人
/// 跑消歧並確認。
///
/// **寧可分割，絕不合併。** 同名不同刊在庫裡還沒有第二筆記錄時，歧義偵測不會觸發
/// ——那正是自動合併會出錯而且看起來沒出錯的情境。
public enum VenueBootstrap {

    /// 一個可建檔的候選。
    public struct Candidate: Equatable {
        public let key: String
        /// 該組的所有寫法（保留原字串；正規化只住配對鍵）。
        public let names: [String]
        public let type: VenueType
        public let occurrences: Int
        /// 判定 `type` 的依據——哪個來源欄位。**印給人看的**：讓審 dry-run 的人
        /// 能一眼看出「這是期刊」是讀出來的還是猜的。
        public let evidence: String
    }

    /// 不建檔也不提名的 literal，**帶理由**。兩類（#554 R5 verify 第 5 列起是兩類）：產不出 key 的
    /// （純 CJK 刊名等）、與**不能作為名字的**（純符號、含控制／格式／不可見字元、空白——
    /// `NameIdentity.wellFormednessIssue` 拒的）。**不靜默丟**——同 `OrgBootstrap` 的 `dropped`：
    /// model 端有欄位而沒人印，與丟棄在效果上完全相同；R5 把第二類 `continue` 在分組之前，
    /// 連 occurrences 都不累計，`bootstrap-venues` 對它零字，而同一個型別的 doc 寫著「不靜默丟」。
    public struct Dropped: Equatable {
        public let name: String
        public let occurrences: Int
        /// 為什麼不建：印給審 dry-run 的人看的，兩類要分得開（一類的出口是 `add-venue` 手動指定 key，
        /// 另一類的出口是修 work 的 `journaltitle` 欄位）。
        public let reason: String

        public init(name: String, occurrences: Int, reason: String) {
            self.name = name
            self.occurrences = occurrences
            self.reason = reason
        }
    }

    /// 同一個刊名來自**不同種類**的來源欄位。
    ///
    /// **目前零實例**（實測 441 個 literal 全部只對應一個欄位種類）。寫這個守衛的理由
    /// 見 `.claude/rules/zero-instance-guards.md` 的第 4 列：不寫的話，這種記錄會**靜默
    /// 取其中一個 type**，而 `VenueType` 決定「哪些欄位存在」（#324 的 §11 判準）
    /// ——取錯的代價不是標籤錯，是整組欄位需求錯。
    public struct TypeConflict: Equatable {
        public let name: String
        public let types: [VenueType]
        public let occurrences: Int
    }

    /// 與既有 venue **寬鬆共鍵**的群（#548）——只提名、不建檔。
    ///
    /// 形狀對齊 `PersonBootstrap.PendingResolutionGroup`，判準**不同**：人名走
    /// `LooseNameKey`（重排／姓＋首字母），刊名走 `LooseTitleKey`（標點／`&`／前導
    /// 冠詞）。理由見 `LooseTitleKey` 的檔頭——那是裁決不是省略。
    public struct PendingResolution: Equatable {
        /// 這一組的所有寫法（保留原字串）。
        public let names: [String]
        public let occurrences: Int
        /// 撞到的既有 venue key（排序）——印給人看「撞的是誰」。
        public let matchedKeys: [String]
    }

    public struct Result: Equatable {
        public let candidates: [Candidate]
        public let dropped: [Dropped]
        public let conflicts: [TypeConflict]
        /// 與既有 venue 寬鬆共鍵、**先消歧再說**的群（#548）。
        public let pendingResolution: [PendingResolution]

        public init(candidates: [Candidate], dropped: [Dropped], conflicts: [TypeConflict],
                    pendingResolution: [PendingResolution] = []) {
            self.candidates = candidates
            self.dropped = dropped
            self.conflicts = conflicts
            self.pendingResolution = pendingResolution
        }
    }

    /// 來源欄位 → 載體種類。**這張表是 `VenueDerivation` 取值順序的鏡像**，
    /// 而那個順序是產生 literal 的唯一來源。
    ///
    /// 三個欄位對三個 `VenueType` 值，**一對一**——所以這裡沒有優先序問題，
    /// 只有「這個 literal 從哪來」。
    static func venueType(forSourceField field: String) -> VenueType? {
        switch field {
        // **`.periodical` 不是 `.journal`**：#324 把 journal 併進 periodical，因為
        // APA7 的 periodical 涵蓋 journal／magazine／newspaper／newsletter／blog，
        // **索取同一組欄位**。`journaltitle` 這個欄位名是 biblatex 的詞彙，
        // 對映到我們的值域要走 #324 的判準，不是照字面。
        case "journaltitle": return .periodical
        case "booktitle":    return .conference
        case "publisher":    return .publisher
        default:             return nil
        }
    }

    /// 走訪每筆 entry，把它的 literal venue 對回**產生它的那個欄位**。
    ///
    /// 不重新發明推導：`VenueDerivation.literals(for:)` 決定了哪些欄位會產生 literal
    /// 以及順序，這裡只是把同一組欄位再讀一次以取得來源標籤。兩者若漂移，
    /// `testSourceFieldsMirrorVenueDerivation` 會紅。
    static func literalsWithSource(_ entry: Entry) -> [(name: String, field: String)] {
        let derived = Set(VenueDerivation.literals(for: entry).compactMap { ref -> String? in
            if case let .literal(s) = ref { return s }
            return nil
        })
        var out: [(name: String, field: String)] = []
        for field in ["journaltitle", "booktitle", "publisher"] {
            guard let v = entry.fields[field], !v.isEmpty, derived.contains(v) else { continue }
            out.append((name: v, field: field))
        }
        return out
    }

    /// 候選 ＋ 丟棄 ＋ 型別衝突。**分組與 key 產生的唯一實作。**
    public static func result(entries: [Entry], existing: [Venue]) -> Result {
        // 既有 venue 的所有寫法（正規化）——已建檔的不重造。
        let known = Set(existing.flatMap { v in
            v.names.entries.map { NameNormalization.matchingKey($0.value) }
        })
        // #548：既有 venue 的**寬鬆**索引。`known` 只摺大小寫與空白，於是同一本刊
        // 只差 `:` ／ `(` ／ `-` 就成了兩筆記錄——實測 live store 已有 5 組／11 筆
        // （JRSS-B 三筆、JRSS-C 三筆、American Statistician、AJP、BJMSP）。
        var looseIndex: [String: Set<String>] = [:]
        for v in existing {
            for n in v.names.entries {
                let lk = LooseTitleKey.key(n.value)
                guard !lk.isEmpty else { continue }
                looseIndex[lk, default: []].insert(v.key)
            }
        }
        var takenKeys = Set(existing.map(\.key))

        struct Group {
            var names: [String] = []
            var types: Set<VenueType> = []
            var fields: Set<String> = []
            var count = 0
        }
        var groups: [String: Group] = [:]
        // 不能作為名字的 literal（純符號、含控制／格式／不可見字元、空白）——**不建、但要印**
        // （R5 verify 第 5 列：上一版在這裡 `continue`，連 occurrences 都不累計，`bootstrap-venues`
        // 對它零字）。以原字串為鍵：操作者要修的是 work 的 `journaltitle` 欄位裡那個字串，
        // 印 canonical 形會讓他找不到。
        var rejected: [String: (reason: String, count: Int)] = [:]

        for entry in entries {
            for (raw, field) in literalsWithSource(entry) {
                // 存 canonical（#554 D8：names 的不變式在 `Venue.validate()`，寫入者先 canonical）；
                // 讀進來仍是 literal 的原字串，只是空白不是名字的一部分。不能作為名字的路由到
                // `dropped` 並留在 literal——bootstrap 不建一筆會被 validate 擋的記錄
                let name = NameIdentity.canonical(raw)
                // **先問「庫裡是不是已經有這本刊」、再問「這能不能當名字」**（R6 verify 第 16 列）：
                // `matchingKey` 會刪 Cf，只差一個 soft hyphen 的既有刊名 literal 本來就能被 resolve-venues
                // 歸戶，把它印成「不建檔…請修來源欄位」是不必要的動作，且它的次數會從乾淨群裡消失
                let id = NameNormalization.matchingKey(name)
                guard !known.contains(id) else { continue }
                if let why = NameIdentity.wellFormednessIssue(name) {
                    // bootstrap 脈絡的出口是修 work 的來源欄位——謂詞的訊息是寫給手改 venue YAML 的人的
                    // （R6 verify 第 34 列），這裡補上這個脈絡自己的修法
                    rejected[raw, default: (reason: why + "（來自 work 的來源欄位 journaltitle／booktitle／publisher，修那裡）", count: 0)].count += 1
                    continue
                }
                guard let type = venueType(forSourceField: field) else { continue }
                var g = groups[id] ?? Group()
                if !g.names.contains(name) { g.names.append(name) }
                g.types.insert(type)
                g.fields.insert(field)
                g.count += 1
                groups[id] = g
            }
        }

        var candidates: [Candidate] = []
        var dropped: [Dropped] = []
        var conflicts: [TypeConflict] = []
        var pending: [PendingResolution] = []

        for (_, g) in groups.sorted(by: {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }) {
            let sortedNames = g.names.sorted()
            // #548：**先問「庫裡是不是已經有這本刊了」**。撞到就不建檔——同
            // `PersonBootstrap` 的既有形狀，出口是把這個寫法補成既有 venue 的
            // variant（`update-venue --add-variant`），下一輪它就成為精確命中。
            //
            // 這一步放在型別衝突**之前**：撞到既有記錄時，type 該是什麼由那筆既有
            // 記錄決定，不必再問一次。
            let hits = Set(sortedNames.flatMap { looseIndex[LooseTitleKey.key($0)] ?? [] })
            if !hits.isEmpty {
                pending.append(PendingResolution(
                    names: sortedNames, occurrences: g.count, matchedKeys: hits.sorted()))
                continue
            }
            guard g.types.count == 1, let type = g.types.first else {
                // 同名來自不同種類的欄位——**不建檔，交人裁**。取任一個都可能讓整組
                // 欄位需求錯（#324：VenueType 決定哪些欄位存在）。
                conflicts.append(TypeConflict(
                    name: sortedNames[0],
                    types: g.types.sorted { $0.rawValue < $1.rawValue },
                    occurrences: g.count))
                continue
            }
            guard let key = OrgBootstrap.suggestedKey(from: sortedNames[0], taken: takenKeys) else {
                dropped.append(Dropped(name: sortedNames[0], occurrences: g.count,
                                       reason: "產不出 ASCII key，需人工指定"))
                continue
            }
            takenKeys.insert(key)
            candidates.append(Candidate(
                key: key, names: sortedNames, type: type, occurrences: g.count,
                evidence: g.fields.sorted().joined(separator: "＋")))
        }
        for (raw, r) in rejected.sorted(by: {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }) {
            dropped.append(Dropped(name: raw, occurrences: r.count, reason: r.reason))
        }
        return Result(candidates: candidates, dropped: dropped, conflicts: conflicts,
                      pendingResolution: pending.sorted {
                          $0.occurrences == $1.occurrences
                              ? ($0.names.first ?? "") < ($1.names.first ?? "")
                              : $0.occurrences > $1.occurrences
                      })
    }

    /// 把候選建成 venue 記錄。**只建立、不歸戶**——entry 的 `venues:` literal 原樣留著。
    public static func makeVenues(_ candidates: [Candidate]) -> [Venue] {
        candidates.map { c in
            // 所有寫法都進 timeline，各自 unbounded——**保留每一種寫法**（大小寫、標點；
            // 正規化的**判定**只住配對鍵 `matchingKey`），但每一筆存 `NameIdentity.canonical`
            // 形（#554 D8：空白不是名字的一部分，`Venue.validate()` 對非 canonical 形是 error）。
            // 「Psychometrika」「PSYCHOMETRIKA」（WoS 大寫形）是同一刊的兩個寫法，
            // 各自留著，否則下次遇到那個寫法又重新分割一次（`OrgBootstrap` 的同一教訓）。
            let timeline = Timeline(c.names.map { TemporalValue(value: $0) })
            return Venue(key: c.key, type: c.type, names: timeline,
                         authorized: [c.names[0]])
        }
    }
}
