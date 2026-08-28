## 1. 模型

- [ ] `Venue` 新增頂層 `variant: [String]?`（與既有 `authorized` 並列）
- [ ] YAML 編解碼：`variant` 進封閉鍵域，未知鍵仍走 tolerant-preserve
- [ ] `StoreVersion.supported` → 14
- [ ] `Venue.validate()`：`variant` 與 `authorized` 不得有交集（同一個名字不能既權威又是異寫）

## 2. 遷移

- [ ] `migrate-venue-variants`：多筆 `names` 中不在 `authorized` 的搬進 `variant`
- [ ] 乾跑是預設，逐筆印出「這筆會被標成 variant」供人過目（35 筆可行）
- [ ] per-file trackedness pre-flight（沿用 `migrate-venues` 的既有形狀）
- [ ] `mcp-cli-parity` 的 CLI-only 表加一列（格式遷移＝維運例外）

## 3. 呈現

- [ ] `displayName` 的四階回退**不動**——確認它讀到的仍是同一組候選
- [ ] `akashic venue` 的輸出把 authorized 與 variant 分開顯示
- [ ] MCP `akashic_venue` 同步（`mcp-cli-parity`：讀取面 `--json` 原樣轉印＋人可讀同源）

## 4. spec

- [ ] `venue-entity` spec：改掉「NOT the nested person partition」那半句
- [ ] 新增 Requirement：variant 分割不帶時間欄位
- [ ] 既有的「Venue name history timeline」Requirement **保留**，收窄適用範圍

## 5. 驗證

- [ ] 遷移後重量：`names` 多筆且不帶時間的 venue 應為 0（全部搬進 variant）
- [ ] `akashic validate` 零新 diagnostic
- [ ] round-trip：舊 binary 讀 format 14 的 venue 檔，`variant` 原樣保留
