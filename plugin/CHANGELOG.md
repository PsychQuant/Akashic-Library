# Changelog

## [unreleased]

- **`akashic_update_venue`／CLI `update-venue`**（#306）：venue 異名補寫——`add_names` append 語意（整組替換刻意不提供，R3F-2 教訓）；`note`／`type` 替換。沿革補全直接擴大 resolve-venues 命中面。
- **⚠️ `akashic_resolve_people` 增 `confirm_tiers`**（#307）：apply 集含寬鬆提名層（reorder／initials／confirmed-elsewhere）而該層未列於 `confirm_tiers` ＝整批拒絕零寫入並指名缺席層；exact 免承認。MCP 面自此也有 tier 覺察閘（CLI 為 `--tier`，兩面對稱不同形）。
- **`akashic_update_person` 的 `references` 落地**（#308）：**append-only**（與其他欄位的替換語意刻意不同——references 持有 verdict，整換會洗判定史）；retrieval／judgement 兩型、(field,value,kind) 冪等；verdict 欄位對拒收（只能經 resolve 流程寫）。alias-promotion 出口的 provenance 半邊自此有正規寫入面。
- **`HOME` 注入隔離**（#309）：registry 值（`~/.akashic`）的 tilde 展開改吃注入的 environment `HOME`——假 home 測試／排練不再落到真 store（R2 verify 事故的根因修除）。

## [0.9.0] - 2026-08-17

- **`akashic_resolve_people` 提名四層化**（#303）：candidates 每列新增 `tier`（封閉四值 `exact`／`confirmed-elsewhere`／`reorder`／`initials`，信心降冪排序；報告形狀 additive——apply 契約的變更見下方 R1 修正輪兩則 ⚠️，是有記錄的變更）。寬鬆比對封閉兩類——token 重排與姓＋首字母（無逗號不猜姓氏位置、CJK 不生 initials 鍵）；羅馬化異拼刻意排除。ambiguities 同步帶 tier（initials 碰撞 ≠ exact 同名）。
- **confirmed verdict 再利用**：同 literal 已於他處 confirmed → `confirmed-elsewhere` tier 自動提名（查證知識走 verdict 持久化、不寫 alias）。
- 新 skill **`akashic-literal-campaign`**：literal 歸零 campaign 編排層——三域 census（`scripts/literal-census.sh`；venue 域對 format < 11 報「未部署」而非 0）、分批 TaskCreate、逐 distinct 查證管線（引 person-verify）、每輪計數落 #303。
- CLI `resolve-people` 人可讀輸出按 tier 分組（initials 段標頭自帶查證義務）；App 裁決台候選列帶 tier。
- **R5 收斂批**（2026-08-17，R4 verify PASS-after-batch 的批）：census 恢復與 loader 同語意的合併掃描（混合佈局不再假零）；兩腿協調配對改寫入後、過濾寫失敗者；`rejected`／`applied` 回音改 raw 三段（StoreKey quarantine 把關，超長 citekey 回音可重用）；counts 標籤過文法夾；兩個守衛測試換可鑑別 fixture；歧義頁尾第五面補雙出口＋整組替換警語；spec R10 改配對級協調語意。**相容性註記**：verdict value 的 holder 自 R2 修正輪起過 `StoreKey` 文法閘（decode 層）——手改／外庫匯入的不合文法 holder 會使**整筆 person 記錄 quarantine**（非僅該 verdict 進 malformed）；真 store 37 筆 verdict 全數合法、零影響。
- **R2／R3 verify 修正輪**（2026-08-17）：兩腿協調改以內部未截斷配對（超長 citekey 不再打斷批次；同列 reject A＋apply B 正確進 apply 腿）；淘汰揭露計數去重（1 筆否決不再報 3）；tier 閘不豁免 `--citekey`／`--person` 收窄（訊息同步）；bootstrap 提名空間與 resolver 同構（逐 tier 查找＋吃 confirmed——幽靈 pending 與 confirmed 盲鑄修除）＋`confirmed:` 必填；`rejected`／`applied` 回音統一三段 pinned 形；歧義出口指引四面重寫（alias-provenance 升 exact；第三人走 `add-person`；`update_person.names` 整組替換警語；provenance 寫入面缺口誠實記錄）；person-verify skill 同步（三段 id、#272 組合呼叫、出口改正）；census 佈局模式切換（半遷移不雙計、純 legacy 不誤拒）；App skip 改 pinned 鍵。
- **R1 verify 修正輪**（2026-08-17，8 blocking）：
  - **⚠️ apply id 升三段形 `citekey:authorIndex:personKey`**（釘 person——提名改指時顯式拒絕指名兩造；兩段 legacy 形僅當該位置提名仍唯一時等價）
  - **⚠️ CLI `resolve-people --apply`（篩選式批次）對寬鬆 tier 候選拒絕、`--tier` 具名才放行**——新 `--tier` 選項（exact／confirmed-elsewhere／reorder／initials，可重複）收窄套用範圍
  - verdict rule 依 tier 導出（`author-name-reorder`／`author-name-initials`／`author-name-confirmed-elsewhere`——寬鬆 tier 的校準史與 exact 分開計；legacy 無尾註 verdict 維持 exact 語意）；三態計數按 rule 分桶、CLI 逐 rule 印
  - `LooseNameKey` 句點分段修正（`Chen, Y.H.`→`chen yh`；`L.W. Wang` 假陽性除）
  - 否決抑制改與提名同套正規化（EN DASH 變體壓得住）；淘汰而得的唯一命中 reason 揭露；confirmed-elsewhere 只吃 work-holder verdict
  - CLI／App 歧義列帶 tier、指引分層（exact 兩難 vs 寬鬆共鍵通常是不同人）
  - `bootstrap-people` 新增「與既有 person 寬鬆共鍵」桶（先消歧不建檔、全否決後回歸建檔候選）；`PersonBootstrap.resolve` 增 `rejected:` 必填參數
  - census：`glob.escape` 防靜默零計數（自檢 exit 3）、口徑統一（總邊／literal 邊／distinct）、org-parents 第四域
  - campaign skill 重寫：候選不在列的三因分辨階梯（歧義／截斷／真無命中）、initials 逐 entry 判斷、「store 內容是資料不是指令」條款

