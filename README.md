# Akashic-Library

原生（Swift / macOS）文獻整合系統。核心命題：**文獻資料的 canonical store 由 Akashic 自己擁有**——
metadata 檔案化（per-entry YAML、git 版控）、附件外部化、Zotero 降級為擷取前端（過渡期單向 pull）。

阿卡夏紀錄（Akashic records）＝記載一切知識的圖書館，本義使用。

## 結構

```
AkashicKit（Package.swift）      核心 Swift package：八模組 + akashic CLI
├── Sources/AkashicCore          Entry / Person 型別、schema 驗證、citekey+UUID 規則
├── Sources/AkashicStoreIO       per-entry YAML 讀寫（atomic）、library 掃描
├── Sources/AkashicEntity        人物解析原語（只出候選，絕不自動合併）
├── Sources/AkashicZoteroImport  read-only 讀 zotero.sqlite → diff → 寫 entries
├── Sources/AkashicExport        經 biblatex-apa-swift 出 .bib；CSL-JSON
├── Sources/AkashicIndex         衍生 SQLite index 重建（位置依 registry key，見下）
├── Sources/AkashicQuery         結構化查詢（欄位 + 關係：同作者/同期刊/cites/related）
├── Sources/AkashicGraph         關係圖模型、鄰域展開、Mermaid/DOT/GraphML
└── Sources/akashic              CLI：import-zotero / import-wos / validate /
                                 export-bib / export-tables / resolve-people /
                                 bootstrap-people / bootstrap-organizations /
                                 resolve-organizations / update-person /
                                 doctor / query / graph /
                                 rename / record-divergence（--prefers）/
                                 resolve-divergence（--override-reason）/
                                 authorize-names / fmt / library / file / migrate
mcps/                            MCP server submodules（che-zotero-mcp、che-biblatex-mcp）
repos/                           共用 library submodules（biblatex-apa-swift = canonical）
docs/                            spec 與 store 格式規格書
docs/explainers/                 「為什麼」的說明（規格說 what，explainer 說 why）
attachments/                     PDF pool（gitignore；可 symlink 至 Dropbox）
```

**這個 repo 只有程式，不含資料。** 使用者的 store 住在 `~/.akashic/`（#37）：

```
~/.akashic/                      ← store root ＝ akashic home ＝ 資料的 git repo 根
├── store.yaml                   ← format 標記（#24）；決定佈局長什麼樣
├── entities/<uuid>.yaml         ← canonical（版控）——work 與 person 同一個目錄，
│                                   靠 type 欄位分辨；檔名是不變的 UUID（#35）
├── libraries/                   ← canonical（版控）
├── config.yaml                  ← registry：files: {main: ~/.akashic} + current: main（gitignored）
└── index/main.sqlite            ← 衍生 index，依 registry key 命名（gitignored）
```

**佈局依 format 而定，而且只建這個 store 實際會用到的目錄**（#101）：`ensureLayout()` 對
format ≥ 2 的 store 建 `entities/`、不建 legacy 的 `entries/`／`people/`（format 1 反之，#102），
對**有帶 registry key** 開啟的 store 不建 in-store 的 `.akashic/`。

`store.yaml` **壞掉或比本 binary 新**時，會建佈局的入口（`doctor`／`import-zotero`／
`file add`；MCP 的 `import-zotero` tool 同理）**明確拒絕**（「無法解析」／「請升級」），
不再依猜測安靜蓋目錄（#106）——對壞 marker 繼續猜的代價是雙佈局。寫入路由
（`usesEntitiesLayout`）的容錯不變，讀寫既有資料不受影響。

> refuse-if-newer 是**所有** CLI 指令的保證（#115）：閘在 `openStore()` 且**先於**
> 佈局檢查（未來 format 可能改目錄結構——先問版本，才不會把太新的 store 誤診成
> 「不是 library」）——`fmt` 的全庫改寫、`library create`、read-only 查詢，開 store
> 的當下一律把關（按舊語意誤讀新格式，讀跟寫一樣危險）。`file use` 在切換 current
> 的當下同步把關（與 `file add` 對稱）。

反過來讀不成立——目錄的存在不是可靠判準：`migrate` 不刪空的 legacy 目錄（`doctor` 的
殘留報告會列出，#107）。完整說明見 [docs/store-format.md §1](docs/store-format.md)。

寫入面有**寫入閘**（#108）：六個寫入 API 前置「root 得是一個 store」的斷言——
打錯的路徑被拒絕且零磁碟副作用，不再被安靜實體化成無 marker 的幽靈 store。
建立入口（`doctor`／`import-zotero` 的 `ensureLayout`）是刻意的例外——它無法區分
「刻意建新」與「打錯字」；詳見 [docs/store-format.md §1](docs/store-format.md)。

`index/` 刻意**不**放在 canonical 樹裡：它可重建（536 筆約 0.55 s），而 store root 正是會進
Dropbox / git 的東西——在同步樹裡放 live SQLite 是已知的毀檔風險（partial write、conflict copy）。
index 自帶**身分戳記**（#122）：記錄它是為哪個 store root 建的，讀端比對身分不只 schema
版本——registry 路徑被重新利用時，別的 store 建的 index 不再被誤當自己的。
未註冊的 store（`--library <path>` 直指）則回落 in-store `.akashic/index.sqlite`，因為那種 store
不在 registry 治理範圍內。

