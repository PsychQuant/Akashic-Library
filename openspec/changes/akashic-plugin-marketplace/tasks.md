## 1. 量測前提

- [x] 1.1 實測守衛的 glob 走訪是否跟隨 symlink 目錄：在暫存樹建立 `plugins/x/rules` 指向 `../../plugin/rules`，以 `akashic-guards` 的 glob 函式計數 `plugins/*/rules/*.md` 的成員數，決定 4.3 的去重做法。驗證：量測指令與輸出貼到 #625 comment，並回填 design.md 的 Open Questions 第一項。

## 2. marketplace 與 discovery 骨架

- [x] 2.1 [P] Repository-root marketplace manifest：新增 `.claude-plugin/marketplace.json`，`name` 為 `akashic`、設定 `owner`，列出 `akashic-mcp`（source `./plugin`）與 `akashic-discovery`（source `./plugins/akashic-discovery`），遵循「akashic-mcp 留在 plugin/，新 plugin 放 plugins/」。驗證：`claude plugin validate --json .` 的 `errors` 為空、`warnings` 恰為允許清單那一條（akashic-mcp 的 `binary_version`）。
- [x] 2.2 [P] 依 Plugin directory layout 建立 discovery 骨架：manifest 位於 `plugins/akashic-discovery/.claude-plugin/plugin.json`、`name` 等於目錄名；Discovery plugin depends on akashic-mcp without a version range（`dependencies` 為純字串 `akashic-mcp`，依「依賴寫純字串、不打 plugin 版本 tag」）；Shared rules through a directory symlink（依「rules 目錄整個 symlink」建立 `rules` 指向 `../../plugin/rules`）。驗證：`claude plugin validate --strict plugins/akashic-discovery` exit 0；`git tag -l '*--v*'` 無輸出；`git ls-files -s plugins/akashic-discovery/rules` 的 mode 為 120000；`plugins/akashic-discovery/rules/assertions-must-be-measured.md` 可讀。

## 3. 負對照先行（RED）

- [x] 3.1 Mutation proof that new roots are seen（RED 階段）：新增子命令 `akashic-guards plugin-roots-mutations`，在暫存複本逐一套用 spec 突變表六列（需要既有受保護檔的列先在複本建立探針並接受進複本的 ratchet），另加 marketplace-consistency 範例表其餘三個失敗列；原始樹不得被修改。驗證：在現行守衛上執行時 exit 非 0，輸出逐條列出未被抓到的突變名稱（證明負對照有鑑別力），並以 `git status` 確認原始樹無變動。

## 4. 守衛實作（GREEN）

