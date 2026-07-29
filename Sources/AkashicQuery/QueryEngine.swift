import Foundation
import AkashicSQLite

public struct QueryFilter: Equatable {
    /// person key 完全命中，或 literal 的 case-insensitive 子字串。
    public var author: String?
    public var yearFrom: Int?
    public var yearTo: Int?
    /// 期刊名 case-insensitive 完全命中。
    public var journal: String?
    public var tag: String?
    public var type: String?
    /// library key 完全命中（#13 membership views）；nil＝全集
    public var library: String?

    public init() {}
}

public struct EntrySummary: Equatable {
    public var uuid: String
    public var citekey: String
    public var type: String
    public var title: String
    public var year: Int?
    public var journal: String?
    public var authors: [String]

    public init(uuid: String, citekey: String, type: String, title: String,
                year: Int? = nil, journal: String? = nil, authors: [String] = []) {
        self.uuid = uuid
        self.citekey = citekey
        self.type = type
        self.title = title
        self.year = year
        self.journal = journal
        self.authors = authors
    }
}

public enum QueryError: Error, LocalizedError {
    case unknownCitekey(String)

    public var errorDescription: String? {
        switch self {
        case .unknownCitekey(let key): return "index 中找不到 citekey：\(key)"
        }
    }
}

/// index 之上的結構化查詢。同作者/同期刊由 metadata 推導；
/// cites/related 讀 relations 表（entry 的 akashic.relations）。
public struct QueryEngine {
    let db: SQLiteDB

    public init(indexPath: URL) throws {
        db = try SQLiteDB(path: indexPath.path, readOnly: true)
    }

    // MARK: - 欄位篩選

    public func find(_ filter: QueryFilter) throws -> [EntrySummary] {
        var conditions: [String] = []
        var bind: [Any?] = []
        if let author = filter.author {
            conditions.append("""
                uuid IN (SELECT entry_uuid FROM authors
                         WHERE person_key = ?
                            OR lower(literal) LIKE '%' || lower(?) || '%' ESCAPE '\\')
                """)
            bind.append(author)
            bind.append(Self.escapeLike(author))
        }
        if let from = filter.yearFrom {
            conditions.append("year >= ?")
            bind.append(from)
        }
        if let to = filter.yearTo {
            conditions.append("year <= ?")
            bind.append(to)
        }
        if let journal = filter.journal {
            conditions.append("lower(journal) = lower(?)")
            bind.append(journal)
        }
        if let tag = filter.tag {
            conditions.append("uuid IN (SELECT entry_uuid FROM tags WHERE tag = ?)")
            bind.append(tag)
        }
        if let library = filter.library {
            conditions.append("uuid IN (SELECT entry_uuid FROM entry_libraries WHERE library_key = ?)")
            bind.append(library)
        }
        if let type = filter.type {
            conditions.append("type = ?")
            bind.append(type)
        }
        let whereClause = conditions.isEmpty ? "" : "WHERE " + conditions.joined(separator: " AND ")
        return try summaries("SELECT * FROM entries \(whereClause) ORDER BY citekey", bind: bind)
    }

    // MARK: - 關係查詢（推導）

    public func sameJournal(as citekey: String) throws -> [EntrySummary] {
        let entry = try requireEntry(citekey)
        guard let journal = entry["journal"] as? String else { return [] }
        return try summaries(
            "SELECT * FROM entries WHERE lower(journal) = lower(?) AND citekey != ? ORDER BY citekey",
            bind: [journal, citekey])
    }

    /// #14 人物檢索：某 person 的著作（可選 library 過濾疊加）。
    public func personPublications(key: String, library: String?) throws -> [EntrySummary] {
        var sql = """
            SELECT DISTINCT e.* FROM entries e
            JOIN authors a ON a.entry_uuid = e.uuid
            WHERE a.person_key = ?
            """
        var bind: [Any?] = [key]
        if let library {
            sql += " AND e.uuid IN (SELECT entry_uuid FROM entry_libraries WHERE library_key = ?)"
            bind.append(library)
        }
        sql += " ORDER BY e.citekey"
        return try summaries(sql, bind: bind)
    }

    public struct CoAuthor: Equatable {
        public var personKey: String?
        public var name: String
        public var count: Int
    }

