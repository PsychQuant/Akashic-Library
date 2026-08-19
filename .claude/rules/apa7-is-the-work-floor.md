# 一筆 work 的資訊下限是「能產出正確的 APA7 參考文獻」——下限不是上限

使用者 2026-08-19（+08:00）定調：「**APA7 匯出是 work 的最低限度要求，當然還能有其他擴充**」。

適用於**任何決定 work 該持有什麼的地方**：`Entry` 的型別與欄位、`Entry.type` 的值域、
importer 收什麼、`create-entry` 要求什麼、export 面驗什麼。

不適用於 person／organization／venue／divergence 的**自身**欄位（它們是 work 的引用對象，
各有自己的完整性規範）。但**當它們被 work 引用而 APA7 需要它們貢獻欄位時**，那個需求由本規則
向它們提出——例如 §9.28 的編著章節需要編者與出版社。

## 規則

**下限（floor）**：store 對任一筆 work 持有的資訊，必須足以產出**該筆的 APA7 參考文獻**。
判準不是「看起來夠了」，是 **APA7 手冊 ch10 的 113 個編號例**——每一例是一個可否證的問句：
「模型持有的資訊夠不夠產出這一筆？」

**上限（不設）**：來源給了更多就收更多。這是 `lossless-intake` 的既有要求，本規則不收窄它。
下限與上限一起夾出區間：**至少能引用，最多是來源給的全部。**

**分類權威（細分關係，不是相等）**：`Entry.type` 的值域必須**細分**（refine）ch10 的 16 節
——**包含它，不是等於它**。形式化：

- 每個 Akashic 類型必須能對映到**恰好一個** ch10 節（保證 APA7 匯出永遠可行）
- **多個 Akashic 類型可以對映到同一節**——專案有權比 APA7 分得更細
- **更細可以，更粗不行**

取 ch10 當對映靶心的理由是每節有可獨立驗證的判準——§9.24：「The source element has **one or
two parts, depending on the reference category**」，即每節向載體索取的欄位組不同。這與
`VenueType` 的 §11 判準（「它決定了哪些欄位存在」）同源。

**為什麼更粗不行**（這是不對稱的來源）：兩個 ch10 節的欄位組不同，混進同一個 Akashic 類型後
就無法判斷該索取哪一組——`unpublished` 的 21 筆正是這個形狀（橫跨 10.5 與 10.8，欄位全空，
現在已無法機械區分）。**更細則永遠安全**：對映是多對一，渲染時查對映即可。

**實例（使用者 2026-08-19 裁定）**：維基百科條目在 APA7 落在 10.3（Edited Book Chapters and
Entries in Reference Works），與編著章節同節。但在本專案它是獨立且高頻的類型（實測 14 筆），
**值得自己的格子**——`wikipedia-entry` 是合法的 Akashic 類型，其 APA7 對映是 10.3。使用者原話：
「這在我這個專案是可以特別用 wikipedia 條目的，我們沒有必要要完全照 APA7，而是我們**包含**他」。

這是「下限不是上限」在**分類**面的形式：**ch10 的節是下限的分辨率**，專案可以更細，不能更粗。

**不進值域的兩類東西**（封閉列舉，不得依性質相似類推第三類）：

1. **欄位存在性的變化**。ch10 開頭四條軸是 **Author／Date／Title／Source Variations**，113 例
   是 `類型 × 變化` 的格：例 1–11 全是 journal article，差別在有無 DOI／21 人以上作者／advance
   online publication／in press／另一語言／republished in translation／reprinted。那些是**欄位
   值、出版狀態與關係**，存成類型會把封閉列舉炸成 113 個值。
2. **衍生的 APA7 section 編號**。`biblatex-apa` 已能從 `(type, fields)` 現算
   （README：「Classify entries into APA 7 manual sections (10.1–11.10)」）。存一份等於製造
   第二個會分岔的來源。

## 為什麼：兩個方向的不對稱

