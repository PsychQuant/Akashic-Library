# 作者位的團體 literal、守衛的隱式-return 盲區、APA7 下限批 C（#378 #381 #340）

PR #380／#382，2026-08-20。三件事，而它們是**連在一起發現的**——每一件都是前一件的
副產物。這條發現鏈本身比任何單一修正更值得記。

## #378 — `Author.organization` 存在，但沒有路徑到得了

`Author` 的三態在 #323 就建好了，`.organization` 也一直在型別裡。但：

- importer 依 `literal-first-then-key` 一律以 `.literal` 進庫 —— **這是對的**（進庫不猜）
- `bootstrap-organizations` 與 `resolve-organizations` 只掃**兩條**邊：
  `Person.profile.affiliations`（封閉列舉第 7 條）與 `Organization.parents`（第 8 條）

`Entry.authors` 是第 **1** 條邊，而它的 `.organization` 分支**沒有消歧路徑**。團體作者
因此永久卡在 literal 態。

**失敗是安靜的**：literal 是合法狀態（`literal-first-then-key` 第 2 段明訂「literal 是
誠實狀態，不是壞掉的 key」），所以 `validate` 不報、`doctor` 不報、測試全綠。沒有任何
跡象顯示那 4 筆卡住了。

修法把三段接起來：bootstrap 收作者位的**大括號標記** literal（`CorporateName.unmark`
去標記後才進候選）、resolve 的 `Holder` 增 `.work(citekey:authorIndex:)`、apply 三道守衛。

**為什麼用索引定位而非 literal 值**：作者是**位置序列**，同一筆可以有兩個團體作者，
值比對會互相干擾。而索引在別人插入作者後會指到另一個人 —— 所以第三道守衛要求那個位置
**仍然是**當初提名的那個 literal。

順帶修掉一個潛伏缺陷：MCP 的 verdict `holderKind` 原本是
`if case .person … else return .org` 的**兩路判斷**，`.work` 會被靜默算成 `.org`。
kind 屬配對身分（person／org key 可合法同名），算錯會讓否決比對**永遠對不上**
——被否決的配對會在下一輪重新被提名。改成窮盡 switch。

實測：brace-marked author literal **3 → 0**（過程中另發現第 4 筆，AERA/APA/NCME 聯合
標準），org 記錄 4 → 8。

## #381 — 守衛看不見隱式 return，而這是 #378 撞出來的

改寫 #378 的 `rowID` 時，一個**一直未消毒**的站點從單行閉包變成多行顯式 return，
`DisplaySinkCoverageTests` 立刻報出兩條違規。**語意沒變、風險沒變，只有寫法變了。**

根因：`sink` 軸以文字比對 `return "`，而 Swift 的單表達式函式／閉包可省略 `return`。

補上 `isImplicitReturnStringBody` 後報 **12 條**，逐條裁決：

| 條數 | 性質 | 處置 |
|---|---|---|
| 3 | `rowID`／`pinnedID` —— apply 的**回程把手** | 豁免（消毒會讓把手對不上，且 `displaySafe` **不冪等**）|
| 4 | `Equatable` 的比較鍵 | 豁免（不進任何輸出面）|
| 4 | 內部 `Set` 的成員判定鍵、封閉 enum 的 rawValue | 豁免 |
| **1** | `DivergenceResolve.describe` | **消毒** |

那 1 條是真的：產物經 `out.collisions` → `migrationCollision(details:)` →
`errorDescription` 直達使用者，而 errorDescription 裡是 `details.map { "  • " + $0 }`
—— 零消毒。**相鄰的 `deletionNotRecoverable` 對 `$0.path` 就有 `displaySafe`**：
同一個 error 型別的策略是 sink-side，本條漏了，而守衛看不見它。

### 一個非顯而易見的量測交互作用

給了第五個 Axis（`implicitReturn`），下限 **2** —— 低得反常，理由必須寫進註解：

strip-all meta-test 只拔 `displaySafe(`，**不拔 `display-safe-exempt:` 註解**，而掃描在
最前面就跳過帶那個註解的行。所以**被豁免的站點對 meta-test 永遠不可見** —— 本軸實測 14
條，逐條裁決後只剩 3 條是消毒站點。