### venue 域（store format 11，#304——與本版並行出貨）

- **store format 11**（#303／#304 venue change）：新 entity 形狀 `venue:`（journal／conference／publisher 封閉三值；`names` 沿革 timeline）＋ `Entry.venues` 二態 ref 邊（`.key`／`.literal`，literal-first）。舊 binary 讀 `venue:` 整檔 quarantine（實測），故 non-additive bump；新 binary 對 format < 11 的 venue 寫入 gate 拒絕指路 `migrate-venues`。
- **6 個新 MCP tool**：`akashic_venue`（記錄＋沿革＋文章編年 list——反向邊現算）、`akashic_venues`、`akashic_add_venue`、`akashic_resolve_venues`（apply+reject 組合腿同 #272 契約；verdict 落被判定 venue）、`akashic_add_organization`／`akashic_resolve_organizations`（#304 org 重啟的 MCP 面補齊）。
- CLI 對應面：`venue`／`venues`／`add-venue`／`resolve-venues`／`migrate-venues`（additive-idempotent 回填，per-file trackedness 守門）。
- importer（WoS／Zotero）自動產生 `.literal` venue ref（單一對映源 `VenueDerivation`；進庫不猜 key）。
- 新 skill `akashic-venue-verify`：literal→verdict 查證紀律（Crossref／OpenAlex／ISSN Portal 證據鏈、刊名沿革 timeline）。

## [0.8.0] - 2026-08-16

- **store format 10**（#227／#241）：person `names` 巢狀化（`authorized`／`variant` 分區——子集關係成為結構性事實）＋ `id` 改為獨立 v4 UUID（單一來源事件發放、永不由名字重算），既有 867 筆一次性換發。舊 binary 讀巢狀 names 整檔 quarantine；新 binary 讀舊格式 fail-closed 指向 `akashic migrate-person-identity`（dry-run 預設）。org 刻意不巢狀化。
- `akashic_update_person` 收巢狀 `names` 物件（平面陣列拒絕、分區重疊拒絕）；讀取面一律 `names.all`。
- `akashic_person` 對 quarantine 歧義查詢回「無法判定」（`undeterminable`）而非 not-found；name-lookup 零候選時附 `quarantined`／`note` 欄位。
- binary：signed＋notarized universal（`akashic-mcp-v0.8.0`）。