### 環境變數

| 變數 | 作用 |
|---|---|
| `AKASHIC_HOME` | 覆寫 akashic home（預設 `~/.akashic`）。**同時決定 registry（`config.yaml`）與衍生 index（`index/<key>.sqlite`）的位置**——兩者必須同源，否則會出現「registry 讀一個 home、index 寫另一個 home」的跨 profile 混用（#101 修正）。CLI / MCP / App 三面一致遵守 |
| `AKASHIC_LIBRARY` | 直接指定 library root，等同 `--library`。路徑已註冊時**反查 registry 帶 key**（#105）——同一個 store 不因開法不同而有兩份 index |

Library root 的解析順序：`--library` → `$AKASHIC_LIBRARY` → `$AKASHIC_HOME/config.yaml`（`current` 指向的
`files:` 項）。三條路都會解析 registry key：前兩者對已註冊路徑**反查**（#105），未註冊才 keyless。

Registry（`config.yaml`）位置只有**一條**解析鏈：`--config` → `$AKASHIC_HOME/config.yaml`。
`file` 家族與 MCP 曾各自 fallback 到寫死的真實家目錄（設了 `AKASHIC_HOME` 時與 `doctor`
讀**不同的 registry**、`file add` 寫進 doctor 看不到的那份）——#110 移除了那個第二來源，
且各解析入口（含 `LibraryLocator`）的 config 預設一律由**同一份** environment 推導——
「一條鏈」是 API 預設值層級的保證，不是只對現有呼叫端碰巧成立。

> **經 registry 解析的指令一律保留 key**（#101）。曾經 `doctor`、`import-zotero` 與 App 只取
> root、丟掉 key，於是把已註冊的 store 當成未註冊的——它們**重建的是錯的那一份 index**：
> in-store 的 `.akashic/index.sqlite` 每次被寫成完整副本，而 `index/<key>.sqlite` 從來沒被更新
> 過，查詢一直打在過期的衍生資料上且無任何訊號。
>
> 這類殘留不用自己猜：**`doctor` 會列出來**（#107 的「殘留：」段——依 format/key 不該
> 存在、且為空目錄或純衍生物的路徑；report-only，處置留給人；含資料的目錄與 `sources/`
> 永不列入）。已註冊的路徑不會再長出來——`--library <路徑>` 與 `$AKASHIC_LIBRARY`
> 現在都反查 registry 帶 key（#105）；只有**真的未註冊**的 store 仍以 keyless 開啟並寫
> in-store `.akashic/`，那是它的正常回落位置，不是殘留。

## 狀態

- **Phase 1（完結）**：store 地基 — 格式規格、AkashicKit、Zotero 單向 pull、CLI。
  Spec：[docs/specs/2026-07-21-akashic-library-phase1-design.md](docs/specs/2026-07-21-akashic-library-phase1-design.md)
- **Phase 2（本階段）**：MCP 整合 — schema hash 機制、`akashic-mcp`（19 tools）、發布統一。
  Spec：[docs/specs/2026-07-22-akashic-library-phase2-mcp-design.md](docs/specs/2026-07-22-akashic-library-phase2-mcp-design.md)
- **Phase 3（本階段）**：原生 App — 管理工作台（人工裁決 GUI）+ Canvas 關係圖。
  Spec：[docs/specs/2026-07-22-akashic-library-phase3-app-design.md](docs/specs/2026-07-22-akashic-library-phase3-app-design.md)
- **Phase 4a**：多 library（membership views）— canonical store 仍是全集不分割，
  library 只是成員集合視角；people / graph / index 共用（#13）。
  Spec：[docs/specs/2026-07-29-akashic-phase4a-multilibrary-design.md](docs/specs/2026-07-29-akashic-phase4a-multilibrary-design.md)
- **Phase 4c**：多「檔案」（多實體 store root）— 每個檔案自成 universe，
  互不相通、不跨檔案共用 people 或 relations（#18）。
  Spec：[docs/specs/2026-07-30-akashic-phase4c-multifile-design.md](docs/specs/2026-07-30-akashic-phase4c-multifile-design.md)

> 上面是**功能**分期。與之正交的還有一份 store 讀取契約的設計：
> [YAML 輸入 profile](docs/specs/2026-08-01-akashic-yaml-input-profile-design.md)（#33，
> 設計定案、實作待 #25 merge）——收窄 store 接受的 YAML 語法子集，讓未知欄位容忍層
> 只需處理「未知的 key」而非「YAML 的全部語法」。

### 實體歸戶的兩步（人／機構同紀律）

`literal`（未歸戶的裸字串）是**合法的長期狀態**，不是待清理的髒資料。要把它變成
指向實體的 `key`，兩個 CLI 分工，中間隔著人的確認：

| 步驟 | 人 | 機構 |
|---|---|---|
| 1. 建實體（從 literal 分組） | `bootstrap-people` | `bootstrap-organizations` |
| 2. 歸戶（literal → key） | `resolve-people` | `resolve-organizations` |

兩步都預設**只列候選**，`--apply` 才寫入；`--min-occurrences N` 依出現次數過濾
（投報率優先）。**絕不自動合併**：正規化（NFKC／連字號家族／不可見字元）只住配對
鍵，同一個正規化名對到 2 個以上實體即判歧義、整組排除，交人裁決。

