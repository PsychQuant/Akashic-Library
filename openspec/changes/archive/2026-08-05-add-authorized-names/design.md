## Context

`docs/store-format.md` §3 有一句被埋在註解裡的規格：「`names` 的第一個是顯示名」。它是本 store 目前唯一的 authorized-form 機制，而且它是**位置式**的——語意由陣列索引承擔，型別是 `[String]`，`validate` 不查、`doctor` 不報。

六個 consumer 讀 `names.first` 當顯示名：MCP 的人物查詢、`.bib` 匯出、CSL-JSON 匯出、關聯式匯出（兩處）。也就是說**陣列的第 0 個元素決定了對外發佈的書目裡印出的作者名**。

實測全 store 868 位 person 的 `names.first`：

| 形態 | 人數 | 佔比 |
|---|---:|---:|
| 引用形（`姓, 名` 逗號倒置） | 734 | 84.6% |
| CJK 本名 | 134 | 15.4% |
| 自然語序 | 0 | 0% |

「引用形」指索引系統（Web of Science 的 Author Full Names 欄、Crossref 的作者欄）對名字做的機械變換。沒有人以 `Guan, Yongtao` 這種形式自稱。

破壞已經真實發生：2026-08-05 一個外部 pipeline 為了縮小 diff 而把 store 既有的 names 排到最前面，於是一位人員的顯示名從本名變成引用形，而寫的人不知道 `names` 的第 0 個位置有語意。

**約束**：

- `docs/store-format.md` §5.0 的 bump 準則是硬的：additive 變更 MUST NOT bump，欄位語意變更 MUST bump。
- `YAML.swift` 的 `requireShape` 對 known 欄位的形狀不符 fail-closed（其註解的實測案例逐字就是 `person.names`）。同一段註解明言「較新 schema 把既有 key 變豐富（如 names: sequence → mapping）時，舊 binary 的 RMW 會把該欄位整段靜默剝除；known 欄位的形狀演化不入 tolerant 範圍」。
- CLI、MCP、App 是各自獨立的 binary，format marker 的 refuse-if-newer 是它們之間唯一的同步機制。

## Goals / Non-Goals

**Goals:**

- 讓「哪個名字對外」成為一個顯式的、可驗證的欄位，而不是陣列位置。
- 同一個人可以在不同書寫系統各有一個對外名字（中文報表印中文名，英文書目印羅馬化名）。
- 缺少對外名字時**可被發現**，而不是靜默退化成引用形。
- Person 與 Organization 對「哪個名字對外」給出同一種答案。

**Non-Goals:**

- **不**把「名字 vs 引用形」的分類存進 store。分類是字串上的純函數（逗號倒置、given 部分全縮寫），存下來等於製造第二個會過期的事實。分類只用於 migration 的提名與 `doctor` 的報告。
- **不**把 Person 的 `names` 升成時間軸。改名（婚後、法定更名）與書寫系統是正交的兩軸，塞進同一個 timeline 會重演本 change 要修的錯誤。時間軸留給後續變更。
- **不**處理機構名稱字串的正規化（228 種寫法、含地址的引用形）。那是機構側的辨識問題，判準與人不同。
- **不**自動判定兩筆記錄是否為同一人。身分解析在本 change 之外；authorized form 是身分**確定之後**的指定。

## Decisions

### D1：`authorized` 是 `names` 的子集（list），不是以 script 為鍵的 map

```yaml
names:
- 謝叔蓉
- Shwu-Rong Grace Shieh
- "Shieh, Grace S."
authorized:
- 謝叔蓉
- Shwu-Rong Grace Shieh
```

**替代方案**：`authorized: {Hant: 謝叔蓉, Latn: Shwu-Rong Grace Shieh}`。查找 O(1)、自我說明。

