# 2026-09-28 多餘的 venue 邊刪得掉了（#572）

一筆 work 可以有兩條邊指向同一本刊。這個狀態工具自己造得出來：兩條同刊名的 literal 邊各 apply 一次、`--repoint` 改指到本 work 已有邊的 venue、venue 合併之後一條 literal 邊解析到 work 已 key 的 venue（#554 R10／R11 verify 用真 binary 造出過）。造出來之後 `--demote`／`--repoint` 對兩條邊都拒絕（D25：verdict 不帶 index，退役會把另一條邊的證據一起刪），而拒絕訊息與 `validate` 的 warning 都只能說「手改 YAML」。

## 改了什麼

**移除腿，兩面同契約**：CLI `resolve-venues --drop-venue <citekey>:<venueIndex>=理由`，MCP `akashic_resolve_venues` 的 `drop_venue`，同走 `dropVenueEdges`。

- **以 index 定位**，與 `--demote` 同形。重複的兩條邊值相同，以值定位分不出要刪哪一條。同一 work 的多筆以原始 index 給，位移由實作處理。
- **key 邊只在刪完之後同一 venue 仍有另一條 key 邊時可刪。** 那時 venue 上的 confirmed verdict 仍由剩下的邊實例化，不受影響。刪唯一的 key 邊會留下一筆沒有邊的 confirmed，那筆該不該留是判定；拒絕訊息指向先 `--demote`（它退役 confirmed、寫 rejected），再刪 literal 邊。
- **literal 邊一律可刪**：literal 是未判定的狀態，沒有 verdict 以它為前提。
- 理由必填，只進報告（`venueEdgesRemoved`，全文不截斷），不寫進 store、不改 store format。這是使用者 2026-09-27 對三個移除面（#572／#586／#588）的裁決，與 #588 的 `--remove-issn` 同一條。
- 移除前要求那些 work 檔已 commit、沒有未提交修改（`assertRecordsRecoverable`）。
- 整批拒絕、零寫入：缺 `=`、不是 `citekey:index`、理由空白或超過 4,096 位元組、同一條邊在一次呼叫裡出現兩次、越界、work 不存在或 citekey 無法唯一定位、一次超過 200 條。
- 單獨呼叫，不與 apply／reject／repoint／demote／undecided 組合（它改的是邊的數量，其他腿的 index 意義會變）。CLI 另過目標 store 確認閘。

**誠實邊界**：刪光一筆 work 的全部 venue 邊之後，`migrate-venues`（只補沒有 venues 的 work）與 Zotero pull 會從 journaltitle／booktitle／publisher 重新推導——報告以 `emptied` 具名那些 work。

**出路改指**：`apply` 的 `skippedDuplicateVenueEdge`、`repoint` 的 D27 拒絕、`repoint`／`demote` 的 D25 拒絕、`Entry.validate()` 的重複 key 邊 warning、App 側欄的說明，從「手改 YAML」改成 `--drop-venue`。第 27 列那一族（同一 work 多個 confirmed literal）的出路**沒有改**：`--drop-venue` 刪的是邊不是 verdict，那一格至今只能手改 YAML。

## 測試

`VenueEdgeRemovalTests` 8 支：重複 key 邊可刪且 verdict 不動、warning 消失；唯一 key 邊拒絕並指向 `--demote`；兩條 key 邊同時刪拒絕；literal 邊可刪且刪光時具名；同一 work 多筆以原始 index；未提交拒絕；七種輸入錯整批拒絕零寫入；單獨呼叫。負控：拿掉 key 邊前提、拿掉 commit 閘，6 支轉紅。

## 規則

`mcp-cli-parity` 的 `akashic_resolve_venues` 列補兩面契約；`two-kinds-of-edits` 加一列（AI 編輯，store 內不留 verdict 是有記錄的不兌現）；`zero-instance-guards` 第 26、27 列與 `docs/store-format.md` 的出路改寫。