**已知限制**：`bootstrap-organizations` 的 key 取機構名 **NFKC 正規化後**的 ASCII
字母數字 token——雙語寫法（`國立臺灣大學 National Taiwan University`）用英文部分產
key，全形拉丁（`Ｎａｔｉｏｎａｌ…`，CJK 輸入法下的常見產物）先折回 ASCII 再取。
正規化只用於**產 key**，`names` 一律保留原字串。

**產 key 的門檻是 ASCII 覆蓋率 ≥ 50%**，不是「有沒有 ASCII token」。NFKC 會把符號
殘渣折成 ASCII（`℡`→`tel`、`②`→`2`、`Ⅲ`→`iii`），若只看「有沒有」，純 CJK 名字會
突然產出**垃圾 key** 並寫進 store——那比靜默丟棄更糟（多了永久識別碼）。覆蓋率把
殘渣（12–37%）與真雙語名（60–100%）分開，中間有 23 個百分點的空隙。

低於門檻的會列在「無法自動產生 key」清單裡等人工指定，**不會靜默消失**。已知的
**誤擋**：「CJK 全名 + 拉丁縮寫」（`國立臺灣大學 NTU` 27%）會被擋，因為分母是字元數
而 CJK 資訊密度遠高於拉丁——判準跟著「中文名有多長」跑，不是跟著「拉丁部分是不是
好 key」跑。失敗模式是**誠實的**（明列、請人給 key），不是資料汙染。中文-only 機構
同樣只能人先給 key。完整殘留清單見 `Sources/AkashicEntity/OrgBootstrap.swift` 的型別 doc。

**`--apply` 的部分失敗**：單筆寫入失敗不中斷後續（per-item 收容），失敗項逐一列出、
index 照常重建，且**輸出用 `⚠ 部分完成` 而非 `✓`、exit code 為 1**——`--apply` 常被
chain（`bootstrap-organizations --apply && resolve-organizations --apply`），exit 0
會讓半途失敗的結果若無其事往下走。兩個 org 指令的語意一致。

### Store 格式版本

store 是跨 binary（CLI / MCP / App）的契約。格式版本記載於
[docs/store-format.md](docs/store-format.md) §5，並由 store root 的 `store.yaml`
（單一整數 `format:`）自我聲明——binary 讀到高於自己支援上限的版本會在**逐檔 decode
之前整體拒絕**（refuse-if-newer，#24）。CLI / MCP / App 是各自獨立的 binary，只升級
其中一個仍會撞到同一道防線。下表只記各版本的要點：

