# 每個 entity 都要看得到所有有關的 entity——**算出來的**，不是存出來的

適用於**呈現面**：CLI 的檢視命令（`akashic person`…）、MCP 的聚合 tool
（`akashic_person`…）、App 的實體頁面、任何「給人看一個 entity」的出口。

不適用於**儲存層**（`entities/*.yaml`）。事實上這條規則對儲存層的要求正好相反——
見下方封閉列舉。

## 規則

**呈現一個 entity 時，與它有關的 entity 都要看得到**——不論那條關係是存在它自己
身上，還是存在對方身上。使用者不必知道邊被記在哪一側。

**這個要求由衍生滿足。** 呈現面缺一個方向，補的是**讀取入口**，不是欄位。

### 可以儲存關係的地方是封閉列舉

以下 **11 條**是 store 裡**僅有的**關係邊。**封閉列舉，不得依性質相似類推第十二條**：

| # | 存在哪 | 指向 | 邊界條件 |
|---|---|---|---|
| 1 | `Entry.authors` | person | `.key` 已歸戶／`.literal` 未歸戶，兩者都合法 |
| 2 | `Entry.akashic.relations.cites` | work | citekey |
| 3 | `Entry.akashic.relations.related` | work | citekey；**對稱邊**，見下方「約定」 |
| 4 | `Entry.akashic.tags` | tag | — |
| 5 | `Entry.akashic.libraries` | library | registry key |
| 6 | `Entry.attachments` | 檔案 | — |
| 7 | `Person.profile.affiliations` | organization | `OrgRef`，時間軸；`.literal` 未歸戶合法 |
| 8 | `Organization.parents` | organization | `OrgRef`，時間軸；與 7 **刻意不共用型別** |
| 9 | `Divergence.candidates` | work／person／organization | `key` + `shape: EntityKind`；**短暫記錄**，消歧後即刪 |
| 10 | `Divergence.judgement.prefers` | 本記錄的某個候選 | decode 時驗證存在性；同樣短暫 |
| 11 | `Person.references` / `Organization.references` | `sources/` 的內容 | `ProvenanceReference`，content-addressed（`sha256:`）|

**每一條邊只存一次，存在上表指定的那一側。反向一律現算。**

新增第十二條 = 改這張表 + 說明為什麼那個方向必須是正典。**不得**因為「這樣讀比較快」
或「這樣呈現比較方便」而加——那兩個理由要的是索引或入口，不是欄位。

#### 兩個必須寫出來的邊界（否則列舉的封閉性是假的）

- **9／10 是短暫記錄。** `divergence` 是 `EntityKind` 的第四個成員、與 work／person／
  organization 並列住在 `entities/`，所以它**是**關係邊、不能因為「感覺不像」而漏列。
  但它的生命週期不同：消歧之後整筆刪除。呈現面的義務因此是「這個人牽涉哪些**未決**的
  同一性問題」，而不是歷史。
- **11 指向的不是 entity，是內容。** 第 6 條（`Entry.attachments → 檔案`）已經開了這個
  先例——指向非 entity 的東西仍然是存下來的邊。把它列進來是為了封閉性，不是為了要求
  呈現面顯示 digest。

#### 對稱邊的約定（判準沉默的地方）

第 3 條 `related` 是 **work ↔ work 的對稱關係**：刪掉任一端那條邊都消失，所以
「哪一側存」的判準對它**不裁決**。現行存在 entry 側是**約定**，不是推導出來的。
標出來是為了讓下一個人知道那不是判準的結論，不要拿它去類推。

> **這張表曾經是錯的。** 第一版寫「8 條、store 裡僅有」，漏掉 9／10／11——因為作者只
> grep 了 `Entry`／`Person`／`Organization` 三個型別就下了窮盡的結論。`common-spec-prose-enumeration.md`
> 說封閉列舉的價值全在它真的封閉；**一份宣稱窮盡卻漏案例的列舉比沒有列舉更糟**，因為
> 讀者會拿它去推導「divergence 的候選不是關係邊 → 不需要呈現 / 可以隨手改」。
> 由 `PsychQuant/Akashic-Library#220` 的 verify 抓出（requirements 與 regression 兩個
> lens 獨立命中）。**新增形狀時，先看 `EntityKind.allCases`，不要只 grep 你想得到的型別。**

### 不得儲存的（同一件事的另一面）

上表**反向**的任何欄位。具體到已經被提議過並否決的：

- person 記錄的 `works:` / `publications:`（1 的反向）
- work 的 `citedBy:`（2 的反向）
- organization 的 `members:`（7 的反向）
- tag 的成員清單（4 的反向）
- person／organization 的 `divergences:`（9 的反向）——「這個人牽涉哪些未決同一性
  問題」由掃 divergence 記錄算出，不在被指涉的那一側存一份

