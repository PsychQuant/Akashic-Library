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