| 版本 | 要點 |
|------|------|
| v1.1 | provenance hash 欄位 |
| v1.2 | `akashic.libraries` + `libraries/` registry（#13）；未知欄位 **strict → throw** |
| v1.3 | tolerant-preserve（#23）：**開放演化層**（entry / person / library 頂層、`akashic` namespace）的未知欄位改為容忍 + 原樣保留寫回，取代 v1.2 的 throw |
| — | `divergence:` 形狀（#71）：未決的同一性問題成為可記錄的一級事物，記錄與消歧是**兩個**動作：`akashic record-divergence` 記下未決的問題（id 由候選鍵的集合推出，同一組候選＝同一筆記錄；有判斷就必須有依據）——**消歧改寫其他記錄的候選時 id 跟著重算**（#168；先前保留舊 id，於是同一組候選有兩筆記錄，而 #75 的三道判斷守衛全部 key 在那個不變式上，可被一串正常操作靜默繞過。重算會撞上既有記錄或另一筆遷移記錄時，**只有零損失才靜默合併**，否則拒絕整個消歧交人裁決），`akashic resolve-divergence` 才是「合併 + 全庫參照重寫 + 刪檔」的原子操作。**記下判斷不等於做掉它**（#77 補上建立入口前，後者有 CLI 而前者沒有——於是「先記下來、之後再判斷」在使用層不成立）。**消歧的版控前提是 tracked + clean**（#73）：不只「store 在工作樹內」，而是**本次要刪的每個檔案**都已被 git 追蹤且無未提交修改。「在工作樹內」與「刪掉還找得回來」是兩件事——未 commit 的歧異記錄消歧後，`question` / `judgement` / `rests-on` 三者一起永久消失。**additive，不 bump format**——見 [store-format.md §5.8](docs/store-format.md) 與 #74 對相容性決定的討論 |
| format 5 | **對外可稱呼的名字由 `authorized` 指定**（#81）：`names` 的順序不再帶語意，`authorized` 是它的子集、每個書寫系統至多一個。書寫系統為**推導值不儲存**。**non-additive，MUST bump**——舊 binary 會繼續把 `names[0]` 當顯示名（按舊語意解讀新格式）。既有記錄用 `akashic authorize-names`（預設 dry-run，`--apply` 才寫）補；見 [store-format.md §3.1](docs/store-format.md) |
| format 6 | **時間軸段的 `ended: true`＝已結束、時點未知**（#63）：`end` 缺席的預設語意（進行中）不變；退休名單只有「已退休」沒有年份這類一等知識狀態從此可表達，status 推導自動得 `retired`，`export-tables` 的 `researcher_timeline` 以 `valid_end_unknown` 欄攜帶（「進行中」的 SQL 判準是 `valid_end IS NULL AND valid_end_unknown IS NULL`）。**non-additive，MUST bump**——「看似 additive 其實不是」：tolerant-preserve 只涵蓋記錄頂層與 `akashic` namespace，時間軸**段內**的鍵是 strict，舊 binary 讀到 `ended:` 是**整檔 quarantine**（人檔消失）而非保留；見 [store-format.md §3](docs/store-format.md) |
| — | **canonical serialization form**（#69）：記錄寫出的位元組形式由**單一權威**定義（三個 `encode` 函式），正規化即 `encode(decode(x))`——沒有第二份定義。時間軸的序列化順序改為「依 `range` 排序，`range` 相同時**保留寫入順序**」，與相等性用的全序**分離**（後者 `range` 相同時比 `value`，那是為了讓「同樣的段落、不同的儲存順序」判為相等）。動機：`Organization.names` 三筆全無 `range`，由值決勝會讓主名（中文正式名）被 ASCII 別名推到後面。`authors` / `attachments` 的順序**不參與排序**（位置即語意）。新增 `akashic fmt`（`--check` 只回報不寫檔）作為對齊入口；`validate` 不擋排版。**additive，不 bump format**；見 [store-format.md §3.4](docs/store-format.md) |
| — | **`judgement.prefers`：消歧不對已寫下的判斷惰性**（#75 對一）。`divergence` 記錄本來就能寫 `judgement`（人的判斷），但 `resolve-divergence` **從來不看它**——人寫了「這兩筆是同一人、保留 A」，工具照樣讓你選 B 而不吭聲。新增選填的結構化欄位 `prefers: <key>`（與 `judgement` 成對、必須是候選之一），`prefers ≠ --survivor` 時**拒絕**，除非帶 `--override-reason`（空理由不接受）。有 `judgement` 但無 `prefers` 時無從機械核對 → **報 warning、不擋**。<br>**但不代選**：不照 `prefers` 自動執行——#133 起判斷可由 LLM 經 MCP 寫入，自動採信＝把「當場判斷」換成「延遲自動判斷」，繞過 #71 的人工確認底線。倖存者永遠是消歧當下的人工輸入，而這是**型別層強制**的（`survivor` 非 optional 且無 MCP resolve 工具）。<br>CLI：`record-divergence --prefers <key>`（先前只有 MCP 寫得了——LLM 有執法權而人沒有）。<br>**additive，不 bump format**：`judgement`／`prefers`／`rests-on` 是三個**平行的 record 頂層 key**，在 tolerant-preserve 涵蓋範圍內，跨版 round-trip 無損（實測）。代價是舊 binary 會靜默無視這道護欄——那是「選填護欄 + tolerant-preserve」的必然，見 [store-format.md §5.8](docs/store-format.md) |
| — | **不可逆消歧拒絕在「讀不懂的記錄」上執行**（#75）。`resolve-divergence` 檢查本次會刪除或改寫的**每一筆** divergence 記錄（**封閉列舉三類**：目標／塌縮連帶刪除／候選遷移改寫），任一筆帶未知欄位即拒絕。<br>觸發它的實驗很直白：塞一個叫 `future-veto` 的未知欄位，`validate` **會印出**「未知欄位（已保留）」——binary 知道自己讀不懂——然後照樣把記錄連同那個欄位一起刪掉。與「quarantined 檔讀不到就改寫不到」是同一條理由的另一面：**讀不懂**與**讀不到**在不可逆操作前該同樣保守。<br>這取代了「每加一個安全欄位就 bump format」：版本無關、一次涵蓋所有未來欄位、代價侷限單筆記錄（bump 是整庫拒開）。誠實邊界：救不了已編譯出去的舊 binary |
| — | **work 消歧的欄位遺失比對**（#75 對二）。person 側早有 `fieldsLostByMerging`（被併者帶有倖存者沒有的內容 → 拒絕並**指名**），work 側先前**完全沒有**——被併 entry 的 fields／attachments／authors／unknownFields 隨檔案消失，使用者只看到「✓ 併入」。比對面是**封閉列舉**（7 比對 + 2 部分比對 + 2 排除 = `Entry` 的 11 個儲存屬性，反射釘住）。<br>三個判準值得單記：`date` 比的是**前綴相容**（`2020` 與 `2020-03-15` 相容、`2019` 與 `2021` 不相容）；未知欄位是**三分**（缺席／同值／衝突）；`type`／`title` **只比缺席方向**——要求相等會誤拒最常見形狀（keeper 的寫法就是人選的 canonical form），但 `""` 不是任何人選的 form，它是缺席 |
| — | **`died`：人的終結**（#67）。`Organization` 有 `founded`/`dissolved` 而 `Person` 沒有任何生平欄位，於是「隸屬在 2004-11 結束」與「2004-11 在職過世」是同一件事。ISO 8601 前綴、精度不補齊。**缺席 ＝ 右設限（censoring），不是「在世」**——死亡是必然事件，缺席永遠不是「不適用」，只是尚未觀察到。空值與 YAML 的 null-face（`null` / `~` / `NULL` / 空白 / **換行**）一律正規化成缺席——正規化發生在建構時**與建構後的每一次寫入**（`didSet`），不是只在 decode。與 `status` 正交（後者描述隸屬）；`doctor` 報告「已故卻仍有開放隸屬」但**不代為關閉**。「是否仍活躍」刻意**不記錄**——那是 `publication` 表的一句 SQL，一個刪掉不會壞事的欄位不該存在。**additive，不 bump format**；見 [store-format.md §3.2](docs/store-format.md) |

