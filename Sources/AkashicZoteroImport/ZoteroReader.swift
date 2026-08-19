import Foundation
import AkashicSQLite

/// Zotero 資料庫讀出的原始 item（尚未 map 成 Entry）。
public struct ZoteroItem: Equatable {
    public var key: String
    public var version: Int
    public var libraryID: Int
    public var typeName: String
    public var fields: [String: String]
    /// (顯示名, 姓)；fieldMode 1 時姓＝完整顯示名。
    public var authors: [(display: String, family: String)]
    public var tags: [String]
    /// 已正規化為 storage/<KEY>/<file> 的 reference。
    public var attachmentPaths: [String]

    public static func == (lhs: ZoteroItem, rhs: ZoteroItem) -> Bool {
        lhs.key == rhs.key && lhs.version == rhs.version && lhs.libraryID == rhs.libraryID
            && lhs.typeName == rhs.typeName
            && lhs.fields == rhs.fields && lhs.tags == rhs.tags
            && lhs.attachmentPaths == rhs.attachmentPaths
            && lhs.authors.map(\.display) == rhs.authors.map(\.display)
    }
}

/// readItems 的結果：items + 被略過的 linked attachments 計數（不靜默）。
public struct ZoteroReadResult {
    public var items: [ZoteroItem]
    public var skippedLinkedAttachments: Int

    public init(items: [ZoteroItem] = [], skippedLinkedAttachments: Int = 0) {
        self.items = items
        self.skippedLinkedAttachments = skippedLinkedAttachments
    }
}

/// 唯讀讀取 zotero.sqlite。鐵律：永不寫入（SQLITE_OPEN_READONLY）。
public enum ZoteroReader {
    /// 排除的 item types（附件/筆記/註記掛在母 item 上處理）。
    static let excludedTypes: Set<String> = ["attachment", "note", "annotation"]

