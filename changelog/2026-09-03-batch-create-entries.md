# 2026-09-03 · #455 批次 create 的 service 面：一次 load、一次 rebuild

## 為什麼

#423 的驗收 run（Psychological Methods 全量 1545 筆）量到逐筆匯入是 **O(n²)**：`create-entry` 每筆各自
`store.load()` 全庫（只為算 citekey 唯一性）、寫後 `LibraryIndex.rebuild()` 全重建；CLI `--format json`
**已收陣列**卻逐筆呼叫 service；`library add` 同形。實測每筆 2 → 6 秒（n≈940 → 2400），全批約 3 小時。

## 裁決（使用者 2026-09-03）

- **失敗語意**：可預期的失敗（type 值域、識別碼形狀、欄位鍵、citekey 目的檔、format 閘、encode）**整批擋、
  零寫入**，訊息指名「第 N 筆「title」」；磁碟層 I/O 失敗**逐筆收容**、其餘照寫、rebuild 照跑——與
  `commitResolution` 同一套。不選「全部整批」（I/O 中途失敗本來就是部分寫入）、不選「全部逐筆」（單筆版
  「拒絕即零寫入」的語意會在批次面消失）。
- **MCP 面不加批次 tool**：批次屬操作者規模（同三個 `bootstrap-*`）；`akashic_create_entry`／
  `akashic_libraries` 維持單筆，但兩面**同一條實作路徑**（單筆是薄包裝）。裁決記在 `mcp-cli-parity.md`
  的 CLI-only 表。

## 改了什麼

- `LibraryStore.assertEntryWritable(_:format:)`：從 `writeEntry` 抽出（citekey 文法、識別碼 reference ≥13、
  membership key、sources ≥9、venues ≥11、organization 作者 ≥12），`writeEntry`／`writeEntryExclusive`
  共用；批次 preflight 鏡射同一個函式。**順手修掉一個真缺口**：`writeEntryExclusive` 先前只驗 citekey＋
  encode，format 閘整組缺席——rename 的目的檔走它，format 10 的 store 能寫進含 venues 的 entry
  （`EntryWritableGateTests` 釘住）。
- `AkashicService.EntryDraft`／`BatchCreateReport`／`createEntries(_:)`：一次 load；`existing`（含 quarantined
  basename）在批次內**逐筆累積**——同作者同年三筆得 `author2024manual`／`author2024bmanual`／
  `author2024cmanual`（單筆版沒有的情況）；先全驗零寫入；逐筆 `writeEntryExclusive`（目的檔存在
  fail-closed，順手關掉單筆版 fileExists→write 的 TOCTOU）；一次 rebuild。`createEntry` 改薄包裝，既有
  5 支測試零改動。
- `AkashicService.setMembership(action:key:citekeys:)`：library add／remove 的批次形；單 citekey 改薄包裝。
- CLI `create-entry`：刪自己的 `EntryDraft`（typealias 到 service），陣列一次呼叫；**行為變更**：先前第 k 筆
  驗證失敗時前 k−1 筆已落地、exit 0，現在零寫入、exit 非零。`library add|remove` 收多 citekey，走
  `setMembership`——**刪掉 CLI 自己那條 `mutateMembership`**（與 MCP 的 `libraries(action:)` 是兩條會分岔的路徑）。
- 守衛：`audit-guards-mutations` 的負控 `moveNestedStruct` 原本搬巢狀 `EntryDraft`，改搬同檔的 `enum Format`
  （case 目的不變：純重排不得被 parity-table-drift 當成缺陷）。

## 量測（2026-09-03，同一台機器 M5 Max；store 副本 3,565 筆 entity、不含 `sources/`；合成 draft）

| 情境 | binary | 筆數 | 秒 | 每筆 |
|---|---|---|---|---|
| 逐筆（舊） | `~/bin/akashic`（2026-09-01 build，release） | 50 | 158 | 3.16 s |
| 批次（新） | `.build/debug/akashic`（本 change） | 50 | 6 | 0.12 s |
| 批次（新） | `.build/debug/akashic` | 1545 | 9 | 0.006 s |

方法：`AKASHIC_HOME=<空目錄> <binary> create-entry --format json --file drafts.json --library <store 副本>`，
`date +%s` 前後相減。**新的是 debug build**（未最佳化），舊的是 release——比較對新的不利，差距仍是
數量級。原始輸出在 job scratch（`measure455/`），不進 repo。

## 誠實邊界

- 「一次 load、一次 rebuild」以量測釘住，不以 mock 計數；`search` 走 `freshEngine()` 會在 stale 時重建，所以
  測試裡的 index 斷言證明的是「index 反映已寫的」，不是「只 rebuild 一次」。
- I/O 失敗注入用「目的檔位置被目錄占住」（`EntryDraft.id` 指定）——這是 entities 佈局下唯一能逐筆注入的手段；
  唯讀目錄會讓整批失敗，測不到「其餘照寫」。
- 部分 I/O 寫入仍是部分寫入：report 逐筆列已寫與失敗、rebuild 照跑、exit 非零——不假裝原子。

## 相關

#455（本張）、#499（venue 側 verdict 的 O(catalog) 形狀，自 #455 拆出）、#458（enrich 面已是一次 load 一次
rebuild）、`plugin/skills/akashic-venue-works/SKILL.md`（第 3／4 步與效能事實段同步改）。