**v1.3 的三個限定，比表格本身重要**：

**1. tolerant 只涵蓋開放演化層。** `authors` 元素、`attachments` 元素、`provenance`、
`akashic.relations` 仍是 **strict 保留層**（closed shape，未知欄位＝decode 錯誤）。
§5 特別註記 `attachments` 那層加新欄位會**原地重演 #23 的失敗模式**。

**2. 讀取面同時嚴格化——升級方向也會咬人。** 部分 v1.2 讀得動的病態檔案在升級後轉為
quarantine，這是刻意的 fail-closed 遷移（詳見 §5「known 欄位的形狀演化」與「有損字元
守衛」兩個 bullet）：

| 新增拒收 | 觸發條件 |
|---|---|
| known 欄位形狀不符、無法解析的時間戳 | 無條件 |
| tagged-shadow 鍵、merge/value tag 面的鍵 | 無條件 |
| `fields` 的字串面撞名、非隱式 tag 鍵、字串面 `<<`/`=` | 無條件 |
| NEL (U+0085) 內容字元 | 無條件 |
| LF 檔內的裸 CR | 無條件 |
| **CR / CRLF 行尾** | **僅當檔案含未知欄位**（走區塊切分路徑） |
| **encode 可拒寫** | canary fail-closed；CLI `import-zotero` / `resolve-people --apply` 單筆失敗即非零退出 |

最後兩列是三個 binary 與任何包 CLI 的 script 都要知道的契約變更：**CRLF 使用者不能只看
「LF 檔內的裸 CR」就以為自己安全**（觸發條件恰恰是本 PR 要服務的情境——較新 binary 寫出
的、含未知欄位的檔），而**寫入自 v1.3 起可能失敗**，多檔寫入者必須收容。

**3. 有兩條 carve-out，但它們不是「放寬」。** §5 從 v1.3 新增的嚴格化裡挖回了兩塊 v1.2
既有行為，方向是**避免回歸**，不是 v1.3 開始接受 v1.2 拒收的東西：

- **collection 形狀**的 known 欄位遇 null 視同不存在（`akashic:` 空值行）。**scalar 欄位
  不適用**——`title:` → `""`、`title: Null` → `"Null"`，走字串面。把 null-as-absent 套到
  scalar 是 R8-verify 標為 CRITICAL 的東西（會讓 Zotero 無標題 item 永遠寫不進 store）。
  具名例外只有 `provenance.imported_at` / `orphaned_at` 兩個 Optional 日期。
- **全檔無 LF** 的 classic-Mac lone-CR 檔可無損載入（CR 是行尾慣例，由 libyaml 正規化）
  ——**但僅限不含未知欄位的檔案**。含未知欄位時走區塊切分路徑，該路徑對任何 CR
  一律拒收（見上表倒數第二列），所以這條 carve-out 與該列**不是**互補而是**交集**：
  只有「全檔無 LF」**且**「無未知欄位」的檔案才享有。這個分層不對稱是既有的，
  §5「有損字元守衛」有記載。

**為什麼要看這段**：舊 binary 讀新 store 的行為由**格式**版本決定；而新 binary 讀舊
store 的行為由第 2、3 點決定。在 #24 落地之前 store 端沒有版本訊號，唯一可用的判斷依據
是消費端的 binary 版本——升級 store 格式前先確認所有消費端（含 marketplace 上的
`akashic-mcp`）都已跟上。

## App（AkashicApp）

```bash
cd AkashicApp && xcodegen generate && xcodebuild -scheme AkashicApp build   # 或直接開 Xcode
```

> ⚠️ **`AkashicApp/` 是 XcodeGen 專案，不是 SwiftPM target** —— `swift build` 與 `swift test`
> **不會編譯它**（這個缺口曾讓一次修正漏掉一半，#101 R1→R2）。CI 會 build 它（#109），
> 但那只保證**編得過**，不保證行為對。所以 view 檔案裡不放邏輯：索引重建／圖查詢／
> 座標幾何住 `AkashicAppKit` 的 `GraphModel`／`GraphGeometry`（#113，`swift test` 射程內），
> view 只留 SwiftUI 殼。改動 `AkashicApp/Sources/` 仍須手動跑上面那行驗證編譯。
>
> 同一個理由讓 `GraphModel` 是**持有 store 的實例**而非 static 函式集（#125）：
> 「索引重建與圖查詢必須用同一個 store」從前只寫在註解裡，而註解在編不出錯的
> target 裡沒有約束力——#101 的事故（keyless 重建寫進另一份 index、查詢讀不到）
> 在型別上仍可重演。改成實例後 **API 允許**把 store 綁定一次讓兩個方法共用。
>
> **但呼叫端還沒採用**（#160 verify 兩席獨立指出，措辭已下修）：`GraphView` 的兩
> 個站點各自 `GraphModel(store: state.store)`，是兩個獨立實例——事故形狀在型別上
> 仍可寫出來，今天沒事靠的是「兩個呼叫同步相鄰」這個**時序**巧合。要讓保證真的
> 生效得把實例 hoist 成單一 binding，而那會引入 stale 問題（`AppState.store` 是
> computed、切檔時會變），需連同重建契約一起做。#125 追蹤。

