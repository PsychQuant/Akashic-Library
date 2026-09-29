import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// 移除面一族（`update-entry` 的三條移除腿、`update-venue --remove-reference`／`--edit-name-segment`）寫檔之後的共用兩件事。
///
/// ## index 重建失敗不得讓報告消失（b13f R1 verify 第 1 列）
///
/// 這一族的理由**只進報告**（使用者 2026-09-27 的裁決：不寫進 store、不改 store format），所以報告是理由與「實際移除了什麼」唯一的一份；
/// 寫檔之後 `LibraryIndex.rebuild()` 若擲錯（SQLite 鎖、磁碟滿、I/O），先前的形狀是整個呼叫回錯誤——移除已經落盤、報告卻沒有，
/// 而重試又會因為東西已經不在而被拒。
///
/// **選的做法：呼叫回成功、報告多兩個鍵，不是像 `import-zotero`（b11b R1）那樣 `throws` 並把整份報告塞進錯誤訊息。**
/// 兩者都不丟報告，差別在報告走哪條路：錯誤訊息要過各個面的錯誤出口，而那些出口**逐行截 400 字元**
/// （`displaySafeErrorMultiline` 的 `maxLineLength`）——JSON 一個鍵一行，一段 4,096 位元組的理由在錯誤路徑上會被截成四百字，
/// 正是這個報告存在的理由。`import-zotero` 的報告是計數與 citekey 清單，短，塞進錯誤訊息沒有這個問題；這一族的報告主體是自由文字的理由。
/// 成功路徑不經那些出口。代價是呼叫端得讀 `indexRebuilt`：CLI 的結束碼與 MCP 的 `isError` 都不會標出這件事——
/// 所以報告的 `indexNote` 把後果說出來（**CLI 的 `query` 不看 mtime、不會自己重建，要跑 `akashic doctor`**；MCP 的讀取面依 mtime 自動重建）。
/// index 是衍生物、canonical 的 YAML 已經寫好，這一步失敗不改變移除的結果。
///
/// **只在失敗時多出這三個鍵**（同 `ambiguousSourceClaims` 的「只在非空時出現」）：成功路徑的 payload 不變。
extension AkashicService {

    /// 寫檔之後重建 index；失敗回傳那個錯誤（不擲出），由呼叫端併進報告。
    func rebuildIndexCapturingFailure() -> Error? {
        do {
            try LibraryIndex(store: store).rebuild()
            return nil
        } catch {
            return error
        }
    }

    /// 把 index 重建失敗併進報告（`indexRebuilt: false`、`indexRebuildError`、`indexNote`）。`written` 是「已經寫進磁碟的是什麼、為什麼先存報告」
    /// 那一句——移除腿用預設；名字段編輯（#675）改的是「改寫」，重試被拒的理由也不同。
    static func noteIndexRebuildFailure(_ error: Error, in payload: inout [String: Any],
                                        written: String = "移除已經寫入磁碟——理由與被移除的內容都在這份報告裡，重試會因為東西已經不在而被拒，先把報告存下來。") {
        payload["indexRebuilt"] = false   // display-safe-exempt: Bool
        payload["indexRebuildError"] = displaySafeError(error, max: 512)
        payload["indexNote"] = written
            + "衍生的 index 沒有重建成功：MCP 的讀取面依 mtime 自動重建；CLI 的 query 不看 mtime、不會自己重建，要跑 akashic doctor"
    }
}
