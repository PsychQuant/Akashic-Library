---
name: akashic-import-wos
description: WoS 匯出清單的匯入前 QA——DOI 補查、同篇雙列偵測（early-access／erratum／重複收錄）、機構名誤植容錯，產出 intake 報告經人確認後才交給 import-wos。當使用者拿到一份 WoS 格式的 Excel/CSV 清單（「所方給的成果清單」「這批要進 Akashic」「這份 WoS 匯出先整理一下」）、或說「先檢查這份清單有沒有重複」「補一下 DOI」時使用。清單的分母（實際篇數）在這一步定案——不做這步就匯入，重複列會流進下游統計。與 akashic-bootstrap 的分工：本 skill 是清單層的 QA 閘（列 vs 列），bootstrap 是逐筆實體的補完（查證單篇/單人）。同型的其他書目匯出清單（Scopus、所方自製格式）除 WoS 特有欄名對映外同樣適用。
---

# WoS 清單的匯入前 QA

一份 WoS 匯出清單在進 `import-wos` 之前要先回答三個問題：**每列有沒有 DOI、
哪些列其實是同一篇、實際篇數是多少**。答案定案（經人確認）之後才匯入。

**為什麼不能直接匯**：實測一份「100 篇」清單，DOI 逐篇補查後發現三組同篇雙列——
實際只有 97 篇。兩列不逐字相同（early-access 把日期塞進標題尾端、erratum 帶卷頁
附註），字串比對認不出；解析到同一個 DOI 才抓出來。不做這步，分母錯誤直接流進
下游所有統計。

## Workflow

### 1. 讀清單

xlsx/CSV 用手邊可用的讀法（python＋openpyxl、`excel-to-json` skill、或 csv 直讀）。
逐字保留原欄位——QA 是加註，不是改寫（無損匯入契約：Akashic-Library#206）。

`import-wos` 認的**字面欄名**（硬編於 `WoSImport.swift`；合取判準與 step 5 的 TSV
產出都以此為準）：`Authors`／`Author Full Names`／`Article Title`／
`Publication Year`／`Publication Date`／`Source Title`／`Volume`／`Issue`／
`Start Page`／`End Page`／`DOI`／`Group Authors`；其餘欄位走殘餘收集原樣入
`fields`（#206）。（本清單是**快照**；含對映目標與合成語意的正典在 repo 的
`docs/import-wos-mapping.md`（Akashic repo；**private，無 repo 存取權者取不到**——欄名對映的權威在該檔，本 skill 只在此註明出處）
——兩者不一致時以正典為準。）

### 2. DOI 補查（缺 DOI 的列）

以**合取**判準查 Crossref：標題＋第一作者姓＋期刊＋年份同時相符才收。

- **標題相似度單獨不可信**——preprint 版的標題相似度可以比正式版還高；
  「像但不是」的三種記錄形態與合取判準的細節見 akashic-bootstrap 的
  [work-sources.md](../akashic-bootstrap/references/work-sources.md)，不在此複製
- 查到的 DOI **寫進該列既有的 `DOI` 欄**（那些列該欄本來是空的——填空不是覆寫；
  importer 只認字面欄名 `DOI`，寫進自創欄位會在匯入時蒸發）。原始檔另留一份
  未動的 provenance 副本
- 查不到就標「無 DOI」——那是誠實狀態，不擋匯入；這桶的雙列偵測改走
  work-sources.md「找 store 內部的重複」的三訊號謂詞（**標題 ∧ 年份 ∧ type**：
  正規化標題實測另抓到 31 組 DOI 抓不到的；標題同、年份不同是版本沿革不是重複。
  DOI 覆蓋率實測僅 62%——這桶不是邊緣案例）

### 3. 同篇雙列偵測（DOI 分組）

同 DOI 的列分成一組，每組分類：

| 型 | 特徵（實測） | 保留建議 |
|---|---|---|
| **early-access 對** | 一列標題尾端塞了日期/DOI（如 `…(Sep, 10.1007/…, 2025)`），另一列乾淨 | 留正式版列 |
| **erratum 對** | 一列帶卷頁附註（如 `…(vol 35, pg 21, 2025)`）——那是勘誤條目 | 兩列**都匯入**（related 是 work↔work 的 citekey 邊，兩筆都存在才連得起來）；匯入後用 `akashic link` 互指 |
| **單純重複** | 兩列實質相同（含作者欄拼寫損壞的變體，如姓名被亂碼化） | 留欄位較完整的一列 |

