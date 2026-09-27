# 2026-09-27 建檔回報 DOI 命中、bootstrap 第 1 步照實寫、散文守衛逐根跑（#637、#638、#644）

## #637：`create-entry` 在 DOI 已在庫時具名回報

`createEntries` 原本不檢查 DOI。store 已有同一篇時照常新建，只在 citekey 撞名時自動加尾碼（`xxx2020b…`），整個過程沒有提示。立案時量到 16 組「同一個 DOI 對到兩筆記錄」，其中 13 組是這個形狀。

做法是**只回報、不拒絕**。（這裡原本寫「DOI 相同只是提名、不是同一性證據」，那與 `identity-is-judged-not-matched` 矛盾——DOI 相等依該規則足以判定指的是同一篇。不拒絕的真正理由是 erratum 會與原文共用 DOI，拒絕會擋掉這類合法記錄。更正見 `2026-09-27-batch7-r2-verify.md`。）

- `BatchCreateReport.doiHits`：這一筆的 DOI 已在庫，或同一批稍早的一筆已用過時，列出命中的 citekey。比對走 `canonicalDOIs` 的正規形。
- 兩面同一份：MCP `akashic_create_entry` 的回應帶 `doiHits`，CLI `create-entry` 印 ⚠。每個 DOI 至多列 20 個 citekey。
- 測試（`BatchCreateTests`）：已在庫、同一批重複、MCP 單筆 payload。負控（拿掉回報）紅 6 條。
- `mcp-cli-parity` 的 `akashic_create_entry` 列記為契約有改、裁決不變。

#611 是同一個問題在 Zotero 匯入路徑上的版本，本輪沒有動。

## #638：`akashic-bootstrap` 第 1 步照實際可行的查法寫

示範的 `akashic_search(query: …)` 不存在：`akashic_search` 只有作者、刊名、年份、tag、type、library 這幾個條件，store 也沒有以標題或 DOI 查詢的入口。

採 issue 的第 2 個選項：把第 1 步改成實際的參數，並寫明——

- 查 DOI 靠 #637 的 `doiHits`：一看到命中就停下核對。
- 查標題靠 `export-tables` 的 publications 表。

第 1 個選項（新增以 DOI、標題查詢的入口）沒有做。

## #644：`rule-prose-guards` 的第 1、2 項逐根跑

這支守衛原本只掃 `plugin/`，所以 `plugins/akashic-discovery` 的散文不受第 1、2 項檢查：repo 專屬路徑不得以可跟隨的連結出現，提到時要在同一行揭露讀者可能取不到。

- 新增 `--prose-only`：只跑第 1、2 項。第 3–6 項綁著 `plugin/` 專屬的內容，在別的根上沒有意義。
- `run-guards.sh` 對 `plugin-roots` 列出的其他根逐一以這個旗標跑。根的清單同樣只取自 `plugin-roots`；`plugin/` 那次照舊跑六項。
- 負控（`rule-prose-guards-mutations`）新增一格：在 discovery 根的副本加一句沒有揭露的 `.claude/rules/…`，恰好第 2 項變紅。注入前先確認副本本身是綠的。harness 現在是 15/15。
