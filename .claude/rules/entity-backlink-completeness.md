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

> **這張表是序列化主張，不是建模主張（#221）。** 它說的是「這條邊寫在哪個實體的 YAML
> 檔裡」——**不是**「世界上只有這 14 種關係」。在查詢層「哪一側」已經沒有意義：
> `LibraryIndex` 把 authorship 存成 join 表並在兩端建 index，所以整體架構是
> **canonical 是 document、derived 是 relational projection**。
>
> 這個區分要寫出來，是因為「可儲存的關係邊」這個說法聽起來像建模主張，而
> `docs/explainers/entity-vs-view.md` 已經抓過同一個病一次——**「是記法先犯的錯」**。
>
> **另見 [`docs/explainers/which-side-does-a-relation-live-on.md`](../../docs/explainers/which-side-does-a-relation-live-on.md)**
> ——面對一條新關係時的兩步提問（可表達性／存在依賴），含**兩步不一致時怎麼辦**。
> 那份文件明寫它是**思考輔助不是裁決程序**：它的輸出必須落回下表，不允許讀者拿它
> 自行類推出沒寫下的邊。本規則只引用它、不複製（複製 = 兩份會分岔的規格）。

以下 **15 條**是 store 裡**僅有的**關係邊。**封閉列舉，不得依性質相似類推下一條**：

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
| 9 | `Divergence.candidates` | work／person／organization／**venue**（#553） | `key` + `shape: EntityKind`；**短暫記錄**，消歧後即刪。venue 是 2026-09-11 加入的——在此之前 `recordDivergence` 的 `byShape` 白名單不收它，所以那條邊**記不下來**（`EntityKind` 早有 `.venue`，擋住的是白名單而不是值域）。`.organization` 仍是半吊子：記得起來、`resolveDivergence` 解不掉——**那是 #555 的顯式裁決**（使用者 2026-09-11：暫不做，既不實作也不拿掉；理由、代價與觸發條件在 `zero-instance-guards` 第 24 列，`StoreHealth.unmergeableDivergences` 讓第一筆出聲、移除面見 #586）。重開那個裁決時本列一起改 |
| 10 | `Divergence.judgement.prefers` | 本記錄的某個候選 | decode 時驗證存在性；同樣短暫 |
| 11 | `Person.references` / `Organization.references` / `Venue.references` | `sources/` 的內容 | `ProvenanceReference`，content-addressed（`sha256:`）；`Venue.references` 於 #304 venue change 隨形狀新增——同型別、同定址法，列入以維持封閉性 |
| 12 | `Divergence.judgement.restsOn` | `sources/` 的內容 | 同 11 的定址法；**與 10 同一筆記錄的另一條邊** |
| 13 | `Person.references` / `Organization.references` / `Venue.references` 中 verdict 欄位對的 `value` | work／person／organization／venue（by key） | **僅限封閉欄位對** `resolution-confirmed`／`resolution-rejected`（#232）；value 文法 `<kind>:<key> :: <literal>`。正典側是**被判定的記錄**：verdict 是關於它的同一性的事實，存在 entry 側會讓 work 長出無上界的 per-person 清單，且 reject 依規格不動 entry。與 11 **不同條**：11 指向存檔內容（content-addressed），13 是 `ProvenanceReference.value` 首次成為跨 entity 指標（by key）——`rename` 因此必須遷移 `work:` value（#232 verify NEW-1 實測不遷移＝否決安靜變回待判）。`resolve-venues` 的 verdict 落被判定的 venue 記錄（#304，同一欄位對、同文法）。**venue 側是 O(catalog)**（#499，2026-09-04 裁決候選 3）：一本刊的 verdict 數＝被歸戶的作品數，`psychological-methods` 實測 1,352 筆；序列化位置**不改**，改在 decode 硬預算的一半設 warning（`AliasEventBudget.venueVerdictWarningThreshold`，`StoreHealth.venueVerdictBudgetWarnings`）。達門檻＝重開本條的規模化裁決，那時的形狀是 sidecar ledger（本表改指向 sidecar、12 格遷移改讀寫）——不是 per-literal 聚合（那會打回 #464／#463 的 per-holder 前提） |
| 14 | `Entry.venues` | venue | `.key` 已歸戶／`.literal` 未歸戶，兩者都合法（與第 1 條同二態形；#304。作品側正典的六理由同適用——刊名沿革中舊文章掛舊刊名即第 4 條可表達性的 venue 版；編年 list 由本邊反向現算，venue 記錄**不存**文章清單） |
| 15 | `Entry.references` | `sources/` 的內容 | 同第 11 條的定址法（content-addressed `sha256:`），但住在 **work** 上——#394 §5 新增。**正典側是 work**：識別碼（`doi`／`pmid`／`isbn`）是那筆作品的屬性，來源說的是「這個號是從哪裡查到的」，那件事只跟該作品有關。值域：三個識別碼欄位 ＋ **`authors`** ＋ **`fields.<鍵名>`**（#517，見下）（#450，2026-09-07：**拆分記錄**——value 是**已退役**的原 literal，與其他三格「值必須在場」的語意相反；一致性條件是 statement 各段至少一段仍是作者位，由 `StoreHealth` 報 warning（`staleSplitRecords`）而非 decode 拒收；statement 走 `SplitRecordValue` 單一解析器、空 rests-on 經 `firstOrderRulingFields` 放行、store format 16）。**#517 起多一格 `fields.<鍵名>`**（見表下方「第 15 條邊的兩次擴充」）——`title`／`date` 仍不得類推（`validateReferenceAttachment` 的 `default` 照舊拒絕）。 **為什麼在此之前不存在**：`Entry` 原本沒有 `references`，而 provenance-reference spec 明寫「不能攜帶 reference 的識別碼不算記錄的一等公民」——照字面，work 的三個識別碼在補上它之前不算一等公民，而那正是 #394 的標題所主張的東西 |


