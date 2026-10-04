import Foundation
import AkashicCore

/// #705：內容寫進 `entities/<id>.yaml`、但 #631 搬移後的 legacy 拷貝刪不掉的那一筆。
///
/// 它**寫了**：新內容在 `entities/`，legacy 檔（`entries/<citekey>.yaml`／`people/<key>.yaml`）還在，同一筆記錄現在有兩份。
/// load 把它標成無法唯一定位（#641）；兩份共用同一個 id（一般的寫入連 citekey／key 也相同；改名時 legacy 那份是舊鍵）。
/// 刪掉 legacy 那份之前，index 重建、匯出與 App 以 `entities/` 那份為準、略過 legacy 拷貝（#709，`ShadowedLegacyCopy`）——
/// 所以寫入之後重建 index 的呼叫照常成功，這一筆在成功回應裡。#709 之前 work 的兩份讓重建撞 UNIQUE、呼叫以錯誤收場。
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
    /// 同一個操作之後對這一筆的寫入被 #631 拒絕（兩份並存）——那一步的改動沒有套用（#705 R2 verify 第 5／9／20 列）。
    /// 由 `LibraryStore` 的寫入前置標記（`LegacyCopyLedger.noteLaterWriteRefused`），不由建構者給：記下這一筆的當下還沒有之後。
    /// 它讓「之後那一步沒套用」與這一筆記在**同一個地方**（成功那一側）：兩者的處置相同——刪掉 legacy 那份、重跑。
    public var laterWriteRefused = false

    public init(kind: Kind, key: String, id: UUID, legacyFile: String, detail: String) {
        self.kind = kind; self.key = key; self.id = id; self.legacyFile = legacyFile; self.detail = detail
    }

    /// 寫進去的那一份。
    public var writtenFile: String { "entities/\(id.uuidString).yaml" }

    /// 人可讀的一句話，已消毒——CLI 的尾段、MCP 錯誤回應的附記都印它。描述本體與範圍外擲出的
    /// `StoreIOError.legacyCopyNotRemoved` 同一份（同一件事只有一句話），前面具名是哪一筆。
    public var message: String {
        let base = StoreIOError.legacyCopyNotRemoved(id: id, file: legacyFile, detail: detail).errorDescription ?? ""
        let shared: String
        switch kind {
        case .person: shared = ""
        // 改名（`renameEntry`）時 legacy 那份是**舊** citekey：兩份共用的是 id，不是 citekey（#705 R1 verify 第 4／11 列）
        case .work where legacyFile == "entries/\(key).yaml": shared = "work 的兩份共用同一個 citekey："
        case .work: shared = "work 的兩份共用同一個 id——legacy 那份是改名前的 citekey："
        }
        // #709：刪掉之前 index、匯出與 App 以 entities/ 那份為準、略過 legacy 拷貝（先前 work 的兩份讓重建撞重複）
        let index = "（\(shared)刪掉之前 index、匯出與 App 以 entities/ 那份為準、略過 legacy 拷貝）"   // display-safe-exempt: shared：本檔字面
        return "\(kind.rawValue)「\(displaySafeInvisible(key, max: 200))」：\(base)\(index)"   // display-safe-exempt: base：errorDescription 對 file 以性質逃脫、detail 擲出端已消毒；kind：封閉列舉；index：本檔字面
    }

    /// 這件事是什麼的一句說明——**只此一份**：CLI／MCP 的報告標題（`reportLines`，前面帶鍵名）與 App 側欄的提示（`LegacyCopyNotice.headline`，
    /// 一般說明文字、不帶鍵名，#708 R1 verify 第 12／32 列）都用它，所以兩面說的是同一件事、不會各改各的。
    ///
    /// 不說「刪掉即可」（#705 第三次 verify）：同一份報告裡標了「之後的寫入沒有套用」的那幾筆刪掉之後還要重跑——那一句在逐筆的列上（`laterWriteRefusedNote`）。
    public static let explanation = "已寫入 entities/、搬移後的 legacy 拷貝沒刪掉——不是寫入失敗；確認 entities/ 那份是新的之後刪掉 legacy 那份"

    /// 兩面共用的人可讀報告：一行標題（鍵名＋完整筆數）加每筆一行。沒有就回空陣列——不印。
    ///
    /// `limit`（#705 R2 verify 第 13 列）：MCP 的錯誤回應至多列這麼多筆（依 (kind, key) 排序留前面的），多出的以一行說出筆數與去哪裡找——
    /// 回應直接進 LLM context，而筆數由 store 狀態決定（`entries/` 整個唯讀時每一筆寫入都留下一份）。截掉的找得回來：`akashic validate`
    /// 逐筆列出兩份並存的記錄（load 的 #641 標註），CLI 全列。nil＝全列（CLI）。
    public static func reportLines(_ items: [LegacyCopyLeft], limit: Int? = nil) -> [String] {
        guard !items.isEmpty else { return [] }
        let sorted = items.sorted { ($0.kind.rawValue, $0.key) < ($1.kind.rawValue, $1.key) }
        let shown = limit.map { Array(sorted.prefix($0)) } ?? sorted
        var lines = ["writtenWithLegacyCopy（\(explanation)）: \(items.count)"]   // display-safe-exempt: explanation：常量字面；count：Int
            + shown.map { "  ⚠ \($0.message)" + ($0.laterWriteRefused ? "；" + laterWriteRefusedNote : "") }   // display-safe-exempt: $0.message：已消毒（見上）；laterWriteRefusedNote：本型別的字面常量
        if shown.count < sorted.count, let limit {
            // 被截掉的列裡若有「之後的寫入沒有套用」的，只在這一行說得出（#705 R3 verify：標記在被截的列上時，唯一的回報跟著不見）
            let hiddenNotApplied = sorted.dropFirst(shown.count).filter(\.laterWriteRefused).count
            let hidden = hiddenNotApplied > 0 ? "；其中 \(hiddenNotApplied) 筆" + laterWriteRefusedNote : ""   // display-safe-exempt: Int；laterWriteRefusedNote：本型別的字面常量
            lines.append("  …另有 \(sorted.count - shown.count) 筆未列出（這裡至多列 \(limit) 筆；akashic validate 逐筆列出兩份並存的記錄，CLI 全列）\(hidden)")   // display-safe-exempt: Int
        }
        return lines
    }

    /// 之後的寫入沒有套用（`laterWriteRefused`）——人可讀報告每筆的附句與 MCP 列的 `laterWriteNotApplied` 同一句。
    public static let laterWriteRefusedNote =
        "同一個操作之後對這一筆的寫入沒有套用（兩份並存時 #631 拒絕同一筆的下一次寫入）——刪掉 legacy 那份之後重跑即可補上"
}

