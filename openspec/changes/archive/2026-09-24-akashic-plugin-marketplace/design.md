## Context

`akashic-mcp` 目前由外部 marketplace psychquant-claude-plugins 以 git-subdir（`path: plugin`）列出；本 repo 沒有 marketplace manifest。discovery 路線的五個 skill（#617、#620–#623）要住進一個新的 plugin `akashic-discovery`，它必須和 `akashic-mcp` 同 repo、同 commit 出貨。

守衛現況（2026-09-24 量測）：受保護清單的五條 glob 全以 `plugin/` 為根；trigger-coverage 的檢查對象就是受保護清單；rule-coverage 以腳本所在位置推出唯一的 plugin 根；跑守衛的 CI workflow 只在 `plugin/**` 等路徑觸發。任何放在 `plugin/` 以外的 plugin，它的測試被刪或沒接線，**沒有一道守衛會出聲**。

上游決策：#617 diagnose（marketplace 名稱、佈局、搬遷、symlink）、#625 diagnose（移除 plugin 版本 tag、Spectra 路徑）、#625 spectra-discuss（A1–A5，本文件 Decisions 前五節）。

## Goals / Non-Goals

**Goals:**

- repo 成為 marketplace `akashic`，列出 `akashic-mcp` 與 `akashic-discovery`，官方 validate 通過。
- 每一道「看目錄」的守衛都涵蓋每一個 plugin 根，而且由負對照證明看得見。
- `akashic-mcp` 的既有安裝能照文件遷移，過程中不出現「兩邊都裝不到」的空窗。

**Non-Goals:**

- 不搬動 `plugin/`：約 224 處寫死 `plugin/` 的路徑維持原樣（#617 定案）。
- 不在 `akashic-discovery` 放任何 skill：skill 由 #617、#620–#623 各自加入。
- 不宣告版本範圍、不打 `<plugin>--v<version>` tag（#625 使用者確認移除 Expected 6）。
- 不修改 harness-devtools：`plugin-update` 認得 `akashic` 由 PsychQuant/che-plugin-devtools#27 處理。
- 不在 CI 安裝 claude CLI（見「claude plugin validate 只在 pre-push 執行」）。
- 不把 rule-coverage 改寫成 Swift：本 change 只改它的根目錄來源。

## Decisions

### 以檔案系統為 plugin 根目錄的權威來源，marketplace manifest 作集合核對

plugin 根＝`plugin` ＋ `plugins/` 底下含 `.claude-plugin/plugin.json` 的直接子目錄，由單一函式計算。另設守衛 `marketplace-consistency` 核對它與 manifest 的 `source` 集合相等（外加名稱一致、依賴可解析、`plugins/` 下沒有無 manifest 的雜目錄）。

替代方案：(a) 以 manifest 為唯一來源——已建立但未列入的 plugin 會得到零涵蓋，而且是安靜的；(b) 只看檔案系統、不核對——拼錯的 `source` 或忘了列的 plugin 會一路出貨到使用者安裝時才壞。兩者各有一個安靜方向，組合起來兩個方向都會變紅。

### bash 端經由 akashic-guards plugin-roots 取得清單

新增子命令 `plugin-roots` 印出根目錄清單（守衛檔必須依子命令名的 PascalCase 命名：`plugin-roots` → `PluginRoots.swift`、`marketplace-consistency` → `MarketplaceConsistency.swift`、`plugin-roots-mutations` → `PluginRootsMutations.swift`；受保護清單以這個對應找出 Swift 守衛，檔名不符的守衛不受保護，被人從入口拿掉也不會有人發現）；`rule-coverage.sh` 接受一個根目錄參數（預設 `plugin`，手動用法不變）；守衛入口以子命令輸出逐根呼叫。守衛入口在跑任何守衛前本來就要求 `akashic-guards` binary 存在，不增加新前提。

替代方案：在 bash 端另存一份清單——兩份會分岔的規格，正是守衛入口檔頭記錄的 #432 形狀。

### 0 個 skill 的 plugin 視為 vacuous 通過

`skills/` 不存在或沒有子目錄時，rule-coverage 印出「0 個 skill（vacuous）」並通過。

替代方案：維持現行 `exit 2`——#625 就無法先於 #617 上線，約定好的施工順序會倒過來。印出來而不是安靜通過，讀的人才分得出「沒有 skill」和「沒檢查」。

### claude plugin validate 只在 pre-push 執行，CI 印出略過

守衛入口偵測 `claude` 是否存在：有就跑 `claude plugin validate --json .`，出現任何 error、或出現允許清單以外的任何 warning 即失敗；沒有就印一行略過原因。

