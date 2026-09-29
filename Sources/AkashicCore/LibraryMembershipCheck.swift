import Foundation

/// 一筆 work 不符 library 成員規則的原因（#642）。**封閉列舉**：每一種都是一個可重跑的事實，
/// 不是判斷——同一份 store 對同一筆 work 必然得到同一個答案（`two-kinds-of-edits`：add 是程式編輯）。
public enum LibraryMembershipViolation: Equatable {
    /// 這個 library 沒有標成員性質——查不到依據。**fail-closed**（#642 R1 verify）：未標性質不是「符合」，
    /// 呼叫端不必另行預查也不會誤放行；日後新增的寫入面只問這個判定就夠。
    case libraryUnmarked
    /// 沒有任何 venue 邊——看不出它屬於哪一本刊。
    case noVenue
    /// 只有未歸戶的 venue 字面值——歸戶之前查不出它是不是這本刊（`literal-first-then-key`：不猜）。
    case venueUnresolved
    /// 有歸戶的 venue 邊，但沒有一條指向規則的 venue。
    case otherVenue([String])
    /// type 不在規則的集合內。
    case typeNotAllowed(WorkType)
    /// 在規則的排除清單裡。
    case excluded
    /// 規則型：規則的 venue key 有不只一筆記錄——分不出規則指的是哪一筆（#670）。與建規則時的拒絕同一個理由：
    /// 同一個不明確的依據，在設定規則時被拒絕、在使用規則時就不能放行（#642 R1 verify）。
    case ruleVenueAmbiguous(String)
    /// 文件型：文件不在庫——查不到它引了什麼。
    case documentMissing(String)
    /// 文件型：文件的 citekey 有不只一筆——分不出是哪一份的參考文獻。
    case documentAmbiguous(String)
    /// 文件型：文件沒有引用它。
    case notCitedByDocument(String)

    /// 給人讀的原因。store 字串逐項消毒；呼叫端不再包一次（`displaySafe` 不冪等）。
    public var message: String {
        switch self {
        case .libraryUnmarked:
            return Library.unmarkedMessage
        case .noVenue:
            return "沒有 venue 邊——看不出它屬於哪一本刊"
        case .venueUnresolved:
            return "venue 只有未歸戶的字面值——先 resolve-venues 歸戶才查得出是不是這本刊"
        case .otherVenue(let keys):
            return "venue 是「" + keys.prefix(5).map { displaySafeInvisible($0, max: 200) }.joined(separator: "、")
                 + "」" + (keys.count > 5 ? "等 \(keys.count) 個" : "") + "，不是規則的 venue"   // display-safe-exempt: Int
        case .typeNotAllowed(let t):
            return "type 是 \(t.rawValue)，不在規則的 type 集合內"   // display-safe-exempt: t.rawValue：WorkType.rawValue 是封閉值域
        case .excluded:
            return "在規則的排除清單裡（依裁決不收）"
        case .ruleVenueAmbiguous(let v):
            return "規則的 venue「\(displaySafeInvisible(v, max: 200))」有不只一筆記錄——分不出規則指的是哪一筆，依據不明確；"
                 + "先修好重複的 venue key（akashic validate 會指出），再 add"
        case .documentMissing(let ck):
            return "文件「\(displaySafeInvisible(ck, max: 200))」不在庫——查不到它引了什麼"
        case .documentAmbiguous(let ck):
            return "文件「\(displaySafeInvisible(ck, max: 200))」的 citekey 有不只一筆——分不出是哪一份的參考文獻"
        case .notCitedByDocument(let ck):
            return "文件「\(displaySafeInvisible(ck, max: 200))」沒有引用它"
        }
    }
}

/// 一個 library 的成員規則對一份 store 的判定（#642）。**單一實作路徑**：CLI／MCP 的 add、`library check`、
/// `library list` 的不符計數、`validate`／`doctor` 的跨記錄 warning、App 的加入動作都問這個型別——規則只有一份
/// 程式碼，各面只渲染（`entity-backlink-completeness` 執行細節 2）。
public struct LibraryMembershipCheck {
    public let library: Library

