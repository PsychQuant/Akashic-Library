# Akashic-Library：設計原則與哲學基礎

> 本文件區分兩個層次：
>
> 1. **規範性設計原則**：對 store、identity、time、provenance、adjudication 與 domain evolution 的實作約束。
> 2. **哲學基礎**：說明這些原則為何形成，以及 Akashic 所採取的世界觀與自我限制。
>
> 哲學詮釋不取代具體 spec；具體欄位、格式與 API 仍以各版本的 store-format 與 phase design 文件為準。

---

## 1. 起點：圖書館不是文獻清單

Akashic-Library 的靈感來自一座記錄每一個人過去、現在與未來的圖書館。管理員可以閱讀、尋找與保存紀錄，卻不能任意改寫故事。

因此 Akashic 的目標不是單純取代 Zotero，也不是只建立另一套 bibliographic database。它的核心命題是：

> **人不是書目中的一個欄位；人自己也是館藏。**

傳統文獻系統通常以 Work／Item 為中心，Person 主要作為 creator metadata 存在。Akashic 則把 Person 與 Work 視為對等的一級實體；「作者」不是 Work 內部的一段文字，而是 Person 與 Work 之間的一項關係或事態。

```text
Person ── Authorship ── Work
```

這個原則可以繼續延伸到 Organization、Event、Project、Place、Concept 等型別，但 Akashic 不預先宣稱已經完成整個世界的 ontology。

---

# Part I：規範性設計原則

## 2. 世界的基本可記錄單位是事態，而不是欄位集合

Akashic 不應把資料只建模為：

```text
Entity
├── attribute
├── attribute
└── attribute
```

它應優先辨認：

```text
Entity₁ ── Relation ── Entity₂
              │
            Time
              │
           Context
              │
           Source
```

Entity 提供穩定指涉與同一性的錨點；state of affairs／assertion 則表達世界在特定時間與脈絡中如何成立。

### 規範

- 關係若具有自身屬性、來源、角色、次序、時間或裁決狀態，**SHOULD** 升格為可獨立表示的 relation record，而不是繼續壓縮成單一欄位。
- 不應因自然語言的主詞—述詞表面形式，就預設其中一端是主體、其他內容只是附屬屬性。
- 是否升格為一級 entity 或 relation，必須由實際使用需求與生命週期決定，而不是由名詞形式決定。

---

## 3. 人與作品是對等的一級實體

Person 與 Work 都必須能夠：

- 獨立存在；
- 擁有穩定身分；
- 擁有可變名稱與 aliases；
- 擁有自己的歷史；
- 成為多種關係的端點；
- 被獨立搜尋、查詢、引用與裁決。

一個 Person 不需要先成為某篇 Work 的作者才有資格存在；一個 Work 也不需要作者已完成 identity resolution 才能存在。

### 規範

- 未解析作者 **MUST** 保留原始文字，不得為了結構完整而自動創造 Person。
- 已解析的 authorship **MUST** 指向穩定 Person identity，而不是只保留顯示名稱。
- 長期而言，Person 與 Work **SHOULD** 具備對等的不可變機器身分與可讀 key。

---

## 4. One identity, one canonical file

Akashic 的核心 store invariant 是：

> **一個穩定 identity 對應一個 canonical file；一個 canonical file 只代表一個 identity。**

檔案不是 snapshot，而是該 entity 沿時間展開的 canonical container。

### Canonical path 只編碼不可變身分

一級 entities **SHOULD** 共用單一 canonical namespace：

```text
entities/<uuid>.yaml
```

若單一目錄的檔案量需要物理分散，可以使用不帶語意的 UUID shard：

```text
entities/55/0e/550e8400-e29b-41d4-a716-446655440000.yaml
```

路徑不得編碼：

- entity type；
- domain；
- 所屬機構；
- 階層位置；
- 作者、年份或題名；
- 目前名稱或其他可變描述。

Person、Work、Expression、Manifestation、Organization 與其他一級實體可以存在於同一 namespace。它們的差異由 record 內的 type、relations 與 validation grammar 表達，而不是由資料夾表達。

