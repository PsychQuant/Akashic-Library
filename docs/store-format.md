# Akashic Store 格式規格書（v1.3，#23 tolerant-preserve 修訂）

Akashic library 的 canonical store 格式。本文件是 spec §4 的正式版；
實作＝`AkashicCore`（型別/YAML/citekey）＋ `AkashicStoreIO`（讀寫）。

原則：**檔案是本體，資料庫是 cache**。記錄檔是 canonical、git 追蹤；
衍生的 index 可全刪重建。

> `notes/<citekey>/*.md` 曾在此宣告為佈局的一部分，但自宣告以來沒有任何寫入端，
> 已於 #103 撤下。日後真要做衍生筆記，從設計開始另開 issue。

## 1. Library 佈局

佈局**依 store format 而定**，而 `ensureLayout()` 只建立這個 store 實際會用到的
目錄——所以「目錄存在」本身帶語意（#101）。

### format ≥ 2（現行）

```
<library-root>/
├── store.yaml                  format 標記（§5）
├── entities/<uuid>.yaml        全部記錄：work / person / organization / divergence
├── libraries/<key>.yaml        library registry（§2.9）
└── .akashic/                   **僅未註冊的 store**：in-store 的 index 回落位置
```

### format 1（legacy，仍可讀）

```
<library-root>/
├── store.yaml                  #24 之前建的 store 沒有這個檔——**缺檔即 format 1**
├── entries/<citekey>.yaml      每筆文獻一檔
├── people/<person-key>.yaml    人物實體
├── libraries/<key>.yaml
└── .akashic/                   同上：僅在沒傳 registry key 時才有
```

讀取端**兩種佈局並存支援**：遷移是一次性動作，但舊佈局的 store（含別人的 clone、
未遷移的備份）必須照樣讀。寫入端則單一：`store.yaml` 的 format 決定寫去哪邊。

### `ensureLayout()` 建哪些目錄

| 目錄 | `ensureLayout()` 何時建 |
|---|---|
| `entries/` `people/` | 僅 format 1 |
| `entities/` | 僅 format ≥ 2（#102）|
| `libraries/` | 一律 |
| `.akashic/` | 僅當開這個 store 的呼叫端**沒有傳 registry key** |

`store.yaml` malformed 或 too-new 時 `ensureLayout()` **整體拒絕、零磁碟副作用**——
不會依猜測建任何目錄（normative 定義見 §5.0，#106）。

index 帶**身分戳記**（#122）：`index_identity` 表記錄它是為哪個 store root（canonical
path）、何時、以多少筆記錄建的。讀端的 `isCurrent` 比對 schema 版本**與**身分——
registry 路徑被重新利用（舊 store 刪除、新 store 用同一 key）時，`index/<key>.sqlite`
是別的 store 建的，只看版本會整份讀到別人的資料。

**既有 store 的殘留**由 `doctor` 報告（#107，report-only 不代刪）：依當前 format 與 key
不該存在、且為**空目錄或純衍生物**的路徑（migrate 留下的空 legacy 目錄、keyless 時期的
孤兒 in-store index、#103 撤下後的空 `notes/`）。含資料的目錄永不報；`sources/`（#66 的
被指涉內容、只留 local 的唯一一份）絕不列入。

**預設 store 的特例**：`~/.akashic` 同時是 akashic home 與 store root，所以
`index/<key>.sqlite` 字面上位於 store root 之內——那是 home 的一部分，**不是殘留**
（分離的實益是「不在 canonical 樹裡、且有名字」，不是路徑上的包含關係）。

**已註冊的 store 的 index 住 store 之外**（`~/.akashic/index/<key>.sqlite`，#37）：
store root 正是會進 Dropbox／git 的東西，而同步樹裡的 live SQLite 是已知的毀檔風險
（partial write、conflict copy）。沒有 key 的 store 沒有名字可命名 index，才回落到
in-store 的 `.akashic/index.sqlite`。

> ⚠️ **反過來讀不成立**：目錄的存在**不是**可靠的判準。
>
> - **`.akashic/` 存在 ≠ 這個 store 未註冊**——它可能是 #105 之前的殘留（`doctor` 的
>   殘留報告會列出，#107）。#105 之後 `--library <path>` 與 `$AKASHIC_LIBRARY` 對已註冊
>   路徑**反查 registry 帶 key**，keyless 只剩「真的未註冊」；但歷史殘留與手動搬移仍讓
>   「存在即未註冊」不可反推。
> - **`entries/` 存在 ≠ format 1。** `migrate` 搬完檔案後不刪空目錄，所以就地遷移過的
>   store 會同時有空的 `entries/` 與 format ≥ 2 的 marker。
>
> 換句話說：這張表是 **`ensureLayout()` 的行為規格**，不是 store 狀態的推論規則。

> **父目錄不由 `ensureLayout` 保證**。寫入路徑自己確保目的檔的父目錄存在
> （`atomicWrite` 的單一咽喉），讀取路徑則容忍目錄缺席（回空）。
>
> root 打錯**會被寫入閘擋下來**（#108）：六個寫入 API（`writeEntry`／`writeEntryExclusive`／
> `writePerson`／`writeOrganization`／`writeLibrary`／`writeDivergence`）前置
> `assertStoreRoot`——`store.yaml` 存在或 `isLibraryRoot`（pre-#24 legacy）任一成立
> 才放行，兩者皆無＝打錯的路徑，拒絕且零磁碟副作用。CLI／MCP／App／外部呼叫端
> 一體適用；「新 store 的 format 取決於先呼叫哪個寫入 API」的分岔隨之消失。
>
> **建立入口是刻意的例外**：`ensureLayout`（`doctor`／`import-zotero`，含 MCP 的
> `akashic_import_zotero`）就是「把一個路徑變成 store」的動作——它無法區分
> 「刻意建新」與「打錯字」，指錯路徑會在該處建出空佈局（#136-F2/F3 記錄）。
> 寫入閘擋的是**繞過建立入口的裸寫**，不是建立入口本身。
>
> **呼叫端仍應先 `ensureLayout()` 或走 `openStore()`**；父目錄的保證只涵蓋「目錄」，
> 不涵蓋「這個 root 是不是一個 store」。

附件不在 library 內。副本的**位元組**進內容定址區（`sources/`，版控排除），
entry 以 digest 引用（`akashic.sources`）；尚未 ingest 的檔案留在外部文獻管理器
自己的 storage，entry 記 `zotero:` reference（見 §2.4）。

## 2. Entry 檔（`entries/<citekey>.yaml`）

### 2.1 範例（全欄位）

```yaml
id: 7C1F6C2E-1A2B-4C3D-9E8F-000000000001
citekey: cheng2025identifiability
type: periodical-article
title: Identifiability of polychoric models with latent elliptical distributions
authors:
  - key: cheng-che              # 已解析 → people/cheng-che.yaml
  - literal: Hau-Hung Yang      # 未解析裸字串
date: 2025-04-01
fields:                          # 其餘 biblatex 欄位（字串→字串）
  journaltitle: Psychometrika
  volume: "90"
  number: "2"
  doi: 10.1017/psy.2025.1
attachments:
  - zotero: storage/ABCD1234/paper.pdf    # 相對 Zotero 資料目錄
provenance:                      # Zotero namespace——pull 管理、可覆寫
  zotero_key: ABCD1234
  zotero_version: 123
  library_id: 1                    # v1.1：Zotero libraryID（personal=1、group=2+）
  zotero_hash: a1b2c3…             # v1.1：mapping 產出 biblatex 面向的 SHA-256
  imported_at: 2026-07-22T00:00:00Z
  orphaned_at: 2026-08-01T00:00:00Z        # 僅 Zotero 端已刪時出現
akashic:                         # Akashic namespace——pull 絕不觸碰
  tags: [identifiability, polychoric]
  libraries: [sinica]            # v1.2（#13）：所屬 library keys；空＝只屬全集 view
  status: published
  relations:
    cites: [olsson1979maximum]   # citekey 或 UUID；庫外引用允許
    related: [foldnes2019bivariate]
  author-list-completeness:      # 選填；只證成這一筆 work 的 exact ordered authors
    work-id: 7C1F6C2E-1A2B-4C3D-9E8F-000000000001
    author-list-fingerprint: sha256:387ccc7ec01d41db3f3e703e6622e2a676a0411754eca775b9388fb2c57c3565
    attested-authors:
      - key: cheng-che
      - literal: Hau-Hung Yang
    references:
      - field: authors
        url: https://example.org/catalogue/cheng2025identifiability
        retrieved: "2026-08-10"
        status: 200
        media-type: text/html
        content: sha256:abababababababababababababababababababababababababababababababab
      - field: authors
        judgement: 此來源逐一列出本作品的完整作者清單
        rests-on:
          - sha256:abababababababababababababababababababababababababababababababab
```

### 2.1.1 `thesis:`——學位論文的 APA7 §10.6 事實（#335，additive）

只在 `type: thesis` 的記錄上出現。**封閉鍵域**：`degree`／`availability`／
`repository`／`repository_url`。

```yaml
type: thesis
title: Paradigmatic Decisions for Measuring Choice
fields:
  institution: National Taiwan University
thesis:
  degree: doctoral              # 封閉三值：doctoral / masters / undergraduate
  availability: published       # 封閉二值：unpublished / published
  repository: ProQuest Dissertations and Theses Global   # 僅 published；可缺
  repository_url: https://…                              # 選填
```

**為什麼需要這個區塊。** APA7 §10.6 有兩張 template，差別不只是字串：未出版時授予機構
落在句末的 source element，已出版時落在**標題後的方括號內**、而 source element 換成典藏庫。
所以 `fields.institution` 有值也不夠——**該把它放哪取決於「已出版與否」**，而那個事實
先前完全不可表達。這是下限違反（`apa7-is-the-work-floor`），不是美觀問題。

**三條非顯而易見的規則**：

1. **兩個欄位都可缺，缺席＝未查，且不得折成預設值。** 把缺席的 `availability` 當成
   `unpublished` 會渲染出 `[Unpublished doctoral dissertation]`——那是一個**可能為假的
   斷言**，不是缺資訊。實測（2026-08-19）5 筆 thesis 的 `availability` 全部缺席。
2. **`availability: unpublished` 不得帶 `repository`／`repository_url`**，decode 拒讀。
   依 §10.6，未出版的論文「必須直接向該校以紙本索取」——沒有典藏庫可指。Swift 側用關聯值
   讓這個組合寫不出來，YAML 側因此也要擋，否則會出現型別接不住的檔案。
3. **`availability: published` 的 `repository` 可缺。** 手冊例 65／66 就是已出版（有典藏
   URL）卻沒有典藏庫名的形狀。要求必帶會讓遇到那種記錄的人只剩「丟掉已知事實」或
   「編造典藏庫名」兩條路。

**空區塊**（`thesis: {}`）讀成缺席，不報錯——它不矛盾，只是沒內容。反向：`ThesisFacts`
的 init 是 failable，所以兩個事實都沒有的事實物件在型別層不存在，也就寫不出空區塊。

**版本**：**additive，不 bump format**。舊 binary 讀到 `thesis:` 走 tolerant-preserve
逐字保留（同 `Entry.type` 封閉列舉的先例，#325）。

**匯出**：`degree` → biblatex `type` 欄位，token 由依賴指定
（`phdthesis`／`mathesis`／`bathesis`）；`published` 的 `repository` → `eprint`、URL → `url`。
**誠實邊界**：biblatex-apa 對「已出版 vs 未出版的學位論文」**沒有任何機制**（全樹搜尋只
命中節名字串），所以 §10.6 兩形態的**渲染**是上游缺口。模型持有這個事實是下限要求；
渲染保真度是另一件事，且本專案沒有 LaTeX 往返測試可驗。

### 2.2 必要欄位

`id`（UUID，不可變）、`citekey`、`type`、`title`。其餘皆可省略；空集合不寫出。

### 2.3 雙 ID 與 citekey 規則

- `id`：UUID，配發後永不變——為 citekey 改名保留的機器身分。
  **Phase 1 尚未提供 rename 流程**（改 citekey 需同步搬檔、更新他檔 relations；
  手改會斷鏈，rename API 是既定 follow-up）。
- `citekey`：`^[a-z0-9][a-z0-9-]*$`。自動生成規則（2026-07-22 定案）：
  **小寫第一作者姓 + 年份 + 標題首個實詞**（如 `cheng2025identifiability`）。
  - 姓：ASCII 摺疊（Müller→muller）；單欄姓名取最後一個 token；CJK 無 ASCII → `anon`。
  - 年：date 中第一組 4 位數字；無 → `nd`。
  - 首實詞：跳過冠詞/介系詞 stopwords；CJK 標題無 ASCII 實詞 → `entry`。
  - **衝突**：年份後插 `b`、`c`…（`cheng2025bidentifiability`）；26 個用盡後 `-2`、`-3`。

### 2.4 附件 reference

一律相對路徑，不記絕對路徑（換機器不斷鏈）：
- `zotero:`＝相對 Zotero 資料目錄（`storage/<attachmentKey>/<檔名>`）。
Phase 1 的 Zotero pull 只記 `zotero:` reference、不搬檔。

**鍵域是一的封閉列舉（format 9 起，#223）。** 可 ingest 的內容一律以 digest 引用、
不以檔案系統路徑引用——路徑會因搬移或改名斷鏈，且無法偵測內容變更。僅存的路徑型
引用是指向外部文獻管理器自有儲存的**過渡形式**，它存在的理由是那個管理器持有本
store 尚未 ingest 的位元組。**不得因「形狀相似」而據以新增第二種路徑型引用。**

#### 2.4.1 `akashic.sources`：記錄側的副本引用（normative，#223）

work 記錄可在 `akashic` namespace 下攜帶 digest 清單，宣告「這些已儲存內容是本
記錄所描述之作品的副本」：

```yaml
akashic:
  sources:
    - sha256:0a9a79d3030c457b7a3f54ecc98c9fa11d60b8901ffd8e709b528d47f151125a
```

- 與**欄位層級**的 `references:`（§3.5）是不同的關係項：`references` 說「這個欄位
  的值以那份內容為據」（值 ← 證據），`sources` 說「那些位元組是這篇作品的副本」
  （作品 ← 副本）。兩者**不得合併**，副本引用也不得寫成指涉整筆記錄的欄位層級
  reference。兩者只在**內容**處相遇：指向同一 digest 時各自保留、內容只存一份。
- 連結存**記錄側**、反向現算：內容先被取得、記錄後被建立，所以內容抵達當下沒有
  citekey 可填，而建立記錄時 digest 已存在——只有這一側能在對方尚未存在時誠實
  記下。不另存內容側的反向索引（兩份會分岔）。
- digest 文法沿用 §3.5 的 reference digest（`sha256:` + 64 個小寫十六進位字元），
  不合文法於載入即拒絕。
- 空清單與缺席等價，encode 不 emit 空鍵。
- digest 合法但本機無存檔＝**載入成功 + 可回報缺席**，與「記錄格式損毀」是兩種
  不同條件（同 §3.5 的既有契約）。

### 2.5 Namespace 契約（CRITICAL）

| 區塊 | 擁有者 | pull 行為 |
|------|--------|-----------|
| biblatex 面向（type/title/authors/date/fields/`zotero:` 附件） | Zotero（過渡期） | 版本較新時覆寫 |
| `provenance` | pull 機制 | 覆寫 |
| `akashic`（含 `sources` 副本引用）、`id`、`citekey` | Akashic/使用者 | **絕不觸碰** |

特例：**已解析的作者**（`key:` 形式）是使用者確認過的衍生知識——pull 更新時
若 entry 含任何 `key:` 作者，整個 authors 欄保持不動（import report 列於
`authors preserved`）。`akashic.tags` 只在**建檔**時從 Zotero seed 一次。

Zotero 欄位只保留 `ZoteroMapping.fieldMap` 允許清單內的項目（title/date 為一級欄位）；
未映射欄位（如 `extra`）**不入庫但不靜默**——import report 的 `dropped fields` 列名列數。
quarantined 檔（decode 失敗）**永不被 import 覆寫**：其 basename 佔住 citekey，
新 entry 一律讓位取衝突後綴。

### 2.5.1 Canonical 作者清單完備性證言

`akashic.author-list-completeness` 是**選填、由 Akashic 擁有、只綁一筆 Entry** 的
canonical witness。它不是「館藏完備」旗標，也不把其他 predicate 或世界整體改成
closed world；只有通過下列封閉契約的 witness，才可授權 `authored(person, work)` 對
exact author list 作負向排除：

1. mapping 的四個 known key 固定依 `work-id`、`author-list-fingerprint`、
   `attested-authors`、`references` 輸出。四者皆必填；未知、重複、非字串或形狀不符的
   key 一律拒收。`attested-authors` 保留 `authors` 的原始順序及每槽 `key`／`literal`
   形狀；完備的空清單必須明寫 `[]`，不能靠欄位缺席暗示。
2. `author-list-fingerprint` 是 `sha256:` 加 64 個小寫 hex。v1 framing 依序雜湊
   ASCII domain `akashic-author-list-v1`、作者槽數的 UInt64 big-endian，接著對每槽雜湊
   一 byte case tag（`key` = 0、`literal` = 1）、raw UTF-8 byte 長度的 UInt64
   big-endian 與 raw UTF-8 bytes。順序、槽位邊界、key／literal case，以及 NFC／NFD
   原始 bytes 都有語意；不得先串字串、排序或 Unicode 正規化。
3. `references` 重用 §3.5 的 strict reference schema，但在 witness 內另加封閉條件：
   每筆 `field` 必須恰為 `authors`、`value` 必須缺席；bundle 至少各有一筆 retrieval
   與 judgement，且每個 judgement 的 `rests-on` digest 必須在同一 bundle 的 retrieval
   `content` 中出現。只有 URL、只有 retrieval，或引用 bundle 外部 digest，都不構成
   作者清單完備性證言。
4. binding 同時驗 `work-id == Entry.id`、persisted fingerprint 可由
   `attested-authors` 重算，且該 fingerprint 等於 Entry 當前 exact ordered raw
   `authors`。`citekey` 刻意不在 binding 內，因此合法 rename 保留 witness；UUID、作者
   增刪、順序、case 或 raw bytes 改變則使 witness stale。decode 遇 malformed／stale
   witness 時整筆檔案 quarantine，不得把錯誤降成「witness 缺席」；程式內直接組出的
   model 也在進入 proposition truth boundary 前重驗同一 binding。

這是 `akashic` tolerant namespace 裡的 additive optional known field：witness 缺席時
既有 canonical bytes 完全不變，也**不 bump store format**。較舊 binary 依 v1.3
tolerant-preserve 將整個未知子樹逐字帶過；認得本欄位的 binary 則把其內部 mapping
視為 strict closed shape。witness 本身不保存 `store-revision` 或 `snapshot-id`，避免
自我參照；它的 canonical bytes 與同一 accepted filesystem capture 一起進入
`StoreRevision`，所以只新增／修改 witness 會改變 revision 與 decoded snapshot，卻不改
store identity 或 Entry UUID。

work merge 的資料遺失閘也把 witness 當 canonical Akashic metadata：被併者有 witness、
倖存者缺席或持有另一筆 work-bound witness 時必須拒絕並指名
`author-list-completeness`；只有同值 witness 才不構成遺失。不得採 keeper-wins、靜默
丟棄或把一筆 work 的證言移植到另一個 UUID。

### 2.5.2 v1.1 update 條件與身分（Phase 2）

- **身分**＝`(library_id, zotero_key)` 複合鍵；**預設 pull 全部 libraries**（personal + groups；
  實庫驗證 group 文獻是真實使用）。`--library-id` 限縮時，orphan 判定只作用於該 library
  視野內（其他 library 與 legacy 檔絕不誤標）。
- **update 條件**＝`version 較新 OR mapping hash 不同`。hash（SHA-256）涵蓋 pull 管的整個
  biblatex 面向——同時抓到本機未同步修改、date 正規化生效、mapping 邏輯演進（自動 re-apply，
  無需 migration 指令）。缺 hash（pre-v1.1 舊檔）＝視為不同、補建一次。
- **date 正規化**：ISO-ish 前綴（`YYYY[-MM[-DD]]`）、`00` 月/日截斷（`1989-00-00 1989` → `1989`）；
  解析不了保留原字串並列入 report `unnormalized dates`。

### 2.6 Orphan 語意

Zotero 端刪除 ≠ Akashic 刪除。pull 只在 `provenance.orphaned_at` 蓋時間戳，
檔案保留，人工裁決（刪檔或抹掉 provenance 轉為純 Akashic entry）。

## 2.9 Library registry（`libraries/<key>.yaml`，v1.2 新增）

具名 library＝**成員集合視角**（阿卡夏理念：store 是全集、不分割；「加入 library」只是標記）。
registry 檔只存 metadata，成員關係在各 entry 的 `akashic.libraries`（per-entry membership——
citekey rename 免遷移、與 tags 同寫入邊界、與 Zotero 天然脫鉤）：

```yaml
key: sinica          # 必要；＝檔名 stem；StoreKey 格式
name: 中研院          # 必要；顯示名稱
description: 選填
```

load 語意驗證同 entries/people：key 格式不符或與 stem 不符 → quarantine。
membership 與 Zotero 完全脫鉤（pull 永不讀寫）。刪 registry 檔後殘留在 entry 上的
key 成 dangling reference——不視為錯誤（同 relations 可指庫外的慣例）。

## 3. 人物檔（`people/<person-key>.yaml`）

