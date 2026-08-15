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

以下 **13 條**是 store 裡**僅有的**關係邊。**封閉列舉，不得依性質相似類推下一條**：

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
| 12 | `Divergence.judgement.restsOn` | `sources/` 的內容 | 同 11 的定址法；**與 10 同一筆記錄的另一條邊** |
| 13 | `Person.references` / `Organization.references` 中 verdict 欄位對的 `value` | work／person／organization（by key） | **僅限封閉欄位對** `resolution-confirmed`／`resolution-rejected`（#232）；value 文法 `<kind>:<key> :: <literal>`。正典側是**被判定的記錄**：verdict 是關於它的同一性的事實，存在 entry 側會讓 work 長出無上界的 per-person 清單，且 reject 依規格不動 entry。與 11 **不同條**：11 指向存檔內容（content-addressed），13 是 `ProvenanceReference.value` 首次成為跨 entity 指標（by key）——`rename` 因此必須遷移 `work:` value（#232 verify NEW-1 實測不遷移＝否決安靜變回待判） |

**每一條邊只存一次，存在上表指定的那一側。反向一律現算。**

新增下一條 = 改這張表 + 說明為什麼那個方向必須是正典。**不得**因為「這樣讀比較快」
或「這樣呈現比較方便」而加——那兩個理由要的是索引或入口，不是欄位。

#### 怎麼機械檢查這張表真的封閉（不是靠相信作者窮舉過）

這張表**兩次**宣稱窮盡、**兩次**是錯的。所以它不能只留一句「請窮舉」——要留**可執行的
稽核程序**。收錄判準是：**一個會被序列化進 `entities/` 或 `libraries/`、且其值指涉另一個
實體或一份存檔內容的欄位。**（純量的外部識別碼——`orcid`／`openalex`／`Entry.provenance`
的 Zotero key——**不算**：它們指向的是 store 之外的權威記錄，不是 store 內的東西。這條
邊界是**判定**，不是推導出來的；要改請改這一句。）

依此稽核：

```bash
# ① 有哪些形狀（不要只 grep 你想得到的型別——這是第一次出錯的原因）
grep -n "case " Sources/AkashicCore/YAML.swift   # EntityKind.allCases
# ② 每個形狀的每個欄位（第二次出錯的原因：補了形狀、沒窮舉它的欄位）
grep -nE "public var" Sources/AkashicCore/{Models,Organization,Divergence,Temporal,Provenance}.swift
# ③ 逐欄位問：它會被序列化嗎？它的值指涉另一個實體或一份存檔嗎？
```

第 ③ 步答「是」而不在上表者，就是表壞了 —— **不是那筆資料違法**。

#### 兩個必須寫出來的邊界（否則列舉的封閉性是假的）

- **9／10 是短暫記錄。** `divergence` 是 `EntityKind` 的第四個成員、與 work／person／
  organization 並列住在 `entities/`，所以它**是**關係邊、不能因為「感覺不像」而漏列。
  但它的生命週期不同：消歧之後整筆刪除。呈現面的義務因此是「這個人牽涉哪些**未決**的
  同一性問題」，而不是歷史。
- **11／12 指向的不是 entity，是內容。** 第 6 條（`Entry.attachments → 檔案`）已經開了
  這個先例——指向非 entity 的東西仍然是存下來的邊。把它們列進來是為了封閉性，不是為了
  要求呈現面顯示 digest。**兩條都要列**：`references`（11）與 `judgement.restsOn`（12）
  用同一套定址法但住在不同形狀，只列一條就是第二次不封閉的原因。
  > **裁決（#280，2026-08-14）**：resolution verdict（第 13 條的 ProvenanceReference）
  > **刻意不攜 rests-on**——證據載體依生命週期分工：已判定 → 被判實體的 `references`
  > （第 11 條）；未判定 → divergence 的 `judgement.restsOn`（第 12 條）。這是設計不是
  > 缺口；不得因「verdict 也該綁證據」而給第 13 條長出第二個內容指標。
  > 實際後果（已修，#251）：`SourceStore.missingSourceDigests` 曾只掃 `people` 與
  > `organizations` 的 `references`、不掃 divergence 的 judgement——報告對消歧證據
  > 鏈全盲。2026-08-15 起第 12 條邊在掃描範圍；同輪修掉「讀不到折成缺席」（#265）。