/// 收集 `LegacyCopyLeft` 的範圍（#705）。
///
/// `writeEntry`／`writePerson` 刪不掉搬移來源時：**範圍內**→ 記下這一筆、照常回傳（它寫了）；**範圍外**→ 擲
/// `StoreIOError.legacyCopyNotRemoved`（#702 的行為）。預設是擲：沒有人收集的地方不會安靜吞掉它。
///
/// 開範圍的是回報面，封閉列舉：MCP 的工具分派（`writtenWithLegacyCopy` 進回應，`Server.swift`）、CLI 的進入點
/// （`AkashicCLI.main`，印在輸出末尾）、直接印 service JSON 的 CLI 命令（鍵進那份 JSON）、`ZoteroImporter.run`（進 `ImportReport`）、
/// App 的各寫入點（`AppState.recordingLegacyCopies`，進側欄的非阻斷提示 `AppState.legacyCopyNotice`，#708——App 沒有單一出口，範圍開在各寫入點）。
///
/// **巢狀時最內層收下**：它自己的報告列出這一筆，外層不重複。內層的 body 擲錯時它沒有報告可以放——收到的**轉交外層**、
/// 回傳空陣列；沒有外層、或外層已經結束（收不下）時才原樣回傳給呼叫端，而呼叫端要經 `LegacyCopyLedger.get(_:written:)` 取結果：失敗時它把收到的附在擲出的錯誤上
/// （`LegacyCopyLeftBeforeFailure`），不讓它們跟著 `try result.get()` 一起消失（#705 R1 verify 第 17／22／30／36 列）。
/// 內層成功、之後的步驟才失敗的呼叫端，用 `handToEnclosingScope` 把報告裡的那幾筆交給外層（第 1 列）。每一筆恰好在一個地方被報告。
public final class LegacyCopyLedger: @unchecked Sendable {
    @TaskLocal static var active: LegacyCopyLedger?

    private let lock = NSLock()
    private var items: [LegacyCopyLeft] = []
    /// id → 在 `items` 的位置（同一個 id 第一次記下的那一筆）。先前 `ZoteroImporter` 每寫一筆就線性掃一次（#705 R2 verify 第 13 列：整趟 O(n²)）。
    private var indexByID: [UUID: Int] = [:]
    /// 外層範圍（開這個範圍時的 `active`）。查「同一個操作稍早寫過沒有」要沿鏈往外找：外層稍早記下一筆、之後開的內層範圍又寫同一筆時，
    /// 那一筆在外層（內層失敗時收到的也轉交外層，`collecting`）。誠實邊界：內層**成功**結束後收到的留在它自己的報告裡、不在鏈上——
    /// 外層之後再寫同一筆，得到的是泛用的 `legacyCopyPresent`（目前沒有寫入者這樣做：import 的範圍結束後同一次呼叫不再寫）。
    private let parent: LegacyCopyLedger?

