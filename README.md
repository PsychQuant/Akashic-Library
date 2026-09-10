# Akashic-Library

原生（Swift / macOS）文獻整合系統。核心命題：**文獻資料的 canonical store 由 Akashic 自己擁有**——
metadata 檔案化（per-entry YAML、git 版控）、附件外部化、Zotero 降級為擷取前端（過渡期單向 pull）。

阿卡夏紀錄（Akashic records）＝記載一切知識的圖書館，本義使用。

## 作者

**鄭澈 / Che Cheng** — person entity `333E7920-EE1C-5ACD-B905-793A34720A1C`（`key: che-cheng`）。

記成 UUID 而不是一個名字字串，是因為**這個系統對「人」的正典表示就是 person entity 的
id**，而作者不該是那條規則的例外。名字會變（拼法、羅馬化、`Family, Given` vs
`Given Family`——本 store 兩種都有）、`key` 也可能改；**id 不會**。

「他是誰」「隸屬哪裡」在那筆記錄裡。**「他寫了什麼」不在**——那是 `work.authors` 的
反向邊，由索引算出來的（#218）。person 記錄刻意不存著作：`work.authors` 已經是正典，
存第二份就會分岔。

```bash
akashic person che-cheng                  # 記錄 + 著作 + 合著者（著作為現算）
akashic query --author che-cheng          # 只要庫內著作清單
```

這也是這個 repo 的一個小小的自指：**它的作者是它自己收藏的一筆記錄。**

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
                                 person（讀取面，#218）/ create-entry（#206）/
                                 people / get-entry / link / tag / set-status（#219，
                                 與 MCP 同名 tool 共用 AkashicService 同一函式）/
                                 doctor / query / graph /
                                 rename / record-divergence（--prefers）/
                                 resolve-divergence（--override-reason）/
                                 authorize-names / fmt / library / file / migrate /
                                 migrate-person-identity（#227/#241，dry-run 預設）

                                 **破壞性寫入的目標 store 須指名（#298）**：會改寫
                                 或刪除記錄的命令——`migrate-person-identity` /
                                 `migrate-venues` / `migrate-identifiers` /
                                 `bootstrap-people` / `bootstrap-organizations` /
                                 `bootstrap-venues` / `resolve-people` /
                                 `resolve-organizations` / `enrich-from-zotero` / `enrich`
                                 （唯一來源是 `DestructiveTargetGate.destructiveCommands`；
                                 **這裡刻意不寫個數**——先前寫「六個」而原始碼已是九個，
                                 數字與清單分岔過一次）——在 `--apply` 時若既未給
                                 `--library` 也未給 `--yes`，**拒絕執行**，並在訊息裡
                                 說出實際解析到的 store 絕對路徑與「與你目前所在的目錄
                                 無關」。**dry-run 不被擋**（不帶 `--apply` 時零拒絕）
                                 ——它不寫東西，且正是用來確認目標的手段。
                                 起因是 2026-08-16 的事故：在 scratch 目錄執行無
                                 `--library` 的 `migrate-person-identity --apply`，
                                 `LibraryLocator` 對 CWD 零感知、循 registry 的
                                 `current` 解析到真 store，867 個 person 檔被改名重發
                                 id。核心不是解析錯了（解析完全按設計），是**呼叫者
                                 以為自己在 scratch** 而沒有任何東西告訴他。
                                 破壞性是**封閉列舉**不是判準（型別層零 marker，
                                 `rename` 與 `resolve-divergence` 都不以 `migrate`
                                 開頭卻同樣不可逆），雙向機械稽核測試守住它。
                                 閘門**只作用於 CLI**：MCP 的 apply 收逐 id 顯式清單，
                                 CLI 的 `--apply` 是篩選式批次掃蕩——同型不對稱見
                                 `.claude/rules/mcp-cli-parity.md` 的 tier 閘先例。
mcps/                            MCP server submodules（che-zotero-mcp、che-biblatex-mcp）
repos/                           共用 library submodules（biblatex-apa-swift = canonical）
plugin/                          akashic-mcp 的 Claude Code plugin shell（#275 起住本 repo）：
                                 plugin.json（version=shell、binary_version=release tag，
                                 兩者刻意解耦）、.mcp.json、bin/wrapper（自動下載 binary）、
                                 skills/（akashic-bootstrap 補完、akashic-verify-person
                                 歸戶查證 #276、akashic-import-wos 清單 QA 閘 #277）。
                                 psychquant-claude-plugins 的 marketplace entry 以
                                 git-subdir source 引用本目錄——release 單 repo 化：bump
                                 plugin/plugin.json 與 binary release 同 commit，不再跨
                                 repo 同步 shell
docs/                            spec 與 store 格式規格書
docs/design-principles-and-philosophy.md
                                 建模的規範性原則（Part I）與哲學基礎（Part II）；
                                 §16 另存原始碼慣例的正典計數（見下）
docs/explainers/                 「為什麼」的說明（規格說 what，explainer 說 why）
                                 **逐份索引見下方「Explainers」一節**——五份各自回答一個
                                 反覆出現的問題，其中兩份是**動手前該讀**的判準
docs/import-wos-mapping.md       import-wos 欄名對映正典（12 具名欄＋殘餘收集，#286）
sources/                         內容定址的副本位元組（gitignore；fail-closed 版控排除）
                                 entry 以 akashic.sources 的 digest 引用它（#223）
```

**這個 repo 只有程式，不含資料。** 使用者的 store 住在 `~/.akashic/`（#37）：

```
~/.akashic/                      ← store root ＝ akashic home ＝ 資料的 git repo 根
├── store.yaml                   ← format 標記（#24）；決定佈局長什麼樣
├── entities/<uuid>.yaml         ← canonical（版控）——work 與 person 同一個目錄，
│                                   靠 type 欄位分辨；檔名是不變的 UUID（#35）
├── libraries/                   ← canonical（版控）
├── config.yaml                  ← registry：files: {main: ~/.akashic} + current: main（gitignored）
├── sources/<2hex>/<62hex>       ← 內容定址存檔（gitignore 排除、fail-closed 驗證；#66）
├── sources/index.jsonl          ← 存檔的 provenance 條目——與 blob 同動作落地、
│                                   append-only（腐壞時拒寫、丟棄可見）；doctor 檢出
│                                   孤兒/懸空/malformed/讀不到的 shard（#224）
└── index/main-<8碼>.sqlite      ← 衍生 index，依 registry key + 化身命名（gitignored）
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
未註冊的 store（`--library <path>` 直指）則回落 in-store `.akashic/index-<8碼>.sqlite`，因為那種 store
不在 registry 治理範圍內。

**檔名帶 store 的化身**（#130）。store 根目錄有一個 `incarnation` 檔（單行 UUID，
`ensureLayout()` 於缺席時補寫、隨檔案複製搬移），index 檔名綁它的前 8 碼。這把
TOCTOU 從「偵測」變成**不可表達**——驗證與開啟之間有多少檔案存取都無所謂，換掉的
store 的 index 根本不叫這個名字；同路徑重生時新舊 index 是**不同檔案**。

**讀不到不等於缺席**（#130 verify C）。缺席回 `nil` 並退回純路徑比對（既有 store
都沒有這個檔，那是正常的）；但檔案**存在而讀失敗**（截斷的 Dropbox 半截同步、
online-only placeholder、權限）一律 **fail-loud、絕不覆寫**——覆寫等於把一個 store
變成另一個化身，而那正是這個機制要偵測的事件。先前不分這兩者，實測 `chmod 000`
之下 `doctor` exit 0 零訊息而 id 每跑一次換一個。

代價：重生後舊 index 成孤兒。`doctor` 報告、**不自動刪**，而且只認**本 key 的**
舊化身（`<key>-<8 小寫 hex>`）——`StoreKey` 允許連字號，所以 `main` 不得把
`main-backup-….sqlite`（另一個已註冊 store 的 live index）報成自己的孤兒。

### View：判準是設定，外延是衍生（#54／#65）

「中研院的人」這種切片有名字了。**判準**（誰算在內）寫進 `~/.akashic/config.yaml`，
**外延**（實際是哪些人與著作）現算、不保存：

```yaml
views:
  iss:
    description: 中研院統計所的人與其著作
    person-affiliation: institute-of-statistical-science
    work-has-author-in-view: true
```

```bash
akashic view list              # 有哪些 view、判準是什麼
akashic view show iss          # 外延（實測本 store：159 人 / 424 篇）
akashic view show iss --keys-only   # 一行一個 key，給下游腳本吃
akashic export-tables --view iss -o out/   # view-scoped 關聯表匯出（#274）——
                               # 外延過濾後走同一條 RelationalExport；被引用的
                               # 合著者與機構閉包一併保留，維持外鍵完整
```

**view 不是 entity**（#54 的裁決）：不動 `EntityKind`、不新增形狀裸標籤、
`entities/` 不會出現 `view:`。判準住 `config.yaml` 是因為**它是設定，不是知識**。

