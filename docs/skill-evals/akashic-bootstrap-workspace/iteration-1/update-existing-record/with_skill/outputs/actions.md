# Actions（chen2020association 補 PMID）

Store: `/Users/che/Developer/psychquant-claude-plugins/plugins/akashic-mcp/skills/akashic-bootstrap-workspace/iteration-1/update-existing-record/with_skill/store`
CLI: `/Users/che/Developer/Akashic-Library/.build/arm64-apple-macosx/debug/akashic`

未使用任何 `mcp__*akashic*` MCP 工具（依指示，全程 CLI / 自寫 script）。

## 1. 找目標記錄（讀取，未修改 store）

```bash
grep -rl "chen2020association" "$STORE"
```
實際執行。找到 `entities/C37BE4B6-FD8C-4BFC-900E-A2EDE664D4E1.yaml`（citekey: chen2020association），已有 DOI `10.2174/0929867327666200425214906`，無 pmid 欄位。

## 2. 外部查詢（讀取，未修改 store）

```bash
curl -s 'https://www.ebi.ac.uk/europepmc/webservices/rest/search?query=DOI:"10.2174/0929867327666200425214906"&format=json&resultType=core'
```
實際執行。命中 1 筆，`pmid: "32334497"`，標題／作者／期刊／卷/期/頁碼與 store 記錄完全一致（見 response.md 的比對表）。

## 3. 乾跑（讀取，未修改 store）

寫了一個一次性 Swift snippet `Snippets/UpdatePmid.swift`（放在 Akashic-Library package 底下，用 `swift run` 執行，事後已刪除），內容依 akashic-bootstrap skill 的 `references/writing-to-the-store.md` 範本：`EntryYAML.decode` → 只在 `fields["pmid"] == nil` 時補值 → `EntryYAML.encode`。

```bash
swift run UpdatePmid                    # 不帶 --apply，純檢查
swift run UpdatePmid -- --show-diff     # 額外把 encode 後的內容寫到 job tmp 目錄做 diff 預覽，不碰 store
diff <store 原檔> /Users/che/.claude/jobs/5a115bd1/tmp/pmid_out.yaml
```
實際執行。確認只會新增一行 `pmid: 32334497`（依欄位字母序插在 `pages` 與 `url` 之間），沒有其他改動。

## 4. 寫入（**唯一實際修改 store 的動作**）

```bash
swift run UpdatePmid -- --apply
```
**實際執行**，寫入了 `entities/C37BE4B6-FD8C-4BFC-900E-A2EDE664D4E1.yaml`。

**寫入機制**：不是走任何 CLI 子指令或 MCP 工具（該操作是「更新既有記錄的部分欄位」，目前沒有正規入口——`akashic_create_entry`/`akashic_add_person` 對已存在的目標會拒寫）。實際機制是 Swift 程式碼直接呼叫 `AkashicCore.EntryYAML.decode(_:)` 讀入既有 YAML → 在記憶體中的 `Entry.fields` 字典補上 `"pmid": "32334497"`（只在該 key 原本是 nil 時才寫，未覆寫任何既有值）→ `AkashicCore.EntryYAML.encode(_:)` 重新序列化 → 用 `String.write(to:atomically:encoding:)` 覆寫回原檔案路徑。這條路徑用的是 store 自己的編碼器（與正規 CLI/MCP 寫入路徑相同的序列化邏輯），不是手刻字串拼 YAML。

## 5. 驗證（讀取，未修改 store）

```bash
akashic validate --library "$STORE"    # ✓ 12 entries、12 people、0 libraries 全部通過
akashic doctor --library "$STORE"      # entries: 12, orphaned: 0
```
實際執行，皆通過。

## 6. 清理

```bash
rm -rf /Users/che/Developer/Akashic-Library/Snippets
```
實際執行——刪掉步驟 3/4 用的一次性 script，沒有留在 Akashic-Library repo 裡（該 repo 本身未被 commit，只是暫時借它的 Swift package 環境跑一次性程式）。

## 未執行 / 跳過的動作

- **未建立 `sources/` provenance 記錄**：skill 建議把外部查來的原始資料（Europe PMC 回應）以內容定址存進 `sources/`。這個 eval store 目前沒有 `sources/` 目錄、也沒有 `.gitignore` 保護（`git check-ignore` 對這個路徑回傳空），而該 store 又位於一個有 remote 的 git repo 底下——貿然新建 `sources/` 有把第三方 API 回應推上 remote 的風險，所以這步刻意跳過，只在 response.md／本檔案裡記錄查詢方式與結果作為 provenance。
- **未動 `.gitignore`**：跑指令過程中發現 Akashic-Library repo 的 `.gitignore` 有一筆非我造成的既有未提交改動（`.claude/worktrees/` 相關），與本任務無關，未觸碰、未還原、未提交——留給該改動的擁有者處理。