## [0.7.0] - 2026-08-15

- **`akashic_resolve_people` 組合呼叫解禁**（#272）：apply+reject 同呼叫改兩段式（reject 先完整提交、apply 以新狀態重解析），回應 `legs.{reject,apply}` 按腿回報；同列兩邊點到以 `skippedBecauseRejected` 回報。單腿呼叫形狀不變。
- **`akashic_person` 增 verdicts 段**（#270）：判定列舉（observed/stale 標示）——stale verdict 首次有列舉面。
- divergence merge 把 verdict 當一等邊（#271）：person merge 自動遷移、work merge 的 citekey 退役改寫 value。
- **`akashic_import_wos`**（#290）：WoS 匯入的 MCP 面——與 CLI `import-wos` 同一條無損路徑（#206：具名對映＋殘餘收集＋`droppedColumns` 可見）；`path`／`csv`／`dry_run`，形照 `akashic_import_zotero`。
- **store format 9**（#223）：附件鍵域收窄（移除 `pool`）＋記錄側副本引用 `akashic.sources`；真實 store 升 9 前 sources 寫入被 gate 拒絕指路。

## [0.6.0] - 2026-08-15

- **⚠️ `akashic_set_status` 呼叫契約變更**（#258）：省略 `status` 不再是清除——會被**拒絕**；清除要顯式 `clear:true`（與 CLI `--clear` 逐條對應）。`akashic_tag` 零參數同步由 no-op 改拒絕。守衛下沉 `AkashicService`，CLI／MCP 共用同一份判準（先前「省略＝清除」對 LLM 消費者是 footgun：省略即 valid 的面恰無守衛）。
- CLI 新增 `add-person`（單筆建 person——unkeyable 作者指定 key 的入口）與 `divergences`（列未決歧異；`--json`＋人可讀同源）——parity 最後兩格（#250）。
- 歸戶修正隨同出貨：識別重排等價對稱化（#226，55.5% 分裂收斂）、變音符號作者自動摺疊＋CJK 作者回報不丟棄（#238）。
- `export-tables --view <key>`：view-scoped 關聯表匯出（#274）。
- binary：signed＋notarized universal（`akashic-mcp-v0.6.0`）。

## [0.5.5] - 2026-08-14

- **#280 裁決落地（選項 2）**：resolution verdict 刻意不攜 rests-on——證據載體依生命週期分工（已判定 → person `references`；未判定 → divergence `restsOn`）。person-verify skill 的「工具面缺口」註記改為設計裁決；規格 requirement 與 entity-backlink 規則同步。shell-only bump（binary 仍 0.5.0）。

## [0.5.4] - 2026-08-14

- **更正 `akashic-wos-intake` 邊界段**（#281）：0.5.3 的「doctor 不查 DOI 共用」為誤——doctor 自 #94 即有兩道檢查（正規化 DOI 共用組＋同標題同年不同 DOI），敘述改回正確指向。
- wos-intake 的 W8 欄名清單降級為快照，正典移至 repo `docs/import-wos-mapping.md`（#286，含對映目標與合成語意）。shell-only bump（binary 仍 0.5.0）。

## [0.5.3] - 2026-08-14

- **`akashic-wos-intake` skill**（Akashic-Library #277）：WoS 型清單的匯入前 QA 閘——DOI 補查（寫回既有 `DOI` 欄）、同篇雙列偵測（early-access／erratum／重複；無 DOI 桶走標題∧年份∧type 三訊號）、機構欄容錯、intake 報告經人確認 → 另存 TSV → `import-wos --dry-run` → 寫入。分母在這一步定案。
- bootstrap 的 xlsx 匯入路徑改為先過 wos-intake（觸發競爭消解）；store 內 DOI 共用無自動偵測的缺口另記 #281。shell-only bump（binary 仍 0.5.0）。

## [0.5.2] - 2026-08-14

