import Foundation
import AkashicCore
import AkashicStoreIO

/// #705：寫進 `entities/`、#631 搬移後的 legacy 拷貝沒刪掉的那一筆——兩面的回報出口。
///
/// 使用者 2026-09-30 裁決 (a)：記在成功那一側的 `writtenWithLegacyCopy`，不算失敗、不進任何失敗清單，全部寫入者統一。
/// 寫入端（`LibraryStore.writeEntry`／`writePerson`）在收集範圍裡只記下、照常回傳；這裡把收到的放進回應：
///
/// - **MCP 工具分派**（`Server.swift`）：每一次呼叫都在一個範圍裡跑，結束後呼叫 `reportingWrittenWithLegacyCopy`。
/// - **直接印 service JSON 的 CLI 命令**：同一個函式，鍵進那份 JSON。
/// - `akashic_import_zotero`：`ZoteroImporter.run` 自己收下，`importReportPayload` 從報告帶出（同一個 `legacyCopyRows`）。
extension AkashicService {
    /// 回應鍵名——兩面、成功與錯誤兩條路徑同一個字串。
    public static let writtenWithLegacyCopyKey = "writtenWithLegacyCopy"

    /// 回應裡的一筆：`{kind, key, written, legacyFile, detail}`，依 (kind, key) 排序。字串都消毒過（key 與 legacyFile 是 store 內容；
    /// detail 在擲出端已消毒，這裡只截）。不截筆數：每一筆都要人去刪 legacy 那份，截掉的就找不回來（同 writeFailed 不截）。
    static func legacyCopyRows(_ items: [LegacyCopyLeft]) -> [[String: String]] {
        items.sorted { ($0.kind.rawValue, $0.key) < ($1.kind.rawValue, $1.key) }.map {
            ["kind": $0.kind.rawValue,   // display-safe-exempt: 封閉列舉的 rawValue
             "key": displaySafeInvisible($0.key, max: 200),
             "written": $0.writtenFile,   // display-safe-exempt: writtenFile：固定前綴＋UUID
             "legacyFile": displaySafeInvisible($0.legacyFile, max: 300),
             "detail": displaySafeClipOnly($0.detail, max: 600)]   // display-safe-exempt: detail：擲出端已消毒（displaySafeError），只截
        }
    }

    /// 把收到的放進一次回應。沒有收到任何一筆時原樣回傳（位元組不變）。
    ///
    /// - **錯誤回應** → 兩面共用的人可讀報告（`LegacyCopyLeft.reportLines`）放在**最前面**，接著空一行、原本的錯誤文字。報告在前，呼叫端先讀到
    ///   「寫了、留下一份 legacy 拷貝」，才讀到錯誤；#705 R1 verify 第 5 列：附在末尾時，收到 isError 的 agent 先讀到失敗、很可能重試，而重試會被
    ///   #631 拒絕（兩份並存）。#709 之前這一格最常見（work 的兩份共用 citekey，寫入之後的 index rebuild 撞 UNIQUE）；#709 起 index 以
    ///   `entities/` 那份為準、略過 legacy 拷貝，那一步不再失敗，這一格只剩寫了之後別的步驟失敗（例如 store 裡另有兩筆不同的記錄共用 citekey）。
    ///   報告在錯誤文字格式化**之後**才接上，不受錯誤出口的截斷（96 KB／200 行）。
    /// - 成功、且回應是 JSON 物件 → 加上 `writtenWithLegacyCopy` 鍵（同一組序列化選項，與 `jsonString` 一致）。鍵已經在（`akashic_import_zotero`
    ///   的 payload 自己帶）時**併進**那個陣列、依 (kind, key) 重排——回應仍是一份 JSON（第 15 列：先前落到下一格，把合法 JSON 變成 JSON 加文字）。
    /// - 成功卻不是 JSON 物件（陣列、純文字）→ 沒有地方放鍵：報告附在後面，不動原本的內容。
    public static func reportingWrittenWithLegacyCopy(_ text: String, _ written: [LegacyCopyLeft], isError: Bool) -> String {
        guard !written.isEmpty else { return text }
        if isError {
            return (LegacyCopyLeft.reportLines(written) + ["", text]).joined(separator: "\n")   // display-safe-exempt: reportLines：LegacyCopyLeft.message 已消毒；text 是呼叫端已組好的回應
        }
        if var obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] {
            let rows: [Any]? = switch obj[writtenWithLegacyCopyKey] {
            case nil: legacyCopyRows(written)
            case let existing as [Any]: (existing + legacyCopyRows(written)).sorted { Self.rowSortKey($0) < Self.rowSortKey($1) }
            default: nil   // 同名鍵卻不是陣列：不是這個函式寫的形狀，不覆寫它——落到下一格附文字
            }
            if let rows {
                obj[writtenWithLegacyCopyKey] = rows
                if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                    return UnsafeToEmitScalar.escapingUnsafeScalars(inSerializedJSON: String(decoding: data, as: UTF8.self))
                }
            }
        }
        return ([text, ""] + LegacyCopyLeft.reportLines(written)).joined(separator: "\n")   // display-safe-exempt: reportLines：LegacyCopyLeft.message 已消毒；text 是呼叫端已組好的回應
    }

    /// 併進既有陣列時的排序鍵：與 `legacyCopyRows` 同一個 (kind, key)。
    private static func rowSortKey(_ row: Any) -> String {
        let d = row as? [String: Any]
        return "\(d?["kind"] as? String ?? "")\u{0}\(d?["key"] as? String ?? "")"   // display-safe-exempt: 只用來排序，不輸出
    }
}