`PersonCLITests.testPersonRecordStoresNoWorks` 是第一條的機械防線。

## 為什麼：不對稱（與 `lossless-intake` 同形，方向相反）

| 選擇 | 代價 |
|---|---|
| 存一次、反向現算 | 每次呈現要查一次索引。微秒級，而索引本來就在 |
| 兩側都存 | **兩份 canonical state**。歸戶、改名、刪除、合併都要同步，而它們**會**分岔 |

分岔的糟糕之處在於它**安靜**：兩份都看起來像真的，沒有任何跡象指出哪一份過期。
`lossless-intake` 說「不收會讓命題永久不可判定」；這條說「存兩份會讓命題**同時**
有兩個答案」。前者是缺，後者是矛盾——**矛盾比缺更難發現**。

反過來，衍生**不可能分岔**：只有一個來源。

## view 與 backlink 不是同一件事

這是本規則最容易被誤用的地方。看到「呈現要完整」很容易想到 `ViewDefinition`，
但多數情形根本用不到它：

| | view | backlink |
|---|---|---|
| 例 | 「統計所的人與著作」 | 「che-cheng 的著作」 |
| **需要判準嗎** | ✅ 需要（`personAffiliation: iss`） | ❌ **不需要** |
| 判準住哪 | `config.yaml`（是設定，不是知識） | 沒有判準可住 |
| 外延怎麼來 | 套判準現算 | 把上表某條邊**反過來讀** |

**backlink 比 view 更基本**：view 是 backlink 之上再加一個條件。所以補一個反向
呈現面**不需要**動 `ViewDefinition`、不需要新增 config——那條邊已經在庫裡了。

判斷方法：問「這個集合需要我**決定**什麼嗎？」需要 → view，判準進 `config.yaml`
（`docs/explainers/entity-vs-view.md` 是那邊的正典）。不需要 → backlink，直接算。

## 執行細節

1. **反向查詢走索引，不要全掃。** `LibraryIndex` 已經為此建了
   `idx_authors_key ON authors(person_key)`。新增反向呈現面前先看索引有沒有；
   沒有就加索引，**不是**加欄位。

2. **一個 entity kind 的讀取面只能有一條實作路徑。** CLI 與 MCP 必須落到同一個
   函式（`AkashicService.*`）。兩邊各自查一次 = 兩條會分岔的路徑，那是本規則在
   儲存層禁止的事在讀取層重演。

3. **未歸戶的要照樣顯示，且不得冒充 identity。** `.literal` 是誠實狀態不是壞掉的
   `.key`（同 `EntityRef` 的立場）。呈現時給名字、不給 key——讓使用者看得出哪些
   還沒歸戶。

4. **空集合要說出來。** 「這個人零篇著作」與「查不到這個人」是兩件事；後者是錯誤，
   前者是結果。折成同一個輸出會讓使用者無法分辨。

## 失敗史

2026-08-10，`README.md` 寫著「想知道作者是誰、**發表過什麼**、隸屬哪裡，答案在
那筆記錄裡」。前後兩項為真，中間那項為假——著作**不在**記錄裡，而且不該在。

那句話把**記錄**當成**視圖**在描述。真正的缺口在別處：衍生鏈

```
LibraryIndex.authors(person_key) → QueryEngine.personPublications → AkashicService.person
```

**完整**，但只有 MCP 接上去。CLI 有 24 個 subcommand，能用 `update-person`
**改寫**一筆 person 記錄，卻沒有一個能**讀出**一筆。

當時的直覺修法是「在 person 記錄加 `works:`」——那會製造第二份 canonical state。
正確的修法是補一個讀取入口（`akashic person`），三十行，因為那條鏈早就在了。

追蹤：`PsychQuant/Akashic-Library#218`。同族的其餘五個缺口（`people` /
`get_entry` / `link` / `tag` / `set_status` 只有 MCP 有）：`#219`。

## 跟其他規則的關係

- `.claude/rules/lossless-intake.md`：管**進來**的完整性（來源給什麼就收什麼）。
  本規則管**出去**的完整性（庫裡有的關係就要看得到）。兩條合起來才是
  「真實世界發生的事，在圖書館裡都找得到 model 使它成立」。
- 全域 `common-spec-prose-enumeration.md`：上面 8 條是**封閉列舉**，刻意不寫成
  「凡是關係都存在擁有它的一側」那種總括判準——那句話的字面涵蓋範圍大於這 8 條，
  會在邊界上自己長出第九條，而每一條多餘的邊都是一次安靜的分岔。
- `docs/explainers/entity-vs-view.md`：view 判準為什麼住 `config.yaml`。本規則
  只引用它、不複製（複製 = 兩份會分岔的規格）。