```yaml
key: chen-chun-houh          # kebab-case 穩定字串
names:                       # 名字變體；**順序不帶語意**（#81）
  - Chun-Houh Chen
  - 陳君厚
  - C.-H. Chen            # 索引系統產生的引用形也放這裡——它是配對鍵，不是名字
authorized:                  # 對外可稱呼的名字：names 的子集，每書寫系統至多一個（#81）
  - 陳君厚
  - Chun-Houh Chen
orcid: 0000-0002-…           # 可選
openalex: A5017…             # 可選
died: '2004-11-18'           # 可選；ISO 8601 前綴。缺席 ＝ 右設限（§3.2），不是「在世」
note: 中研院統計所            # 可選；#66 之前，died 的來源寫這裡
```

### 3.1 `authorized`：對外可稱呼的名字（normative，#81）

`names` 的**順序不帶任何語意**。哪個名字對外由 `authorized` 指定——它是 `names` 的
**子集**，不是另外引進的字串。

**為什麼不是位置式**：本欄位之前，規格是「`names` 的第一個是顯示名」。那個約定沒有
型別、沒有驗證，任何寫入者重排 `names` 就會無聲改掉一個人對外的名字。實測全 store
868 位 person，`names` 第一個有 734 筆（84.6%）是索引系統產生的引用形（`Guan, Yongtao`
這種 `姓, 名` 倒置），而該位置決定了 `.bib` 匯出印出的作者名。

**兩條不變式（MUST）**：

1. `authorized` 的每個元素 **MUST** 是 `names` 的成員。
2. 每個書寫系統 **MUST** 至多一個 authorized。同書寫系統兩個是**未決的問題**，不是指定。

**書寫系統是推導值，MUST NOT 儲存。** 它只用來切分同一筆記錄的名字，所以 `han` /
`latn` 的粗分割就夠——沒有人同時擁有中文名與日文名，`Jpan` 與 `Hant` 的區別在這個用途
上不存在。存下來只會多一個可能與值不一致的欄位。

**解析順序（normative）**：

```
displayName(script) =
  1. authorized 中書寫系統相符者
  2. 任一 authorized
  3. key                      ← MUST NOT fallback 回 names 的任一元素
```

第 3 步退到 `key` 而非任一 name：沒有指定就是「不知道該怎麼稱呼他」，用醜的 key 讓缺口
**看得見**，比靜默印出引用形誠實。`organization` 在第 3 步之前多一階「當前有效名稱」
（`names.current`）——那是對名稱時間軸的**查詢**，不是讀取順序，故保留。

**`authorized` 為選填。** 缺席合法，由 `doctor` 報告而非 `validate` 拒絕：修復所需的
資訊（正確的對外名字）無法自動取得，設成錯誤等於把不可自動化的工作變成載入的前置條件。

### 時間軸段的 `attested`：某時點成立、起訖皆不明（normative，#70）

`ended`（下節）的鏡像：不是「何時結束不知道」而是「**起訖都**不知道，只知道這幾個
時點成立」。典型來源是論文的機構掛名——同人同機構 5 篇論文＝5 個觀測點：

```yaml
- value:
    literal: 中央研究院統計科學研究所
  attested:
  - '2003'
  - '2011'
```

**normative 規則：**

1. `attested` 是 ISO 8601 前綴的清單；非空時 `start`／`end`／`ended` **MUST** 全
   缺席——起點若已知就不是「起訖皆不明」，用 `start`（encode/decode 兩端拒矛盾）。
2. attested-only 段 **MUST NOT** 視為進行中（`isOpen` false、`current` 不採計、
   status 推導不採計）——有觀測不等於現況。
3. 觀測點**不合併**：同 org 的多個觀測各自成點（每點日後可掛 #66 的 reference
   逐點溯源——本版尚未接，觀測來源暫記 `source`／`note`）。
4. **format 7 專屬**（段內鍵 strict → non-additive）：write gate 對 format < 7 的
   store 拒寫＋指路，同 `ended` 的 v6 gate 機制（版本歸屬見 §5 版本對照表的 7 行）。
5. 把發表年填進 `start` 是「從那年起」的**偽造斷言**——`attested` 存在的理由就是
   讓這個常見的資料輸入偽造有一個誠實的替代。

### 時間軸段的 `ended`：已結束、時點未知（#63）

profile 時間軸（`affiliations`／`ranks`／…）的每一段，`end` 缺席的預設語意是
**進行中**。「已結束但結束日期未知」是另一個一等的知識狀態（例：退休名單只有
「已退休」的事實、沒有年份）——用 `ended: true` 表達：

```yaml
affiliations:
- value: {literal: 中研院統計所}
  start: "1985"
  ended: true        # 已結束、時點未知——不是進行中，也不捏日期
  source: 所方網頁退休名單
```

- `ended: true` 的段**不算 current**（status 推導得 `retired`，不是 `current`）
- `end` 有值時 `ended: true` 是矛盾（end 即「已結束於此」）——decode **MUST** 拒絕
- `ended: false` 冗餘但合法（等同缺席）；encode **MUST NOT** 寫出預設值
- 重疊判定：無端點無從排除——`ended` 段視為延伸到無限遠（保守多報，交人工裁決）
- 同一批（format 6）順帶對齊：affiliations 段的 `start:`／`end:` 的 **null 面
  （`null`／`~`）視為缺席**——先前 `ranks` 等純字串時間軸已如此，affiliations 卻把
  `start: null` 存成字串 `"null"`。`source:`／`note:` 維持字串語意不變
- **non-additive，MUST bump（format 6）**——「看似 additive 其實不是」：
  tolerant-preserve 的開放演化層只涵蓋記錄**頂層**與 `akashic` namespace（§5 v1.3），
  時間軸**段內**的鍵是 strict（未知鍵拒絕）——舊 binary 讀到 `ended:` 是**整檔
  quarantine**（這個人在舊 binary 消失），不是保留。refuse-if-newer 的一句
  「請升級」遠比 per-file quarantine 誠實（#74 判準的實際運用：判 additive 前
  先確認新鍵落在哪一層）

## 3.2 `died`：逝世與設限（normative，#67）

`died` 是 ISO 8601 前綴字串（`2004` / `2004-11` / `2004-11-18`），與
`organization` 的 `dissolved` 同慣例。**精度就是來源說了什麼，讀寫兩端 MUST NOT 補齊**
——把 `2004` 變成 `2004-01-01` 等於斷言了一個沒有任何來源說過的日子。

### 缺席的語意是右設限，不是「在世」

`died` 是存活分析中「事件指示 δ 與事件時間 T」的緊湊編碼：

| 寫法 | 意義 | 對 T 的資訊 |
|---|---|---|
| `died: '2004-11-18'` | 精確觀測（δ=1）| 已知到日 |
| `died: '2004-11'` | **區間設限**（δ=1）| 落在該月 |
| `died: '2004'` | **區間設限**（δ=1）| 落在該年 |
| 缺席 | **右設限**（δ=0）| 大於觀察窗，上界不存在 |

ISO 前綴慣例本來就在做區間設限——**精度即區間寬度**。

缺席同時涵蓋「真的還活著」與「已故但未記錄」。**從資料的角度這兩者就是同一件事**：
右設限的定義就是「在觀察窗內沒觀察到事件」。消費端 **MUST NOT** 把缺席讀成「在世」的
斷言。

**死亡是必然事件，所以缺席永遠不是「不適用」。** 每個人都會死，只是尚未觀察到——
`died` 是一個**部分觀察到的普遍屬性**，不是「一個可能不存在的事件的選填資料」。因此
δ=0 是一個完整而明確的狀態，不是記錄的缺漏。

### 空值 ≡ 缺席（normative）

以下寫法**MUST** 正規化成缺席——不保留、不寫回、不得讀成一筆已記錄的死亡：

| 類別 | 寫法 |
|---|---|
| 空 / 全空白 | `''`、`"   "`、只含 tab 或**換行**的值 |
| YAML 的 null-face | `died:`（空值行）、`null`、`~`、`Null`、`NULL` |

**換行要一起算**：實作上 `CharacterSet.whitespaces` 不含換行，只用它會讓一個純換行的
值變成一筆「死於換行」的記錄（實際發生過）。

理由是**兩種可能意圖都收斂到缺席**：若想說「不知道他死了沒」，那本來就是缺席的意思；
若想說「死了但不知何時」，那是下一段的不可表達情形，**MUST** 寫進 `note` 而非用佔位值。
上表沒有一個是合法的 ISO 8601 前綴，所以正規化不會丟掉任何可表達的事實。

（這**不推翻** §5 對 scalar 欄位不套 null-as-absent 的既有決定——那條的理由是
`title` 的空值可能是真實狀態。差別在值域：`died` 的值域排除空字串與所有 null-face。）

#### 正規化發生在哪（normative）

**建構時，以及建構之後的每一次寫入。** 這兩件事要分開講，因為 Swift 的 property
observer **不在初始化期間觸發**：

| 路徑 | 由誰保證 |
|---|---|
| 建構（`init`）| initializer 明確呼叫正規化函式 |
| decode 的賦值、直接賦值、key-path 寫入、`inout` 寫回 | 屬性的 `didSet`（賦值已在初始化之後）|

**不要在讀取端逐點檢查**「是不是空的」——那要求每個消費者都記得，是「小心就不會錯」的
介面。也**不要**在 decode 端另做一次：那會是同一個概念的第二套判準，而本欄位的第一個
缺陷正是這樣來的（合併檢查用「非空」、診斷用「非 nil」，於是 `died: ''` 被當成已故）。

**曾經不夠的作法**：只在 `init` 與 decode 正規化，並認為事後賦值會被 encode 的語意
canary 攔下。那不成立——關聯匯出不經過 canary，而 canary 的行為是**拋錯**而非正規化。
**守衛在某一條路徑上，不等於不變量成立。**

日後若為 person 記錄加上 `Decodable`，`init(from:)` 同屬初始化路徑，**MUST** 自己呼叫
同一個正規化函式。

缺席也**不容其他讀法**：死亡是邊界銳利的事件，人不會半死、也不會被另一個人吸收。
機構的結束不是如此（合併、被吸收、重建），所以那裡的缺席還可能藏著一個未裁決的
**同一性問題**——那屬 §5.8 歧異記錄的範疇，不該用日期欄位去蓋。

### 唯一表達不了的一格

「已知過世，但完全不知何時」（δ=1 而區間無界）。ISO 前綴最粗只到年，沒有「某個時候」
這種寫法。δ=0 完整、δ=1 有界完整，**只缺 δ=1 無界**——那屬 #63（「已結束但日期未知」）。
遇到這種案例時 **MUST NOT** 填一個捏造或佔位的日期，改記在 `note`。

### `died` 與 `status` 正交

衍生層的 `status` 描述的是**隸屬**。在職過世者的隸屬確實結束了，所以 `status` 仍是
`retired`——加上 `died` **MUST NOT** 改變任何隸屬推導。兩者放在一起會露出一個矛盾
（已故卻仍有開放的隸屬段），`doctor` **MUST** 報告它，並 **MUST NOT** 代為關閉：
把隸屬的結束日設成死亡日是推論，而人可能離職多年後才過世。

### 內容不驗證，但 doctor 報告（#85 的裁決，四欄位一致適用）

上表的三種精度是**值域的描述**，不是解碼器強制的約束。`died` 的內容**不驗證**——
與 `DateRange` 的 `start` / `end`、`organization` 的 `founded` / `dissolved` 同慣例。
解碼只拒絕**形狀**錯誤（sequence / mapping）；`2004-13-99` 或 `not-a-date` 會被原樣收下。

理由與整個 store 一致：內容的可信度屬使用端的判斷，而 fail-closed 的內容驗證會讓一筆
可疑的**歷史資料**變成整個 store 載入不了（quarantine 對舊 binary 的實際後果是
「人檔消失」）。而「只知道民國某年」這類真實情況在拒絕式驗證下會被擋死——不確定性
是正式的資料狀態（§8）。

**#85 把這個沿襲變成裁決**：值域是文件契約、驗證是 `doctor` 報告、載入不擋。
`doctor` 對四個日期樣欄位（`DateRange.start`/`end`、`founded`/`dissolved`、`died`）
逐筆列出不合值域的值（key＋欄位＋原值，命中才輸出）。**`entry.date` 刻意不在掃描
範圍**：biblatex/EDTF 允許區間、季節、約略與 `unknown`/`open`——它的值域屬
biblatex 契約，ISO 前綴檢查對它全是假陽性——回報而非拒絕，判斷屬使用端，
與重疊報告、authorized-name 缺口報告同一形狀。值域判定只驗月 01–12、日 01–31，
**不驗日曆**（`2004-02-30` 通過）——日曆級驗證需要曆法假設，對歷史資料是另一個裁決。
`endedUnknown` 段的 `end` 缺席是合法而非缺值，報告用 `isOpen` 語意、不裸看 `nil`。

（缺席的**記法**——`null` / `~` / `NULL` / 空白——不在此列：那些不是值，會在邊界被
正規化成缺席，見上一節。）

### 來源（#66 之前的資料輸入慣例）

provenance 機制（#66，見 §3.5）落地前，`died` 的來源（訃聞、紀念專輯、機構公告）
**應**寫進 `note`。落地後新資料可改用 `references:`（`field: died` 的擷取型或判斷型）；
既有 note 的遷移不強制。它醜——單一自由文字欄、不參與計算——但**「醜且留著」勝過「乾淨且弄丟」**：
機制落地時這些字串可以遷移，沒記下來的來源不行。

**這是對「填資料的人」的慣例，不是格式的 normative 要求**：`died` 在場而 `note` 缺席
是合法記錄，載入不受影響，`validate` 與 `doctor` 都不檢查。把它寫成格式的 MUST 會讓
每一筆歷史資料在來源不可考時無法記錄，而那與本節其餘部分的立場（不確定性是正式的資料
狀態）矛盾。

### 為什麼新增本欄位不 bump format

依 §5.0 的 bump 準則，新增欄位是 **additive → MUST NOT bump**。舊 binary 靠
tolerant-preserve 原樣保留 `died`，**不會按舊語意誤讀新格式**，而後者才是需要 bump 的
條件。

與 format 5（#81）對照：那次改的是**既有欄位的語意**（廢除「`names` 第一個是顯示名」），
舊 binary 會在一次 read-modify-write 裡重排 `names` 而不自知——所以必須 bump 並寫遷移。
本欄位沒有任何一項，§5.0 的版本對照表因此**不新增列**。

## 3.3 解析紀律

解析紀律：**絕不自動合併**。`akashic resolve-people` 依信心分四層提名
（exact／confirmed-elsewhere／reorder／initials，#303；同層對到 2+ 人＝歧義、
不出候選），`--apply` 是顯式第二步——套用集含寬鬆層時必帶 `--tier` 具名。

## 3.4 Canonical form：寫出去的位元組形式（normative，#69）

記錄寫出的位元組形式由**單一權威**定義：三個 `encode` 函式（`EntryYAML` /
`PersonYAML` / `OrganizationYAML`）。正規化即 `encode(decode(x))`——**沒有第二份
定義**，`akashic fmt` 只是走訪器。

### 「range 相同」的兩種成因（誠實邊界，#100）

`range` 相同時保留寫入順序（下節）——但「相同」有兩種成因，**系統分不出來**：

1. **真的同時**（或該維度本質上無時序，如別名的並存寫法）——fallback 排序是
   明示的決定；
2. **時間解析度不夠／根本沒記時間**——排序默默製造一個現實中沒有根據的順序，
   同時把「你的資料不夠精確」藏起來。

實測（2026-08，1769 筆）：175 組 range 相同的段**全部**是「完全沒有日期」，且
names／fields／ranks 三個維度**從來沒有**日期——問題的實際形狀不是「精度粗」而是
「未記錄」。`doctor` 對「從來沒有日期」的維度出 warning（`timeline dimensions
with zero dates`）——讓缺席可見，處置（補日期 vs 承認它不是時間軸）留給人。
後者牽動「該維度是否該是 Timeline 形狀」的設計問題（#63/#54/#65 的值域），
不在報告層決定。

### 時間軸的序列化順序

時間軸（`affiliations` / `ranks` / `administrative` / `appointments` / `fields` /
`contacts.*` / organization 的 `names` 與 `parents`）**MUST** 依下列順序寫出：

| 情況 | 順序 |
|---|---|
| 兩段的 `range` 不同 | 依時間先後（早的在前）|
| 兩段的 `range` 相同（含**全部無日期**）| **保留寫入順序** |
| 一段有 `range`、一段沒有 | 有的在前（沿用 `DateRange.<` 對 `nil` 的既有處理）|

**「相同時保留寫入順序」是刻意的**，不是實作細節。時間沒話說時，位置就是唯一
可用的訊號——`Organization.names` 三筆全無 `range`，主名（中文正式名）靠位置表達，
與 `Person.names` 的「第一個是主名」同一套規則。

若改以值決勝（曾經的行為），ASCII 碼位低於中文，主名會被英文別名推到後面：工具每次
把它推到後面、人每次改回來，最後沒人執行正規化。

**序列化順序與相等性順序是兩個函式。** 相等性（`TimelineOf.==`）用的是全序（`range`
相同時比 `value`），因為要讓「同樣的段落、不同的儲存順序」判為相等就必須是全序。
兩者不共用比較器。

### 兩種「序」不在同一層（normative，#80）

排序有兩種，混同它們是把「某個問題的答案」焊進圖書館：

| | 例子 | 屬於誰 | 為什麼 |
|---|---|---|---|
| **正規序列化順序** | 時間軸按時間排（#69） | **圖書館** | 位元組穩定性的一部分——不排就沒有 canonical form，同一份資料會有多種表示 |
| **語意／領域順序** | 職階高低、期刊分級、作者貢獻排名、來源可信度 | **使用端** | 它是**某一個問題的答案**，不是資料的性質。換個問題就換個序 |

store 的職責是記「他的職稱字串是 X」，**不表態 X 跟 Y 誰高**。需要序的人在使用端
自己帶，而且——**帶之前先確認領域真的有那個序**。實證教訓（#80）：為了標 PI 而在
使用端捏造職階全序，立刻生出兩個領域裡不存在的問題（「助理研究員排門檻哪一邊」）；
回去看所方原始分類，那裡是互斥的職稱詞彙表——判準是**集合歸屬**，「待人工確認」
從 1 變 0。有些領域確實自帶序；但序**經常是問題強加的、不可假定存在**，分類常常
只有分割。

因此：

- `profile.ranks` 等維度是 `TimelineOf<String>` **是刻意的**，不是待補的型別安全——
  把 rank 換成 `enum: Comparable` 看似改進，實際是把「某機構某年代的升等階梯」
  焊進圖書館：別的機構、別的年代、別的用途（薪資級距／指導資格／投票權各有各
  的序）全部被綁架。回頭路要 schema／資料遷移且可能丟資訊（enum 裝不下的原始
  標籤）——字串事後給序是使用端一行，焊死的序退場是一次格式工程
- 同一判準適用於**標籤的語意排序**：職階高低、期刊分級、來源可信度（#66）、
  作者**貢獻排名**——store 實作 **MUST NOT** 為這些標籤定義語意比較器。
  此禁令**不**涵蓋：canonical 序列化與內部正規化用的比較器（`DateRange.<`、
  `sorted` 的相等性全序——那是上表第一列的圖書館職責）；也不涵蓋**保存**
  宣告過的序列位置——`authors` 的原文順序是 store 記錄並保護的資料（見下節
  MUST NOT 改動），使用端擁有的是從它**另行推導**的排序（貢獻排名、姓氏排序）
- 這是 #69「同一個 comparator 不得同時服務等價正規化與序列化順序」的同一條線
  再往外一格：**值標籤**（rank／tier／credibility）不得同時服務「記錄說了什麼」
  與「它比誰大」——後者屬於問題，不屬於資料

### 位置即語意的序列不參與排序

`authors` 與 `attachments` 的順序**MUST NOT** 被正規化改動。作者位置帶語意（第一
作者、通訊作者），任何排序都是資料破壞而不是整理。

### 冪等

正規化 **MUST** 一次到達不動點：`fmt(fmt(x)) == fmt(x)`。序列化是 `entries` 陣列的
純函式而 decode 保留陣列順序，故此性質成立。不成立的正規化每跑一次產生一次 diff，
工具與版控互相對抗。

### 明確不保證的性質

**一個值不只有一種位元組表示。** 兩條 `==` 成立的時間軸，若 `entries` 陣列順序不同，
會寫出不同位元組。store 內沒有任何機制對 entity YAML 做內容雜湊（`sources/` 走內容
定址、entities 走 UUID 定址），故此性質目前沒有依賴者。

### 對齊入口

```bash
akashic fmt            # 就地把偏離的記錄重寫為 canonical form
akashic fmt --check    # 只回報偏離並以非零碼退出，不寫任何檔案
```

`validate` **不**擋排版偏離——那不是正確性問題。若 `validate` 擋排版，外部 pipeline
每次寫完都得先跑 `fmt` 才過驗證，摩擦大到會讓人繞過 `validate` 本身。`--check` 的
語意與 `swift format --lint` 一致，給 CI 與外部 pipeline 當明確關卡。

## 3.4 `incarnation`：store 的化身 id（normative，#130）

store 根目錄可有一個名為 `incarnation` 的單行檔案，內容是一個 UUID。它回答
**「這是不是同一個 store」**，不回答「內容新不新」——兩者混在一起會讓兩邊都說不清。

- **生成**：`ensureLayout()` 於檔案缺席時補寫（`writeIfAbsent` 模式）。**既有的
  一律不覆寫**——覆寫等於把一個 store 變成另一個化身，而那正是這個機制要偵測的事件。
- **複製即同一化身**：id 隨檔案原樣搬移（cp／rsync／Dropbox／git）。它就是同一份
  位元組，不需要特別設計。
- **缺席**：讀到缺席回 `nil`，**MUST NOT** throw。既有 store 都沒有這個檔案，讓它
  throw 等於把一個選配的加強變成載入的前置條件。

