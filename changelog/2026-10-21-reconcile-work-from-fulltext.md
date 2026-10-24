# 2026-10-21／10-24 依作品全文核對一筆 work：作者列替換腿、替換記錄、團體成員名單、`fulltext text`／`compare`、`akashic-verify-work` skill（#742）

Spectra change `reconcile-work-from-fulltext`。觸發實例 `claw2018framework`（Claw et al., 2018, *Nature Communications* 9:2957）：
作者列取自 Crossref，20 位，第 6、7 位順序與 PDF byline 相反，13 位聯盟成員被列成作者，團體名沒有 corporate 標記，`export-bib` 把它照人名切開。
PDF 第 1 頁 byline 是 6 位個人＋SING Consortium，成員名單印在第 7 頁。在此之前沒有任何面能整組替換一筆 work 的作者列，唯一的修法是手改 YAML
（10/23 這一筆就是這樣修的，store commit `9ab11e7c`）。

## 使用者的四項裁決（#742 Decision comments）

1. 先做獨立的新 skill，再接在 `akashic-fetch-fulltext` 之後當下一步（2026-10-21）。
2. 團體成員要記錄（原話「需要紀錄，不然團體可能以後會換成員」）；作者列照 byline，成員不留在 `authors`，記在那一篇 work 上，是出版當時的名單（2026-10-21）。
3. **2026-10-24 改判**（原話「我覺得要叫bestOCR才行」）：沒有文字層的 PDF 由 skill 呼叫 bestOCR 的多引擎共識轉出逐頁文字再比對；OCR 得到的值在乾跑報告標「OCR」，一律要人 apply；
   只有 bestOCR 不可用、轉出失敗或信心不足時才標成無法核對。**2026-10-21 的原裁決**是「沒有文字層即標成無法核對、跳過，不做 OCR」。
4. 整份替換作者列時，綁著舊 fingerprint 的完整性證言會失效：移除它，並在報告列出（2026-10-21）。

另有一項 #578 的裁決落在這個 change：`tools/list` 的位元組預算 60,000 → **65,000**、不拆分 MCP server（2026-10-21；觸發點是 `replace_authors`）。

## 落地了什麼（commit 依序）

| commit | 內容 |
|---|---|
| `f3006db1` | `AuthorListReplacementRecordValue`（`替換為 ⟦a⟧ …；依據第 N 頁：理由` 的單一解析器）、`Entry` 附著驗證收第三種 `field: authors` 記錄、頂層 `group-members:`（`GroupMemberList`，規則只有一份）、store format 22 → 23 與寫入閘、work 合併的遺失檢查比對 `group-members`（`entryFieldsCoveredByMergeCheck` 19 → 20）、三個讀取面、`docs/store-format.md` 與 README 的 format 表 |
| `599c90f2` | `update-entry --replace-authors`／`akashic_update_entry.replace_authors`：唯一的 JSON 解碼器、已歸戶位的沿用與釋放、舊記錄與證言的移除與列出、git 閘、`group-members` 的寫入規則、乾跑時寫入閘的拒絕寫進 `applyRefusal`、MCP 面 `verdictsOnRetiredLiterals` 截 20 筆；預算 65,000 |
| `97240b7a` | `StoreHealth` 的失效 warning（`staleReplacementRecords`，doctor 與 App 各一個計數）；Zotero pull 保留帶替換記錄的作者列 |
| `913796b2` | `akashic fulltext text`／`fulltext compare`；`WriteGateRulings` 兩列 |
| `7ac6ee41` | skill `akashic-verify-work`、`akashic-fetch-fulltext` 的下一步、`writing-to-the-store.md`、plugin 殼 0.13.6 → 0.13.7 |
| （本段所在的 commit） | 規則與裁決表、`docs/store-format.md` §3.5 兩節、端到端測試、本檔；akashic-discovery 0.2.16 → 0.2.17（它經 symlink 送出 `plugin/rules`，而 `source-of-truth-over-consent` 加了一列） |

## 部署順序（三個 binary 一起升）