沒有 `view create`——設定該用編輯器改，不是用 CLI 造。給一個寫入指令會讓那個區分
在使用層被磨掉（與 `library create` 刻意不同：後者是 registry metadata、屬 store）。

**缺這一半的代價**（#65 記錄的實例）：判準被推到 store 之外，由每個下游各自重新
發明。storyline#5 的 `4AK_build_duckdb.R` 裡那段 filter 就是這裡該有的東西——只是
它住在另一個 repo、另一種語言、另一個人維護的檔案裡。後果是判準不可稽核、會分岔、
無法演化，而成員清單被迫用一份 `.txt` 代替（**外延被當成判準用**，方向反轉）。

**兩個刻意的取捨**：`person-affiliation` 只收 organization **key** 不收 literal
（未歸戶的 literal 拿來當判準會讓成員資格隨拼寫漂移——要納入就先 `resolve-organizations`）；
成員資格**不比對時間範圍**（「現在還在不在」是另一個問題，`endedUnknown` 的語意未定，
見 #63）——view 回答的是「屬於過」。

**「有沒有 key」必須是被查過的事實，不是碰巧**（#125）。keyless 是**合法**狀態；壞的是
「一個已註冊的 store 被當成 keyless」——那會在它裡面長出一個永遠用不到的 index，並且
**重建錯的那個**。#101 修過兩個這樣的呼叫點並留下註解要人一律走 `AppState.store`，但
**註解擋不住新的呼叫點，也擋不住重構**。

所以 `AkashicStoreIO.ResolvedStore` 把它變成型別事實：`GraphModel` 只收 `ResolvedStore`，
於是 `GraphModel(store: LibraryStore(root: x))` **編不過**。取得方式兩種，都要顯式：

| 取得 | 意思 |
|---|---|
| `.resolved(store)` | 由 registry 解析而來（`AppState.resolvedStore` 走這條） |
| `.unregistered(store, reason:)` | 顯式的 keyless opt-out，**理由必填**（同 `display-safe-exempt` 的哲學） |

`.unregistered` 是**刻意留的洞**——keyless 合法，那條路徑必須存在，代價是它可以被誤用。
生產程式碼不得走它，有測試釘住；同一組測試也釘住「`GraphModel` 只能有一個 init」——
多一個收 `LibraryStore` 的 overload，閘門就形同虛設而所有既有測試照樣綠。

### 環境變數

| 變數 | 作用 |
|---|---|
| `AKASHIC_HOME` | 覆寫 akashic home（預設 `~/.akashic`）。**同時決定 registry（`config.yaml`）與衍生 index（`index/<key>-<化身>.sqlite`）的位置**——兩者必須同源，否則會出現「registry 讀一個 home、index 寫另一個 home」的跨 profile 混用（#101 修正）。CLI / MCP / App 三面一致遵守 |
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

## Explainers

`docs/explainers/` 下是「**為什麼**」的說明——規格說 what，explainer 說 why。它們與
`.claude/rules/` 的分工：規則是**要照做的**（封閉列舉、稽核程序），explainer 是
**要理解的**（判準的由來、被否決的替代方案）。

| Explainer | 一句話 | 什麼時候讀 |
|---|---|---|
| [**which-side-does-a-relation-live-on**](docs/explainers/which-side-does-a-relation-live-on.md) | 一條新關係該存在哪一側——**兩步提問**（可表達性／存在依賴），含兩步不一致時怎麼辦 | **要新增任何關係邊之前** |
| [entity-vs-view](docs/explainers/entity-vs-view.md) | entity 與 view 的分界；view 的判準住 `config.yaml` 而非 store | 要新增「某某清單」之前 |
| [why-akashic-is-not-just-google](docs/explainers/why-akashic-is-not-just-google.md) | 為什麼不是「搜尋就好」 | 質疑這個專案存在理由時 |
| [logical-picture-future-and-questions](docs/explainers/logical-picture-future-and-questions.md) | 圖像論的工程類比與未決問題（3.1432：不要把配置實體化）| 要把關係「物件化」之前 |
| [yaml-alias-dos](docs/explainers/yaml-alias-dos.md) | YAML alias 的 DoS 面與為什麼文字層守衛全數失敗 | 碰 YAML 解析時 |

### 兩步提問（最常用的那一份，摘要）

新增一條關係邊時，**先問這兩題**：

| 步驟 | 問題 | 判準 |
|---|---|---|
| **一（可表達性）** | 這條事實在**對方的記錄還不存在時**，能不能被誠實地記下來？ | 能的那一側是正典 |
| **二（存在依賴）** | 把其中一筆記錄**整個刪掉**，這條邊還是不是庫裡的一個事實？ | 事實隨誰消失，邊就住誰身上 |

**「可衍生性」不能當判準**——`person.works` 可從 `work.authors` 算出，而反向同樣成立。
兩個方向都可衍生，所以「能算就算」推不出任何結論。**「查詢方便」也不是**——那是索引的職責。

**兩步不一致時，程序沒有答案**，必須當成新裁決來做並寫下「另一步指向相反方向」。兩步問的
不是同一件事：第一步是**認識論的**（我們能不能誠實記下手上有的東西），第二步是**本體論的**
（那個事實依賴誰存在）。它們目前一致是**經驗事實，不是邏輯必然**。

> ⚠️ **這是思考輔助，不是裁決程序。** 它的輸出必須落回
> [`entity-backlink-completeness`](.claude/rules/entity-backlink-completeness.md) 的封閉
> 列舉表——**不允許拿兩步自行類推出沒寫進表裡的邊**。完整版（含「其餘四條理由為什麼不
> 升格為程序」）見上表的第一份。

## 狀態

- **Phase 1（完結）**：store 地基 — 格式規格、AkashicKit、Zotero 單向 pull、CLI。
  Spec：[docs/specs/2026-07-21-akashic-library-phase1-design.md](docs/specs/2026-07-21-akashic-library-phase1-design.md)
- **Phase 2（本階段）**：MCP 整合 — schema hash 機制、`akashic-mcp`（31 tools）、發布統一。
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

判定會被**記住**（#232）：`--apply` 在同一動作內寫 `resolution-confirmed`、
`--reject` 寫 `resolution-rejected`（entry／holder 不動）；**venue 域的
`--repoint` 兩側都寫**（新的 confirmed、舊的 rejected）、`--demote` 寫 rejected
（#418）——少了 rejected，下一輪會把使用者剛否決的配對再提名一次。以上都是判斷型
provenance reference，落在被判定的 person／organization 上。已否決的配對不再被
提名（同 literal 在別的 entry 是另一次觀察，照提），列表沉底標示而非隱藏；三態
計數（已確認／已否決／未處理）從 verdict 現算、絕不儲存，**只報計數不報比率**
——未處理量（censoring）永遠可見。判定跟著記錄走：`rename` 會一併遷移 verdict、
`bootstrap-*` 絕不覆寫既有檔（含 quarantined）。**verdict 需要 store format ≥ 8**
（同 `ended`／`attested` 的 write-gate 範式；舊 binary 對含 verdict 的記錄是整檔
quarantine，升 marker 前 `--reject` 不可用、`--apply` 照常歸戶但跳過 verdict 並
明白告知——升級程序見 #247）。

`resolve-organizations` 走**兩處** literal：person 的 `profile.affiliations` 與
**organization 的 `parents`**（#166；先前只走前者，於是 `bootstrap-organizations`
吃進去的 parents literal 進得去、出不來）。parents 側多兩道排除，因為那裡有 person
側**不可表達**的錯誤形狀：

- **自我父權**——literal 命中自己的別名。那不是歸戶，是把記錄變成自己的上級。
- **環**——A→B 已存在時再讓 B 指回 A。**本 repo 沒有任何地方偵測 org 階層的環**
  （載入不查、`crossRecordIssues` 不查），造出來會安靜存在到某個走 parents 的消費端
  無限迴圈。判定含既有 `.key` 邊**與本輪已接受的候選**——只看既有邊會漏掉「兩個候選
  各自無害、湊在一起成環」。

