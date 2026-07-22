import Foundation
import SQLite3

public enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String, sql: String)
    case stepFailed(String, sql: String)
    case bindFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let m): return "SQLite open 失敗：\(m)"
        case .prepareFailed(let m, let sql): return "SQLite prepare 失敗：\(m)（\(sql)）"
        case .stepFailed(let m, let sql): return "SQLite step 失敗：\(m)（\(sql)）"
        case .bindFailed(let m): return "SQLite bind 失敗：\(m)"
        }
    }
}

private let sqliteTransient = unsafeBitCast(-1, to: sqlite3_destructor_type.self)

/// 最小 SQLite wrapper：讀 Zotero（read-only）與寫 .akashic/ index 共用。
public final class SQLiteDB {
    private var handle: OpaquePointer?

    public init(path: String, readOnly: Bool) throws {
        let flags = readOnly
            ? SQLITE_OPEN_READONLY
            : (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE)
        var db: OpaquePointer?
        guard sqlite3_open_v2(path, &db, flags, nil) == SQLITE_OK else {
            let message = db.map { String(cString: sqlite3_errmsg($0)) } ?? "unknown"
            sqlite3_close(db)
            throw SQLiteError.openFailed(message)
        }
        handle = db
        sqlite3_busy_timeout(db, 3000)
    }

    deinit { sqlite3_close(handle) }

    public func execute(_ sql: String, bind: [Any?] = []) throws {
        _ = try run(sql, bind: bind)
    }

    public func query(_ sql: String, bind: [Any?] = []) throws -> [[String: Any]] {
        try run(sql, bind: bind)
    }

    @discardableResult
    private func run(_ sql: String, bind: [Any?]) throws -> [[String: Any]] {
        var stmt: OpaquePointer?
        guard sqlite3_prepare_v2(handle, sql, -1, &stmt, nil) == SQLITE_OK else {
            throw SQLiteError.prepareFailed(String(cString: sqlite3_errmsg(handle)), sql: sql)
        }
        defer { sqlite3_finalize(stmt) }

        for (i, value) in bind.enumerated() {
            let idx = Int32(i + 1)
            let rc: Int32
            switch value {
            case nil:
                rc = sqlite3_bind_null(stmt, idx)
            case let v as Int:
                rc = sqlite3_bind_int64(stmt, idx, Int64(v))
            case let v as Int64:
                rc = sqlite3_bind_int64(stmt, idx, v)
            case let v as Double:
                rc = sqlite3_bind_double(stmt, idx, v)
            case let v as String:
                rc = sqlite3_bind_text(stmt, idx, v, -1, sqliteTransient)
            default:
                throw SQLiteError.bindFailed("不支援的型別：\(String(describing: value))")
            }
            guard rc == SQLITE_OK else {
                throw SQLiteError.bindFailed(String(cString: sqlite3_errmsg(handle)))
            }
        }

        var rows: [[String: Any]] = []
        while true {
            let rc = sqlite3_step(stmt)
            if rc == SQLITE_DONE { break }
            guard rc == SQLITE_ROW else {
                throw SQLiteError.stepFailed(String(cString: sqlite3_errmsg(handle)), sql: sql)
            }
            var row: [String: Any] = [:]
            for col in 0..<sqlite3_column_count(stmt) {
                let name = String(cString: sqlite3_column_name(stmt, col))
                switch sqlite3_column_type(stmt, col) {
                case SQLITE_INTEGER:
                    row[name] = Int(sqlite3_column_int64(stmt, col))
                case SQLITE_FLOAT:
                    row[name] = sqlite3_column_double(stmt, col)
                case SQLITE_TEXT:
                    row[name] = String(cString: sqlite3_column_text(stmt, col))
                default:
                    break   // NULL / BLOB：Phase 1 不需要
                }
            }
            rows.append(row)
        }
        return rows
    }
}