**為什麼不放進 `store.yaml`**：`StoreVersion.read` 對任何非 `format:` 的有內容行
**throw**。加一行進去，所有既有 binary 會拒絕開啟整個 store——不是忽略未知欄位，是
連讀都不讀。**`store.yaml` 不在 tolerant-preserve 的涵蓋範圍內**（那是記錄層政策）。
放根目錄而非 `.akashic/`：後者被 `.gitignore` 排除（衍生物的位置），而化身是 store 的
**身分**，該進版控、該隨 clone 走。

**index 檔名綁化身**：`<key>-<化身前 8 碼>.sqlite`（keyless 回落 `index-<8 碼>.sqlite`）。
這把 TOCTOU 從「偵測」變成**不可表達**——驗證與開啟之間有多少檔案存取都無所謂，換掉的
store 的 index 根本不叫這個名字。同路徑重生時新舊 index 是**不同檔案**，「舊 index 被
誤信」的狀態不存在。`index_identity.store_id` 仍寫入，作為**縱深防禦**（擋人工改名）；
它與化身檔皆缺席時退回純路徑比對——那是今日行為，不是退步。

代價：重生後舊 index 成為孤兒。`doctor` **MUST** 報告它們，**MUST NOT** 自動刪
（報告不動手；它們可能是另一台機器同步過來的）。

**誠實邊界**：舊 binary 讀不到 `incarnation`，因此在同路徑重生情境下仍會誤信舊 index。
這是刻意的取捨——替代方案是讓它們全部拒絕開啟，代價更大。

## 3.45 organization 階層的環（normative，#179）

`organization.parents` 可以造出環（A 的 parent 是 B、B 的 parent 是 A，或自環）。
`crossRecordIssues()` **MUST** 偵測並報告，severity 為 **warning**。

**warning 而非 error**，與 `ISO8601Prefix` 的裁決同理：fail-closed 的內容驗證會讓一筆
壞資料使整個 store 載入不了，而環是**可回溯的**（檔案都在版控裡）。升成 error 會讓
`assertNoCrossRecordErrors` 鎖住整個寫入面。

偵測 **MUST** 是 O(V+E) per start（持久的 visited 集合，不是「當前路徑」集合）——
用後者會走遍所有**路徑**而非所有**節點**，實測 n=120 就要 543 秒，在 `doctor` 的
路徑上等於功能不存在。報出來的環 **MUST NOT** 含通往它的前綴（`a→b`、`b→c`、
`c→b` 報 `b → c → b`，`a` 不在內）。

每個環 **MUST** 只報一次（取環上字典序最小的 key 當起點），否則 n 個節點的環會產生
n 則說同一件事的警告。`.literal` 的 parents **MUST NOT** 計為邊——它還沒歸戶、指不到
任何記錄。

**為什麼寫入端擋不夠**：#166 已在歸戶端（`resolve-organizations`）排除會閉環的候選，
那是製造環最容易的路徑。但它不涵蓋手寫 YAML、批次改寫、或**從別台機器同步進來的
檔案**——store 內容未信任（#23）意味著環可能不是這台機器造出來的，所以「所有寫入點
都擋」永遠不完整，需要一道檢查時的偵測。

## 3.5 `references`：欄位層級的 provenance（normative，#66）

person 與 organization 記錄可攜帶頂層 `references:` 清單；Entry 的
`akashic.author-list-completeness.references` 也重用同一種 reference 形狀，並再受
§2.5.1 的封閉 bundle 規則約束。一筆 provenance 同時記
**取得路徑**（URL、擷取日期、HTTP 狀態）與**取得的內容**（SHA-256 定址的位元組）。
只有 URL 不構成 provenance：URL 是通往內容的路徑，不是內容本身（實測兩個 host 回
相同位元組、第三個 404）。

兩種 reference，**互斥**（混用拒收）：

```yaml
references:
- field: orcid                    # 擷取型：url / retrieved / status / content 皆必要
  url: https://pub.orcid.org/v3.0/0000-0003-4038-9439
  retrieved: 2026-08-03
  status: 200                     # 錯誤頁面同樣有 digest——「死」也是內容；200 不代表活著
  media-type: application/json    # 可選
  content: sha256:d1f446b3507bd24aXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
- field: names                    # 判斷型：judgement + rests-on 成對；不得帶 content
  value: "Chen, H-Y."             # 欄位是清單時以值定位（索引在重排時失效）
  judgement: 名冊內 Chen 姓且 given initials H-Y 唯一，與縮寫配對一致
  rests-on:
  - sha256:9a23d701e4fe4888XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
```

**normative 規則：**

1. 每筆 reference **MUST** 帶 `field:` 指名它支持的欄位；欄位是清單（`names`／
   `authorized`）時 **MUST** 另帶 `value:` 以值定位、純量欄位 **MUST NOT** 帶
   `value:`（掛在純量上沒有意義又永不被驗——安靜的垃圾欄位）。指名不存在的欄位
   拒絕載入；清單欄位的 `value` 不在清單內拒絕載入（值被改寫後 provenance 成了
   孤兒——載入時擋下，錯誤同時指名欄位與值）。`profile.*` 維度只驗非空、`value`
   不比對（OrgRef 等複合值無 canonical 字串——誠實邊界，細部定位屬消費端）。
2. 擷取型 **MUST** 有 `url`／`retrieved`／`status`／`content`；缺 `content` 拒收
   ——內容的 digest 是 provenance 必要的另一半。判斷型 **MUST** 有 `judgement` 與
   `rests-on`（成對、皆非空）；帶 `content` 拒收——判斷不是擷取，沒有自己的位元組，
   它依據的內容以 `rests-on` 指名。
3. digest 形狀 **MUST** 是 `sha256:` + 64 個小寫 hex——算在**收到的原始位元組**上，
   不正規化、不轉碼（同一份實質內容可能因廣告/時間戳而有多個 digest——誠實接受的
   代價；正規化是詮釋，另案）。
4. reference 清單內的鍵是 **strict**（未知鍵拒收）——未來加欄位是 **non-additive**
   （同時間軸段內鍵的教訓，#63/#74）。
5. 既有 `TemporalValue.source`（時間段上的**裸 URL**）**不動**、不遷移、與 references
   並存（#66 D7）。無 `references` 的既有記錄零 diff。
6. **`TemporalValue.source` 只放裸 URL；digest 屬 `references:`**（#146）。#66 落地前
   的手工路徑曾把 `sha256:` 摘要塞進 `source`（實測 22 筆），使「provenance 記在
   哪一層」有兩個答案。`akashic migrate-provenance` 搬它們，`akashic doctor` 報殘留——
   **兩者分開存在**：遷移是一次性動作，而這條是要持續成立的不變式，新寫入隨時
   可能再破壞它。遷移**不 bump 格式**（`§5.0` 的判準是「舊 binary 會不會誤讀」，
   而 `references:` 自 #66 起就在契約內）。

   遷移的目標種類是 **`judgement` 而非 `retrieval`**，判準來自資料不是型別：那 22 筆
   的 `note` 全部以「由…推得」開頭（`note` 是斷言、digest 是依據），而擷取型也裝不下
   它們——`retrieval` 要求 `url` 與 `status`，那些 blob 沒有 URL（「圖書館寄來的檔案」、
   「以 DOI 逐筆查詢多個 API」都不是單一 URL）。

   **`profile.contacts.*` 搬不了**：它不在 `validateReferenceAttachment` 的欄位白名單
   內。加進去的後果是**該人檔被 quarantine**（`decode` throw 被 `load()` 的 per-file
   catch 接住，`validate` 仍 exit 0）——**不是**整個 store 拒絕載入。但那筆人檔會從
   所有查詢中消失，而 §5.0 的 format 6 與 7 正是因為這種整檔 quarantine 而 bump 的，
   所以仍需格式 bump，不在本範圍。遷移對它**回報而不靜默略過**。

### 消解判定欄位對：`resolution-confirmed`／`resolution-rejected`（#232）

人工消解判定（「這個 literal 就是他」／「查過了，不是他」）以**判斷型 reference**
落在**被判定的記錄**上（person 或 organization），欄位名是**封閉對**——只有
`resolution-confirmed` 與 `resolution-rejected` 兩值，不得依性質相似類推第三個：

```yaml
references:
- field: resolution-rejected
  value: "work:cheng2025alpha :: Cheng, C."   # <kind>:<key> :: <literal>，見下
  judgement: 查過本人網頁，非本人 [rule: author-name-exact]
  rests-on: []                                # verdict 例外：允許空（見下）
```

**配對的唯一性（normative，#554 R10–R12）**：verdict 的 `value` 只定位配對 `(holder, literal)`，
**不帶** `venues` 的 index——所以一筆 work 對同一個 venue **只能有一條 key 邊**，且同一 (venue, work)
上正規化後（`NameNormalization.matchingKey`）不同的 confirmed literal 只能有一個（同一配對**只差位元組**的兩筆 confirmed 不違反
這一句，但它們是重複的判定記錄——工具面以 `verdictEqualityKey` 去重、寫不出它——而 D23 的拒絕比位元組，所以掃描面兩類都報，R15 D39；
**「位元組」自 R16 起才真的是位元組**（D42——R15 的去重寫 Swift `==`，那是 canonical equivalence，NFC／NFD 的兩筆被收攏、零診斷；
R15 verify 第 1 列 HIGH），混合情形（三筆裡兩筆只差位元組）第一類訊息點名那一組、超過 5 組時說「…共 N 組」（R17，R16 verify 第 12 列）。這是 `work:` 記錄
的約束，住在這裡而不在 §5.7（那節講的是 venue 的名字內容；R11 verify 第 7 列指出手改 work 的人不會去
讀那節）。寫入面：`resolve-venues --apply` 對會造出第二條 key 邊的候選**逐筆略過並具名**（D33，
`skippedDuplicateVenueEdge`）；`--repoint` 讓被動到的邊撞上第二條時拒（D27）；`--demote`／`--repoint`
對已違反的 work 拒（D25；≥2 個不同 confirmed literal 拒，D23）；`--apply` 對「目的 venue 已對該 work 持有另一個
confirmed literal（沒有對應的邊）」的候選逐筆略過並具名（`skippedConflictingConfirmedLiteral`），`--repoint` 對改指後會造出同一形的
整批拒絕（D38，R15——R14 verify Codex 第 1 列：生產端的 fail-closed 只在合併有，apply／repoint 寫下第二個 confirmed 就把那條邊鎖進
D23）——**相等比位元組，與 D23 同一把**（D43，R16；R15 verify 第 3／5 列：R15 以 `matchingKey` 比、放行同一 literal 的另一個拼法——寫下去
不會多一筆，但之後 `--demote` 從唯一的 confirmed 取回**舊拼法**，邊被改寫成不是這筆記錄原本寫的字），訊息分「另一個 literal」與「另一個拼法」
兩種、兩桶同時非空時兩桶都說（D50，R17——R16 verify DA 第 9 列：只印第一桶會逼出兩趟往返而中間 validate 全綠）；apply 的這道閘在重複邊檢查（D28／D33）**之後**判（D44——第 2 列：跑在前面時「沒有對應的邊」那句從未被驗證，重複來源欄位被分進錯的桶）；venue 合併在塌邊會留下兩筆正規化後
不同的 confirmed literal 時拒（D32），倖存者與被併者對同一配對持相反判定時拒（D31——person 合併同）；
被併者的 verdict 遷移以 `verdictEqualityKey` 去重（與 `appendIfAbsent`／`supersede`／#486 同一把鍵），
**被去重丟掉的那筆逐筆回報在 `verdictsCollapsed`**（R13：位元組不同的判定記錄可能帶人寫的 judgement 與
rests-on，被併檔隨即刪除、唯一副本只剩 git）。**R13 的三個收緊**（R12 verify 七席）：D31 的比對是**累積**的
（三方合併時被併者彼此的相反判定也擋），且同一道閘裝在 **holder 遷移**那一步（`assertHoldersWritable`，
work／person 合併把第三方 holder 上的 `<kind>:<被併鍵>` 改寫成倖存者之後，同一 holder 不得同時持有該配對的
confirmed 與 rejected——三種 shape 共用）；D32 守的是不變式本身而不是「塌邊」這個症狀——這次合併**新增**的
confirmed literal 會讓倖存者對某個 work 持有 ≥2 個正規化後不同的 confirmed 即拒，倖存者自己既有的違反不是
合併的事；D33 的勝者由**呼叫端的順序**決定（先到先寫，`apply` 陣列保序不排序——同一 work 兩條拼法不同的
literal 邊誰落地、confirmed 帶哪個字串，都取決於呼叫端送的順序），略過訊息分「既有的 key 邊」與「同一批稍早的
候選」兩種來源。**合併本身是一種移除面**（R12 verify logic 第 38 列）：`resolveVenueDivergence` 對 entry 的 key
邊去重時，與被併鍵無關的既有重複 key 邊也會被收成一條（#553 起）、報告只有 `entriesRewritten` 的計數——#572
落地前留著，這裡把它寫出來。
既有的違反：第一半（同一 work 兩條 key 邊指同一 venue）由 `Entry.validate()` 報 warning（`zero-instance-guards`
第 26 列）；第二半（同一 (venue, work) 上 ≥2 個正規化後不同的 confirmed literal，以及只差位元組的重複記錄）由 `Venue.validate()`
報 warning（第 27 列，R14／R15——R13 之前這一半全庫沒有掃描面，而真正造出它的路徑（work 合併）結構上不會點亮第一半的燈，
R13 verify DA 第 16 列）。兩族自 R15 起各有 `StoreHealth` 家族（doctor 的 `recordIssues` 與 App 側欄各一個計數）、每筆記錄最多列
20 則——概括句自 R16 起用自己的前綴（`Entry.perRecordCapSummaryPrefix`）、不進任何家族，所以家族計數是「受影響數，至多上限」
（R15 verify 第 29 列：R15 讓概括句帶家族前綴，被截的記錄計數變 21）。修法都是手改 YAML——刪掉多餘的邊、或刪掉不屬於那條邊的 confirmed verdict——移除面是 #572。
**R14 把三處閘收成一個謂詞**（R13 verify 33 列、6 席齊）：R13 的 keeper 路徑用「被併者對累積中的 keeper 找相反鍵」的
delta 謂詞——漏掉矛盾整組住在同一筆被併者裡、以及單一被併者自帶兩個 literal 而倖存者對該 work 無 verdict（D32 多了「keeper
已有 ≥1」的前提）；holder 路徑用整份清單的絕對謂詞——既有且與被併鍵無關的 #486 矛盾對擋下不相干的合併、訊息把因果歸給這次
合併，且只補了相反判定那一半：work 合併把 venue 對 keep／doom 各持的 confirmed 改寫到同一 work，純工具面造得出 D23 從此拒的
邊（DA 第 3 列）。現在兩條路同一個 delta（D34）：合併後的記錄（keeper ＝ 自己的 ＋ 全部被併者的 references，person 側經 holder
改寫；holder ＝ 遷移後、去重前）與合併前比，只擋這次帶進來的兩類違反——相反判定（三種 shape）與同一 work ≥2 個正規化後不同的
confirmed literal（只對 venue 記錄算——D23 是 venue 側的拒絕）；訊息說出每筆的出處與**遷移前**的原值（遷移後的 value 不在
任何 YAML 裡，DA 第 17 列）。合併前就存在的違反不擋（validate 的 warning 負責）——含住在被併鍵上、改寫後整組搬到倖存鍵的**（R16 起收窄：只在倖存配對合併前一筆都沒有時，見下）**（R15，D37；R14 verify logic
第 2 列 HIGH、四席同指：R14 的差集在配對鍵層算，而配對鍵含 holder，被併鍵上的既有矛盾對或雙 literal 改寫後鍵變了、被判成新，訊息自己
列出的兩筆 holder 都是被併鍵、末句還說既有的不擋；keeper 路徑對倖存者自己持有的 `person:<被併>` 矛盾對同型）。R15 的差集在**索引層**算；
**R16（D45）把「既有」釘在倖存配對上**（R15 verify 第 12／13／20 列：R15 問「有沒有**某一個**合併前分區已持有全部」——holder 對 doom 持
{A, B}、對 keep 持 {A}，doom 那一區 ⊇ 全部就放行，而 (holder, keep) 合併前只有一個 literal、可以 demote，合併後被 D23 鎖住；R15 自己的
末句「含住在被併鍵上的不擋」與判準互相矛盾）：after 的違反是既有的，當且僅當倖存配對（合併後這個配對／work 鍵在倖存記錄上合併前的那一份）
就已經是整組違反，或倖存配對合併前一筆都沒有而某一個合併前分區整組就是（整組原樣搬過來，沒有新東西進到任何既有配對）；整組住在被併
記錄裡的仍擋（keeper 路徑，R13 的裁決——那個檔要刪、出處會消失），讓倖存配對的既有歧義變大的擋。**R17（D47）：合併也要「位元組是位元組」**
（R16 verify DA 第 1 列 HIGH：合併是第三個會動到同一批 verdict 的面，收攏用 `verdictEqualityKey`（正規化）去重後由勝者政策挑一筆，而 #468 的
「弱血統優先」排在「未改寫者勝」之前——被併記錄弱血統的 `VEE JOURNAL` 贏過倖存者使用者確認的 `Vee Journal`、連位元組一起取代，之後 `--demote`
把倖存邊寫成不是它原本記的字）：碰撞的 literal **位元組不同**時倖存配對自己的（未改寫）那筆勝，同拼法時 #468 三層照舊；被丟的那筆連同留下的拼法印在
`verdictsCollapsed`（holder 遷移、keeper 合併、rename 三條收攏路徑同一個描述）。**刻意不加拒絕**：被併記錄去留由使用者裁決，只差位元組的兩筆判定
不該擋合併，揭露即可。**R18（D51）：倖存配對不是倖存邊**（R17 verify Codex 第 1 列 HIGH、logic 第 6 列、regression 第 8 列、DA 第 10 列：keeper 對某 work
持有的 confirmed 可能**沒有邊**——手改、舊 binary、D38 具名的那種輸入——而 work 的唯一邊指向被併 venue，被併記錄的那筆才是那條邊記錄的字；R17 的 keeper
路徑一律 keeper 勝、三方合併由 `doomed` 陣列順序決定（上一版這裡寫「由 #468 的三層決定」，對 keeper 路徑為假）、holder 路徑的第 0 層是組層級旗標而對每一對
套用、rename 沒有任何政策）。三條收攏路徑自此同一個勝者函式（`LibraryStore.collapseWinner`）：候選拼法位元組不同時 (0) 先留**活著的邊**那些——合併前
work 對該 venue（`Entry.venues`）／person（`Entry.authors`）、person 對該 organization（`affiliations`）真的有邊（`VerdictEdgeSet`）；(1) 再留與倖存配對
自己位元組相同的那些；(2) #468 三層——弱血統優先、倖存配對自己的優先、statement 字典序；(3) 首見順序（三方合併兩筆被併材料同弱、同 statement 時——
揭露而非任意）。holder 路徑（work 合併）沒有活邊那一層：work 合併不搬 venues／authors 邊，被併配對在合併後必死，那裡「倖存配對自己的勝」就是活邊規則。
**rename 只收攏它動到的鍵（D53）**：位元組相同的重複收攏（留首見）；被改寫的那筆對上一筆早已指向新鍵的 verdict 時——後者必然是死的（目的鍵不存在，否則
rename 拒絕）——留活的；兩筆都沒被改寫的碰撞**留著**（那是 rename 之前就在的第 27 列第二類 warning，rename 不替它判定；R16 之前是全量 dedup、由陣列順序決定）。
**代價寫出來**（R17 verify regression 第 9 列）：留強丟弱時弱血統那筆的 `rule` 尾註從 store 消失，它的消費端不只收攏列——之後每一次提名的
confirmed-elsewhere 揭露（`PersonResolver`／`VenueResolver` 從 `confirmedByLiteral` 讀 rule）都不再看到弱出身；#468 保的那個警告在這一格只在
`verdictsCollapsed` 出現一次。**家族計數是下限（D54）**：doctor／App 的兩族計數每筆記錄至多 20 則，`StoreHealth.cappedRecords`（doctor 的
`recordIssues.cappedRecords`、App 摘要）說有幾筆記錄被截（R17 verify Codex 第 2 列：R17 的 MCP 描述寫「各族計數永遠完整」，與 `StoreHealth` 的 doc 矛盾）。雙 literal 的拒絕訊息把這次帶進來的
（含合併前住在被併鍵上的）與倖存配對既有的分開列（DA 第 11 列：R14 把絕對集合印在「帶進來的」下、末句又說既有的不擋）。**收攏丟列印遷移前的原值**（D40）：`verdictsCollapsed` 的兩個生產者（holder 遷移、rename）先前
印改寫後的 value——被丟掉的恆是被改寫的那一筆，所以那個字串不在任何 YAML 裡（DA 第 10 列）；value 與 statement 各截 200 scalar、
merge 與 rename 的 CLI／App sink 同一種性質式逃脫。**dry-run 對去重丟掉的判定也要預告**（D35）：
`verdictsCollapsed` 在 preview 與實跑同源（`mergedVenueKeeper`／`mergedPersonKeeper`——R13 只裝在實跑，dry-run 對「這次會丟掉
哪幾筆判定記錄」沉默，而 dry-run 正是還能反悔的時點）。

**與 §3.5 一般規則的三個刻意偏離**（各有理由，皆為 normative）：