篩選旗標 `--person` 改名為 `--holder`（持有者可能是 organization）；**舊名保留為
alias**，既有腳本不會壞。

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
| format 7 | **時間軸段的 `attested: [觀測點]`＝某時點成立、起訖皆不明**（#70）：`ended` 的鏡像——有觀測不等於現況，attested-only 段 **MUST NOT** 視為進行中。非空時 `start`／`end`／`ended` MUST 全缺席（起點已知就不是「起訖皆不明」）。**non-additive，MUST bump**——同 6：段內鍵 strict，舊 binary 讀到 `attested:` 是整檔 quarantine 而非保留；見 [store-format.md §3](docs/store-format.md) |
| format 8 | **`references[].field` 白名單新增消解判定欄位對 `resolution-confirmed`／`resolution-rejected`**（#232）：人工消解判定（「這個 literal 就是他」／「查過了，不是他」）以**判斷型 reference** 落在**被判定的記錄**上（person 或 organization），欄位名是**封閉對**、不得依性質相似類推第三個；`value` 必填、必須可解析，單一文法 `<kind>:<key> :: <literal>`（以**第一個** ` :: ` 切分）。**non-additive，MUST bump**——同 6／7 的「看似 additive 其實不是」：field 白名單是 strict → 舊 binary 讀到 verdict reference 是**整檔 quarantine（記錄消失）**，且該檔可被 bootstrap 的決定性 UUID 安靜覆寫、判定史全滅（#232 verify 實測整條鏈）。write gate 對 format < 8 拒寫含 verdict 的記錄＋指路；**序列化形狀不變——8 只是「這個 store 可以持有 verdict」的宣告**。見 [store-format.md §3.5 消解判定節](docs/store-format.md) |
| format 9 | **附件鍵域收窄為只剩 `zotero`（移除 `pool`）＋ 記錄側副本引用 `akashic.sources`**（#223；原佔 8，rebase 時已被 #232 佔用順延）：可 ingest 的內容一律以 digest 引用、不以檔案系統路徑引用；副本清單存記錄側、反向現算。**non-additive，MUST bump**——依據是**鍵域的嚴格性，不是資料量**：`attachments` 元素鍵走 strict 驗證，未知種類導致整檔 quarantine，故縮減鍵域是 non-additive。移除當下受影響資料為 0 筆，但那是巧合而非契約；當死碼移除而不 bump，會讓 refuse-if-newer 在下一次真的有資料時失效。見 [store-format.md §2.4](docs/store-format.md) |
| format 10 | **person `names` 巢狀化（`authorized`／`variant` 分區）＋ `id` 改為獨立 v4 UUID**（#227／#241）：子集關係從 runtime 驗證變成結構性事實（分區不交、共同書寫系統唯一仍是 runtime 驗證）；`id` 與 key 徹底脫鉤——單一來源事件發放、永不由名字重算，867 筆既有記錄一次性換發。**non-additive，MUST bump**——舊 binary 讀巢狀 `names` 是整檔 quarantine；新 binary 讀舊平面 `names`／頂層 `authorized` fail-closed 指向 `akashic migrate-person-identity`（dry-run 預設）。org 刻意**不**巢狀化（不對稱是設計）。見 [store-format.md §3.1](docs/store-format.md) |
| format 11 | **新一級形狀 `venue:`（發表載體——期刊／會議／出版社）＋ entry 的 `venues:` 二態 ref 邊**（#304）：`type` 封閉三值（journal／conference／publisher，未知值整檔拒讀）**——當時的值域；#324 已改為六值，見下一列**、`names` 是刊名沿革 timeline（同 org 模式）；`venues` 元素 `.key`（已歸戶）／`.literal`（未歸戶，匯入端唯一產物——literal-first）。文章編年 list 由反向邊現算，venue 記錄不存清單。**non-additive，MUST bump（實測依據）**——format-10 binary 讀 `venue:` 是整檔 quarantine（與 format 6 同型）；entry 的 `venues:` 在舊 binary 落 tolerant-preserve，但 ref 邊「保留而不解讀」＝反向查詢靜默漏資料，併入同一 bump。回填走 `akashic migrate-venues`（dry-run 預設、只加不改、idempotent）；升級順序＝全 binary 升 v11 → migrate → validate → 手動 bump。見 [store-format.md](docs/store-format.md) format 對照表 |
| format 12 | **`Author` 三態（新增 `organization`）＋ `VenueType` 改以 APA7 §9.23–9.33 為判準**（#323／#324）：團體作者終於能歸戶（先前只能永遠停在 `.literal`——升格的唯一路徑是 person key，而團體不是人）；`journal` → `periodical`（APA7 的 periodical 涵蓋 journal／magazine／newspaper／newsletter／blog，索取同一組欄位），另加 `database`／`socialMedia`／`website`。**non-additive，MUST bump（實測依據）**——format-11 binary 讀含 organization 作者的 entry 是整檔 quarantine，而 `query` 回 **rc=0 且該筆消失、無訊息**；`VenueType` 對未知值整檔拒讀。write gate 對 format < 12 兩者皆拒寫。**`Entry.type` 的封閉列舉（#325）不在此列**——它對舊 binary 是 additive，安全性由兩階段部署順序承擔。見 [store-format.md](docs/store-format.md) format 對照表 |
| format 13 | **識別碼能攜帶來源**（#394）：`venue.issn`／`organization.ror`／work 的 `doi`・`pmid`・`isbn` 進 `ProvenanceReference` 的可附著欄位集合；`Entry` 新增 `references`；venue 補上先前**完全沒有**的附著驗證。**non-additive，MUST bump（實測依據）**——對 format-12 binary 實測三種新形狀行為**不同**：organization 帶 `field: ror` 的 reference 是**整檔 quarantine**，而 venue 的 `field: issn` 與 work 的 `references:` 都**照常載入**（落 tolerant-preserve）。只有一種是硬觸發，因為附著驗證原本只有 person 與 organization 有。後兩者併入同一 bump 的理由沿用 format 11 對 `venues:` 的裁決：保留而不解讀的 reference 不會被附著驗證，可以指向一個不存在的值而沒有人發現。**write gate 只擋 reference、不擋識別碼欄位本身**——後者是 additive，設閘會讓 `migrate-identifiers` 在 bump 之前跑不動。見 [store-format.md](docs/store-format.md) |
| format 14 | **venue 的異寫法有自己的格子**（#422）＋ **`paginated` 三態判定**（#406）：`names` 的型別是時間軸、spec 宣稱它模型化刊名沿革，而實測 405 筆 venue——多名字的 **35 筆裡帶時間欄位的 0 筆**，內容全是同一本刊的不同寫法。**一個欄位在說謊**。拆出 `variant` 分割（與既有 `authorized` 並列的頂層清單），時間軸 Requirement 保留但收窄（variant 不得帶時間）。同輪加 `paginated`：決定「這篇有沒有頁碼」的是**刊物的性質**（article number 制 vs 傳統紙本），而四個外部來源全部量過、全部不提供頁碼。**`nil` 不得折成 `false`**——「未判定」是 APA7 下限**仍該報缺**的狀態。**對舊 binary 是 additive，仍 MUST bump**（#422 verify R1 更正：第一版寫 format-13 binary 會整檔 quarantine，與程式相反——`VenueYAML.decode` 走 tolerant-preserve，原樣保留而不解讀；format 13 那列對同一層的 `issn:` 早就實測過）。bump 的理由沿用 format 11／13 的既有裁決：「保留而不解讀」對一個分割標記等於舊 binary 安靜地把異寫法當一般名字顯示、把已判定的 `paginated` 當從未判定——不會大聲失敗，所以更需要 marker 讓 refuse-if-newer 出聲。遷移走 `akashic migrate-venue-variants`（乾跑逐筆過目，35 筆可行；帶時間的一律不動；**`authorized` 為空的不分類、交人先指定**——補集規則對空的 authorized 會把每個名字都標成自己的異寫，#422 verify R1 實測三筆）。見 [store-format.md](docs/store-format.md) |
| format 15 | **`paginated` 的判定 reference**（`field: paginated` 的 judgement，#406 R1 verify）：format 14 只涵蓋**頂層**欄位，判定 reference 是之後引入的 vocabulary——format-14 binary 的 venue 附著驗證沒有這個 case，讀到會走封閉 default → **整檔 quarantine**，且輸出**與「判定從未發生」不可分辨**（R1 在完整 store 副本量測：406 venue 靜默掉到 373、rc=0）。write gate 對頂層 `paginated` 值在 format < 14 拒寫（那是 format 14 的鍵域）、對 `field: paginated` 判定 reference 在 format < 15 拒寫——兩個閘分開（#422 verify R2 更正：先前此處把兩者都寫成 < 15）；**marker bump 前不 push store repo**（gate 讀 marker 不讀 binary 能力）。見 [store-format.md](docs/store-format.md) |
| format 16 | **work 側的拆分記錄**（`field: authors` 的 judgement reference，#450）：`split-author`（#443）把黏著的作者 literal 拆成 N 段，先前是作者位變更家族裡唯一**不可逆且沒有 store 記錄**的一腿——原文與理由只進報告，un-split 所需資訊只在 git 歷史。#450 裁決：判定持久化到 work 側 `references`（value＝被拆掉的原 literal 逐字、statement `拆為 ⟦a⟧ ⟦b⟧：理由` 走 `SplitRecordValue` 單一解析器、空 rests-on 經 `firstOrderRulingFields` 放行），與作者位改寫在**同一次**寫入。這是第 15 條邊值域第一次承載**已退役的值**：不驗 value 在場，一致性條件是「各段至少一段仍是作者位」，由 health 報 warning（各段全不在／持有已退役 literal 的孤兒 verdict）而非 decode 拒收。**non-additive，理由同 15**：format-15 binary 的 `Entry` 附著驗證沒有 `authors` case → 封閉 default → **整檔 quarantine**、rc=0。write gate 對 format < 16 拒寫帶拆分記錄的 entry，`splitAuthors` 在任何寫入前對全部計畫過閘。#443 已拆的 4 筆不回填。**升級前置**：CLI/MCP/App 全升 v16 世代 → 手動 `format: 16` |
| format 17 | **work 側的移除記錄**（同一格 `field: authors`，statement `移除：理由`，#457）：`Author` 的三態都假設那一格背後有一個作者，而 PsycInfo 的 `No authorship indicated`（實測 21 筆）不是——它在 `.bib` 裡被拆成 `AUTHOR = {indicated, No authorship}`，一個被捏造出來的人。在此之前沒有任何面到得了 0 個作者位。移除記錄與拆分記錄住同一格、由 statement 前綴分辨（value 語意相同：**已退役的作者 literal**，差別只在退役後剩幾段）。**non-additive**：format-16 binary 的 `authors` case 存在，但只認得拆分文法 → parse 回 nil → 一樣整檔 quarantine 且 rc=0。**升級前置**：CLI/MCP/App 全升 v17 世代 → 手動 `format: 17` |
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
工具面：**31 tools**（實測 `grep -oE 'Tool\(name: "akashic_[a-z_]+"' Sources/akashic-mcp/Server.swift | sort -u | wc -l`；逐格裁決見 `.claude/rules/mcp-cli-parity.md` 的封閉列舉）——9 讀（search/get_entry/relations/graph/export/people/person/doctor/divergences 列歧異）+ akashic_files（list/use——多檔案切換）+ akashic_libraries（list/create/add/remove）+
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