例如 Work、Expression 與 Manifestation 的階層應表示為關係：

```text
Work ← realized_as ─ Expression ← embodied_in ─ Manifestation
```

而不是固定成巢狀路徑。Entity 可以同時參與多個階層、集合與世界片段；資料夾只能表達單一 containment 軸，不能充當 ontology。

### UUID、designator 與名稱的分工

- UUID 是 canonical machine identity，**MUST** 不可變。
- Canonical designator 是人類可讀的穩定指涉名稱，可用於 CLI、UI 與查詢，但 **MUST NOT** 成為 canonical filename 的必要組成。
- Names、titles、citekeys、DOI、ISBN、ORCID、ROR 與其他外部 identifiers 是名稱使用或外部識別，不等於 Akashic identity。
- Work 可由作者＋年份＋題名產生可讀 designator，但該 designator 不應承擔檔案路徑的身分完整性。
- DOI 可作為高權重的外部 identifier 與 identity-resolution evidence，但 **MUST NOT** 被假定等同於 Akashic Work identity；其 referent 粒度可能是 Work、Expression、Manifestation、chapter、dataset 或其他對象。

### 規範

- 同一 entity 的 aliases **MUST NOT** 各自形成 canonical files。
- 名稱、職級、隸屬、type refinement、版本階層或其他狀態變更 **MUST NOT** 自動產生新 entity file 或搬移 canonical path。
- 跨檔案連結 **SHOULD** 使用 UUID。
- Type、hierarchy、membership 與 domain grouping **MUST** 存在 record／relation 或 derived view 中，不得由 canonical directory layout 暗示。
- 「中研院有關」「某研究計畫相關」「某型別」「某時期」等集合 **SHOULD** 是可重建的 query／view，而不是 canonical folder。
- derived index、search cache、export artifact **MUST NOT** 成為 canonical identity source。

可濃縮為：

> **Canonical paths encode immutable identity only; names, types, hierarchies, and classifications live in records, relations, or derived views.**

---

## 5. 檔案是本體，資料庫是可重建索引

Canonical truth 存在於可讀、可 diff、可版本控制的 store files。SQLite index、Graph cache、BibLaTeX、CSL-JSON、DuckDB 與其他輸出皆為衍生物。

### 規範

- `.akashic/` 下的 index **MUST** 可由 canonical files 重建。
- 刪除 index 不得造成 canonical knowledge loss。
- Export **MUST** 被視為編譯產物，不得成為反向覆寫 canonical store 的默認來源。
- Store mutation **SHOULD** 採 atomic write，避免半寫檔案。

---

## 6. 有意義的變化必須保存歷史

Akashic 不以 Type 1 overwrite 作為有意義歷史的默認策略。

對於機構隸屬、職級、行政職、聘任類型、研究領域、聯絡資訊及其他具有歷史意義的變化，系統 **SHOULD** 採 valid-time／Type 2 語意：舊狀態結束，新狀態新增，而非覆蓋。

```text
同一 Person P
├── rank = postdoc      [t1, t2)
└── rank = professor    [t2, ∞)
```

### 規範

- Entity identity 與 temporal facts **MUST** 分離。
- 不同屬性若具有不同變化節奏，**SHOULD** 擁有各自的時間軸，而不是任何欄位變動都複製整個 entity snapshot。
- 若「世界何時如此」與「圖書館何時得知」不同，模型 **SHOULD** 區分 valid time 與 recorded／transaction time。
- 更正過去認識時，舊認識的 repository history 不得被偽裝成從未發生。

---

## 7. 世界、主張、使用事件與圖書館裁決必須分層

Akashic 至少必須區分：

```text
World entity / state of affairs
  世界中被指涉的存在與事態

Usage event
  某人在某時間、脈絡中使用某個表達

Assertion
  某次使用或來源提出的可判真偽內容

Evidence / source
  支持、反對或產生該主張的材料

Adjudication
  圖書館目前如何接受、拒絕、保留或修正該主張
```