    /// libraryID=nil（預設）拉全部 libraries（personal + groups；實庫驗證 group 文獻是真實使用）；
    /// 指定則只拉該 library。跨 library 身分由 (libraryID, key) 複合鍵處理（#3）。
    public static func readItems(dbPath: String, libraryID: Int? = nil) throws -> ZoteroReadResult {
        let db = try SQLiteDB(path: dbPath, readOnly: true)

        let deleted = Set(try db.query("SELECT itemID FROM deletedItems")
            .compactMap { $0["itemID"] as? Int })

        // itemID → (key, version, typeName, libraryID)；一次撈全表在記憶體組裝（個人庫規模）
        var meta: [Int: (key: String, version: Int, type: String, libraryID: Int)] = [:]
        for row in try db.query("""
            SELECT i.itemID AS itemID, i.key AS key, i.version AS version,
                   i.libraryID AS libraryID, t.typeName AS typeName
            FROM items i JOIN itemTypes t ON i.itemTypeID = t.itemTypeID
            """) {
            guard let itemID = row["itemID"] as? Int, let key = row["key"] as? String,
                  let version = row["version"] as? Int, let type = row["typeName"] as? String else {
                continue
            }
            meta[itemID] = (key, version, type, row["libraryID"] as? Int ?? 1)
        }

        var fieldsByItem: [Int: [String: String]] = [:]
        for row in try db.query("""
            SELECT d.itemID AS itemID, f.fieldName AS fieldName, v.value AS value
            FROM itemData d
            JOIN fields f ON d.fieldID = f.fieldID
            JOIN itemDataValues v ON d.valueID = v.valueID
            """) {
            guard let itemID = row["itemID"] as? Int,
                  let name = row["fieldName"] as? String,
                  let value = row["value"] as? String else { continue }
            fieldsByItem[itemID, default: [:]][name] = value
        }

        // 作者位的 creator type **由 Zotero 自己宣告**，不寫死 `'author'`（#340）。
        //
        // `itemTypeCreatorTypes.primaryField = 1` 是 Zotero schema 對每個 item type 指定
        // 的「主要 creator」。實測本庫：`presentation` → **`presenter`**，其餘 → `author`。
        //
        // **先前寫死 `ct.creatorType = 'author'` 的後果**：所有會議發表在匯入時**掉了
        // 全部發表人**（實測 64 個 `presenter` creator row、21 筆記錄的 `authors` 整塊
        // 消失）。而 APA7 §10.5 把發表人放在作者位——所以那不是「少一個欄位」，
        // 是那筆記錄**無法被引用**（`apa7-is-the-work-floor` 的下限違反）。
        //
        // 這與 `meetingName`／`encyclopediaTitle` 同型：**資料一直在 Zotero，是我們的
        // 對映不接受它**。差別是那兩個走殘餘路徑至少留了值，這個是整塊丟掉。
        //
        // **`editor` 刻意不納入**：Zotero 對 `bookSection` 的 primary 是 `author`，
        // editor 是次要 creator——它在 APA7 走 `EDITOR` 欄位而非作者位（#354 的
        // `authorPositionAlternatives`）。用 primaryField 判定自動得到這個正確結果，
        // 不需要另寫一張排除清單。
        var authorsByItem: [Int: [(Int, String, String)]] = [:]   // (orderIndex, display, family)
        for row in try db.query("""
            SELECT ic.itemID AS itemID, ic.orderIndex AS orderIndex,
                   c.firstName AS firstName, c.lastName AS lastName, c.fieldMode AS fieldMode
            FROM itemCreators ic
            JOIN creators c ON ic.creatorID = c.creatorID
            JOIN items i2 ON i2.itemID = ic.itemID
            JOIN itemTypeCreatorTypes itct
                 ON itct.itemTypeID = i2.itemTypeID
                AND itct.creatorTypeID = ic.creatorTypeID
                AND itct.primaryField = 1
            """) {
            guard let itemID = row["itemID"] as? Int else { continue }
            let order = row["orderIndex"] as? Int ?? 0
            let first = (row["firstName"] as? String) ?? ""
            let last = (row["lastName"] as? String) ?? ""
            let fieldMode = row["fieldMode"] as? Int ?? 0
            let display: String
            let family: String
            if fieldMode == 1 {
                // 單欄姓名：Zotero 把整個名字存在 lastName；citekey 用最後一個 token 當姓。
                //
                // **#6 刻意不在這裡自動標記機構名**：`fieldMode == 1` 同時被用在機構
                // （"World Health Organization"）與「不想被拆的人名」（測試 fixture 的
                // "Chun-Houh Chen" 就是），Zotero 端沒有能分開兩者的訊號。自動標記會把
                // 人名保護成 `{Chun-Houh Chen}`，export 出 `{Chun-Houh Chen}` 而非
                // `Chen, Chun-Houh`——**修一個錯換一個錯**。
                //
                // 沒有儲存結構就無法自動判別（token 數也分不開：2-token 的人名切分正確、
                // 3-token 的機構切分錯誤，4-token 的人名又切分正確）。真正的修法是
                // family / given / corporate 三態各自成欄，屬 #35 的 entity 模型統一。
                // 在此之前，使用者可手動在 store 檔裡把機構名寫成 `{...}`，export 端
                // 會尊重（見 `CorporateName`）。
                display = last
                family = last.split(separator: " ").last.map(String.init) ?? last
            } else {
                display = [first, last].filter { !$0.isEmpty }.joined(separator: " ")
                family = last
            }
            authorsByItem[itemID, default: []].append((order, display, family))
        }

        var tagsByItem: [Int: [String]] = [:]
        for row in try db.query("""
            SELECT it.itemID AS itemID, t.name AS name
            FROM itemTags it JOIN tags t ON it.tagID = t.tagID
            """) {
            guard let itemID = row["itemID"] as? Int, let name = row["name"] as? String else { continue }
            tagsByItem[itemID, default: []].append(name)
        }

        var attachmentsByParent: [Int: [String]] = [:]
        var skippedLinked = 0
        for row in try db.query("""
            SELECT a.parentItemID AS parentItemID, a.path AS path, i.key AS childKey
            FROM itemAttachments a JOIN items i ON a.itemID = i.itemID
            WHERE a.parentItemID IS NOT NULL
              AND a.itemID NOT IN (SELECT itemID FROM deletedItems)
            """) {
            guard let parent = row["parentItemID"] as? Int,
                  let path = row["path"] as? String,
                  let childKey = row["childKey"] as? String else { continue }
            guard path.hasPrefix("storage:") else {
                // linked / URL 附件：Phase 2 仍不入庫，但計數不靜默（#3）
                if meta[parent].map({ libraryID == nil || $0.libraryID == libraryID }) ?? false {
                    skippedLinked += 1
                }
                continue
            }
            let filename = String(path.dropFirst("storage:".count))
            attachmentsByParent[parent, default: []].append("storage/\(childKey)/\(filename)")
        }

        var items: [ZoteroItem] = []
        for (itemID, m) in meta {
            if deleted.contains(itemID) { continue }
            if excludedTypes.contains(m.type) { continue }
            if let wanted = libraryID, m.libraryID != wanted { continue }
            let authors = (authorsByItem[itemID] ?? [])
                .sorted { $0.0 < $1.0 }
                .map { (display: $0.1, family: $0.2) }
            items.append(ZoteroItem(
                key: m.key, version: m.version, libraryID: m.libraryID, typeName: m.type,
                fields: fieldsByItem[itemID] ?? [:],
                authors: authors,
                tags: (tagsByItem[itemID] ?? []).sorted(),
                attachmentPaths: (attachmentsByParent[itemID] ?? []).sorted()))
        }
        return ZoteroReadResult(items: items.sorted { $0.key < $1.key },
                                skippedLinkedAttachments: skippedLinked)
    }
}
