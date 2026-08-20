## 0. 追溯

每條 spec requirement 與每個 design 決策落在哪些任務上。**這張表是驗收的入口**——
實作完成後逐列確認，缺一列就是有東西沒做。

| 來源 | 標題 | 落在 |
|---|---|---|
| spec (MODIFIED) | Two or more hits within the nominating tier SHALL be reported as ambiguity | 1.4、2.3、6.4、7.1 |
| spec (ADDED) | A judged pairing SHALL resolve one occurrence and SHALL carry its judgement | 1.1、1.3、2.2、6.2、7.2 |
| spec (ADDED) | A judged pairing SHALL be applied only when the named position still holds the named literal | 1.5、2.4、3.2、7.3、8.2 |
| spec (ADDED) | A judgement SHALL nominate the same literal elsewhere, with its provenance visible | 2.1、2.3、6.5、7.4 |
| design | 決策 1：以 protocol 抽出四個欄位，不新增 `ResolutionTier` case | 1.2、1.3、1.5 |
| design | 決策 2：型別保證由欄位形狀自動保住，不靠紀律 | 1.4 |
| design | 決策 3：判定的 rule 參與 `confirmedByLiteral`（傳染），錯配交既有兩道閘 | 2.1、2.3、6.5、7.4 |
| design | 決策 4：證據走被判 person 的 `references`，不進 verdict | 6.6 |
| design | 決策 5：CLI 只給逐 id 顯式，不給篩選式批次 | 3.1 |
| design | Implementation Contract → Behavior | 6.2、6.4、6.5 |
| design | Implementation Contract → Interface / data shape | 1.2、1.3、1.5、3.1、4.1、4.2 |
| design | Implementation Contract → Failure modes | 1.1、2.4、3.2 |
| design | Implementation Contract → Acceptance criteria | 6.1–6.6、7.1–7.4、8.1、8.2 |
| design | Implementation Contract → 範圍邊界 | 本檔不含任何 out-of-scope 項；5.1 確認 delta 標題相符即為邊界檢查 |

## 1. 型別與提名層（AkashicEntity）

- [x] 1.1 寫失敗測試：`JudgedPairing` 對空白 judgement 建構回 nil。測試檔
      `Tests/AkashicKitTests/JudgedPairingTests.swift`；驗收＝該測試在型別尚不存在時
      無法編譯、型別加入後轉為紅→綠
- [x] 1.2 在 `Sources/AkashicEntity/PersonResolver.swift` 定義 `AuthorPairing` 協定
      （citekey／authorIndex／literal／personKey 唯讀）並讓既有 `ResolutionCandidate`
      conform。驗收＝既有測試全數維持綠（無行為改變）
- [x] 1.3 定義 `JudgedPairing`（conform `AuthorPairing`，額外持 judgement，failable
      init 對空白拒收，無 tier 無 restsOn）。驗收＝1.1 轉綠
- [x] 1.4 寫失敗測試：以型別反射斷言 `AmbiguousMatch` 不具備單數成員 `personKey`
      （手法同既有 `PersonCLITests` 斷言 `Person` 無 `works` 成員）。驗收＝紅→綠且
      不需要修改 `AmbiguousMatch`
- [x] 1.5 把 `PersonResolver.apply` 改為接受任一 conforming 型別的序列，寫入邏輯與三道
      守衛（記錄存在／索引有效／該位置仍是該 literal）逐字不變。驗收＝既有 apply 測試
      全綠，且新增一條測試證明 `apply` 吃得下 `JudgedPairing`

## 2. Verdict 與傳染（AkashicEntity）

- [x] 2.1 在 `Sources/AkashicEntity/ResolutionLedger.swift` 定案判定用的 rule 字面值
      （小寫連字號、通過 `^[a-z][a-z-]{0,60}$`、與既有三個字面值語意可區分），
      並補一條測試斷言它通過弱血統揭露的字面檢查、不被顯示成「非標準rule」
- [x] 2.2 寫失敗測試：判定寫出的 verdict 其 judgement 欄同時含操作者原文與該 rule 尾註。
      驗收＝紅→綠
- [x] 2.3 寫失敗測試：某 literal 在 A 篇被判定後，同 literal 在 B 篇的 occurrence 於重跑
      `resolve` 時以 `confirmedElsewhere` tier 出現，且提名理由逐字含該 rule 字面值。
      驗收＝紅→綠
- [x] 2.4 寫失敗測試：重複套用同一筆判定後，該作者位仍指向同一人且該 person 的
      references 未新增第二筆相同 verdict（既有 `appendIfAbsent` 的冪等）

## 3. CLI 面（akashic）

- [ ] 3.1 在 `Sources/akashic/Commands.swift` 的 `resolve-people` 新增可重複的判定旗標，
      收 `<citekey>:<authorIndex>:<personKey>` 與 judgement 文字。**不新增**任何篩選式
      批次判定旗標。旗標的確切形狀（單旗標兩段 vs 兩個成對旗標）在此定案並回填
      design 的 Open Questions
