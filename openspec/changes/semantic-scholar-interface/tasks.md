## 1. Target 與測試接縫

- [x] 1.1 在 `Package.swift` 新增 library target `AkashicS2`（依賴 `AkashicCore`）與 test target `AkashicS2Tests`，讓 `akashic` 與 `akashic-mcp` 依賴它（design「S2 放在獨立 target，不進 AkashicService 也不進 AkashicCore」）。先寫測試（RED）再實作三個環境覆寫的解析，以 `environment:` 參數注入：`AKASHIC_S2_BASE_URL` 只收 loopback 的 http，`AKASHIC_S2_KEYCHAIN_SERVICE` 只收 `akashic-test-` 開頭，`AKASHIC_S2_STATE_DIR` 只收絕對路徑（Requirement「Test overrides are confined」；design「測試接縫：三個受限的覆寫」）。驗證：`swift build` 成功；`S2ClientTests` 中 `https://example.org`、`stat-sinica-compute`、相對路徑三種值都被拒絕，且拒絕發生在任何請求之前。

## 2. 金鑰與 host 規則

- [x] 2.1 [P] 先寫測試再實作 `S2KeyProvider`：以 Security framework（`kSecUseAuthenticationContext` 搭配 `interactionNotAllowed = true` 的 `LAContext`）非互動讀取 service `semantic-scholar`、account `default`，區分「項目不存在」「ACL 不允許非互動讀取」「其他 keychain 錯誤」三種結果；持有金鑰的型別描述一律回 `<redacted>`（Requirement「The key is read from the keychain without interaction and never exposed」；design「金鑰：程序內非互動讀取，ACL 所有 app 可讀，header 只送 S2 主機」）。非互動讀取的 API 寫法先查 Apple 官方文件再寫，不憑記憶。驗證：`S2ClientTests` 中，金鑰型別以字串插值與 `String(describing:)` 都得到 `<redacted>`；`akashic-test-<隨機>` 回「不存在」且不跳授權框。
- [x] 2.2 先寫測試再實作 `S2Client` 的 host 規則與錯誤分類：`x-api-key` 只附給 `https://api.semanticscholar.org`，loopback 覆寫一律不帶；404 回報找不到的識別碼，其他 4xx、5xx、連線失敗回報端點與狀態碼或錯誤類別，錯誤文字不含任何 header（Requirement「The key header is sent only to the Semantic Scholar host」與「Other failures are reported with their cause」）。驗證：`S2ClientTests` 以 `URLProtocol` stub 斷言 header 的有無、網址中不含金鑰、500 的錯誤文字不含 header、404 的訊息含 `DOI:10.0000/none`。

## 3. 節流與退避

- [x] 3.1 [P] 先寫測試再實作 `S2Throttle` 的時段預約：以 `flock` 鎖住狀態檔、讀寫 `nextAllowedAt`、解鎖後才等待；存的時間比現在晚超過 60 秒時視為過期並從現在重設；狀態檔預設在 `~/Library/Caches/akashic/s2-throttle`（Requirement「Requests are throttled machine-wide」；design「跨程序節流：預約時段，429 退避共用」）。驗證：`S2ThrottleTests` 跑 spec 的 Slot reservation 例子（A 在 0.00 送出，B 在 0.30 要求、於 1.00 以後送出）與過期重設。
- [x] 3.2 先寫測試再實作 429 退避與重試：把共用的 `nextAllowedAt` 推到「現在＋`Retry-After`」（秒數或 HTTP-date），沒有 header 時依序等 2、4、8 秒，同一請求最多重試 3 次，`Retry-After` 超過 60 秒直接判限流用盡（Requirement「Rate-limit responses back off for every caller」）。驗證：`S2ClientTests` 以 stub 跑 spec 的 Retry budget 四列；`S2ThrottleTests` 驗證 A 在 1.00 收到 `Retry-After: 3` 後，B 的下一個請求不早於 4.00。

## 4. 端點、分頁與輸出

- [x] 4.1 先寫測試再實作八個端點的請求組裝與分頁（`S2Endpoints`）：以 `10.` 開頭的裸 DOI 補上 `DOI:`、id 百分比編碼、batch 至多 500 個 id、references／citations／author-papers 翻頁直到結果或上限用盡，並依 design 的來源取得 `total`（Requirement「One interface serves both faces」）。驗證：`S2ClientTests` 以 stub 分 10 頁回 1,000 筆時得到 1,000 筆且 `total` 為 1000；`paper 10.1037/a0038889` 送出的路徑是 `DOI:10.1037/a0038889`。
- [x] 4.2 [P] 先寫測試再實作 `S2Output`：S2 回應中的每個字串遞迴經過 `displaySafe`；依傳入的位元組上限只保留完整筆數，回報 `returned`、`truncated`、`nextOffset`（Requirement「Text from Semantic Scholar is sanitized before display」與「The MCP tool bounds its result by bytes」）。驗證：`S2OutputTests` 中含 U+202E 的標題輸出後不含 U+202E；48 KiB 只放得下 120 筆時得 `returned: 120`、`truncated: true`、`nextOffset: 120`，且沒有半筆。