> **掃描面含 `AkashicApp/Sources`**（#161）。它不在 `Sources/` 底下（XcodeGen 專案，
> `Package.swift` 對它零引用、`swift build` 從不編譯），所以枚舉掃不到，是**明列**進去
> 的；而它正是**真正的 SwiftUI 顯示層**——`Sources/AkashicAppKit` 只差三個字，是 error
> 型別所在的 library。#158 曾把目錄加進掃描而三條全綠：`isSink` 認不得 `Text(` /
> `Label(` / `.navigationTitle(`。**加目錄不等於加保護，判準要一起改。**
>
> **四種 error 型別有三種消毒政策**（#162），守衛先前對三者一視同仁：
>
> | 型別 | `errorDescription` 消毒 payload | throw 站點要消毒 |
> |---|---|---|
> | `StoreIOError` | ✅ | ❌ 會雙重跳脫 |
> | `StoreYAMLError` | ❌（策略是 sink-side） | ❌ 由輸出端 sink |
> | `ServiceError` | ❌（`.invalid` 直接回 `why`） | ✅ |
> | `StoreVersionError` | ❌（`path`／`line` 原樣內插） | ✅ |
>
> sink-side 策略靠的是**每個介面有一個消毒出口**。CLI 早有（`CLI.swift` 的單一
> `main()`，明寫「逐條補 error 站點是假性閉合——新增的 case 又會裸奔」），**MCP 從沒
> 拿到同樣處置**——`Server.swift` 的 per-tool catch 直到 #162 才補上。那個缺口讓約 90 個
> 折行 throw 站點的 payload（檔案裡的未知欄位名、YAML 鍵、值原文）逐字進 LLM context。
>
> **App 是第四個介面，而它的 sink 政策與 `StoreYAMLError` 那一列相反**（#162 verify
> 182-3）：`Text(errorMessage ?? "")` 那六處**不消毒**，它依賴「每一種 error 型別的
> `errorDescription` 自己消毒」。今天兩者不相撞，靠的是**路由上的巧合**——所有 decode
> 剛好都在 `load()` 的 quarantine 迴圈裡，不是一條被強制的不變式。**所以：
> `StoreYAMLError` 不得以 thrown error 進入 App 路徑。** 任何人在 App 的動作路徑上加
> 一個直接 decode（例如仿 `UpdatePerson` 做一個 App 端的部分更新），洩漏就回來了，
> 而守衛看不見（那六處無插值、無 token——正是上面那條「無插值裸綁」的機制）。
>
> 表格加上第四列 `StoreVersionError`（`errorDescription` ❌／throw 站點 ✅）：它的 `path`／`line` 原樣內插，政策與 `ServiceError` 同一列。
>> **「無插值的裸綁」已補上**（#193；曾是 #161 verify 181-3 記錄的全盲區）。原本
> `scanViolations` 的候選運算式**只**來自 `\( … )` 插值與 `"key": value` 的 dict 值，
> 一行顯示呼叫若兩者皆無就**抽出零個運算式**——`isSink` 判成 true 也沒有東西可檢，
> 於是 `swiftUISinks` 那九個**只在「該行剛好也有插值」時才起作用**，`Text(entry.title)`
> 這種最常見的形狀看不見。現在多一個抽取器 `bareChains`：對 SwiftUI sink 取括號配對
> 的引數，再拆成 `foo.bar` 的**成員存取鏈**。
>
> **拆成鏈而不是整個引數**，因為整條會踩共現洞——`Text(entry.title.isEmpty ? entry.citekey : entry.title)`
> 整條含 `.isEmpty`，既有豁免會把 `entry.title` 一起放掉，而那正是 #193 的行為證明。
> 拆鏈之後豁免只作用於它自己那一條。`displaySafe( … )` 的內容先**塗白**（不是整段
> 跳過，那會重演同一個洞）。
>
> 行為證明（verify-181-182 的兩個 mutation，過去全綠）：`EntryViews.swift:13` 與
> `AdjudicationViews` 的 OrphanView 換回裸欄位 → 現在各自變紅（`entry.title`、
> `item.file`、`item.reason`）。
>
> **仍未涵蓋**：`print(foo.title)` 這種**非 SwiftUI** 的裸綁（同機制、不同面；掃描面
> 上目前零命中，但那是實測不是保證。擴到全部 sink 會讓 error sink 的每個裸引數
> 無條件入列——`isErrorSink` 繞過 token 比對——屬另一個量級的分類工作）。以及下面的
> **裸變數名**，那是**不同的機制**（token 清單抓不到，不是判準不參與）。
>
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

### 改 code 之前值得知道的一條

**新成員不得插進既有 API 的 doc comment／attribute 與其宣告之間。** 那會讓兩份文件
對調——被孤兒化的 doc 掛到新成員頭上（對它每一句都是假的），原本的宣告零註解。
實際發生過**七次**，其中一次是在寫下這條紀律的同一個 commit 裡，而第七例是在
寫下前六例的那一週被獨立驗證席找到的——**那張表在提出時就已經不完整**。

[docs/design-principles-and-philosophy.md §16](docs/design-principles-and-philosophy.md)
是它的**正典計數**——完整清單、以及三次機械化嘗試的誤中量測（19 / 78 / 26，
掃 5128 個宣告，全部太吵所以沒 ship）。原始碼裡的四處引用都指向那裡；**不要在
原始碼裡各自重新計數**，那正是它一直過期的原因（每個數字在寫下的當時都對，之後
再也沒人同步）。review 時的具體動作：**看新成員的上一行是不是別人的 doc。**

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

### `sources/index.jsonl` 該不該進版控（#262 裁決一）

**裁定：`index.jsonl` SHOULD 被追蹤；blob MUST NOT。** 兩者不同類，而先前是被**同一條整
目錄規則連帶**涵蓋的。

判準來自 store 自己 `.gitignore` 的註解（原文）：

> 判準不是 repo 公開/私密（private repo 的內容仍在 GitHub 伺服器上），而是
> 「**原始第三方材料**」vs「**自己加工過的衍生產物**」。

`index.jsonl` 的條目是 digest ＋ `origin` 敘述 ＋ `retrieved` ＋ `media-type` —— **全部是
自己寫的指涉紀錄**，不含任何第三方位元組。依那條註解自己的判準，它屬**可追蹤**的一側。
它被排除只是因為規則寫成了容器（`sources/`）而非對象。

#### issue 原本提議的寫法**無效**（實測發現）

```gitignore
# ❌ 無效：git 無法 re-include 已被排除目錄底下的檔案
sources/
!sources/index.jsonl

# ✅ 正確：排除目錄的**內容**而非目錄本身
sources/*
!sources/index.jsonl
```

git 的規則：*It is not possible to re-include a file if a parent directory of that file is
excluded.* 照 ❌ 那樣寫會**以為追蹤了但其實沒有** —— 靜默失敗。

#### 對承重閘的影響：**實測為零**

`SourceStore` 的 fail-closed 是**逐一路徑**問 `git check-ignore -q`。在暫存 repo 實測：

| `.gitignore` | blob（`sources/ab/<62>`）| `index.jsonl` |
|---|---|---|
| `sources/`（現況）| **已排除** | 已排除 |
| `sources/` ＋ `!sources/index.jsonl` | **已排除** | 仍被排除（提案無效）|
| `sources/*` ＋ `!sources/index.jsonl` | **已排除** | **未排除** |

blob 仍被涵蓋（`sources/ab` 這個子目錄被排除，其下內容連帶排除），所以**放寬承重閘的風險
不存在** —— 前提是用正確寫法。診斷把這列為「唯一真風險」且要求實測，實測結果是否證。

### `retrieved` 的格式契約（#262 裁決二）

