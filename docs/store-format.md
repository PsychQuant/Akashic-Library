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

**known 欄位的形狀演化不入 tolerant 範圍（normative，R6）**：known key 存在但
形狀不符（如 `names` 由 sequence 演化為 mapping、`tags` 變 mapping、`status` 變
sequence、`imported_at` 非 ISO-8601）→ **decode 錯誤 → quarantine**。v1.2 的
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
  共用**（R7——per-block 重置可被 N 個接近上限的區塊聚合成 CPU 放大面）；
  實際可容納的節點數依結構而定（單鍵 mapping 元素約耗 3 次比對/個）。巨大
  未知子樹與 anchor/alias 重用型 DAG 都會觸發 → quarantine。這是未知子樹的
  實質大小上限（可用性懸崖，照實記載）；超大 payload 不應塞在未知欄位裡。
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
  直接 throw。
- **有損行尾字元不支援**（含未知欄位時）：**CR / CRLF / NEL (U+0085)**——
  libyaml 讀取時會把 quoted scalar 內的 CR/NEL 摺疊成空白（**毀字**），CR 另有
  Swift grapheme 行模型分歧（`\r\n` 是單一 grapheme，Character 層檢查是死碼；
  unicodeScalar 層比對）→ decode 錯誤 → quarantine。本 binary 的 emitter 對
  CR/NEL 都 escape，自家產物永不觸發（守衛零誤殺）。**LS (U+2028) / PS
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
  可接受；效能面見 #31）。
- **版面契約（normative）**：容忍層假設 block-style、LF 行尾、非 complex-key
  的版面——這是 store writer 的約束；超出此版面的合法 YAML 一律 fail-closed
  quarantine（資料完整性 > 病態版面的可用性）。
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