## 5. CLI 面

- [x] 5.1 先寫測試再實作 `akashic s2` 子命令群：八個端點各一個子命令，外加 `status`（design「每個端點一個具型別子命令」）；`--json` 信封含 `source`、`endpoint`、`request`、`fetchedAt`（帶本機時區 offset）、`total`、`data`，並有同源的人可讀輸出；結束碼 3、4、5、64 依 design 的表對應（Requirement「The CLI prints complete results in two forms」「A missing key stops the command with setup guidance」「Status reports readiness without revealing the key」）。驗證：`S2CommandTests` 中，`AKASHIC_S2_KEYCHAIN_SERVICE=akashic-test-<隨機>` 時 `akashic s2 paper DOI:10.1037/a0038889` 以 3 結束、訊息含 service、account 與設定文件路徑（此測試不設 `AKASHIC_S2_BASE_URL`；讀不到金鑰時不發出請求由 in-process 測試以 stub 驗證）；`CLITestHarness` 對未指定 keychain service 的 `s2` 呼叫補上 `akashic-test-harness`；`status --json` 不含金鑰；`references --limit 50 --json` 得 50 筆。
- [x] 5.2 跨程序節流驗收：兩個 `akashic` 子程序共用同一個 `AKASHIC_S2_STATE_DIR`，各送 3 個請求到 loopback stub（Requirement「Requests are throttled machine-wide」）。驗證：`S2CommandTests` 記錄 stub 收到的 6 個請求時間，兩兩間隔至少 1 秒（容許 50 ms）。

## 6. MCP 面

- [x] 6.1 先寫測試再在 `Sources/akashic-mcp/Server.swift` 註冊 `akashic_s2`，在 async 的 `CallTool` handler 內分流：`akashic_s2` 走 async 的處理函式，其餘工具照舊走同步的 `handleToolCall`（design「MCP 面的 async 路徑」與「兩個面都做，MCP 面有位元組上限」）；上限取 48 KiB，錯誤回 `isError: true`，文字與 CLI 相同。驗證：`S2ToolTests` 中 references 截斷為 120 筆時回 `total: 1000`、`returned: 120`、`truncated: true`、`nextOffset: 120`，缺金鑰時的錯誤文字與 CLI 相同；既有的 `AkashicMCPTests` 全數照過。

## 7. 守衛

- [x] 7.1 [P] 先寫負對照 `akashic-guards network-confinement-mutations`（RED），再寫 `akashic-guards network-confinement`，並在 `Sources/akashic-guards/main.swift` 註冊（Requirement「Networking and keychain APIs are confined to AkashicS2」與「A mutation control proves the guard fires」；design「守衛：網路與 keychain API 只准出現在 AkashicS2」）。兩者接進 `.githooks/run-guards.sh`（Requirement「The guard runs with the other guards」）。驗證：兩個子命令都 exit 0，負對照回報九個模式各一個失敗的 mutation、一個在 `Sources/AkashicS2/` 內通過的放置、一個通過的原樣副本；`bash .githooks/run-guards.sh` 全綠。

## 8. 規則、文件與整體驗證

- [x] 8.1 [P] 改寫 `.claude/rules/web-access-via-safari-browser.md`：第 2 條改為只有 `Sources/AkashicS2/` 例外；例外清單從一類改為兩類（帶金鑰的 S2 呼叫經 `akashic s2` 與 `akashic_s2`）；「不適用」第 2 類把 `akashic s2` 排除；〈為什麼〉與〈觸發過的實例〉各補 #664。同步 `CLAUDE.md` 的規則索引；`.claude/rules/mcp-cli-parity.md` 的 MCP 表加 `akashic_s2` 對 `s2` 一列，工具數 33 改為 34，寫明兩面有記錄的差異（MCP 位元組上限、CLI 不截）。驗證：`akashic-guards parity-table-drift` 與 rule-prose 類守衛全綠；逐段讀過，例外與不適用仍是封閉列舉。
- [x] 8.2 [P] 寫設定文件 `plugin/skills/akashic-bootstrap/references/semantic-scholar.md`（存金鑰的指令、ACL 取捨、以 `akashic s2 status` 確認、結束碼 3 的兩種原因），並在 `README.md` 加 S2 段落。驗證：文件裡的 service、account、路徑與 CLI 錯誤訊息逐字一致；rule-coverage 守衛全綠。
- [ ] 8.3 整體驗證：`swift build` 與 `swift test` 全綠，且 `RealHomeSandboxGuard` 未報錯；`bash .githooks/run-guards.sh` 全綠；`spectra validate semantic-scholar-interface` 通過。實機（使用者機器、真金鑰，不進自動測試）：`akashic s2 status` 回報 present 與 readable 皆為 true，`akashic s2 paper DOI:10.1037/a0038889 --json` 回傳該論文。