#### 對稱邊的約定（判準沉默的地方）

第 3 條 `related` 是 **work ↔ work 的對稱關係**：刪掉任一端那條邊都消失，所以
「哪一側存」的判準對它**不裁決**。現行存在 entry 側是**約定**，不是推導出來的。
標出來是為了讓下一個人知道那不是判準的結論，不要拿它去類推。

> **這張表錯過兩次。**
>
> **第一次**：寫「8 條、store 裡僅有」，漏掉 9／10／11——因為作者只
> grep 了 `Entry`／`Person`／`Organization` 三個型別就下了窮盡的結論。`common-spec-prose-enumeration.md`
> 說封閉列舉的價值全在它真的封閉；**一份宣稱窮盡卻漏案例的列舉比沒有列舉更糟**，因為
> 讀者會拿它去推導「divergence 的候選不是關係邊 → 不需要呈現 / 可以隨手改」。
> 由 `PsychQuant/Akashic-Library#220` 的 verify R1 抓出（requirements 與 regression 兩個
> lens 獨立命中）。
>
> **第二次**：改成 11 條、並在這裡寫下「先看 `EntityKind.allCases`」之後，作者**照做了**
> （補進 divergence 形狀）**卻只補了那個形狀的兩個欄位**——`judgement.restsOn` 是第 12 條。
> 方法論的修正沒有實際窮舉那個形狀。同一輪 R2 verify 抓出。
>
> 兩次的共同點：**作者相信自己窮舉過**。所以現在的防線不是更嚴厲的告誡，是上面那段
> **可執行的稽核程序**——它不需要相信任何人。
>
> **第三次**（#232，2026-08-13）：這次不是「宣稱窮盡卻漏列」，是**新增了一條邊
> （verdict `value`）而沒有同步改表**——實作 commit 未動本檔，由 verify 的
> requirements 席跑上面的稽核程序抓出（第 ③ 步對 verdict value 答「是」而表裡沒有）。
> 稽核程序第一次以「抓到真缺口」的方式證明了自己的價值；第 13 條隨修正補入，
> 並附帶行為後果（rename 遷移）——漏列不只是文件不完整，是**沒有任何遷移路徑
> 知道這條邊存在**的原因。

### 不得儲存的（同一件事的另一面）

上表**反向**的任何欄位。具體到已經被提議過並否決的：

- person 記錄的 `works:` / `publications:`（1 的反向）
- work 的 `citedBy:`（2 的反向）
- organization 的 `members:`（7 的反向）
- tag 的成員清單（4 的反向）
- person／organization 的 `divergences:`（9 的反向）——「這個人牽涉哪些未決同一性
  問題」由掃 divergence 記錄算出，不在被指涉的那一側存一份

`PersonCLITests.testPersonTypeHasNoWorksMember`（型別反射）與
`testHandWrittenWorksFieldLandsInUnknownFields`（tolerant-preserve 反向）是第一條的機械防線。

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
- 全域 `common-spec-prose-enumeration.md`：**上表**是封閉列舉，刻意不寫成「凡是關係
  都存在擁有它的一側」那種總括判準——那句話的字面涵蓋範圍大於上表，會在邊界上自己
  長出新的一條，而每一條多餘的邊都是一次安靜的分岔。
  （**這裡刻意不重複條數。** 先前這段寫死「8 條…第九條」，表格改成 11 條時沒跟著改，
  於是同一份規則裡有兩個計數——正是那條全域規則描述的「總括判準與封閉列舉分岔」
  在同一個檔案內重演。引用「上表」而非數字，讓它不可能再分岔。）
- `docs/explainers/entity-vs-view.md`：view 判準為什麼住 `config.yaml`。本規則
  只引用它、不複製（複製 = 兩份會分岔的規格）。