**下限量測的是「這一軸碰到幾個消毒站點」，不是「這一軸的觸及範圍」。** 這一軸的價值是
那 11 條被逼出來的具名理由，而它們按定義不會出現在計數裡。不寫清楚的話，下一個人看到
`implicitReturn: 2` 會以為是校準失誤而順手調高，然後測試在下一次豁免時無故變紅。

順帶更新那條停在 2026-08-07 的過期 baseline：`68/21/14/54`（四軸）→
`172/48/57/115/3`（五軸），總數 `78` → `406`。

### 這是同一個家族的第四次

`#142`（跨行 `case …: return "…"`）／`#149`（回看被註解夾層擋掉）／本張（隱式 return）
—— **三次同向即模式**：這個守衛的每一個盲區都來自「Swift 允許同一語意有多種寫法，
而文字掃描只認一種」。是否該換 `SwiftSyntax` 留在 #381 討論，**本輪不裁決**（blast
radius 遠大於這個盲區）。

## #340 批 C — 症狀是缺 `JOURNALTITLE`，病因是 `type` 分類錯

剩下的 10 筆**全部**報同一句 `Missing required field: JOURNALTITLE`，於是前幾批一直在
問「這篇的期刊叫什麼」。逐筆看內容後發現**其中 6 筆根本不是期刊論文**：兩本教科書、
三個書章、一份報告。

`type` 標成 `periodical-article` → `APADataModel.requiredFields` **必然**索取
`JOURNALTITLE` → 錯誤訊息指著**欄位**，而真正錯的是 **type**。

這是 `apa7-is-the-work-floor` 那條「**更粗不行**」的實例：把六種東西壓進同一個 Akashic
類型後，欄位需求就取錯了一整組 —— 而那筆記錄會**通過所有檢查**，因為它確實滿足了
（錯的）那一組。同一條規則已記過 `unpublished` 的 21 筆是這個形狀；這裡是
`periodical-article` 的版本，而且**更隱蔽**，因為 `periodical-article` 看起來不像 catch-all。

落地 7 筆（store commit `96ae8c5`），每筆都有正對照：`philipecheng2008information` 的
**頁碼 535-558 與 store 完全相同**且四位作者全符 → Statistica Sinica；
`thompson2002universal` 由 **ERIC ED467721** 給出 NCEO 全名與 Synthesis 44；三個書章的
容器書年份與 store **完全吻合**。

**刻意不寫的**（寧缺勿誤）：三個書章的頁碼、Statistica Sinica 的卷期（後者可從落地頁
檔名 `A18n27.pdf` 推成 18(2)，但那是**從檔名慣例推**、不是取到的欄位）。

量測：`[ERROR]` **10 → 3**，本輪累計 **101 → 3（縮減 97%）**。

### 一則自我更正，與一個關於控制組的教訓

上一輪寫過「四個獨立權威已窮盡」。**那個範圍下得太寬**：窮盡的是 **Crossref**。
OpenAlex **加年份閘**、OpenLibrary **改 `q=` 自由查詢**、ERIC 各自解掉一筆。
**問題在缺閘與查詢形式，不在來源不足。**

而第一輪的 OpenLibrary 查詢（`title=` ＋ `author=` 併用）讓實測 A、實測 B、**負控**
全部 `numFound=0`。三個 0 看起來像「書不在庫裡」，其實是查詢過嚴 —— 而當下分不出來，
因為**負控與實測表現相同就等於沒有控制組**。改成 `q=` 之後負控 0、實測 1，才有鑑別力。

這與本 repo 既有的「只跑負對照只能證明不亂命中、證不了命中的是對的」是同一家族的
另一半：**負控本身也要能被否證。**

## 相關但未落地的（開著的 issue）

- **#383** —— `initials` 層對「已帶完整名」的 literal 仍只比首字母。實測 100 筆歧義裡
  **32 筆**問的是另一個問題（「這是新人還是異名」而非「選哪一個」）。順帶記錄第二個
  缺口：歧義清單的 `static let rows = 50` 寫死、無旋鈕，100 筆時只看得到 50 筆。
- **#384** —— 統計所 100 筆歧義的查證結果與裁決請求。「Chen, Y.-H.」24 筆 → 程毅豪的
  ORCID **正對照 20/24**（12 筆逐字相同）、**負對照**（兩個碰撞候選的著作）0.42／0.38
  正確拒絕。寫入等使用者裁決 —— `akashic-person-verify` 明訂「判定是人的、絕不自動合併」。