#### 第 15 條邊的兩次擴充（#450 的 `authors`、#517 的 `fields.<鍵名>`）

> **`authors` 那一格自 #457 起收兩種記錄**（值域沒有再擴，收的仍是 `authors`）：拆分（`拆為 ⟦a⟧ ⟦b⟧：理由`，退役後留 N ≥ 2 段，format ≥ 16）與**移除**（`移除：理由`，留 0 段，format ≥ 17）。兩者的 value 語意相同——**已退役的作者 literal**——差別只在退役之後剩幾段，所以住同一個 field，由 statement 前綴分辨、各有唯一解析器。
> **一致性條件相反**：拆分要求「至少一段仍是作者位」（`staleSplitRecords`），移除要求那個字串**不在**作者位（`contradictedRemovalRecords`），兩者都是 warning。
> 兩種記錄的 field 相同不是巧合：它們是同一件事（作者位的退役）的兩個結果。

#517 一次裁兩件事，因為它們是同一個洞的兩面：

- **前綴不是風格。** `Entry.fields` 的鍵由來源決定（`lossless-intake`），所以它**必然**與 reference 保留的欄位名撞上——2026-09-09 實測 live store：40 種鍵，其中 `doi` 3 筆、`isbn` 3 筆同名。裸鍵名之下「`field: doi` 指哪一個」**今天就已經是歧義**。前綴讓那個歧義寫不出來（3.325 的同一個立場），而不是靠一份會漏的白名單。
- **value 缺席 ＋ retrieval ＝ 對這個欄位做過的一次查找。** 欄位在場 → 值出自它；欄位缺席 → **查過了，沒有**。在此之前那個狀態寫不出來：`doi` 的 reference 必須帶 value，而 value 必須是清單成員——清單空的時候沒有任何合法寫法，於是「沒查」與「查了沒有」在 store 裡是同一個觀察（`lossless-intake` 執行細節 3 的形）。
- **kind 必須是 retrieval**，因為一次查找的 **url 與日期沒有別的地方記**：`sources/index.jsonl` 記 origin／retrieved／media-type，**不記 url**。
- **空 rests-on 的 judgement 走不進來**（那是被否掉的另一條路）：`fields.*` 與識別碼都不在 `firstOrderRulingFields`，平面 init 已經擋下。所以走 judgement 的必然帶著真的 digest——離線來源（紙本掃描件）因此表達得出來，而 `retrieval` 的 url 是必填的。
- **刻意不檢查 `fields[鍵]` 在場**：那正是負結果的形狀。代價寫出來——打錯的鍵名會靜靜附上去，沒有東西擋得住；要擋它就得放棄負結果的表達法。

