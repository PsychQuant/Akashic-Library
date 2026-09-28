import Foundation

/// 一筆 entry 與它的 Zotero 來源之間的連結狀態（#609）——封閉三值。
///
/// #605 讓 orphan 逐來源標記之後，「這筆是不是 orphan」不再是 `provenance?.orphanedAt != nil` 一句話：
/// 附加來源被刪時只標那個來源，而沒有主來源、附加來源全部被刪的 entry 用那句話判是「不是 orphan」——
/// 它在 doctor、index、App 的裁決台全都看不見（#609 R2 補充）。這裡是**唯一**的判準，`StoreHealth`、
/// `LibraryIndex` 的 orphan 欄與 App 的裁決台都讀它；三處各寫一份會分岔（`no-compat-fallback` §「同一件事只能有一份描述」）。
public enum ZoteroLinkState: Equatable {
    /// 沒有已刪除的來源——含完全沒有 Zotero 來源的 entry。
    case intact
    /// 整筆 orphan：主來源已在 Zotero 端刪除；或沒有主來源、附加來源（至少一個）全部已刪除。
    /// 裁決台的「移到垃圾桶」「與 Zotero 脫鉤」作用在這一類。
    case orphaned
    /// 主連結仍在（主來源活著，或沒有主來源而仍有活著的附加來源），但至少一個附加來源已刪除。
    /// 裁決台的「拿掉已刪除的附加來源」作用在這一類。
    case additionalSourceOrphaned
}

public extension Entry {
    var zoteroLinkState: ZoteroLinkState {
        let orphanedAdditional = additionalProvenance.contains { $0.orphanedAt != nil }
        if let primary = provenance {
            if primary.orphanedAt != nil { return .orphaned }
            return orphanedAdditional ? .additionalSourceOrphaned : .intact
        }
        guard orphanedAdditional else { return .intact }
        return additionalProvenance.allSatisfy { $0.orphanedAt != nil } ? .orphaned : .additionalSourceOrphaned
    }
}