例如來源中的 `Chen, YC` 首先是文字使用或來源紀錄，不等同於一個已確認的 Person entity。

### 規範

- 字串 **MUST NOT** 被直接視為 entity identity。
- Source assertion **MUST NOT** 因為被保存就自動升格為 accepted fact。
- 系統 **SHOULD** 允許 competing assertions、歧義與 unresolved states 共存。
- Provenance **MUST** 能指出資料從何而來，以及哪些欄位由哪一個來源／機制管理。

---

## 8. 不確定性是正式資料狀態，不是髒資料

未知、歧義、衝突與尚未裁決，不是必須盡快消除的資料缺陷，而是知識狀態。

### 規範

- Person resolution **MUST NOT** 自動合併；自動化只可產生候選與證據。
- `literal` 與 resolved key **MUST** 保持不同語意。
- 無法解析的檔案 **SHOULD** quarantine，而不是靜默略過或覆寫。
- 未知欄位在可演化區域 **SHOULD** tolerant-preserve，避免舊 binary 重寫時造成資料剝除。
- 推測 **MUST NOT** 偽裝成已裁決事實。

---

## 9. 來源資料與 Akashic 衍生知識必須有明確 ownership boundary

外部來源、匯入機制、人工裁決與 Akashic 自有 metadata 不得互相冒充。

### 規範

- Zotero、WoS 或其他 importer 僅可更新其明確擁有的 namespace。
- 已由人工解析或裁決的 identity／relation **MUST NOT** 被外部 pull 靜默覆寫。
- Source-owned fields、Akashic-owned fields 與 derived cache **MUST** 可被辨識。
- Importer 對 dropped、unmapped、conflicting fields **SHOULD** 提供可見報告。

---

## 10. 合併是 identity correction，不是建立第二個失效 entity

當兩個 entity files 被裁決為同一 identity 時，合併後 canonical store 應只剩一個 UUID file。

### 正確結果

```text
合併前：
entities/<uuid-a>.yaml
entities/<uuid-b>.yaml

合併後：
entities/<surviving-uuid>.yaml
```

### 規範

- 被保留的 entity file **MUST NOT** 內嵌 `merged_from` 作為永久 domain metadata。
- 被移除的 entity file **MUST NOT** 以 `merged_into` tombstone 留在 `entities/`，否則會破壞 one identity, one canonical file。
- 合併必須遷移所有指向舊 UUID 的 references。
- Git **MUST** 保存實際檔案變更歷史。
- 若未來需要機器可查詢的 identity adjudication history，可另設 `adjudications/` 或 event log；該記錄是圖書館裁決事件，不是另一個 canonical entity。

可濃縮為：

> **Git 保存變更；Akashic 保存變更後的 canonical meaning。**

---

## 11. Domain 可以開放，但 core 必須克制

Akashic 的語意 horizon 可以延伸至 Person、Work、Organization、Event、Project、Concept、LanguageUsage 等領域；但每一個新名詞都升格為 entity，會使 domain 無限膨脹。

### Core 應穩定負責

- identity；
- relation／assertion；
- valid time 與 recorded time；
- provenance；
- uncertainty；
- adjudication；
- canonical file 與 derived index；
- schema evolution。

### Domain modules 可持續新增

- bibliography；
- people；
- organizations；
- projects；
- language usage；
- 其他經實際需求證明的領域。

### Entity admission rule

一個概念只有在符合下列多數條件時，才 **SHOULD** 升格為一級 entity：

1. 需要跨紀錄保持穩定身分；
2. 名稱改變後仍應被視為同一物；
3. 有自己的生命週期或歷史；
4. 能成為多種關係的端點；
5. 需要獨立查詢、引用或裁決；
6. 已有反覆出現的實際使用案例。

若只是「未來可能有用」，應先保留為文字、tag、open field 或 assertion，而不是立即擴張 canonical ontology。

> **World may be the horizon of Akashic, but it must not be the scope of every release.**

---

## 12. Schema 可以在版本內封閉，但不能宣稱窮盡未來

