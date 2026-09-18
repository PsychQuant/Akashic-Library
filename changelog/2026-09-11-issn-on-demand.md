# periodical 的 ISSN 覆蓋率 10%：裁決按需補，而「怎麼補」被 verify 改寫了一次（#556）

## 量測改變了 issue 的形狀

立案（2026-09-11）實測 live store：periodical 403 筆、無 ISSN 363 筆（90%）。三個候選形狀——按需補、批次補、不做。
裁決前先量了 issue 自己要求先量的東西：`fields` 殘留裡未升格的 ISSN 是 **0**（`migrate-identifiers` 已搬完），40 筆現有
ISSN 全來自遷移。所以 10% 是**上游（WoS／Zotero）的覆蓋率**，不是 Akashic 漏收；批次補的第一條路（從殘留撈）不存在，只剩外部查證。

使用者拍板：**按需補，不掃全庫**——`akashic-verify-venue` 的證據鏈本來就查 Crossref journals 與 ISSN Portal，只差「查到就寫」
一步。`a6d3373` 在該 skill 的 Step 3 加了 5 行。

## R1 verify：裁決沒被推翻，那 5 行怎麼寫被打到八處

Run `wf_16618477-862`（2026-09-19）：六席齊，42 列，8 HIGH。沒有一列動到「按需補」；HIGH 全在措辭：

- 動詞「**順手**寫進去」與同 plugin 的 `akashic-venue-works` 第 7 步（「ISSN 寫入是 venue 身分斷言，**不是**順手動作」）字面對立
  （四席同指）——兩份 skill 對同一個寫入面各說各話，LLM 照哪一份走由載入順序決定。
- 沒分 confirm／reject 腿：reject 時查到的號屬於 literal 真正對應的那本刊，`key:<venue>` 沒定義，而 `add_issn` 沒有移除面。
- 使用者確認畫面（報告形狀恰三項）裡沒有「要寫進去的號」。security 席判成「在確認閘之外」，DA 更正：結構上在閘之內、缺的是
  報告第 4 項——照 security 的診斷會再加一道閘而使用者仍看不到那個字串。
- 同檔第 81 行「存 `sources/` 寫入 venue 的 `references`」在 HEAD **執行不了**：venue 沒有通用 reference 寫入面（person 有），
  只有 `paginated` 判定那條路會寫；新句只否認 `add_issn` 那一格，反而讓第 81 行看起來仍成立（DA）。
- `add_issn` **記不下 medium**（`ISSN.init` 把 medium 設 nil、寫入面不走 `withQualifier`），而 `["<print>","<electronic>"]` 佔位正好
  誘導把角色寫進字串→整批拒絕；Step 0 讀取面印的 `0003-1305（print）` 就是那個會被拒的形。live store 59 個號裡 9 個有 qualifier、
  全來自遷移——按需補這條路寫出來的每一筆都比遷移資料少一格 store 真的有的欄位。

## R2：兩個裁決（Claude 代裁，使用者可翻）

- **D91**：ISSN 寫入比照 venue-works 第 7 步——只在 confirm 腿、報告加第 4 項（號、medium、來源、確屬本刊的依據）給使用者過目、
  號要在 ISSN Portal 或出版商頁再確認一次（ISSN 自己的停止條件，不借用配對那條）、只送裸號、單獨一次呼叫（整批拒絕零寫入，
  與 `add_names` 併送會把名字一起吞掉）、一定用陣列（#561 的靜默 no-op）、核對 `issnAdded`。
- **D92**：兩個缺口開 **#587**——venue 通用 `references` 寫入面、`add_issn` 的 medium；第 81 行改成「digest 今天只能記在報告」。
  建檔面補「查到並核對過的 ISSN 一起送 `issn:`」（`add_venue` 收得下，別建出一筆新的無 ISSN 刊）。數字加立案日期；「唯一補的路徑
  就是這裡」拆成「唯一的資料來源是外部查證；寫入面不只這裡」（DA 第 32 列：照兩席直接刪句會連本 issue 唯一的量測結論一起刪掉）。
- Sister Concerns 那句「那在 plugin repo、不在本 repo」為假——plugin source 就在本 repo 的 `plugin/skills/`，errata 留言補在 #556。

## 誠實邊界

- skill 散文裡的數字沒有守衛在看（`MeasuredNumbersAudit` 只掃 `.claude/rules/` 與 `plugin/rules/`），`rule-coverage.sh` 只查
  有沒有掛規則、不查有沒有遵守。這一格是「沒有守衛在看」，不是「守衛看過說沒問題」。
- 「外部網頁 → store 寫入」是這 5 行開出的結構性通道；mod-11 檢查碼擋得住亂碼、擋不住合法但屬於姊妹刊的號。兩道核對與報告
  第 4 項是這條通道上唯一的人眼。