    /// 文件型的文件在這份 store 裡的狀態——建構時算一次，逐筆判定不再掃全庫。
    private enum DocumentState {
        case cites(Set<String>)
        case missing
        case ambiguous
    }
    private let document: DocumentState?
    private let entries: [Entry]
    /// 規則型的排除清單，建構時做成 Set——逐成員比對是 O(1)，不是對每個成員線性掃整份清單（#642 R1 verify）。
    private let excludedSet: Set<String>
    /// 規則型：規則的 venue key 在這份 store 裡有不只一筆記錄（`Venue` 的 `unlocatableVenueKeys`）。
    private let ruleVenueIsAmbiguous: Bool

    /// `venues` 是這份 store 的**全部** venue 記錄，不是規則的那一筆——「規則指的是哪一筆」只有看得到重複才答得出來。
    /// **必填、沒有預設值**：預設空陣列會讓忘了傳的呼叫端安靜地放行重複的 venue key（#642 R1 verify）。
    public init(library: Library, entries: [Entry], venues: [Venue]) {
        self.library = library
        self.entries = entries
        if case .document(let ck)? = library.membership {
            let hits = entries.filter { $0.citekey == ck }
            switch hits.count {
            case 0: document = .missing
            case 1: document = .cites(Set(hits[0].akashic.relations.cites))
            default: document = .ambiguous
            }
        } else {
            document = nil
        }
        if case .rule(let rule)? = library.membership {
            excludedSet = Set(rule.excluded)
            ruleVenueIsAmbiguous = venues.unlocatableVenueKeys.contains(rule.venue)
        } else {
            excludedSet = []
            ruleVenueIsAmbiguous = false
        }
    }

    /// **規則的依據本身有問題**（與逐筆比對分開）：規則的 venue key 有不只一筆記錄、文件型的文件不在庫或有不只一筆。
    /// 有依據問題時每一筆 work 都會以同一個原因不符——所以 `library check` 與 validate 先說這一句，而不是逐筆重複；
    /// 零成員的 library 也照樣看得到（沒有成員可列，不代表依據沒問題）。`nil` ＝依據可用（含主題型、未標性質——
    /// 後者由 `violation(of:)` 的 `.libraryUnmarked` 說話）。
    public var basisProblem: LibraryMembershipViolation? {
        switch library.membership {
        case nil, .topic?:
            return nil
        case .rule(let rule)?:
            return ruleVenueIsAmbiguous ? .ruleVenueAmbiguous(rule.venue) : nil
        case .document(let ck)?:
            switch document {
            case .cites?: return nil
            case .ambiguous?: return .documentAmbiguous(ck)
            case .missing?, nil: return .documentMissing(ck)
            }
        }
    }

    /// `nil` ＝符合（主題型永遠符合）。**未標性質回 `.libraryUnmarked`**——那不是「符合」而是「查不到依據」，
    /// 這個判定 fail-closed，呼叫端不必另行預查（#642 R1 verify：先前回 `nil`，靠每個呼叫端記得先看 `membership == nil`）。
    /// 規則依據不明確（`basisProblem`）時每一筆都回那個原因。
    public func violation(of entry: Entry) -> LibraryMembershipViolation? {
        guard let membership = library.membership else { return .libraryUnmarked }
        switch membership {
        case .topic:
            return nil
        case .rule(let rule):
            if let problem = basisProblem { return problem }
            if excludedSet.contains(entry.citekey) { return .excluded }
            if !entry.venues.contains(.key(rule.venue)) {
                let keys = entry.venues.compactMap { ref -> String? in
                    if case .key(let k) = ref { return k }
                    return nil
                }
                if !keys.isEmpty { return .otherVenue(keys) }
                return entry.venues.isEmpty ? .noVenue : .venueUnresolved
            }
            if !rule.types.isEmpty, !rule.types.contains(entry.type) { return .typeNotAllowed(entry.type) }
            return nil
        case .document(let ck):
            if let problem = basisProblem { return problem }
            guard case .cites(let cites)? = document else { return .documentMissing(ck) }
            return cites.contains(entry.citekey) ? nil : .notCitedByDocument(ck)
        }
    }

    /// 現有成員（`akashic.libraries` 含這個 key 的 work）裡不符規則的，依 citekey 排序。未標性質回空——
    /// 沒有依據就列不出「不符」，那一格由 `Library.validate()` 的未標 warning 說話。
    public func nonconformingMembers() -> [(citekey: String, violation: LibraryMembershipViolation)] {
        guard library.membership != nil else { return [] }
        return entries
            .filter { $0.akashic.libraries.contains(library.key) }
            .compactMap { e in violation(of: e).map { (citekey: e.citekey, violation: $0) } }
            .sorted { $0.citekey < $1.citekey }
    }