| 方向 | 代價 |
|---|---|
| **少於下限** | 那筆 work **無法被引用**。而「能引用」是這個專案存在的理由——`replace-endnote-and-zotero` 的終局是不裝 EndNote／Zotero 也能做完所有事，一筆不能引用的記錄直接否定它 |
| **多於下限** | YAML 裡多幾個鍵。幾十 bytes（`lossless-intake` 的既有論證，本規則沿用不重述）|

不對稱本身就是全部論據。而它有一個**更尖的版本**：少於下限的失敗是**安靜的**——`.bib` 語法完美、
序列化測試全綠、`validate` 零 diagnostic，然後把它丟進 LaTeX 才看到參考文獻缺了 volume。
語法正確性與書目正確性是兩件事，而目前只有前者有守衛（#326）。

## 為什麼是 APA7，以及它**不是**什麼

**是**：本專案的既有正典（`che-axiom-systems` 的 `apa7-style` domain、`repos/biblatex-apa-swift`
依賴），且使用者的領域標準就是它。ch10 的 113 例是**現成的、權威的、可執行的**驗收矩陣——不必
自己發明一份完整性清單。

**不是本體論**。APA7 是**呈現**標準，它的類別為排版而分，所以會把本體上不同的東西併在一起
（§9.29 把 book／report／software／data set 的**來源**全歸 publisher）。因此：

- APA7 當**下限**與**分類權威**：✅
- APA7 當**上限**：❌ 那會讓模型只留 APA7 用得到的東西，把 `lossless-intake` 反轉
- 日後支援 Chicago／Vancouver：那是**新增 export 面**與可能的新欄位需求，**不是重新建模**
  ——因為下限只約束「至少要有」，沒有禁止更多。這是把 APA7 放在下限而非上限的第二個理由

若判準來源日後要換（例如改以 CSL 的 item type 為值域權威），那是一次**顯式裁決**，要改本檔，
不是靜默漂移。

## 觸發過的實例（2026-08-19 讀 ch8–ch10 全文時一次性發現）

- **`Entry.type` 是自由 `String`**，10 個值是各 importer 碰巧寫的，沒有任何東西擋得住第 11 個
  拼錯的值（#325）。對照 `VenueType` 封閉三值、decode 對未知值整檔拒讀——**驅動 export 排版的
  欄位反而沒約束**
- **兩個 catch-all 都在藏真類型，但兩者的病不同**：`misc` 的 14 筆**全部**是維基百科條目
  ——它們在 APA7 有歸屬（10.3 例 49）但在**本專案沒有自己的格子**，該由細分關係補上
  （`wikipedia-entry` → 10.3）；`unpublished` 的 21 筆**全部**是會議發表或未刊稿，而 APA7 把
  它們分在**兩個不同節**（10.5／10.8）——這是**更粗**的那種病，欄位全空且已無法機械區分。
  catch-all 的名字說「雜項」，內容說「沒人給它們正確的格子」
- **10.11 Tests, Scales, and Inventories 零實例**——而使用者主授心理測驗、做心理計量，引用量表
  是日常需求。缺口不是「用不到」，是「用到了卻落進 `misc`」
- **`BibValidator` 已實作、零呼叫**（#326）。專案付了 dependency 的代價卻沒拿到它最有價值的
  能力：`export-bib` 只借了 `BibEntry` 型別與 `BibWriter.serialize`
- **113 例零覆蓋**（#327）：`export-bib` 的測試驗序列化正確性（大括號平衡、注入防護），不驗
  書目正確性——一筆語法完美但缺 volume 的 journal article 會通過所有測試

## 下限的機械檢查目前**不含** `EVENTTITLE`（#359，2026-08-19 量測）

`export-bib` 的 APA7 報告用 `APADataModel.requiredFields`（#353 換表），而那張表把
`PRESENTATION` 的 `EVENTTITLE` 列為 **recommended 而非 required**。

**但手冊說它是 source element。** §10.5 的 template 把 Source 欄寫成：

> **Conference Name, Location.**

