import Foundation

/// 一個 Zotero 來源 `(library_id, zotero_key)` 被哪幾筆 entry 宣稱（#610）。
///
/// 匯入端要靠它把 Zotero 條目對回**唯一**一筆 entry；跨記錄檢查（doctor／validate／App）要靠它說出
/// 「同一個來源被多筆宣稱」。兩處用同一份定義——兩份會分岔（`no-compat-fallback` §「同一件事只能有一份描述」）。
///
/// **算的是什麼**（封閉，只有這三條）：
/// 1. 主來源與附加來源，鍵是 `<library_id>:<zotero_key>`；同一筆 entry 的主來源與附加來源恰好相同只算一次
///    （那不是多筆宣稱）。
/// 2. 沒記 `library_id` 的**主來源**（pre-Phase-2 舊檔，#3）進裸 key 桶，鍵是 `?:<zotero_key>`——兩筆以上舊檔宣稱
///    同一個裸 key 同樣是多筆宣稱（#610 R1 verify：匯入端曾在行內另有一份 legacy 的定義，doctor 看不到）。
/// 3. 沒記 `library_id` 的**附加來源**不算：匯入端以 `(library_id, key)` 比對附加來源，對不回它；合併閘也不讓
///    這種來源收成附加來源（`fieldsLostByMerging`）。
///
/// 舊檔（`?:`）與某個 library 的來源同裸 key **不算**多筆宣稱——歸屬不明不是確定的重複，匯入端照 #607 的規則
/// 不認領，那一格不在這裡。
///
/// **同一筆 entry 只算一次**（以 entry id 去重）：`load()` 在兩份並存（#631）時會把同一個 id 讀到兩次，那不是攣生。
/// 兩筆**不同**記錄共用同一個 id 時只看先讀到的那一筆——那個形狀有它自己的診斷（`unlocatableCitekeys`），不靠這裡。
public enum ZoteroSourceClaims {
    /// 來源的鍵：`<library_id>:<zotero_key>`；沒記 library_id 的是 `?:<zotero_key>`（裸 key 桶）。
    /// 全樹產生來源鍵的**唯一**位置——匯入端的索引、路由與孤兒偵測都走這裡。
    public static func key(libraryID: Int?, zoteroKey: String) -> String {
        "\(libraryID.map(String.init) ?? "?"):\(zoteroKey)"
    }

    /// 來源鍵 → 宣稱它的 entry id（依 `entries` 的順序、以 entry 去重）。
    public static func claimants(_ entries: [Entry]) -> [String: [UUID]] {
        var out: [String: [UUID]] = [:]
        var visited = Set<UUID>()
        for entry in entries where visited.insert(entry.id).inserted {
            var seen = Set<String>()
            func claim(_ k: String) {
                if seen.insert(k).inserted { out[k, default: []].append(entry.id) }
            }
            if let primary = entry.provenance {
                claim(key(libraryID: primary.libraryID, zoteroKey: primary.zoteroKey))
            }
            for extra in entry.additionalProvenance {
                guard let lid = extra.libraryID else { continue }
                claim(key(libraryID: lid, zoteroKey: extra.zoteroKey))
            }
        }
        return out
    }
}
