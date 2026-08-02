## 1. §11 Entity admission rule：實體邊界（normative）

實現 `Formal concepts SHALL NOT occupy the canonical entity namespace`
與 `The entity criterion SHALL be stated as a single discriminating test`。
依 design 決定「D1：判別性條件是「decoder 是否為它分岔」，且它是**必要條件**，不參與多數決」
與「D2：規範用 MUST NOT，不用 SHOULD NOT」。

- [x] 1.1 實現 `The entity criterion SHALL be stated as a single discriminating test`：改寫 `docs/design-principles-and-philosophy.md` §11 的 Entity admission rule——現行「符合下列多數條件」是本次缺陷的直接成因（view 得分 5:1，唯一不符的正是「能成為多種關係的端點」）。改成：形狀選擇條件為**必要條件**，其餘條件維持為多數決的參考。這是本 change 唯一允許改寫既有條文的地方。
- [x] 1.2 判別測試改寫得比原第 4 條鋒利：從「能成為多種關係的端點」改為「**它決定了哪些欄位存在嗎（載入器會為它分岔嗎）**」，並明寫關係端點只是**佐證徵候**、不是判準（可被「那我加一條關係」反駁）。敘述須**不綁定標示機制**——不得寫成「看 `type:` 欄位的值」，因為標示機制由 `add-entity-shape-label` 改變，判準必須在那之後仍成立。
- [x] 1.3 實現 `Formal concepts SHALL NOT occupy the canonical entity namespace`：在 §11 的准入規則後新增一條 **MUST NOT**（依「D2：規範用 MUST NOT，不用 SHOULD NOT」——它防的失敗是結構性的）：形式概念（view / 分類 / 查詢 / 索引結構）不得存入 canonical entity namespace、不得取得 entity UUID。條文須自帶定義（什麼算形式概念）而非只引用他處。
- [x] 1.4 同條加上**與 §16 的界線說明**：本規則管形式概念能否進入 entity namespace（層次問題），**不管** §16 所處理的真正概念之間的 domain 取捨（課程、學期、研究領域該不該是 entity——那仍需先例與實踐）。無此說明，條文會被讀成推翻 §16「不需要一套自稱最終的 domain rule」。
- [x] 1.5 在 §3 的「### 規範」子節末尾加一行，指向 §11 的准入規則——§3 的六項是對 Person／Work 的**描述**、不是准入條件，而 #54 正是從那六項出發推論的。明寫身分／名稱／aliases／歷史為必要但不充分，附反例「index schema 版本四項皆具備但不是 entity」。

## 2. §7：predicate 的定義域（normative）

實現 `Predicates SHALL be expressed as fields on the shapes they apply to`，
依 design 決定「D5：predicate 以欄位形式住在適用的形狀上，不得有通用邊表」。

- [x] 2.1 實現 `Predicates SHALL be expressed as fields on the shapes they apply to`：在 §7 的「### 規範」子節末尾新增一條 **MUST NOT**——predicate 的定義域由「哪些形狀帶有該欄位」顯示，不得表達成資料；canonical store 不得含通用邊表 `(subject, predicate, object)`，不得含宣告 predicate 可接受哪些 subject 的 meta-schema。
- [x] 2.2 同條加上正面陳述：圖／三元組**可以**作為衍生產物存在（與 §5 的可重建索引同地位），並寫明理由——可重建 ⇒ 攤平的損失可回復。
- [x] 2.3 同條加上「擴充定義域必須是 schema 變更、不得是新增一筆記錄」，並附誠實邊界：這些限制是本 store 的**文法規則**、不是形上學必然，會隨實踐改變（呼應 §15 語言遊戲與 §16 規則遵循）；工程推論是**改一條規則的代價應配得上它的邏輯地位**。
- [x] 2.4 舉現況為例（一句）：「隸屬不能形容 work」沒有任何一行程式碼在陳述它——它由 `Entry` 沒有該欄位所顯示。此例證明本規範是把既有做法寫下來，不是引入新約束。

## 3. 交叉引用（既有 Part II 已有大量維根斯坦內容，只補指路）

實現 `Borrowed philosophical vocabulary SHALL name its source`。
依 design 決定「D3：Tractatus 出處寫進哲學文件，完整論證寫進 explainer」。

- [x] 3.1 實現 `Borrowed philosophical vocabulary SHALL name its source`：在 §2 的「事態」一詞處加**一句**，指出該詞是 Tractatus 的 *Sachverhalt* 的精確借用，並指向 §14（該節已引用《邏輯哲學論》並鋪陳圖像論）與 explainer。**只加交叉引用，不重複 §14 的內容**——缺的是指路，不是新論證。
- [x] 3.2 在 §11 與 §7 新增的條文各加一行指向 `docs/explainers/entity-vs-view.md`。

## 4. Explainer（非 normative，完整論證）

實現 `The boundary SHALL be documented with a recorded failure case`，
承載「D3：Tractatus 出處寫進哲學文件，完整論證寫進 explainer」拆出去的論證與
「D4：以 #54 的實測失誤作為文件裡的具體案例」的實測案例。

