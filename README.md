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
├── Sources/AkashicIndex         .akashic/ SQLite index 重建
├── Sources/AkashicQuery         結構化查詢（欄位 + 關係：同作者/同期刊/cites/related）
├── Sources/AkashicGraph         關係圖模型、鄰域展開、Mermaid/DOT/GraphML
└── Sources/akashic              CLI：import-zotero / import-wos / validate /
                                 export-bib / export-tables / resolve-people /
                                 bootstrap-people / doctor / query / graph /
                                 rename / record-divergence / resolve-divergence /
                                 authorize-names / library / file / migrate
mcps/                            MCP server submodules（che-zotero-mcp、che-biblatex-mcp）
repos/                           共用 library submodules（biblatex-apa-swift = canonical）
docs/                            spec 與 store 格式規格書
docs/explainers/                 「為什麼」的說明（規格說 what，explainer 說 why）
attachments/                     PDF pool（gitignore；可 symlink 至 Dropbox）
```

**這個 repo 只有程式，不含資料。** 使用者的 store 住在 `~/.akashic/`（#37）：

```
~/.akashic/                      ← store root ＝ akashic home ＝ 資料的 git repo 根
├── entities/<uuid>.yaml         ← canonical（版控）——work 與 person 同一個目錄，
│                                   靠 type 欄位分辨；檔名是不變的 UUID（#35）
├── libraries/  notes/           ← canonical（版控）
├── config.yaml                  ← registry：files: {main: ~/.akashic} + current: main（gitignored）
└── index/main.sqlite            ← 衍生 index，依 registry key 命名（gitignored）
```

`index/` 刻意**不**放在 canonical 樹裡：它可重建（536 筆約 0.55 s），而 store root 正是會進
Dropbox / git 的東西——在同步樹裡放 live SQLite 是已知的毀檔風險（partial write、conflict copy）。
未註冊的 store（`--library <path>` 直指）則回落 in-store `.akashic/index.sqlite`，因為那種 store
不在 registry 治理範圍內。解析順序：`--library` → `$AKASHIC_LIBRARY` → `~/.akashic/config.yaml`。

## 狀態

- **Phase 1（完結）**：store 地基 — 格式規格、AkashicKit、Zotero 單向 pull、CLI。
  Spec：[docs/specs/2026-07-21-akashic-library-phase1-design.md](docs/specs/2026-07-21-akashic-library-phase1-design.md)
- **Phase 2（本階段）**：MCP 整合 — schema hash 機制、`akashic-mcp`（14 tools）、發布統一。
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
| — | `divergence:` 形狀（#71）：未決的同一性問題成為可記錄的一級事物，記錄與消歧是**兩個**動作：`akashic record-divergence` 記下未決的問題（id 由候選鍵的集合推出，同一組候選＝同一筆記錄；有判斷就必須有依據），`akashic resolve-divergence` 才是「合併 + 全庫參照重寫 + 刪檔」的原子操作。**記下判斷不等於做掉它**（#77 補上建立入口前，後者有 CLI 而前者沒有——於是「先記下來、之後再判斷」在使用層不成立）。**additive，不 bump format**——見 [store-format.md §5.8](docs/store-format.md) 與 #74 對相容性決定的討論 |
| format 5 | **對外可稱呼的名字由 `authorized` 指定**（#81）：`names` 的順序不再帶語意，`authorized` 是它的子集、每個書寫系統至多一個。書寫系統為**推導值不儲存**。**non-additive，MUST bump**——舊 binary 會繼續把 `names[0]` 當顯示名（按舊語意解讀新格式）。既有記錄用 `akashic authorize-names`（預設 dry-run，`--apply` 才寫）補；見 [store-format.md §3.1](docs/store-format.md) |
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

管理工作台：Sidebar 健康總覽、列表＋詳情（biblatex 唯讀／衍生層可編／rename）、
裁決台三頁籤（People 逐候選、Orphans 三選——刪檔進垃圾桶可救回、Quarantine）、
原生 Canvas force-directed 關係圖（拖拉/縮放/雙擊展開）。
外部變更（CLI/MCP/git）由 file watcher 自動刷新。`akashic rename <old> <new>` CLI 同步提供。

## MCP（akashic-mcp）

marketplace 安裝：`claude plugin install akashic-mcp@psychquant-claude-plugins`。
Library 解析：`$AKASHIC_LIBRARY` → `~/.akashic/config.yaml`（`library: <path>`）。

多 library（#13，membership views）：`akashic library list/create/add/remove` 管理具名
成員集合（如 `sinica`、`psychology`），`akashic query --in-library <key>` 篩選；MCP 有
`akashic_libraries` tool 與 `akashic_search` 的 `library` 參數；App sidebar 可切換 view。
store 永遠是全集——library 只是視角，成員關係存在 entry 的 `akashic.libraries`（與 Zotero 脫鉤）。
⚠ 並發限制：對**同一 entry** 並發執行 membership 寫入（CLI 與 MCP 同時 `library add/remove`）
不保證安全——read-modify-write 無跨程序鎖，後寫者可能靜默蓋掉先寫者（跨程序鎖為 #7
store 硬化範疇）。`create` 為 exclusive-create（並發同 key 恰一方成功）。單一操作者依序使用不受影響。
工具面：17 tools——8 讀（search/get_entry/relations/graph/export/people/person/doctor）+ akashic_files（list/use——多檔案切換）+ akashic_libraries（list/create/add/remove）+
7 寫（**只碰衍生層**：set_status/tag/link/resolve_people 逐候選/create_entry 庫外/add_person/import_zotero）。
biblatex 面向唯讀——過渡期歸 Zotero pull 管。並發（MCP 與 CLI 並用）：per-file atomic
write、last-wins、index 冪等重建（單人場景設計）。

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

`.github/workflows/ci.yml`，macOS runner，觸發限 **PR 與 push to main**（macOS runner 的
GitHub Actions 計費倍率是 10×，而本 repo 是 Apple 平台專屬、沒有 Linux 選項；PR 是改動進
main 前的最後一道門，那裡跑一次就夠）。

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
