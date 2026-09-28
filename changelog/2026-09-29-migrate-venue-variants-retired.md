# 2026-09-29 `migrate-venue-variants` 退場（#567）

## 問題

`migrate-venue-variants`（#422，format 13 → 14 的一次性遷移）用補集規則分類：對「`variant` 為空、`names` 多筆、無時間欄位、`authorized` 非空」的 venue，把 `names − authorized` 全部標成 `variant`。

這個前提在 #554 之後為假。`update-venue --authorize X` 刻意把換下來的舊指定留在 names、未標（D1，使用者 2026-09-12），產物正好滿足上述四個條件。#554 R2 verify 以真 binary 實測：同一筆 venue 在 `--authorize` 之前乾跑印「沒有可分類的 venue」，之後印「將分類 1 筆 → variant: Y」。D1 裁定程式不替呼叫端多說「Y 是異寫」，而這條命令存在的理由就是機械地說那句話。

#554 R15（D41）已讓 `--apply` 一律拒絕，但命令、`@Flag apply` 與乾跑路徑都還在：一個永遠不會成功、看起來卻可用的旗標。live store 的遷移工作已歸零（2026-09-12 乾跑「沒有可分類的 venue」），format 14 早已部署。

## 改了什麼

依 `no-compat-fallback` 第 3 條（退場後刪掉，不留著當保險；先例是 #325 的 `migrate-work-types`）：

- 刪除 `Sources/AkashicStoreIO/VenueVariantMigration.swift`、`VenueCommand.swift` 裡的 `MigrateVenueVariants`、`CLI.swift` 的註冊。
- 刪除 `Tests/AkashicKitTests/VenueVariantMigrationTests.swift`（三支測試，全部只測這條遷移）；`FormatBumpHintTests` 移除它的目標、`SanitizationBoundaryTests` 移除它的兩個清單項（Error → 文字入口、clip-only sink）。
- `WriteGateRulings.swift` 移除那一格。`WriteGateRulingsTests` 對執行期命令樹做雙向比對，重量：CLI 葉命令 56、裁決表 56、兩個差集皆空（不寫 19、不閘 17、逐腿 3、過閘 17）。記進 `zero-instance-guards` 第 37 列的量測段。
- `mcp-cli-parity` CLI-only 表那一列**劃掉、不刪**，寫明退場理由，保留裁決史（同 `migrate-work-types` 列）；同檔另兩處提到它的地方標明已退場。`parity-table-drift` 守衛會檢查劃掉的列不得仍註冊。
- README、`docs/store-format.md` 的 format 14 那一格、`StoreVersion.bumpHint` 的 doc、`AkashicService` 與兩個測試檔的註解、`venue-entity` spec 兩個 `@trace` 的 code 清單同步。`bumpHint` 仍服務 `migrate-person-identity` 與 `migrate-venues`，保留。

**一併裁掉的：`variant` 的 format 14 寫入閘**（代裁，見下）。`LibraryStore.assertVenueWritable` 原本刻意不對 `variant` 設閘，理由寫在程式註解：它有一條必須跑在 bump 之前的遷移，設閘會讓遷移跑不動；判準是「有沒有 pre-bump 遷移」。#554 R20 的補記寫明這一格留給 #567 一併裁。遷移刪除之後，依同一條判準答案變成「沒有」，所以補上閘：format < 14 且 `variant` 非空即拒，與 `paginated` 的閘同形。format-13 binary 讀到頂層 `variant:` 會原樣保留而不解讀，把異寫法當一般名字顯示、不出聲。format-13 store 零實例（2026-09-29 唯讀量測：live store 的 `store.yaml` 是 format 18）。

## 測試與負控

- 新增 `VenueStoreTests.testVariantWriteRefusedBelowFormat14`：format 13 寫帶 variant 的 venue 被拒、零副作用；不帶 variant 照常可寫；format 14 起可寫。
- 新增 `VenueVariantWriteTests.testAddVariantIsRefusedBelowFormat14`：服務層 `update_venue` 的 `add_variant` 在 format 13 整個呼叫拒絕、訊息含 14、venue 逐欄不變。
- 負控一：把閘的條件改成永不成立（`format < 0`），上面兩支各自轉紅（各 2 則斷言失敗，分兩次跑）；每次以備份還原後 `cmp` 逐位元組相同。
- 負控二：把 `mcp-cli-parity` 那一列的刪除線拿掉，`akashic-guards parity-table-drift` 報「表列了 `migrate-venue-variants` 而它已不在 CLI.swift」；還原後 `cmp` 相同、守衛回到「三面皆同步」。
- `WriteGateRulingsTests`、`DestructiveTargetGateTests`、`FormatBumpHintTests`、`SanitizationBoundaryTests`、`VenueVariantWriteTests`、`PackageManifestTests` 全綠。

## 誠實邊界

- 一個仍在 format 13、尚未遷移的 store（新 clone 的 store repo、或從別處帶進來的）自此沒有補集遷移可跑。要標異寫，先 bump 到 14，再用 `update-venue --add-variant` 逐筆標——判定型寫入，不再有機械分類。這一條路在 D41 之後本來就已經關了，這裡只是把命令也拿掉。
- 新的寫入閘也會擋下 format-13 store 上經 `writeVenue` 寫出 `variant` 的操作（`--add-variant`、#565 起合併帶過去的 variant）。`fmt` 不經 `assertVenueWritable`（它只跑 `validate()`），所以不受這道閘管。零實例；訊息指向 bump 到 14。
- `openspec/changes/archive/` 與舊 changelog 裡的提及是歷史記錄，沒有改。
