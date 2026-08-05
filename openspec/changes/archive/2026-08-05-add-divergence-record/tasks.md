> 每個群組標明它落實哪一條 spec requirement 與哪一個 design 決策。
> Spec：`divergence-record`（新增）、`entity-shape-label`（修訂）、`entity-boundary`（修訂）。Design：D1–D5 與「Implementation Contract」各節。
> `.spectra.yaml` 設 `tdd: true`，每個群組先寫失敗的測試再實作。

## 1. 形狀與載入驗證

> [requirement: An unresolved identity question SHALL be recordable]
> [requirement: The judgment SHALL reuse the provenance vocabulary]
> 依據 design 的 **D1：裸標籤取名 `divergence`**、**D2：判斷型形狀是抽出的共用件，不是複製**、**D5：歧異記錄不帶「已解決」狀態**；
> 形狀取自 design 的 **介面與資料形狀**，拒絕條件取自 **失敗模式** 前四列。

- [x] 1.1 RED — [requirement: An unresolved identity question SHALL be recordable] 新增 `Tests/AkashicKitTests/DivergenceDecodeTests.swift`，五個測試對應 design **失敗模式** 前四列與正常路徑：`testTwoCandidatesLoads`（question + 兩個同形狀 person key → 接受）、`testSingleCandidateRefused`、`testCandidatesSpanningShapesRefused`（一個 person key、一個 work key）、`testJudgementWithoutRestsOnRefused`、`testRestsOnWithoutJudgementRefused`。每個拒絕測試須斷言錯誤訊息指名觸發的條件與涉及的鍵。執行 `swift test --filter DivergenceDecodeTests` 全部失敗（型別尚不存在）
- [x] 1.2 GREEN — [requirement: The judgment SHALL reuse the provenance vocabulary] 新增 `Sources/AkashicCore/Divergence.swift`，內含歧異記錄型別（`question` / `candidates` / 選填判斷）與 `{judgement, rests-on}` 的共用型別。共用型別**不含** `field:`（落實 **D2**）；歧異記錄**不含**任何狀態欄位（落實 **D5**）。執行 `swift test --filter DivergenceDecodeTests` 五個全綠
- [x] 1.3 GREEN — 在 `Sources/AkashicCore/YAML.swift` 的實體形狀封閉集合加入新標籤，並實作該形狀的 decode，套用既有的未知欄位保留與拒絕條件。執行 `akashic validate` 對含一筆歧異記錄的暫時 store 通過

## 2. 序列化正規性

> [requirement: The new shape SHALL be serialized like every other]
> 依據 design **Risks** 的最後一項（與序列化正規化的順序耦合）。

- [x] 2.1 RED — [requirement: The new shape SHALL be serialized like every other] 新增 `Tests/AkashicKitTests/DivergenceSerializationTests.swift`：`testRoundTripByteIdentical`（encode → decode → encode，兩次輸出位元組相同）、`testUnknownFieldSurvives`（帶一個 store 不認得的頂層區塊，讀寫後該區塊逐位元組不變）。執行後失敗
- [x] 2.2 GREEN — 在 `Sources/AkashicCore/YAML.swift` 實作該形狀的 encode：欄位順序固定、`candidates` 與 `rests-on` 依既有規則排序輸出、未知欄位以既有機制附回、寫出前跑編碼自檢（讀回的值與原值相同否則拒寫）。執行 `swift test --filter DivergenceSerializationTests` 兩個全綠

## 3. 消歧操作

> [requirement: Resolving SHALL merge, rewrite references, and delete atomically]
> 依據 design **D3：消歧是原子操作，不是「刪一個檔」**；
> 錯誤行為取自 **失敗模式** 的第五列與最後一列。

