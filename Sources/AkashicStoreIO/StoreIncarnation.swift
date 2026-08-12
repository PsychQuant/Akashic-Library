import Foundation
import AkashicCore

/// store 的**化身 id**（#130）——回答「這是不是同一個 store」，不回答「內容新不新」。
///
/// ## 為什麼路徑不夠
///
/// index 的身分戳記原本只記 canonical path。那讓兩件事分不出來：
///
/// - **同路徑重生**：刪掉 store、在同一個位置建一個新的 → 路徑相同 → 舊 index
///   通過身分檢查 → 查詢**讀舊 store 的資料當現況**。
/// - **cross-process swap**：驗證與開啟之間有人把檔案換掉。
///
/// ## 判準偏向「判為新化身」（裁決 1）
///
/// 兩種誤判的代價完全不對稱：
///
/// | 誤判 | 後果 |
/// |---|---|
/// | 同一個 store 被當成新化身 | index 白重建一次——**只是時間** |
/// | 新 store 被當成舊化身 | 讀舊化身的資料當現況——**靜默給錯答案** |
///
/// 所以任何模稜兩可一律當新的。缺席（既有 store 都沒有這個檔案）回 `nil` 並退回
/// 純路徑比對——那是今天的行為，不是退步。
///
/// ## 為什麼是根目錄的獨立檔案，不進 `store.yaml`（裁決 2）
///
/// `StoreVersion.read` 對任何非 `format:` 的有內容行 **throw**。加一行進
/// `store.yaml`，**所有既有 binary 會拒絕開啟整個 store**——不是忽略未知欄位，是
/// 連讀都不讀。為了一個只有 index 在乎的欄位炸掉舊 binary 的全部功能，不划算。
///
/// 實測舊 binary 對根目錄未知檔案：`validate` 與 `doctor` 都完全容忍。**優雅降級**
/// ——舊 binary 照常運作，只是拿不到重生保護，而它今天本來就沒有。
///
/// 放根目錄而非 `.akashic/`：真實 store 的 `.gitignore` 排除 `.akashic/`（那是衍生物
/// 的位置）。化身 id 不是衍生物——它與 `store.yaml` 同類，是 store 的身分，該進版控、
/// 該隨 clone 走。
///
/// ## 複製出來的 store 是同一個化身
///
/// id 隨檔案原樣搬移（cp / rsync / Dropbox / git 都一樣）——它就是同一份位元組。
/// 這不需要特別設計，是「它是一個檔案」的自然結果。要防的那個情境（同路徑重生）
/// 自動被涵蓋：新 store 走 `library create` 拿到新 id。
///
/// Dropbox 兩機也對：同一份 store 同步到兩台機器、id 相同、各自有各自的 index。
/// **內容是否過期由既有的內容比對機制負責**——化身身分與內容新舊是兩個問題，
/// 不要用一個機制回答兩件事。
public enum StoreIncarnation {

    public static let fileName = "incarnation"

    public static func url(in root: URL) -> URL {
        root.appendingPathComponent(fileName)
    }

    /// 讀化身 id。**缺席、空白、格式不符一律回 `nil`，不 throw。**
    ///
    /// 不 throw 是刻意的：既有 store 全部沒有這個檔案，讓它 throw 等於把一個
    /// 選配的加強變成載入的前置條件。格式不符也回 `nil` 而不是 throw——那與
    /// 「任何模稜兩可一律當新的」一致（`nil` 退回路徑比對，不會誤信）。
    public static func read(root: URL) -> String? {
        try? readStrict(root: root)
    }