**每一條邊只存一次，存在上表指定的那一側。反向一律現算。**

新增下一條 = 改這張表 + 說明為什麼那個方向必須是正典。**不得**因為「這樣讀比較快」
或「這樣呈現比較方便」而加——那兩個理由要的是索引或入口，不是欄位。

#### 怎麼機械檢查這張表真的封閉（不是靠相信作者窮舉過）

這張表**兩次**宣稱窮盡、**兩次**是錯的。所以它不能只留一句「請窮舉」——要留**可執行的
稽核程序**。收錄判準是：**一個會被序列化進 `entities/` 或 `libraries/`、且其值指涉另一個
實體或一份存檔內容的欄位。**（外部識別碼——`orcid`／`openalex`／`Entry.provenance`
的 Zotero key／#394 起的 `Venue.issn`／`Organization.ror`／`Entry` 的 `doi`・`pmid`・`isbn`
——**不算**：它們指向的是 store 之外的權威記錄，不是 store 內的東西。這條
邊界是**判定**，不是推導出來的；要改請改這一句。）

> **這句先前寫「純量的外部識別碼」，#394 把「純量的」三個字拿掉了。** 那個限定詞是
> 描述當時的實例（`orcid`／`openalex` 恰好都是純量），不是理由的一部分——排除的根據
> 是**指向 store 之外**，而基數與指向哪裡無關。`Venue.issn` 是清單（print 與 electronic
> 是兩個真的號），若留著「純量的」，它就會落在判準的字面之外而**看起來**該進封閉列舉，
> 於是一個外部識別碼被當成關係邊。
>
> 這正是本檔與全域 `common-spec-prose-enumeration` 反覆記過的形狀：**限定詞若不是理由
> 的一部分，就會在下一個實例上把判準切錯邊**。改這一句而不是推導，是規則自己要求的。

依此稽核：