1. 同一個 release 出 `akashic` CLI、`akashic-mcp`、App（三者都要認得 store format 23；舊 binary 遇到 marker 23 整份拒讀）。
2. 使用者把三者都升到這一版。
3. **使用者自己**把 store 的 `store.yaml` 改成 `format: 23`。在那之前替換腿對較舊的 store 拒絕實寫（乾跑照常、拒絕寫在 `applyRefusal`）。
   live store 目前是 **format 18**（2026-10-24 讀 `store.yaml`），所以 19～22 的升級前置一併適用（見 `docs/store-format.md` §5.0 各列）。
4. plugin 殼 0.13.7 的 `binary_version` 仍是 0.12.1：skill `akashic-verify-work` 的第 0 步會先檢查 `akashic fulltext text --help`，binary 不夠新就停。
5. **OCR 路徑要另外裝 bestOCR plugin**。沒有它時，沒有文字層的全文只會標成無法核對，其餘功能不受影響。

## 量測

- `tools/list`：59,159（main `494412f9`）→ **59,816 bytes**（2026-10-24，python 驅動 stdio 量 tools/list 那一行；預算 65,000）。
- live store（2026-10-24 唯讀）：store format 18、entities 8,032、work 2,957、作者列替換記錄 0、帶 `group-members` 的 work 0、讀不到的檔 0
  （`zero-instance-guards` 第 104 列；正對照在寫入過的 scratch store 上數到 1／1）。
- 全套 `swift test`（format bump 之後的第一次）：20 分鐘、只有 KitTests 失敗 11 個案例，全部是這個 change 該跟著改的地方
  （寫死 `supported == 22` 的四個、讀取面守衛、屬性計數、format 文件列、消毒註記），之後逐一修好。

## 測試與負控

- 解碼器 12 條檢查、替換規則 9 條、失效 warning 2 條、Zotero 保留 1 條、`fulltext text` 2 條、`compare` 2 條：逐一拿掉那條檢查，對應的案例都變紅（暫存腳本突變、跑測試、還原，還原後逐位元組相同）。
- **TDD 的例外照實記**：2.2–2.4 的測試是在替換腿實作之後才寫的（沒有經過 RED），改以上面的負控證明它們真的在量。
- 4.2 的「binary 不呼叫 OCR」檢查改為比對呼叫形（argv 裡的 OCR 執行檔名、Vision 的文字辨識 API、`consensus(` 呼叫）：原本的字詞 grep 會命中說明「本命令不做 OCR」的註解與 help。改後零命中。

## 端到端（6.4，`FulltextReconcileCLITests.testClawShapeEndToEnd`，真 binary）

scratch store：7 頁的 fixture PDF（byline 在第 1 頁、13 位成員在第 7 頁），work 有 20 位作者、第 20 位（index 19）已歸戶為 `garrison-nanibaa`。

```
akashic store-source <fixture.pdf> --media-type application/pdf … --json --library <scratch>
akashic fulltext text --library <scratch> --citekey claw2018framework --out <tmp>/text.json      # pageCount 7、hasTextLayer true
akashic fulltext compare --library <scratch> --citekey claw2018framework --proposal <tmp>/p.json --out <tmp>/c.json
akashic update-entry claw2018framework --replace-authors <tmp>/replace.json --library <scratch>          # 乾跑
akashic update-entry claw2018framework --replace-authors <tmp>/replace.json --library <scratch> --apply
akashic export-bib --library <scratch> --citekeys claw2018framework
akashic validate --library <scratch>; akashic doctor --library <scratch>
akashic resolve-people --library <scratch> --split-author "claw2018framework:0: G. =…"; akashic validate --library <scratch>
```

結果：作者列 7 位、第 6 位是 `{Summer internship for INdigenous peoples in Genomics (SING) Consortium}`、第 7 位以 `from: 19` 沿用 `garrison-nanibaa`；
`group-members` 13 位照原序、第 7 頁；替換記錄解析出 7 段、第 1 頁；`export-bib` 的 AUTHOR 把團體輸出為一個 corporate 名、成員不在其中；
`validate` 與 `doctor` exit 0、沒有這一族的 warning；`get-entry` 印出名單。替換之後再拆一位，`validate` 印出
「作者列替換記錄與目前的作者列對不上」且 exit 0（D8）。