    /// 讀不到的三種原因，**分開**（#130 verify C）。
    ///
    /// `read()` 先前不區分「不存在」與「存在但讀失敗」，而 `writeIfAbsent` 只問
    /// 它是否回 `nil`——於是**檔案存在但讀不到時，store 的身分被靜默覆寫**。
    /// 席位實測三種情形：
    ///
    /// | 情形 | 先前的行為 |
    /// |---|---|
    /// | 截斷（Dropbox 半截同步）| id 換掉，舊 index 變孤兒 |
    /// | `chmod 000`（online-only placeholder／權限）| `doctor` **exit 0、零訊息**，id 換掉 |
    /// | 連續跑 | **每跑一次換一個新 id** |
    ///
    /// 不可讀那條最嚴重且連鎖：atomic replace **保留 000 權限**，所以新 id 也讀
    /// 不到 → `indexURL` 退回無 tag 的舊檔名 → 整個機制靜默失效，而
    /// `orphanedIndexFiles()` 在 tag 為 `nil` 時回 `[]`，連累積出來的孤兒都不報。
    ///
    /// 而 doc 自己寫著「既有的一律不覆寫——覆寫等於把一個 store 變成另一個化身，
    /// 而那正是這個機制要偵測的事件」。實作在讀失敗時做的**正是那件事**。
    /// **Dropbox 是文件自己點名要支援的情境**，所以這裡該 fail-loud。
    public static func readStrict(root: URL) throws -> String? {
        let u = url(in: root)
        guard FileManager.default.fileExists(atPath: u.path) else { return nil }   // 真的缺席
        let data: Data
        do { data = try Data(contentsOf: u) }
        catch { throw StoreIncarnationError.unreadable(path: u.path, why: error.localizedDescription) }
        return try parse(data: data, path: u.path)
    }

    /// 與 filesystem API 共用的 bytes parser。snapshot 只解析已接受的 capture，
    /// 因此 identity 與 revision 看到的 incarnation 必定是同一份原始 bytes。
    static func parse(data: Data?, path: String) throws -> String? {
        guard let data else { return nil }
        guard let text = String(data: data, encoding: .utf8) else {
            throw StoreIncarnationError.unreadable(path: path, why: "內容不是 UTF-8")
        }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmed.count == 36,
              let uuid = UUID(uuidString: trimmed),
              uuid.uuidString.caseInsensitiveCompare(trimmed) == .orderedSame else {
            throw StoreIncarnationError.malformed(path: path, content: trimmed)
        }
        return uuid.uuidString
    }

    /// 不存在才寫（沿用 `StoreVersion.writeIfAbsent` 的模式）。回傳最終的 id。
    ///
    /// **既有的 id 一律不覆寫**——覆寫等於把一個 store 變成另一個化身，而那正是
    /// 這個機制要偵測的事件。
    @discardableResult
    public static func writeIfAbsent(root: URL, id: UUID = UUID()) throws -> String {
        // **走 strict**（#130 verify C）：讀失敗必須 throw，不能被當成缺席而覆寫。
        if let existing = try readStrict(root: root) { return existing }
        let value = id.uuidString
        try (value + "\n").write(to: url(in: root), atomically: true, encoding: .utf8)
        return value
    }

    /// index 檔名用的短前綴——化身 id 的前 8 碼。
    ///
    /// **把 TOCTOU 從「偵測」變成「不可表達」**（裁決 3）：驗證與開啟之間有多少
    /// 檔案存取都無所謂，因為**檔名本身就綁定化身**，換掉的檔案根本不叫這個名字。
    /// pin connection 只是把競爭窗口縮小，窗口仍在。
    ///
    /// 附帶好處：同路徑重生時新舊 index 是**不同檔案**，不存在「舊 index 被誤信」
    /// 的狀態。代價是重生後舊 index 檔成為孤兒，需要 `doctor` 報告（不 GC——
    /// 報告不動手，與 #79 的形狀一致）。
    public static func shortTag(_ id: String?) -> String? {
        guard let id, id.count >= 8 else { return nil }
        return String(id.prefix(8)).lowercased()
    }
}

/// 化身檔讀取失敗（#130 verify C）。**與「缺席」嚴格分開**——缺席回 `nil` 是正常的
/// （既有 store 都沒有），讀失敗則必須 fail-loud，否則 `writeIfAbsent` 會覆寫掉一個
/// 存在但暫時讀不到的身分。
public enum StoreIncarnationError: Error, LocalizedError {
    case unreadable(path: String, why: String)
    case malformed(path: String, content: String)

    public var errorDescription: String? {
        switch self {
        case let .unreadable(path, why):
            return "化身檔「\(displaySafe(path, max: 300))」存在但讀不到（\(displaySafe(why, max: 300))）"
                + "——**不覆寫**：它是 store 的身分，覆寫等於把它變成另一個化身。"
                + "修好權限／等同步完成後重試；確定要重新賦予身分請自行刪除該檔"
        case let .malformed(path, content):
            return "化身檔「\(displaySafe(path, max: 300))」的內容不是 UUID"
                + "（實得「\(displaySafe(content, max: 120))」）——同樣不覆寫，理由同上"
        }
    }
}
