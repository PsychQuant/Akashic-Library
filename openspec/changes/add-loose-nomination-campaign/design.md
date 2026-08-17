## Context

`PersonResolver.resolve` 的提名判準是 alias 正規化後**完全命中**（`NameNormalization.matchingKey`：NFKC＋連字號家族＋空白收斂＋大小寫摺疊——不重排 token、不比縮寫）。2026-08-16 實測：2,123 個 literal 作者邊、零候選。#303 campaign 需要寬鬆提名層與編排層；discuss（#303 comment 5307415428）已定五項前提。消費端三面：CLI `resolve-people`、MCP `akashic_resolve_people`（#272 組合腿）、App `Sources/AkashicAppKit/Adjudication.swift`。

## Goals / Non-Goals

**Goals**：寬鬆提名（封閉兩 tier）＋verdict 知識再利用（confirmed-elsewhere）＋tier 可見性（三面）＋campaign skill（census／分批／每輪回報）。

**Non-Goals**：CJK 羅馬化異拼（查表域）；venue／org resolver 寬鬆化；apply 寫 alias；campaign 各輪實際執行；venue format 11 部署。

## Decisions

### D1 — 寬鬆鍵生成器 `LooseNameKey`（AkashicCore，與 `NameNormalization` 並列）

單一定義住 core（#140 分岔血案防線）。輸入一個名字字串，輸出各 tier 的比對鍵；兩側（literal 與 person 的 `names.all`）都生鍵，同 tier 鍵相等才算命中。

- **L1 reorder key**：`matchingKey(s)` → 去逗號句點 → 以空白切 token → **排序** → join。`Hsu, Yung-Fong` 與 `Yung-Fong Hsu` 同鍵 `hsu yung-fong`（連字號保留在 token 內）。
- **L2 initials keys**：token 結構解讀後生 `<family> <initials>` 鍵。**有逗號＝姓氏已標定**（逗號前是姓），只生一鍵；**無逗號不猜**——姓前／姓後兩種解讀各生一鍵。initials＝各 given token 逐連字號段取首字母串接（`Chun-Houh`→`ch`、`Y.-H.`→`yh`、`C-H`→`ch`）。`Chen, Y.-H.` → `chen yh`；alias `Chen, Yi-Hau` → `chen yh`——命中。**L2 只對含拉丁字母的名字生鍵**：CJK 姓名（`鄭澈`）取首字母無意義，不生 L2 鍵（L1 照生）。
- 正規化鐵律延伸：鍵只用於配對、永不外洩成資料（`matchingKey` 檔頭原則）。

### D2 — tier 語意與抑制序

`Tier` 封閉四值，信心降冪：`exact` > `confirmedElsewhere` > `reorder` > `initials`。每個 literal 出現位置**只在最高命中 tier 提名**（高 tier 抑制低 tier——同一配對不重複出現）。tier 內 1 命中 → candidate；2+ 命中 → `AmbiguousMatch`（新增 `tier` 欄）。`rejected` 抑制對全 tier 生效（恰為 (work, citekey, literal, personKey) 配對，語意不變）。

### D3 — confirmed-elsewhere：verdict 知識再利用

`ResolutionLedger` 增 `confirmedPairings(people:)`（鏡像 `rejectedPairings`，讀 `resolution-confirmed` 的 value 文法 `<kind>:<key> :: <literal>`）。`resolve` 簽名增 `confirmed: Set<ResolutionPairing>`（**刻意必填**，同 `rejected` 的 verify DA fix-10 理由）。判準：literal 的 `matchingKey` 與某 confirmed pairing 的 literal 之 `matchingKey` 相等、且本配對未被 reject → 以 `confirmedElsewhere` tier 提名該 person。持久化只走 verdict、不寫 alias。

### D4 — 回報形狀（additive）

`ResolutionCandidate` 與 `AmbiguousMatch` 各增 `tier`。排序：tier（信心降冪）→ citekey → index。三面同步：MCP JSON 增 `"tier"` 欄；CLI 人可讀輸出按 tier 分組；App Adjudication 列帶 tier 標示。既有欄位、rowID、apply 語意零改動。

### D5 — campaign skill `akashic-literal-campaign`

`plugin/skills/akashic-literal-campaign/`：SKILL.md（campaign workflow：census → 按批 TaskCreate → 逐 distinct「查證（person-verify）→ resolve → apply」→ 每輪計數落 #303 comment）＋ `scripts/literal-census.sh`（三域 literal 計數：author／venue／affiliation 的邊數與 distinct 數；store format < 11 時 venue 域報「未部署」而非 0——缺席與零要可區分）。批次順序依使用者拍板：混合——高頻先掃、統計所批接續、長尾建檔殿後。

### D6 — 契約面重確認（mcp-cli-parity）

不新增工具，既有 `akashic_resolve_people`／`resolve-people` 列的契約描述增 tier 語意——依 parity 規則「修改既有能力時重新確認對應列」，實作時更新該列註記。

