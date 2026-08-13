## Why

歧義消解的人工判定（「就是他」／「查過了，不是他」）目前不留任何痕跡：apply 改寫 entry 後判定本身消失，否決更是完全沒有落地處。後果有三：(1) 系統會永遠重新提名同一個已被否決的候選；(2)「來源信心」無從校準——分母（看過幾次、否決幾次）不可知，只能靠人填的主觀分數，而自由填寫的分數不可證偽；(3)「查過了，不是他」與「還沒查」在庫裡同形，事後無法區分（違反 lossless-intake 的可判定性要求）。

## What Changes

- 消解判定（確認與否決）以**既有** `ProvenanceReference`（`kind: .judgement`）記錄在被判定的 person／organization 上：`field` 用新的封閉動詞欄位對 `resolution-confirmed`／`resolution-rejected`，`value` 定位配對（entry citekey ＋ author literal），statement 為人話說明（含證據類別名）。**零 format bump**——序列化形狀不變，只擴充 `validateReferenceAttachment()` 的封閉欄位表（此為 provenance-reference spec 的 normative 修改，見 Modified Capabilities）。
- 新增 `ResolutionLedger`（AkashicEntity）：從 references **現算**三態（已確認／已否決／未處理）——calibration 是 derived 不是 stored（entity-vs-view 立場、#221 的直接應用）。
- `PersonResolver`／`OrgResolver` 消解前查 ledger，**跳過已否決配對**（不再重新提名）。
- resolve 面新增 **reject 動作**（rowID 同 apply 的複合鍵）：`AkashicService.resolvePeople` 單一函式承載，CLI `resolve-people` 與 MCP `akashic_resolve_people` 兩面同路徑（mcp-cli-parity）；`resolve-organizations`（CLI 單面）同資訊形。apply 路徑同時寫入確認判定——分子與分母是同一種記錄。
- 呈現：候選帶三態**計數**（絕不報比率——N 小時比率製造假精確，且 WoS/Crossref 不獨立、計數不邀請貝氏相乘）；未處理量可見（censoring 可見）；已否決候選**沉底但不隱藏**（避免自我強化迴圈）。

## Non-Goals

- 不動「絕不自動合併」鐵律：reject 只能由人以 rowID 顯式觸發，校準只影響排序與呈現，任何 apply 仍需人指名。
- 不做比率、不做貝氏合成、不做任何自動降權抑制。
- 單位粒度為 resolver 證據類別（今日恰一類 `author-name-exact`）；「來源 × 證據類別」需要 author 層級的來源歸屬資料，今天不存在——deferred，不假裝可算。
- person 檢視／doctor 的計數呈現、organization 的 MCP 工具面（屬 #259 的 CLI-only 裁決）均不在本 change。
- 不新增任何序列化形狀（#247 store format bump 是明確的不可觸發約束）。

## Capabilities

### New Capabilities

- `resolution-judgement`: 消解判定的記錄（確認／否決）、三態 ledger 的衍生計算、resolver 的已否決跳過、reject 動作、計數呈現。

### Modified Capabilities

- `provenance-reference`: 可附著欄位的封閉列舉增加 resolution verdict 欄位對（`resolution-confirmed`／`resolution-rejected`，value 必填、定位 entry+literal 配對、不做集合成員檢查）——僅驗證層，序列化不變。

## Impact

- Affected specs: `resolution-judgement`（新）、`provenance-reference`（修改）
- Affected code:
  - New: Sources/AkashicEntity/ResolutionLedger.swift、Tests/AkashicKitTests/ResolutionLedgerTests.swift
  - Modified: Sources/AkashicCore/Provenance.swift、Sources/AkashicEntity/PersonResolver.swift、Sources/AkashicEntity/OrgResolver.swift、Sources/AkashicMCPKit/AkashicService.swift、Sources/akashic/Commands.swift、Sources/akashic-mcp/Server.swift、Tests/AkashicMCPTests/（resolvePeople 面）、Tests/AkashicKitTests/（resolver regression）
  - Removed: (none)