- [x] 4.1 [P] 建立 `docs/explainers/entity-vs-view.md`，開頭一段說明三方分工：規格說 what（Part I 的規範）、Part II 說哲學基礎、本 explainer 說**這一次的具體失誤與它的診斷**。沿用 `docs/explainers/yaml-alias-dos.md` 已建立的體例。凡 Part II 已有的內容一律**引用節次**，不重新推導。
- [x] 4.2 [P] 寫「實測失誤」一節（落實「D4：以 #54 的實測失誤作為文件裡的具體案例」）：記錄 #54 的原始主張（`entities/<uuid>.yaml` 加 `type: view`）、**逐條列出 view 對 §11 六條的得分 5:1**、以及為什麼多數決會核准它。含使用者的糾正原話。重點是：提議者沒有誤讀規則，是規則本身核准了它。
- [x] 4.3 [P] 寫「是記法先犯的錯」一節：`type:` 同時裝形式種類與書目類型，使 `type: view` 看起來是自然的第三個兄弟；附實測證據（`type: view` 的檔案通過 `akashic validate` 並被 doctor 計為一篇著作）。指向 `add-entity-shape-label`。
- [x] 4.4 [P] 寫「形式概念 vs 真正的概念」一節：Tractatus 4.126（形式概念隨著落在它下面的對象一起被給出）、4.1272（當成真正的概念用會產生 unsinnige Scheinsätze）、4.1211（`fa` 顯示 a 出現在其意義中，不需額外一句「a 是對象」）、3.333。**§14 已鋪陳圖像論，本節只補「形式概念」這個 §14 未涵蓋的部分並引用它。**
- [x] 4.5 [P] 寫「predicate 之間的關係」一節：4.124–4.125 內在關係——可能情境之間的內在關係，透過表達它們的句子之間的內在關係表現出來；因此 predicate 的定義域不能再用一個 predicate 去說。含被否決的兩個替代方案（通用邊表、predicate 定義域宣告表）與它們各自壞在哪。
- [x] 4.6 [P] 寫「表層文法騙人的地方」一節：以「隸屬」為例——某人隸屬中研院（僱用關係，有任期）與統計所隸屬中研院（部分-整體）是兩個 predicate；某論文隸屬中研院看似成立，實為作者當時隸屬的簡寫，是衍生物而非原生。引用 §15（語言遊戲）而非重述後期維根斯坦。
- [x] 4.7 [P] 寫「view 是 aspect 而不是部分」一節：兔鴨圖；圖沒有變、變的是 aspect；對應使用者原話「全部都是人，只是不同的 view 不一樣」。並寫「為什麼是 view 不是 slice」：#20 的 valid-time timeline 讓「中研院的人」的邊界取決於時間參數，而部分需要確定邊界。
- [x] 4.8 [P] 寫「這套論證的界限」一節（**防過度推廣**）：Tractatus 的形式概念是對象／事實／函數／數這一類，**不包含「人」**——「蘇格拉底是人」是完全合法的命題。本文的論證只適用於 store 裡的 person 作為**記錄形式**，不適用於「某個體是人類」這個關於世界的主張。並記 5.4733（「蘇格拉底是同一的」什麼都沒說，因為沒給該符號作為性質詞的用法）——診斷方向是**記法的失敗而非形上學的失敗**，配合 5.473「邏輯必須自己照顧自己」，這正是本專案讓記法擋下錯誤、而不是靠散文禁令的理由。
- [x] 4.9 [P] 在同一節寫清楚**反共相的思路屬於後期**：PI 65–67 家族相似與 Tractatus 的顯示／說不是同一個論證，結論也不同；PI 68–69 的推論是概念邊界為特定目的而畫，因此形狀標籤集合是規定而非本體論發現（呼應 §16）。收尾：標籤的意義是載入器拿它做什麼，因此本設計不需要共相——store 裡**不得**有一筆記錄代表「人性」，理由與 view 不得是 entity 相同（3.333）。
- [x] 4.10 寫「那 view 該放哪」一節：指向 #54 的結論（判準進 `config.yaml`、外延進 index），並說明「推不回來」不等於「是 canonical knowledge」——第三個可能是「它是設定」。

## 5. 收尾與驗收

- [x] 5.1 逐行 diff 確認 `docs/design-principles-and-philosophy.md` 的既有節次編號（§1–§20）與既有規範條文**除 §11 的准入規則外逐字未變**。驗證方式：該檔 `git diff` 的刪除行僅出現在 §11 的准入規則段落。
- [x] 5.2 在 `README.md` 的 `docs/explainers/` 說明行確認新檔已被涵蓋（該行於 #52 加入；若措辭是通稱則無須改動，若列舉檔名則補上）。
- [x] 5.3 在 #54 留一則 comment，指向本 change 產出的 explainer，並更正 issue 內對缺陷成因的描述（真正的成因是 §11 的多數決准入規則，不是提議者誤讀）。
- [x] 5.4 驗收 `The boundary SHALL be documented with a recorded failure case` 的可讀性條件：以未參與本次討論的視角通讀 explainer，確認能在五分鐘內回答四個問題——什麼算 entity／view 為什麼不算／曾經怎麼弄錯／正確位置在哪。無法回答者回頭補該節。
