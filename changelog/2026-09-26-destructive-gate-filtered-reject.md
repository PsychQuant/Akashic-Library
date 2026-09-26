# 2026-09-26 #298 的目標確認閘：判準寫成「篩選式寫入」，`resolve-organizations --reject` 補進去（#580）

#580 問的是：`resolve-venues --apply` 為什麼不在 `DestructiveTargetGate.destructiveCommands` 裡？同族的 `resolve-people` 與 `resolve-organizations` 都在。

**診斷推翻了 issue 的前提。** `resolve-venues` 的 `--apply` 收的是 id 清單（`citekey:venueIndex:venueKey`），不是篩選式掃蕩。它與 `resolve-people` 的逐 id 腿（`--reject`／`--judge`／`--split-author`……）同形，而那些腿本來就不閘，理由與「只擋 CLI、不擋 MCP」相同：逐 id 顯式指名的呼叫端知道自己在寫什麼。所以這張表真正的判準是「篩選式寫入」，不是「會寫的命令」。

照這個判準重看，找到一個真正的漏洞：`resolve-organizations --reject` 是篩選式的，收窄後的候選全部寫 rejected verdict，卻只有 `--apply` 被閘住。未指名 `--library` 時，它會照寫到 registry 解析出來的 store。

- `resolve-organizations` 的閘條件改為 `apply || reject`，放在參數組合檢查之後。拒絕訊息寫出實際的旗標名（`--reject 拒絕執行`）。為此，`assertTargetNamed` 多了 `flag` 參數，預設 `--apply`。
- `DestructiveTargetGate` 的 doc 寫明判準，並列出不閘的一類（逐 id 顯式指名的寫入腿，封閉列舉）。另外記下 `rename-person` 無條件呼叫閘、`rename` 沒有閘。這個不一致另案 #650，本表不替它裁決。
- `mcp-cli-parity` 的 `--yes` 列更正兩句與程式不符的話：「`resolve-venues` 的 `--apply` 是篩選式掃蕩」與「`rename-person` 沒有這道閘」。
- 測試：
  - `testEveryFilteredRejectIsGated`：以源碼稽核確認帶布林 `--reject` 的命令，其閘條件含 `reject`；空掃描算失敗；
  - `testResolveVenuesApplyIsAnIDList`：釘住「不在表內」的前提；
  - `testOrgFilteredRejectRequiresANamedTarget`：用真 binary，未指名時拒絕且零寫入，帶 `--yes` 則放行。
  - 負控：把條件改回只看 `apply`，6 個失敗。

另外踩到一件事：doc 裡一度逐字寫出布林旗標的宣告，`testEveryApplyCommandIsEnumerated` 以字面比對，就把它當成一個命令，歸到上一個被掃到的 `create-entry`。現在 doc 不寫出那行宣告。

## R1 verify（5 HIGH），推翻了上面的判準

- **`authorize-names --apply` 是全庫布林掃蕩，卻沒有閘，稽核也看不到它。** 它的宣告寫出了 `: Bool`，而稽核只比對省略型別的寫法。現在它有閘、在表內，兩種寫法稽核都認得（`--reject` 同）。
- **「逐 id 就不閘」被表內既有的成員推翻。** `enrich` 與 `enrich-from-zotero` 都是逐 id 的，它們的 doc 早就寫著「閘的成本是一行，豁免需要的理由比加上它多」。閘防的是**寫錯 store**，而從錯的 store 列出來的 id，在錯的 store 上全部對得上。所以 `resolve-venues` 的全部寫入腿（apply、reject、repoint、demote、undecided）都進表，#580 Impact 講的 campaign 批次因此受到保護。issue 的 Expected（三個 `resolve-*` 對閘給同一個答案）現在以「進表」達成。
- **「不閘的只有一類」這個封閉列舉為假**：`fmt`、`migrate`、`migrate-provenance`、`import-*`、`create-entry`、`resolve-divergence`、`resolve-people` 的逐 id 腿都在表外，也都沒有閘。doc 改成照實描述，不寫封閉列舉；逐格裁決另開 #653。
- `--yes` 的 help 與 parity 表 `--yes` 列的理由欄同步改寫。舊理由「CLI 篩選式、MCP 逐 id」在逐 id 也閘之後不再成立，真正的差別是 MCP 的 store 是 session 狀態（#310）。
- 測試：
  - 用真 binary：`resolve-venues --demote` 與 `authorize-names --apply` 未指名 store 時拒絕，不帶寫入腿的列表不擋；
  - `testResolveVenuesGatesEveryWriteLeg`；
  - 負控：拿掉 authorize-names 或 resolve-venues 主路徑的閘，對應測試變紅。
- 未處理（LOW）：
  - `rename-person` 的拒絕訊息仍寫 `--apply` 與 dry-run，但它兩者都沒有（併入 #650）；
  - 消毒守衛放行表的 `^flag$` 是全域比對，沒有限定在閘的檔案。

## R2 verify（0 HIGH；devils-advocate 因週額度中斷而缺席）

- `resolve-organizations --undecided` 與剛閘住的 `resolve-venues --undecided` 同形，但它在閘之前就提早返回。現在也閘。
- 拒絕訊息原本一律寫「先跑一次不帶 X 的 dry-run」，對逐 id 的腿、`--reject`、`rename-person` 都是假話，因為它們沒有 dry-run。閘多了 `hasDryRun` 參數：沒有 dry-run 的改說「不帶寫入旗標執行只會列出候選」。`rename-person` 不再冒稱有 `--apply`。
- `resolve-people` 的逐 id 腿仍不閘。R2 指出，照新理由它們也該閘，但這一格留給 #653 逐格裁決。所以 issue Expected「三個 `resolve-*` 給同一個答案」只在**命令層**成立（三個都在表內）；腿層的一致性由 #653 承接。
- 列表測試補上 `status == 0` 的斷言。
