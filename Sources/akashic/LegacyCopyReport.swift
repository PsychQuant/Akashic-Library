import Foundation
import AkashicStoreIO
import AkashicMCPKit

/// #705：寫進 `entities/`、#631 搬移後的 legacy 拷貝沒刪掉的那一筆——CLI 面的兩個出口。
///
/// 使用者 2026-09-30 裁決 (a)：記在成功那一側的 `writtenWithLegacyCopy`，不算失敗、不進任何失敗清單。
///
/// - **CLI 進入點**（`AkashicCLI.main`）把每一個命令包在收集範圍裡，命令結束後（成功或擲錯）用 `printLines` 印在輸出末尾、
///   錯誤訊息之前。印人可讀文字的寫入命令因此都涵蓋到，新命令不必記得接。
/// - **直接印 service JSON 的寫入命令**（`update-person`、`update-entry`、`tag`、`link`、`set-status`、`resolve-venues`、
///   `enrich --json`）**必須**用 `payload`：鍵進那份 JSON，stdout 仍是一份合法 JSON——不接的話，進入點會把人可讀報告接在 JSON 後面
///   （#705 R2 verify 第 4 列）。`LegacyCopyPayloadScanTests` 掃 `Sources/akashic/`：寫入命令直接印 service JSON 而沒經這裡的，除了
///   具名的豁免（寫不到既有 work／person 的命令）都紅。擲錯時沒有 JSON 可放——收到的轉交進入點的範圍（沒有外層範圍時附在擲出的錯誤上，
///   `LegacyCopyLedger.get`；#705 R1 verify 第 17／36 列），進入點看到這個命令的 stdout 是 JSON，就改印一份只有這三個鍵的 JSON（`printTrailer`）。
///
/// **失敗時 stderr 的第一行也說寫了**（#705 R2 verify 第 16／19 列）：報告在 stdout、錯誤在 stderr，只擷取 stderr 與結束碼的呼叫端
/// （cron、CI）先前只讀到 UNIQUE 失敗，不知道那幾筆其實寫了、重跑會被 #631 拒絕。
///
/// CLI 一個 process 跑一個命令，所以兩個狀態放在 static：這一趟的 stdout 是不是 service JSON、stdout 上已經報了幾筆。
enum LegacyCopyReport {
    /// `payload` 進入時設下：這個命令的 stdout 是一份 service JSON。
    private(set) static var stdoutIsJSON = false
    /// 這一趟在 stdout 上已經報告的筆數（JSON 的鍵、人可讀報告，含 `import-zotero` 自己印的那一段）。
    private(set) static var reportedOnStdout = 0

    static func payload(_ body: () throws -> String) throws -> String {
        stdoutIsJSON = true
        let (result, written) = LegacyCopyLedger.collecting(body)
        let out = AkashicService.reportingWrittenWithLegacyCopy(try LegacyCopyLedger.get(result, written: written), written,
                                                                isError: false, limit: nil)   // CLI 全列（MCP 才截）
        reportedOnStdout += written.count
        return out
    }

    /// 兩面共用的人可讀報告（`LegacyCopyLeft.reportLines`）；沒有就不印。CLI 全列。
    static func printLines(_ items: [LegacyCopyLeft]) {
        for line in LegacyCopyLeft.reportLines(items) { print(line) }   // display-safe-exempt: line：reportLines 由已消毒的 message 組成
        reportedOnStdout += items.count
    }

    /// 進入點的尾段：命令失敗而它的 stdout 是 service JSON 時，印一份只有 `writtenWithLegacyCopy` 三個鍵的 JSON（stdout 仍是一份 JSON——
    /// 命令自己擲錯、沒印出它的 JSON）；其餘印人可讀報告。
    static func printTrailer(_ items: [LegacyCopyLeft], commandFailed: Bool) {
        guard !items.isEmpty else { return }
        guard commandFailed, stdoutIsJSON else { return printLines(items) }
        print(AkashicService.reportingWrittenWithLegacyCopy("{}", items, isError: false, limit: nil))   // display-safe-exempt: 序列化器逐項消毒（reportingWrittenWithLegacyCopy 走 escapingUnsafeScalars）
        reportedOnStdout += items.count
    }

    /// 命令失敗時 stderr 的內容（`errorText` 是已消毒的錯誤訊息，可以是空的）。stdout 上已經報告過寫了的筆數時，第一行說這件事（只含筆數，
    /// 沒有 store 字串）；沒有報告過就原樣回傳。
    ///
    /// **錯誤訊息是空的也要說**（#705 R3 verify）：`throw ExitCode(1)`（import-zotero 的 `writeFailed`／未記下的 DOI 提名、`enrich-from-zotero` 等）
    /// 沒有訊息，先前 `!safe.isEmpty` 的守衛讓這一格 stderr 整個是空的——只擷取 stderr 與結束碼的呼叫端（cron、CI）讀不到「不要重跑」。
    static func stderrText(errorText: String) -> String {
        guard reportedOnStdout > 0 else { return errorText }
        // 不以 `writtenWithLegacyCopy` 開頭：那是 stdout 報告的標題，合併兩個串流讀的呼叫端找它時不該先找到這一行
        let lead = "已寫入 \(reportedOnStdout) 筆、搬移後的 legacy 拷貝沒刪掉（writtenWithLegacyCopy，清單在 stdout）"   // display-safe-exempt: Int
            + "——那幾筆不是寫入失敗，不要重跑（兩份並存時 #631 會拒絕）；刪掉 legacy 那份即可。"
        return errorText.isEmpty
            ? lead + "這次以非零結束碼結束、沒有錯誤訊息——原因見 stdout 上的報告。"
            : lead + "以下是這次失敗的原因：\n" + errorText
    }
}
