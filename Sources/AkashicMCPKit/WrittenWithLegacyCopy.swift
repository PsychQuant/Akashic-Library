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
    /// - 成功、且回應是 JSON 物件 → 加上 `writtenWithLegacyCopy` 鍵（同一組序列化選項，與 `jsonString` 一致）。
    /// - 錯誤回應，或成功卻不是 JSON 物件（陣列、純文字）→ 沒有地方放鍵：把兩面共用的人可讀報告（`LegacyCopyLeft.reportLines`）
    ///   附在後面。錯誤那一格最常見——work 的兩份共用 citekey，寫入之後的 index rebuild 撞重複；寫進去的那一筆不能跟著錯誤消失。
    public static func reportingWrittenWithLegacyCopy(_ text: String, _ written: [LegacyCopyLeft], isError: Bool) -> String {
        guard !written.isEmpty else { return text }
        if !isError,
           var obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any],
           obj[writtenWithLegacyCopyKey] == nil {
            obj[writtenWithLegacyCopyKey] = legacyCopyRows(written)
            if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                return UnsafeToEmitScalar.escapingUnsafeScalars(inSerializedJSON: String(decoding: data, as: UTF8.self))
            }
        }
        return ([text, ""] + LegacyCopyLeft.reportLines(written)).joined(separator: "\n")   // display-safe-exempt: reportLines：LegacyCopyLeft.message 已消毒；text 是呼叫端已組好的回應
    }
}
