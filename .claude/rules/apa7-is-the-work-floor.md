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

**分類權威**：`Entry.type` 的值域取 **ch10 的 16 節**。理由是每節有可獨立驗證的判準——§9.24：
「The source element has **one or two parts, depending on the reference category**」，即每節向
載體索取的欄位組不同。這與 `VenueType` 的 §11 判準（「它決定了哪些欄位存在」）同源。

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
- **兩個 catch-all 都在藏真類型**：`misc` 的 14 筆**全部**是維基百科條目（ch10 例 49 有專屬
  格式）；`unpublished` 的 21 筆**全部**是會議發表或未刊稿，而 APA7 把它們分在**兩個不同節**
  （10.5／10.8）。catch-all 的名字說「雜項」，內容說「沒人給它們正確的格子」
- **10.11 Tests, Scales, and Inventories 零實例**——而使用者主授心理測驗、做心理計量，引用量表
  是日常需求。缺口不是「用不到」，是「用到了卻落進 `misc`」
- **`BibValidator` 已實作、零呼叫**（#326）。專案付了 dependency 的代價卻沒拿到它最有價值的
  能力：`export-bib` 只借了 `BibEntry` 型別與 `BibWriter.serialize`
- **113 例零覆蓋**（#327）：`export-bib` 的測試驗序列化正確性（大括號平衡、注入防護），不驗
  書目正確性——一筆語法完美但缺 volume 的 journal article 會通過所有測試

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
