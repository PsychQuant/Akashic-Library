---
name: akashic-verify-work
description: 依作品本身的全文核對 Akashic 一筆 work 的書目欄位——作者列（byline）、團體作者的成員名單、標題、卷、期、頁碼或 article number、日期——乾跑給人看，人在 session 裡明確同意後，才以 `update-entry --replace-authors`（MCP `akashic_update_entry` 的 `replace_authors`）整組替換作者列並記下依據（哪一份全文、第幾頁、理由）。全文要已經存在 store 的 `sources/` 並連在該 work 上（`akashic-fetch-fulltext` 之後的下一步）。PDF 沒有文字層時改用 bestOCR 的多引擎共識逐頁轉出文字，OCR 讀出的值在乾跑表標「OCR」。當使用者說「用全文核對這筆」「作者列跟 PDF 不一樣」「照 byline 改作者」「團體作者的成員要記下來」「核對書目」「verify work」，或 `akashic-fetch-fulltext` 剛存好一份全文時使用。**不做**：取得全文（那是 akashic-fetch-fulltext）、判定某個名字是不是某個人（那是 akashic-verify-person）、改作者列以外的欄位（只列出不一致）。
---

# 依全文核對一筆 work

書目欄位以作品本身為依據（#639）：登記機構（Crossref、Zotero、WoS）給的作者列是線索，PDF 的 byline 才是作品自己說的話。觸發實例 `claw2018framework`（#742）：Crossref 給 20 位，PDF 第 1 頁 byline 是 6 位個人＋1 個團體，13 位團體成員印在第 7 頁。

這個 skill 把「讀全文 → 逐欄比對 → 乾跑給人看 → 人確認後寫入」串起來。確定性的部分（轉文字、比對、驗證、寫入）全是 `akashic` 子命令；**判讀**（哪一行是 byline、人名怎麼切、哪一段是成員名單）由你做，再交給人確認——`two-kinds-of-edits` 的「提名（程式）→ 判定（AI／人）→ 落地（程式）」。

## 這個 skill 能做到哪裡（誠實邊界）

- **能**：讀本機 `sources/` 裡那份全文的逐頁文字、比對 store 現值、產出可以直接交給 `update-entry --replace-authors` 的 JSON，經人同意後寫入作者列、替換記錄與成員名單。
- **能（沒有文字層時）**：以 bestOCR 的多引擎共識逐頁轉出文字再比對（見〈沒有文字層：OCR 路徑〉）。
- **只列、不寫**：作者列以外的欄位（標題、卷、期、頁碼、article number、日期）不一致時只列出。目前的寫入路徑記不下「出自哪份全文第幾頁」，要另案處理（#742 的後續 issue）。
- **不連網**：只讀本機 `sources/`，所以不涉及 `web-access-via-safari-browser`。OCR 只用 bestOCR 的本機引擎，全文不離開本機。
- **不判身分**：「byline 上的 Garrison, Nanibaa' A. 是不是 store 裡的 `garrison-nanibaa`」不是本 skill 判的。已歸戶的位置只有兩種處置：以 `from` 原樣沿用，或列在 `release` 附理由；不得依名字自動對回。

## 開始前

0. **binary 夠不夠新**：`akashic fulltext text --help` 要能印出說明。印不出（`Unexpected argument`、找不到子命令）表示 `akashic` 比 #742 舊——停下，請使用者更新 Akashic 的 CLI、akashic-mcp 與 App，不要改用別的方法讀 PDF。
1. 這筆 work 要已經連著一份全文：`akashic get-entry <citekey> --json` 的 `akashic.sources` 至少一個 digest。沒有 → 先走 `akashic-fetch-fulltext`。連著兩份以上時，要使用者指定是哪一份（`--source <digest>`）。
2. 寫入作者列替換記錄需要 **store format 23**。`update-entry --replace-authors` 乾跑會照樣報出計畫，format 不足時理由在 `applyRefusal`；升 marker 是使用者在 CLI、akashic-mcp、App 三者都升級之後自己做的事，本 skill 不代改。
3. 開一個暫存目錄放全文文字與 OCR 輸出，**必須在任何 git 工作樹之外**（全文是第三方有版權的內容）：

   ```bash
   WORK_DIR=$(mktemp -d "${TMPDIR:-/tmp}/akashic-verify-work.XXXXXX")
   ```

## 流程（一次一筆）

### 1. 取逐頁文字

```bash
akashic fulltext text --citekey <citekey> [--source <digest>] --out "$WORK_DIR/text.json"
```

輸出 `{"citekey", "source", "pageCount", "hasTextLayer", "pages": [{"page", "text"}]}`。`page` 是 PDF 的**實體頁序**（從 1 起算），不是印刷頁碼——替換記錄記的就是這個數。

