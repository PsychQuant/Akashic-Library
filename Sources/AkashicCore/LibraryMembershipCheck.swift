import Foundation

/// 一筆 work 不符 library 成員規則的原因（#642）。**封閉列舉**：每一種都是一個可重跑的事實，
/// 不是判斷——同一份 store 對同一筆 work 必然得到同一個答案（`two-kinds-of-edits`：add 是程式編輯）。
public enum LibraryMembershipViolation: Equatable {
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
    /// 文件型：文件不在庫——查不到它引了什麼。
    case documentMissing(String)
    /// 文件型：文件的 citekey 有不只一筆——分不出是哪一份的參考文獻。
    case documentAmbiguous(String)
    /// 文件型：文件沒有引用它。
    case notCitedByDocument(String)

    /// 給人讀的原因。store 字串逐項消毒；呼叫端不再包一次（`displaySafe` 不冪等）。
    public var message: String {
        switch self {
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

    public init(library: Library, entries: [Entry]) {
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
    }

    /// `nil` ＝符合（主題型永遠符合）。**未標性質也回 `nil`**——那不是「符合」而是「查不到依據」，
    /// 由呼叫端先看 `library.membership == nil` 並整個拒絕；這個函式只回答有依據時的比對結果。
    public func violation(of entry: Entry) -> LibraryMembershipViolation? {
        switch library.membership {
        case nil, .topic?:
            return nil
        case .rule(let rule)?:
            if rule.excluded.contains(entry.citekey) { return .excluded }
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
        case .document(let ck)?:
            switch document {
            case .cites(let cites)?:
                return cites.contains(entry.citekey) ? nil : .notCitedByDocument(ck)
            case .ambiguous?:
                return .documentAmbiguous(ck)
            case .missing?, nil:
                return .documentMissing(ck)
            }
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

extension Library {
    /// 未標性質的 warning——`Library.validate()` 與寫入面的拒絕訊息共用這一句（#642）。
    public static let unmarkedMessage =
        "library 沒有標成員性質（topic／rule／document）——查不到成員的依據，add 會被拒絕；"
        + "用 akashic library set-kind（MCP：akashic_libraries action set-kind）標（#642）"

    /// 人讀的性質名；未標性質說「未標性質」。
    public var membershipLabel: String { membership?.kindLabel ?? "未標性質" }
}