    /// #14：合著者統計——與該 person 同 entry 掛名的其他作者（key 或 literal）＋合作次數。
    public func coAuthors(of key: String) throws -> [CoAuthor] {
        let rows = try db.query("""
            SELECT a.person_key AS pk, a.literal AS lit, COUNT(DISTINCT a.entry_uuid) AS n
            FROM authors a
            WHERE a.entry_uuid IN (SELECT entry_uuid FROM authors WHERE person_key = ?)
              AND (a.person_key IS NULL OR a.person_key != ?)
            GROUP BY a.person_key, a.literal
            ORDER BY n DESC, COALESCE(a.person_key, a.literal)
            """, bind: [key, key])
        return rows.map { row in
            let pk = row["pk"] as? String
            let lit = row["lit"] as? String
            return CoAuthor(personKey: pk, name: pk ?? lit ?? "?",
                            count: row["n"] as? Int ?? 0)
        }
    }

    public func sameAuthor(as citekey: String) throws -> [EntrySummary] {
        let entry = try requireEntry(citekey)
        let uuid = entry["uuid"] as? String ?? ""
        return try summaries("""
            SELECT DISTINCT e.* FROM entries e
            JOIN authors a ON a.entry_uuid = e.uuid
            WHERE e.uuid != ? AND (
                (a.person_key IS NOT NULL AND a.person_key IN
                    (SELECT person_key FROM authors WHERE entry_uuid = ? AND person_key IS NOT NULL))
                OR
                (a.literal IS NOT NULL AND lower(a.literal) IN
                    (SELECT lower(literal) FROM authors WHERE entry_uuid = ? AND literal IS NOT NULL))
            )
            ORDER BY e.citekey
            """, bind: [uuid, uuid, uuid])
    }

    // MARK: - 關係查詢（儲存的 relations）

    public func cites(of citekey: String) throws -> [EntrySummary] {
        let entry = try requireEntry(citekey)
        let uuid = entry["uuid"] as? String ?? ""
        return try summaries("""
            SELECT DISTINCT e.* FROM entries e
            JOIN relations r ON (r.target = e.citekey OR r.target = e.uuid)
            WHERE r.from_uuid = ? AND r.kind = 'cites'
            ORDER BY e.citekey
            """, bind: [uuid])
    }

    public func citedBy(_ citekey: String) throws -> [EntrySummary] {
        let entry = try requireEntry(citekey)
        let uuid = entry["uuid"] as? String ?? ""
        return try summaries("""
            SELECT DISTINCT e.* FROM entries e
            JOIN relations r ON r.from_uuid = e.uuid
            WHERE r.kind = 'cites' AND (r.target = ? OR r.target = ?)
            ORDER BY e.citekey
            """, bind: [citekey, uuid])
    }

    public func related(to citekey: String) throws -> [EntrySummary] {
        let entry = try requireEntry(citekey)
        let uuid = entry["uuid"] as? String ?? ""
        return try summaries("""
            SELECT DISTINCT e.* FROM entries e
            WHERE e.uuid != ? AND (
                e.uuid IN (SELECT from_uuid FROM relations
                           WHERE kind = 'related' AND (target = ? OR target = ?))
                OR EXISTS (SELECT 1 FROM relations r WHERE r.from_uuid = ? AND r.kind = 'related'
                           AND (r.target = e.citekey OR r.target = e.uuid))
            )
            ORDER BY e.citekey
            """, bind: [uuid, citekey, uuid, uuid])
    }

    // MARK: - Internals

    /// LIKE 萬用字元 escape：使用者輸入的 % _ \ 一律當字面字元。
    static func escapeLike(_ s: String) -> String {
        s.replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_")
    }

    func requireEntry(_ citekey: String) throws -> [String: Any] {
        guard let row = try db.query("SELECT * FROM entries WHERE citekey = ?",
                                     bind: [citekey]).first else {
            throw QueryError.unknownCitekey(citekey)
        }
        return row
    }

    func summaries(_ sql: String, bind: [Any?]) throws -> [EntrySummary] {
        try db.query(sql, bind: bind).map { row in
            let uuid = row["uuid"] as? String ?? ""
            let authorRows = (try? db.query(
                "SELECT person_key, literal FROM authors WHERE entry_uuid = ? ORDER BY position",
                bind: [uuid])) ?? []
            let authors = authorRows.compactMap { r -> String? in
                (r["person_key"] as? String) ?? (r["literal"] as? String)
            }
            return EntrySummary(
                uuid: uuid,
                citekey: row["citekey"] as? String ?? "",
                type: row["type"] as? String ?? "",
                title: row["title"] as? String ?? "",
                year: row["year"] as? Int,
                journal: row["journal"] as? String,
                authors: authors)
        }
    }
}