- [x] 3.1 RED — [requirement: Resolving SHALL merge, rewrite references, and delete atomically] 新增 `Tests/AkashicKitTests/DivergenceResolveTests.swift`，以注入的假 home 建臨時 store：`testReferencesFollowMerge`（一筆 work 的作者含被併鍵 → 消歧後改為倖存鍵）、`testMergedFilesRemoved`（被併實體與歧異記錄的檔案都不存在）、`testAliasesMergedIntoSurvivor`（被併者的名稱出現在倖存者的名稱清單內）、`testSurvivorOutsideCandidatesRefused`（錯誤須列出實際候選）。執行後全部失敗
- [x] 3.2 GREEN — 新增 `Sources/akashic/DivergenceCommands.swift`，實作消歧子命令：接受歧異記錄識別與倖存者鍵，依序執行合併別名 → 全庫參照重寫 → 刪除。參照重寫沿用既有 citekey 改名路徑已具備的全庫遷移能力（**D3**），不另寫一套掃描
- [x] 3.3 GREEN — 在 `Sources/akashic/CLI.swift` 的子命令清單註冊該命令。執行 `swift test --filter DivergenceResolveTests` 四個全綠
- [x] 3.4 RED — 在 `DivergenceResolveTests` 加 `testPartialWriteFailureReportsAndExitsNonZero`：令其中一筆參照記錄無法寫入，斷言其餘記錄仍被改寫、失敗清單指名失敗的那一筆、且**被併記錄與歧異記錄都未被刪除**（有參照沒改寫成功時刪掉被併記錄，那些參照就永久懸空——比撕裂狀態更糟）。執行後失敗
  > **驗證標的的修正（實作階段發現）**：原文寫「斷言退出碼非零」。SwiftPM 的 executable target 不可被測試 target import，`AkashicKitTests` 到不了 `akashic` 的退出碼。改以「消歧回報 `hasFailures`」為測試標的——那正是退出碼的唯一來源；退出碼本身由 `Sources/akashic/DivergenceCommands.swift` 的一行映射負責（`hasFailures` → `ExitCode.failure`），以人工執行核對。
- [x] 3.5 GREEN — 在消歧的參照重寫迴圈為每筆包上錯誤收容：捕捉、累積、繼續下一筆，結束時報告並依有無失敗決定退出碼。執行 `swift test --filter DivergenceResolveTests` 五個全綠

## 4. 版控前提

> [requirement: Deletion SHALL require version control]
> 依據 design **D4：刪除前驗證版本控制生效**。

- [x] 4.1 RED — [requirement: Deletion SHALL require version control] 在 `DivergenceResolveTests` 加 `testRefusesOutsideVersionControl`：於非 git 目錄建臨時 store，斷言消歧被拒、錯誤訊息說明版本控制是刪除的前提、且所有檔案仍存在（逐檔雜湊比對）。執行後失敗
- [x] 4.2 GREEN — 在消歧命令的刪除步驟之前加入工作樹檢查，不在版控內則拒絕並回報原因。檢查須在**任何寫入之前**執行，避免合併與參照重寫已發生卻無法刪除的半完成狀態。執行 `swift test --filter DivergenceResolveTests` 六個全綠

## 5. 收尾驗證

> 落實 design **驗收條件** 的整體項。

- [x] 5.1 執行 `swift test` 確認全套測試通過，且既有測試無回歸
- [x] 5.2 對 `~/.akashic` 執行 `akashic validate` 與 `akashic doctor`，確認新增形狀未破壞既有 store 的載入（該 store 無歧異記錄，計數應與變更前相同）
  > 結果：`✓ 636 entries、822 people、0 libraries 全部通過`（無歧異註記——該 store 沒有歧異記錄，正確）；`doctor` 多一行 `divergences: 0`。636/822 與磁碟上 `work:`/`person:` 標籤的檔案計數相符。
  > 另做了 CLI 端到端核對（3.4 的人工那一半）：暫時 store 上 `resolve-divergence` 成功路徑退出碼 0、作者鍵改寫、別名併入倖存者、被併檔與歧異檔皆刪除；把一筆參照檔設成 immutable 後重跑，退出碼 **1**、其餘記錄仍改寫、且**沒有刪除任何檔**；解除 immutable 再跑一次即完成（可重跑）。

