import Foundation
import AkashicStoreIO
import AkashicMCPKit

/// #705：寫進 `entities/`、#631 搬移後的 legacy 拷貝沒刪掉的那一筆——CLI 面的兩個出口。
///
/// 使用者 2026-09-30 裁決 (a)：記在成功那一側的 `writtenWithLegacyCopy`，不算失敗、不進任何失敗清單。
///
/// - **CLI 進入點**（`AkashicCLI.main`）把每一個命令包在收集範圍裡，命令結束後（成功或擲錯）用 `printLines` 印在輸出末尾、
///   錯誤訊息之前。所有寫入命令因此都涵蓋到，新命令不必記得接。
/// - **直接印 service JSON 的寫入命令**（`update-person`、`update-entry`、`tag`、`link`、`set-status`、`resolve-venues`、
///   `enrich --json`）用 `payload`：鍵進那份 JSON，stdout 仍是一份合法 JSON。擲錯時沒有 JSON 可放——收到的轉交進入點的範圍
///   （沒有外層範圍時附在擲出的錯誤上，`LegacyCopyLedger.get`；#705 R1 verify 第 17／36 列）。
enum LegacyCopyReport {
    static func payload(_ body: () throws -> String) throws -> String {
        let (result, written) = LegacyCopyLedger.collecting(body)
        return AkashicService.reportingWrittenWithLegacyCopy(try LegacyCopyLedger.get(result, written: written), written, isError: false)
    }

    /// 兩面共用的人可讀報告（`LegacyCopyLeft.reportLines`）；沒有就不印。
    static func printLines(_ items: [LegacyCopyLeft]) {
        for line in LegacyCopyLeft.reportLines(items) { print(line) }   // display-safe-exempt: line：reportLines 由已消毒的 message 組成
    }
}
