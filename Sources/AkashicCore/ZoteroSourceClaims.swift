import Foundation

/// 一個 Zotero 來源 `(library_id, zotero_key)` 被哪幾筆 entry 宣稱（#610）。
///
/// 匯入端要靠它把 Zotero 條目對回**唯一**一筆 entry；跨記錄檢查（doctor／validate／App）要靠它說出
/// 「同一個來源被多筆宣稱」。兩處用同一份定義——兩份會分岔（`no-compat-fallback` §「同一件事只能有一份描述」）。
///
/// **算的是什麼**：主來源與附加來源都算；同一筆 entry 的主來源與附加來源恰好相同只算一次（那不是多筆宣稱）；
/// 沒記 `library_id` 的來源**不算**——它的身分不完整（#3），歸屬由匯入端的 legacy 規則處理（`ZoteroImporter`）。
public enum ZoteroSourceClaims {
    /// 來源的鍵：`<library_id>:<zotero_key>`。
    public static func key(libraryID: Int, zoteroKey: String) -> String { "\(libraryID):\(zoteroKey)" }

    /// 來源鍵 → 宣稱它的 entry id（依 `entries` 的順序、以 entry 去重）。
    public static func claimants(_ entries: [Entry]) -> [String: [UUID]] {
        var out: [String: [UUID]] = [:]
        for entry in entries {
            var seen = Set<String>()
            for p in [entry.provenance].compactMap({ $0 }) + entry.additionalProvenance {
                guard let lid = p.libraryID else { continue }
                let k = key(libraryID: lid, zoteroKey: p.zoteroKey)
                if seen.insert(k).inserted { out[k, default: []].append(entry.id) }
            }
        }
        return out
    }
}