每一個版本必須具有可驗證、可實作的 schema；但 schema 無法預先決定所有未來案例應如何分類。

### 規範

- Current-version schema **MUST** 有明確驗證與行為。
- Ontology **MUST** 保持可演化，而不得宣稱已完成世界的最終分類。
- 新 domain admission **SHOULD** 透過案例、替代方案、實際查詢需求與風險分析裁決。
- 重要 ontology decision **SHOULD** 留下 design rationale、正例、反例與後續修訂歷史。
- Schema evolution 本身也屬於圖書館的歷史，不應被視為無時間的永恆真理。

---

## 13. AI 是管理員，不是作者

Akashic agent／MCP 的角色應接近圖書館管理員：它可以閱讀、索引、尋找、比較、提出候選與指出衝突，但不能擅自把推測寫成事實。

### 規範

AI 可以：

- 搜尋與聚合紀錄；
- 重建 index；
- 提出 identity candidates；
- 顯示 evidence 與 conflict；
- 協助產生待裁決變更。

AI 不可以：

- 在無公開判準下自動合併 entity；
- 隱藏 provenance；
- 把索引或生成文字當成 canonical source；
- 因無法理解紀錄而靜默刪除；
- 將自身信心等同於共同體裁決。

> **管理紀錄，不冒充紀錄的作者。**

---

# Part II：哲學基礎

## 14. 早期維根斯坦：圖書館作為世界的圖像

《邏輯哲學論》的圖像理論提供 Akashic 的結構直覺：

- 世界不是事物的清單，而是事實／事態的總體；
- 圖像由元素構成；
- 圖像元素的排列，表現世界中對象的排列；
- 圖像首先表現可能事態，與現實比較後才為真或假；
- 圖像能描繪世界，是因為圖像與世界共享某種表現形式。

對 Akashic 而言：

```text
Entity                  = 圖像元素
Relation / assertion    = 元素的配置
Schema / ontology       = 可表現形式
Record                   = 可能事態的圖像
Evidence / adjudication = 圖像與世界的比較機制
```

這使 Akashic 的基本語意不是「某個主體有哪些欄位」，而是「哪些元素在何種時間、脈絡與來源下形成何種事態」。

但圖像不能站到自身表現形式之外，完整描繪「它為什麼能描繪」。同樣地，schema 無法以更多 schema 無限奠基自己的所有使用條件。

---

## 15. 後期維根斯坦：圖書館本身也是語言遊戲

Akashic 不只是被動描述世界；一旦使用者開始依照它的分類、規則與裁決方式行動，它本身就形成一個 language game。

`Person`、`Work`、`accepted`、`quarantined`、`same_entity` 的意義，不只存在於規格文字，而存在於人們如何：

- 建立紀錄；
- 使用 key；
- 提出與拒絕 candidates；
- 修正 identity；
- 關閉與新增時間區間；
- 查詢、爭論與解釋資料。

因此 schema 是語法的一部分，但不是完整語言遊戲。語意還依賴制度、訓練、反應、正確性判準與生活形式。

Akashic 是一個第二階語言遊戲：

> **它記錄其他語言遊戲中，人們如何命名、任命、出版、承諾、分類、否認與修正。**

---

## 16. 規則無法唯一決定所有未來應用

後期維根斯坦的規則遵循問題提醒我們：一條有限規則不會自行攜帶所有未來案例的唯一答案。

例如：「具有穩定身分、可跨紀錄重複出現且有自身歷史者，應建模為 entity。」仍無法自動決定：

- 一門課是否是 entity；
- 某學期開課是否另成 entity；
- 一個研究領域是 tag 還是 Concept；
- 一次語言使用是 Event、Assertion、Relation，或數者組合。

再增加一條「解釋規則的規則」也不能終止問題，因為新規則同樣需要應用。

但這不代表任何延伸都同樣正確。規則的約束力來自公開且穩定的實踐：案例、訓練、糾正、先例、目的與共同體裁決。