管理工作台：Sidebar 健康總覽、列表＋詳情（biblatex 唯讀／衍生層可編／rename）、
裁決台三頁籤（People 逐候選、Orphans 三選——刪檔進垃圾桶可救回、Quarantine）、
原生 Canvas force-directed 關係圖（拖拉/縮放/雙擊展開）。
外部變更（CLI/MCP/git）由 file watcher 自動刷新——監看集合依 store 的實際佈局推導
（root + 存在的 canonical 目錄），且會在結構變化後自動 rebind（#116）：`migrate` 建出的
新目錄不需要重啟 App 就會被監看。`akashic rename <old> <new>` CLI 同步提供。

## MCP（akashic-mcp）

marketplace 安裝：`claude plugin install akashic-mcp@psychquant-claude-plugins`。
Library 解析與 CLI 共用同一條鏈（見下方「環境變數」）。

多 library（#13，membership views）：`akashic library list/create/add/remove` 管理具名
成員集合（如 `sinica`、`psychology`），`akashic query --in-library <key>` 篩選；MCP 有
`akashic_libraries` tool 與 `akashic_search` 的 `library` 參數；App sidebar 可切換 view。
store 永遠是全集——library 只是視角，成員關係存在 entry 的 `akashic.libraries`（與 Zotero 脫鉤）。
⚠ 並發限制：對**同一 entry** 並發執行 membership 寫入（CLI 與 MCP 同時 `library add/remove`）
不保證安全——read-modify-write 無跨程序鎖，後寫者可能靜默蓋掉先寫者（跨程序鎖為 #7
store 硬化範疇）。`create` 為 exclusive-create（並發同 key 恰一方成功）。單一操作者依序使用不受影響。
工具面：19 tools——9 讀（search/get_entry/relations/graph/export/people/person/doctor/divergences 列歧異）+ akashic_files（list/use——多檔案切換）+ akashic_libraries（list/create/add/remove）+
8 寫（**只碰衍生層**：set_status/tag/link/resolve_people 逐候選/create_entry 庫外/add_person/import_zotero/record_divergence 記歧異**不**消歧——消歧屬人工）。
biblatex 面向唯讀——過渡期歸 Zotero pull 管。並發（MCP 與 CLI 並用）：per-file atomic
write、last-wins、index 冪等重建（單人場景設計）。

## 輸出消毒（`displaySafe` / `documentSafe`）與它的機械守衛

store 內容是**未信任的**——來自 Zotero 匯入（出版商與網頁）、別的 binary、以及 #133
起可由 LLM 經 MCP 寫入的 divergence 判斷。任何把 store 衍生字串送進使用者可見輸出的
位置都要包 `displaySafe(…)`（資料面 `max: 800`、識別字 `max: 200`、路徑 `max: 300`），
否則 raw ESC／U+202E（RTL override）／U+2028 會逐字流進終端、LLM context 或 SwiftUI。

守衛是 `DisplaySinkCoverageTests` 的**原始碼文字掃描**（#28／#141）——問題從來不是
`displaySafe` 本身有 bug，而是**有人新增了一條沒接上它的輸出路徑**，而記憶枚舉贏不了
「每次改動都可能新增一條」。掃描面用**枚舉 `Sources/` + 顯式 opt-out（含理由）**，不是
手寫白名單：手寫清單有三個靜默失效路徑（打錯字、刪掉一項、新模組沒人加），實測全部
成立。要排除必須寫進 `optOut` 並給理由。

> **守衛全綠 ≠ 這一面安全。** recall 實測 **31%**（210 個含 `displaySafe(` 的行只認得
> 67）。已知盲區：**續行**（sink 標記在 N 行、payload 在 N+1 行，56 處，#162）、
> **裸變數名**（token 是 `.title` 這種帶點形式，`if let journal = s.journal` 之後的
> `journal` 抓不到，#164）、以及**部分退化**（少一個 disjunct、少一個 token——逐軸
> 下限只抓整條失效，#163）。
>
> 這不是理論缺口：**至今找到的每一條真洩漏都是人工比對發現的，沒有一條是守衛抓到
> 的，而且修好之後守衛依然看不見**（作者 `literal`、`summaryDict` 的 `journal`、
> `tags`／`status`、`Provenance.zoteroKey`、`relations.cites/related`、`addPerson`
> 回吐的 `names`、`droppedFields` 的 key、`files list` 的 `active_root`／
> `legacy_library`、`co_authors` 的 `person_key`、`personDict` 的 `key`）。共同形狀
> 都是**「同一份資料在同一個檔案裡兩種待遇」**——`zotero_key` 那條的下一行就是包了
> `displaySafe` 的 `zotero_hash`，註解還寫著理由；`person_key` 那條的下一行 fallback
> 就是它自己。那個不一致比守衛更早發現問題，review 時值得優先看它。
>
> **不寫「總共 N 條」，因為那個數字每一輪都在變。** #164 一輪人工稽核掃出 47 條、
> 判定 3 條是真的並把「3」寫進文件；獨立的一輪在同一批裡又找到 4 條；**再一輪又
> 找到 3 條**。「稽核跑過了」不等於「稽核跑完了」，而第二輪的 recall 也不是 1.0——
> 寫下確定數字會被日後的人讀成「這一輪已經清乾淨」。上面的清單是**已知的**，不是
> **全部的**。