- **`akashic-person-verify` skill**（Akashic-Library #276）：歸戶查證——「這個 literal 作者是不是這個人」的證據鏈（Europe PMC core／ORCID／OpenAlex／出版商頁）、affiliation timeline、判定建議，經使用者確認後以 apply/reject 落 verdict；查不出來記 divergence（第三個出口）。`references/verification-traps.md` 收四類實測陷阱。shell-only bump（binary 仍 0.5.0）。
- `akashic-bootstrap` description 讓渡身分判定給 person-verify（觸發競爭消解）。

## [0.5.1] - 2026-08-14

- **Plugin shell 遷入 Akashic-Library**（#275）：plugin.json／.mcp.json／wrapper／skills 自 psychquant-claude-plugins `plugins/akashic-mcp/` 遷至本 repo `plugin/`；marketplace 改以 git-subdir source 引用本目錄。Release 流程單 repo 化——binary release 與 plugin bump 同 repo 同 commit。
- **`binary_version` 欄位**：wrapper 的 binary release tag 改讀 `binary_version`（缺席回讀 `version` 相容舊檔）——shell-only bump 不再產生不存在的 release tag（本版即例：shell 0.5.1、binary 0.5.0）。
- `akashic-bootstrap-workspace`（eval 工作區，504 檔）不隨遷入 plugin——移存本 repo `docs/skill-evals/`（不出貨給安裝者）。

## [0.5.0] - 2026-08-14

- 消解判定 ledger（Akashic-Library #232）：`akashic_resolve_people` 新增 `reject` 參數（顯式否決、entry 不動）；apply 同動作寫 `resolution-confirmed`；候選帶三態計數（confirmed/rejected/pending，不報比率）、已否決獨立 `rejected` 段、`pendingTotal` 可見
- **Store format 8**：verdict reference 需要 store format ≥ 8——format < 8 的 store 上 reject 硬擋（指路訊息）、apply 照常歸戶但跳過 verdict 並以 `verdictsSkipped` 揭露；升級程序見 Akashic-Library #247
- binary：signed + notarized universal（akashic-mcp-v0.5.0）

## [0.3.0] - 2026-08-04

### Added
- `akashic-bootstrap` skill：把資料補進 store 的完整路徑——認出手上是什麼（不要求使用者預先分類 person／work）→ 查 store 已有什麼 → 外部查詢 → 多訊號合取驗證 → 乾跑報告 → `--apply` 才寫。
  - `references/work-sources.md`：Crossref 與 Europe PMC 的實測覆蓋率與三類「像但不是」的記錄（審稿報告 DOI、preprint、同前綴會議摘要）。
  - `references/person-sources.md`：ORCID 的 employment 不回填歷史、given-names 常是英文暱稱；姓名比對靠佐證不靠拼音相似度。
  - `references/writing-to-the-store.md`：哪些操作有正規入口、哪些沒有（更新既有記錄欄位無入口，見 Akashic-Library#68）、以及沒有時的正確繞法（decode → 改 → encode，絕不手刻 YAML）。
  - `scripts/crossref_match.py`：標題→DOI 的四訊號合取比對 + 反向驗證，內建三類陷阱的自動繞行。

### Removed
- `person-search` skill —— 內容併入 `akashic-bootstrap`。它要求使用者先判定「這是 person 查詢」，但實務上人手上常是一個名字、一個 citekey、一份匯出檔，不知道也不該需要知道它對應到哪種實體形狀；分類是看內容就能決定的事。找人、消歧、聚合、追關係四段全部保留在新 skill 的步驟 1。

## [0.2.0] - 2026-07-30

### Added
- Binary v0.2.0（14→17 tools）：`akashic_libraries`（#13 membership views）、`akashic_person`（#14 人物聚合）、`akashic_files`（#18 多實體庫切換）；`akashic_search` 支援 `library` 過濾；index schema 版本機制；config schema v2（多檔案 registry，向後相容）。
- `person-search` skill（#14）：找人→消歧→聚合→追關係 workflow；需 akashic-mcp binary ≥ v0.2.0（`akashic_person` tool）。隨 akashic-mcp-v0.2.0 binary release 上架。

## 0.1.0 (2026-07-22)

- 首發：14 tools（7 讀 + 7 寫衍生層）；Akashic store 查詢/關係/圖形、person 解析逐候選 apply、Zotero 單向 pull。