- `hasTextLayer: true` → 讀 `pages` 的文字，到第 2 步。
- `hasTextLayer: false`（沒有任何一頁含字母）→ 走〈沒有文字層：OCR 路徑〉，取得逐頁文字後回到第 2 步。
- 命令拒絕（本機沒有那份存檔、work 沒連任何 PDF、`--out` 在 git 工作樹內）→ 這筆**無法核對**，說出原因，停。

### 2. 讀出作品本身說的值，寫成提議

先看 store 現值與作者位的索引（`from` 與 `release` 用的是 0 起算的位置）：

```bash
akashic get-entry <citekey> --json
```

從全文讀出：

- **byline**（通常在第 1 頁）：作者的次序與寫法照原文逐字；團體作者寫成 `group`（不含大括號，寫入時會加 corporate 標記）。
- **團體成員名單**（文末或附錄，例如「SING Consortium: …」）：照原文次序逐字，記下所在頁。成員**不進** `authors`。
- 標題、卷、期、頁碼或 article number、日期，各帶頁序。

store 裡已歸戶的位置（`key`／`organization`）要逐位處置：byline 上仍是那一位 → `{"from": i}`；byline 上沒有 → 列在 `release` 附理由（例如「PDF byline 沒有這一位：Crossref 把聯盟成員列成作者」）。兩者都沒有的提議會被擋下，那是刻意的。

把提議寫成 `$WORK_DIR/proposal.json`：

```json
{"source": "sha256:…",
 "authors": {"page": 1, "items": [{"literal": "Katrina G. Claw"}, {"group": "Summer internship for INdigenous peoples in Genomics (SING) Consortium"}, {"from": 19}]},
 "release": [{"index": 12, "reason": "…"}],
 "groupMembers": [{"group": "Summer internship for INdigenous peoples in Genomics (SING) Consortium", "page": 7, "members": ["…"]}],
 "title": {"value": "…", "page": 1}, "volume": {"value": "9", "page": 1}}
```

`source` 與 `authors` 必填，其餘欄位可省。`authors.reason` 選填：它會成為替換記錄的理由，省略時填「PDF 第 N 頁 byline」；byline 有值得記下的判斷（例如「Crossref 把聯盟成員列成作者」）就寫進去，**依 OCR 文字時一定要寫**（見〈沒有文字層：OCR 路徑〉第 5 點）。**拿不準就不提議那一欄**——缺的看得見，錯的看不見。

### 3. 比對

```bash
akashic fulltext compare --citekey <citekey> --proposal "$WORK_DIR/proposal.json" --out "$WORK_DIR/compare.json"
```

輸出 `rows`（每欄一列：`field`、`store`、`proposed`、`page`、`status`∈`same`／`differs`／`absentInStore`／`notProposed`）、`replaceAuthors`（作者列不同時，可直接交給 `update-entry --replace-authors` 的 JSON，否則 null）與 `refusal`（替換腿會拒絕這份提議時的原因，否則 null）。

`refusal` 不是 null → 回第 2 步修提議（多半是某個已歸戶位沒有 `from` 也沒有 `release`）。不要繞過它。

### 4. 乾跑給人看

把 `replaceAuthors` 存成檔，乾跑替換腿：

```bash
akashic update-entry <citekey> --replace-authors "$WORK_DIR/replace.json"
```

（MCP：`akashic_update_entry(citekey=…, replace_authors={…})`，`dry_run` 預設 true。）

給使用者看一張表，**每一列**是：

| 欄位 | store 現值 | 作品本身（頁） | 文字來源 | 提議寫入 |
|---|---|---|---|---|

- 「文字來源」寫 **文字層** 或 **OCR**（OCR 路徑讀出的列一律標 OCR）。
- 作者列那一列之下另列：`authorsBefore`→`authorsAfter`、`released`（逐位、附理由）、`recordsRemoved`（會被移除的拆分、移除、先前替換記錄）、`witnessRemoved`、`groupMembersAfter`／`groupMembersRemoved`、`verdictsOnRetiredLiterals`（`carriedOver: true` 的是仍以 `from` 留著的 key，當初升格的依據，不必處理）。
- `applyRefusal` 有值時照實說：實寫會被擋（多半是 store format 不足），計畫本身仍可看。
- 作者列以外不一致的欄位只列出，並說明：這一次不會寫，因為目前的寫入路徑記不下依據。

### 5. 人同意之後才寫

**只有使用者在這個 session 裡明確同意這張表**，才實寫：

```bash
akashic update-entry <citekey> --replace-authors "$WORK_DIR/replace.json" --apply
```

（MCP：同一個 `replace_authors` 加 `dry_run=false`。）實寫要求這筆 work 的檔已在 git 裡 commit、乾淨——被移除的記錄在 git 裡留副本。

- **unattended（沒有人在場）只做到第 4 步**，不寫。
- 寫完用 `akashic get-entry <citekey>` 核對作者列與 `group-members`，`akashic validate` 不應多出新的 error。

### 6. 收尾