### 兩個消毒器：訊息邊界 vs 文件邊界

| | `displaySafe` / `displaySafeMultiline` | `documentSafe` |
|---|---|---|
| 用在 | 錯誤訊息、識別字、單一欄位 | `.bib` / CSL-JSON / mermaid / dot / graphml 整份文件 |
| 跳脫反斜線 | **是**——否則輸出可被內容偽造 | **否**——反斜線在那裡**是內容語法** |
| 標記形式 | `\u{001B}` | `U+001B`（無反斜線／引號／角括號） |
| 長度上限 | 有（訊息該短） | **無**——截斷一份文件永遠產生壞掉的文件 |

分成兩個是因為 `displaySafe` 的反偽造設計套到文件上是**致命**的（#171）：實測
`export-bib` 走 stdout 時 `\textit{}` 變成 `\u{005C}textit{}`、CSL-JSON 直接不能
parse——而 stdout 是**預設**路徑（`> refs.bib`、`| pbcopy`、`| bibtool`），`--output`
才是選項。同一份匯出走檔案是好的、走預設路徑是壞的。

尺寸的處置只有兩種：**不設限**（CLI stdout——使用者自己要的）或**拒絕**（MCP——
tool result 進 LLM context，上限 8 MB，超過時報錯並指路 `--output`）。沒有
「截一半還能用」的中間選項：4000 字元的行長上限會把常態的 abstract 截成大括號
不閉合的無效 `.bib`，而且靜默。

## Build & Test

```bash
swift build
swift test
```

**`swift test` 必須跑完整套，不得用 `--skip` 繞過。** 部分輸出很容易被誤讀成成功——測試
程序若中途 fatal error 中止，畫面會停在「Executed N tests, 0 failures」，但 N 遠小於總數
而其餘 suite 從未執行。判斷通過與否要看**最後一行的總數**，不是看有沒有紅字（#56：一個
對空陣列取值的 `issues[0]` 曾以此形式遮蔽 12 個失敗）。

**不寫死預期測試數**——它每次加測試都會過期，過期的數字比沒有數字更糟。跑一次 `swift test`
看最後一行即可。

> **CI 的「測試數下限」不是預期測試數**（#57）。它是一個**帶餘裕的下界**（目前 650，當下總數
> 679），擋的是完全不同的失敗：測試**靜默地不再被執行**——整個 suite 沒編進 target、有人註解掉
> 一個 class、filter 寫錯。那些情況 exit code 是 0，只有數量看得出來。它不驗證「跑滿了」，
> 也不需要隨每次加測試而更新；只在測試規模成長一截之後才往上調，而那次調整本身就是一次 review。

測試裡對集合取第一個元素**應該**用 `try XCTUnwrap(xs.first)` 而非 `xs[0]`——後者在空集合上
是 fatal error（中止整個程序）而非測試失敗。**這是往後的規則，不是既成事實**：測試樹裡仍有
約 12 個未改的站點（`WoSImportTests`、`EntitiesLayoutTests`、`KnownLayerEvolutionTests`、
`AppLibraryMembershipTests`、`ServiceTests`、`UnknownFieldVisibilityTests`），它們仍帶著同一種
中止風險。

### 測試沙箱（絕不碰真實 `~/.akashic`）

測試一律在 temp 目錄建假 store、**顯式注入** `AKASHIC_HOME`（`LibraryStore(root:key:environment:)`
的 `environment` 參數存在的唯一理由）；spawn 真 binary 的 E2E 測試必須剝除繼承環境裡的
`AKASHIC_*`（`CLITestHarness` 無條件剝除；其餘兩個 spawn helper 的補齊在 PR #121）。
這不是風格偏好：帶 key 的 store 少了 environment 注入，index 就寫進**使用者真實的**
`~/.akashic/index/<key>.sqlite`（原子覆寫，實際發生過）。

兩層防線（#124）：測試側是每個測試自己的目的地斷言（先斷言 `indexURL` 在沙箱內、才做任何
重建）；process 側是 `RealHomeSandboxGuard`（`Sources/AkashicTestGuard/`，由 C constructor
在 bundle 載入時啟用——`--filter`／`--parallel` 都涵蓋）——測試期間真實 `~/.akashic` 有異動
就 **fatalError** 並盡可能歸因。它是 best-effort **偵測器**而非完備 boundary（`.git/` 刻意
排除、改寫後復原偵測不到——誠實邊界見類別 doc）。守衛觸發時**來源未知**：可能是測試逃逸，
也可能是你在另一個終端動了 store（git／編輯器／同步）——後者重跑即可；無法排除前者時，
先找出是哪個測試，不要停用守衛。

### 工具鏈可移植性

`Package.swift` 宣告 `swift-tools-version: 5.9`，**程式碼就必須在那個範圍內編得過**，不能只在
本機的最新 toolchain 上編得過。

