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
/// 2. **服務層做的輸入驗證**（#549 R1 搬了 `library add`／`remove` 的 key 格式；#654 逐站盤點）。只看參數的檢查已抽成
///    服務（與 store 層 `recordDivergence`）的 static 函式：服務方法在讀 store 之前呼叫，CLI 的 `validate()` 經 `argvCheck`
///    呼叫同一個函式——回 64、早於開 store，同一件事只有一份描述。逐站清單記在
///    `changelog/2026-09-28-empty-digest-and-service-argv.md`。**服務丟的錯誤仍是 1 的，是下列要讀 argv 以外才判得出來的**
///    （封閉列舉，不得依性質相似類推——新的站點要逐一判、補進這裡）：
///    - `resolve-people`／`resolve-venues` 的 `--apply`／`--reject` id：要比對這次的候選列表；
///    - `resolve-organizations` 每一筆 `--undecided`／`--judge` id：`@orgKey=` 要在這次列表的 id 上切（只看參數的——一次的上限、
///      rests-on 的 digest、連一個 `@<orgKey>=` 位置都沒有的 id——已搬）；
///    - store 狀態：format 閘（`store.yaml`）、記錄是否存在、citekey 是否唯一、venue 有沒有要移除的 ISSN、作者位是否已歸戶；
///    - 合併到既有記錄後才判得出來的：`update-person` 的 `validate()` error（例如 authorized ⊆ names）與寫入閘對合併後記錄的驗證
///      （references 指名的欄位要存在、digest 的形狀——後者只看參數，但它住在寫入閘的 canary 裡，不在 `applyUpdateFields`）；
///    - 輸入檔與 stdin 的內容：`create-entry`、`enrich` 的提案檔、`update-person` 從 stdin 讀的 JSON、`store-source` 讀不到或 0 byte 的檔。
/// 3. **exit 1 與「跑了、發現問題」共用。** `validate` 找到 fatal、`--apply` 部分失敗也回 1——exit code 只分得開「用法」
///    與「其他」，分不開「沒跑起來」與「跑了有問題」；後者要讀訊息。#549 要求的是不回 64，本輪不再細分。
/// 4. **只看 argv 的檢查放在 `validate()`**，早於開 store；放在 `run()` 裡而排在開 store 之後，store 缺佈局時會先報
///    執行期失敗。#549 R1 搬了 verify 點名的三處（library key、`--tier`、`--fields`）；#654 起服務層那一族也在 `validate()`
///    （見第 2 點），`link` 的「至少給一個」與 `person` 的 `--in-library` 同批搬了。**仍在 `run()` 裡、排在開 store 之後的**
///    （2026-09-28 盤點，不含 `Reference*`）只剩 `query` 的關係旗標組合（留著：`CLIExitCodeTests` 靠它量 `run()` 期間
///    `ValidationError` 的子命令 usage）。`bootstrap-people` 的 `--json` 與 `--apply` 互斥、`enrich-from-zotero` 的空
///    `--citekeys` 同批搬進 `validate()`——先前排在目標確認閘之後，而閘要解析 registry、失敗是 1。`resolve-*` 的腿組合檢查
///    在 `run()` 裡、早於目標確認閘與開 store（`resolve-people` 先前把閘排在組合檢查前面，#654 對調）。
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