**`retrieved` MUST 是 ISO 8601 且帶 UTC offset**（`2026-08-19T14:30:00+08:00`）。

裸日期被讀成什麼時刻取決於**讀的人在哪個時區**，而 provenance 的用途正是「在什麼時候看到
的」—— 一個會隨讀者漂移的時刻答不了那個問題。

**加了時分秒不等於加了時區**：全域規則記載的踩坑實例正是 `2027-02-01T00:00:00`（無 offset）
被當成 UTC，實際生效時間差 8 小時。

#### 契約**刻意不**做成 decode 的硬閘

實測 store 的 `index.jsonl` 有 **7 條** `retrieved`、**全部是裸日期**。做成硬閘會讓那 7 條
把整個 store 鎖在門外 —— **用一條新契約把既有資料擋掉**，而那些資料本身沒問題（只是格式舊）。

所以契約先以**可驗證的函式 ＋ 文件**存在（`RetrievedFormatContractTests`），硬閘等回填完成
後再上。**退場條件是可執行的**：

```bash
python3 -c "import json; [print(json.loads(l).get('retrieved')) for l in open('$HOME/.akashic/sources/index.jsonl')]" | grep -cv '+\|Z'
```

回 0 即可上硬閘。而 `testBareDateStillDecodesForNow` 釘住「現在還不能上」—— 沒有它，日後
有人「順手」接上就會鎖門，而那個後果在測試裡看不到（測試用的是自己造的資料，不是真 store）。

### 「被收錄於」這條邊：暫不新增，但觸發條件是可執行的（#339）

一章收錄於哪本編著，目前靠 `fields.booktitle` 的**純量字串**。同一本書被多章引用時，
在 store 裡是多個彼此無關的字串 —— 問「這本書收錄了哪幾章」沒有機制答得出來。

**方向不是問題，規模才是。** 套
[兩步提問](docs/explainers/which-side-does-a-relation-live-on.md)，兩步同向指向**章側**
（那本書還不存在時只有章側記得下來；刪書則章仍記著字串、刪章則事實消失）—— 也就是
`fields.booktitle` **已經在對的那一側**。剩下的問題只是「純量該不該升格為 ref」。

**裁決：暫不升格**，三個理由：

1. **實測 6 筆**，其中只有 1 個容器被共用（`The Stanford Encyclopedia of Philosophy` ×3）。
   新增一條封閉列舉的邊要付：封閉列舉表＋merge 閘＋反射守衛計數＋YAML 編解碼與封閉鍵域＋
   `resolve-*` 一族＋index 反向查詢＋literal 歸零 campaign＋parity 裁決 —— **兩個中型
   issue 的量級**。
2. **APA7 下限已達**：`INCOLLECTION` 的必要欄位含 `BOOKTITLE` 而它在場。這不是破底，
   是**表達力**問題。
3. **venue 那條路已被 #324 關掉**：不得把 edited book 塞進 `VenueType`。

#### 「暫時」不會變成「永遠」——觸發條件寫成可執行的

```bash
python3 - <<'EOF'
import glob, io, re, collections
uncov = collections.Counter()
for f in glob.glob('/Users/che/.akashic/entities/*.yaml'):
    s = io.open(f, encoding='utf8').read()
    m = re.search(r'^  booktitle: (.+)$', s, re.M)
    if m and not re.search(r'^venues:\n- key: ', s, re.M):
        uncov[m.group(1).strip()] += 1
print(sum(uncov.values()), max(uncov.values()) if uncov else 0)
EOF
```

**≥ 20 筆**或**單一容器被 ≥ 5 筆共用**即重新裁決。2026-08-23 實測 **11 筆／最大 ×1**。

> **這條指令換過一次（#409）**：原本數的是「帶 `booktitle` 的記錄」，而 `lossless-intake`
> 規定來源欄位不刪 —— 容器改由 venue 承載之後那個數字**完全不會下降**（實測仍是 31）。
> 現在數的是「仍只有純量字串、沒有任何 ref 承載容器」的記錄。

第二個觸發（#354 讓 `INREFERENCE` 的必要欄位含 `BOOKTITLE`）**已消解** —— 見下方那則。

> **順帶記一個相鄰發現 —— 已於 2026-08-23 由 #409 消解**：`WorkType.wikipediaEntry` 的名字
> 過窄 —— 它實際承擔的是「參考工具書中的條目」，而 SEP 不是 Wikipedia。
>
> #409 把它改名為 **`referenceWorkEntry`**（rawValue `reference-work-entry`）。理由是它自己的
> 三個下游對照沒有一個說 Wikipedia：APA7 §10.3「Entries in **Reference Works**」／biblatex
> `INREFERENCE`／CSL `entry-encyclopedia`。改名後 3 筆 SEP 一併改型別、走進
> `booktitleCarrierTypes`、歸戶到 `stanford-encyclopedia-of-philosophy` venue —— 實測「仍只有
> 純量字串」從 **14 筆／最大 ×3** 掉到 **11 筆／最大 ×1**。

#### 守衛守的是**前提**不是結論

不存在的邊測不出來，所以 `ContainerRelationDeferralTests` 釘住的是**當初據以裁決的事實**：
`booktitle` 仍是自由字串、`Entry` 沒有容器語意的成員（**用反射列名，抓得到任何名字**）、
`VenueType` 沒有 edited book 值。

任一前提不再成立 → 紅 → 提醒重做裁決。這與 #315 的
`testStoreDirectoryForMembershipIsStillNamedLibraries` 同形。

### `bootstrap-venues`：缺的是鏈條的第一環（#367）

venue 域先前**沒有批次建檔的路徑**。person 與 organization 都有，venue 沒有：

| 域 | 從 literal 批次建實體 | 單筆建檔 | 消歧 | **歸錯了怎麼辦** |
|---|---|---|---|---|
| person | ✅ `bootstrap-people` | ✅ `add-person` | ✅ `resolve-people` | ✅ `resolve-divergence`（合併＋全庫改寫）|
| organization | ✅ `bootstrap-organizations` | ✅ `add-organization`（MCP）| ✅ `resolve-organizations` | **❌ 無** |
| venue | **❌ 先前無** → ✅ `bootstrap-venues` | ✅ `add-venue` | ✅ `resolve-venues` | **❌ 先前無** → ✅ `--repoint` / `--demote`（#418）＋ ✅ `resolve-divergence`（#553）|

**最後一欄是 #418 補的，而它同時揭露了 organization 也缺這一格。**
`literal-first-then-key` 的整套論證建立在「漏（literal 待消歧）可逆，誤（錯誤歸戶）
不可逆」這個不對稱上，並為它提供退路。**venue 於 #553 補齊**（record↔record 的攣生
合併，與 `--repoint`／`--demote` 是不同的東西：後兩者改的是**邊**，前者刪的是**記錄**）；
`resolve-divergence` 現在接得住 person／work／venue，organization 仍拒。

> **這一段在 #553 close 的 doc-sync sweep 抓到過一次，而它抓到的不只是文件。**
> 原文逐字引用著錯誤訊息「本版的消歧只處理 person 與 work」——去核對才發現
> **程式那一則也沒改**：venue 加進支援值域了，訊息還在說舊值域，而今天唯一觸發得到
> 它的是 organization，所以那是一句對著使用者說的假話。修法不是改字串，是讓訊息
> **從實際支援的清單生成**（`DivergenceResolveError.mergeableShapes`），並用
> `testUnsupportedShapeMessageNamesTheRealDomain` 釘住清單與分支一致——手寫的值域
> 會再分岔一次，而它分岔時不會有任何東西報錯。

寫這張表時我先填了「organization ✅ 同上」，**去查才發現是假的**——那正是本批
（#407）在管的形狀，出現在為它自己寫的文件裡。venue 那格已由 #418 補上；
organization 那格仍空，追蹤在 #418 的討論。

venue 的兩個旗標各對應一種錯誤：

| 錯誤 | 退路 |
|---|---|
| 邊指到**錯的** venue | `resolve-venues --repoint <citekey:venueIndex:newKey>` |
| 誤升格，而**現有的 venue 都不對** | `resolve-venues --demote <citekey:venueIndex>` |

`--demote` 的原字串**從 verdict 逐字取回**（`resolution-confirmed` 的 value 帶著它），
所以是無損的；取不到就拒絕，**不拿 venue 的顯示名頂替**——顯示名不是那筆記錄原本
寫的字（WoS 的 `PSYCHOMETRIKA` vs 正式刊名 `Psychometrika`），頂替會安靜改寫書目資料。

```
migrate-venues ──→ 803 筆 literal ──→ ??? ──→ venue entity ──→ resolve-venues
     ✅ 已做            ✅ 已有        ❌ 缺        ❌ 0 個         ✅ 已實作但空轉
```

**每一個零件都正常** —— `migrate-venues` 跑完回填了 803 筆、`resolve-venues` 存在且可執行、
`akashic venues` 也正常回應（回「0 個」）。缺的是它們**之間的一段**，而現有的機械稽核抓不到
它：`mcp-cli-parity` 查的是「每個命令有沒有被裁決」，查不到「**某個域少了一個命令**」。