```bash
# ① 有哪些形狀（不要只 grep 你想得到的型別——這是第一次出錯的原因）
grep -n "case " Sources/AkashicCore/YAML.swift   # EntityKind.allCases
# ② 每個形狀的每個欄位（第二次出錯的原因：補了形狀、沒窮舉它的欄位）
grep -nE "public var" Sources/AkashicCore/{Models,Organization,Divergence,Temporal,Provenance,Venue}.swift
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
- venue 記錄的 `works:`／文章清單（14 的反向）——編年 list 由 `venue_refs` 索引
  現算（`QueryEngine.venueWorks`），期刊的「編年期刊 list」是呈現不是欄位（#304 裁決五a）

`PersonCLITests.testPersonTypeHasNoWorksMember`（型別反射）與
`testHandWrittenWorksFieldLandsInUnknownFields`（tolerant-preserve 反向）是第一條的機械防線。

### 考慮過但**暫不新增**的邊（附觸發條件）

被提議、經裁決**暫時不加**的邊記在這裡。留著是為了讓下一個人不必重新發現缺口，也不必
重新推導一次結論——而**每一列都要附一個可檢查的觸發條件**，否則「暫時」會變成「永遠」
而沒有人知道。

#### work → work 的「被收錄於」（#339，2026-08-19 裁決：暫不新增）

**問題**：一章收錄於哪本編著，目前只能靠 `fields.booktitle` 的純量字串表達。同一本書被
多章引用時，在 store 裡是**多個彼此無關的字串**——改一個不影響其他；問「這本書收錄了
哪幾章」沒有機制答得出來。

**方向不是問題，規模才是。** 套
[`docs/explainers/which-side-does-a-relation-live-on.md`](../../docs/explainers/which-side-does-a-relation-live-on.md)
的兩步提問，兩步同向指向**章側**：

| 步驟 | 問 | 答 |
|---|---|---|
| 一（可表達性）| 那本書的記錄還不存在時，能誠實記下來嗎？ | 章側可（`booktitle` literal）；書側連檔案都沒有 |
| 二（存在依賴）| 刪掉一端，事實還在嗎？ | 刪書 → 章仍記著字串；刪章 → 沒了 |

也就是說 `fields.booktitle` **已經在對的那一側**了。問題只剩「純量該不該升格為 ref」。

**裁決：暫不升格。** 三個理由：

1. **實測 6 筆**（#339 立案當時），而其中只有 1 個容器被共用（`The Stanford Encyclopedia
   of Philosophy` ×3）。新增一條封閉列舉的邊要付的代價是：本表加一列＋merge 閘＋反射守衛計數＋YAML
   編解碼與封閉鍵域＋`resolve-*` 一族（提名／verdict／tier）＋index 反向查詢＋
   `literal-first-then-key` 的 campaign 納入＋MCP/CLI parity 裁決。那是兩個中型 issue
   的量級。
2. **APA7 下限已達**：`INCOLLECTION` 的必要欄位含 `BOOKTITLE`，而它在場。所以這不是
   `apa7-is-the-work-floor` 的破底，是**表達力**問題。
3. **venue 那條路已被 #324 關掉**：不得把 edited book 塞進 `VenueType`——那會製造一個
   結構上無法持有 APA7 要求欄位的 venue，是把「模型接不住」搬個位置而不是修掉。

> ✅ **觸發條件曾成立、已於 2026-08-23 處置完畢（#339）——本裁決維持「暫不新增」。**
>
> **經過**：#407 R33 重跑時兩個觸發條件都成立（6 → 31 筆；最大共用 ×3 → ×10），
> 於是回頭重做裁決。拆解那 31 筆之後，**兩個門檻幾乎完全由「參考工具書」那一群造成**：
>
> | 群 | 筆數 | 容器 |
> |---|---|---|
> | `wikipedia-entry`（#409 起 `reference-work-entry`） | 14 | 維基百科 ×10 ＋ Wikipedia ×4（**同一個容器的兩個語言變體**） |
> | SEP 條目（**當時**型別是 `book-chapter`；#409 起 `reference-work-entry`） | 3 | The Stanford Encyclopedia of Philosophy ×3 |
> | 真正的編著章節 | 14 | 14 個容器，**每個 ×1** |
>
> **裁決（使用者 2026-08-23）：參考工具書的容器走 venue，不走 `booktitle` ref。**
> 理由是 #324 自己的判準（§11：「它決定了哪些欄位存在」）——#324 關掉的是**編著**
> 那條路（編著索取 `BOOKTITLE + EDITOR + PUBLISHER`，venue 持不住），而參考工具書
> 是持續出版的線上工具，沒有逐卷編者與同義的出版社，索取的欄位組接近
> `website`／`database`，而那兩個值 `VenueType` 已經有。**把兩者混為一談，正是
> 「依性質相似類推」。**
>
> **落地**：`VenueDerivation.booktitleCarrierTypes`（原名 `proceedingsTypes`，加入
> `.wikipediaEntry`（#409 起 `.referenceWorkEntry`）後名字說謊，故改名）＋ `migrate-venues` 回填 ＋ 一個 `wikipedia`
> venue 實體（`type: website`，四個名稱變體）＋ `resolve-venues` 歸戶 14 筆。
> zh/en 兩個字串的合一由既有的 `resolve-venues` 免費涵蓋——走第 15 條邊則要重造一套。
>
> **原本的觸發條件量錯了東西，一併修正。** 它數的是「帶 `booktitle` 的記錄」，而
> `lossless-intake` 規定來源欄位不刪——所以容器改由 venue 邊承載之後，那個數字
> **完全不會下降**（實測仍是 31）。要數的是**仍只有純量字串、沒有任何 ref 承載
> 容器**的記錄。

**觸發條件（任一成立即重新裁決；2026-08-23 實測 14 筆／最大 ×3，兩者皆未達）**：

- **容器仍只是純量字串**（`booktitle` 在場而該記錄沒有 `venues:` key 邊）的記錄
  **≥ 20 筆**，或**單一容器被 ≥ 5 筆共用**
  ```bash
  python3 - <<'EOF'
  import glob, io, re, collections
  uncov = collections.Counter()
  for f in glob.glob('/Users/che/.akashic/entities/*.yaml'):
      t = io.open(f, encoding='utf8').read()
      m = re.search(r'^  booktitle: (.+)$', t, re.M)
      if m and not re.search(r'^venues:\n- key: ', t, re.M):
          uncov[m.group(1).strip()] += 1
  print(sum(uncov.values()), max(uncov.values()) if uncov else 0)
  EOF
  ```
- ~~或 **`INREFERENCE` 一族的容器需求浮現**~~ —— **已於 2026-08-23 由 #409 消解**。

  > 這一條原本寫著：那 3 筆 SEP 條目與 14 筆維基條目是同一種東西，但型別不同
  > （`book-chapter` vs `wikipedia-entry`），所以走不進 `booktitleCarrierTypes`；
  > 把 `.bookChapter` 加進去會把 14 筆真正的編著章節一起掃走，**要修的是型別**
  > （`wikipediaEntry` 這個名字對 SEP 過窄）。
  >
  > **#409 就是去修那個型別的**：`wikipediaEntry` → `referenceWorkEntry`
  > （rawValue `reference-work-entry`）。理由是它自己的三個下游對照——APA7 §10.3
  > 「Entries in **Reference Works**」／biblatex `INREFERENCE`／CSL
  > `entry-encyclopedia`——**沒有一個說 Wikipedia**。改名後 3 筆 SEP 一併改型別，
  > 走進 `booktitleCarrierTypes`、歸戶到 `stanford-encyclopedia-of-philosophy`
  > venue。實測「仍只有純量字串」從 **14 筆／最大 ×3** 掉到 **11 筆／最大 ×1**。
  >
  > **這一條保留而不刪除**：它是本裁決「暫不新增」得以維持的原因之一，刪掉會讓
  > 上面那個量測看起來憑空變好（`mcp-cli-parity` 對退場命令「劃掉而非刪除」的同一
  > 立場——刪掉會丟失裁決史）。


#### entity → entity 的「分裂／繼承」（#421，2026-08-25 裁決：暫不新增）

**問題**：一個期刊一分為二（實例：JRSS Series B／C），或一個機構改組。`Venue`／
`Organization` 有 UUID 身分與 names timeline，但「這個實體從那個實體分出來」**零機制、
零詞彙**。

**裁決：暫不新增**，理由不是「還沒發生」——JRSS 的分裂是真的發生過的事：

> issue body 稱 JRSS Series B／C 是「未被表達的實例」，診斷查證後修正為：它是模型
> **表達不了**的一件真事，**不是**模型算錯的一件事 —— 目前無任何查詢因缺那條邊而出錯。

那個修正是關鍵：**表達不了 ≠ 算錯**。加這條邊要付的代價是本表加一列、YAML 編解碼、
遷移、以及「分裂後舊的那個還在嗎」這個**形上學前提**（它需要選擇，不是查證）——而
換到的是一個目前沒有任何查詢在問的答案。

**觸發條件（任一成立即重新裁決）**：

```bash
# ① 有查詢因缺這條邊而給出錯的答案（不是「表達不了」，是「答錯」）
#    ——目前為 0，且這一格沒有機械量測，需要人指認
# ② 帶時間欄位的 names 段出現（＝沿革真的開始被用，而分裂是它的鄰居）
python3 -c "
import glob,io,re
n=0
for f in glob.glob('\$HOME/.akashic/entities/*.yaml'):
    t=io.open(f,encoding='utf8').read()
    if not (t.startswith('venue:') or t.startswith('organization:')): continue
    m=re.search(r'^names:\n((?:- .*\n|  .*\n)+)',t,re.M)
    if m and re.search(r'(from|until|since|start|end):',m.group(1)): n+=1
