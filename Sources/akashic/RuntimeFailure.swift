import AkashicCore

/// 命令列解析無誤、失敗來自 argv 以外的東西（#549）。
///
/// `ValidationError` 由 ArgumentParser 渲染成 **exit 64（`EX_USAGE`）＋ top-level usage**——那是「命令列打錯了」的語意。
/// 缺 store 佈局、registry 裡沒有那個 key、輸入檔形狀不對，命令列都是對的；印 usage 會把讀者導向「子命令名稱打錯了」，
/// 下游自動化也分不出兩類失敗。本型別走頂層的一般錯誤路徑：`Error: <訊息>`、exit 1、不印 usage。
///
/// ## 判準（一個可獨立驗證的性質，不是案例清單）
///
/// **只看解析後的 argv 就判得出來 → `ValidationError`；需要讀 argv 以外的任何東西 → `RuntimeFailure`。**
/// 「argv 以外」包括檔案系統、檔案註冊表與 config、store 的內容、服務層的回應、輸入檔的內容。
/// 判斷一個拋錯點時只問一句：拿掉所有 I/O，這個條件還判得出來嗎？判得出來就是用法錯誤。
///
/// **四個邊界**（#549 R1 verify；寫在判準旁邊，不讓讀者從性質自行類推）：
///
/// 1. **stdin 是 argv 以外。** `update-person` 從 stdin 讀到的 JSON 不對 → `RuntimeFailure`；同一個 JSON 經 `--fields`
///    給而格式不對 → `ValidationError`。與 `create-entry` 從 stdin／`--file` 讀到壞 JSON 同一類。
/// 2. **服務層做的輸入驗證會被包成 1。** `AkashicService` 丟的 `ServiceError` 在 CLI 的包裝站點一律成 `RuntimeFailure`，
///    其中有些其實只看 argv（例如 key 格式）。本輪把 verify 實測到的那一格（`library add`／`remove` 的 key 格式）
///    搬到 CLI 的 `validate()`；其餘逐站搬移記在 #654，不在這裡寫成「服務錯誤都是執行期」。
/// 3. **exit 1 與「跑了、發現問題」共用。** `validate` 找到 fatal、`--apply` 部分失敗也回 1——exit code 只分得開「用法」
///    與「其他」，分不開「沒跑起來」與「跑了有問題」；後者要讀訊息。#549 要求的是不回 64，本輪不再細分。
/// 4. **只看 argv 的檢查放在 `validate()`**，早於開 store；放在 `run()` 裡而排在開 store 之後，store 缺佈局時會先報
///    執行期失敗。本輪搬了 verify 點名的三處（library key、`--tier`、`--fields`）；其餘散在 `run()` 裡的仍受順序影響。
///
/// 既有拋錯點的逐一歸類（2026-09-26）記在 `changelog/2026-09-26-cli-runtime-failure-exit-code.md`。
/// `Sources/akashic/Reference*` 三個檔屬另一個 session 的 #617 範圍，本輪沒有動，該檔也記著。
///
/// ## 消毒
///
/// 與 `ValidationError` 同一條紀律：payload 在**擲出端**逃脫一次（store 字串走 `displaySafeInvisible`，
/// 包裝的錯誤走 `displaySafeErrorText`），本型別只是載體。它自帶消毒，所以頂層不再逃一次（`displaySafe` 不冪等）。
/// 做成 enum 而不是 struct，是為了讓 `SanitizationBoundaryTests` 的「擲出站點逐 payload 比對」自動涵蓋它的每一個站點。
enum RuntimeFailure: Error, CustomStringConvertible, SanitizedErrorDescription {
    case state(String)

    var description: String {
        switch self {
        case .state(let message): return message   // display-safe-exempt: 擲出端已逃一次，本型別只是載體
        }
    }
}
