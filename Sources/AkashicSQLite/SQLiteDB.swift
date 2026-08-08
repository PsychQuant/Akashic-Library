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
        // #158 verify R4：**這條與上面三條不同**——`bindFailed` 的 payload 曾經是
        // **caller 傳進來的 bind 值**（`String(describing: value)`），不是 errmsg 也不是
        // SQL。目前那條路徑已把 payload 收斂成型別名（見下方 `run(_:bind:)` 的 `default:` 分支）。
        //
        //（不寫死行號：R4 席位指出前一版指向的 `:79` 在我自己的修改之後就 stale 了。
        // 「見下方某某分支」這種符號式引用不會隨行號漂移。）
        case .bindFailed(let m): return "SQLite bind 失敗：\(m)"   // display-safe-exempt: payload 兩個來源都不含 caller 值——(1) run(_:bind:) 的 default: 收斂成型別名（ObjC 橋接實例會是 CF 實作名如 __NSCFNumber，那是真實動態型別，不做映射）(2) sqlite3_errmsg（同 openFailed）。這一行已連續三次寫錯（stale :79 → 「收斂成型別名」曾不成立 → 符號名 bind 不存在），它是守衛唯一逼人寫、卻沒有測試看著的那句話
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
                // errorDescription 流到使用者可見輸出。
                //
                // **為什麼拿掉值不是「型別比較有用」這種品味判斷**（R4 席位給的因果
                // 版，比我原本的理由強）：會落進這個 `default:` 是因為**型別**不在
                // `nil`/`Int`/`Int64`/`Double`/`String` 之列。對**絕大多數**型別，值
                // 不影響落到哪個分支，所以值對「為什麼失敗」攜帶零診斷資訊。這擋得住
                // 未來有人說「可是看到值也不錯啊」。
                //
                // **但那不是全稱句**（#158 verify F2）：`NSNumber` 的 `as?` 橋接走
                // exact-value 語義——`NSNumber(3)` 走 `case let v as Int` 成功，
                // `NSNumber(UInt64.max)` 落進這裡。**同一個靜態型別，值決定分支。**
                // 那一族失敗的原因恰恰是值，而訊息只給型別名。無實害（codebase 沒有
                // bind `NSNumber` 的呼叫端），且反洩漏的理由**完全不受影響**——
                // 該修的是過強的因果句，不是那個決定。
                //
                // **`value!` 是必要的**（#158 verify F1）：`value` 的靜態型別是 `Any?`，
                // `type(of: value)` 一律回 `Optional<Any>`——**每一次**，不只異質集合時。
                // 席位實測 Date／Bool／Float／[Any]／Data 全部印 `Optional<Any>`，
                // `type(of: value as Any)` 也一樣無效；**只有 unwrap 之後**才拿得到
                // `Date` / `Bool` / `Array<Any>` / `__NSCFNumber`。`case nil:` 在上面，
                // 所以這裡必非 nil。
                //
                // 三處註解宣稱「收斂成型別名」，而在修掉之前收斂成的是一個常量字串
                // ——**改進點 4 正是「量詞要給『跑什麼會看到什麼』」，而改進點 2／3
                // 的理由自己沒跑過**。
                //
                // 收斂成型別名讓 payload-free 成為**結構性質而非紀律**：AkashicSQLite
                // 沒有 `displaySafe` 可用（C 綁定模組不該依賴 domain core），所以
                // 「這裡不准放 payload」是編譯器層級的事實，不是靠人記得。
                //
                // **補 bind index**（R4 席位）：`idx` 是 `Int32`、結構上不可能帶 payload，
                // 卻補回了值原本在偷偷代理的那個資訊——「是**哪一個**呼叫端」。異質
                // 集合的 `type(of:)` 只給 `Array<Any>` 時，這是唯一能定位的線索。
                throw SQLiteError.bindFailed(
                    "參數 #\(idx) 不支援的型別：\(type(of: value!))")
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