## 6. Spec 對齊

- [x] 6.1 [requirement: Shape labels SHALL be drawn from a closed set] 確認實作與該條的修訂一致：封閉集合的成員新增有對應的 shape-selection 論證記錄在 `entity-boundary` 的 delta 內，而非只是把標籤加進 enum。逐條對照 design 的 **可觀察行為** 六項，確認每一項都有測試覆蓋（1.1–4.1 的測試清單）
- [x] 6.2 [requirement: Admissions to the entity namespace SHALL be recorded with their reasoning] 確認 `entity-boundary` delta 內的 admission 記錄含兩要素：本形狀決定哪些欄位、以及被同一測試拒絕的對照候選（view）。並逐項核對 design 的 **範圍邊界**——確認實作沒有溢出「在範圍外」列的六項（organization 候選、實體上的 references 欄位、判斷遷移、自動偵測、歧異查詢或圖形化、tombstone）

### 6.x 的核對結果

**可觀察行為 → 測試**（七項，含實作階段補上的第 7 條）：

| # | 可觀察行為 | 覆蓋 |
|---|---|---|
| 1 | store 可承載；無此類記錄的既有 store 位元組不變 | `testLoadReportsDivergence` + 5.2 對 `~/.akashic` 的計數核對 |
| 2 | 記錄自報問題／候選／選填判斷 | `testTwoCandidatesLoads`、`testJudgementWithRestsOnLoads` |
| 3 | 跨形狀候選拒絕 | `testCandidatesSpanningShapesRefused` |
| 4 | 消歧執行合併／重寫／刪除並回報 | `testReferencesFollowMerge`、`testMergedFilesRemoved`、`testAliasesMergedIntoSurvivor` |
| 5 | 不在版控工作樹內拒絕 | `testRefusesOutsideVersionControl` |
| 6 | 序列化與其他形狀一致 | `testRoundTripByteIdentical`、`testWriteOrderDoesNotAffectBytes`、`testUnknownFieldSurvives` |
| 7 | 檢查與佈局報告計入摘要 | 7.2 的手動驗證（兩個命令的輸出） |

**失敗模式七列**：前四列由 `DivergenceDecodeTests` 覆蓋；第五列 `testSurvivorOutsideCandidatesRefused`；第六列 `testRefusesOutsideVersionControl`；第七列 `testPartialWriteFailureReportsAndExitsNonZero`。「候選指名的鍵不存在」一列的落點在實作階段修正（見 design 的〈實作階段的兩處修正〉）。

**範圍邊界核對**：六個「在範圍外」項目均未實作——organization 候選由 `unsupportedShape` 明確擲錯而非默默支援；實體上沒有新增 `references:`；判斷隨記錄刪除、未遷移到倖存者；沒有任何自動偵測；除了第 7 條要求的計數之外沒有查詢或圖形化；沒有 tombstone。

## 7. 承載的可觀察性

> 落實 design **可觀察行為** 第 7 條。此條為實作階段發現 design 漏寫後補上：
> 原契約只說「store 可以承載」，但未要求任何輸出反映它——記錄載入成功卻不出現在
> 任何摘要裡，使用者無從分辨「載入了」與「被靜默忽略」。

- [x] 7.1 RED — 在 `DivergenceDecodeTests` 加 `testLoadReportsDivergence`：以注入的假 home 建臨時 store、寫入一筆歧異記錄，斷言 `LibraryLoad.divergences` 有一筆且 `quarantined` 為空。執行後應通過（載入已實作）；若不通過表示載入路徑有問題
- [x] 7.2 GREEN — 讓 schema 檢查與佈局報告的摘要行含歧異記錄的計數，與既有形狀並列。手動驗證：對含一筆歧異記錄的 store 執行兩個命令，輸出須出現該計數