- [ ] 3.2 判定被守衛略過時（記錄不存在／索引越界／該位置已非該 literal／已是 `.key`），
      在報告中**具名列出**被略過者與原因，不靜默、不中止其餘判定。驗收＝新增一條 CLI
      測試斷言略過訊息含該三段形 id
- [ ] 3.3 判定路徑的所有 store 衍生字串（citekey／literal／judgement）依既有顯示面紀律
      消毒或帶理由豁免。驗收＝`DisplaySinkCoverageTests` 維持綠

## 4. MCP 面（AkashicMCPKit／akashic-mcp）

- [ ] 4.1 在 `Sources/AkashicMCPKit/AkashicService.swift` 讓 `resolvePeople` 收 per-id 的
      判定清單，與 CLI 走**同一條** service 函式（`entity-backlink-completeness` 執行
      細節 2 的單一實作路徑）
- [ ] 4.2 在 `Sources/akashic-mcp/Server.swift` 的 `akashic_resolve_people` schema 新增
      對應參數。驗收＝`StdioE2ETests` 的工具數斷言與 schema 斷言更新後轉綠
- [ ] 4.3 更新 `.claude/rules/mcp-cli-parity.md` 的 `akashic_resolve_people` 列，載明
      兩面契約的差異（CLI 逐 id 顯式且不提供批次；MCP per-id 顯式）

## 5. Spec 與文件

- [ ] 5.1 [P] 把 delta spec 的 MODIFIED 與 ADDED requirements 併進
      `openspec/specs/person-resolution/spec.md`（由 archive 流程執行，本項只確認 delta
      的 requirement 標題與既有檔逐字相符，避免 MODIFIED 對不上）
- [ ] 5.2 [P] 在 `changelog/` 新增本輪紀錄，寫明「判定的作用範圍」這個關鍵 trade-off
      與它被反轉一次的理由（不傳染 → 傳染）

## 6. 真實 store 驗收

- [ ] 6.1 判定前先記錄基線：`resolve-people` 的歧義列數、`confirmedElsewhere` 未處理數、
      全庫 `Author.literal` 計數。**基線要先記**（既有教訓：事後挑欄位看「像不像乾淨」
      會漏掉寫入）
- [ ] 6.2 對 `chen2006decision` 與 `huang2015symptom` 各自「C.-H. Chen」所在的作者位判給
      `chun-houh-chen`，judgement 引用兩篇論文在該作者位登記的機構皆為
      Institute of Statistical Science, Academia Sinica
- [ ] 6.3 判定後跑 `akashic validate`，驗收＝全綠
- [ ] 6.4 重跑 `resolve-people` 並**逐筆解釋**歧義集合的每一個增減——不得只看總數。
      預期減 2；任何額外增減都要查清楚落在誰身上（既有教訓：補 alias 後歧義少了 28 而非
      預期的 27，多的那筆落在另一個人身上並已 reject）
- [ ] 6.5 確認其餘「C-H Chen」occurrence 出現 `confirmedElsewhere` 提名且理由含判定的
      rule 字面值；確認裸 `--apply` 對它們仍然拒絕
- [ ] 6.6 把判定所依據的承重來源寫進 `chun-houh-chen` 的 `references`（依 #280 的分工，
      證據不進 verdict）

## 7. Spec requirement 逐條驗證

實作完成後逐條確認 spec 的 requirement 真的被滿足——這不是重複第 1–6 節，是**反向**檢查：
從 requirement 出發問「哪個測試或哪次執行證明了它」。

- [ ] 7.1 驗證 `Two or more hits within the nominating tier SHALL be reported as ambiguity`
      ——指出證明它的測試名或執行輸出（歧義仍不可 apply、且仍可接受 judgement）
- [ ] 7.2 驗證 `A judged pairing SHALL resolve one occurrence and SHALL carry its judgement`
      ——指出證明空白 judgement 建構失敗、以及 judgement 原文進了 verdict 的測試名
- [ ] 7.3 驗證 `A judged pairing SHALL be applied only when the named position still holds the named literal`
      ——指出證明「位置對不上就略過且具名回報」與「重複套用為 no-op」的測試名
- [ ] 7.4 驗證 `A judgement SHALL nominate the same literal elsewhere, with its provenance visible`
      ——指出證明 confirmed-elsewhere 提名出現、理由含 rule 字面值、且裸 apply 仍拒絕的
      測試名或執行輸出

## 8. 收尾

- [ ] 8.1 全套 `swift test` 零失敗
- [ ] 8.2 Mutation 驗證：把 `JudgedPairing` 的空白 judgement 檢查改成永遠通過，1.1 必須
      變紅；把「該位置仍是該 literal」守衛拿掉，3.2 的略過測試必須變紅。以反向編輯還原
      （不用 checkout——既有教訓：checkout 會回滾真修改）
