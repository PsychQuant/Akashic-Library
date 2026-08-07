import Foundation
import SQLite3

public enum SQLiteError: Error, LocalizedError {
    case openFailed(String)
    case prepareFailed(String, sql: String)
    case stepFailed(String, sql: String)
    case bindFailed(String)

    public var errorDescription: String? {
        switch self {
        case .openFailed(let m): return "SQLite open 失敗：\(m)"   // display-safe-exempt: m 是 sqlite3_errmsg，非 caller/store payload
        // #158 verify R4：`sql` 由**呼叫端**建構，所以這條 exempt 依賴一個**跨模組
        // 不變式**——SQL 文字只由程式字面片段組成、所有值走 `?` bind。釘在這裡而不是
        // 寫在別的檔案的 opt-out 理由裡，是因為改 SQL 建構的人會看見這一行。
        // 唯一的 SQL 內插點：`AkashicQuery/QueryEngine.swift:100` 的 `\(whereClause)`，
        // 內插的是 `conditions` 陣列（全為程式字面片段 + `?`），值全走 bind。
        case .prepareFailed(let m, let sql): return "SQLite prepare 失敗：\(m)（\(sql)）"   // display-safe-exempt: m 是 errmsg；sql 見上方不變式
        case .stepFailed(let m, let sql): return "SQLite step 失敗：\(m)（\(sql)）"   // display-safe-exempt: 同 prepareFailed 的不變式
        // #158 verify R4：**這條與上面三條不同**——`bindFailed` 的 payload 來自
        // `SQLiteDB.swift:79` 的 `String(describing: value)`，`value` 是 **caller 傳進來
        // 的 bind 值**，不是 errmsg 也不是 SQL。目前 unreachable（呼叫端只 bind 支援
        // 型別），但「目前不可達」與「不含 caller payload」是兩件事——前一版的 opt-out
        // 理由宣稱後者，那是假的。
        case .bindFailed(let m): return "SQLite bind 失敗：\(m)"   // display-safe-exempt: payload 已在 :79 收斂成型別名（見該處）
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

    deinit { if handle != nil { sqlite3_close(handle) } }

    /// 顯式關閉，供 atomic rename 前使用（#7a）。SQLite 對「搬移一個仍開啟的
    /// 資料庫檔」沒有定義行為，所以換位前必須關。idempotent；關閉後不得再用。
    public func closeForHandoff() {
        if handle != nil { sqlite3_close(handle); handle = nil }
    }

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
                // #158 verify R4：**不要把值本身放進訊息**。原本是
                // `String(describing: value)`——那是 caller 傳進來的任意值，會經
                // errorDescription 流到使用者可見輸出。而訊息真正需要的是**型別**
                // 不是值：「不支援的型別：Date」比「不支援的型別：2020-01-01」更有用。
                // 收斂成型別名之後這條路徑結構上不可能帶 payload——比消毒更徹底，
                // 也讓 AkashicSQLite 不必依賴 AkashicCore（C 綁定模組不該依賴 domain core）。
                throw SQLiteError.bindFailed("不支援的型別：\(type(of: value))")
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