1. **`value` 必填、必須可解析、不做集合成員檢查**。一般清單欄位的 `value` 以值
   定位記錄自己的清單；verdict 的 `value` 定位的是**配對**——**單一文法**
   `<kind>:<key> :: <literal>`（以**第一個** ` :: ` 切分、holder token 再以第一個
   `:` 切出 kind；literal 其餘內容原樣保留）。kind ∈ `work`／`person`／`org`
   且**必填**：person 族的 holder 是 entry citekey（`work:`）、organization 族是
   持有 literal 的 person／organization key（`person:`／`org:`）——person 與 org
   的 key 可合法同名（#166），沒有 kind，一筆 org 側否決會連帶抑制同名 person 的
   配對。它們都不是本記錄的欄位值，所以成員檢查不適用；解析不了的 value 拒收
   （verdict 沒有可解析的配對即無錨——malformed 進不了 store，手改壞的檔在載入
   時整筆 quarantine，loud）。解析器住 `ProvenanceReference.VerdictPairingValue`，
   store 閘與 `ResolutionLedger` 共用同一個。
2. **允許空 `rests-on`**。裁決本身即一階證據（人看過、判了）；有外部依據時照常
   以 digest 指名。非 verdict 欄位的判斷型維持「`rests-on` 非空」不變——例外不外溢。
3. **`judgement` 尾註 `[rule: <name>]` 標記證據類別**（person 族
   `author-name-exact`、organization 族 `org-name-exact`——兩族的校準歷史分開計）。
   tolerant 解析：尾註缺席依 kind 計入該族預設。這是 typed slot 的 v1 妥協；
   格式再演化時遷移為 typed 欄位。

三態計數（confirmed／rejected／pending）一律**現算、絕不儲存**——store 內沒有任何
counter 欄位；「還沒查」與「查過了不是他」由 verdict 存在與否區分。

**verdict 是一條邊，生命週期有防線**（#232 verify）：`value` 內嵌 citekey／key，
`akashic rename` 會一併遷移 person 記錄上的 `work:` verdict（`RenameReport.verdictValuesRewritten`
報出）；`bootstrap-people`／`bootstrap-organizations` 對**已存在的目的檔**（含
quarantined 檔——決定性 UUID 使同 key 落同檔名）一律跳過並報告，絕不覆寫。

**相容性（format 8 write gate）**：verdict 的序列化形狀完全是既有的判斷型（無新
形狀），但 `references[].field` 白名單是 **strict** 層——舊 binary 讀到 verdict
reference 是**整檔 quarantine（記錄消失）**，不是 tolerant 保留。與 §5.0 的 v6
（`ended`）／v7（`attested`）同型的「看似 additive 其實不是」，同一套補救：
**寫入含 verdict 的記錄要求 store format ≥ 8**（`writePerson`／`writeOrganization`
的 v8 gate，拒絕而非自動 bump、訊息指路）；format 8 的 store 讓舊 binary 走
refuse-if-newer 的一句「請升級」，取代 per-file quarantine。format < 8 的 store：
`reject` 不可用（硬擋、指路），`apply` 照常歸戶但 verdict 跳過並以
`verdictsSkipped` 揭露。實際 bump store marker 的程序見 #247（先同步 distribution
再改 marker）。

### 存檔佈局：`sources/`（內容定址，不進 remote）

擷取的位元組住 `<store>/sources/<digest 前 2 字元>/<其餘 62 字元>`，**無副檔名**
（位元組就是位元組，媒體型別記在 reference 上）。同位元組只存一份。

**存檔 MUST NOT 進版控 remote**——它是第三方逐字內容，與本專案對 raw 逐字稿的
處置相同；追蹤的是**指涉紀錄**（references 欄位），不是被指涉的位元組。
`ensureLayout()` 建 `sources/` 並寫入 `.gitignore` 標記區塊（`# BEGIN akashic
sources` … `# END`；idempotent——標記已在（含手工版本）就不寫也不改寫）。寫入存檔
前 **MUST** 以 git 自身的忽略判定驗證排除生效（fail-closed）：未生效拒寫、git 不可
用拒寫；store 非 git repo 時跳過驗證，跳過的事實記錄在寫入回條。

**digest 缺席是預期狀態，不是損毀**：存檔不進 remote，clone 後必然缺席。載入
**MUST** 照常成功，缺席以與格式錯誤**不同的**條件回報（`missingSourceDigests`）。

**存一份 source 是一個動作**（#224）：blob 與它的 provenance 條目（`sources/
index.jsonl`，欄位 `content`／`bytes`／`media-type`／`retrieved`／`origin`／
`acquisition`／`note`）一起落地——沒有「只存 blob」的入口（blob 只是位元組，沒有
條目它什麼都不證明）。index **append-only、永不重寫既有行**（含手工條目的未知
欄位——lossless；檔尾無換行時先補一個 `\n` 再 append，不動既有位元組）；同
digest 不重複 append，回條回報 existing **並附上被丟棄的 provenance**（丟棄必須
可見）。index 有無法解析的行時**拒絕**新寫入（腐壞的 sidecar 不可判定冪等——先修
再存，且拒寫在任何磁碟寫入之前）。index.jsonl 自身的路徑同樣過 fail-closed 排除
驗證（blob 的探測路徑不能代替它）。`doctor` 檢出四類並**只報告不動手**：孤兒
blob（有存檔無條目）、懸空條目（有條目無存檔）、無法解析的行、讀不到的 shard
（讀不到 ≠ 缺席，不得捏造懸空）；audit 自身失敗降級為警告、不中止報告。

#### `index.jsonl` 的版控處置（#262 裁決一，2026-08-19）

**裁定：`index.jsonl` SHOULD 被追蹤；blob MUST NOT。** 兩者的處置不同類，而先前是被
**同一條整目錄規則連帶**涵蓋的。

判準來自 store 自己 `.gitignore` 的註解（原文）：

> 判準不是 repo 公開/私密（private repo 的內容仍在 GitHub 伺服器上），
> 而是「**原始第三方材料**」vs「**自己加工過的衍生產物**」。

`index.jsonl` 的條目是 digest ＋ `origin` 敘述 ＋ `retrieved` ＋ `media-type`
——**全部是自己寫的指涉紀錄**，不含任何第三方位元組。所以依那條註解自己的判準，
它屬於**可追蹤**的一側。它被排除只是因為規則寫成了容器（`sources/`）而非對象。

> 這與 #295 記載的形狀同構：為某類對象寫的規則用「容器」表達，把不同類的對象一起
> 涵蓋，而理由對後者不成立。

**遷移寫法（重要——issue 原本提議的寫法無效）**：

```gitignore
# ❌ 無效：git 無法 re-include 已被排除目錄底下的檔案
sources/
!sources/index.jsonl

