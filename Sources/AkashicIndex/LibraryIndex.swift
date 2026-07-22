import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicSQLite

public struct IndexStats: Equatable {
    public var entries: Int
    public var people: Int
    public var relations: Int

    public init(entries: Int, people: Int, relations: Int) {
        self.entries = entries
        self.people = people
        self.relations = relations
    }
}

/// `.akashic/index.sqlite` 重建器。index 是可全刪重建的衍生物——
/// canonical 永遠是 entries/ 與 people/ 的 YAML。
public struct LibraryIndex {
    let store: LibraryStore

    public init(store: LibraryStore) {
        self.store = store
    }

    @discardableResult
    public func rebuild() throws -> IndexStats {
        let load = try store.load()

        // 全刪重建：舊 index 直接移除，避免 schema 演化殘留
        try? FileManager.default.removeItem(at: store.indexURL)
        let db = try SQLiteDB(path: store.indexURL.path, readOnly: false)

        for sql in [
            """
            CREATE TABLE entries(
                uuid TEXT PRIMARY KEY, citekey TEXT UNIQUE, type TEXT, title TEXT,
                year INT, journal TEXT, status TEXT, orphaned INT)
            """,
            "CREATE TABLE authors(entry_uuid TEXT, position INT, person_key TEXT, literal TEXT)",
            "CREATE TABLE tags(entry_uuid TEXT, tag TEXT)",
            "CREATE TABLE relations(from_uuid TEXT, kind TEXT, target TEXT)",
            "CREATE TABLE people(key TEXT PRIMARY KEY, names TEXT)",
            "CREATE INDEX idx_authors_entry ON authors(entry_uuid)",
            "CREATE INDEX idx_authors_key ON authors(person_key)",
            "CREATE INDEX idx_tags_entry ON tags(entry_uuid)",
            "CREATE INDEX idx_relations_from ON relations(from_uuid)",
        ] {
            try db.execute(sql)
        }

        var relationCount = 0
        try db.execute("BEGIN")
        for entry in load.entries {
            try db.execute(
                "INSERT INTO entries VALUES (?,?,?,?,?,?,?,?)",
                bind: [
                    entry.id.uuidString, entry.citekey, entry.type, entry.title,
                    entry.date.flatMap(Self.extractYear),
                    entry.fields["journaltitle"],
                    entry.akashic.status,
                    entry.provenance?.orphanedAt == nil ? 0 : 1,
                ])
            for (i, author) in entry.authors.enumerated() {
                switch author {
                case .key(let k):
                    try db.execute("INSERT INTO authors VALUES (?,?,?,NULL)",
                                   bind: [entry.id.uuidString, i, k])
                case .literal(let s):
                    try db.execute("INSERT INTO authors VALUES (?,?,NULL,?)",
                                   bind: [entry.id.uuidString, i, s])
                }
            }
            for tag in entry.akashic.tags {
                try db.execute("INSERT INTO tags VALUES (?,?)", bind: [entry.id.uuidString, tag])
            }
            for cite in entry.akashic.relations.cites {
                try db.execute("INSERT INTO relations VALUES (?,'cites',?)",
                               bind: [entry.id.uuidString, cite])
                relationCount += 1
            }
            for rel in entry.akashic.relations.related {
                try db.execute("INSERT INTO relations VALUES (?,'related',?)",
                               bind: [entry.id.uuidString, rel])
                relationCount += 1
            }
        }
        for person in load.people {
            try db.execute("INSERT INTO people VALUES (?,?)",
                           bind: [person.key, person.names.joined(separator: "\n")])
        }
        try db.execute("COMMIT")

        return IndexStats(entries: load.entries.count, people: load.people.count,
                          relations: relationCount)
    }

    static func extractYear(_ date: String) -> Int? {
        guard let range = date.range(of: "[0-9]{4}", options: .regularExpression) else { return nil }
        return Int(date[range])
    }
}
