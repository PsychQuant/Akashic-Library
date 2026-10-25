import Foundation

/// 一個團體作者的**成員名單**（#742，design D6）——住在 work 頂層的 `group-members:`。
///
/// 使用者 2026-10-21 裁決 2：團體成員要記錄（「不然團體可能以後會換成員」），作者列照 byline、成員不留在
/// `authors`。觸發實例 `claw2018framework`：byline 是 6 位個人＋SING Consortium，13 位成員印在 PDF 第 7 頁。
///
/// ## 形狀
///
/// - `group`：逐字等於作者列中一個團體位的值，**含 corporate 大括號**（`CorporateName.mark` 的形）。寫入時
///   由替換腿確認對得上；之後該位被升格為 organization，名單照留——它記的是作品裡寫的團體名。
/// - `rests-on`：一個合法、非空內容的 digest（那份全文）；`page`：PDF 實體頁序，從 1 起算。依據直接寫在
///   名單上，不另寫 `Entry.references` 記錄：名單只由替換腿寫，理由已在替換記錄裡。
/// - `members`：至少一位，次序照原文，不得有逐字重複；每位非空、前後無空白。
///
/// ## 為什麼成員是字串
///
/// 目前沒有任何面能把成員升格為 person key；做成二態 ref 就是新的關係邊（`entity-backlink-completeness`
/// 的封閉表要加一列），`rename-person` 與 person 合併都得遷移它，而它在這一輪不會有任何 key。
/// 升格為 ref 是一次顯式裁決，另開 change。
///
/// 規則只有一份（`problem`）：`init?`、YAML decode 與替換腿都經它，不會有「寫得出、讀不回」的形狀。
public struct GroupMemberList: Equatable, Sendable {
    public let group: String
    public let restsOn: String
    public let page: Int
    public let members: [String]

    public init?(group: String, restsOn: String, page: Int, members: [String]) {
        guard Self.problem(group: group, restsOn: restsOn, page: page, members: members) == nil else { return nil }
        self.group = group
        self.restsOn = restsOn
        self.page = page
        self.members = members
    }

    /// 回 nil＝合法；否則回一句說得出哪裡不對的話（不含未信任內容以外的值——呼叫端負責消毒後再拼）。
    public static func problem(group: String, restsOn: String, page: Int, members: [String]) -> String? {
        guard CorporateName.isMarked(group), group == group.trimmingCharacters(in: .whitespacesAndNewlines),
              !CorporateName.unmark(group).trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            return "group 必須是帶 corporate 大括號、前後無空白的團體名（與作者列中那一個團體位逐字相同）"
        }
        guard ProvenanceReference.isValidDigest(restsOn) else {
            return restsOn == ProvenanceReference.emptyContentDigest
                ? ProvenanceReference.emptyContentDigestReason
                : "rests-on 必須是 sha256: 加 64 個小寫 hex 的 digest"
        }
        guard page >= 1 else { return "page 是 PDF 的實體頁序，從 1 起算" }
        guard !members.isEmpty else { return "members 至少要有一位" }
        // 去重比位元組：`Set<String>` 比的是 Unicode 正規等價，NFC 與 NFD 的「José」會被當成同一位，而 store 存的是逐字的值（#742 verify）
        var seen = Set<[UInt8]>()
        for m in members {
            guard !m.isEmpty, m == m.trimmingCharacters(in: .whitespacesAndNewlines) else {
                return "成員名不得為空、不得有前後空白"
            }
            guard !AuthorListReplacementRecordValue.containsControlCharacter(m) else {
                return "成員名不得含控制字元（換行、tab 等）"
            }
            guard seen.insert(Array(m.utf8)).inserted else { return "成員名逐字重複" }
        }
        return nil
    }
}

extension Entry {
    /// 一筆 work 的成員名單之間的約束：同一個 `group` 至多一組（各組自己的形狀由 `GroupMemberList` 保證）。比位元組，理由同成員去重。
    public static func groupMembersProblem(_ lists: [GroupMemberList]) -> String? {
        var seen = Set<[UInt8]>()
        for l in lists where !seen.insert(Array(l.group.utf8)).inserted {
            return "同一個團體的成員名單出現兩組"
        }
        return nil
    }
}