**不選的理由**：map 的鍵可以與值的實際書寫系統**不一致**（有人會寫成 `{Latn: 謝叔蓉}`），憑空多出一類不一致需要驗證。list 形式下 script 是算出來的，不可能與值衝突。本 change 的整個論點就是「不要讓表述承擔它承擔不了的語意」，儲存一個可推導且可能說謊的鍵與該論點相違。

### D2：script 是推導值，不儲存，且只需 Han / Latn 粗分割

**替代方案**：每筆名字存 ISO 15924 四字碼（`Hant` / `Jpan` / `Latn`）。

**不選的理由**：script 只用來切分**同一個人**的名字。沒有人同時擁有中文名與日文名，所以 `Jpan` 與 `Hant` 的區別在這個用途上不存在——森元俊成的漢字與謝叔蓉的漢字落在同一桶，而他們是不同的人，永不相遇。改用封閉 enum 則重演既有的「往封閉集合加成員缺少相容性決定」問題。

推導規則：字串含 CJK 統一表意文字 → `han`，否則 → `latn`。無法歸類者歸 `other`（不阻擋，`doctor` 可報）。

### D3：`names` 的順序不再帶語意，且**不**保留位置式 fallback

顯示解析：

```
displayName(script) =
  1. authorized 中書寫系統相符者
  2. 任一 authorized（順序未定義，因此不變式要求 script 內唯一）
  3. key
```

**替代方案**：第 3 步 fallback 回 `names` 的任一元素，讓沒有 authorized 的人仍印得出人名。

**不選的理由**：那正是位置式約定本身。留著它，「哪個名字對外」就仍有兩個答案，consumer 各讀各的，而 84.6% 的問題不會被任何機制推動修復。退到 `key`（`guan-yongtao`）雖然難看，但**難看是可見的**——靜默印出引用形不是。

### D4：format marker 由 4 bump 到 5

**apply 期間更正（2026-08-05）**：本節初稿寫「2 → 3」，那是照 `docs/store-format.md` §5.0 的
版本對照表寫的，而該表停在 `format: 2`。實際的 `StoreVersion.supported` 是 **4**——格式 3
（裸標籤）與 4（organization 形狀 + 隸屬升為指涉／字面）都發生過但沒有回寫該表。正確的
bump 是 **4 → 5**，且本 change 順帶把 §5.0 的對照表補齊到 5。

`names[0]` 的語意變更屬 §5.0 的 non-additive。舊 binary 若讀新 store，會繼續把 `names[0]` 當顯示名——那是**按舊語意解讀新格式**，正是 refuse-if-newer 存在的情境。

同時，`authorized` 欄位本身對舊 binary 是未知欄位，會被 tolerant-preserve 逐字保留；但保留不等於遵守——舊 binary 的 RMW 可以在保留 `authorized` 的同時重排 `names`，破壞不變式而不自知。bump 是唯一能擋住這條路的機制。

### D5：Migration 是機械提名 + 人工採納，不是自動決定

`authorized` 是指定，不是推導。但提名可以機械化，而且判斷只在候選多於一個時才發生：

| 情況 | 處置 |
|---|---|
| 某書寫系統只有一個候選 | 直接採用（沒有可挑的餘地，不構成判斷） |
| 某書寫系統多個候選，其中恰一個非引用形 | 提名該非引用形 |
| 仍然多於一個候選 | 留空，`doctor` 報出 |

形狀與既有的補資料紀律一致：答案唯一就做，多選一就停下給人看。migration 工具預設 dry-run，`--apply` 才寫。

### D6：`authorized` 選填；缺席是 `doctor` 的報告項，不是 `validate` 的錯誤

實測 734 位目前無法被稱呼。設為必填會讓 migration 當下產生 734 個違規，等於把 store 變成無法通過驗證的狀態，而修復所需的資訊（正確的對外名字）**無法自動取得**。

`validate` 只守形狀不變式（子集、script 內唯一）；「有沒有」交給 `doctor`。