    private init(parent: LegacyCopyLedger?) { self.parent = parent }

    /// 範圍已經結束（`collecting` 的 body 回傳之後）：之後才到的寫入**不得**再被這份帳本收下。
    /// `Task { }` 會繼承 task-local，範圍裡開的 `Task { }` 可以活得比範圍久——它之後的寫入若仍被這份帳本收下，記進一份早已取走報告的帳本，
    /// 沒有擲錯也沒有任何提示，兩份拷貝留著而使用者什麼都沒看到（#708 R2 verify 第 39 列：零實例表第 74 列與掃描器文件說「大聲而不是安靜」，
    /// 對 `Task { }` 為假）。關起來之後 `recordIfCollecting` 回 false，寫入端照無範圍時擲 `legacyCopyNotRemoved`——與 GCD、`Task.detached`
    /// （不繼承 task-local）同一個結果。
    private var closed = false

    /// 記下一筆；範圍已結束時回 false、不記。
    @discardableResult
    private func record(_ item: LegacyCopyLeft) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return false }
        if indexByID[item.id] == nil { indexByID[item.id] = items.count }
        items.append(item)
        return true
    }

    /// 一次記下全部；範圍已結束時一筆都不記、回 false。**全有或全無**（同一次加鎖、只看一次 `closed`）：呼叫端依回傳值決定那幾筆
    /// 留在自己的報告還是交出去，部分收下會讓收下的那幾筆被報兩次、或沒收下的那幾筆哪裡都不報（#708 R3 verify 第 15／20／24 列）。
    private func recordAll(_ batch: [LegacyCopyLeft]) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard !closed else { return false }
        for item in batch {
            if indexByID[item.id] == nil { indexByID[item.id] = items.count }
            items.append(item)
        }
        return true
    }

    private func close() {
        lock.lock(); defer { lock.unlock() }
        closed = true
    }

    private var recorded: [LegacyCopyLeft] {
        lock.lock(); defer { lock.unlock() }
        return items
    }

    /// 目前範圍到此為止收下的（不沿鏈往外）。`DOITwinNomination`（#611）用它排除這一趟留下 legacy 拷貝的 work，不把它們提名成候選。
    public static var collected: [LegacyCopyLeft] { active?.recorded ?? [] }

    private func find(_ id: UUID) -> LegacyCopyLeft? {
        lock.lock(); defer { lock.unlock() }
        return indexByID[id].map { items[$0] }
    }

    private func markLaterWriteRefused(_ id: UUID) -> Bool {
        lock.lock(); defer { lock.unlock() }
        guard let i = indexByID[id] else { return false }
        items[i].laterWriteRefused = true
        return true
    }

    /// 同一個操作稍早對這個 id 的寫入已落地、搬移後的 legacy 拷貝沒刪掉的那一筆（沿範圍鏈由內往外找；沒有就是 nil）。
    ///
    /// `LibraryStore` 的 #631 前置用它：兩份並存時，那個拒絕說出「稍早已寫入」，所有寫入者同一句（#705 R2 verify 第 5 列——先前只有
    /// `ZoteroImporter` 自己查、其他多步寫入者只得到泛用的「兩份並存」）。
    static func earlierWrite(id: UUID) -> LegacyCopyLeft? {
        var ledger = active
        while let l = ledger {
            if let item = l.find(id) { return item }
            ledger = l.parent
        }
        return nil
    }

    /// 在記著這一筆的範圍裡標記「之後的寫入沒有套用」；找不到回 false。冪等（一個 Bool）——多檔操作的前置與寫入當下各問一次也只標一次。
    @discardableResult
    static func noteLaterWriteRefused(id: UUID) -> Bool {
        var ledger = active
        while let l = ledger {
            if l.markLaterWriteRefused(id) { return true }
            ledger = l.parent
        }
        return false
    }

    /// 寫入端用：有範圍就記下並回 true（呼叫端照常回傳），沒有就回 false（呼叫端擲錯）。
    static func recordIfCollecting(_ item: LegacyCopyLeft) -> Bool {
        guard let ledger = active else { return false }
        return ledger.record(item)
    }

    /// 把已經收下、放進某份報告的那幾筆交給**目前的**範圍（外層）；沒有範圍、或那個範圍**已經結束**時回 false、什麼都不做（#705 R1 verify 第 1 列）。
    ///
    /// 給「內層範圍成功、之後的步驟才失敗」的呼叫端：`ZoteroImporter.run` 的範圍收下、放進 `ImportReport`，之後 index rebuild 失敗時
    /// 報告只能嵌進錯誤訊息，而錯誤出口有 96 KB／200 行的上限——交給外層（MCP 分派），它在格式化錯誤**之後**把人可讀報告放在回應最前面、不截。
    /// 回 true 時呼叫端要把那幾筆從自己的報告拿掉，否則同一筆報兩次；回 false 時留在自己的報告裡。
    /// **已經結束的範圍收不下**（#708 R3 verify 第 15／20／24 列）：先前這裡忽略 `record` 的回傳、一律回 true——繼承了 task-local、活得比範圍久的
    /// `Task { }` 把那幾筆交給一份已經關起來的帳本，什麼都沒記下，呼叫端卻依 true 把它們從自己的報告拿掉，哪裡都不報。
    @discardableResult
    public static func handToEnclosingScope(_ items: [LegacyCopyLeft]) -> Bool {
        guard let ledger = active else { return false }
        return ledger.recordAll(items)
    }

    /// `collecting` 的結果交回呼叫端的出口（#705 R1 verify 第 17／22／30／36 列）。成功回結果；失敗時，收到的若已轉交外層（`written` 是空的）
    /// 原樣擲出原本的錯誤，**沒有外層可轉交而收到了東西**就擲 `LegacyCopyLeftBeforeFailure`——寫進去的那幾筆跟著錯誤出去。
    /// 先前 `ZoteroImporter.run` 與 CLI 的 `LegacyCopyReport.payload` 直接 `try result.get()`，沒有外層範圍的呼叫端（測試、日後的嵌入）會把它們丟掉。
    public static func get<R>(_ result: Result<R, Error>, written: [LegacyCopyLeft]) throws -> R {
        switch result {
        case .success(let value): return value
        case .failure(let error):
            guard !written.isEmpty else { throw error }
            throw LegacyCopyLeftBeforeFailure(underlying: error, written: written)
        }
    }

    /// 在一個收集範圍裡跑 `body`。回傳它的結果與範圍內記下的每一筆（`written`）。
    public static func collecting<R>(_ body: () throws -> R) -> (result: Result<R, Error>, written: [LegacyCopyLeft]) {
        let outer = active
        let ledger = LegacyCopyLedger(parent: outer)
        let result: Result<R, Error> = $active.withValue(ledger) { Result { try body() } }
        ledger.close()   // 範圍結束：繼承 task-local、活得比範圍久的 `Task { }` 之後的寫入不得再被收下（見 `closed`）
        let written = ledger.recorded
        // 失敗時轉交外層——外層已經結束時收不下（#708 R3 verify 第 15／20／24 列：先前忽略回傳、回空陣列，那幾筆哪裡都不報），
        // 那就照沒有外層時一樣回傳給呼叫端，`get` 把它們附在擲出的錯誤上。
        if case .failure = result, let outer, outer.recordAll(written) {
            return (result, [])
        }
        return (result, written)
    }
}

/// 沒有外層收集範圍、而 body 在留下 legacy 拷貝之後擲錯：錯誤帶著已經寫進去的那幾筆（#705 R1 verify 第 17／22／30／36 列）。
///
/// 描述**先說寫了什麼**、再說錯誤——與 MCP 錯誤回應同一個順序（第 5 列）。`underlying` 是原本的錯誤；要判斷錯誤種類的呼叫端從這裡拿。
/// 只由 `LegacyCopyLedger.get` 擲出，而那只在沒有外層範圍時發生：CLI 進入點與 MCP 分派一定有外層（它們自己是最外層、自己處理 `written`），
/// 所以這兩面的錯誤型別與結束碼不受影響。
public struct LegacyCopyLeftBeforeFailure: LocalizedError, SanitizedErrorDescription {
    public let underlying: Error
    public let written: [LegacyCopyLeft]

    public init(underlying: Error, written: [LegacyCopyLeft]) {
        self.underlying = underlying; self.written = written
    }

    public var errorDescription: String? {
        (LegacyCopyLeft.reportLines(written) + ["", displaySafeErrorText(underlying)]).joined(separator: "\n")   // display-safe-exempt: reportLines 由已消毒的 message 組成；underlying 經 displaySafeErrorText 逃一次
    }
}