# ✅ 正確：排除目錄的**內容**而非目錄本身
sources/*
!sources/index.jsonl
```

git 的規則原文：*It is not possible to re-include a file if a parent directory of
that file is excluded.* 照 ❌ 那樣寫會**以為追蹤了但其實沒有**——靜默失敗。

**對承重閘的影響：實測為零。** `SourceStore` 的 fail-closed 是**逐一路徑**問
`git check-ignore -q <blob 的相對路徑>`。在暫存 repo 實測四種寫法：

| `.gitignore` | blob（`sources/ab/<62>`）| `index.jsonl` |
|---|---|---|
| `sources/`（現況）| **已排除** | 已排除 |
| `sources/` ＋ `!sources/index.jsonl` | **已排除** | 仍被排除（提案無效）|
| `sources/*` ＋ `!sources/index.jsonl` | **已排除** | **未排除** |

blob 仍被 `sources/*` 涵蓋（`sources/ab` 這個子目錄被排除，其下內容連帶排除），
所以**放寬承重閘的風險不存在**——前提是用正確寫法。

**為什麼值得追蹤**：`index.jsonl` 目前是**單一副本、無歷史**。append-only 擋得住
in-process 重寫，擋不住截斷、誤覆寫、磁碟損壞；clone 之後從零開始。而它是
`missingSourceDigests` 與 `doctor` 四類檢查的**唯一**依據——沒有它，「有存檔無條目」
與「從來沒存過」不可分辨。

**store 端的實際變更不由本 repo 執行**：`.gitignore` 住在使用者的 store
（`~/.akashic/.gitignore`），改它是資料工作。本節是裁決與遷移說明。

#### `retrieved` 的格式契約（#262 裁決二）

**`retrieved` MUST 是 ISO 8601 且帶 UTC offset**（例：`2026-08-19T14:30:00+08:00`）。

裸日期（`2026-08-19`）**不合契約**：它被讀成什麼時刻取決於讀的人在哪個時區，而
provenance 的用途正是「在什麼時候看到的」——一個會隨讀者漂移的時刻答不了那個問題。
全域規則（`~/.claude/CLAUDE.md` 的時區節）對此有具名的踩坑實例：無 offset 的時間值
被當成 UTC 解讀，實際生效時間與預期差 8 小時。

**現況與成本**：實測 store 的 `index.jsonl` 有 **7 條** `retrieved`，**全部是裸日期**
（`2026-07-19` ×1、`2026-08-04` ×6），零個帶 offset。`provenance-reference` 的 spec
先前對格式**未表態**（只說 SHALL record the retrieval date）。

**7 條是目前成本，這個契約現在最便宜**——條目數只會增加，而回填成本隨之放大。
既有 7 條的回填是資料工作（同上，store 端）。

#### 條目內容的真值不由 audit 承載（#269 裁決，2026-08-19）

**裁定：`origin` 敘述屬實由寫入當下的人負責；audit 只保形式一致性。** 三個候選裡取
「明記能力邊界」，spec 側的規範文字在 `provenance-reference` 的
「The truthfulness of a provenance description SHALL rest with the writer」。

**digest 保證位元組不變，不保證敘述屬實**——這是兩個不同的宣稱，而只有前者可機械檢查。
audit 能查的是：每個條目對得到位元組、每個被引用的 digest 解析得開、沒有未被引用的
blob。它**不能**、也不得被描述成「確認了那段敘述是對的」。

**為什麼不做「retrieval 型重抓 URL 比 digest」**：不是成本問題，是**那個比對本身沒有
判別力**。

實測 7 條（2026-08-19）的欄位集合完全一致：`acquisition`／`bytes`／`content`／
`media-type`／`note`／`origin`／`retrieved`。**取得方式是結構化的**——`acquisition` 取值
`api+web` ×5、`api` ×1、`file` ×1——所以「哪些是 retrieval 型」機械上分得出來。
但**沒有 `url` 欄位**：具體抓了什麼位址只寫在 `origin` 的自由散文裡。

> **這一段修正過一次。** #269 的 diagnosis 寫「無結構化 `kind`」，本節初稿照抄；實測
> 發現 `acquisition` 就是那個 kind。缺的是 URL 不是 kind——結論不變，但理由換了，
> 而換過之後論據更強（見下）。**照抄未經自己量測的數字，會把別處的錯誤搬進規範文字。**

即使補上 URL，重抓比對仍不可用：這 7 條的位元組是**多次查詢的彙總結果**
（`origin` 原文：「以已驗證的 DOI **逐筆查詢**」、「Europe PMC REST（62 篇）與
Crossref REST（18 篇）」）。對活的 API 重跑同一組查詢，**不預期得到位元組相同的結果**。
所以 digest 不一致既可能代表敘述為假、也可能只代表上游變了——而後者正是
`provenance-reference` 既有 scenario「The content at a URL changes between retrievals」
處理的情形。**一個無法區分兩種成因的檢查，不構成真值抽查。**

而它**也不可能覆蓋全部**：`acquisition: file` 那一條的 `origin` 是
「中央研究院統計科學研究所圖書館提供（研究成果 100 篇；檔名日期 20260717）」——
該路徑結構上不可重訪。**覆蓋 6/7 卻叫「已有抽查」，正是 #298 記過的錯誤安全感形狀**：
被誤信的檢查比沒有檢查更糟。

**既有 7 條的處置（#269 S5）：不回溯抽查，也不標記為「未驗證」。** 後者看似誠實，實際
會製造相反的暗示——若只標記其中一些，讀者會推論其餘**已經**驗證過。而按本裁決，
**全部條目一律未經敘述層驗證**，那是這個資料結構的常態而非例外，所以它屬於規範文字
（寫在這裡與 spec 裡）而不屬於逐條欄位。

**與 #262 的關係**：兩張都落在 index 條目的契約上，所以刻意同處記載。#262 管**欄位的
形式**（`retrieved` 必帶 offset、`index.jsonl` 應被追蹤），本節管**欄位內容的真值歸屬**。
本裁決不新增、不修改任何欄位，所以與 #262 的欄位契約無交集，兩者不會分岔。

**存檔不是 entity**（兩個獨立理由，任一充分）：網頁不決定記錄形狀、不讓 loader
分岔到不同 decoder；且內容定址的身分被位元組窮盡——entity 的判準之一是「改名後
仍是同一物」，而位元組串改一個 byte 就是另一串。它沒有名字、沒有歷史、沒有生命
週期，在構造上不可能是 entity（詳見 design-principles 的對應節）。

### `fields.type` 與頂層 `type:` 同名，但它們是兩件事（#357 裁決，2026-08-19）

`fields:` 底下的鍵是 **biblatex 欄位名**，而 biblatex 有一個欄位就叫 `type`。它與頂層的
`type:`（`WorkType` 的封閉列舉，#325）**毫無關係**：

| | 頂層 `type:` | `fields.type` |
|---|---|---|
| 是什麼 | 這筆 work 是哪一種（封閉列舉） | biblatex 的 `type` 欄位（自由字串） |
| 誰消費 | `biblatexEntryType`／`apa7Section` 的來源 | 直接寫進 `.bib`，由 biblatex 排版 |
| 例 | `report`、`thesis` | `Research Grant`、`manual`、`phdthesis` |

**同名是 biblatex 的既定命名，不是本專案的失誤**，而依賴明確期待它
（`APADataModel.recommendedFields["THESIS"] = ["TYPE"]`）。所以**不改名、不刪除**——
改名會讓匯出寫出 biblatex 不認得的欄位。

#### 為什麼不對它發診斷

考慮過在 decode 端對 `fields.type` 報一句「這個鍵與頂層 `type` 同名，容易誤讀」。**否決。**
實測 23 筆裡，`report` 的 7 筆與 `thesis` 的 2 筆是**正確且被依賴期待**的用法——對它們
發診斷等於對正確資料報警，而被忽略的檢查比沒有檢查更糟（它讓人以為已經檢查過）。

同名造成的是**讀 YAML 的人**的困惑，那是文件問題，本節就是它的解。

#### 23 筆的逐類裁決（實測 2026-08-19，937 筆全庫）

| `WorkType` | 筆數 | `fields.type` | 裁決 |
|---|---:|---|---|
| `conference-session` | 12 | `Conference Presentation` | **保留**。與 `WorkType` 冗餘，但刪掉不會多出任何資訊，反而失去「來源這麼寫過」這件事。同筆另有更精確的 `titleaddon: Poster presentation`（§10.5 要的那個標籤） |
| `report` | 7 | `Research Grant` ×5／`manual` ×2 | **保留**。這正是 biblatex `@REPORT` 的 `type` 欄位；`manual` 兩筆逐字來自 Zotero 的 `reportType`（R 套件手冊），`Research Grant` 五筆是國科會計畫 |
| `thesis` | 2 | `phdthesis`／`Master's Thesis` | **已由 #335 處理**：遷入結構化的 `thesis.degree`（封閉三值），匯出時結構化欄位勝過殘留值 |
| `webpage` | 2 | `Preprint` | **型別是錯的**，已改為 `unpublished-work`（見下） |

> **本表更正了 #357 issue 內的分布表**：該表把 `report` 的值寫成 `Research Grant`／
> `Preprint`、把 `webpage` 的寫成 `manual` —— **兩列對調了**。實測是 `report` → `manual`、
> `webpage` → `Preprint`。這個對調不只是筆誤：它反轉了裁決方向。照 issue 的說法
> 「`webpage` 的 `manual` 疑似錯置」會讓人去查 R 套件手冊那兩筆（它們沒問題），
> 而真正錯置的預印本反而被歸進「真的子類型資訊」而不會被檢查。

#### 兩筆預印本的型別修正

`cheng2024bexistence`／`yang2024parametric` 原標 `webpage`（宣稱 §10.16），但**四個獨立
訊號一致指向預印本**：PsyArXiv 的 DOI 前綴（`10.31234/osf.io/…`）、`keywords: preprint`、
`organization: PsyArXiv`、`fields.type: Preprint`。APA7 §10.8（Unpublished and Informally
Published Works）涵蓋預印本，所以已改為 `unpublished-work`。

**只改頂層 `type:`**，`fields.type: Preprint` 保留——它是來源給的，`lossless-intake`
管的是不丟。

## 4. 衍生物

- `.akashic/index.sqlite`：查詢/圖形用 index，`doctor`/import 尾端全刪重建。
- `.bib`／CSL-JSON：`export-bib` 匯出的**編譯產物**（ADR #10），不是資料本體。
- 同作者/同期刊等關係由 metadata 推導；只有 `akashic.relations`（cites/related）
  是儲存的關係資料。

## 5. 版本與相容

本格式為 v1.3（v1.1 增 provenance hash 欄位；v1.2 增 `akashic.libraries` 與
`libraries/` registry，#13；v1.3 引入 tolerant-preserve，#23）。

### 5.-1 v2：`entities/<uuid>.yaml`（normative，#35）

**分類不進路徑。** `work` / `person` / `organization` 與 `article` / `book` 是**同一個軸上
的值**，沒有理由前者當目錄、後者當欄位。

```
entities/<uuid>.yaml     +  type: article | book | person | …
```

| | format 1 | format 2 |
|---|---|---|
| work | `entries/<citekey>.yaml` | `entities/<uuid>.yaml` |
| person | `people/<person-key>.yaml` | `entities/<uuid>.yaml` + `type: person` |
| 檔名的意義 | **稱呼**（會變） | **身分**（不變） |

**normative 規則：**

1. `entities/` 的檔名 **MUST** 是合法 UUID，且 **MUST** 等於記錄的 `id`。不符 → quarantine
   （代表有人改了檔名或 id，兩者都會讓引用錯位）。
2. 記錄種類由 `type` 決定：`type: person` → person，其餘（含缺席）→ work。判別 **MUST**
   讀該欄位，**MUST NOT** 用文字掃描——`type:` 可能出現在註解、字串值、未知欄位裡。
3. person 記錄 **MUST** 有 `id`。legacy `people/<key>.yaml` 缺 `id` 時，讀取端 **MUST** 以
   `UUIDv5(namespace, key)` 推出**確定性**值；**MUST NOT** 隨機生成（否則 index 的
   primary key 與作者引用每次載入都會漂）。`id` 在場但非合法 UUID → **MUST** fail-closed。
4. format 2 下 rename **MUST NOT** 搬檔案（UUID 不變），但 **MUST** 檢查新 citekey 未被
   其他記錄佔用——檔名不再是 citekey，唯一性不再由檔案系統天然保證。
5. 讀取端 **MUST** 同時讀 `entities/` 與 legacy 目錄（未遷移的 clone / 備份要能開）；
   寫入端 **MUST** 依 **store format** 而非「`entities/` 目錄是否存在」決定寫哪裡
   （空目錄可能是 `ensureLayout` 或中斷的遷移留下的）。
6. 沒有 `store.yaml` 的既有 store，若 `entries/` 或 `people/` 有內容，**MUST** 標為
   format 1——無條件標成 supported 會把 legacy store 誤標成 v2。

**遷移**：`akashic migrate`（`--dry-run` 先看）。順序是**先驗、再寫、後刪、最後 bump
format**；有任何 quarantine 檔則拒絕遷移（內容讀不出來的檔搬過去只會把問題帶進新佈局，
並失去「它原本在哪」這個唯一線索）。

### 5.0 Format marker 與 refuse-if-newer（normative，#24）

store root 有一個 canonical 的 `store.yaml`，只含一個整數欄位：

```yaml
format: 1
```

**放 store root 而非 `.akashic/`**：version 是 canonical 事實（「這份資料是什麼格式」），
不是衍生物。`.akashic/` 是可全刪重建的衍生層，把 canonical 事實放進去語意錯，而且會隨
index 一起被清掉。

**bump 準則（normative）**：

| 變更種類 | 由誰處理 | bump `format`？ |
|---|---|---|
| **additive**（新增欄位）| §5「v1.3 tolerant-preserve」的容忍 + round-trip 保留 | **否** |
| **non-additive**（欄位語意變更、欄位刪除、結構重排）| 本節的 refuse-if-newer | **是** |

兩者**不重疊**，而且這條邊界是硬的：additive 變更下舊 binary 讀新資料是安全的（未知欄位
原樣保留），所以 **MUST NOT** bump —— 每個 additive 演化都 bump 會逼所有 binary 同步升級，
等於白做 tolerant-preserve。non-additive 下舊 binary 會**按舊語意解讀新格式**，靜默產生錯誤
行為，所以 **MUST** bump。

**binary 行為（normative）**：

- 缺 `store.yaml` **MUST** 視為 `format: 1`（本機制之前寫的 store 都沒有這個檔，而它們就是
  v1.x）。缺檔不是錯誤。
- 檔案存在但無 `format:` 行、或值非正整數 → **MUST** 明確報錯，**MUST NOT** 猜成 1
  （猜會讓一個壞掉的標記檔靜默降級成「沒有防線」）。
- `format` > binary 支援上限 → **MUST** 在 `load()` 開始、**逐檔 decode 之前**整體拒絕，
  訊息須點名兩個版本數字與「CLI / akashic-mcp / App 是各自獨立的 binary」。在 decode 現場
  才報錯等於把「請升級」變成一堆難解的 per-file 錯誤。
- `ensureLayout()` **MUST NOT** 覆寫既有的 `store.yaml`（那可能是較新版本寫的，覆寫等於在
  使用者跑一個看似無害的 `doctor` 時把防線自毀）。
- `ensureLayout()`（建佈局的入口：`doctor`／`import-zotero`／`file add`／MCP 的
  `import-zotero`）**MUST** 對 malformed 與 too-new 的 marker 拒絕（#106）——建佈局是
  結構性動作，依猜測建目錄的代價是雙佈局。`usesEntitiesLayout` 的**寫入路由**兜底
  （marker 壞掉時以磁碟事實猜）不在此限，維持 #35 語意。拒絕 **MUST** 零磁碟副作用
  （不得留下依錯誤猜測建出的目錄）。
- **marker grammar（normative，#117 定案）**——合法 marker：

  ```
  marker      = *( comment / blank ) format-line *( comment / blank )
  format-line = "format:" WS* 1*DIGIT WS* [ comment ]     ；必須頂格
  comment     = *WS "#" anything                          ；註解可縮排
  WS          = Unicode Zs ∪ tab（值周圍的空白種類不帶語意）
  換行        = Character.isNewline 全集（\n、\r\n、\r、VT、FF、NEL、LS、PS）
  DIGIT       = ASCII 0-9；值須為正整數且落在 Int64 可表示範圍，
                超出（或全形/其他 Unicode 數字）→ malformed（fail-closed）
  BOM         = 檔案開頭的 U+FEFF 在 UTF-8 解碼時剝除（編輯器加的 BOM 無害）；
                檔案**中間**的 U+FEFF 是未知內容 → malformed
  ```

  其餘一律 malformed（fail-loud）：**未知頂層行**（含 `meta: {`——#112 修掉縮排類
  fail-silent 後，flow mapping 第 0 欄的鍵是僅存的毒化繞法，本 grammar 整類關閉）、
  **縮排的非註解行**（marker 無巢狀結構）、**第二個 `format:` 行**（歧義不猜）、
  **值後的非註解尾隨內容**（`format: 2 garbage` 不得取前綴當真）。解析器 **MUST NOT**
  「跳過不認識的行」——跳過正是 fail-silent 的來源。未來要加 additive key，**MUST**
  連同本 grammar 一起修訂（marker 是自產檔，additive 演化必經設計）。
  相容性註記：手工加料過的 `store.yaml` 自 #117 起會被拒絕（fail-loud）；
  `write` 模板產出的形狀（註解 + 單一 `format:` 行）不受影響。

**版本對照**（source of truth 是 `StoreVersion.supported` 的文件註解；下表為對照）：

| format | 變更 | 為何 non-additive |
|---|---|---|
| 1 | v1.x 家族（`entries/<citekey>.yaml` + `people/<person-key>.yaml`）| — |
| 2 | `entities/<uuid>.yaml`（#35，見 §5.-1）| 結構重排；舊 binary 看到空的 `entries/` 而回報「0 entries」——一個**看起來成功的錯誤答案** |
| 3 | 記錄形狀改由**裸標籤**標示，不再由 `type:` 的值標示 | 舊 binary 看不到 `type: person`，走全稱後備判成 work、decode 失敗 |
| 4 | 新增 organization 形狀；person 的隸屬值由字串升成**指涉或字面** | 舊 binary 不認得 `organization:` 標籤，也讀不懂 `{key: …}` 形式的隸屬值 |
| 5 | 廢除「`names` 第一個是顯示名」，改由 `authorized` 指定（#81，見 §3.1）；**`divergence` 形狀歸屬本版**（#71 引入、#74 回填歸屬） | **欄位語意變更**。`authorized` 對舊 binary 是未知欄位、會被保留，但保留不等於遵守——舊 binary 仍會把 `names[0]` 當顯示名，並在一次 read-modify-write 裡重排 `names` 而不自知。`divergence:` 形狀標籤對 ≤4 世代 binary 是整檔 quarantine（形狀標籤是 strict——#131 判準重評，曾誤標 additive）；`writeDivergence` 對 format < 5 的 store 拒寫＋指路（#74） |
| 6 | 時間軸段內新增 `ended: true`（已結束、時點未知，#63）；null-face 對齊 | **段內鍵是 strict**——tolerant-preserve 的開放層只涵蓋記錄頂層與 `akashic` namespace，舊 binary 讀到 `ended` 是整檔 quarantine（人檔消失）而非保留。`writePerson` 對 format < 6 的 store 拒寫含 ended 段的記錄＋指路（#131） |
| 7 | 時間軸段內新增 `attested: [觀測點]`（某時點成立、起訖皆不明——`ended` 的鏡像，#70）| 同 6：段內鍵 strict → 舊 binary 整檔 quarantine；write gate 對 format < 7 拒寫＋指路。`attested` 與 `start`/`end`/`ended` 並存是矛盾（encode/decode 兩端拒收）|
| 8 | `references[].field` 白名單新增消解判定欄位對 `resolution-confirmed`／`resolution-rejected`（#232，見 §3.5 消解判定節）| 同 6/7 的「看似 additive 其實不是」：field 白名單是 strict → 舊 binary 讀到 verdict reference 是整檔 quarantine（記錄消失），且該檔可被 bootstrap 的決定性 UUID 安靜覆寫、判定史全滅（#232 verify 實測整條鏈）。write gate 對 format < 8 拒寫含 verdict 的記錄＋指路；序列化形狀不變——8 只是「這個 store 可以持有 verdict」的宣告 |
| 9 | 附件鍵域收窄為只剩 `zotero`（移除 `pool`）；新增記錄側副本引用 `akashic.sources`（#223，見 §2.4／§2.4.1）| **提升依據是鍵域的嚴格性，不是資料量**：`attachments` 元素鍵走 strict 驗證，未知種類導致**整檔 quarantine** 而非保留，所以縮減鍵域是 non-additive——帶 `pool` 附件的記錄被新 binary 讀到會整檔消失。移除當下受影響資料為 0 筆，但那是**巧合而非契約**；當死碼移除而不 bump，會讓 refuse-if-newer 在下一次真的有資料時失效。`writeEntry` 對 format < 9 拒寫含 `akashic.sources` 的記錄＋指路（原佔 8，rebase 時已被 #232 佔用順延） |
| 10 | person 的 `names` 巢狀化為 `authorized`／`variant` 兩個分割（頂層 `authorized` 欄位移除）；`id` 改為建立時發放的獨立 v4、缺 `id:` 的檔 fail-closed（#227／#241）| **known 欄位的形狀演化不入 tolerant 範圍**（同 6/7 的機制）：巢狀 `names` 對 v9 binary 是形狀不符 → 整檔 quarantine（人檔消失）。v10 binary 對平坦 `names` 與頂層 `authorized` 同樣 fail-closed——舊形狀只能經 `migrate-person-identity`，decoder 順便相容是 no-compat-fallback 要擋的第一類。子集不變式「`authorized` ⊆ `names`」由結構承擔（矛盾狀態不可表達）、執行期檢查退場；**內容**約束兩條留在執行期：「每書寫系統至多一個」與「兩分割互斥」（同一字串不得同時在 `authorized` 與 `variant`——結構表達不了跨陣列值域，#227 verify R1 補；decode 對檔上矛盾 fail-closed、`writePerson` 經 validate 擋所有寫入路徑）。`migrate-person-identity` 是舊形狀唯一的進入路徑，涵蓋面是封閉列舉（entities 裸標籤／format-2 `type: person`／legacy `people/` 佈局就地遷移／缺 `id:` 補發／簡單 flow-style 摺疊），error 級記錄一律先過 validate、失敗進 failed 不落盤（含已是新形的 skip 候選）；中斷重跑以 **key 級**分組收斂（任何形狀組合的同 key 殘留都點名交人、永不發第三個 id）；`--apply` 要求每個將被改寫的檔**自身**被 git 追蹤（目錄級不夠——被 ignore 的檔 git 零歷史，改寫即不可回復）。`writePerson` 對 format < 10 拒寫含 names 的 person＋指路。**升級前置**：先確認會碰 store 的 CLI/MCP/App 都已升到 v10 世代，跑 `migrate-person-identity --apply`（一併重發全部 person id 為 v4、檔名同步），驗證後手動把 `store.yaml` 的 `format:` 改成 10。organization 不變（其 names 是時間軸；不對稱是刻意的）（原佔 8，實作時 8/9 已被 #232／#223 佔用順延） |
| 11 | 新一級形狀 `venue:`（發表載體——期刊／會議／出版社，封閉 `type` 三值**——當時的值域；#324 已改為六值，見 format 12 那一列**）＋ entry 的 `venues:` 有序二態 ref 邊（`- key:`／`- literal:`，作品側為正典側、反向現算）（#304） | **non-additive，實測依據**（2026-08-16，format-10 binary 對含 `venue:` 檔的 copy store）：未知頂層形狀 → **整檔 quarantine**（「頂層的無值鍵 『venue』 不是已知形狀（已知：divergence、organization、person、work）」——記錄自計數與查詢消失，與 format 6 的 ended 前例同型）。entry 的 `venues:` 鍵在舊 binary 落 tolerant-preserve（保留不解讀），但「保留而不解讀」對 ref 邊＝反向查詢靜默漏資料——併入同一 bump。venue 記錄形狀：`id`（v4，建立即發放、無 v5 遺產故無 legacy 補值入口）／`key`／`type`（封閉三值，未知值整檔拒讀）／`names`（`TimelineOf<String>`——刊名沿革即時間軸，同 organization 模式；巢狀化是 person 專屬的刻意不對稱）／`authorized`（執行期子集檢查）／`note`／`references`。匯入端只產生 `.literal`（`literal-first-then-key` 規則）；`fields` 的 journaltitle 等字串照舊保留（ref 是升格不是取代）。`migrate-venues` 回填既有 entry（dry-run 預設、只加不改、idempotent）。write gate 對 format < 11 拒寫 venue 記錄與含 `venues` 的 entry＋指路。**升級前置**：CLI/MCP/App 全升 v11 世代 → `migrate-venues --apply` → 驗證 → 手動 `format: 11` |
| 12 | `Author` 三態（新增 `organization:` 鍵，#323）＋ `VenueType` 值域改以 APA7 §9.23–9.33 的 source 類型學為判準（`journal` → `periodical`，新增 `database`／`socialMedia`／`website`，#324） | **non-additive，實測依據**（2026-08-19）：**#323** format-11 binary 讀含 `authors: [{organization: …}]` 的 entry → `rejectUnknownKeys` 擲錯、被上層轉成**整檔 quarantine**；實測 `akashic query` 回 **rc=0 且該筆整個消失、無任何訊息**，只有主動跑 `doctor` 才看得到 `quarantined: 1`（與 format 11 的 venue 前例同型）。**#324** `VenueType` 的 decode 對未知值**整檔拒讀**，舊 binary 讀到 `type: periodical` 直接拒絕整個檔案。write gate 對 format < 12 拒寫「含 organization 作者的 entry」與「type 不在 format 11 值域內的 venue」；`venueTypesReadableAtFormat11` **寫死是刻意的**——它記錄的是歷史事實（format 11 的 binary 認得哪些值），不是當下值域的函式。**`Entry.type` 的封閉列舉（#325）刻意不在此列**：`type` 是自由 `String` 且 decode 不驗，舊 binary 讀到新值走 tolerant-preserve 原樣保留——那是 additive，依本檔的判準表不該 bump。#325 的安全性由**兩階段部署順序**承擔（先 `migrate-work-types --apply`、再上線嚴格 decode），不是由 format 承擔 |
| 13 | 識別碼欄位（`venue.issn`／`organization.ror`／`work` 的 `doi`・`pmid`・`isbn`）進 `ProvenanceReference` 的可附著欄位集合，使識別碼能攜帶來源；`Entry` 新增 `references` （封閉列舉第 15 條邊）；venue 補上先前**完全沒有**的附著驗證（#394） | **non-additive，實測依據**（2026-08-24，對 `6a234d4` 建出的 format-12 binary 餵同一份 fixture）：**三種新形狀的行為各不相同，而只有一種是硬觸發**——(a) `organization` 帶 `field: ror` 的 reference → **整檔 quarantine**（「organization 沒有可附著 reference 的欄位『ror』」）；(b) `venue` 帶 `issn:` ＋ `field: issn` → **載入**，落 tolerant-preserve；(c) `work` 帶 `references:` ＋ `doi:` → **載入**，落 tolerant-preserve。原因是附著驗證只有 person 與 organization 有，**venue 先前沒有**（本 change 才補）。（b）（c）併入同一個 bump，理由沿用 format 11 對 `venues:` 的既有裁決：「保留而不解讀」對一條 ref 邊等於反向查詢靜默漏資料，而 provenance 更尖銳——一筆不被解讀的 reference 不會被附著驗證，於是它可以指向一個不存在的值而沒有人發現。 **write gate 只擋 reference，不擋識別碼欄位本身**：後者是 additive（上表 b／c 實測），而對它設閘會讓 `migrate-identifiers` 在 bump 之前跑不動——design.md 的部署順序要求遷移**跑在舊解碼器上**、format bump 是最後一步（先有雞先有蛋）。**升級前置**：CLI/MCP/App 全升 v13 世代 → `migrate-identifiers --apply` → 驗證 → 手動 `format: 13` |
| 14 | venue 的 `names` 拆出 `variant` 分割（異寫法，#422）＋ `paginated` 三態判定（本刊使用頁碼嗎，#406） | **對舊 binary 是 additive，仍 bump**（#422 verify R1 更正，2026-09-02）：第一版此格寫「`VenueYAML.knownKeys` 是封閉鍵域 → `rejectUnknownKeys` → 整檔 quarantine」，**與程式相反**——`VenueYAML.decode` 走 `captureUnknownBlocks` 的 tolerant-preserve，format-13 binary 讀到頂層 `variant:`／`paginated:` 會**原樣保留而不解讀**（上一列 format 13 早四天就對同一層的 `issn:` 實測過同一件事（b）；`VenueTests.testUnknownFieldsTolerantPreserved` 釘著）。**bump 的理由沿用 format 11 對 `venues:`／format 13 對（b）（c）的既有裁決**：「保留而不解讀」對一個**分割標記**等於舊 binary 安靜地把異寫法當一般名字顯示、把已判定的 `paginated` 當從未判定——不會大聲失敗，所以更需要 marker 讓 refuse-if-newer 出聲。write gate 只對 `paginated` 設閘、`variant` 不設（同 format 13 對識別碼欄位的 doctrine：`variant` 有必須跑在 bump 之前的遷移，設閘會讓它跑不動）。**兩個欄位併入同一個 bump 是 #406 的排程裁決**（該 issue 的三個選項取第 3 個「欄位合併、判定分開」）：分兩次做等於兩輪「build 三 binary → migrate → validate → 手動 bump」，而那條鏈每一步都是本檔記過會出錯的地方。**`paginated` 的 `nil` 不得折成 `false`**——「未判定」與「判定為不使用頁碼」是兩件事，前者是 APA7 下限**仍該報缺**的狀態；decode 只收 `true`／`false`，其餘整檔拒讀。**升級前置**：CLI/MCP/App 全升 v14 世代 → `migrate-venue-variants --apply` → 驗證 → 手動 `format: 14`。**順序約束（#554）**：這一步必須跑在任何 `update-venue --authorize` 之前——`--authorize` 刻意把換下來的舊指定留在未標，而本遷移的補集規則會把它重新標成 variant；已有 `--authorize` 記錄的 store **不得再跑**，退場見 #567。**#554 起 venue 名字內容另有寫入期不變式（無 format bump）**，見 §5.7 |

| 15 | venue 的 `paginated` **判定 reference**（`field: paginated` 的 judgement，#406） | **non-additive，實測依據**（2026-08-31，R1 verify 在完整 store 副本量測）：format 14 只涵蓋**頂層** `paginated:` 欄位；判定 reference 是之後才引入的 vocabulary——format-14 binary 的 venue 附著驗證沒有 `paginated` case，讀到 `field: paginated` 的 reference → 封閉 default 擲錯 → **整檔 quarantine**。最尖的一格：406 個 venue 靜默掉到 373、rc=0、`export-bib` 回到判定前的數字——**舊 binary 的輸出與「這些判定從未發生」不可分辨**，連鎖到 `add-venue` 重複 key → UNIQUE constraint 讓 doctor/venues/venue 全滅。write gate（`assertVenueWritable`）對頂層 `paginated` 值在 format < 14 拒寫（那是 format 14 的鍵域）、對 `field: paginated` 判定 reference 在 format < 15 拒寫——兩個閘分開（#422 verify R2 更正：先前此處把兩者都寫成 < 15）。**升級前置**：CLI/MCP/App 全升 v15 世代 → 手動 `format: 15`；**且 marker bump 前不 push store repo**（gate 讀 marker 不讀 binary 能力——已寫入的記錄只有 marker bump 防得住其他 clone 的舊 binary） |
| 16 | work 側的**拆分記錄**（`field: authors` 的 judgement reference，value＝被拆掉的原 literal 逐字，statement `拆為 ⟦a⟧ ⟦b⟧：理由` 走 `SplitRecordValue` 單一解析器，#450） | **non-additive，理由同 15**：format-15 binary 的 `Entry.validateReferenceAttachment` 沒有 `authors` case → 封閉 default 擲錯 → **整檔 quarantine**——被拆過的 work 在舊 binary 上整筆消失、rc=0，輸出與「這筆從未存在」不可分辨。write gate（`assertEntryWritable`）對 format < 16 拒寫帶拆分記錄的 entry；`splitAuthors` 在**任何寫入之前**對全部計畫過閘（整批零寫入）。空 rests-on 經 `ProvenanceReference.firstOrderRulingFields`（＝resolution 兩欄位 ∪ `authors`）放行——第二個具名集合，`resolutionVerdictFields` 不動（三處把它當 verdict 文法解析）。**無資料遷移**：#443 已拆的 4 筆（store `32916ba`）不回填。**升級前置**：CLI/MCP/App 全升 v16 世代 → 手動 `format: 16`；且 marker bump 前不 push store repo（同 15 的理由） |
| 17 | work 側的**移除記錄**（同一格 `field: authors`，statement `移除：理由` 走 `AuthorRemovalRecordValue` 單一解析器，value＝被移除的原 literal 逐字，#457） | **non-additive，理由同 16 但成因不同**：format-16 binary 的 `authors` case **存在**，所以不是走到封閉 default，而是走到 `SplitRecordValue.parse(statement) != nil` 那道 guard——移除記錄的前綴是 `移除：` 不是 `拆為 `，parse 回 nil → **一樣整檔 quarantine 且 rc=0**。差別只在錯誤訊息會說「不是合法的拆分文法」而不是「不認得的 field」，對使用者一樣是「這筆 work 消失了」。write gate（`assertEntryWritable`）對 format < 17 拒寫帶移除記錄的 entry；`dropAuthors` 在**任何寫入之前**對全部計畫過閘（整批零寫入）。**為什麼不重用 `SplitRecordValue`**：它的 `init?` 要求段數 ≥ 2，放寬到 0 會讓 `unsplitAuthors` 把一次移除讀成可還原的拆分並把字串塞回作者位——正好是這個面要消除的東西；兩種記錄要在文法上就分得開。空 rests-on 沿用 format 16 那一列的 `firstOrderRulingFields`（`authors` 已在其中，不新增集合）。一致性條件與拆分**相反**：拆分要求「至少一段仍是作者位」（`staleSplitRecords`），移除要求那個字串**不在**作者位（`contradictedRemovalRecords`），兩者皆 warning。**無資料遷移**。**升級前置**：CLI/MCP/App 全升 v17 世代 → 手動 `format: 17`；且 marker bump 前不 push store repo（同 15／16 的理由） |

3 與 4 曾經發生而未回寫本表（#81 補齊）；6 曾漏補（#74 一併回寫）。**「資料鍵變保留字」同屬版本歸屬**：`divergence` 成為形狀標籤使同名頂層鍵在 ≥5 成為保留字——這與形狀標籤機制（format 3）的既有語意一致，不另立規則（#74 後果二）。`akashic migrate` 是使用者知情動作：它把 store 升到 supported 版本，升版後舊 binary 整庫拒開是 refuse-if-newer 的**預期**行為，不是 migrate 的缺陷（#74 後果三，文件化現況）。

### v1.3：tolerant-preserve（開放演化層）

**開放演化層**——entry 頂層、person 頂層、library 頂層、`akashic` namespace——的
未知欄位**不再是 decode 錯誤**。行為契約（normative）：

1. **容忍（MUST）**：未知欄位不使檔案 quarantine；已知欄位照常可讀可用。
2. **保留（MUST）**：未知欄位的 value 子樹整棵保留（`UnknownField`，YAML 文字形式），
   re-encode 時原樣寫回。**容忍與保留不可拆分**——只容忍不保留會讓舊 binary 的
   read-modify-write 靜默剝掉新欄位，是資料毀損路徑（v1.2 以前用 throw 防這件事，
   v1.3 用保留寫回達成同一保證，同時讓較新 schema 的檔案保持可用）。
3. **可見性（MUST）**：`validate()` 對未知欄位發 warning（非 error）；
   `doctor` 列出含未知欄位的檔案（`unknownFieldFiles`），提示升級 binary。

**strict 保留層**（closed shape，未知欄位仍＝decode 錯誤）：`authors` 元素
（key/literal 二態封閉）、**`attachments` 元素**（`{zotero: path}` 單鍵封閉——R6 補列：此層加新欄位會原地重演 #23 的失敗模式，演化必須與 binary
同步 + 版本訊號，見 #24）、`provenance`（Zotero namespace，mapping 與 binary 同步
演化、pull 覆寫）、`akashic.relations`（新關係類別應為 `akashic` 層的新欄位，
由該層容忍涵蓋），以及 `akashic.author-list-completeness` 的四鍵 mapping、
`attested-authors` 槽與 nested `references`。最後一項是 truth-bearing witness：未知或
重複 key、null、stale binding 都必須 quarantine，不能由 tolerant-preserve 吸收成
「沒有 witness」；只有不認得整個頂層 `author-list-completeness` key 的舊 binary 才把
完整未知子樹逐字保留。

**known 欄位的形狀演化不入 tolerant 範圍（normative，R6；R8 精確化）**：known
key 存在但形狀不符（如 `names` 由 sequence 演化為 mapping、`tags` 變 mapping、
`status` 變 sequence、`imported_at` 非 ISO-8601）→ **decode 錯誤 → quarantine**。
**例外（R8，R9 限縮到 collection 欄位）**：**collection 形狀**的 known 欄位
（`akashic:`/`fields:`/`names:`/`authors:`/`attachments:`/`relations:`/`tags:`/
`libraries:` 等）遇 explicit/implicit **null**（空值行、`~`、`null` 面）視同
「欄位不存在」——null 沒有可被剝除的子樹，quarantine 會把 v1.2 可載入的良性檔
推下可用性懸崖；face 白名單只收 **plain 樣式**的 `""`/`~`/`null`/`Null`/`NULL`
——顯式 `!!null` **帶非 null-face 內容**（如 `!!null foo`）走形狀 guard、不被
吸收。**R11 更正（R10-verify M7/M17）**：原文寫「帶內容與否**皆**不被吸收」
是過度宣稱——`!!null null` / `!!null ~` 的 composed node 與 implicit `null`
**完全相同**（同 `style == .plain`、同 `tag == Tag(.null)`、同字串面），
resolved tag + style 無法分辨顯式與隱式。而兩者語意本來就等價、吸收不丟任何
子樹，故照實記載為「與 implicit null 同視同不存在」。**具名例外（R10
記載）**：`provenance.imported_at`/`orphaned_at` 雖是 scalar，因模型為
Optional 日期、nil↔省略等冪，null 面同樣視同不存在（RMW 會把該行正規化為
省略）；同一 mapping 內 `zotero_hash: ~` 則以字串面保留 `"~"`——差異照實
記載。除此之外 **scalar 欄位不適用**：其 extractor 以字串面收下 null-face
（`title:` → `""`、`title: Null` → `"Null"`）——emitter 對 `""`/`"null"`/`"~"`
就是輸出 plain null-face，套 null-as-absent 會讓 Zotero 無標題 item 永遠寫不進
store、v1.2 的 `title: Null` 檔被 quarantine（R8-verify CRITICAL）。附帶語意
（照實記載）：collection **內部**的 null 元素同樣走字串面、保留**來源字面**
（`[~]` → `"~"`、`[null]` → `"null"`、`[a, , b]` 的空元素 → `""`）。**RMW
正規化（記載）**：collection 的 null 行重寫後省略（空集合≡省略是 §2.2 既有
契約，非資料損失）；scalar 的 null-face **值**重寫後以 plain 面落地，磁碟
表徵與 YAML null 不可區分——本 binary 以字串面讀回（round-trip 穩定），
第三方 reader 會讀成 null（interop 邊界）。v1.2 的
strict gate 事實上同時保護形狀演化（unknown key 先 throw、檔案永不被寫回）；
v1.3 若只接「加 key」那一半，較新 schema 把既有 key 變豐富時，舊 binary 的
read-modify-write 會把該欄位整段**靜默剝除**且所有檢查綠燈（verify R5 DA 實測
構造：`names` 被無害編輯刪除）。quarantine 是 v1.2 級保護——檔案原封不動、
升級 binary 後恢復。非累加的形狀演化應走版本訊號（#24）。

**字串欄位以 scalar 的字串面解讀（normative，R6）**：known 字串欄位（tags、
names、status、author key/literal、fields 值等）接受**任意 scalar**、取其字面
內容；非 scalar（sequence/mapping）→ decode 錯誤。理由：emitter 對「長得像
int/bool/null 的字串」（如 tag「2026」）輸出 plain 樣式，plain `2026` re-parse
resolve 成 int——嚴格拒收使**本 binary 自己寫出**的檔案永久 decode 失敗
（寫得出、讀不回的自我毒化，verify R5 DA 實測）。字串面解讀與 emitter 對合，
encode/decode 等冪。

**接受的 trade-off**：typo 偵錯從 hard-reject 降為 warning——`orcidd:` 這類打錯
不再擋下，由 validate / doctor 的 warning 保持可見。

**保真邊界（normative，verify R2 後 α 定案）**——保留載體是**原始檔案的逐字文字
區塊**（含 key 行與其縮排子行），decode 不 serialize、encode 逐字 append：

- **byte-level 保真**：未知區塊內的 key 型別（quoted / typed）、tag（`!!binary`、
  自訂 tag）、anchor / alias（**不展開**）、註解、block scalar 全部逐字保留。
  結構上不存在展開放大——未知子樹從不經過 parse-reserialize。
- **欄位重排**：已知欄位由 encoder 重寫在前；未知區塊 append 到檔尾（akashic 的
  未知子區塊 append 在 akashic 段尾、必要時做**等量縮排平移**——整塊每行加減
  同量前導空白，YAML 相對縮排語意不變）。**平移不變式（R6，R7 精確化）**：
  語意續行平移後必須仍深於目標縮排，否則會成為下一次 decode 的同層 entry 起始
  （區塊切不開、記錄「讀得到但永遠寫不回」）→ encode 拒寫（fail-closed；
  decode 端對縮排不足的版面仍容忍，讀取可用性不受影響）。豁免與切分規則對齊
  的三類行（R7——不變式必須鏡射 entry-start oracle）：註解行、空白-only 行
  （語意等同空行）、sequence 指標行（indentationless sequence 落在目標縮排
  合法，低於才拒寫）。空行逐字保留（含 `|+` keep-chomping 的尾端空行）；
  stream-scoped 標記行（column-0 的 `---`/`...` **含尾隨空白/註解變體**、
  `%` directive 行——R6 擴列；stream 開頭的 UTF-8 BOM——R7 補列）於擷取時
  剝除——它們不屬於欄位資料，隨區塊搬移會使產物無法解析。
- **不保留**：檔案前導（檔頭註解、directive、`---`）與已知欄位側的註解——known
  重寫本就不保留（與 v1.2 行為一致）。**註解歸屬（R6 明確化）**：區塊以 key 行
  起算，緊貼在未知欄位**上方**的註解歸前一個（已知）區塊、不保留；只有 key 行
  之後、落在區塊內的註解逐字保真。
- **fail-closed 對齊 oracle（R3 定案——計數校驗不夠）**：每個未知區塊必須
  (a) 能**獨立**解析（跨區塊 anchor/alias 引用在此擋下）、(b) 恰為單一 entry、
  (c) key 相符、(d) 值與原 parse 的節點**語意相等**（預算走訪）。任一不成立 →
  decode 錯誤 → 檔案 quarantine——絕不冒錯位寫壞的險。涵蓋：complex key、
  flow-style、tagged decoy、值截斷。**驗證預算（R6 更正歸因，R7 改共用）**：
  語意比對次數與節點數線性相關，上限 200,000 次、**單次 decode／encode 全檔
  共用**（R7；R8 起 encode 側跨 entry/akashic 兩層同一份預算；encode 內含的
  canary decode 屬一次 decode、自帶同額預算——它才是 encode 路徑的實際約束，
  R10 撤回 R9 的 2× 放寬）；耗盡訊息指認
  的是「觸發」區塊，實際消耗可能來自同檔較早的區塊（訊息已註明）；另設遞迴
  深度上限（512）——深巢狀子樹 fail-closed quarantine 而非 stack overflow；
  實際可容納的節點數依結構而定（單鍵 mapping 元素約耗 3 次比對/個）。巨大
  未知子樹與 anchor/alias 重用型 DAG 都會觸發 → quarantine。這是未知子樹的
  實質大小上限（可用性懸崖，照實記載）；超大 payload 不應塞在未知欄位裡。
> **想知道「為什麼」而不是「規則是什麼」** → [`explainers/yaml-alias-dos.md`](explainers/yaml-alias-dos.md)
> （一分鐘版的比喻、實測的 43,000 倍、七次失敗各錯在哪、威脅模型）。本節是 normative 規格。

- **已修：alias 展開 DoS（#36 / #27，normative）**——`compose` **之前**在 parser 的
  **event 層**估計展開成本。**三個獨立的軸**，任一超過即拒收（quarantine）：

  | 軸 | 上限 | 擋的是什麼 |
  |---|---|---|
  | 展開後**節點數** | 200,000 | 指數放大（billion laughs） |
  | 展開後 **bytes** | 64 MB | **重量**——19,000 次引用一個 5 KB scalar 只算 38,003 節點（計數過關），展開後卻是 95 MB |
  | **展開後**的樹深 | 512 | **語法深度看不到的那一種**——`k1: &a1 [*a0]` 每行都是深度 1，展開後卻可以是 8000 層 |
  | 輸入 bytes | 8 MB | 單一超大 scalar |

  **三個軸各自獨立，而且每一個都是被打出來的**：

  - **計數不等於重量**——只算節點數會讓「少量 alias 引用大 scalar」完全通過。
  - **語法深度不等於展開深度**（PR #49 因此被撤回）。這個構造語法上完全是平的：

        root: &a0 x
        k1: &a1 [*a0]
        …8000 層…
        ? *a8000
        : 1

    180 KB、24,005 節點、**語法深度 2**——只測語法深度的守衛完全放行，而
    `akashic validate` 直接 **SIGSEGV（exit 139）**。libyaml 的 `MAX_NESTING_LEVEL`
    也不觸發，它同樣只管語法。**SIGSEGV 比 DoS 更嚴重**：DoS 會 timeout 然後
    quarantine，SIGSEGV 是 `catch` 抓不到的，那個檔案會讓三個 consumer 每次載入都死。

    所以估計器記的是**展開後的樹深**：anchor 記錄其子樹深度，alias 引用時取該深度，
    collection 的深度 = 1 + 子節點最大值。

  **上限設在合法可解析範圍之內就是誤殺**：實測 500 層的 `[[[…]]]` 仍能被 Yams 正常
  compose，所以 512 是下界。真實書目資料的深度是個位數。

  **為什麼是 event 層**：`yaml_parser_parse` **不展開 alias**（每個 alias 就是一個
  `YAML_ALIAS_EVENT`），成本與**輸入大小**成正比，與展開後大小無關。而它給的是 parser
  自己的判斷，**不需要重現任何 YAML 詞法**——那正是前五次失敗的來源。

  **慢的到底是什麼（實測，非推論）**——同一個 bomb，只差 alias 放在哪：

  | alias 位置 | bytes | `Yams.compose` |
  |---|---|---|
  | **value**：`zz: *a8` | 404 | **0.001 s** |
  | **key**：`*a8: 1` | 403 | **43.4 s** |

  **43,000 倍**，展開量完全相同（9⁸ ≈ 4300 萬節點）。原因：compose 建完 mapping 後要
  檢查重複鍵，而那需要 hash 每個 key node——key 是 alias 時得**遞迴 hash 整棵展開後的
  子樹**，且**沒有 memoisation**。value 位置不痛是因為 Yams 的 `Node` 是 enum，
  alias 在 value 位置只是共用同一個節點參照（COW），沒有真的展開。

  **但守衛不需要知道位置**：它擋的是「展開量大」，而展開量大是 key 位置爆炸的**必要
  條件**。擋掉必要條件就夠了。R11 那一輪去猜 complex-key 語法，直覺方向對（位置確實
  是關鍵）但用文字判位置必然失敗——`*a: 1` / `{? *a : 1}` / `{*a: 1}` 是同一件事的
  三種寫法。

  **門檻與成本的對應**（實測，約線性）：

  | 展開節點 | compose |
  |---|---|
  | 11 萬（fan 2 × 12 層）| 0.01 s |
  | 480 萬（fan 9 × 7 層）| 4.8 s |
  | 4300 萬（fan 9 × 8 層）| 43 s |

  所以 200,000 的門檻對應 compose 約 **0.2 秒**上限。

  **三個由 verify 補上的修正（第 7 版）**：

  1. **估計值必須精確等於真實展開量**，不是「夠接近」。記錄 anchored 子樹大小時漏算
     collection 自己那一層，單看是差一，鏈起來累積成 **84 倍**（500 層的鏈估 1,505、
     真實 126,755）。修正後四組構造的估計值與真實值**逐一相等**。
  2. **節點軸只在有 alias 時生效**。alias-free 的檔案放大**定義上不可能**，成本由
     `maxBytes` 已界住（實測 alias-free 的 compose 對輸入線性）。不 gate 的話 1.8 MB 的
     正常大檔會被擋下並告知「這是攻擊的形狀」——誤殺，而且訊息是錯的。
  3. **寫入路徑放寬 2×（遲滯）**。encode canary 走同一道守衛，讀寫門檻若相同則一筆
     199,999 節點的記錄讀得進來、下次編輯多一個節點就**永遠寫不回**。R9 對 oracle
     預算做過同一件事，理由逐字相同。

  **排除清單（文字層方案，不要再試）**：

  | 嘗試 | 輪次 | 死法 |
  |---|---|---|
  | 行尾字元全文掃描 | R5 / R6 | 誤殺 block scalar 內容 |
  | `? key` complex-key 判定 | R10 / R11 | 三條繞道未擋 + 誤殺 emitter 輸出 |
  | anchor/alias 計數 | PR #42（撤回） | 真實 corpus 已坐在門檻上；跨行引號（雙向）、跨行 flow、CRLF、`#` 判準全破 |

  共同形態：**用手寫的逐字元狀態機重現 YAML 詞法**。引號跨行、flow collection、
  block scalar 標頭、CRLF、註解起始條件，每個細節都是一個獨立破口。

  **門檻由合法資料的最壞情形校準，不是由現況**（這個區別是實作時修正的重點）：

  | 輸入 | 估計節點數 |
  |---|---|
  | 真實 corpus 最大檔（536 檔實測） | **180** |
  | 45 位作者 + 40 個大欄位的 entry | 230 |
  | **#20 的 temporal person，1400 段時間軸** | **15,859** |
  | fanout 2 × 12 層（**compose 僅 0.01 s，不痛**） | 135,158 |
  | **真正會痛的**：fanout 9 × 7 層（357 B、compose **4.8 s**） | **超過門檻** |

  第三列是**合法資料**——#20 明說「全部維度都要記錄歷史」，而 ISS 有 77 位 PI、六個維度
  加聯絡資訊。門檻若貼著現況（~700）設，這種記錄會被誤殺，而誤殺代表**永久寫不回**
  （encode canary 也走這道守衛），那正是 R11 的死法。200,000 讓合法最壞情形有 13× 餘裕、
  **門檻擋在痛點之前**（實測 fanout 9 的痛點在 lv=7、compose 4.8 s，而 lv=5 就已超標）——**兩邊都留餘裕**，不是只顧一邊。

  對比 PR #42 的「anchor 數 × alias 數」：那種代理指標與真實資料的距離**無法量測**，
  結果 corpus 已經坐在上面。這裡是**同一個量綱**的直接比較，兩邊的餘裕都看得見。

  **實測**：R12 三條繞道 + PR #42 四條（`>` 致盲、跨行 flow、CRLF、`#` 判準）+ 單一
  anchor 放大 + 超大 scalar，**全部擋下**；713–789 B 的 payload 從 **40 s timeout →
  0.33 s quarantine**。真實 corpus 536 檔零誤殺（validate 全程 0.32 s），emitter 對
  含跨行折行的長 abstract 輸出零誤殺。

  **守衛位置**（五處，缺一不可）：三個 decode 入口、encode canary、`EntityKind.peek`
  （**entities 佈局的第一個動作**——只接 decode 入口實測仍會 timeout）、
  `verifyBlockOracle` 的區塊獨立 compose（整檔通過不代表每個切片都便宜）。

  實作在 `Sources/AkashicCore/AliasEventBudget.swift`，libyaml vendored 於
  `Sources/CLibYAML`（Yams 未把 `CYaml` 匯出成 product，見 `include/VENDORED.md`）。

- ~~**已知未防護：alias 落在 mapping key 位置的展開 DoS（R12 照實記載）**~~（已修，見上）：本檔
  所有預算守衛都跑在 `Yams.compose` 之後，而 composer 的重複鍵偵測會對每個
  key node 遞迴 hash（無 memoisation）。alias 指向 DAG 且落在 key 位置時，
  展開發生在 compose **內部**，預算一個都還沒開始跑。實測三種形式在 630–645
  bytes 下都讓消費端 100% CPU 直到 timeout：`*a12: 1`（block 隱式）、
  `{? *a12 : 1}`（flow 顯式）、`{*a12: 1}`（flow 隱式）。
  **這不是 v1.3 引入的**——`compose`-first 的順序自始如此。R11 曾嘗試在文字層
  以 `? key` 判準攔截，**兩個方向都錯**（三條繞道未擋；block scalar 與折行續行
  的合法 `? ` 內容被誤殺，且因 encode 內含 decode canary 而變成寫不回），已於
  R12 revert。文字層補不到 flow context 與 implicit alias key；正確的層是禁
  anchor/alias 的 profile gate（見 `docs/specs/2026-08-01-akashic-yaml-input-profile-design.md`）
  或 Yams 端。已另立 issue 追蹤（#36）。

  **揭露範圍（R13 codex 補）**：不只 alias-in-key。**所有 `compose` 之前的資源
  耗用皆未防護**——200,000 節點預算不限制單一**超大 scalar**（數百 MB 的 scalar
  對節點走訪只算一個節點，decode 端亦無檔案大小上限）；`depth > 512` 只保護語意
  比較那一段遞迴，保護不到 libyaml/Yams 在 compose 階段的解析堆疊與記憶體。

  **威脅模型（避免與 `displaySafe` 的註解讀起來互斥）**：store 目錄對**可用性**
  （DoS）而言目前必須視為信任邊界內——沒有防線，一個 630 B 的檔案就能讓 consumer
  掛死。但對**完整性與顯示安全**而言它是未信任的：檔案可能由別的 binary、別人、
  Dropbox 同步寫入，所以未知欄位 key 與 quarantine reason 一律經 `displaySafe`。
  兩者不矛盾——是同一份資料在不同軸上的不同假設，而 DoS 那條軸的防線還沒蓋。
### 5.7 venue 的名字內容：寫入期不變式（normative，#554 D8；R6／R7／R9／R10／R11 補記）

`venue:` 記錄的 `names[].value`／`authorized[]`／`variant[]` 每一筆字串在**寫入期**
（`writeVenue`／`fmt`／合併的 keeper 寫回／work・person 合併對持有被併鍵 verdict 的 holder 遷移——venue、
organization、person 三種各過各的閘（R9，D24；2026-09-14 以含此版的 binary 對 live store 跑 `validate`：4,572 筆 person、13 筆
organization 零 error——擴閘不拒絕任何既有記錄；閘在 `fieldsLostByMerging` **之後**，merge 專屬的那句先出，R10）／
`resolve-venues` 的 verdict 寫回——repoint／demote 寫 verdict 時退役同 holder 上同一配對的相反判定（D20）；配對唯一性的
規範文字在 §3.5「配對的唯一性」，這裡不複述（D23／D25／D27／D28／D31／D32／D33）；退役的每筆逐字回報在 `verdictsRetired`
（截 20 筆，`verdictsRetiredTotal`／`truncated` 揭露）；第 5 條的求值上限在讀取路徑上也跑）都要通過
`Venue.validate()` 的名字內容檢查，**error 級**；decode **不驗**（load 照讀，
`validate`／`doctor` 報出來）。這一段是 **store 契約**（與 §3.4 canonical form、§3.1
`authorized` 同級——手改 YAML 的人讀的是本檔不是 `.claude/rules`，而手改正是它指定的修法）。
**它與 `openspec/specs/venue-entity` 的關係**（R6 verify 第 3 列指出 R6 說「記在 parity 列」
而沒記）：spec 已有兩條 validate-time Requirement（authorized／variant 互斥、variant 不帶時間），
本節的五條與它們同形，**應該**成為 spec 的 Requirement——那要走 spectra-propose，#554 不做
（#554 的裁決是「既有 tool 的新參數，不走 Spectra」，D8 把它擴成 store 不變式時沒有重開那個
裁決）。在 spec 補齊之前，本節是唯一的規範來源；follow-up 見 #570。五條，封閉（第 5 條是 R11 加的求值上限，R11 verify 第 13 列指出它先前只住在上面那個括號裡）：

1. **canonical 形**：NFC；無前後空白；內部任何 `White_Space` scalar 串（含 tab、換行、
   NBSP、NNBSP、U+3000）收斂為單一 U+0020。**正規化只丟空白、不刪任何其他 scalar**（空白後的
   combining mark 留著）。
2. **不含危險或不可見 scalar**：Cc／Cf／Zl／Zp、輸出閘 `UnsafeToEmitScalar` 的成員、Unicode 的
   `Default_Ignorable_Code_Point`（零寬、變體選擇子如 U+FE0F、CGJ U+034F、Hangul filler U+3164、
   TAG 字元），以及 U+2800 BRAILLE PATTERN BLANK（三者都沒收、卻渲染成一格空白）。**例外只有
   ZWJ／ZWNJ**，且只在兩個脈絡：(a) 前一個 scalar 是 virama（ccc 9），從 virama 往前跳過標記找到的基底是
   **字母**（數字或標記當基底不算；含 legacy Malayalam chillu 的詞尾 ZWJ），**virama 與跳過的每個標記都是基底
   那個文字的**（R9，D22：`ک\u{094D}\u{200D}`、Bengali virama 掛在 Devanagari 基底上都不算），右鄰居若在要是
   同一文字的字母／數字——**右鄰居是空白視同沒有**（多字刊名裡的詞尾 chillu `അവന്\u{200D} വന്നു`；canonical 形保證
   內部空白只會是單一 U+0020）；(b) 左鄰居是使用 join control 的文字裡的**字母／標記／數字**、右鄰居是**同一文字**的
   **字母／數字**，**或 Devanagari／Bengali 的 virama 且 virama 之後接同文字的字母**——joiner 在 halant 之前是印度系文字
   的正字法（R9，D21：Unicode 核心規範 ch. 12.2 的 Bengali ya-phalaa `<RA, ZWJ, VIRAMA, YA>`；Microsoft 的 Devanagari／
   Bengali OpenType 音節文法 `{C+[N]+<H+[<ZWNJ|ZWJ>]|<ZWNJ|ZWJ>+H>}`，2026-09-13 實取確認；R8 曾把它當「沒有正字法意義」
   拒掉）。**每個引用實例都是 `<C, J, H, C>`**——halant 後面的輔音才是 joiner 有作用的原因，沒有它 `क\u{200D}\u{094D}`
   與 `क्` 渲染完全相同，能各自進 names 再被 `--authorize` 升成 displayName；R9 對 0900–0DFF 十個文字一起放行且不看右脈絡
   （R9 verify DA 第 10 列真 binary 實測 `क‍्`／`क‌्Journal`／Tamil 全過），R10 收到有引用的兩個文字＋後續字母（D26），其餘
   Indic 文字依 `zero-instance-guards` 一列一列加；
   右側其他標記仍不收（joiner 夾在基底與它的母音記號之間沒有正字法意義），非 Indic 的 virama（Myanmar asat、
   Khmer coeng）之前的 joiner 沒有文法支撐，仍拒（Arabic 一族含 Extended-C、Syriac 含 Supplement、Mandaic、NKo、
   Indic 0900–0DFF 含 Devanagari Extended／Extended-A、Myanmar 含 Extended-A／B、Khmer、Mongolian、Tifinagh、
   Hanifi Rohingya、Sogdian／Old Uyghur、Manichaean、Adlam）——同區塊的**標點**不算鄰居（`A\u{200C}،B` 的 ZWNJ
   沒有接合用途），鄰居是另一個 joiner 也不算（連續 joiner 沒有正字法意義）。拉丁、西里爾、CJK 之間的 joiner 不合法。
3. **至少一個字母或數字**——generalCategory 的 L 類或 N 類（純數字刊名 *1843* 合法、tatweel 是 Lm 合法；
   `×`／`—` 不是名字，一個孤立的變音符號也不是——它是 Mn，雖然 Unicode 的 `Alphabetic` 收它）。
4. **每張清單內無 canonical-相等對**。`names` 有一個例外：**同名的沿革段**——兩筆都帶
   `start`／`end`／`ended-unknown`／`attested` 任一，**且**一段有 `end`、另一段有 `start`，兩者都是
   ISO 8601 前綴（`YYYY`／`YYYY-MM`／`YYYY-MM-DD`；`2003-1`、`民國49` 這類手改值不算——venue 的日期 decode
   不驗、`doctor` 也不掃，所以放行條件自己要驗），前段的 `end` 以兩者中較粗的粒度截斷後**嚴格**早於後段的
   `start`（Sankhyā 1933–1960 與 2002–2007）。
   以較粗粒度截斷後相等——端點相等（`end: 1960`／`start: 1960`）、粒度混用而同年（`end: 1960`／
   `start: 1960-06`；`end: 1960-06`／`start: 1960-07` 兩者都到月，截斷後 06 < 07，**是**不相交）——都算重疊；只有 `attested` 或 `ended-unknown` 的段沒有可比的端點，永遠進不了豁免。任一筆
   無時間宣稱，仍是違反。這個「不相交」刻意比 `DateRange.overlaps` 保守——那個函式是給提醒用的
   （多報安全），這裡是放行條件。**兩段本身都要是有效區間**（R12，R11 verify Codex 第 3 列）：在場的每個
   端點都是 ISO 前綴、且 `start` 以較粗粒度截斷後不晚於 `end`——`{start: 2000, end: 1900}` 對 `{1950–1960}`
   曾以 `"1900" < "1950"` 解鎖豁免；證明不了區間有效就不授予豁免。
5. **同名段的求值上限**（R11；`Venue.validate()` 在讀取路徑——`StoreHealth` → doctor／App——也跑）：一組 canonical
   相等的 `names` 段最多逐對評估 5,000 對（≈100 筆），超過即 error，**不論每一對是否都命中第 4 條的豁免**
   （fail-closed：`add_names` 不帶時間欄位造不出全豁免組，手改或匯入才造得出，而一本刊改回同名一百次不是真的
   沿革）。訊息以「同名段過多」開頭，與第 4 條的「近重複」在 grep 層面分得開；一組內逐一列出的違反對至多 3 對，
   其餘以「另至多 M 對未評估」概括（M 是未評估的對數）。

**修法是人改 YAML**（不猜、不靜默修）：訊息逐條說改什麼——改成 canonical 寫法、刪掉那個
字元、刪掉那一筆、或把沿革段補上不相交的時間。工具不提供 `--repair`。同一句訊息也出現在
寫入面（`add-venue`／`update-venue`）與合併 dry-run 的拒絕裡——那時「請刪掉它」指的是呼叫端
的輸入、「被併的 X 的 names…」指的是被併記錄的 YAML。

**誠實邊界（fail-closed，不是靜默損失）**：第 2 條的「DI 一律不可見」擋掉幾類真實正字法用字
——CJK 表意文字變體序列（IVS，U+E0100–E01EF）、蒙古文 FVS／MVS（U+180B–180F）、希伯來文的
CGJ、emoji 的 ZWJ 序列、德文用來抑制複合詞連字的 ZWNJ（`Auf\u{200C}lage`）——它們被拒時訊息具名、零寫入；
書目資料裡機率極低，這是 Claude 代裁 D9 的取捨，使用者可翻。第 1 條把蒙古文後綴用的 NNBSP
（U+202F，White_Space）折成一般空格，渲染上後綴會斷開。第 1 條的 NFC 對 CJK 相容表意文字有損
（U+FA10 塚 → U+585A；Swift `==` 早視為相等）。放行但不像名字的：純 tatweel（U+0640，Lm）、
開頭或空白後的 combining mark、未指派碼位（Cn；落在 DI 區段內的保留碼位除外——那些會被擋）。私用區（Co）不擋。
第 2 條的區塊表**不含 Vedic Extensions（U+1CD0–1CFF）**：它們的 `joinScript` 是 nil——(a) 支的同文字檢查（D22）與 (b) 支的
鄰居檢查都會拒鄰接它們的 joiner（實測 `क्᳐‍ष` 被拒），少數 Lo 字母（U+1CE9–1CEC 等）沒有 joiner 用途（R9 記為邊界，
R8 verify 第 21／28／38 列；理由句 R10 依 R9 verify 第 24 列改寫——R9 那句「走訪時本來就跳過」描述的是 D22 之前的行為）。以上全部零實例。

**部署視窗（R5 verify 第 16 列）**：這條不變式沒有 format bump，refuse-if-newer 管不到。
三個 binary（CLI／`akashic-mcp`／App）**全部**升到 #554 世代之前，舊 binary 仍可寫入
`"X "` 這類字串——它在舊 binary 合法、在新 binary 之後對**那筆 venue 的所有寫入**拒絕
（含 `add_names`、`paginated`、verdict 寫回），且沒有面能修（只能手改）。所以升級順序是
「三 binary 全升 → 跑 `akashic validate` 確認名字內容 error 為 0 → 才視為生效」；視窗
期間發現的違反照上一段修。2026-09-12 實測 live store 485 筆 venue 違反 0。

**序列化註記**：純數字刊名（`1843`）由本 repo 的 YAML 寫出時不加引號，Swift 讀回是字串
（本檔 §3.4 的 canonical form 只對 Swift 側承諾）；外部 YAML 解析器（PyYAML）會讀成整數
——`010` 讀成 8。用外部工具量本節的不變式時要對 `names` 做 `str()`，第 25 列的 Python
對照腳本（`.claude/rules/zero-instance-guards.md`）就是這樣寫的。

### 5.8 `divergence`：未決的同一性問題（normative，#71）

store 已有「寧可分割，絕不合併」——同一個人的兩種寫法會建成兩筆記錄，因為錯誤合併
不可逆而錯誤分割可逆。但分割之後兩筆各自失憶：沒有地方記「這兩筆可能是同一個」。
`divergence` 補的就是那個位置。

```yaml
divergence:
id: 6577DE3B-DAFE-5CC0-A9DE-2E04030737B3
question: 是否為同一人
candidates:
- key: fann-cathy-s-j
  shape: person
- key: fann-cathy-s-j-2
  shape: person
judgement: 兩者的姓與 given initials 一致，差異僅在連字號與句點的排版慣例
rests-on:
- sha256:9a23d701e4fe4888…
```

**normative 規則：**

1. `candidates` **MUST** 至少兩筆、**MUST** 全部同 `shape`、且 **MUST NOT** 有重複的
   `(shape, key)`。跨形狀不是未決的問題而是類別錯誤；重複的候選沒有東西可以與之相同。
2. 每個候選的 `shape` **MUST** 明寫，**MUST NOT** 由 `key` 推導——鍵在不同形狀之間可以
   同名（見 §organization 的 key 契約），而 decode 沒有 store 存取。`shape: divergence`
   **MUST** 拒收：歧異記錄沒有 key（身分是 UUID），不是可被指涉的對象。
3. `judgement` 與 `rests-on` **MUST** 成對出現。`prefers`（選填）指名判斷傾向的
   候選，**MUST** 與 `judgement` 成對、**MUST** 是本記錄的候選之一。形狀與判斷型 provenance reference 相同，
   但 **MUST NOT** 含 `field:`——判斷關乎哪個候選才對，不是宿主記錄的哪個欄位。
   兩者的**空值**同樣 **MUST** 拒收（空 `question` 亦然）：空的斷言不是判斷，空的摘要
   不是依據，而空的問題不是未決的問題。
4. 記錄 **MUST NOT** 帶「已解決」狀態。消歧完成時整筆刪除，歷史託給版本控制而非 store。
5. `divergence` **MUST** 只存在於 format ≥ 5 的 store（版本歸屬見 §5 版本對照表，
   #74 回填；寫入 gate 對 format < 5 拒寫＋指路）。佈局前提（`entities/`）由版本
   歸屬蘊含——format ≥ 5 必然 ≥ 2。legacy 下 person 落在
   `people/<key>.yaml` 而刪除只認 `entities/<uuid>.yaml`——寫得進去、刪不掉。

6. 候選鍵 **MUST** 在寫入時通過 `StoreKey` 驗證，與其他每一條寫入路徑一致。理由不是
   path traversal（候選鍵不進任何路徑），而是 `validate` 對畸形候選鍵報 error——沒有
   這道守衛，工具就能寫出一筆自己的 validate 永遠不會通過、又沒有編輯入口可修的記錄。

**判斷與消歧的關係**（#75 對一）：消歧 **MUST NOT** 對已寫下的判斷惰性——`prefers`
與 `--survivor` 不一致時 **MUST** 拒絕。但**也 MUST NOT 代選**：不照 `prefers` 自動
執行——判斷可由 LLM 經 MCP 寫入（#133），自動採信等於把「當場判斷」換成「延遲自動
判斷」，繞過 #71 的人工確認底線。倖存者永遠是消歧當下的人工輸入。判斷本身可能錯：
`--override-reason <理由>` 是知情的覆寫通道，**空理由不接受**（判斷的變更也是判斷）。
有 `judgement` 但無 `prefers` 時無從機械核對——**報 warning、不擋**。preview（`--dry-run`）
與實跑 **MUST** 對同一組參數擲同樣的錯、給同樣的 warning：dry-run 的價值是誠實預告，
而它是使用者在不可逆刪除前唯一還能反悔的時點。

**這道一致性檢查是 binary 級、不是 store 級的保證**（#159 verify 159-8）。`prefers` 落在
divergence 記錄的**頂層**（與 `judgement`／`rests-on` 平行，不是巢狀在 judgement 裡），
因此在 tolerant-preserve 的涵蓋範圍內——**不需要 bump format**，跨版 round-trip 無損
（實測：舊 binary 讀到只報「未知欄位『prefers』（已保留）」、`fmt` 整檔改寫後該欄位仍在、
新 binary 重讀護欄照常 fire）。代價是**舊 binary 會靜默無視這道護欄照樣消歧**（實測
`exit=0`，一個字都不說）。這是「選填護欄 + tolerant-preserve」的必然：要讓舊 binary 也
擋，唯一手段是 bump format，那會讓它們對整庫拒絕開啟（含唯讀）——代價不對稱，不做。

**不可逆消歧 MUST NOT 在帶有本 binary 不理解欄位的記錄上執行**（#159 verify §6／
159-12／159-13）。適用範圍是**封閉列舉**——`resolve-divergence` 本次會刪除或改寫的
divergence 記錄，**只有這三類，不得依性質相似類推第四類**：

| # | 類別 | 這個操作對它做什麼 |
|---|---|---|
| 1 | **目標**（使用者以 `<id>` 指名的那筆） | 刪除 |
| 2 | **塌縮連帶刪除**（`migrateOtherDivergences` 的 `collapsed`） | 刪除 |
| 3 | **候選遷移改寫**（同函式的 `toWrite`） | read-modify-write |

三類的完整性由 `migrateOtherDivergences` 的回傳值界定，不由性質推導。任一筆的
`unknownFields` 非空即拒絕（preview 與實跑同擋，檢查住共用驗證段），訊息指路
「升級 binary，或確認該欄位可忽略後手動移除」。

**本列舉只涵蓋 divergence 記錄，不涵蓋被併的實體**（#159 verify R3 Q1(b)）。被併
實體（person／work 記錄本身）也在這個操作裡被刪除，它們的未知欄位由**另一道守衛**
負責——`fieldsLostByMerging`：

| 被刪的東西 | 守它的是誰 |
|---|---|
| divergence 記錄（三類，上表） | 本節的 unknown-field gate |
| 被併的 **person** | `fieldsLostByMerging(_ p: Person, into:)`——三分比對，含「兩邊都有同名未知欄位但值不同」 |
| 被併的 **work** | `fieldsLostByMerging(_ e: Entry, into:)`（#75 對二）——**同一組守衛的另一半** |

**這兩道守衛的來源不同、目的也不同**：unknown-field gate 是「本 binary 讀不懂就不
執行不可逆操作」，`fieldsLostByMerging` 是「被併者帶有倖存者沒有的內容就不自動合併」。
它們**碰巧**都涵蓋未知欄位，但那是巧合不是設計。

**而且巧合是不完整的**（#159 verify R4-2）：`fieldsLostByMerging` 對未知欄位是**三分**
判定——倖存者沒有 → 報、值不同 → 報、**兩邊同名同值 → 不報**。最後那一格對它自己的
目的完全正確（合併不會失去任何東西），但對 gate 的目的是漏的。席位實測的邊界案例：

```
兩個記錄都帶 `future-veto: do-not-merge`（validate 兩邊都印過「未知欄位（已保留）」）
→ fieldsLostByMerging 判定「不會失去」→ 放行 → exit=0，被併者連同該欄位一起刪除
```

那個欄位**字面叫 `do-not-merge`**——正是 gate 的錯誤訊息裡寫的「那些欄位可能正是
一道本版讀不到的限制」。關鍵區分：`fieldsLostByMerging` 問的是「會不會**失去內容**」，
gate 問的是「我**讀不讀得懂**」。未知欄位若是**限制**而非**內容**，前者結構上表達不了。

所以本表第 2、3 列涵蓋的是未知欄位的**資料遺失子集**，不是全集；divergence 側的
gate 沒有這個洞（任何未知欄位一律擋，不看值）。把 gate 也套到被併實體是**行為變更**
（會改變今天通過的合併），屬另案。

實測紀錄：work 側的 `fieldsLostByMerging` 是 #75 對二補上的；在它落地**之前**，
work 的被併 entry 帶未知欄位時消歧照跑（席位實測 `exit=0`，`validate` 事前才印過
「未知欄位（已保留）」）。person 側被守住是因為那道為別的目的寫的守衛剛好涵蓋。

**為什麼寫成列舉而非「所有受影響的記錄」**：第一版寫的正是那句總括判準，而實作
只檢查目標那一筆——席位實測另外兩類都放行，其中第 3 類更產出**自相矛盾**的檔案
（候選被改寫成新鍵，未知欄位仍指著全庫已無的舊鍵；tolerant-preserve 保證位元組
不變，但候選被改寫時「不變」剛好就是錯的）。總括判準的字面涵蓋範圍大於實作，
差距就在邊界上安靜地答出沒人同意的答案——這是 `common-spec-prose-enumeration`
記載的失敗模式，逐字對應。

這是「跨版本安全」的**正解**，取代「每加一個安全欄位就 bump format」：它版本無關
（是本 binary 對自己無知的紀律，不需 store 級協商）、一次涵蓋所有未來欄位、且代價
侷限在該筆記錄而非整庫拒開。與上游「quarantined 檔讀不到就改寫不到」的 gate 是同一
條理由的另一面——**讀不懂**與**讀不到**在不可逆操作前應該同樣保守。誠實邊界：它救不
了已編譯出去的舊 binary（它們不覺得自己讀不懂 `prefers`），那個缺口見上一段。

**重錄 MUST NOT 靜默抹掉 `prefers`**（#159 verify 159-4）：既有記錄已指定 `prefers` 時，
帶新 `judgement` 而省略 `prefers` 的重呼叫 **MUST** 拒絕。與 `judgement` 自己那道守衛
（#133 F1）對稱——`prefers` 是本機制唯一能機械執法的東西，抹掉它就退回「只警告不擋」，
而「更新判斷時忘了帶 prefers」在 LLM 經 MCP 寫入的前提下是很順的一條路徑。沿用請再帶
一次同值、改傾向請帶新值、撤銷請直接編輯該檔。

**消歧**：`akashic resolve-divergence <id> --survivor <key>`。它是**一個操作**：合併別名
→ 全庫參照重寫 → 刪除被併記錄與歧異記錄。

動磁碟前的六道前提，**任何一道不過就完全不動**：

| 前提 | 為什麼 |
|---|---|
| store 位於版控工作樹內 | 歷史託給版控，版控之外刪掉就是真的沒了 |
| **本次要刪的每個檔案都是 tracked 且無未提交修改**（#73）| 「在工作樹內」與「刪掉還找得回來」是兩件事。上一列只驗前者，於是三種情況照樣通過而歷史真的消失：<br>① `entities/` 被 `.gitignore` 擋——被 ignore 的檔案在 `git status --porcelain` 裡連 `??` 都不會出現；<br>② **歧異記錄建立後尚未 commit 就被消歧**（最常見）——`question` / `judgement` / `rests-on` 三者一起永久消失，`#71` 要解決的「判斷留不下來」原封不動地回來；<br>③ 被併實體有未提交的修改——git 裡是舊版本，當下這版不可回復。<br>**只驗本次要刪的那些檔案**，不驗整棵樹：store 其他地方髒不影響這次刪除的可回溯性。**git 不可用時一律當成不安全**（fail-closed）——不可逆刪除的預設應該是拒絕。**不存在的檔案跳過**：它不可能被不可回復地刪除，而那正是下一列要診斷的情況，搶先報「未被 git 追蹤」會指錯方向 |
| `entities/` 佈局（format ≥ 4） | legacy 下寫得進去、刪不掉 |
| 無跨記錄不一致 | 雙佈局並存時會刪錯檔 |
| **`entities/` 與 `entries/` 無 quarantined 檔** | 讀不到的檔可能正指著要被刪掉的實體，而讀不到就改寫不到——刪除後會留下藏在工具看不見處的永久懸空參照。**只擋這兩個目錄**：`people/` 與 `libraries/` 的記錄結構上不可能持有那種參照（person 不引用 person，library 只有 metadata），把它們一起擋，理由對它們就是假的，而且擋在最需要消歧的 store 狀態上 |
| **每個候選的記錄真的在 `entities/<uuid>.yaml`** | 讀取端同時讀 `entities/` 與 legacy 目錄，所以住在 `people/<key>.yaml` 的記錄照樣載入得了；而刪除只組 `entities/<uuid>.yaml`。少了這道，刪除階段的「檔案不存在就跳過」會把**刪不掉**當成**已刪掉**——參照全改、被併檔原封不動、歧異記錄被刪、零警告、退出碼 0。有了它，「檔案不在」就只可能是「已經刪過」，冪等才成立 |

參照的範圍包含**其他歧異記錄的候選**（那也是參照）。候選 **MUST** 同時比對 key 與
shape 才遷移——鍵在不同形狀之間可以同名。遷移後候選少於兩個的記錄 **MUST** 一併刪除
並回報：那種記錄寫回去會被自己的 decoder 拒收。

`akashic rename` 同樣 **MUST** 遷移歧異記錄的 work 候選；改名會讓候選塌縮時 **MUST**
拒絕——rename 沒有合併語意。

**遷移後的 id MUST 重算**（#168）。id 由候選鍵的集合推出，所以改寫候選卻保留舊 id 會讓
記錄與它的候選集脫鉤，而「同一組候選＝同一筆記錄」正是 `judgement` 三道守衛
（`contradictsJudgement`、無判斷的重呼叫不得抹掉判斷、重錄不得抹掉 `prefers`）的**共同
前提**——脫鉤之後，同一組候選有兩筆記錄，三道守衛全部去問了沒有判斷的那筆。實測：
`record → resolve → 再 record → resolve` 這串**全部是正常操作**的序列，會讓帶判斷與
`prefers` 的記錄被連帶刪除、判斷指名為正確的實體被合併掉，而 dry-run 與實跑**只警告不擋**
（#159 之後會印一則連帶刪除的判斷警告），然後照樣 exit 0 完成不可逆刪除。

重算 = 改名 = 刪舊建新，舊檔 **MUST** 與塌縮記錄同批處理（同一套可刪性前移檢查與失敗
收容）。重算後撞上另一筆記錄時（撞既有記錄、或兩筆遷移記錄互撞），**只有零損失才
MUST 靜默合併**（`candidates`、`question`、`judgement`、未知欄位**皆**相同）。
`candidates` 必須在內：`forDivergence` 只雜湊候選的 **key**、不含 shape，而 key
跨形狀同名是允許的——少了這一項，一筆 person 歧異會撞上候選 key 相同但 shape
不同的既有記錄並被整筆丟掉（#168 verify 實測）；否則 **MUST 拒絕整個消歧**
並指名將被犧牲的判斷。自動挑一邊活下來，正是這條規則要防的靜默毀損。

**失敗語意**：參照重寫的單筆失敗**收容並繼續**，結束時報告清單並以非零碼退出；參照
重寫**有任何失敗就不進入刪除**——歧異記錄是唯一能重跑的依據，先刪它再讓被併檔留著，
比撕裂更糟。刪除階段自身的可預期失敗 **MUST** **前移**：動手前檢查每個要刪的檔案
可刪（父目錄可寫、無 immutable flag），任何一個不可刪就**一個都不刪**（與「候選檔案
必須在 `entities/`」的前置是同一個做法）。前移檢查後仍發生的刪除失敗（TOCTOU、真正的
I/O 錯誤）收容並回報——此時被併記錄**可能部分已刪**，但歧異記錄 **MUST** 保留，修復
後重跑同一個 id 冪等收尾。報告 **MUST** 在索引重建之前印出：索引過期可重建，報告遺失
不可回復。

**塌縮的可見性**：候選塌縮的連帶刪除動的是**使用者沒有指名**的記錄，回報 **MUST**
攜帶該記錄的 `question`，不得只有 UUID——裸 UUID 讓使用者無從知道被刪掉的是哪個
問題。消歧 **MUST** 提供 dry-run（`--dry-run`）：跑同樣的拒絕條件、預告合併／改寫／
塌縮刪除，不動任何檔案。

**合併的範圍**：只搬別名。被併記錄帶有倖存者沒有的內容時，合併 **MUST** 拒絕並指名將
失去什麼。**work 消歧同此**（#75 對二）。

比對面是**封閉列舉**——`Entry` 的 11 個儲存屬性分成**三組**（7／2／2），
**不得依性質相似類推第四組**：

> **這句先前寫「兩組……第三類」，是事實錯誤**（#169 verify F8）。表格只有兩欄、
> 散文寫「比對 7 + 排除 4」，而 `fieldsLostByMerging` 自己的 doc 用第三套帳
> （7／2／2）——同一份規格三套數法。正確的是 code doc 那套：`type`／`title`
> **有比**（缺席方向會拒絕），把它們併進「排除」是錯的。
>
> 值得記在原地：`common-spec-prose-enumeration` 那條規則要保護的就是封閉列舉的
> 宣告，而**寫錯的封閉列舉比沒有更糟**——它讓讀者確信自己知道有幾類。

| 比對（doomed 有而 keeper 沒有／衝突 → 拒絕） | 部分比對（只比缺席方向） | 排除（身分） |
|---|---|---|
| `fields`（逐 key；同 key 不同值＝衝突）、`attachments`、`akashic`（tags／libraries／status／**出向 relations**／author-list-completeness／unknownFields——cites/related 的遷移只搬「別人指向被併者」的參照，被併者自己指出去的隨檔案消失；canonical witness 的專屬規則見 §2.5.1）、`authors`（`.key` 是 resolve-people 歸戶的產物，work 合併不搬）、`date`、`unknownFields`、`provenance`（`zoteroKey`／`libraryID` 的**對**、`orphanedAt`）——共 **7** | `type`／`title`——共 **2**。keeper 為空、被併者非空 → 拒絕（`""` 不是任何人選的 form，它是缺席）。兩邊都非空時**不擋**：要求相等會誤拒最常見形狀，keeper 的寫法**就是人選的 canonical form**。<br><br>**兩者不對稱**：只有 `title` 額外發不擋的提醒（#169）——被併者以 `title` 為前綴（case-fold）、且多出來的部分**含詞字元**時進 `warnings`。少了詞字元條件，真 corpus 上 5 次觸發**全部**是 APA 句末句點、真實遺失 0 筆。**`type` 不發**：它是封閉 token 集合，字串包含與完整度零相關（13 對標準 biblatex type 滿足包含，`book ⊂ inbook` 不是「較長版本」）。 | `id`／`citekey`——共 **2**。身分，不隨合併移動 |

子集才放行——搬欄位是人的判斷，不自動合併。7 + 2 + 2 ＝ `Entry` 的 11 個儲存
屬性（`akashic` 的六個子欄位**收合成一個屬性算**），由
`testEntryFieldCoverageOfMergeCheck` 以反射釘住；巢狀型別（`AkashicMeta`／`Relations`／
`Provenance`）另有各自的計數斷言——`AkashicMeta` 現有 tags／libraries／status／
relations／author-list-completeness／unknownFields 六個儲存子欄位；歷史上 schema 演化
正是發生在 `akashic` 那層，
只釘頂層對最會 rot 的地方失明（#157 verify 157-9）。

兩個判準值得單獨寫明（#157 verify 157-6／157-7／157-8——第一版兩者都做錯，且真
binary 實測都會靜默丟資料）：

- **`date` 比的是「前綴相容」，不是「在場與否」也不是「相等」。** `2020` 與
  `2020-03-15` 相容（同一件事的不同精度，是重複記錄的**正常形狀**，要求相等會誤拒）；
  `2019` 與 `2021` 不相容（那是對「這兩筆是不是同一篇」的反證，或至少是必須有人裁決
  的來源衝突——同 person 側 `died` 的理由）。前綴 **MUST** 落在 `-` 分隔點上：`202`
  不是 `2020` 的低精度版。非 ISO 前綴格式一律當**不相容**。**空字串視同缺席**
  （與 store 其他地方的慣例一致——同一個概念不該有兩套判準）。
- **未知欄位是三分不是二分**：key 缺席＝遺失、raw 相同＝不遺失、**raw 不同＝衝突**。
  只比 key 在不在會讓「兩邊都有同名欄位但內容不同」整條漏掉，而 `validate` 明明對
  兩邊都印過「未知欄位（已保留）」——系統已經知道兩邊都有，合併閘不該不看值。

判定 **MUST** 是**子集**而非相等：被併者的每個欄位要嘛為空、要嘛與倖存者相同，才算
「不會失去」。相等只放行「全空」與「完全相同」，會誤拒最常見的形狀——使用者把資料
較完整的那筆選為倖存者是消歧的常態。時間軸維度（隸屬、職級、行政職、聘任、領域、
聯絡資訊）**MUST** 逐維度比對子集，不得整份相等。

未知欄位 **MUST** 三分：key 不在倖存者身上 → 會失去；key 在且原文相同 → 不會失去；
key 在但原文不同 → 那是**衝突**，訊息 **MUST** 據此措辭（說成「倖存者沒有」對這一格
是假的）。

**逐欄是必要的**（子集關係無法用整體相等表達），所以防腐 **MUST** 另尋機械手段——
本實作用反射數型別的儲存屬性，與檢查涵蓋的數量不符即測試失敗。「換成結構比較」不是
這個問題的解答：它換掉的是語意，不是防腐方式。

**消歧不是清理工具**：沒有指名被併鍵的記錄 **MUST NOT** 被改動，即使它自己有既存的
重複參照。

**已知缺口**（皆有 issue）：沒有建立入口（#77）；封閉集合擴充的相容性未決（#74）；
消歧不看已寫下的判斷、work 合併不搬欄位（#75）；MCP 面無投影（#76，進行中）。
（#73「版控檢查只到『往上找得到 `.git`』」已修——見上方前提表格的 tracked+clean 列。）

### 5.9 v1.4 規劃：known 層的演化語意（#26 裁決，尚未實作）

v1.3 的 tolerant-preserve 只涵蓋**未知 key**。known 層的三個 strict 區塊在演化時整檔
quarantine——而其中兩個正是「最可能的下一次演化位置」。實測（2026-08-02）確認行為：

| 構造 | v1.3 行為 |
|---|---|
| `attachments: [{futurekind: files/x.pdf}]` | **整檔 quarantine** |
| `provenance: {…, future_field: v}` | **整檔 quarantine** |
| `akashic.relations: {futurekind: [...]}` | **整檔 quarantine** |
| `akashic: {futureNested: v}`（對照，tolerant 層） | warning，正常載入並保留 |

**裁決：三者全部升格 tolerant（逐字保留 + 明示「本 binary 不理解」），v1.4 實作。**

理由是**代價不對稱**。這三處的共同形態是「一個小結構的未知細節，讓整筆書目資料消失」：

- **新 relation kind**（`extends` / `refutes`…）——R1 DA 指出這是最可能的 additive 演化。
  容忍後最壞是圖上少一條邊；quarantine 是整筆記錄不見。**少一條邊 << 少一整筆**。
- **新 attachment kind**（`web` / `local`…）——附件解析不了，但書目資料完好。strict 當初
  的理由是「path traversal 是安全面」，但那由 **path 的驗證**負責，與 **kind 是否認得**
  無關；用 kind 的未知去否決整筆記錄是錯置的防線。
- **provenance 新欄位**——那是 Zotero 同步的簿記，與記錄的意義無關。

**這不需要 bump store format（#24）**：改的是**本 binary 變得更容忍**，舊 binary 的行為
不變（它們照樣 quarantine，跟現在一樣）。純粹擴大容忍不是 non-additive 變更。

**實作時的 normative 要求**（寫在這裡避免日後走樣）：

1. 未知的 kind / 欄位 **MUST** 逐字保留並在 re-encode 時原樣寫回——與 v1.3 開放層同一個
   raw-text 載體，不得 serialize。
2. **MUST** 在讀取面明示（`unknownFields` 同族的訊號），否則使用者會以為圖上就是沒有那條邊。
3. **MUST NOT** 讓未知 kind 影響已知 kind 的解析——例如未知 relation kind 不得使
   `cites` / `related` 的解析改變。
4. `attachments` 的 **path 驗證維持 strict**——容忍的是 kind，不是路徑。

**已解決（#26 的第 1 項，issue body 已過時）**：「known-field shape 不符靜默剝除」在 #23
的輪次中已改為 **fail-loud**。實測 `names: "字串"`（應為 sequence）→ quarantine，訊息
明確指出形狀不符。原本擔心的「decode 略過 → re-encode 從磁碟抹除」的靜默資料遺失**不再存在**。

**保持 strict 的部分（不改）**：`authors` 元素的 shape（`key` / `literal` 二選一）與
`attachments` 的 path 驗證。這兩處的未知不是「不理解」而是「無法安全處理」——前者決定
記錄的作者是誰、後者是 path traversal 面。

- **merge / value 面以 tag 判定，不以鍵名字串判定（R11，R10-verify HIGH）**：
  YAML 的 merge 語意由 tag（`tag:yaml.org,2002:merge`）決定——Yams 自己的
  `Node.Mapping.flatten()` 就是比 tag。R10 以前開放演化層用 `k == "<<"` 字串
  比對，兩個方向都錯：**漏擋** `!!merge foo:`（字串面是 `foo`，字串測試看
  不到）→ 被當普通未知欄位收下並原樣寫回，merge-aware loader 讀同一份檔案
  會展開成**另一份記錄**（實測可注入 `orcid` 這類 known 欄位）；**過擋**
  quoted `'<<'`（依 YAML 是普通字串、tag 為 str）。改判 `key.tag ∈ {merge,
  value}` 後兩個方向同時修正——`!!merge`／`!!value` 加在任何鍵名上都拒收，
  quoted `'<<'`／`'='` 在開放演化層照常當普通未知欄位保留（`fields` 層另有
  字串面條款，見下）。
- **tagged-shadow 鍵不入範圍（R6；R7 擴至所有層）**：字串與 schema 欄位同名、
  tag 非 str 的鍵（如 `!foo note:`、provenance 的 `!foo zotero_hash:`）→
  decode 錯誤 → quarantine——這種鍵 str-tag subscript 讀不到、又被字串比對
  歸為已知而不進保留，optional 欄位會被靜默歸零、寫回即剝除（required 欄位
  本就 fail-closed）。適用開放演化層與 closed shape 層。**unknown** 鍵不受
  此限：tag 區分的同字串鍵、自訂 tag 鍵都走文件序 index 對齊，型別在 raw 內
  逐字保真。前提（明文化）：Yams 的重複鍵偵測比的是 string+tag 全等——同
  字串異 tag 不是 duplicate；`fields` 以字串面當 dictionary key，字串面撞名
  → decode 錯誤（R7，否則靜默壓成一筆）。mapping 型 complex key（`=`/!!value
  鍵）經 construct 特例會呈現字串面：known 欄位一律以真 scalar 驗形
  （`scalar` 檢查，R7）、known-同名由 tag 條款擋；sequence 型 complex key
  直接 throw。**`fields` 的鍵與 `attachments` 元素鍵同受此律（R8，R9 修正）**——
  兩處此前走 `Node.string` 的 construct 特例（tagged 鍵靜默丟 tag、`=`-鍵
  mapping 扁平化）。R10 規則：鍵必須是真 scalar 且 resolved tag 屬**隱式
  resolver 可產出的閉集**（str/int/float/bool/null/timestamp）、以字串面解讀
  ——emitter 對 fields 鍵輸出 plain 樣式，`2026`/`no` 這類鍵 re-parse resolve
  成 int/bool，str-tag 檢查會讓自家產物寫得出、讀不回（R8-verify HIGH）。
  閉集之外一律拒收：顯式 local tag（`!foo journal:`）、**merge 面 `<<`**
  （各層一致拒收——我們若 emit，他家 loader 會展開或報錯）、value 面 `=`
  （R9 的 namespace 前綴判準誤放行兩者，R9-verify M4/M8）。**R11 補字串面**
  （R10-verify HIGH）：tag 閉集只擋 tag 面，quoted `'<<'` / `'='` 的 resolved
  tag 是 str、會通過閉集被 decode 收下，但 encode 時 `Node("<<")` implicit
  resolve 成 merge → emit 成裸指示符 → 內層 canary decode 撞閉集 → **永遠
  throw**。淨結果是本節自己命名的最壞形態「讀得到但永遠寫不回」，且**零
  可見性**（不進 quarantine、無未知欄位故不進 `unknownFieldFiles`、
  `validate()` 也不發 warning）。decode 端因此對字串面 `<<` / `=` 一併
  fail-closed——載入即 quarantine，可見、可救。已知邊界（記載）：
  顯式 core tag（`!!int 123:`）與 plain `123:` 在 resolved-tag 層不可區分，
  接受並正規化為 plain。attachments 元素鍵維持 str-tag 檢查——鍵域固定為
  `zotero` 這個純字母字串、恆 resolve 為 str，無等冪問題（三層鍵規則
  不同是刻意的：各層鍵域不同）。字串面撞名仍 fail-closed。
- **有損字元守衛（R8 拆成兩層、全部 decode 入口無條件執行）**：
  (i) **毀字通道——NEL (U+0085) 一律拒收**（所有 decode 入口，含純 known 檔
  ——R7 的守衛只長在切分路徑，R8 關上半開門；R9 依 R8-verify 更正把裸 CR 移出
  此層）。NEL 的特殊性：不是任何行尾慣例、emitter 一律 escape（自家產物零
  誤殺）、且是 cp1252 `…` 誤轉 UTF-8 的常見**內容**字元——被 libyaml 當
  line break 摺疊即為毀字。(ii) **CR 以「檔內有無 LF」裁決（R10 判別式，
  R9-verify HIGH）**：全檔無 LF ⇒ CR 是 classic-Mac 行尾，由 libyaml 正規化、
  無損載入（v1.2 相容）；檔內有 LF ⇒ 行尾已由 LF/CRLF 承擔，**不接 LF 的
  裸 CR 只能是內容字元**（Word/RIS 貼入 quoted scalar 的 0x0D）——libyaml
  讀取時摺疊毀字 → 拒收（R9 連行尾慣例一起放行是回歸，實測一次良性寫入即
  毀檔）。CRLF 行尾照常可讀；emitter 對內容 CR 一律 escape，自家產物零誤殺。
  守衛分層造成「同一檔案的行尾接受度取決於有無未知欄位」（帶未知欄位時
  CRLF 也拒收）——已知的分層不對稱，照實記載。**帶未知欄位時 CR + NEL 全面
  拒收**：
  文字層切分與 libyaml 行模型分歧（`\r\n` 是單一 grapheme，Character 層檢查
  是死碼；unicodeScalar 層比對）→ decode 錯誤 → quarantine。**LS (U+2028) / PS
  (U+2029) 不在守衛範圍（R6 限縮，R7 更正機制敘述）**：quoted scalar 內被
  libyaml 依 YAML 1.1 摺疊規則**保留**（round-trip 無損），且 emitter 自己就
  會逐字寫出 raw U+2028（R5 的全文掃描把自家產物整檔誤殺）；plain scalar 含
  裸 LS 會讓 libyaml 多切出 key——帶未知欄位時由切分計數 oracle fail-closed，
  **純 known 檔無此防線（已知盲區**：`title: A␨date: 2020` 型的手寫檔會被
  解成兩個 key、無任何訊號；本生態 writer 不產生此類版面**）**。
- **encode 雙層 canary（R6 起無條件、正規化比較）**：**每次**寫出前
  (a) re-parse 產物（重複鍵、dangling alias 拒寫）+ (b) **語意自檢**——decode
  產物與**正規化後的模型**比對（known 欄位全等、各層未知 key 序列相符、各未知
  區塊值語意相等；不符時訊息指認欄位——R7）。正規化＝把序列化有損的欄位截到
  encoder 精度（provenance 的兩個 Date，秒精度——store 刻意不存 fractional
  seconds；identity 比對會把次秒 Date 的合法寫入誤拒，verify R5 CRITICAL）。
  已知的字串有損通道——值的**前導 U+FEFF**（serialize→compose 會吃掉）——
  刻意不正規化：屬資料品質問題，fail-closed 拒寫 + 欄位指認訊息，不靜默改
  資料。canary 的界線（明文化，R7）：它比的是「模型 ↔ 產物」，**偵測不到
  decode 端已經丟掉的東西**——「檔案 → 模型」的保真由 decode 側的 oracle 與
  各 fail-closed 條款負責。不符拒寫；絕不原子性覆蓋合法檔案。代價：每次寫入
  多數輪 parse（產物 canary、full decode、per-block compose ×2——檔案 KB 級，
  可接受；效能面見 #30）。
- **版面契約（normative）**：容忍層假設 block-style、LF 行尾、非 complex-key
  的版面——這是 store writer 的約束；超出此版面的合法 YAML **不保證保真**。
  多數情形 fail-closed quarantine（資料完整性 > 病態版面的可用性），但**有一個
  已知例外**：alias 落在 mapping key 位置時，展開發生在 `Yams.compose` **內部**，
  在任何守衛之前——那不是 quarantine，是掛死（見上「已知未防護」與 #36）。
  R11 曾加過一個文字層的 complex-key 守衛，R12 實測它兩個方向都錯（三條繞道未擋、
  又誤殺 emitter 自己的輸出）後整段撤除。**不要重新加回文字層守衛。**
- **多文件 YAML** 由 root parse 拒收（單文件 stream）；`---`/`...` 出現在
  block scalar 內容中不受影響（無文字層守衛誤傷）。
- **merge key `<<` 不入 tolerant 範圍**（parser 間語意分歧；適用所有容忍層——
  entry/person/library 頂層與 `akashic` 巢狀層，R6 更正原「頂層」措辭）→
  decode 錯誤 → quarantine；未知區塊**內部**的 `<<` 隨原文逐字保留（本生態
  單一 parser，寫回不改文字即無新語意）。
- **寫入路徑的可失敗性（R6，R7 誠實化）**：encode 自 v1.3 起可拒寫（canary
  fail-closed）。多檔寫入者必須收容——已收容者：Zotero pull 與 resolve-people
  （三個 call site：CLI／MCP／App）對單筆寫入失敗記入 `writeFailed`／回報並
  續跑，index 照 rebuild；CLI（`import-zotero`、`resolve-people --apply`）在有
  單筆失敗時**非零退出**（收容 ≠ 吞掉 process 層訊號）。citekey rename 先對
  所有要改寫的 entry 做 **encode 預檢**——這只消除「canary 拒寫」這類**確定性
  失敗**的中途中斷；I/O 層失敗（磁碟滿、權限、外部競態）仍可能留下部分改寫，
  完整多檔交易／rollback 屬 #29 範圍，本節不宣稱多檔原子性。

**混版部署（R7 重申）**：tolerant-preserve **不具追溯力**——已釋出的舊 binary
（≤ v1.2）面對新欄位仍整檔 reject；要享有本節保證，所有讀寫者都必須先升到
v1.3+。非累加演化（形狀變更、strict 層加欄位）另需版本訊號（#24）。同理，
v1.3 的讀取面**嚴格化**（known 形狀不符、無法解析的時間戳由靜默容忍改為
quarantine）可能讓舊版可載入的病態檔案在升級後進 quarantine——這是刻意的
fail-closed 遷移（檔案原封不動，`doctor` 列出 quarantine 原因供修復），不是
資料損失。

## 附註：多「檔案」（#18，config 層——不屬 store format）

一份 config 可註冊多個實體 store root（`files:` registry＋`current:`）。**每個檔案
內部完全遵守本文件的 store format**；檔案之間互不相通（無跨檔案 relations／people
共用）。本節僅為指引——config schema 見 `docs/specs/2026-07-30-akashic-phase4c-multifile-design.md`。