## OCR 路徑的實跑（5.4、5.5）

fixture：把一份三頁的文字 PDF 以 `pdftoppm -r 150` 點陣化、`sips` 包回 PDF、`pdfunite` 合併——`pdftotext` 抽不到任何字。

- **(5.4 b)** `fulltext text` 回 `pageCount 3`、`hasTextLayer false`。bestOCR `list_engines`：本機可用 vision、tesseract、ext.rapidocr、ext.cnocr、ext.surya、doc.marker（雲端三個不可用）。
  `consensus` 恰被呼叫三次（`pages` 依序 "1"、"2"、"3"，不帶 `engines`），每次參與的都是那六個本機引擎、沒有 `cloud.*`；第 1 頁轉出 byline 五行、0 個低共識項。
  **實跑抓到一件 skill 要寫明的事**：`sources/` 裡的存檔沒有副檔名，bestOCR 以 `unsupported input type` 拒收；skill 改成先複製成 `$WORK_DIR/<citekey>.pdf`。
  低共識清單在 `.consensus.json` 的鍵是 `low_consensus`、參與引擎是 `engines`，skill 照這兩個鍵名寫。
- **(5.4 c)** 在一個沒有任何 MCP 工具的 agent（只有 Read／Grep／Glob／Bash）裡照 skill 跑同一筆：它走進 OCR 路徑、因為沒有 bestOCR 的工具而標成無法核對，
  點名缺的是 `list_engines`、`consensus`，附上「裝好 bestOCR plugin 後可以再核對」，`update-entry` 一次都沒呼叫，暫存目錄刪掉。
- **(5.5 b)** byline 頁以 38 dpi 點陣化、加 6% 椒鹽雜訊與 0.7 的高斯模糊：`consensus` 回 9 項、**8 項低共識**，其中一行被認成「with indigenous **cohorts**」
  （原文 communities）。照 skill 的規則，byline 有低共識項 → 作者列整欄「無法核對（信心不足）」、不送 `replace_authors`；這一次沒有呼叫 `update-entry`。
  共識擋下的正是這種錯；多個引擎錯得一樣時它擋不住，所以 OCR 的列仍一律要人確認。

## live store 的 `claw2018framework`（6.5，唯讀）

這筆在 10/23 已依 PDF 手改成 7 位作者，所以這次的乾跑：作者列 `same`、成員名單 `absentInStore`，替換會補上依據記錄與第 7 頁的 13 位成員：

```
akashic fulltext text --library ~/.akashic --citekey claw2018framework --out <tmp>/text.json          # 7 頁、有文字層
akashic fulltext compare --library ~/.akashic --citekey claw2018framework --proposal <tmp>/proposal.json --out <tmp>/compare.json
akashic update-entry claw2018framework --replace-authors <tmp>/replace.json --library ~/.akashic         # 乾跑
```

乾跑：`unchanged: false`、`groupMembersAfter` 一組 13 位（第 7 頁）、`recordsRemoved` 0、`witnessRemoved` false、`verdictsOnRetiredLiterals` 0；
`applyRefusal`：store 是 format 18、要 23 才寫得進。**沒有寫 live store**：操作前後 `git status --porcelain` 逐行相同（live store 本來就有其他工作留下的
未 commit 與未追蹤檔，沒有動）。三個 binary 都升級、marker 升到 23 之後，要套用就是同一條命令加 `--apply`（乾跑先看一次）。

## 後續（另開的 issue）

- #745：依全文更正非作者欄位時記不下依據——`update-entry` 沒有對應的寫入腿。
- #746：團體作者的成員名單升格為 person ref。

## 照實記的行為擴大

Zotero pull 的作者列保留，原本只看 person key（`.key`）；這個 change 依 spec 的「任何已歸戶位」一併算進 organization（`.organization`）。
organization 位在 #323 之前不存在，原本那一行寫在它之前。