發現它的路徑值得記：`resolve-venues` 的 dry-run **回零候選** —— 那不是 bug，它的工作是拿
literal 去比對**既有的** venue entity，而 entity 有 0 個。所以「消歧一次都沒跑過」不是使用
怠惰，是**結構上跑不出東西**。

#### `VenueType` 從哪來 —— 讀它從哪個欄位來，不是猜

`VenueType` 是封閉值域（#324），批次建檔必須給每個 venue 一個值。

答案是 **`VenueDerivation.literals(for:)` 的來源欄位**：`journaltitle` → `.periodical`、
`booktitle`（僅會議發表）→ `.conference`、`publisher` → `.publisher`。literal 從哪個欄位
來，那個欄位的**意思**就決定了載體種類 —— 這是讀出來的事實，不是啟發式。

> **`journaltitle` 對到的是 `.periodical` 不是 `.journal`。** #324 把 journal 併進
> periodical（APA7 的 periodical 涵蓋 journal／magazine／newspaper／newsletter／blog，
> **索取同一組欄位**）。**biblatex 的欄位名與我們的值域不是同一套詞彙**，照字面對映會錯。

實測（937 筆全庫）：**402 個候選**、**5 筆產不出 ASCII key**（純 CJK：`天下雜誌出版`／
`管理學報`…，明列不靜默丟）、**0 個型別衝突**。

大小寫變體的分組正確：`Journal of Personality and Social Psychology ≡ …Social psychology ≡
…social psychology` 收成一筆而**三個寫法都留著**（WoS 全大寫形同理）—— 只留一個寫法的話，
下次遇到另一個寫法又會重新分割一次。

#### 一個零實例守衛（`zero-instance-guards` 第 4 列）

同名來自**不同種類**的來源欄位時**不建檔，交人裁**。目前零實例，但它與前三列的理由不同：

> 前三列的代價都落在「看不見」；這一列的代價是**看得見但看起來是對的**。`VenueType` 決定
> 哪些欄位存在，所以取錯 type 不是標籤錯而是**整組欄位需求錯** —— 而那筆記錄會通過所有
> 檢查，因為它確實滿足了（錯的）那一組。

#### 稽核自己的脆弱，被同一個 PR 抓到

`DestructiveTargetGateTests`（#298）掃的是**寫死的兩個檔名**。新命令住在新檔案裡，於是三條
稽核同時紅 —— 而紅的原因不是它們要抓的缺陷，是**稽核自己的涵蓋範圍**。

這與 `mcp-cli-parity` 記載的教訓同型（第一版 regex 只命中 11/30，該檔的結論是「**稽核程序
自己也要被稽核**」）。已改成掃整個 `Sources/akashic/` 目錄：**寫死的檔名清單與寫死的 regex
是同一種脆弱** —— 它們在新增東西時失效，而新增正是稽核最該發揮作用的時刻。

### 「library」承載三義，而最危險的一對是相鄰的（#315）

| 介面 | 意思 | 值域 |
|---|---|---|
| **CLI `--library`** | **開哪個 store** | 檔案系統路徑 |
| **MCP `library` 參數** | store **內**的 membership 分類 | `StoreKey`（`libraries/` 的 key）|
| registry 的 `files:` 鍵 | registry 中的 store 條目 | registry key |

前兩者**同名、鄰接、不同型別、不同語意，而錯用不會報錯** —— 只會 scope 到錯的東西，然後
回一個看起來完全合理的空集合或子集。這種缺陷不會被任何測試抓到，因為兩邊各自都「正確地」
執行了被要求的事。

**危害已經實體化，不是假設的。** #315 量測時發現**同一個 skill 的兩份文件**分別用了兩個
意思，而沒有任何一處提醒讀者它們不同：

- `plugin/skills/akashic-bootstrap/SKILL.md` → `akashic_person(key: …, library: "sinica")`（membership 義）
- `.../references/writing-to-the-store.md` → `akashic doctor --library <暫存路徑>`（store root 義）

現況採 **option (2)：保留名稱、強化描述**（零成本下限）。四處都明寫「它不是什麼」：
CLI help、兩個 MCP tool 的 schema、兩份 skill 文件。issue 指出這個選項的弱點是
「保證只來自文字」—— `LibraryTermDisambiguationTests` 把那個保證變成機械的。

#### 一個反直覺的方向（若日後裁定改名）

issue 的 option (1) 預設要改的是 **MCP 參數**。但 store 自己的目錄叫 **`libraries/`**
—— membership 那個意思才是 store 的**原生詞彙**，CLI 的 `--library`（store root）反而是
異類。

所以若裁定改名，該改的很可能是 **CLI 旗標**而不是 MCP 參數 —— 而那是使用者手打的介面、
橫跨 42 個 subcommand，成本高得多。`testStoreDirectoryForMembershipIsStillNamedLibraries`
把這個分析的**前提**（目錄名）釘住：目錄哪天改名，那條會紅，提醒重新檢視整個結論。

### APA7 的合法形式不得被報成缺漏（#350）

三類 APA7 認可的形式先前被報成缺欄位。它們的處置各不相同，而**分界線是同一條**：

| 類 | 形式 | 處置 |
|---|---|---|
| 1 | **編者填作者位置**（編著書只有 `EDITOR`）| 加一條替代滿足規則 |
| 2 | **合法的無日期**（APA7 印 `(n.d.)`）| 新增 sentinel `date: n.d.` |
| 3 | **合法的無個人作者**（網頁／參考工具書條目）| **已由 #353／#354 結構性消除** |

#### `date` 的三態（第 2 類）

`date` 先前只能表達兩種狀態，而中間那一格是缺的：

| `date` | 意思 |
|---|---|
| `"2020-04-01"` | 有日期 |
| **`Entry.noDateSentinel`（`"n.d."`）** | **查過了，這筆作品確實沒有日期** |
| `nil` | **還沒查** |

把「確實沒有」折進 `nil` 正是 `lossless-intake` 執行細節 4 禁止的折疊。實測：store 有
**20 筆**確認無日期的記錄，而它們的 **citekey 自己就寫著** ——`anonndbbs`／`anonndbentry`／
…／`mediandentry`（Zotero 快速入門指南）。citekey 產生器把 `nd` 編進鍵裡，但**模型讀不到
那個資訊**。

**為什麼是 sentinel 而不是另一個布林欄位**：`dateIsAbsent: Bool` 會讓
「`date: 2020` ＋ `dateIsAbsent: true`」這個矛盾寫得出來。sentinel 佔用同一個格子，
矛盾在文法上不存在 —— 同 `ThesisFacts.Availability` 用關聯值的理由。

**為什麼字面值是 `n.d.`**：那是 APA7 自己的詞，也是依賴自己認的形式
（`APACitationParser` 對 `dateStr == "n.d."` 的處理就是「無日期」）。

**store 與 `.bib` 的表達方式刻意不同**：store 裡是一個值，`.bib` 裡是**欄位缺席**
（biblatex-apa 對缺席的 date 印 `(n.d.)`）。store 要能區分「查過沒有」與「還沒查」，
`.bib` 不需要 —— 它只需要印對。

#### 編者填作者位置（第 1 類）

APA7 §10.2 的 template 是 `Editor, E. E. (Ed.). (Year). Title. Publisher.` —— 編者就在
作者位置。所以一筆只有 `EDITOR` 的編著書**不是缺作者**。

值域刻意窄（只有 `BOOK` 與 `INCOLLECTION`），且**不得依性質相似類推**：期刊文章的編者
**不**填作者位置（那篇文章的作者就是作者），`PRESENTATION` 同理。兩條反面測試釘住這一點。

#### 同一條界線，第三次用到

| | 動作 | 需要什麼才能裁決 |
|---|---|---|
| **#359** | **反轉**依賴刻意設定的 required／recommended 判斷 | ch10 的證據 |
| **#354** | **補上**依賴沒有意見的型別 | 手冊直接寫著值 |
| **#350** | 不動任何欄位的必要性，只承認 APA7 允許**另一個欄位填同一個位置** | 手冊的 template 直接寫著 |

三者都是「依賴的表不夠用」，但只有 #359 需要人來裁決誰對。

#### 誠實邊界：機制到位，資料未標記

`n.d.` sentinel 讓那 20 筆**可以**被正確表達，但它們在 store 裡目前仍是 `date` 缺席
（＝還沒查）。標記那 20 筆是**資料工作**，不在本次範圍。所以全庫的 `[ERROR]` 數字
（101）沒有因本次改動而下降 —— 下降會發生在資料標記之後。

### 必要欄位補充表與它的退場守衛（#354）

`INREFERENCE`（`referenceWorkEntry` 送出的型別；#409 前叫 `wikipediaEntry`）在依賴的**兩張表裡都沒有** ——
`allEntryTypes` 認得它、`classifySection` 算得出 10.3，但沒有必要欄位。所以 #352 之後那
14 筆維基條目變成 unchecked：假陽性消失了，代價是完全不被檢查。