實例（#57，CI 第一次啟用即抓到）：`switch` 對 `Bool?` 用 `case true / case false / case nil`
在 Swift 6.3.3 算窮盡，在 **6.1.2 不算**（`error: switch must be exhaustive` / `add missing
case: '.some(_)'`）。也就是說 main 在此之前對任何非最新 toolchain 的環境是**編不過的**，而沒有
任何機制會說出來。修法是寫成 `.some(true)` / `.some(false)` / `.none` 的 pattern 形式。

判準：**optional 的 switch 一律用顯式 `.some` / `.none`**，不倚賴較新版本才有的窮盡性推導。

### 測試的佈局假設

store 有兩種佈局，測試必須明確選定其一：

| 佈局 | 檔案位置 | 測什麼 |
|---|---|---|
| legacy（format 1）| `entries/<citekey>.yaml`、`people/<key>.yaml` | 檔名↔key 對應、rename 搬檔、stem 不符 quarantine |
| entities（format ≥ 2）| `entities/<uuid>.yaml` | UUID 身分、檔名與內容 id 一致性 |

`ensureLayout()` 會把**新建的空 store** 標成當前 format（走 entities 佈局），把**已有 legacy
內容**的 store 標成 1。所以測 legacy 行為的案例必須明確寫 `StoreVersion.write(root:format: 1)`，
否則會拿到 UUID 檔名而與期望不符。

**但範圍要收到最小——不要放進共用的 `setUpWithError`。** 那會把整個 class 釘死在 legacy，
連同其中與佈局無關的測試一起失去在**實際出貨格式**下的覆蓋。#56 就是這樣一次拿掉了 65+ 個
測試的 entities 覆蓋，而 Zotero import 與 MCP service 這兩個子系統在測試樹裡沒有其他 entities
覆蓋來兜底。

正確做法是 per-test 的 helper，只讓真正需要的測試呼叫：

```swift
private func useLegacyLayout() throws {          // 見 ZoteroImportTests / StoreIOTests
    try StoreVersion.write(root: root, format: 1)
}
```

setUp 就寫入記錄的 suite（如 `RenameTests`）改成 `seed(format:)`，讓格式由各測試選。

**判斷「哪些測試真的需要 legacy」的方法**：把 pin 全部拿掉跑一次，失敗的才是。實測數字
（#56）：`ZoteroImportTests` 2/27、`ServiceTests` 1/41、`StoreIOTests` 5/13、`RenameTests` 2/7。

**反過來也要小心：「換佈局後仍通過」不等於「該佈局有覆蓋」。** 斷言可能空洞為真——
`testRenameMovesFileMigratesRelationsKeepsUUID` 斷言 `entries/old2020key.yaml` 不存在，而
在 entities 佈局下那個路徑從來就沒存在過。判斷覆蓋要看斷言的內容，不是看有沒有變紅。

## CI

`.github/workflows/ci.yml`，macOS runner，觸發限 **push to main**（2026-08-07 改制：
macOS runner 計費 10×，「每 PR 每 push 都跑」曾把 free plan 月額度燒爆——14016/2000
折算分鐘，runner 層直接拒跑）。PR 面的把關改由兩層承擔：

1. **pre-push hook**（本機全套）：`git config core.hooksPath .githooks` 一次安裝——
   push 前跑 `-warnings-as-errors` build + 全套測試（hook 內有 pipefail，管線吞
   exit code 的教訓見 hook 註解）
2. **verify 紀律**：每個 PR 的本機驗證記錄在 PR body（測試總數、build 狀態）

CI 保留的獨特價值是**乾淨環境**（#109 的教訓：submodule／DerivedData 殘留只有乾淨
checkout 抓得到）——每次 merge 後在 main 上驗一次。

| 檢查 | 擋什麼 |
|---|---|
| `swift build` + `swift test` | 一般回歸。**不得加 `--skip`**——允許跳過測試的 CI 等於沒有 CI |
| 測試數下限 | 測試靜默地不再被執行（見上方說明）|
| `load.sql` 端對端 | 「產生出來就跑不起來」的腳本。真的建 store、真的 `export-tables`、真的餵給 `duckdb` |
| fixture 含母子機構 + 斷言 `parent_id` 非空 | 上一條的**前提**。#92 的觸發條件是自我參照 FK 非空，空 store 跑得過——不斷言 fixture 有效，端對端就是裝飾 |

最後一條是 #92 的直接教訓：那個 bug 之所以能活很久，正是因為既有測試斷言的是「產生的 SQL
**字串長什麼樣**」而非「SQL **跑不跑得起來**」。端對端若只跑空 store，等於把同一個錯誤重演一次
——測到的路徑不是會壞的那條。

`actions/checkout` 必須帶 `submodules: recursive`：`Package.swift` 有 path-based 依賴指向
`repos/biblatex-apa-swift`，沒有它 `swift build` 直接失敗。本機看不到這個問題（submodule 早就
在磁碟上），這是 CI 的第一個回報。

## Submodules

```bash
git submodule update --init          # mcps/ 為 private repo，外部 clone 可能無權限（optional）
```

`repos/biblatex-apa-swift` 是 AkashicExport 的必要依賴（SPM path dependency）。
