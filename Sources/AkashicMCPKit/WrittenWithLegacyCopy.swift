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
    /// 完整筆數與有沒有截（#705 R2 verify 第 13 列）——與 `writtenWithLegacyCopy` 同進同出（`ambiguousSourceClaims` 那三個鍵的形）。
    public static let writtenWithLegacyCopyTotalKey = "writtenWithLegacyCopyTotal"
    public static let writtenWithLegacyCopyTruncatedKey = "writtenWithLegacyCopyTruncated"
    /// 完整筆數裡**之後的寫入沒有套用**的有幾筆（#705 R3 verify，codex：成功清單截到 20 筆時，唯一的「有更新沒完成」回報可能正好在被截掉的那幾列）。
    /// 在截斷之外、只在 > 0 時出現（沒有這個鍵＝零筆，不改既有回應的位元組）；併進已帶這個鍵的回應時是兩邊相加。
    /// 這個數不是「還有幾份拷貝要清」（那是 `…Total`），是「這一趟有幾次更新沒落地、刪掉 legacy 那份之後要重跑」。
    public static let writtenWithLegacyCopyNotAppliedKey = "writtenWithLegacyCopyNotApplied"
    /// MCP 回應至多列這麼多筆（#705 R2 verify 第 13 列）：回應直接進 LLM context，而筆數由 store 狀態決定——`entries/` 整個唯讀時
    /// 每一筆寫入都留下一份。截掉的找得回來：`akashic validate` 逐筆列出兩份並存的記錄（load 的 #641 標註），CLI 全列。
    /// （R1 的理由「截掉的就找不回來」不成立：留下的 legacy 檔在磁碟上，load 每次都看得到它。）
    public static let writtenWithLegacyCopyLimit = 20

    /// 回應裡的一筆：`{kind, key, written, legacyFile, detail}`（之後的寫入沒有套用時另帶 `laterWriteNotApplied`），依 (kind, key) 排序。
    /// 字串都消毒過（key 與 legacyFile 是 store 內容；detail 在擲出端已消毒，這裡只截）。筆數的上限在 `legacyCopyFields`。
    static func legacyCopyRows(_ items: [LegacyCopyLeft]) -> [[String: String]] {
        items.sorted { ($0.kind.rawValue, $0.key) < ($1.kind.rawValue, $1.key) }.map {
            var row = ["kind": $0.kind.rawValue,   // display-safe-exempt: 封閉列舉的 rawValue
                       "key": displaySafeInvisible($0.key, max: 200),
                       "written": $0.writtenFile,   // display-safe-exempt: writtenFile：固定前綴＋UUID
                       "legacyFile": displaySafeInvisible($0.legacyFile, max: 300),
                       "detail": displaySafeClipOnly($0.detail, max: 600)]   // display-safe-exempt: detail：擲出端已消毒（displaySafeError），只截
            if $0.laterWriteRefused { row["laterWriteNotApplied"] = LegacyCopyLeft.laterWriteRefusedNote }   // display-safe-exempt: 本型別的字面常量
            return row
        }
    }

    /// 三個同進同出的鍵：已排序的列留前 `limit` 筆（nil＝全列）、`total` 是完整筆數、有沒有截。
    /// `notApplied`（#705 R3 verify）：完整筆數裡之後的寫入沒有套用的有幾筆——由呼叫端數**截斷之前**的完整清單；> 0 才另給第四個鍵。
    static func legacyCopyFields(rows: [Any], total: Int, notApplied: Int = 0, limit: Int?) -> [String: Any] {
        let shown = limit.map { Array(rows.prefix($0)) } ?? rows
        var fields: [String: Any] = [writtenWithLegacyCopyKey: shown,
                                     writtenWithLegacyCopyTotalKey: total,   // display-safe-exempt: Int
                                     writtenWithLegacyCopyTruncatedKey: shown.count < total]   // display-safe-exempt: Bool
        if notApplied > 0 { fields[writtenWithLegacyCopyNotAppliedKey] = notApplied }   // display-safe-exempt: Int
        return fields
    }

    /// 把收到的放進一次回應。沒有收到任何一筆時原樣回傳（位元組不變）。
    ///
    /// `limit`：至多列幾筆（MCP 預設 `writtenWithLegacyCopyLimit`；CLI 的 `LegacyCopyReport` 傳 nil＝全列）。JSON 物件帶三個鍵
    /// （`writtenWithLegacyCopy`、`…Total`、`…Truncated`）；文字（錯誤回應、非物件）的人可讀報告標題是完整筆數，多出的一行說去哪裡找。
    ///
    /// - **錯誤回應** → 兩面共用的人可讀報告（`LegacyCopyLeft.reportLines`）放在**最前面**，接著空一行、原本的錯誤文字。報告在前，呼叫端先讀到
    ///   「寫了、留下一份 legacy 拷貝」，才讀到錯誤；#705 R1 verify 第 5 列：附在末尾時，收到 isError 的 agent 先讀到失敗、很可能重試，而重試會被
    ///   #631 拒絕（兩份並存）。#709 之前這一格最常見（work 的兩份共用 citekey，寫入之後的 index rebuild 撞 UNIQUE）；#709 起 index 以
    ///   `entities/` 那份為準、略過 legacy 拷貝，那一步不再失敗，這一格只剩寫了之後別的步驟失敗（例如 store 裡另有兩筆不同的記錄共用 citekey）。
    ///   報告在錯誤文字格式化**之後**才接上，不受錯誤出口的截斷（96 KB／200 行）。
    /// - 成功、且回應是 JSON 物件 → 加上 `writtenWithLegacyCopy` 鍵（同一組序列化選項，與 `jsonString` 一致）。鍵已經在（`akashic_import_zotero`
    ///   的 payload 自己帶）時**併進**那個陣列、依 (kind, key) 重排——回應仍是一份 JSON（第 15 列：先前落到下一格，把合法 JSON 變成 JSON 加文字）。
    /// - 成功卻不是 JSON 物件（陣列、純文字）→ 沒有地方放鍵：報告附在後面，不動原本的內容。
    public static func reportingWrittenWithLegacyCopy(_ text: String, _ written: [LegacyCopyLeft], isError: Bool,
                                                      limit: Int? = writtenWithLegacyCopyLimit) -> String {
        guard !written.isEmpty else { return text }
        if isError {
            return (LegacyCopyLeft.reportLines(written, limit: limit) + ["", text]).joined(separator: "\n")   // display-safe-exempt: reportLines：LegacyCopyLeft.message 已消毒；text 是呼叫端已組好的回應
        }
        if var obj = (try? JSONSerialization.jsonObject(with: Data(text.utf8))) as? [String: Any] {
            // 已帶這個鍵的回應（`akashic_import_zotero` 的 payload 自己帶、可能已截）：併進去，總數是它的總數加上這次的筆數
            let newlyNotApplied = written.filter(\.laterWriteRefused).count
            let merged: (rows: [Any], total: Int, notApplied: Int)? = switch obj[writtenWithLegacyCopyKey] {
            case nil: (legacyCopyRows(written), written.count, newlyNotApplied)
            case let existing as [Any]:
                ((existing + legacyCopyRows(written)).sorted { Self.rowSortKey($0) < Self.rowSortKey($1) },
                 (obj[writtenWithLegacyCopyTotalKey] as? Int ?? existing.count) + written.count,
                 // 已截的那份自己帶完整的數（它的列可能被截掉）；沒帶就數它還看得到的列
                 (obj[writtenWithLegacyCopyNotAppliedKey] as? Int ?? existing.filter { Self.rowIsNotApplied($0) }.count) + newlyNotApplied)
            default: nil   // 同名鍵卻不是陣列：不是這個函式寫的形狀，不覆寫它——落到下一格附文字
            }
            if let merged {
                obj.merge(legacyCopyFields(rows: merged.rows, total: merged.total, notApplied: merged.notApplied, limit: limit)) { _, new in new }
                if let data = try? JSONSerialization.data(withJSONObject: obj, options: [.prettyPrinted, .sortedKeys]) {
                    return UnsafeToEmitScalar.escapingUnsafeScalars(inSerializedJSON: String(decoding: data, as: UTF8.self))
                }
            }
        }
        return ([text, ""] + LegacyCopyLeft.reportLines(written, limit: limit)).joined(separator: "\n")   // display-safe-exempt: reportLines：LegacyCopyLeft.message 已消毒；text 是呼叫端已組好的回應
    }

    /// 一列是否標了「之後的寫入沒有套用」（`legacyCopyRows` 加的 `laterWriteNotApplied`）。
    private static func rowIsNotApplied(_ row: Any) -> Bool {
        (row as? [String: Any])?["laterWriteNotApplied"] != nil
    }

    /// 併進既有陣列時的排序鍵：與 `legacyCopyRows` 同一個 (kind, key)。
    private static func rowSortKey(_ row: Any) -> String {
        let d = row as? [String: Any]
        return "\(d?["kind"] as? String ?? "")\u{0}\(d?["key"] as? String ?? "")"   // display-safe-exempt: 只用來排序，不輸出
    }
}