**允許清單（封閉列舉，只有一項，不得依性質相似類推）**：`plugin/.claude-plugin/plugin.json` 的 `binary_version` 未知欄位警告。這個欄位由 MCP wrapper 用來選擇 server binary 的 release（#275），harness-devtools 也讀它，刻意保留。實作時量到：`--strict` 會因為它而永遠失敗（2026-09-24，Claude Code 2.1.281），所以不能直接用 `--strict`；改用 `--json` 並逐條比對，保留「任何新的未知欄位都會失敗」這個 strict 的用意。CI 必須擋的結構不變量由 `marketplace-consistency` 負責（它不依賴 CLI）。

替代方案：CI 安裝 claude CLI——守衛本身多了網路依賴與未釘版本的漂移；完全不跑 validate——schema 錯誤要到使用者安裝時才浮現。

### rules 目錄整個 symlink

`plugins/akashic-discovery/rules` 指向 `../../plugin/rules`。

替代方案：逐檔 symlink——日後新增的通用規則不會傳到 discovery，而且是安靜的。整個目錄 symlink 的反方向（日後出現 akashic-mcp 專屬規則）會讓 discovery 的 rule-coverage 變紅，是有聲的。受保護清單以真實路徑計數，symlink 不造成重複成員。

### 依賴寫純字串、不打 plugin 版本 tag

`akashic-discovery` 的 `dependencies` 為 `["akashic-mcp"]`。官方文件：純字串依賴取 marketplace 目前提供的版本，不讀 tag；兩個 plugin 同 commit 出貨，版本範圍提供不了額外保護。

替代方案：宣告範圍並打 `akashic-mcp--v<version>` tag——與 binary release tag `akashic-mcp-v<binary_version>`（wrapper 以此下載 binary）只差一個連字號、語意不同，手打錯一個會安靜地指到另一個系統。日後真需要範圍時用 `claude plugin tag --push` 產生。

### akashic-mcp 留在 plugin/，新 plugin 放 plugins/

`akashic-mcp` 的 source 為 `./plugin`；其他 plugin 一律 `plugins/<name>/`，目錄名等於 manifest `name`（由 `marketplace-consistency` 檢查）。沿用 #617 定案。

### 跨 repo 發布順序：先上架、驗證可安裝、再移除外部條目

順序固定為：Akashic-Library 推上 manifest → 從它安裝 `akashic-mcp@akashic` 成功且 MCP 工具可呼叫 → psychquant 移除條目、加 `renames: {"akashic-mcp": null}`、刪除遺留空目錄 → 遷移使用者本機安裝。反過來會出現新使用者兩邊都裝不到的空窗。遺留的空目錄 `plugins/akashic-mcp/` 必須刪除：harness-devtools 以「`plugins/<name>` 目錄存在」判斷歸屬，它會讓工具對已移除的條目動手。

### marketplace 條目描述依 /plugin 回落行為決定

實測 `/plugin` 在 marketplace 條目缺 `description` 時是否回落到 plugin.json：會回落→條目不寫描述（單一來源）；不會→寫入，並讓 store-format parity 測試正式覆蓋它、刪除原本記為跨 repo 無法覆蓋的那一行。兩種結果都不能讓 parity 測試的註解停在「跨 repo」。

## Implementation Contract

**行為**：

- `claude plugin marketplace add PsychQuant/Akashic-Library` 之後，`akashic-mcp@akashic` 與 `akashic-discovery@akashic` 可安裝；安裝 discovery 會自動帶入 akashic-mcp。
- 在 `plugins/` 下新增 plugin 而沒列入 manifest、或列入 manifest 而目錄不存在，守衛入口失敗並指名。
- 在任一 plugin 根下新增沒接線的測試、刪除受保護測試、或讓 skill 漏引規則，守衛入口失敗並指名。

**介面**：

- `akashic-guards plugin-roots`：無參數；stdout 每行一個 repo 相對路徑、排序；exit 0。
- `akashic-guards marketplace-consistency`：無參數；一致時 exit 0；否則 exit 非 0，stderr 逐條列出 spec 中五類封閉列舉的違規與其路徑或名稱。
- `akashic-guards plugin-roots-mutations`：無參數；在暫存複本上逐一套用 spec 的突變表並執行對應守衛；全部被抓到時 exit 0，任一未被抓到時 exit 非 0 並指名該突變；原始樹不得被修改。需要先存在受保護檔的突變（刪除測試）先在複本中建立探針並接受進複本的 ratchet，再刪除。
- `plugin/tests/rule-coverage.sh [root]`：root 預設 `plugin`；0 個 skill 印 vacuous 並 exit 0。
- 守衛入口：以 `plugin-roots` 逐根跑 rule-coverage；執行 `marketplace-consistency` 與 `plugin-roots-mutations`；依 `claude` 是否存在執行（`--json` 加允許清單比對）或略過官方 validate。