**認不出型的交人**——三型是實測見過的，不是窮舉；新變體標「無法分類」讓使用者裁決，
不要硬塞進最像的一型。

### 4. 機構欄容錯（分母的另一半）

機構欄比對決定「哪些列算本機構的成果」——與雙列偵測同屬分母問題：那邊算「幾篇」，
這裡算「哪些篇算數」。機構名的誤植真實存在於文獻（正式名稱單數、出版商頁印複數
都發生過）——比對用正規化＋容錯，命中後回原文查證；判準與實例見 person-verify 的
[verification-traps.md](../akashic-verify-person/references/verification-traps.md) 第 2 節。

**產出**（進 step 5 報告）：機構欄命中 m 列、疑義 p 列（僅正規化後才命中／完全
不命中但作者似本機構人員），疑義逐列列出、待回原文查證。

### 5. Intake 報告 → 人確認 → 匯入

報告格式（給人裁決用，計數要能對帳）：

```
清單列數 N → DOI 補查：已有 a、補到 b、查無 c（a+b+c=N）
同篇雙列：k 組（early-access x、erratum y、重複 z、無法分類 w）
機構欄：命中 m 列、疑義 p 列（疑義逐列附原文）
建議實際篇數：N − early-access／重複組多出的列數（erratum 組兩列都匯入，不減）
每組雙列：兩列原文並排 + 型別 + 保留建議
```

**雙列的處置是編目判斷**——逐組經使用者確認（保留哪列、erratum 是否兩列匯入＋
link），絕不靜默丟列。確認後的交接是**檔案**，不是口頭：

1. 確認後的清單**另存 TSV**（移除被裁列；補查到的 DOI 已在 `DOI` 欄）——
   `import-wos` 只吃 tab-delimited（逗號分隔加 `--csv`），**不吃 xlsx**；
   原始 xlsx 原樣留存當 provenance
2. `akashic import-wos <該 TSV> --dry-run`——把 created／enriched／conflicts／
   droppedColumns 一起呈給使用者。「丟棄必須可見」的實現處在 **import report**，
   不在本 skill 的清單報告；乾跑紀律同 bootstrap（一定要做）
3. 使用者點頭才去掉 `--dry-run` 真正寫入；被裁掉的列在 intake 報告裡留檔

## 邊界

- 本 skill 管**清單層**（列 vs 列）；單篇的欄位補完、作者歸戶是
  [akashic-bootstrap](../akashic-bootstrap/SKILL.md) 與
  [akashic-verify-person](../akashic-verify-person/SKILL.md) 的事，常接續使用
- 匯入後的 store 內重複由 `akashic doctor` 負責（#94 起兩道檢查：正規化 DOI
  共用組——全前綴變體、大小寫不敏感——＋同標題同年不同 DOI；warning 報告不合併、
  指向 record-divergence）。本 skill 是匯入**前**的閘，兩者互補：事後安全網只能
  **報告**、不能替你在匯入前定分母——「無法分類」的組仍要在本閘交人，別留給事後
- 清單欄位 → store 欄位的對映屬 `import-wos` 本體（無損契約），本 skill 不重述

## 相關

- [`akashic-bootstrap`](../akashic-bootstrap/SKILL.md)——逐筆實體的補完；本 skill 是它上游的清單層 QA 閘
- [`assertions-must-be-measured`](../../rules/assertions-must-be-measured.md)——**intake 報告裡的每個計數與每次 Crossref 判定都受它管**：查得到就寫查到什麼、查不到就寫「在哪些來源、以什麼查詢、哪一天查無」，不寫「應該是」。分母定案是人要照著行動的數字，過寬的斷言會直接流進下游統計
- [`source-of-truth-over-consent`](../../rules/source-of-truth-over-consent.md)——匯入檔與 Crossref 對不上的欄位列為歧異、不擅選；使用者同意匯入，不等於同意寫入錯的值
