## Context

#304 五項裁決（2026-08-16）：①TIGP/org 域零新機制（已落地）②org 全開 ③venue 族一次到位 ④Spectra 路徑 ⑤編年＝呈現（文章編年 list）＋儲存（刊名沿革 timeline）兩者都要。前置 doctrine：`literal-first-then-key`（進庫不猜 key、升格留 verdict、終局全域 literal 歸零 #303）。現況：371 distinct journaltitle／754 works、conference 與 publisher 散在 `fields`；store format 10。

## Goals / Non-Goals

**Goals**：venue 一級實體（journal/conference/publisher）；Entry 作品側二態 ref 邊；literal-first 匯入＋既有 works 回填；編年呈現＋刊名沿革；MCP/CLI/skill 全面；format 11。
**Non-Goals**：不刪 fields 字串；不做 371 刊實際消歧（#303 campaign）；不收 series 等其他載體；不動 person/org 形狀。

## Decisions

### D1 — 單一 `venue` kind＋封閉 `type` 欄位（不是三個 kind）

`venue:` 頂層形狀，`type: journal | conference | publisher`（strict，未知值整檔拒讀）。三者共享全部行為（names／沿革／ref／消歧），分三個 kind 會把同一套機制複製三份；`type` 欄位讓封閉列舉的邊只加**一條**。擴充第四類（series 等）＝修 spec 的顯式動作。

### D2 — venue names：平面 list＋`authorized`（org 模式），每項可攜時間段（沿革）

**不巢狀**（#227 的 authorized/variant 巢狀是 person 專屬；org 維持平面是刻意不對稱，venue 跟隨 org）。沿革（裁決五b）用 names 項的選填時間欄位表達：

```yaml
venue:
id: <v4 UUID>
key: journal-of-computational-and-graphical-statistics
type: journal
names:
- value: Journal of Computational and Graphical Statistics
- value: JCGS
authorized:
- Journal of Computational and Graphical Statistics
note: …
```

改名史範例：`- value: 舊刊名` 項攜 `start:`／`end:`（機制同 affiliations 時間軸段，含 `ended:`／`attested:` 語意——直接重用 Temporal 既有型別，不新造）。無時間欄＝不主張時段（現行名或別名）。

### D3 — Entry 邊：`venues:`（有序 list，二態 ref），作品側正典

`Entry.venues` 元素形同 `authors`（`- key:` ／ `- literal:`）。**list 而非單值**：conference paper 可同時連 conference 與 publisher。順序帶語意（主要載體在前）。反向（venue → works 編年 list）由 index 現算（`idx_venues_key`），**不**在 venue 記錄存文章清單——`entity-backlink-completeness` 第 14 條邊，表同步修訂。正典側論證同 #300 六理由（有界、出處同在、未歸戶可表達、存在依賴、變更局部性；「序即結構」此處弱但無反向論證）。

### D4 — literal-first 匯入與回填

importer 對映：`journaltitle` → `.literal`（type 推定 journal）；`booktitle`（proceedings 型 entry）→ conference；`publisher` → publisher。**進庫不猜 key**（規則第 1 段）；欄位字串照舊保留。回填 migration `migrate-venues`（dry-run 預設、`--apply` 寫入；participates in 既有 migration 慣例：目標 store 回顯、git tracked 前提）：754 works 的 journaltitle → `venues: [- literal: …]`，只加不改（同 #206 回填判準）。

### D5 — format 11（non-additive，附實測義務）

新頂層形狀 `venue:` 對舊 binary 的行為**必須實測**（tasks 有專項）：若舊 binary enumerate 未知形狀＝skip → 資料靜默不可見；若 error → 整庫拒開。兩者都不可接受 → bump。`Entry.venues` 雖在 tolerant-preserve 層（舊 binary 保留不解讀），但「保留而不解讀」對 ref 邊即靜默漏資料——併入同一 bump 論證。部署程序同 format 10（binary 先升、真 store 後遷、手動 bump marker）。

### D6 — MCP/CLI/skill 面（parity 表逐列裁決）

| 能力 | CLI | MCP | 裁決 |
|---|---|---|---|
| venue 檢視（編年文章 list） | `akashic venue <key>`（`--json`＋人可讀同源） | `akashic_venue` | 兩面 |
| venue 列舉 | `akashic venues` | `akashic_venues` | 兩面 |
| venue 消歧 | `resolve-venues` | `akashic_resolve_venues` | 兩面（同 resolve-people 契約形） |
| venue 單筆建檔 | `add-venue` | `akashic_add_venue` | 兩面（同 add-person 形） |
| org 單筆建檔（#304 移轉） | 既有 bootstrap 涵蓋批次 | `akashic_add_organization` | MCP 補面 |
| org 消歧（#304 移轉） | 既有 `resolve-organizations` | `akashic_resolve_organizations` | MCP 補面 |

每列落 `mcp-cli-parity.md` 表（兩張表依方向）。skill：`akashic-venue-verify`（plugin/skills，形同 person-verify——查證來源、consensus、verdict 落 store）。

### D7 — 編年呈現（裁決五a）

`akashic venue <key>` 輸出：venue 記錄＋沿革＋**文章編年 list**（依 `pub_year`／`date` 升冪；同年依 citekey）＋計數。空集合顯式報「零篇」（區別於查無此 venue——`entity-backlink` 執行細節 4）。

## Risks / Trade-offs

- **371 刊異形消歧量大** → 機制先行、消歧走 #303 campaign 分批；`resolve-venues` 的 alias 正規化（大小寫摺疊、縮寫展開）為首輪武器
- **type 推定錯誤**（booktitle 不必然 conference）→ 推定只給 `.literal` 附帶 hint，不寫死；歸戶時人裁
- **format 11 連兩次 bump 的部署疲勞** → 沿用 format 10 剛驗證過的部署鏈（release-signed → migrate → doctor/validate → bump），文件照抄

## Migration Plan

1. code 落地＋測試（含未知形狀實測）→ 2. format 11 gate（venue 寫入被 gate 拒直到 marker 升）→ 3. release binary → 4. 真 store `migrate-venues --apply` → 5. doctor/validate → 6. 手動 `format: 11`。回滾：git store 可逆；binary 降版受 refuse-if-newer 保護。

## Implementation Contract

- **可觀察行為**：(1) `venue:` 檔案 round-trip（encode(decode(x))==x）；(2) `Entry.venues` 二態 ref 解碼／編碼；(3) `akashic venue <key>` 列編年文章（derived，非儲存）；(4) `migrate-venues` dry-run 印計畫不寫、`--apply` 只加 `venues:` 鍵不動既有欄位；(5) format 10 store 中 venue 寫入被拒（`invalidInput`，訊息指向部署程序）；(6) 全部新 MCP tool 有 CLI 對應列（parity 稽核程序通過）
- **失敗模式**：未知 `type` 值→整檔拒讀；`venues` 元素非 key/literal→拒讀；migration 於 untracked store→拒
- **驗收**：swift test 全綠；copy store 演練 754/754 回填、idempotent、validate 全綠；parity 機械稽核（兩張表）零缺格
- **邊界**：不動 person/org 解碼路徑；`fields` 原樣；#303 campaign 執行不在本 change
