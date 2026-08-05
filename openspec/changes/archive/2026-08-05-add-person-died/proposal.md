## Why

Store 裡有**三件互相獨立的事**被壓成一個由隸屬時間軸推導出來的 `status`：

| 實際的事實 | 現況 |
|---|---|
| 與某機構的隸屬已結束 | 可表達（`profile.affiliations` 段有 `end`）|
| 是否仍在學術上活躍 | 無法表達——被讀成 `status: retired` |
| 是否在世 | **完全無法表達** |

兩個實證。**退休不等於停止發表**：李靜沛 2023 離開中研院統計所、銀慶剛 2017 離開，兩人 ORCID 著作都持續到 2026，但 store 記錄都會被推導成 `retired`。**離職與過世現在分不出來**：魏慶榮任期 `1990-09 ~ 2004-11`，那個 `end` 記的其實是死亡（2004-11-18，Statistica Sinica 16(3) 2006 紀念專輯載明），但 store 只看得到「隸屬在 2004-11 結束」。

還有一個不對稱：`Organization` 有 `founded` / `dissolved`，`Person` 沒有任何生平欄位。同一個 store 裡機構有生命週期而人沒有。

這不只是表達力問題。Akashic-Library issue 64 的 CV 補完需要一個**終止條件**：已故者的著作清單是封閉的（可以補完），在世者是開放的（永遠補不完）。而 issue 83 量到統計所退休名冊 44 位研究人員中 39 位在庫內 0 篇著作，其中含多位已故者——填補那份缺口時，逝世日期與著作清單來自同一份紀念文集。本變更若不先落地，那趟檢索要跑第二遍。

## What Changes

`Person` 新增一個 optional 的 `died` 欄位，持有逝世日期。三件事改用三種處置：

| 事實 | 處置 | 理由 |
|---|---|---|
| 隸屬已結束 | **已可表達**，不動 | `affiliations` 段的 `end` 就是它 |
| 是否仍活躍 | **推導，不記錄** | 「活躍」沒有非任意的門檻；記下來等於把一個規約當事實存 |
| 是否在世 | **記錄** | 世界裡的離散事實，有第三方來源，且是 issue 64 的終止條件 |

`status` 的推導邏輯與欄位名皆逐字不動；改為在匯出的 researcher 表新增 `died` 欄，並把「`status` 描述的是隸屬」寫進匯出 schema 說明（目前只在原始碼註解裡）。另新增一條驗證：有 `died` 卻仍有開放的 affiliation 段時報告，不自動修改。

**本變更不 bump store format**：新增欄位是 additive，依 store 格式文件的 bump 準則，additive 變更 MUST NOT bump——舊 binary 靠 tolerant-preserve 原樣保留未知欄位，不會按舊語意誤讀新格式。

## Non-Goals

- **`born` 欄位**：對在世者是個資，且本專案用途不明。因為新增欄位是 additive，日後要加仍是 additive，延後零成本。
- **帶 provenance 的結構化 `died`**（形如 date + source + note 的複合值）：方向決定可逆性。平欄位 → 日後 provenance 機制落地時在旁邊加仍是 additive；複合值 → 日後改形狀就是欄位形狀變更、必須 bump format。不為尚未設計的機制先蓋 bespoke 版本。過渡期來源寫進既有的 person note 欄位。
- **Akashic-Library issue 63 的無界區間問題**（「知道已結束、完全不知何時」）：見設計文件的設限（censoring）分析——本變更涵蓋右設限與區間設限，無界區間留給 issue 63。
- **Akashic-Library issue 66 的 provenance 機制**。
- **把 `status` 改名為 `affiliation_status`**：對衍生層是 breaking change 且跨 repo。先給資料（新增 `died` 欄）再談改名。
- **任何 format bump 或遷移工具**。
- **實際逝世日期的填補**（issue 83 的資料工作，不是 schema 工作）。

## Capabilities

### New Capabilities

- `person-deceased`: Person 的逝世事實如何被記錄、如何與隸屬狀態區隔、以及活躍度為何不被記錄

### Modified Capabilities

(none)

## Impact

- Affected specs: `person-deceased`（新增）
- Affected code:
  - New:
    - `Tests/AkashicKitTests/PersonDeceasedTests.swift`
  - Modified:
    - `Sources/AkashicCore/Models.swift`
    - `Sources/AkashicCore/YAML.swift`
    - `Sources/AkashicExport/RelationalExport.swift`
    - `Sources/AkashicStoreIO/LibraryStore.swift`
    - `Sources/akashic/Commands.swift`
    - `docs/store-format.md`
    - `README.md`
  - Removed: (none)