**失敗模式**：`marketplace-consistency` 讀不到 manifest 或 JSON 無法解析時 exit 非 0 並說明，不視為「沒有 plugin」。`plugin-roots` 在 `plugins/` 不存在時只印 `plugin`（這是正常狀態，不是錯誤）。官方 validate 略過時必須印出，不得靜默。

**驗收**：

- `bash .githooks/run-guards.sh` 在本機全綠，且輸出中可見 discovery 根的 rule-coverage vacuous 行與 validate 通過行。
- `akashic-guards plugin-roots-mutations` exit 0，輸出六個突變各自被對應守衛抓到。
- `claude plugin validate --json .`：`errors` 為空，`warnings` 恰為允許清單那一條。
- 從推上去的 marketplace 安裝 `akashic-mcp@akashic` 後，`claude plugin list --json` 對兩個 plugin 都沒有 `errors` 欄位，且至少一個 akashic MCP 工具實際呼叫成功。
- psychquant 的 manifest 不再列 `akashic-mcp`，且含 `renames` 將其對應到 `null`；其 `plugins/akashic-mcp/` 目錄不存在。

**範圍**：包含本 repo 的 manifest、discovery 骨架、守衛與其負對照、CI 觸發、README 與量測斷言、parity 測試、psychquant 條目移除、使用者本機安裝遷移。不包含任何 discovery skill、harness-devtools 修改、plugin 版本 tag、`plugin/` 搬遷。

## Risks / Trade-offs

- [globFiles 對 symlink 目錄的走訪行為未量] → 實作前先在 CI 同款 runner 上實測；若會跟隨 symlink，受保護清單對 `rules` 以真實路徑去重，並由 spec 的「不重複計數」情境把關。
- [`marketplace add` 會 clone 整個 repo，可能連同 3 個 submodule] → 實作時量測實際 clone 內容與大小，寫進 README 遷移段；若 submodule 被遞迴抓取且成本明顯，另開 issue 評估，不在本 change 內改 repo 結構。
- [使用者本機遷移後 binary 需重新下載] → 遷移後以實際呼叫 MCP 工具驗收，不只看 `plugin list`。
- [另一個 session 共用同一 checkout] → 只 add 本 change 觸及的檔案，不用全量 add。
- [守衛新增檔會碰 protected-ratchet] → 新增的受保護成員以 `--accept` 明示接受，並在 commit 訊息說明。

## Migration Plan

1. 本 repo：守衛與負對照先行（RED→GREEN），再加 manifest 與 discovery 骨架，全部守衛綠燈後 push。
2. 驗證：`claude plugin marketplace add PsychQuant/Akashic-Library` → `claude plugin install akashic-mcp@akashic` → 呼叫一個 MCP 工具成功。
3. 外部 marketplace：移除 `akashic-mcp` 條目、加 `renames`、刪除遺留空目錄，push。
4. 使用者本機：解除安裝舊 id → 安裝 `akashic-mcp@akashic` → 移除啟用設定中的舊 id → 重啟後確認工具可用。

回滾：步驟 3 之前任何失敗，外部條目原樣保留、使用者安裝不動，只需 revert 本 repo 的 commit。步驟 3 之後回滾：外部 manifest revert（恢復條目、移除 `renames`）即可恢復舊安裝路徑。

## Open Questions

- ~~globFiles 是否跟隨 symlink 目錄~~ → 已量（tasks 1.1）：遞迴走訪（`enumerator`）不進入 symlink 目錄；只有最後一段萬用字元時（`contentsOfDirectory`）會穿過。逐根展開 `<root>/rules/*.md` 因此會重複計數，受保護清單改為先還原真實路徑再去重。
- `marketplace add` 是否遞迴 clone submodule、實際大小多少（遷移段實測）。
- ~~`/plugin` 在 marketplace 條目缺 `description` 時是否回落 plugin.json~~ → 已量（tasks 5.1，探針 marketplace 兩條目對照，`claude plugin list --available --json`）：沒寫時回落到 plugin.json；有寫時條目覆蓋 plugin.json。採「條目不寫描述」，並由 store-format parity 測試檢查條目不帶 description。
