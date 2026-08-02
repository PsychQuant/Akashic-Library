## Context

`docs/design-principles-and-philosophy.md` 是本專案的 normative 哲學文件（20 節，Part I 規範、Part II 哲學基礎，各規範節帶「### 規範」子節）。

**實作前重讀文件後修正了本 change 的前提**（原稿把缺口歸給 §3，那是找錯地方）：

真正的缺口在 **§11 的 Entity admission rule**。它明文寫著：

> 一個概念只有在符合下列**多數條件**時，才 SHOULD 升格為一級 entity：(1) 跨紀錄穩定身分 (2) 改名後仍是同一物 (3) 有自己的生命週期或歷史 (4) **能成為多種關係的端點** (5) 需要獨立查詢、引用或裁決 (6) 已有反覆出現的實際使用案例。

一個 view 定義對這六條的得分是 **5 比 1**——唯一不符的正是第 4 條。**在多數決之下，文件自己的規則會核准 view 升格為 entity。** 2026-08-02 的 #54 因此不是誤讀規則，是照著規則走：AI 提議 `entities/<uuid>.yaml` 加 `type: view`，使用者糾正「view 不是 entity 吧，他是 index 吧」。

§3 的六項（獨立存在、穩定身分、可變名稱、自己的歷史、成為多種關係的端點、被獨立搜尋引用裁決）是對 Person／Work 的**描述**，不是准入規則。它沒有宣稱充分性，所以它不是缺口所在。

其餘兩個缺口：

1. **§2 的核心詞彙「事態」逐字是 Tractatus 的 Sachverhalt**，而 §14 已經引用《邏輯哲學論》並鋪陳圖像論——但 §2 沒有指向 §14，讀者在讀到該詞時無從知道它是精確借用。缺的是**交叉引用**，不是新論證。
2. **沒有任何規範說明 predicate 的定義域該住在哪裡**。目前程式碼做對了（`Entry` 沒有 affiliations 欄位、`Person` 沒有 relations 欄位），但這是慣例而非規則，下一次擴充可以用一張通用邊表推翻它而不違反任何成文規範。

再往下追一層發現：**schema 也犯了同型的範疇錯誤**。`type:` 這一個 key 同時裝著形式種類（`person`，決定用哪個 decoder）與書目類型（`article`，固定形狀裡的一個值）。實測確認：`type: view` 的檔案通過 `akashic validate`，並被 `doctor` 計為一篇著作。該缺陷由獨立 change 修復；本 change 只寫下它必須遵守的規範。

**與 §16 的關係（必須明說，不得靜默推翻）**：§16「規則無法唯一決定所有未來應用」明確反對「一套自稱最終的 domain rule」，並舉「一個研究領域是 tag 還是 Concept」為無法自動裁決的例子。本 change 新增的 MUST NOT **不與它衝突**，因為兩者管的不是同一件事：§16 管的是**真正的概念**之間的 domain 取捨（課程／學期／研究領域該不該是 entity），那確實需要先例與實踐；本 change 管的是**形式概念**能不能進入 entity namespace，那是層次問題，不是 domain 取捨。條文必須自帶這個界線說明，否則會被讀成推翻 §16。

## Goals / Non-Goals

**Goals:**

- 讓「什麼算 entity」有一條**可操作、可引用**的判準，而不是六條可任意取用的特徵。
- 讓 §2 / §4 / §7 的 Tractatus 出處可見，使讀者知道詞彙是精確借用。
- 讓下一個提議「把某個形式概念放進 `entities/`」的人（或 agent）被文件擋下，而不是靠人記得。
- 把「predicate 的定義域由欄位位置顯示」從慣例升格為規範，使既有的正確做法不會在下一次擴充時被無聲推翻。

**Non-Goals:**