因此 Akashic 不需要一套自稱最終的 domain rule，而需要：

```text
新案例
→ 對照既有案例
→ 說明相似與差異
→ 比較替代模型
→ 以實際使用驗證
→ 形成可修正先例
```

無法永久封閉不是失敗，而是語言遊戲與生活形式具有開放性的正常結果。

---

## 17. Frege 與維根斯坦：精確語言與語言界線

Frege 從數學與證明出發，追求一套能明確表達客觀思想、揭露邏輯結構並逐步驗證推理的形式語言。這支持 Akashic 對 schema、type、namespace、proof trail 與 validation 的要求。

維根斯坦則把問題推向世界與語言的關係：

- 早期追問命題如何描繪世界；
- 後期追問語詞如何在實際使用中取得意義；
- 一生持續探索語言的邊界，以及語言何時因脫離正常實踐而製造哲學幻象。

Akashic 需要同時接受兩種紀律：

> **Frege 原則：能明確規定的，必須盡可能明確規定。**
>
> **維根斯坦原則：再完整的規定，也不能取代使它具有意義的實際使用。**

---

## 18. 圖書館不能等同於世界

即使 Akashic 保存每一個人的每一次語言使用，也不因此捕捉所有事實。

原因包括：

- 語言使用可以提出錯誤、虛假、過時或反諷的主張；
- 世界中有未被觀察、未被說出或未留下紀錄的事件；
- 不同語言遊戲對「何謂事實」具有不同判準；
- 圖書館本身進入世界後，會產生新的使用、分類與回應；
- 價值、意義與生活本身不能簡化成更多同類型的事實列。

因此 Akashic 的最高目標不應是：

> 收錄所有真理，成為世界的完整副本。

而應是：

> **讓每一項被保存的紀錄，都能追溯它如何被說出、由何而來、指向什麼、何時成立、如何被裁決，以及後來如何被修正。**

圖書館可以無限接近更豐富的世界圖像，但必須保留對自身界線的認識。

---

## 19. 檔案倫理

Akashic 的技術選擇背後是一組檔案倫理：

1. **記錄不應因目前無法理解而消失。**
2. **身分不應因名稱改變而消失。**
3. **現在不應覆蓋有意義的過去。**
4. **推測不應偽裝成事實。**
5. **來源主張不應冒充世界本身。**
6. **索引不應取代記憶。**
7. **讀取與理解不等於擁有任意改寫的權力。**
8. **圖書館必須保存自己如何修正錯誤，但不把錯誤 identity 永久留作 canonical entity。**
9. **世界可以超出目前 schema；未知不等於不存在。**
10. **每一次 ontology 擴張都應有可審計的理由，而不是因抽象野心任意增生。**
11. **檔案路徑只保存不可變身分，不把暫時的名稱、型別、階層或分類誤當成存在本身。**

---

## 20. 核心宣言

Akashic-Library 可以由以下命題概括：

> 人與作品是對等的一級館藏。
>
> Entity 提供身分；state of affairs 表達世界如何成立。
>
> 一個 identity 只有一個 canonical file；一個 file 只代表一個 identity。
>
> Canonical paths 只編碼不可變 UUID；名稱、型別、階層與分類存在紀錄、關係或可重建視角中。
>
> 檔案是本體，資料庫是可重建索引。
>
> 有意義的變化必須沿時間保存，而不是由現在覆蓋過去。
>
> 圖書館保存來源、主張、歧義與裁決，不讓推測冒充事實。
>
> Git 保存檔案如何改變；canonical store 表達圖書館目前如何理解世界。
>
> Schema 可以在版本內明確，但不能宣稱已窮盡所有未來語言遊戲。
>
> 世界可以是 Akashic 的 horizon，但不能是每一個 release 的 scope。
>
> 管理員可以閱讀、連結與澄清紀錄，但不能冒充故事的作者。

最後，Akashic 不是保存對象目前的狀態，而是保存：

> **對象在時間中的存在、它與其他事物形成的事態，以及圖書館如何逐步理解並修正這些紀錄。**