print(n)"   # 2026-08-28 實測：0
```

**同案的另外兩層一併記在這裡**（它們不是關係邊，所以不進上表，但屬同一次裁決）：

| 層 | 裁決 | 為什麼 |
|---|---|---|
| **Person 的名字要不要有時間軸** | 暫不做 | blast radius 46 個呼叫點／27 檔，而零實測損害 |
| **`Venue.issn` 要不要跟著 names 變 timeline** | 暫不做 | **前提未滿足**：405 個 venue、35 個多名字、**帶時間的 0 個**且全是異寫法——加 `issn` 時間軸會做出**第二條空軸**。另有型別前提：`TemporalValue<V: Equatable & Comparable>` 而 `Identifier` 無 `Comparable`，`TimelineOf<ISSN>` 今天編不過 |

**第二層的前提正在被 #422／PR #437 處理**（把異寫法從 names 時間軸搬進 `variant` 分割）
——那之後 names 的時間軸才可能只裝沿革，而「第一條軸有沒有在用」才成為可問的問題。

## 為什麼：不對稱（與 `lossless-intake` 同形，方向相反）

| 選擇 | 代價 |
|---|---|
| 存一次、反向現算 | 每次呈現要查一次索引。微秒級，而索引本來就在 |
| 兩側都存 | **兩份 canonical state**。歸戶、改名、刪除、合併都要同步，而它們**會**分岔 |

分岔的糟糕之處在於它**安靜**：兩份都看起來像真的，沒有任何跡象指出哪一份過期。
`lossless-intake` 說「不收會讓命題永久不可判定」；這條說「存兩份會讓命題**同時**
有兩個答案」。前者是缺，後者是矛盾——**矛盾比缺更難發現**。

反過來，衍生**不可能分岔**：只有一個來源。

### 哲學補強（#300 審議，2026-08-16）：好記法該讓矛盾寫不出來

上面的工程論證（「會分岔」）有一個更深的版本，來自《邏輯哲學論》3.325 的工程類比
（**受稽核類比**，非哲學宣稱——劃界紀律見 `docs/tractatus/` README 與 #235）：

> 要用一種受邏輯文法約束的記號語言，使錯誤在其中**不可能發生**。

雙側儲存的問題不只是「兩份會不一致」，而是：它讓 store 這個記法**有能力表達一個
不可能的世界**——兩份 copy 分岔時，store 同時「說」P 著有 W 與 P 未著有 W，而沒有
任何可能的事態使之成立。單側儲存＋反向現算是讓這種無意義組合**在文法上寫不出來**
的記法：分岔不是被檢查擋住，是無處可寫。同族的支持文本：2.03（關係中對象「如鏈環
相扣」、沒有第三個東西扣住它們——把 authorship 抽成獨立三元組記錄反而是把關係實體
化成第三項）與 3.1432（關係之成立由記號的結構性排列顯示——person key 出現在
`authors` 序列裡就是該事態的表達）。

> **另見（#302 裁決，2026-08-19）——這不是第七條理由。** #300 的 residue「作者身分的
> 存在論：『我是這些作品的作者』對自我意味著什麼」已以 `analogy_only` 記在 corpus 的
> **5.632**（主體不屬於世界，而是世界的一道界限）。那條 relation 指出的是**記法層的
> 可查證事實**：下方封閉列舉裡沒有任何 person → work 邊，而「person 記錄的 `works:`」
> 明文在不得儲存之列——所以在這個記法中，作者確實不是「裡面裝著作品清單」的那種東西。
>
> **但那是呼應，不是證成。** 本節設計的證成是下方六條理由；5.632 不增列為第七條，
> 依 #300 同案裁定的「Tractatus 對照維持受稽核工程類比地位、不升格為規範判準」。
> 混同兩者會重演該案已裁決過的界線問題。

## 為什麼正典側是**作品側**（#300 裁決，2026-08-16）

單側儲存決定後還有第二個問題：邊存哪一側。`Entry.authors`（作品側）是裁決結果，
不是偶然。六個理由，強度遞減：

1. **有界 vs 無界**：作品的作者清單在作品誕生時即封閉（byline 印在紙上）；人的著作
   清單終身開放。有界側的記錄可以**完整為真**；無界側的清單永遠是「目前看到的」
   冒充「全部」。
2. **事實與其出處同在**：authorship 跟著作品到達（byline、WoS 列、BibTeX 筆）。
   作品側＝事實存在它被證立的地方，與 `lossless-intake` 的來源單位同構；人側＝每筆
   匯入拆散來源、散射寫入 N 個 person 檔。
3. **序即結構**：作者順序（第一作者、通訊作者）是作品的屬性——配置本身攜帶語意，
   作品側原樣保存；人側的 works 清單沒有對應的結構性配置。
4. **未歸戶作者的可表達性**（工程上決定性）：`.literal` 作者只能住在作品側——人側
   正典儲存連檔案都沒有可放這筆事實。
5. **存在依賴的方向**：authorship 存在上依賴作品（無作品即無此事實）、不依賴 person
   記錄（無名氏的作品仍有作者）。刪作品，authorship 原子性同死；person 合併只是
   機械遷移 key。
6. **變更頻率的局部性**：新增作品在作品側寫一檔，在人側寫 N+1 檔。

**六條裡沒有一條是「查詢方便」**——那是索引（`idx_authors_key`）的職責，不是儲存
落位的論據（執行細節 1 的既有立場）。

裁決脈絡：#300（使用者以 Tractatus 提問「authorship 該不該記錄在文章裡」）；同案
一併裁定 Tractatus 對照維持「受稽核工程類比」地位（per-proposition 裁決、劃界措辭，
不升格為規範判準）。相關 corpus 條目：2.03／3.1432／3.325 的 `project_relations`。

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

2. **一個 entity kind 的讀取面只能有一條實作路徑。** **三個面**——CLI、MCP、**App**
   ——必須落到同一個函式。兩邊各自查一次 = 兩條會分岔的路徑，那是本規則在儲存層
   禁止的事在讀取層重演。

   > **App 是 #263 補上的第三個面。** 這條先前只點名 CLI 與 MCP，而 App 在結構上
   > 同位置卻不在列舉內——於是它長成**第三條獨立實作路徑**而沒有違反任何寫下來的
   > 規則：健康總覽的六個數字全由 `AppState` 自行推導，**完全不呼叫**
   > `AkashicService.doctor()`（實測全樹唯一命中是一行註解）。
   >
   > 失敗模式的差別很實：**子集只會少，獨立路徑會分岔**——App 可能顯示健康數字而
   > `doctor` 對同一 store 報問題，而使用者沒有任何線索知道哪個對。而 App 是取代
   > Zotero 的主要 UI（`replace-endnote-and-zotero`），只用 App 的人永遠不會知道
   > audit trail 正在腐爛。
   >
   > **落到同一個函式不等於落到同一個入口。** `doctor()` 會 `rebuild()` index
   > ——**它不是唯讀的**，所以 App 每次刷新都呼叫它是不可接受的副作用。#263 的解法
   > 是把**唯讀的**事實抽成 `StoreHealth`（`LibraryStore.health(from:)`），兩面各自
   > 渲染它；`doctor()` 在其上額外做 rebuild 與統計。共用的部分只有一條路徑，各自
   > 獨有的部分是各自的職責。
   >
   > 機械防線是 `StoreHealthSurfaceTests`：以**反射**取 `StoreHealth` 的全部欄位，
   > 逐一要求兩個消費面都提到它。人工清單會與型別分岔——那正是本檔的表錯過三次的
   > 形狀。

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