- **不實作 view 機制**（#54 追蹤：判準放 `config.yaml`、外延進 index）。
- **不改任何 code**——`Sources/` 零影響，無 runtime 行為變更。判別測試雖然引用 decoder 的分岔行為，但只是**觀察**既有程式碼，不修改它。
- **不引入 `kind:` 欄位、不引入 organization 形狀、不改 affiliation 的型別**。那些是獨立 change 的範圍；本 change 只寫下它們必須遵守的規範。
- **不把 `libraries/` 併進 `entities/`**（#35 收尾；且 library 的定義屬 §7 的 Adjudication 層）。
- **不做成 lint rule**。判準是給人讀的規範。

## Decisions

### D1：判別性條件是「decoder 是否為它分岔」，且它是**必要條件**，不參與多數決

§11 現行的 admission rule 是六條的**多數決**。本 change 主張其中對應「能成為多種關係的端點」的那個層次的條件必須升格為**必要條件**——不滿足它，其餘五條全中也不得升格。

判準本身改寫得更鋒利：不是「能否成為關係的端點」（那是徵候，且可被「那我加一條關係」反駁），而是**它是否決定了哪些欄位存在**，可操作的形式是載入器是否為它分岔到不同的 decoder。**判準與「形狀在檔案裡怎麼被標示」無關**——標示機制可以改（見獨立 change），判準不變。

| 候選 | decoder 分岔？ | 弄錯的後果 | 是 entity 嗎 |
|---|---|---|---|
| person / work | 是（分岔到不同 decoder） | **結構錯誤**——person 沒有 citekey，work 沒有職級時間軸。整份檔的形狀錯，改不動 | 是 |
| `article` / `book` | 否（同一個 decoder） | **事實錯誤**——改一個欄位即可，記錄其餘部分意義不變 | 否，它是屬性值 |
| view | 否，而且沒有形狀可分岔到 | — | 否 |

理由：切點落在「這個值決定哪些欄位存在」的高度。在它之上，種類不是關於那個東西的事實，而是**你用來談它的句子的形狀**；在它之下，它只是固定形狀裡的一個值。第二個支持理由：切點之下的分類法（`article` / `incollection`）是 BibLaTeX / Zotero 的，會在本專案沒同意的情況下改；切點之上是本 store 自己的承諾。

**替代方案（已否決）：維持多數決、只把第 4 條的措辭改清楚。** 否決理由——#54 的得分是 5 比 1，措辭再清楚也會被其餘五條輾過。多數決本身就是缺陷：它把一個層次問題當成程度問題來投票。

**替代方案（已否決）：用「能不能從 canonical files 重建」當判準。** 那是 §5 的 index 判準，答案會是「view 的判準推不回來 → 所以是 canonical → 所以是 entity」，正是 #54 原版犯的錯。**「推不回來」只證明它不是 derived data**；第三個可能性是「它是設定」。

### D2：規範用 MUST NOT，不用 SHOULD NOT

它防的失敗是結構性的：形式概念一旦進入 `entities/`，載入器就會把它 decode 成某種既有形狀（實測：`type: view` 被當成 work 並通過 validate）。這不是品味問題。

### D3：Tractatus 出處寫進哲學文件，完整論證寫進 explainer

沿用 #52 建立的分工——**規格說 what，explainer 說 why**。

- 哲學文件（normative）：一段**簡短**出處說明（Sachverhalt、形式概念 vs 真正的概念、內在關係），讓讀者知道詞彙是精確借用。
- explainer（非 normative）：完整論證，包含 Tractatus 4.126 / 4.1272 / 4.1212 / 4.124–4.125 / 3.333、後期的 Aspektsehen 與表層／深層文法、以及 #54 的實測失誤過程。

**替代方案（已否決）**：把完整論證塞進哲學文件。否決理由——那份文件的每一節都以「### 規範」收尾，讀者是來找 MUST / SHOULD 的。

### D4：以 #54 的實測失誤作為文件裡的具體案例

抽象規範容易被「這次不一樣」繞過。文件裡放一個**真的發生過**的誤判（連同它當時看起來為什麼合理），比純抽象敘述更能擋下同型錯誤。

### D5：predicate 以欄位形式住在適用的形狀上，不得有通用邊表

一個 predicate 適用於哪些形狀（它的定義域），SHALL 由**哪些形狀帶有那個欄位**來表達，不得表達成資料。

