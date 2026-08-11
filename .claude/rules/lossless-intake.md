# 匯入不得有損：來源給了什麼，就收什麼

適用於**任何把外部資料寫進 store 的路徑**——`import-wos`、`import-zotero`、
`create-entry`、MCP 的寫入 tool、以後任何新的 importer。

不適用於**輸出端**（`export-bib`、`query`、App 顯示）。輸出當然要挑、要排版、要截斷；
這條規則只管**進來的那一刻**。

## 規則

**來源提供的每一個欄位都要進 store**，即使：

- 現在沒有任何程式讀它
- 它看起來跟別的欄位重複
- 它看起來會過期（外部系統的當下快照）
- 你不確定它是什麼意思

**不收**的只有兩類，**封閉列舉，不得依性質相似類推第三類**：

1. **秘密**——token、密碼、API key、任何憑證。
2. **CLAUDE.md 隱私邊界禁止的原始第三方逐字內容**——raw 逐字稿、未經加工的第三方私訊。
   （判準見全域 CLAUDE.md「Git 隱私邊界」；加工過的衍生產物不在此列。）

落在這兩類之外而你仍想丟掉的東西：**不要自己決定，問**。

**真的要丟就必須報出來。** 靜默丟棄是本規則要防的核心行為——見下方。

## 為什麼：不對稱

| 選擇 | 代價 |
|---|---|
| 收了但沒人用 | YAML 裡多一個鍵。幾十 bytes。隨時可以開始用 |
| 沒收 | **那件事永遠不可判定**，而且沒有任何跡象顯示它曾經可判定 |

這個不對稱是整條規則的全部論據。它**不受** YAGNI 反駁——YAGNI 管的是「你可能不會寫的
程式路徑」，那是可逆的；這裡管的是「你再也拿不回來的資訊」。

## 為什麼：這是本專案目標的直接推論

專案目標：**真實世界中發生的事情，在圖書館裡都要能找到一個 model 使它成立。**

那句話在 `AkashicProposition` 裡是可執行的（#198／#199／#200）：一個命題對 model 求值，
回 `.holds`／`.fails`／`.undetermined`。

匯入時丟掉一個欄位，不是「資料缺一塊」——是**讓一整族命題永久落在
`.undetermined(.notProjectable(…))`**。那不是「暫時不知道」，是**結構上不可知**：
沒有任何下游工作能救回來，因為來源已經不在了。

具體：presentation 的 `eventtitle`／`venue`／`eventdate` 被丟掉之後，
「這場報告在哪裡發表」這個命題在庫裡**連問都問不出來**。不是答案是「否」，
是這個問句沒有可投射的符號。

## 為什麼：store 層本來就準備好了

限制從來不在模型層：

- `Entry.fields` 是 `[String: String]`——完全自由
- YAML 有 `unknownFields` 的 tolerant-preserve——**連 decoder 不認得的欄位都原樣保留**

也就是說 store 的設計**已經**遵守這條規則。違反它的是各個 importer 自己寫死的欄位表。
這條規則不是新增約束，是把既有設計意圖寫下來，免得下一個 importer 又關一次門。

## 執行細節

1. **對映歸對映，收集歸收集。** 需要語意的少數欄位（title／authors／date）做對映；
   **其餘全部原樣進 `fields`**。兩件事不要混在同一個 `switch` 裡——混在一起就會變成
   「沒列到的就沒有」。

2. **殘餘收集要有 else。** 判斷一個 importer 有沒有違反本規則，看它有沒有「處理完已知
   欄位之後，剩下的怎麼辦」那一段。沒有那一段 = 靜默丟棄。

3. **丟棄必須可見。** 若某欄位真的不能收（上面兩類），要出現在該次匯入的報告裡，
   與既有的 `skippedRows`／`conflicts` 同一個層級。**靜默是最糟的形式**——
   它讓「沒有這個欄位」與「這個來源沒給」變成同一個觀察，而那兩件事在事後完全無法區分。