刪掉 `$WORK_DIR`（全文文字與 OCR 輸出不留在磁碟上）。回報每筆一列：citekey、結果（已替換／乾跑待確認／無法核對）、文字來源、依據的 digest 與頁序、未寫入的不一致欄位。

## 沒有文字層：OCR 路徑

`fulltext text` 回 `hasTextLayer: false` 時（2026-10-24 使用者裁決：「我覺得要叫bestOCR才行」），不跳過，改由 bestOCR 轉出文字再比對。Akashic 的 binary 不呼叫任何 OCR 引擎，這一步在本 skill 裡做。

1. **確認引擎**：呼叫 bestOCR 的 `list_engines`。可用的**本機**引擎（不含 `cloud.*`）少於兩個 → 這筆無法核對（見下表）。只有一個引擎時**不退回**單一引擎的 `ocr`：它不輸出任何信心值，沒有共識就沒有信心可量。
2. **逐頁共識**：對第 1 頁到第 `pageCount` 頁，**一次一頁**呼叫 bestOCR 的 `consensus`：`input_path` 是那份全文（`sources/` 裡的檔，或先複製到 `$WORK_DIR`），`pages` 設成那一頁的頁號（`"1"`、`"2"`…），`out_dir` 設在 `$WORK_DIR` 裡，**不帶 `engines`**（預設是全部本機引擎），**不指定任何 `cloud.*` 引擎**（那會把文件送出本機）。一次一頁，頁序就由呼叫方式確定，不必從輸出反推哪段文字在哪一頁。
3. **讀文字與低共識清單**：每頁的 `<stem>.consensus.md`（⚠ 標出低共識項）與 `<stem>.consensus.json`（低共識複核清單）。第 2 步照常讀 byline 與成員名單，但記下每個值依據的是哪幾項。
4. **信心不足就不提議**：一個欄位的提議值所依據的文字，只要有**一項**在該頁的低共識複核清單裡，這一欄就標「無法核對（信心不足）」，不提議。**作者列與成員名單算同一欄**（它們由同一次替換寫入）：byline 或成員名單任何一項低共識，整個作者列不提議、不送 `replace_authors`。
5. **標記與理由**：乾跑表每一列的「文字來源」寫 **OCR**。依 OCR 文字替換作者列時，提議的 `authors.reason`（它就是替換理由）寫明「依 bestOCR 多引擎共識辨識」並列出這次參與的引擎 id（取自 `list_engines` 或 `consensus.json`），例如：`PDF 第 1 頁 byline；依 bestOCR 多引擎共識辨識（vision、tesseract）`。這樣 store 日後說得出這一筆依據的是 OCR 文字。
6. **寫入閘不變**：OCR 列同樣只有使用者在 session 內明確同意才 apply，unattended 不寫。共識只擋得住引擎之間意見不一的錯；多個引擎錯得一樣時照樣過關，所以人要看。

## 無法核對的情形（封閉列舉，只有這幾種）

| 情形 | 說什麼 |
|---|---|
| work 沒有連任何全文 | 先走 akashic-fetch-fulltext |
| 本機 `sources/` 沒有那份存檔 | 換機器後要重新取得；`sources/` 不進 git |
| 沒有文字層，而這個 session 沒有 bestOCR 的工具 | 指名缺的是 bestOCR plugin 的 MCP 工具；裝好 bestOCR plugin 後可以再核對 |
| 沒有文字層，`list_engines` 回報可用的本機引擎少於兩個 | 說出實際可用幾個；`consensus` 至少要兩個 |
| 沒有文字層，某一頁的 `consensus` 回錯誤 | 說出是哪一頁、錯誤訊息 |
| 某一欄依據的文字有低共識項 | 只有那一欄（作者列與成員名單一起）標「信心不足」，其他欄照常 |
| 有文字層，但需要的欄位落在沒有字母的那幾頁 | 說出是哪一頁；個別頁的 OCR 不在這一輪 |

整筆無法核對時，不呼叫 `update-entry`。

## 不做的事

- 不手寫條目 YAML；作者列一律走 `update-entry --replace-authors`（writing-to-the-store.md）。
- 不依名字把 byline 上的人對回 store 裡的 person key；那是 akashic-verify-person 的判定。
- 不在乾跑之前寫、不在使用者沒有明確同意時寫、unattended 不寫。
- 不用 `cloud.*` OCR 引擎、不把全文或 OCR 輸出放進任何 git 工作樹、用完刪掉暫存目錄。
- 不寫作者列以外的欄位。

## 相關

- [`source-of-truth-over-consent`](../../rules/source-of-truth-over-consent.md)——團體署名與成員名單的依據是作品本身；使用者的話是線索
- [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)——回報裡的每一句都要量過；拿不準就標無法核對
- akashic-fetch-fulltext——取得全文、存進 `sources/`、連回 work（本 skill 的前一步）
- akashic-verify-person——「這個 literal 是不是這個人」的身分判定
- #742（本 skill 與替換腿；2026-10-21 四項裁決、2026-10-24 裁決 3 改判）
