import Foundation
import AkashicCore
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

        var authorsByItem: [Int: [(Int, String, String)]] = [:]   // (orderIndex, display, family)
        for row in try db.query("""
            SELECT ic.itemID AS itemID, ic.orderIndex AS orderIndex,
                   c.firstName AS firstName, c.lastName AS lastName, c.fieldMode AS fieldMode
            FROM itemCreators ic
            JOIN creators c ON ic.creatorID = c.creatorID
            JOIN creatorTypes ct ON ic.creatorTypeID = ct.creatorTypeID
            WHERE ct.creatorType = 'author'
            """) {
            guard let itemID = row["itemID"] as? Int else { continue }
            let order = row["orderIndex"] as? Int ?? 0
            let first = (row["firstName"] as? String) ?? ""
            let last = (row["lastName"] as? String) ?? ""
            let fieldMode = row["fieldMode"] as? Int ?? 0
            let display: String
            let family: String
            if fieldMode == 1 {
                // 單欄姓名（機構、或不分姓名的個人）：Zotero 把整個名字存在 lastName。
                // #6：以 `{...}` 標記保留「這不是 Given Family」這個事實——不標記的話
                // export 會切成 "Organization, World Health"。citekey 仍用最後一個 token
                // 當姓（既有行為，不動；改它會讓既有 citekey 全部漂移）。
                display = CorporateName.mark(last)
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
