# venue 的 verdict 數逼近 decode 預算時出聲（#499，裁決：候選 3）

第 13 條邊把 resolution verdict 落在**被判定的記錄**上。對 person 有界；對 venue 不是——一本刊的 verdict 數＝被歸戶的作品數，
`akashic-venue-works` 每補完一本大刊，venue 檔就長一截（`psychological-methods` 2026-09-04 實測 1,352 筆、268 KB）。唯一的守衛
是 decode 硬預算（`AliasEventBudget.maxExpandedNodes = 200,000` 節點），撞上時整檔 quarantine、venue 消失。

使用者裁決（2026-09-04）：**候選 3**——不改序列化位置，在硬預算的一半設 warning、達門檻重開裁決。候選 1（per-literal 聚合）
會把 #464 死 verdict 掃描與 #463 的 12 格 holder 遷移剛建好的 per-holder 前提打回原形；候選 2（sidecar ledger）是正確的長期
形狀但 blast radius 是那整套機制加 format bump，今天沒有一本刊接近門檻。

- `AliasEventBudget.nodesPerVenueVerdict = 9`（**量測值**：2026-09-01 14,031 節點／1,556 筆）；
  `venueVerdictWarningThreshold = maxExpandedNodes / 2 / nodesPerVenueVerdict` ＝ 11,111 筆。門檻由換算得出、不是憑空的數字，
  `VenueVerdictBudgetWarningTests.testThresholdIsHalfTheDecodeBudgetInVerdicts` 釘住換算與「live 最大刊在門檻外」。
- `LibraryStore.venueVerdictBudgetIssues(in:threshold:)`：只數 `resolutionVerdictFields` 的 reference（增長來源就是它們），
  達門檻的 venue 各一筆 warning 級 `OwnedIssue`（owner＝venue key），訊息說出數字、門檻與處置；併入 `perRecordIssues`
  （`venueVerdictBudgetPrefix`／`venueVerdictBudgetWarnings`，與 #464／#453 同形）。
- 兩面：CLI `validate` 計數行、MCP `doctor` 的 `recordIssues.venueVerdictBudgetWarnings`；源碼掃描釘住。App 側欄「記錄」Section 渲染計數（#487）。
- `zero-instance-guards` 第 16 列（✅ 寫，理由「裁決依賴守衛」——不寫的話候選 3 就退化成「等它壞」）；
  `entity-backlink-completeness` 第 13 條加 venue 側 O(catalog) 註記與觸發後的形狀。
- **不做**：放寬 `maxExpandedNodes`（那是把 O(catalog) 留給下一本大刊）；聚合或 sidecar（達門檻再議）。