現況已經是對的，本 decision 只是把它寫下來：`Entry` 沒有 affiliations 欄位——「隸屬不能用來形容 work」這件事沒有任何一行程式碼在陳述它，它由欄位的缺席所顯示。同理 `Relations { cites, related }` 只掛在 `Entry.akashic` 上，`Person` 沒有。

依據 Tractatus 4.125：可能情境之間的**內在關係**，透過表達它們的**句子之間的內在關係**表現出來。predicate 之間的關係是內在關係，因此不能再用一個 predicate 去說它。

**替代方案（已否決）：通用邊表 `relations(subject, predicate, object)`。** 三元組把所有 predicate 變成平輩、所有實體變成平輩，正如 `String` 把指涉與標籤變成平輩、`type:` 把形式種類與書目類型變成平輩——同一個攤平錯誤的第三次。在三元組裡沒有東西阻止 `(article-uuid, affiliated-with, org-uuid)`：它不會壞，它會被接受。

**替代方案（已否決）：加一張 `predicate_domain(predicate, allowed_subject_kind)` 表來擋。** 正中 4.1272——把形式概念當成真正的概念來用。那張表存在的當下，「擴充一個 predicate 的定義域」與「新增一筆事實」變成同一個動作（一個 INSERT），文法變更與主張再也無法區分。

**誠實邊界（PI 371 / 373）**：這些定義域限制不是形上學必然，是本 store 的**文法規則**，會隨實踐改變。若哪天真的需要記錄「這本書由哪個機構的出版社出版」，`Entry` 就該長出機構欄位——那不是破例，是文法變了。工程推論：**改一條規則的代價應配得上它的邏輯地位**。定義域住 schema 裡 → 擴充它要改 struct + 遷移 + bump store format，這是對的，因為那本來就是改文法。

圖／三元組表示 MAY 作為**衍生**產物存在（與 DuckDB 匯出同一地位，#20 已拍板）。衍生層可以攤平，因為可重建 ⇒ 攤平的損失可回復。

## Implementation Contract

**Behavior**：

1. 任何人或 agent 提議把一個形式概念（view / 分類 / 查詢 / 索引結構）放進 `entities/<uuid>.yaml`，能在 §3 找到一條**可直接引用的 MUST NOT** 與一個判別測試（「decoder 會為它分岔嗎？」）。
2. 任何人或 agent 提議引入通用邊表或 predicate 的 meta-schema，能在 §7 找到一條可直接引用的 MUST NOT。

**Interface / data shape**：無。純文件，不引入 schema、CLI 旗標或函式。

**Verification**：
- `docs/design-principles-and-philosophy.md` §11 的 Entity admission rule 不再是純多數決：形狀選擇條件為**必要條件**，且該節含一條以 MUST NOT 表述的形式概念禁令。
- 同節條文自帶與 §16 的界線說明（本規則管形式概念的層次問題，不管真正概念之間的 domain 取捨）。
- §3 含一行指向 §11 的准入規則，使從 §3 的六項描述出發的讀者被導向正確位置。
- 同文件 §7 的「### 規範」子節含一條以 MUST NOT 表述的 predicate 定義域規則（欄位位置顯示、禁通用邊表、禁 predicate meta-schema、圖為衍生層）。
- §2 的「事態」處含一行指向 §14（《邏輯哲學論》圖像論）與 explainer。
- `docs/explainers/entity-vs-view.md` 存在，且含 #54 的實測案例（原始誤判 + 為什麼當時看起來合理 + 正確位置）；其哲學段落**引用 Part II 既有各節，不重複推導**。
- 既有節次編號（§1–§20）與既有規範條文除 §11 的准入規則外**逐字不變**——本 change 只新增，唯一的改寫是把多數決改為含必要條件。

**Out of scope**：任何 `Sources/` 下的檔案；形狀標示機制（`type:` 的收窄與標籤化由 `add-entity-shape-label` 負責，含 §4 那句「差異由 record 內的 type 表達」的修訂）；organization 形狀；affiliation 的型別變更；#54 的 view 機制實作。