而該節的四個編號例（60 Conference session／61 Paper presentation／62 Poster
presentation／63 Symposium contribution）**全部帶會議名稱**，無一例外
（`APA7GoldenTests.testEverySection105ExampleCarriesTheConferenceName` 釘住這件事）。

所以一筆缺 `EVENTTITLE` 的會議發表**沒有來源可印** —— 那是本規則定義的**下限違反**，
而 `APA7Report.hasErrors` 現在抓不到它（只有 warning 級）。#359 當日實測 store 有 **25 筆**。

**同日稍後降到 4 筆（#340）——而降下來的方式值得記住。** 那 21 筆的會議名稱**一直在
Zotero 裡**（`meetingName`，21 筆 presentation 全部都有），只是 `ZoteroMapping.fieldMap`
沒有它，於是走殘餘路徑以 `meetingname` 入庫：**資訊沒有丟，可引用性丟了**。

這是本規則與 `lossless-intake` 的**交界形狀**，值得單獨標出來：殘餘收集（#206）保證了
「來源給的都收」，但收進來的鍵名若不是 export 面認得的那個，下限仍然跌破。兩條規則各自
滿足、合起來仍有洞——**「有這個資訊」與「能產出參考文獻」是兩個不同的命題**。

同一輪還有一個完全同型的：`encyclopediaTitle` → `booktitle`（14 筆，APA7 10.3 的
source element）。兩次都是「殘餘裡躺著答案」。查缺口時先問一句**「上游是不是其實有，
只是我們用別的鍵名收了？」**，比直接去外部查證便宜得多。

**這一格是 known gap，不是 known good。** 記在這裡的理由：本規則說「113 例是驗收矩陣」，
若不明寫這個缺口，讀者會以為矩陣全綠＝下限全達。矩陣確實全綠 —— 因為它的 fixture 都是
**完整的**手冊例子，而缺口在**不完整的**記錄上，那些記錄矩陣裡沒有。

`APA7GoldenTests.testRemovingEventTitleIsOnlyAWarningToday` 用一個**斷言現況**的守衛把
缺口釘住：它會在缺口被修好時變紅，提醒回來更新這一節。

**為什麼不直接在 Akashic 側把它加回 required**：那會製造**第三張**必要欄位表
（`BibValidator` 的、`APADataModel` 的、我們自己的），而三張會各自分岔。#354 的補充表
之所以可以存在，是因為它補的是依賴**沒有意見**的型別；這裡是**反轉依賴刻意設定的值**，
兩者不同類。裁決留在 #359。

## 一個誠實的邊界（別把下限當成品質保證）

通過 113 例是**必要條件不是充分條件**。把所有東西塞進 `fields` 的自由字典也能讓 113 例通過
——那不是好模型。結構品質仍靠封閉列舉的紀律（#323 的 `Author` 三態、#324 的 `VenueType` 判準、
#325 的 `Entry.type` 值域），本規則只保證「不會少到不能引用」。

## 跟其他規則的關係

- `lossless-intake`：那條管**上限方向**（來源給什麼就收什麼）；本條管**下限方向**（至少要有
  什麼）。兩條合起來夾出區間，且**不重疊**——一筆 work 可能同時違反兩者（來源給了 volume 卻沒
  收＝違反 lossless；來源本來就沒給 volume 而模型也沒地方放＝違反本條）
- `replace-endnote-and-zotero`：本條是那條的**可驗證下限**。「這個功能我回去用 Zotero 做」若
  發生在「產出參考文獻」上，就是取代失敗的最核心形式；113 例是它的量測
- `entity-backlink-completeness`：APA7 section 編號現算不存，是那條「反向／衍生一律現算」的
  同一條紀律在另一個欄位上的應用
- `mcp-cli-parity`：export 面的完整性報告要兩面都有（#326 的 impact 已載明）
- 全域 `common-spec-prose-enumeration`：本檔的「不進值域的兩類東西」是封閉列舉，刻意不寫成
  「凡是變化都不算類型」那種總括判準——那句話會在邊界上自己長出第三類