`BibExport` 因此有一張**暫時的**補充表，補依賴**沒有意見**的型別。它滿足
[`no-compat-fallback`](.claude/rules/no-compat-fallback.md) 對例外的三條要求：

| 要求 | 怎麼滿足 |
|---|---|
| 不住 default 位置 | 具名的補充表；`requiredFields(for:)` 明確地**先問依賴、再問補充表** |
| 寫下退場條件與量測 | 「當 `APADataModel.requiredFields["INREFERENCE"] != nil` 就刪」——`testSupplementOnlyCoversTypesTheDependencyLacks` 會在那一刻變紅 |
| 退場即刪 | 那條測試的訊息直接寫「請刪掉那一列」，不留著當保險 |

**值從哪裡讀出來。** APA7 §10.3 的參考工具書條目（例 49 維基百科）：
「條目名。(年, 月 日)。In《工具書名》。URL」—— **條目名佔作者位置**，所以 `AUTHOR` 不是
必要的（那正是 #352 改對映的理由）；工具書名（`BOOKTITLE`）是必要的。同節另有帶團體作者
的例子，所以 `AUTHOR` 是 **recommended 而非禁止**。

**為什麼是本地補充而不是改上游。** 上游是同一個 owner 的 repo，但**它完全沒有 Tests
目錄** —— 在一個沒有測試基礎設施的**共用** canonical library 裡加必要欄位語意，會讓多個
consumer 的行為改變而沒有任何守衛，比一個自我刪除的本地補充更糟。

這也是本表與 **#359** 的分界：#359 要**反轉依賴刻意設定的值**（`EVENTTITLE`
required ↔ recommended 是一個判斷），本表只**補上依賴沒有意見的型別**。前者需要 ch10 的
證據來裁決誰對，後者的值手冊直接寫著。

**實測**（937 筆全庫）：`unchecked` **14 → 0** —— 每一筆都被檢查過了。error 78 → 101，
`+23` 拆開是 **14 筆真缺漏**（維基條目缺工具書名）＋ **9 筆是 `anonnd*`**（citekey 自己
寫著 `nd`，合法無日期，屬 #350 第 2 類的量尺缺口）。

**一個測試側的分岔，順手修掉。** golden 矩陣的 `isChecked` 原本自己讀 `APADataModel`。
補充表一加，它立刻與受測者分岔 —— 而且**空洞地通過**：唯一受影響的型別沒有 fixture，
所以那條斷言對空集合為真。改成走 `BibExport.requiredFields(for:)` 同一個入口。這是 #353
剛消除的形狀在測試側重現：一個「以為在守某件事、其實在守自己那份副本」的守衛。

### APA7 完整性報告讀哪張表（#353）

`repos/biblatex-apa-swift` 有**兩張**必要欄位表，而它們對同一個型別會給出**相反**的答案。
`apa7Report` 原本用的是較舊、較粗的那張。

| | `BibValidator.requiredFields`（舊用） | `APADataModel.requiredFields`（現用）|
|---|---|---|
| 涵蓋型別 | 7 | **15** |
| 來源 | 手寫 | **`apa.dbx`**（biblatex-apa 的 LaTeX 資料模型）|
| `ONLINE` | 不在表內 → 整批 unchecked | `[TITLE, DATE]`，**AUTHOR 不要求** |
| `VIDEO`／`AUDIO`／`SOFTWARE`／`DATASET` | 不在表內 | 各為 `[TITLE, DATE]` |
| `PRESENTATION` 的 `EVENTTITLE` | **required** | 只是 recommended |

選 `APADataModel` 的理由不是「它比較大」，是**它比較權威**：值域來自 `apa.dbx`，而依賴
自己較新的路徑（`APARuleEngine.fix` 的 Phase 7）也在用它。

**實測效果**（937 筆全庫，三個階段）：

| | #340 開立時 | #352 後（修對映）| **#353 後（換表）** |
|---|---:|---:|---:|
| `[ERROR]` 條數 | 143 | 94 | **78** |
| distinct 記錄 | 97 | 71 | **76** |
| unchecked 筆數 | 12 | 26 | **14** |

`#353` 的 `−16` 拆開來是 **−25 ＋ 9**：25 筆 `EVENTTITLE` 降級成 warning（見下），
9 筆新納入檢查的 `ONLINE` 記錄**真的**缺 `DATE`（先前完全不被檢查）。

**兩個順帶消除的結構性風險**：

1. **手維護的鏡像沒了。** `apa7CheckedTypes` 原本是寫死的 7 個型別的 `Set`，doc 自己寫著
   「會隨 dependency 演進而過期」——而它就是那樣過期的。現在改成現算
   （`APADataModel.requiredFields[type] != nil`），漂移在結構上不可能發生。golden 矩陣側
   的同一份鏡像也一起刪掉。
2. **一條測試的偵測力被救回來。** `testExportSurfacesTypesNotCoveredByValidator` 原本用
   `.webpage`（→`ONLINE`）當「未涵蓋」的探針。換表後 `ONLINE` **有**表了，那條測試會
   繼續通過，只因為它斷言的那件事不再成立 —— 那是最壞的一種綠燈。改用 `.visualWork`
   （→`IMAGE`，目前確實不在表內的三個型別之一）。

**明寫的代價（#359）**：`EVENTTITLE` 的降級不是無害的。依 §10.5，會議發表的 source
element **就是**會議名稱 —— 沒有它那筆參考文獻印不出來，所以那 25 筆是**下限違反**，而
`hasErrors` 現在抓不到。資訊沒消失（`[WARNING]` 行照印），失去的是嚴重度分級的偵測力。
**刻意不在 Akashic 側把它加回 required**：那會製造第三張必要欄位表，而三張會各自分岔。

### 學位論文的三個一級事實：`thesis:`（#335）

APA7 §10.6 有**兩張** template，而差別不只是字串：

| | 未出版（例 64） | 已出版（例 65／66） |
|---|---|---|
| 方括號 | `[Unpublished doctoral dissertation]` | `[Doctoral dissertation, 機構名]` |
| 授予機構的位置 | **句末的 source element** | **標題後的方括號內** |
| source element | 機構名 | **典藏庫**（＋URL）|

所以 `fields.institution` 有值也不夠 —— **該把它放哪取決於「已出版與否」**，而那個事實
先前完全不可表達。這是下限違反（`apa7-is-the-work-floor`），不是美觀問題。

結構化欄位落在 `thesis:`（封閉鍵域，見 [store-format.md §2.1.1](docs/store-format.md)）。
三件維護時會用到的判準：

1. **為什麼是欄位而不是 `WorkType` 的細分值。** 規則的判準是「這個區分改變的是**索取哪組
   欄位**，還是只改變**渲染字串**」。學位別只改方括號內的字串（author／title／institution／
   date 一模一樣）→ 欄位。而「已出版與否」更直接：規則的「不進值域」封閉列舉第 1 類
   **逐字點名了「出版狀態」**。壓進類別的具體代價是笛卡兒積 —— 3 學位 × 2 狀態 ＝ 6 個值，
   而它們索取的欄位組只有兩種。
2. **兩個欄位都可缺，缺席＝未查，不得折成預設值。** 把缺席的 `availability` 當成
   `unpublished` 會渲染出 `[Unpublished doctoral dissertation]` —— 那是一個**可能為假的
   斷言**，不是缺資訊。實測 5 筆 thesis 的 `availability` 全部缺席。
3. **兩個「讓錯誤寫不出來」的設計。** `availability` 帶關聯值，所以「未出版卻有典藏庫」
   在文法上不存在（依 §10.6，未出版的論文必須直接向該校索取）；`ThesisFacts` 的 init 是
   **failable**，所以「兩個事實都沒有的事實物件」也不存在 —— 那個狀態的編碼是有損的，
   而 `EntryYAML.encode` 的語意自檢會拒絕寫出它（開發時實際撞到）。

**fixture 反過來修正了設計。** 原本要求 `published` 必帶 `repository`。ch10 的手冊例
65／66 揭露那是過嚴的 —— 它們是已出版（有典藏 URL）卻**沒有典藏庫名**的形狀，於是遇到
那種記錄的人只剩「丟掉已知事實」或「編造典藏庫名」兩條路，兩者都是 `lossless-intake`
禁止的折疊。放寬它**不弱化**真正要防的那件事（`unpublished` 仍然沒有帶 `repository` 的形式）。

**誠實邊界**：`degree` 匯出成 biblatex `type`（token 由依賴指定），但 biblatex-apa 對
「已出版 vs 未出版的學位論文」**沒有任何機制** —— §10.6 兩形態的**渲染**是上游缺口，
且本專案沒有 LaTeX 往返測試可驗。模型持有這個事實是下限要求；渲染保真度是另一件事。

### `WorkType` 的兩個下游對映必須互相同意（#352）

`WorkType` 同時宣稱兩件事，而它們**可以互相矛盾而沒有任何跡象**：

| 屬性 | 宣稱什麼 |
|---|---|
| `apa7Section` | 這個型別在 APA7 手冊 ch10 的哪一節 |
| `biblatexEntryType` | 匯出 `.bib` 時寫哪個 entry type |