4. **新 importer 的驗收條件**：拿一份含未知欄位的來源餵進去，斷言那些欄位在
   round-trip 之後仍在。不是「有對映到已知欄位」，是「**未知的也還在**」。

## 失敗史

2026-08-09，把個人 CV 的 34 筆非期刊條目（22 場 presentation、7 份 report、
2 篇學位論文、3 筆 online）收進 store 時發現：`import-wos` 只讀 12 個寫死的欄位名，
其餘 **21 個欄位靜默消失**（`eventtitle`／`venue`／`eventdate`／`institution`／
`eprint`／`abstract`／`annotation`…）。對 presentation 而言那些**就是主要內容**，
丟完只剩標題與年份。

`import-zotero` 有同一個形狀（`ZoteroMapping` 只寫 `fields["title"]`／`fields["date"]`）。

當下的 workaround 是繞過 CLI、用 stdio 驅動 `akashic-mcp` 逐筆呼叫
`akashic_create_entry`（那支收任意 `fields`）。可行，但那條路只有寫程式的人走得到——
**能不能無損匯入，不該取決於使用者會不會寫 script。**

追蹤：`PsychQuant/Akashic-Library#206`。

## 回填：規則要及於**已經匯入**的記錄

把 importer 改成無損之後，舊記錄仍然缺著當初被丟掉的欄位。若重跑匯入只報
「conflict」而不補，這條規則對**既有資料**等於沒有生效——而既有資料才是大多數。

所以兩個 importer 都要能回填，判準是**只多不少**：

- 共有的欄位**一個都不動**（人工修改過的值不得被洗掉——那正是 conflict 路徑
  當初不覆寫的理由）
- 只補**原本不存在**的鍵。加一個不存在的鍵洗不掉任何東西
- 除此之外的差異仍是 conflict，交給人

WoS 走 `report.enriched`（與 `conflicts` 分開）。Zotero 走既有的 hash 比對——
殘餘欄位進 `mappingHash`，所以下次 `import-zotero` 會自動更新。**代價是那次
匯入會大範圍觸發更新**，而更新分支在沒有已歸戶 `.key` 作者時會用 Zotero 的作者
覆寫 literal 作者（既有 sync 語意，非本規則引入，但會被它一次性放大）。

## 兩個 importer 的方向相反——這是刻意的，但必須說出來

| | 既有記錄與來源不一致時 |
|---|---|
| `import-wos` | **拒絕覆寫**，記 `conflicts` 留給人 |
| `import-zotero` | **跟隨上游**：Zotero 供給的欄位以 Zotero 為準；未歸戶的 literal 作者被覆寫 |

各自都對：WoS 是一次性匯出檔（store 可能比它新），Zotero 是 pull-based sync
（Zotero 是上游）。**危險的不是差異本身，是差異看不見**——使用者跑兩個命令會
得到相反的資料保護等級。

所以 Zotero 側把會蓋掉的東西**報出來**：`authorsOverwritten`（未歸戶作者被改成
Zotero 版本）與 `fieldsRemovedByPull`（Zotero 這次沒給、整份替換後消失的欄位，
含使用者手工補的）。已歸戶的 `.key` 作者永不被覆寫（`authorsPreserved`）。

**尚未解決的部分**：`applyBiblatexFields` 整份替換 `fields`，所以 Zotero
「沒給」與「說沒有」被當成同一件事。要分開需要 per-field provenance，那是
更大的設計題（追蹤：#208）。目前的立場是**先讓它可見**——靜默才是真正的問題。

## 跟其他規則的關係

- 全域 `common-spec-prose-enumeration.md`：本規則的「不收」是**封閉列舉**，
  刻意不寫成總括判準（「無用的欄位不必收」那種寫法會在邊界上自己長出第三類，
  而每一個第三類都是一次不可逆的資訊損失）。
- 全域 CLAUDE.md「Git 隱私邊界」：第 2 類例外的判準住在那裡，本檔不複製一份
  （複製 = 兩份會分岔的規格）。