### D7：Organization 沿用同一個 `authorized` 概念，但**保留**其 `names` 的時間軸

Organization 的 `names` 是 `TimelineOf<String>`，因為機構改名之後舊記錄仍指向同一 identity。這與書寫系統正交，兩者都要保留：`authorized` 從**當前有效**的名稱集合中選取。

Organization 的 `displayName` 因此變成：script 相符的 authorized → 任一 authorized → `names.current` → `key`。保留 `names.current` 這一階是因為它**不是位置式**——它是有語意的時間查詢，不是本 change 要廢除的東西。

## Implementation Contract

### 觀察得到的行為

1. 一筆 person 記錄可以宣告哪些名字是對外的；宣告的形式是 `names` 的子集。
2. 匯出書目（`.bib`、CSL-JSON）、MCP 的人物回應、關聯式匯出，印出的是 authorized form；沒有 authorized form 時印出 `key`，不再印引用形。
3. 讀取 format marker 大於本 binary 支援上限的 store 時，在逐檔 decode 之前整體拒絕，訊息點名兩個版本數字。
4. `doctor` 報出「沒有任何 authorized form」的記錄清單。
5. `validate` 對違反子集或 script 內唯一的記錄拒絕通過。

### 資料形狀

person 與 organization 記錄新增選填的頂層鍵 `authorized`，值為字串序列。形狀不符（非序列）時 fail-closed，與既有 `names` 的處理一致。

`Person` 與 `Organization` 各提供一個以書寫系統為參數的顯示名解析函式，其解析順序如 D3 / D7 所述。書寫系統的推導提供為一個純函式，輸入字串、輸出 `han` / `latn` / `other` 三者之一。

store 根目錄的 format marker 檔內容由 `format: 4` 改為 `format: 5`。

### 失敗模式

| 情況 | 行為 |
|---|---|
| `authorized` 含不在 `names` 內的字串 | `validate` 拒絕，訊息點名該字串與所屬記錄 |
| 同一書寫系統有兩個 authorized | `validate` 拒絕，訊息點名該書寫系統與兩個候選 |
| `authorized` 形狀不是序列 | decode fail-closed（quarantine），與 `names` 同 |
| `authorized` 缺席或為空 | 合法。`displayName` 退到 `key`，`doctor` 列入報告 |
| 舊 binary 讀 `format: 3` 的 store | 整體拒絕載入（既有 refuse-if-newer 機制） |
| migration 遇到多於一個候選且無法以引用形分類區分 | 該書寫系統留空，列入報告，不猜 |

### 驗收條件

- 新增測試檔涵蓋：子集不變式、script 內唯一不變式、`displayName` 的四階解析（含退到 `key`）、書寫系統推導（漢字、羅馬字、混合）、`authorized` 缺席時的行為、形狀不符時 fail-closed。
- 既有測試全數通過，且**六個 consumer 的測試不得再斷言 `names.first`**。
- `swift test` 全綠。
- 對真實 store 執行 migration 的 dry-run。**逐人**的四類計數（全部指定完 / 仍有歧義 / 無可用名字 / 原本已指定）互斥且窮盡，加總等於 person 記錄總數；逐書寫系統的採用／提名／留空計數不可直接相加（雙語者同時貢獻多筆）。
- `docs/store-format.md` 的 §3 不再含「第一個是顯示名」，§5.0 的版本對照補齊 `format: 3`／`4`／`5` 三個缺漏條目。

### 範圍邊界

**在範圍內**：person 與 organization 的 `authorized` 欄位與其驗證、書寫系統推導函式、顯示名解析、六個 consumer 的改讀、format marker bump、migration 工具、`doctor` 檢查、規格文件更新。

**不在範圍內**：身分解析（判定兩筆記錄是否同一人）、機構名稱字串的正規化、Person names 的時間軸化、引用形分類的持久化、外部寫入者（store 之外的 pipeline）的對應改動。