關鍵事實：**`biblatex-apa` 自己也會從 entry type 反算 APA7 節**
（`APADataModel.classifySection`，邏輯來自 `apa.dbx`）。所以送出去的 entry type
**隱含**了一個節，那個節必須與我們自己宣稱的節相同。

送錯型別不只是欄位需求對不上——是**整筆參考文獻被當成另一個類別排版**，而那個錯誤在
`.bib` 語法層完全合法、在必要欄位檢查裡也可能通過。

`WorkTypeSectionAgreementTests` 用**依賴自己的分類器**釘住這件事。它的價值在於**不寫
期望值**：一般測試斷言「我期望 X」，而期望值是作者寫的，所以作者的誤解會一起寫進斷言；
這條守衛拿兩個獨立來源互相對照。實測（#352）：人工盤點出 4 個矛盾，守衛抓到 **8 個**。

#352 修掉的收窄（原註解寫「biblatex 無專屬型，REPORT 最近」——**那句話是錯的**）：

| `WorkType` | 舊 | 新 | 依賴算出的節 |
|---|---|---|---|
| `dataSet` | `REPORT` | `DATASET` | 10.4 → **10.9** |
| `software` | `REPORT` | `SOFTWARE` | 10.4 → **10.10** |
| `audiovisualWork` | `ONLINE` | `VIDEO` | 10.16 → **10.12** |
| `audioWork` | `ONLINE` | `AUDIO` | 10.16 → **10.13** |
| `visualWork` | `ONLINE` | `IMAGE` | 10.16 → **10.14** |
| `conferenceSession` | `INPROCEEDINGS` | `PRESENTATION` | 10.5（節本來就對，但欄位需求錯：要 `BOOKTITLE` 而非 `EVENTTITLE`）|
| `referenceWorkEntry`（#409 前 `wikipediaEntry`） | `INCOLLECTION` | `INREFERENCE` | 10.3（節本來就對；改的理由是消除假陽性，代價見 #354）|

**實測效果**（937 筆全庫）：`[ERROR]` 143 → 94、error 記錄 97 → 71。帳目對得上：
26 筆停止報錯 ＝ 14 筆變 unchecked（維基條目）＋ 12 筆變乾淨（有 `eventtitle` 的會議發表）。

**三節仍不同意，且刻意不修**（10.7／10.11／10.15）：那三節在 `apa.dbx` 的模型裡不是由
entry type 決定，而是由 entry type ＋一個欄位決定。送出那些欄位就能讓守衛全綠，但
`ENTRYSUBTYPE: Database record` 對一份不是來自 PsycTESTS 的量表**是假的**。裁決見 #355。

### 外部權威 fixture：APA7 手冊 ch10 的 golden 矩陣（#327）

`Tests/Fixtures/apa7-ch10/`（8 個 `.bib`、ch10 的 11 個節、**111 筆**）是 APA7 手冊的編號
範例，來源是 `che-axiom-systems` 的 `apa7-style` domain。它與其他 fixture 的**方向相反**：

| | 一般 fixture | 本批 |
|---|---|---|
| 誰寫的 | 我們 | APA 官方（手冊印出來的正確參考文獻）|
| 測試在驗 | 實作對不對 | **我們的模型夠不夠** |
| 紅燈的意思 | 程式壞了 | 手冊接不進來——是我們不足，不是它錯 |

這批 fixture 是 [`apa7-is-the-work-floor`](.claude/rules/apa7-is-the-work-floor.md) 那條規則
指定的驗收矩陣（「一筆 work 的資訊下限是能產出正確的 APA7 參考文獻」）。測的是**往返**：

```
fixture 的 BibEntry ──→ 我們的 Entry ──→ bibEntry(for:) ──→ BibValidator
       （手冊）          （受測的模型）      （匯出路徑）        （書目正確性）
```

中間那一步是重點——模型持有不了的東西會在那裡掉，然後 validator 報缺欄位。

**三件維護時會踩到的事**：

1. **fixture 是複製的檔案，不是抄成 Swift 陣列。** 第一批 10 筆是手抄的，改掉了：手抄會
   掉欄位（抄的人只抄他認為必要的），而且離開來源檔就再也對不回去。手冊編號直接編碼在
   citekey（`10.2:20` ＝ 節號:例號）——**不要改成連續編號**，那會把對映弄丟。
2. **例號不是整數。** 手冊有子例（`75a`／`75b`／…），111 筆裡 **42 筆**帶字母後綴。用
   `Int()` 解析會把它們整批**靜默**丟掉（第一版就是這樣只看到 69 筆而沒有任何錯誤訊息）。
3. **覆蓋率有結構性上界，且三張表把它釘住。** `BibValidator.requiredFields` 只涵蓋 7 個
   biblatex type，所以對映到 `UNPUBLISHED`／`ONLINE` 的 7 個節驗不出東西。矩陣不省略它們，
   而是斷言它們落在 `uncheckedCitekeys`：

   | 表 | 內容 | 它變紅代表 |
   |---|---|---|
   | `knownValidatorGaps` | 4 筆手冊例報 error 的具名原因（編者代作者／`n.d.`／無個人作者，見 #350）| 缺口被修好（刪列）或新缺口出現（裁決）|
   | `sectionsWithoutFixtures` | 來源無範例的 5 節（10.5／10.7／10.8／10.11／10.14）| ch10 有節既沒 fixture 也沒具名 |
   | `checkedBiblatexTypes` | validator 涵蓋範圍的鏡像 | 對方的涵蓋範圍變了 |

   三張表都用**精確相等**斷言。永遠紅的測試會被無視；精確相等讓紅燈永遠代表「有一件事
   變了」。這與 `uncheckedCitekeys`（#326）同一條紀律：不讓「沒被檢查」冒充「檢查過且乾淨」。

### 逐筆從 Zotero 補值：與 pull 刻意不同的第二種語意（#340）

`import-zotero` 是 **pull**：Zotero 是上游，`applyBiblatexFields` **整份替換** `fields`、
重設 `type`、覆寫未歸戶的 literal 作者。那個語意對「同步一個由 Zotero 維護的書目」是對的，
但用來修跌破 APA7 下限的記錄時，作用半徑是**整個 store**、而且會蓋掉人工補過的值。

`enrich-from-zotero`（CLI）／`akashic_enrich_from_zotero`（MCP）走另一條紀律——而自 #458 起它是
generic `enrich --from <file.json>`／`akashic_enrich` 的 **Zotero adapter**：add-only 政策只有一份
（`AddOnlyEnrichment`，住 AkashicCore），提案以 citekey 或 DOI 定位（DOI 命中多筆＝`ambiguous`、零寫入）、
雙摘要分鍵（`abstract-<lang>` → `abstract_<lang>`）、`sourceDigest` 只回顯不進 store：

| | pull | 逐筆補值 |
|---|---|---|
| `fields` | 整份替換 | **只加原本不存在的鍵** |
| `type`／`title`／`authors`／`venues`／`attachments` | 重設／可能覆寫 | **一律不動** |
| 作用半徑 | 整個 store | 呼叫端**逐筆指名**（`--citekeys`，無「全部」的寫法）|

**四類「沒補到」全部回報**（`unchanged` ＝上游也沒有／`noProvenance`／`zoteroMissing`／
`notInStore`）——「查過但上游沒有」與「根本沒查」必須分得開，折成同一個輸出正是
`lossless-intake` 執行細節 3 說的靜默形式，只是換到報告面。

對映邏輯**只有一份**：`plan` 借 `applyBiblatexFields` 算出 Zotero 會產生什麼，再從中只取
缺著的鍵。自己重寫一份對映＝兩份會分岔的規格。

**它解決的問題比預期的有趣**：issue 的前提是「store 沒有可用資訊，必然要外部查證」。
實測 73 筆有 `zotero_key` 的 error 記錄後，**35 筆的答案一直在 Zotero 裡**——只是
`fieldMap` 沒有 `encyclopediaTitle`／`meetingName`，於是它們走殘餘路徑以別的鍵名入庫。
**殘餘收集保證「來源給的都收」，但收進來的鍵名若不是 export 面認得的那個，下限仍然跌破。**

### 補欄位讓分類器算對節，什麼時候可以（#355）

ch10 有三節不由 entry type 單獨決定，需要一個欄位配合。判準不是「送不送得出」，
是**這個值對這個型別是不是定義上為真**：

| 情形 | 裁決 |
|---|---|
| `review` → `RELATEDTYPE = reviewof` | ✅ **送**——`.review` 的意思就是「這是一篇評論」 |
| `testInstrument` → `ENTRYSUBTYPE: Database record` | ❌ 它斷言記錄**來自 PsycTESTS** |
| `socialMediaPost` → `EPRINT: Twitter` | ❌ 它斷言**平台** |

**可以送型別已經聲明的東西，不可以送記錄的出處。** 完整論證與上游限制（依賴的社群平台
清單是寫死的封閉列舉，Mastodon 不在其中）見 `.claude/rules/apa7-is-the-work-floor.md`。

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