    /// 這個 library 的成員依據，給人讀（「要求／依據／實際寫入」的中間那一格）。store 字串逐項消毒。
    public var basis: String { Self.basis(of: library.membership) }

    public static func basis(of membership: LibraryMembership?) -> String {
        switch membership {
        case nil:
            return "未標性質——查不到成員的依據"
        case .topic?:
            return "主題型：成員由使用者挑選，照指定的寫"
        case .rule(let r)?:
            var parts = ["規則型：venue「\(displaySafeInvisible(r.venue, max: 200))」"]
            if !r.types.isEmpty { parts.append("type ∈ {" + r.types.map(\.rawValue).joined(separator: ", ") + "}") }
            if !r.excluded.isEmpty { parts.append("排除 \(r.excluded.count) 筆") }   // display-safe-exempt: Int
            if let s = r.source {
                parts.append("來歷 \(displaySafeInvisible(s, max: 200))（只記來歷，不作檢查依據）")
            }
            return parts.joined(separator: "；")
        case .document(let ck)?:
            return "文件型：文件「\(displaySafeInvisible(ck, max: 200))」的 cites"
        }
    }
}

extension LibraryMembershipCheck {
    /// 一條成員規則的**完整**依據，逐行（`library check` 與 `set-kind` 的「先前」段用）：`basis` 只說「排除 N 筆」，
    /// 而 `set-kind` 是整值替換——要改一條帶排除清單的規則，操作者得看得到每一個 citekey，否則只能去讀 YAML
    /// （#642 R1 verify）。CLI 不截（輸出進人的終端機）；每個 store 字串逐項消毒。
    public static func details(of membership: LibraryMembership?) -> [String] {
        switch membership {
        case nil:
            return ["未標性質"]
        case .topic?:
            return ["主題型（不檢查成員）"]
        case .rule(let r)?:
            var lines = ["規則型", "  venue：\(displaySafeInvisible(r.venue, max: 200))"]
            lines.append("  type：" + (r.types.isEmpty ? "不限" : r.types.map(\.rawValue).joined(separator: "、")))
            if r.excluded.isEmpty {
                lines.append("  排除：無")
            } else {
                lines.append("  排除（\(r.excluded.count) 筆，依裁決不收）：")   // display-safe-exempt: Int
                for ck in r.excluded { lines.append("    · " + displaySafeInvisible(ck, max: 200)) }
            }
            if let s = r.source { lines.append("  來歷：\(displaySafeInvisible(s, max: 600))（只記來歷，不作檢查依據）") }
            return lines
        case .document(let ck)?:
            return ["文件型", "  文件：\(displaySafeInvisible(ck, max: 200))（它的 cites 即成員）"]
        }
    }
}

extension LibraryMembership {
    /// 規則型與文件型需要的最低 store format（#642）。**只在這裡定義一次**：`StoreVersion.libraryMembershipFormat`（寫入閘）
    /// 引用它，而訊息（未標性質的拒絕與 warning）在 Core 裡也要說出這個數。
    public static let requiredStoreFormat = 21
}

extension Library {
    /// 未標性質的 warning——`Library.validate()` 與寫入面的拒絕訊息共用這一句（#642）。
    ///
    /// **要說三件事**（#642 R1 verify）：(1) 標性質是使用者的決定，不是呼叫端替他選；(2) rule／document 需要 store format ≥ 21——
    /// 在那之前只標得上 topic；(3) **不要為了讓 add 通過而改標 topic**：topic 不檢查成員，等於回到沒有規則的狀態，而那正是
    /// 這個檢查存在要防的事。
    public static let unmarkedMessage =
        "library 沒有標成員性質（topic／rule／document）——查不到成員的依據，add 會被拒絕；"
        + "性質由使用者決定，用 akashic library set-kind（MCP：akashic_libraries action set-kind）標。"
        + "rule／document 需要 store format ≥ \(LibraryMembership.requiredStoreFormat)；"   // display-safe-exempt: Int 常量
        + "不要改標 topic 來解鎖——topic 不檢查成員（#642）"

    /// 人讀的性質名；未標性質說「未標性質」。
    public var membershipLabel: String { membership?.kindLabel ?? "未標性質" }
}
