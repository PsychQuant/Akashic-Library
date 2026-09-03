# venue `variant` 分割的 verify 修正（#422 verify R1）

#422 的實作跟著 #406 一起 merge（PR #447），從未被獨立 verify——#406 的 verify（PR #452）
沒有一個字提到它。2026-09-02 補跑六席（4 lens ＋ DA ＋ Codex）**全部 FAIL**，收斂在三個 HIGH：

1. **spec 的 `SHALL` 零實作**：`venue-entity` spec 寫「Names listed in the `variant` partition
   SHALL NOT carry temporal fields」並附 Scenario「A variant carrying a date fails validation」，
   而 `Venue.validate()` 完全不看時間欄位。遷移的「帶時間整筆跳過」只保證遷移自己不造出這種
   記錄，擋不了手改 YAML 與未來寫入面。
2. **format 14 的「實測依據」與程式相反**：五處出貨文件（`StoreVersion.swift`、`docs/store-format.md`、
   `README.md`、`LibraryStore.swift` 的註解與**使用者可見的 why 字串**）寫 format-13 binary 讀到
   `variant:`／`paginated:` 會 `rejectUnknownKeys` 整檔 quarantine；實際 `VenueYAML.decode` 走
   `captureUnknownBlocks` 的 tolerant-preserve，format 13 那一列早四天就對同一層的 `issn:` 實測過
   同一件事。**bump 本身站得住**（沿用 format 11／13「保留而不解讀」的裁決），錯的只是證據句。
3. **遷移對 `authorized` 為空的記錄把全部名字標成 variant**：補集規則對空集合回傳全部，實測三筆
   （`wikipedia`、`stanford-encyclopedia-of-philosophy`、`bulletin-of-the-institute-of-mathematics-academia-sinica`
   ——最後一筆的 note 自述是新舊系列沿革），三筆的對外顯示名都是它們自己 variant 清單裡的字串。
   而 `add-venue --names A B` 建檔時 `authorized` 刻意留空（「指定是人的判斷」），所以這不是三筆
   歷史資料的問題，是建檔的預設產物。

## 修法（DA 裁決：blocking 三項 ＋ in-scope 九項）

- **B1** 三筆記錄退回 **unclassified**（刪 `variant:` 區塊，`names` 一字不動）——spec 明文允許的
  誠實狀態；不指定 `authorized`（那是權威形的判定）、bulletin 現在不補 `start`／`end`（守衛在 B1
  當下還不存在，補了會做出 spec 禁止而沒人出聲的矛盾記錄；且改版年份是從 URL 推的）。資料修正
  在 store repo 本機 commit，沿革另立 issue。
- **B2** 五處假實測依據改成量到的事實；bump 理由改用既有裁決。
- **B3** 遷移加 `authorized.isEmpty → 不分類` 守衛，新桶 `noAuthorized` 在乾跑報表點名交人。
- **I1** `Venue.validate()`：variant 內的名字其 `names` 項帶時間欄位 → error。判準
  `DateRange.makesTemporalClaim` 與遷移共用。
- **I3** 分割互斥改呼叫 `AuthorizedNames.validateDisjointPartitions`（`NameIdentity`：收空白、
  **不**大小寫摺疊——實測 32 筆遷移 variant 全是大小寫異寫，摺疊會整批誤報）。
- **I2** `VenueVariantMigrationTests`（五桶分類、乾跑不寫、二次 no-op、未追蹤拒寫進 `failed`）；
  遷移的實跑逐筆 do/catch、乾跑走同一組寫入閘。
- **I4** `akashic venue` 的「沿革：」標題改掉，每項就地標 〔authorized〕／〔variant〕，不重列。
- **I5** `updateVenue` 的 doc 不再說「附加 variant」（它只 append 進 `names`，不標分割）。
- **I6** `paginated` 有閘而 `variant` 沒有：不是矛盾——判準是「有沒有 pre-bump 遷移」，註解指向
  format 13 的 doctrine。
- **I7** `singleName` 桶拆出 `allAuthorized`。**I8** spec `@trace` 去掉兩個編輯器檔。
  **I9** `mcp-cli-parity` CLI-only 表頭停止寫死列數。

## 不做

- 不回退 format 14。不加 `variant` 的 write gate（會讓遷移在 bump 前跑不動）。
- `variant` 的寫入面、遷移 `nextStep` 的過期 format 目標、孤兒 variant 的嚴重性、
  `displayName` 在 `authorized` 為空時的行為、`zero-instance-guards` 補列、bulletin 沿革：
  各自開 follow-up issue（見 #422 的 verify report）。
