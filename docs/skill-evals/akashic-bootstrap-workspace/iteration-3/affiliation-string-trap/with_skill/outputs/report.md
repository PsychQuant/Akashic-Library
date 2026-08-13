# 作者機構判定報告 — fixtures/affiliations.json

**性質**：純分析作業。未寫入任何 store，未呼叫任何 `akashic_*` 指令。

## 資料來源與範圍

- 輸入：`fixtures/affiliations.json`，1 篇論文（DOI `10.1000/demo.2025.1`）、4 位作者的機構字串。
- `10.1000/demo.2025.1` 是 DOI 的測試前綴，不對應可解析的真實文獻，因此本次判定**完全基於題目給定的機構字串本身**做內部證據推理，未做外部 API 查證（Crossref／Europe PMC／ORCID 等）。
- 判準依據：`references/work-sources.md`「機構字串裡出現機構名 ≠ 那是作者的隸屬」一節的四類判定表，並套用 SKILL.md 的反例檢核（「如果他不是所內人員，字串會長什麼樣」）：

  | 類型 | 判定 |
  |---|---|
  | 該機構是唯一機構 | 隸屬 ✓ |
  | 該機構排第一、另有其他 | 大致可判隸屬 ✓ |
  | 該機構排在其他機構之後 | ⚠ 合聘與掛名在字串上長得一樣，分不出來 |
  | 該機構名出現在學程／中心／計畫的名稱裡 | ✗ 不是隸屬 |

## 逐位判定

### 1. Wu HJ — 判定：**是**（高信心）

機構字串（唯一一筆）：
> `Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.`

**理由**：ISS 是列出的唯一機構，屬四類判準第一類（唯一機構→隸屬 ✓）。反例檢核：若他不是所內人員，通常不會只列這一個機構、又用標準「所、院、市、國」位址格式呈現——找不到會產生這個字串卻不是隸屬的合理替代情境。

### 2. Chang ML — 判定：**否**（機構字串陷阱，非個人隸屬；高信心）

機構字串：
1. `Institute of Plant and Microbial Biology, Academia Sinica, Taipei, Taiwan. mlchang@gate.sinica.edu.tw.`
2. `Bioinformatics Program, Institute of Statistical Science, Taiwan International Graduate Program, Academia Sinica, Taipei, Taiwan.`

**理由**：第二筆字串中「Institute of Statistical Science」夾在「Bioinformatics Program … Taiwan International Graduate Program」之中，屬四類判準第四類——研究所名出現在學程／計畫名稱裡，判定為 ✗ 不是隸屬（這正是 `work-sources.md` 中原樣引用的真實案例，字串幾乎逐字相同）。加上她的第一機構明確是「Institute of Plant and Microbial Biology」並附有 email——兩個獨立訊號一致指向她本人的機構是 IPMB，ISS 只是 TIGP 生物資訊學程的主辦（合辦）單位之一，不代表她本人隸屬 ISS。

**不建議**把 ISS 記進這位作者的 person 記錄。

### 3. Fischer K — 判定：**無法單靠字串判定，需人工查證**（待人工判定）

機構字串：
1. `Department of Mathematics, ETH Zurich, Switzerland.`
2. `Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.`

**理由**：ISS 排在另一機構（ETH Zurich）**之後**，屬四類判準第三類——合聘與掛名在字串上長得一樣，分不出來。這條字串本身乾淨（沒有 Program/Center 之類的修飾詞包住 ISS，不是第 2 位作者那種陷阱），但無法排除兩種同樣合理的情境：
  (a) 她在 ISS 確有正式合聘／訪問職位；
  (b) 她以 ETH Zurich 為主要身分，因這篇論文的資料蒐集或合作發生於到訪 ISS 期間而順帶列出（掛名性質）。

兩者在字串層次無法區分。**建議**：查她的 ORCID employment 紀錄，或 ISS 官方訪問學者／合聘名冊，確認後再決定是否記進 person 記錄；不要僅憑此字串下判斷。

### 4. Lee SY — 判定：**可能是**（中高信心，非唯一機構）

機構字串：
1. `Institute of Statistical Science, Academia Sinica, Taipei, Taiwan.`
2. `Department of Public Health, National Taiwan University, Taipei, Taiwan.`

**理由**：ISS 排在**第一位**、後面接著另一機構（NTU 公衛系），屬四類判準第二類——大致可判隸屬 ✓。反例檢核：若他本人的機構其實是 NTU、只是與 ISS 研究者合作，這篇論文通常會把 ISS 字串記在別的作者名下（例如本例的 Wu HJ），而不會把 ISS 列成 Lee SY 自己的第一機構；把 ISS 放在本人字串首位，較合理的解讀是這確實是他的機構之一（可能合聘、雙聘，或近期轉換單位）。信心不到 Wu HJ 那種「唯一機構」等級，仍建議之後補查 ORCID 或本人網頁確認是否為現職。

## 總表

| 作者 | ISS 隸屬判定 | 依據類型（四類判定表） | 信心 |
|---|---|---|---|
| Wu HJ | 是 | 唯一機構 | 高 |
| Chang ML | 否 | 機構名夾在學程／計畫名稱裡（陷阱） | 高 |
| Fischer K | 待查證 | 排在他機構之後 | 低 — 需外部核對 |
| Lee SY | 可能是 | 排第一、另有其他 | 中高 |

## 提醒

- 本報告純為分析，未寫入任何 store、未呼叫任何 `akashic_*` 指令。
- Chang ML 與 Fischer K 若之後要真的補進 person 記錄，依 SKILL.md 步驟 4 的判準都屬於「挑出來的」判斷（尤其 Fischer K 需額外查證），寫入前應走乾跑並取得使用者明確同意再處理。
- Wu HJ、Lee SY 的隸屬記錄若要寫入，仍建議走一次「反向驗證」或 ORCID 交叉核對再定案，不必因為信心較高就跳過驗證步驟。
