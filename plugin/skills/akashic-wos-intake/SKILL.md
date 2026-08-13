---
name: akashic-wos-intake
description: WoS 匯出清單的匯入前 QA——DOI 補查、同篇雙列偵測（early-access／erratum／重複收錄）、機構名誤植容錯，產出 intake 報告經人確認後才交給 import-wos。當使用者拿到一份 WoS 格式的 Excel/CSV 清單（「所方給的成果清單」「這批要進 Akashic」「這份 WoS 匯出先整理一下」）、或說「先檢查這份清單有沒有重複」「補一下 DOI」時使用。清單的分母（實際篇數）在這一步定案——不做這步就匯入，重複列會流進下游統計。與 akashic-bootstrap 的分工：本 skill 是清單層的 QA 閘（列 vs 列），bootstrap 是逐筆實體的補完（查證單篇/單人）。
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

### 2. DOI 補查（缺 DOI 的列）

以**合取**判準查 Crossref：標題＋第一作者姓＋期刊＋年份同時相符才收。

- **標題相似度單獨不可信**——preprint 版的標題相似度可以比正式版還高；
  「像但不是」的三種記錄形態與合取判準的細節見 akashic-bootstrap 的
  [work-sources.md](../akashic-bootstrap/references/work-sources.md)，不在此複製
- 查到的 DOI 記回該列（新欄位，不覆寫任何原欄位）；查不到就標「無 DOI」——
  那是誠實狀態，不擋匯入，但雙列偵測對它退化為人工比對

### 3. 同篇雙列偵測（DOI 分組）

同 DOI 的列分成一組，每組分類：

| 型 | 特徵（實測） | 保留建議 |
|---|---|---|
| **early-access 對** | 一列標題尾端塞了日期/DOI（如 `…(Sep, 10.1007/…, 2025)`），另一列乾淨 | 留正式版列 |
| **erratum 對** | 一列帶卷頁附註（如 `…(vol 35, pg 21, 2025)`）——那是勘誤條目 | 兩列**都**有意義（原文＋勘誤）；預設留原文列、勘誤記為 related |
| **單純重複** | 兩列實質相同（含作者欄拼寫損壞的變體，如姓名被亂碼化） | 留欄位較完整的一列 |

**認不出型的交人**——三型是實測見過的，不是窮舉；新變體標「無法分類」讓使用者裁決，
不要硬塞進最像的一型。

### 4. 機構欄容錯

機構名的誤植真實存在於文獻（正式名稱單數、出版商頁印複數都發生過）——機構欄比對
用正規化＋容錯，命中後回原文查證；判準與實例見 person-verify 的
[verification-traps.md](../akashic-person-verify/references/verification-traps.md) 第 2 節。

### 5. Intake 報告 → 人確認 → 匯入

報告格式（給人裁決用，計數要能對帳）：

```
清單列數 N → DOI 補查：已有 a、補到 b、查無 c（a+b+c=N）
同篇雙列：k 組（early-access x、erratum y、重複 z、無法分類 w）
建議實際篇數：N − 每組多出的列數
每組雙列：兩列原文並排 + 型別 + 保留建議
```

**雙列的處置是編目判斷**——逐組經使用者確認（保留哪列、勘誤要不要記 related），
絕不靜默丟列。確認後才執行 `akashic import-wos`（或逐筆走 bootstrap）；被裁掉的列
在報告裡留檔，「丟棄必須可見」。

## 邊界

- 本 skill 管**清單層**（列 vs 列）；單篇的欄位補完、作者歸戶是
  [akashic-bootstrap](../akashic-bootstrap/SKILL.md) 與
  [akashic-person-verify](../akashic-person-verify/SKILL.md) 的事，常接續使用
- 匯入後的重複偵測（store 內 DOI 共用）由 `akashic doctor` 負責——本 skill 是
  匯入**前**的閘，兩者互補不重疊
- 清單欄位 → store 欄位的對映屬 `import-wos` 本體（無損契約），本 skill 不重述
