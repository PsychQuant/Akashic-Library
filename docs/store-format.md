# Akashic Store 格式規格書（v1.3，#23 tolerant-preserve 修訂）

Akashic library 的 canonical store 格式。本文件是 spec §4 的正式版；
實作＝`AkashicCore`（型別/YAML/citekey）＋ `AkashicStoreIO`（讀寫）。

原則：**檔案是本體，資料庫是 cache**。`entries/`、`people/`、`notes/` 是 canonical、
git 追蹤；`.akashic/` 下一切可全刪重建。

## 1. Library 佈局

```
<library-root>/
├── entries/<citekey>.yaml    每筆文獻一檔
├── people/<person-key>.yaml  人物實體
├── notes/<citekey>/*.md      衍生筆記（自己的產出）
└── .akashic/                 衍生物（index.sqlite 等）；gitignored、可重建
```

附件不在 library 內：PDF 進外部 attachment pool 或留在 Zotero storage，
entry 只記 reference（見 §2.4）。

## 2. Entry 檔（`entries/<citekey>.yaml`）

### 2.1 範例（全欄位）

```yaml
id: 7C1F6C2E-1A2B-4C3D-9E8F-000000000001
citekey: cheng2025identifiability
type: article
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
  - pool: 2025/cheng2025identifiability.pdf  # 相對 attachment pool
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
```

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
- `pool:`＝相對 attachment pool root。
Phase 1 的 Zotero pull 只記 `zotero:` reference、不搬檔。

### 2.5 Namespace 契約（CRITICAL）

| 區塊 | 擁有者 | pull 行為 |
|------|--------|-----------|
| biblatex 面向（type/title/authors/date/fields/`zotero:` 附件） | Zotero（過渡期） | 版本較新時覆寫 |
| `provenance` | pull 機制 | 覆寫 |
| `akashic`、`pool:` 附件、`id`、`citekey` | Akashic/使用者 | **絕不觸碰** |

特例：**已解析的作者**（`key:` 形式）是使用者確認過的衍生知識——pull 更新時
若 entry 含任何 `key:` 作者，整個 authors 欄保持不動（import report 列於
`authors preserved`）。`akashic.tags` 只在**建檔**時從 Zotero seed 一次。

Zotero 欄位只保留 `ZoteroMapping.fieldMap` 允許清單內的項目（title/date 為一級欄位）；
未映射欄位（如 `extra`）**不入庫但不靜默**——import report 的 `dropped fields` 列名列數。
quarantined 檔（decode 失敗）**永不被 import 覆寫**：其 basename 佔住 citekey，
新 entry 一律讓位取衝突後綴。

### 2.5.1 v1.1 update 條件與身分（Phase 2）

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
names:                       # aliases；第一個是顯示名
  - Chun-Houh Chen
  - 陳君厚
  - C.-H. Chen
orcid: 0000-0002-…           # 可選
openalex: A5017…             # 可選
note: 中研院統計所            # 可選
```

解析紀律：**絕不自動合併**。`akashic resolve-people` 只列 alias 完全命中的
高信心候選（同 alias 對到 2+ 人＝歧義、不出候選），`--apply` 是顯式第二步。

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

**版本對照**：`format: 1` ＝ v1.x 家族（`entries/<citekey>.yaml` + `people/<person-key>.yaml`；
tolerant-preserve 於 v1.3 落地，屬 additive 故不 bump）。`format: 2` ＝ `entities/<uuid>.yaml`
（#35，見 §5.-1）——**結構重排**，是 refuse-if-newer 存在的直接理由。

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
（key/literal 二態封閉）、**`attachments` 元素**（`{zotero: path}` / `{pool: path}`
單鍵封閉——R6 補列：此層加新欄位會原地重演 #23 的失敗模式，演化必須與 binary
同步 + 版本訊號，見 #24）、`provenance`（Zotero namespace，mapping 與 binary 同步
演化、pull 覆寫）、`akashic.relations`（新關係類別應為 `akashic` 層的新欄位，
由該層容忍涵蓋）。

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
  | **#20 的 temporal person，1400 段時間軸** | **15,857** |
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
   同名（見 §organization 的 key 契約），而 decode 沒有 store 存取。
3. `judgement` 與 `rests-on` **MUST** 成對出現。形狀與判斷型 provenance reference 相同，
   但 **MUST NOT** 含 `field:`——判斷關乎哪個候選才對，不是宿主記錄的哪個欄位。
4. 記錄 **MUST NOT** 帶「已解決」狀態。消歧完成時整筆刪除，歷史託給版本控制而非 store。
5. `divergence` **MUST** 只存在於 `entities/` 佈局（format ≥ 4）。legacy 下 person 落在
   `people/<key>.yaml` 而刪除只認 `entities/<uuid>.yaml`——寫得進去、刪不掉。

6. 候選鍵 **MUST** 在寫入時通過 `StoreKey` 驗證，與其他每一條寫入路徑一致。理由不是
   path traversal（候選鍵不進任何路徑），而是 `validate` 對畸形候選鍵報 error——沒有
   這道守衛，工具就能寫出一筆自己的 validate 永遠不會通過、又沒有編輯入口可修的記錄。

**消歧**：`akashic resolve-divergence <id> --survivor <key>`。它是**一個操作**：合併別名
→ 全庫參照重寫 → 刪除被併記錄與歧異記錄。

動磁碟前的四道前提，**任何一道不過就完全不動**：

| 前提 | 為什麼 |
|---|---|
| store 位於版控工作樹內 | 歷史託給版控，版控之外刪掉就是真的沒了 |
| `entities/` 佈局（format ≥ 4） | legacy 下寫得進去、刪不掉 |
| 無跨記錄不一致 | 雙佈局並存時會刪錯檔 |
| **無 quarantined 檔** | 讀不到的檔可能正指著要被刪掉的實體，而讀不到就改寫不到——刪除後會留下藏在工具看不見處的永久懸空參照 |

參照的範圍包含**其他歧異記錄的候選**（那也是參照）。候選 **MUST** 同時比對 key 與
shape 才遷移——鍵在不同形狀之間可以同名。遷移後候選少於兩個的記錄 **MUST** 一併刪除
並回報：那種記錄寫回去會被自己的 decoder 拒收。

`akashic rename` 同樣 **MUST** 遷移歧異記錄的 work 候選；改名會讓候選塌縮時 **MUST**
拒絕——rename 沒有合併語意。

**失敗語意**：參照重寫的單筆失敗**收容並繼續**，結束時報告清單並以非零碼退出；**有任何
失敗就不刪任何東西**——歧異記錄是唯一能重跑的依據，先刪它再讓被併檔留著，比撕裂更糟。
報告 **MUST** 在索引重建之前印出：索引過期可重建，報告遺失不可回復。

**合併的範圍**：只搬別名。被併記錄帶有倖存者沒有的任何內容時，合併 **MUST** 拒絕並
指名將失去什麼。判定 **MUST** 是結構比較而非逐欄白名單——白名單會在型別加欄位時靜默
失效，那正是這條檢查要防的事重演一次。

**消歧不是清理工具**：沒有指名被併鍵的記錄 **MUST NOT** 被改動，即使它自己有既存的
重複參照。

**已知缺口**（皆有 issue）：沒有建立入口（#77）；版控檢查只確認「往上找得到 `.git`」而
非「已被追蹤」（#73）；封閉集合擴充的相容性未決（#74）；消歧不看已寫下的判斷、work
合併不搬欄位（#75）；MCP 面無投影（#76）。

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
  `zotero`/`pool` 兩個純字母字串、恆 resolve 為 str，無等冪問題（三層鍵規則
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
