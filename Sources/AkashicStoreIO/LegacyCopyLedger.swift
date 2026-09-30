import Foundation
import AkashicCore

/// #705：內容寫進 `entities/<id>.yaml`、但 #631 搬移後的 legacy 拷貝刪不掉的那一筆。
///
/// 它**寫了**：新內容在 `entities/`，legacy 檔（`entries/<citekey>.yaml`／`people/<key>.yaml`）還在，同一筆記錄現在有兩份。
/// load 把它標成無法唯一定位（#641）；work 的兩份共用同一個 citekey，刪掉 legacy 那份之前 index 重建會撞重複（person 的不會——
/// index 的 people 表對重複 key 留第一筆，#670）。
///
/// 使用者 2026-09-30 裁決 (a)：各寫入者統一，這一筆記在**成功那一側**的 `writtenWithLegacyCopy`，不算失敗、不進任何失敗清單。
/// #702 之前 import-zotero 把它同時列在成功清單與 `writeFailed`，其他寫入者則只算它失敗——同一件事兩種說法，而兩種都不完全對。
public struct LegacyCopyLeft: Equatable, Sendable {
    public enum Kind: String, Sendable { case work, person }

    public let kind: Kind
    /// citekey（work）或 person key。**原始值**——輸出端消毒。
    public let key: String
    public let id: UUID
    /// legacy 檔相對 store root 的路徑。**原始值**（含 key）——輸出端消毒。
    public let legacyFile: String
    /// 刪不掉的原因。**擲出端已消毒**（`displaySafeError`）。
    public let detail: String

    public init(kind: Kind, key: String, id: UUID, legacyFile: String, detail: String) {
        self.kind = kind; self.key = key; self.id = id; self.legacyFile = legacyFile; self.detail = detail
    }

    /// 寫進去的那一份。
    public var writtenFile: String { "entities/\(id.uuidString).yaml" }

    /// 人可讀的一句話，已消毒——CLI 的尾段、MCP 錯誤回應的附記都印它。描述本體與範圍外擲出的
    /// `StoreIOError.legacyCopyNotRemoved` 同一份（同一件事只有一句話），前面具名是哪一筆。
    public var message: String {
        let base = StoreIOError.legacyCopyNotRemoved(id: id, file: legacyFile, detail: detail).errorDescription ?? ""
        let index = kind == .work ? "（work 的兩份共用同一個 citekey：刪掉之前 index 重建會撞重複）" : ""
        return "\(kind.rawValue)「\(displaySafeInvisible(key, max: 200))」：\(base)\(index)"   // display-safe-exempt: base：errorDescription 對 file 以性質逃脫、detail 擲出端已消毒；kind：封閉列舉；index：本檔字面
    }

    /// 兩面共用的人可讀報告：一行標題（鍵名＋筆數）加每筆一行。沒有就回空陣列——不印。
    public static func reportLines(_ items: [LegacyCopyLeft]) -> [String] {
        guard !items.isEmpty else { return [] }
        let sorted = items.sorted { ($0.kind.rawValue, $0.key) < ($1.kind.rawValue, $1.key) }
        return ["writtenWithLegacyCopy（已寫入 entities/、搬移後的 legacy 拷貝沒刪掉——不是寫入失敗，刪掉 legacy 那份即可）: \(items.count)"]   // display-safe-exempt: count：Int
            + sorted.map { "  ⚠ \($0.message)" }   // display-safe-exempt: $0.message：已消毒（見上）
    }
}

/// 收集 `LegacyCopyLeft` 的範圍（#705）。
///
/// `writeEntry`／`writePerson` 刪不掉搬移來源時：**範圍內**→ 記下這一筆、照常回傳（它寫了）；**範圍外**→ 擲
/// `StoreIOError.legacyCopyNotRemoved`（#702 的行為）。預設是擲：沒有人收集的地方不會安靜吞掉它。
///
/// 開範圍的是回報面，封閉列舉：MCP 的工具分派（`writtenWithLegacyCopy` 進回應，`Server.swift`）、CLI 的進入點
/// （`AkashicCLI.main`，印在輸出末尾）、直接印 service JSON 的 CLI 命令（鍵進那份 JSON）、`ZoteroImporter.run`（進 `ImportReport`）。
/// App 沒有開——它的單筆編輯沒有報告可以放，照舊擲出那句「已寫入……」。
///
/// **巢狀時最內層收下**：它自己的報告列出這一筆，外層不重複。內層的 body 擲錯時它沒有報告可以放——收到的**轉交外層**、
/// 回傳空陣列；沒有外層時才原樣回傳給呼叫端。每一筆恰好在一個地方被報告。
public final class LegacyCopyLedger: @unchecked Sendable {
    @TaskLocal static var active: LegacyCopyLedger?

    private let lock = NSLock()
    private var items: [LegacyCopyLeft] = []

    private init() {}

    private func record(_ item: LegacyCopyLeft) {
        lock.lock(); defer { lock.unlock() }
        items.append(item)
    }

    private var recorded: [LegacyCopyLeft] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    /// 最內層範圍到目前為止記下的（沒有範圍時是空的）。給同一個操作裡**之後的步驟**用：稍早一步對某筆記錄的寫入已落地、
    /// legacy 拷貝還在時，#631 會拒絕同一筆的下一次寫入（兩份並存）——呼叫端可以先查這裡、具名說出前一步寫了
    /// （`ZoteroImporter` 的主來源、附加來源、orphan 標記可能在同一趟各寫一次同一筆，#702 R2 verify）。
    public static var collected: [LegacyCopyLeft] { active?.recorded ?? [] }

    /// 寫入端用：有範圍就記下並回 true（呼叫端照常回傳），沒有就回 false（呼叫端擲錯）。
    static func recordIfCollecting(_ item: LegacyCopyLeft) -> Bool {
        guard let ledger = active else { return false }
        ledger.record(item)
        return true
    }

    /// 在一個收集範圍裡跑 `body`。回傳它的結果與範圍內記下的每一筆（`written`）。
    public static func collecting<R>(_ body: () throws -> R) -> (result: Result<R, Error>, written: [LegacyCopyLeft]) {
        let outer = active
        let ledger = LegacyCopyLedger()
        let result: Result<R, Error> = $active.withValue(ledger) { Result { try body() } }
        let written = ledger.recorded
        if case .failure = result, let outer {
            for item in written { outer.record(item) }
            return (result, [])
        }
        return (result, written)
    }
}