### D7 — R1 verify 後的四個追加裁決（2026-08-17）

R1 verify（6-AI，FAIL：8 blocking）後定案，spec 已同步成文：

- **D7a 淘汰語意成文**（B7）：rejected 過濾先於計數——「否決後餘一」照提但 reason 揭露；跨 tier fall-through 同揭露。替代案「回退到 singleton-only 過濾」否決：否決本來就是消歧的推進器，藏住倖存者反而讓進度停滯，揭露即可。
- **D7b verdict rule 分層**（B2）：`personRule(for:)` 封閉映射；exact 沿用既有字面（#232 史零遷移）、legacy 無尾註預設 exact（語意正確）。
- **D7c apply id 釘 person**（B8）：三段 id；App 面傳值物件本就免疫，MCP/CLI 的兩呼叫窗由 pin 關閉。替代案「apply 時整包重驗 literal+person」否決：id 內嵌 pin 讓錯誤在解析層顯形，不用比對快照。
- **D7d bootstrap 排除面跟上**（B4）：寬鬆共鍵 literal 路由 `pendingResolution`（回報不丟棄）；`rejected:` 必填讓否決史決定回歸建檔的時點。

### D8 — R2／R3 verify 後的裁決（2026-08-17）

- **D8a tier 閘範圍**（使用者裁決「不豁免」＋R3 DA 仲裁）：受閘面封閉列舉＝CLI 篩選式批次 apply；`--citekey`／`--person` 不豁免。MCP per-id apply 刻意不在閘內（id 顯式＋tier 可見＋skill 分 tier 批次紀律），tier-acknowledgment 參數列 follow-up——spec 不寫全稱句（R2→R3 的教訓：undefined「bulk apply」總括詞）。
- **D8b 歧義出口**（使用者裁決 alias-provenance 路）：清單中人 → variant alias＋provenance 升 exact；**第三人 → `add-person` 以該寫法為 name**（exact 單命中優先於寬鬆碰撞——最高 tier 抑制即出口，無需新機制）。誠實邊界成文：provenance 現無 MCP/CLI 寫入面（follow-up）；`update_person.names` 整組替換——指引一律寫「先讀再附加整組回寫」。
- **D8c 兩腿協調**：以內部未截斷配對（rowID＋personKey）協調，不用消毒截斷的 JSON 回音；配對級比對讓「同列 reject A＋apply B」進 apply 腿重解析。
- **D8d 淘汰計數**：去重 person key 集合——同一否決跨多鍵空間計一次。
- **D8e bootstrap 空間同構**：逐 tier 查找＋confirmed 同源必填——不留 resolver 提名空間的第二份拷貝（#140 在空間定義層的重演）。

## Risks / Trade-offs

- **initials 碰撞面**（93/724「姓＋首字母」鍵對 2+ 人）→ 湧出的是 ambiguity 列（回報不解決）與弱證據 candidates；防線＝tier 可見＋campaign 逐 distinct 查證紀律，契約不禁止 apply
- **store 不完整假象**：initials 單命中只因店裡「今天」只有一個同鍵者——skill 明文警告（person-verify 已有同款），tier=initials 的 apply 必附查證
- **L2 雙解讀過度生成**：無逗號西式名「John Smith」的 family-first 解讀生出 `john s` 鍵——僅在恰有同鍵 person 時提名，噪音上限＝店內人名空間，實測可承受；出現洪水再議分頁

## Migration Plan

純 additive：無 store format 變更、無資料遷移。既有呼叫端因 `confirmed:` 必填參數而編譯失敗 → 逐面補上（這是刻意的顯式接線）。回滾＝revert commits。

## Implementation Contract

- **可觀察行為**：(1) `LooseNameKey` 對表列輸入產出表列鍵（reorder／initials／逗號標定／CJK 略過 L2）；(2) `resolve` 對「Yung-Fong Hsu vs alias Hsu, Yung-Fong」提名 tier=reorder；對「Chen, Y.-H. vs alias Chen, Yi-Hau」提名 tier=initials；同 literal 他處 confirmed → tier=confirmedElsewhere；exact 命中時不重複出現於低 tier；(3) rejected 配對在全 tier 被抑制；(4) 三面輸出帶 tier；(5) census script 對演練 store 回報三域計數、format < 11 時 venue 域顯示未部署
- **失敗模式**：L2 對 2+ 命中回 ambiguity 不 candidate；`confirmed`／`rejected` 參數缺省＝編譯錯誤（無預設值）
- **驗收**：`swift test` 全綠（新增 LooseNameKeyTests＋PersonResolverTests tier 案例）；census script 於 rehearsal store 實測；真 store `resolve-people` 候選數 > 0（相對現況零候選）
- **邊界**：不動 apply 寫入路徑與 verdict 寫入邊界；不動 venue／org resolver；App 面只加顯示不改互動流