- [x] 4.1 Single source of plugin roots，依「以檔案系統為 plugin 根目錄的權威來源，marketplace manifest 作集合核對」：新增 `pluginRoots()` 與子命令 `akashic-guards plugin-roots`，輸出排序後的 repo 相對路徑、每行一個。驗證：在含 `plugins/scratch/`（無 manifest）的暫存樹上輸出恰為 `plugin` 與 `plugins/akashic-discovery`；在現行樹上輸出同樣兩行。
- [x] 4.2 Filesystem and marketplace manifest agree：新增子命令 `akashic-guards marketplace-consistency`，實作 spec 的五類封閉列舉，逐條指名違規；manifest 讀不到或 JSON 無法解析時 exit 非 0 並說明。驗證：現行樹 exit 0；3.1 中所有 consistency 突變列改為被抓到。
- [x] 4.3 Protected inventory covers every plugin root：受保護清單的測試腳本與規則 pattern 改由 `pluginRoots()` 對每個根展開，經 `rules` symlink 才到達的檔案依 1.1 的結果以真實路徑去重。驗證：現行樹 `akashic-guards protected-ratchet` 的差異恰為本 change 新增的 3 支 Swift 守衛與 2 個 manifest（`.claude-plugin/marketplace.json`、discovery 的 `plugin.json`），且不含任何 `plugins/*/rules/` 路徑（由 `plugin-roots-mutations` 的結構檢查釘住）；3.1 的「刪除受保護測試」「未接線測試」兩列改為被抓到。
- [x] 4.4 Rule coverage runs per plugin root，依「bash 端經由 akashic-guards plugin-roots 取得清單」與「0 個 skill 的 plugin 視為 vacuous 通過」：`plugin/tests/rule-coverage.sh` 接受選填的根目錄參數（預設 `plugin`），守衛入口以 `akashic-guards plugin-roots` 的輸出逐根呼叫。驗證：`bash plugin/tests/rule-coverage.sh plugins/akashic-discovery` 印出 0 個 skill（vacuous）並 exit 0；不帶參數的輸出與變更前逐字相同；3.1 的「skill 未引用規則」列改為被抓到。
- [x] 4.5 [P] CI triggers include plugin roots and the manifest：跑守衛的 workflow（`.github/workflows/census-parity.yml`）觸發路徑加入 `plugins/**` 與 `.claude-plugin/**`；Swift build workflow（`.github/workflows/ci.yml`）的 paths-ignore 加入同樣兩條。驗證：`akashic-guards trigger-coverage` 在現行樹通過；3.1 的「移除 plugins/** 觸發路徑」列改為被抓到。
- [x] 4.6 Official validation where the CLI exists，依「claude plugin validate 只在 pre-push 執行，CI 印出略過」：守衛入口偵測 `claude`，存在時執行 `claude plugin validate --json .`，任何 error 或允許清單以外的 warning 即失敗，不存在時印出略過原因。驗證：本機執行 `bash .githooks/run-guards.sh` 可見 validate 通過行；在暫存複本的 manifest 加一個未知欄位時該步失敗並指名該欄位；以移除 `claude` 的 `PATH` 執行可見略過行。
- [x] 4.7 Mutation proof that new roots are seen（GREEN 階段）：把 `plugin-roots`、`marketplace-consistency`、`plugin-roots-mutations` 接進守衛入口，新增的受保護成員以 `akashic-guards protected-ratchet --accept` 明示接受。驗證：`akashic-guards plugin-roots-mutations` exit 0 且輸出每個突變都被對應守衛抓到；`bash .githooks/run-guards.sh` 全綠。

## 5. 文件與量測斷言

- [x] 5.1 依「marketplace 條目描述依 /plugin 回落行為決定」：以本機 marketplace 實測 marketplace 條目缺 `description` 時 Claude Code 顯示的描述來源，依結果增刪條目描述，並把 `plugin/tests/plugin-store-format-parity.py` 中「跨 repo、無法覆蓋」的說明改成實際覆蓋或單一來源的說明。驗證：parity 測試通過，且該檔不再把 repo 內的 marketplace manifest 描述為無法覆蓋。

## 6. 發布與遷移

- [ ] 6.1 依「跨 repo 發布順序：先上架、驗證可安裝、再移除外部條目」推上本 repo，接著遷移使用者本機安裝：解除安裝 `akashic-mcp@psychquant-claude-plugins` → `claude plugin marketplace add PsychQuant/Akashic-Library` → `claude plugin install akashic-mcp@akashic`；同時量測 clone 是否包含 submodule 與實際大小。驗證：`claude plugin list --json` 對 `akashic-mcp@akashic` 無 `errors` 欄位，且一個 akashic MCP 工具實際呼叫成功；任一步失敗即重新安裝舊 id 並停止，不進 6.3。
- [ ] 6.2 Install id migration（文件）：README 的安裝指令改為 `akashic-mcp@akashic`，並寫入遷移三步與 6.1 量到的 clone 內容；`plugin/rules/assertions-must-be-measured.md` 中「經由公開 marketplace 發布」一列依新 manifest 重新量測並改寫量法。驗證：`grep -rn 'akashic-mcp@psychquant' README.md plugin/` 無結果；`akashic-guards measured-claims-audit` 通過。
- [ ] 6.3 Install id migration（外部 marketplace）：psychquant-claude-plugins 的 manifest 移除 `akashic-mcp` 條目、加入 `renames` 將 `akashic-mcp` 對應到 `null`，刪除其遺留的空目錄 `plugins/akashic-mcp/`，push。驗證：該 manifest 不含 `akashic-mcp` 條目且 `renames` 內容正確；該目錄不存在；`claude plugin marketplace update psychquant-claude-plugins` 無錯誤。
- [ ] 6.4 收尾驗證：使用者層設定中不再啟用舊 id，重啟 Claude Code 後 akashic MCP 工具可用。驗證：使用者層 `settings.json` 無 `akashic-mcp@psychquant-claude-plugins`；重啟後呼叫一個 akashic MCP 工具成功；結果記到 #625。
