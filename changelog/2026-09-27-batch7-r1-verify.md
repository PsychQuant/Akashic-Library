# 2026-09-27 #543／#585／#573／#653 的 R1 verify 修正

R1 verify 有 6 席，回報 40 條，其中 1 HIGH、12 MEDIUM。本輪修正如下：

- **HIGH（#573）**：可回溯性閘原本用 `id.uuidString` 拼出大寫路徑，而共用檢查對不存在的路徑是略過，等於沒有檢查（fail-open）。載入時接受小寫 UUID 檔名，這種 venue 檔即使已 commit，也永遠被報成「未追蹤」。現在路徑取自 `entities/` 裡的實際檔名，找不到檔就整批拒絕。
  - 測試：`testRecoverabilityGateUsesTheFileNameOnDisk`。負控：改回由 id 拼路徑，測試變紅。
- **#573／#585**：git 子程序改成只讀 repo 自己的設定（`GIT_CONFIG_GLOBAL=/dev/null`、`GIT_CONFIG_NOSYSTEM=1`，並加 `-c core.fsmonitor=false`），同時剝除 xcrun 的選路變數（`DEVELOPER_DIR`、`TOOLCHAINS`、`SDKROOT`）。DA 實測過一個攻擊：用 `HOME` 下的 clean filter 讓 dirty 的檔看起來是 clean，閘因此放行，並刪掉一筆只存在工作樹的判定。
  - 測試：`testGlobalGitconfigCannotMakeADirtyFileLookClean`。它會先確認這份 gitconfig 真的騙得過只剝 `GIT_*` 的 git，再斷言閘沒被騙。負控變紅。
- **#573**：`retiredLimit` 為負數時，在任何寫入之前就拒絕。先前會先寫完，組 payload 時才 crash。
- **#543**：搬進 `addendum` 的 DOI 會先做 TeX 逃脫；既有 addendum 已以句末標點結尾時，不再多補一個句點。csl 的 note 不接在來源的 note 後面，因為這個匯出本來就不輸出來源的 note。負控兩條都紅。
- **#543**：export-tables 只留第一個 DOI，而那段零實例裁決寫的觸發條件已成立（202 筆），另開 #657。
- **#653／#650**：
  - `rename-person` 加進 `destructiveCommands`。
  - 沒有寫入旗標也沒有乾跑的命令，拒絕訊息改成說明它沒有預覽模式。
  - `--yes` 的 help 補上新閘的命令。
  - migrate 族乾跑時印的「實際執行」提示改成帶 `--library`。
  - `akashic-merge-twins` skill 的合併步驟補上 `--library`。
- **#653 的措辭**：先前寫「不閘的都可逆」，這句不成立——`--drop-author` 與 import-zotero 都不可逆。這兩個閘不閘、以及稽核怎麼抓到新的未閘寫入命令，一併記在 #658，交給使用者裁決。
- `GitSpawnHygieneTests` 的封閉清單改成真的封閉：會 spawn git 卻沒登記的檔也會紅。另外補登記兩個檔。
