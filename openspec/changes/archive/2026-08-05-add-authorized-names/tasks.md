## 1. 書寫系統推導（Requirement: At most one name per writing system SHALL be authorized；design D2：script 是推導值，不儲存，且只需 han / latn 粗分割）

- [x] 1.1 純函式輸入字串、輸出 `han` / `latn` / `other` 三者之一：含 CJK 統一表意文字者為 `han`，僅含基本拉丁字母與常見標點者為 `latn`，其餘為 `other`。空字串為 `other`。驗證：`Tests/AkashicKitTests/AuthorizedNameTests.swift` 新增測試涵蓋「謝叔蓉」「森元俊成」→ `han`，「Shwu-Rong Grace Shieh」「Guan, Yongtao」→ `latn`，混合字串（含漢字與拉丁）→ `han`，空字串 → `other`；`swift test` 對該測試由紅轉綠。 (Requirement: At most one name per writing system SHALL be authorized)

## 2. 引用形分類（Requirement: The absence of a designation SHALL be fillable without deciding what cannot be decided；僅供提名與報告，不入 store）

- [x] 2.1 純函式判定一個字串是否為索引系統產生的引用形：含逗號且逗號後的 given 部分至少一個 token 為單字母（可帶點）者為引用形；含逗號但 given 部分全為完整 token 者亦為引用形（姓名倒置）。不含逗號者不是。驗證：測試涵蓋 `Guan, Yongtao` 與 `Key, Timothy J.` 與 `Chang, Y-H.` 判為引用形，`Shwu-Rong Grace Shieh` 與 `謝叔蓉` 判為非引用形；`swift test` 由紅轉綠。 (Requirement: The absence of a designation SHALL be fillable without deciding what cannot be decided)

## 3. Person 的 authorized 欄位（Requirement: An entity SHALL designate which of its names are addressed outward；design D1：authorized 是 names 的子集 list，不是以 script 為鍵的 map）

- [x] 3.1 [P] `Person` 攜帶選填的 authorized 名字集合，預設為空；空集合的記錄仍為良構。驗證：測試建構一個無 authorized 的 `Person` 並斷言其為空、且 `Equatable` 比較不受影響；`swift test` 由紅轉綠。 (Requirement: An entity SHALL designate which of its names are addressed outward)（design D1：`authorized` 是 `names` 的子集（list），不是以 script 為鍵的 map）
- [x] 3.2 person 記錄的 YAML 編解碼保留 authorized 集合，且 round-trip 位元組相同；形狀不是序列時 fail-closed（與 `names` 同）。驗證：測試涵蓋「有 authorized 的 person 編碼後解碼相等且位元組相同」「`authorized:` 為 mapping 時 decode 擲錯」「`authorized:` 缺席時 decode 得空集合」；`swift test` 由紅轉綠。 (Requirement: An entity SHALL designate which of its names are addressed outward)

## 4. Organization 的 authorized 欄位（Requirement: An organization SHALL be a record shape of its own；design D7：Organization 沿用同一個 authorized 概念但保留其 names 的時間軸）

- [x] 4.1 [P] `Organization` 攜帶選填的 authorized 名字集合，與其名稱時間軸並存且互不影響。驗證：測試建構一個有兩段名稱歷史且designate 當前名稱的 organization，斷言時間軸與 authorized 各自可讀；`swift test` 由紅轉綠。 (Requirement: An organization SHALL be a record shape of its own)
- [x] 4.2 organization 記錄的 YAML 編解碼保留 authorized 集合，round-trip 位元組相同，形狀不符 fail-closed。驗證：測試涵蓋 round-trip 位元組相同與形狀不符擲錯；`swift test` 由紅轉綠。 (Requirement: An organization SHALL be a record shape of its own)

## 5. 不變式驗證（Requirement: An entity SHALL designate which of its names are addressed outward；Requirement: At most one name per writing system SHALL be authorized）

- [x] 5.1 驗證拒絕 authorized 含不在 names 內的字串，錯誤訊息點名該字串與所屬記錄的 key。驗證：測試斷言擲出的錯誤訊息同時含該字串與 key；`swift test` 由紅轉綠。 (Requirement: An entity SHALL designate which of its names are addressed outward)
- [x] 5.2 驗證拒絕同一書寫系統有兩個 authorized，錯誤訊息點名該書寫系統與兩個候選。驗證：測試以兩個拉丁名字為 authorized，斷言錯誤訊息含兩者；另一測試以一個漢字名與一個拉丁名為 authorized，斷言通過；`swift test` 由紅轉綠。 (Requirement: At most one name per writing system SHALL be authorized)
- [x] 5.3 上述兩條不變式在 person 與 organization 上行為一致，且在 `validate` 子命令的實際執行路徑上生效（不只在型別層）。驗證：測試以暫存 store 寫入違規記錄後執行 validate 路徑，斷言非零結果；`swift test` 由紅轉綠。 (Requirement: An entity SHALL designate which of its names are addressed outward)

## 6. 對外名字解析（Requirement: Outward-facing name resolution SHALL be script-aware and SHALL NOT fall back to name order；design D3：names 的順序不再帶語意，且不保留位置式 fallback）

- [x] 6.1 [P] `Person` 依請求的書寫系統解析對外名字，順序為：書寫系統相符的 authorized → 任一 authorized → key。**不** fallback 到 names 的任一元素。驗證：測試涵蓋四階解析的每一階，特別斷言「只有 `Guan, Yongtao` 一個 name 且無 authorized」時結果為 key 而非該字串；`swift test` 由紅轉綠。 (Requirement: Outward-facing name resolution SHALL be script-aware and SHALL NOT fall back to name order)（design D3：`names` 的順序不再帶語意，且**不**保留位置式 fallback）
- [x] 6.2 [P] `Organization` 的解析在 key 之前多一階「當前有效名稱」：書寫系統相符的 authorized → 任一 authorized → 當前有效名稱 → key。驗證：測試涵蓋無 authorized 但有當前名稱時回當前名稱、兩者皆無時回 key；`swift test` 由紅轉綠。 (Requirement: Outward-facing name resolution SHALL be script-aware and SHALL NOT fall back to name order)（design D7：organization 沿用同一個 `authorized` 概念，但**保留**其 `names` 的時間軸）

## 7. Format marker（Requirement: Removing the positional convention SHALL bump the store format marker；design D4：format marker 由 2 bump 到 3）

- [x] 7.1 store 的支援上限由 4 提高到 5（apply 期間更正：design 初稿寫「2 → 3」是照 `docs/store-format.md` §5.0 已過時的對照表，實際 `StoreVersion.supported` 是 4），且 `ensureLayout` 對新 store 寫出的 marker 為 5。舊 marker 的 store 仍可載入。驗證：測試涵蓋「marker 為 6 的 store 被整體拒絕且訊息含 6 與 5」「marker 為 4 的 store 可載入」「新建 store 的 marker 為 5」；`swift test` 由紅轉綠。 (Requirement: Removing the positional convention SHALL bump the store format marker)

## 8. 一致性報告（Requirement: Records carrying no authorized name SHALL be reported, not rejected；design D6：authorized 選填，缺席是 doctor 的報告項不是 validate 的錯誤）

- [x] 8.1 `doctor` 報出沒有任何 authorized 名字的記錄清單（person 與 organization 各自計數），而 `validate` 對同一 store 仍通過。驗證：測試以含無 authorized 記錄的暫存 store 執行 doctor 路徑，斷言輸出含該記錄的 key 與計數；同一 store 的 validate 斷言通過；`swift test` 由紅轉綠。 (Requirement: Records carrying no authorized name SHALL be reported, not rejected)（design D6：`authorized` 選填；缺席是 `doctor` 的報告項，不是 `validate` 的錯誤）

## 9. 渲染路徑改讀解析結果（Requirement: Every published rendering of an entity SHALL use the resolved outward-facing name）

- [x] 9.1 書目匯出（`.bib`）與引用資料匯出（CSL-JSON）印出的作者名為解析結果，無 authorized 時印出 key。驗證：測試以無 authorized 的 person 匯出，斷言輸出含 key 且不含 `Guan, Yongtao` 式的引用形；`swift test` 由紅轉綠。 (Requirement: Every published rendering of an entity SHALL use the resolved outward-facing name)
- [x] 9.2 關聯式匯出（人物列與關係列）與工具介面（人物查詢回應）印出的名字為解析結果。驗證：測試斷言匯出的人物列名稱欄與工具回應皆為解析結果；並以搜尋確認樹內不再有任何渲染路徑讀 `names.first`；`swift test` 由紅轉綠。 (Requirement: Every published rendering of an entity SHALL use the resolved outward-facing name)

## 10. Migration（Requirement: The absence of a designation SHALL be fillable without deciding what cannot be decided；design D5：機械提名 + 人工採納，不是自動決定）

- [x] 10.1 提供一條 migration 路徑，對既有記錄提名 authorized：某書寫系統僅一個候選則採用、多候選中恰一個非引用形則提名該筆、仍多於一個則留空並報告。預設只報告不寫入，明確指示才寫。驗證：測試涵蓋三種情況各一，並斷言未給寫入指示時 store 未變；`swift test` 由紅轉綠。 (Requirement: The absence of a designation SHALL be fillable without deciding what cannot be decided)（design D5：migration 是機械提名 + 人工採納，不是自動決定）
- [x] 10.2 對真實 store 執行 dry-run 並記錄結果。**驗收軸更正（apply 期間）**：初稿寫「三類計數（採用／提名／留空）加總等於 person 記錄總數」是錯的——那三個是**逐書寫系統**的計數，一個雙語的人會同時貢獻一筆採用與一筆提名（實測 867＋136＋1 = 1004 ≠ 868）。正確的恆等式在**逐人**軸：全部指定完 ＋ 仍有歧義 ＋ 無可用名字 ＋ 原本已指定 = person 總數。驗證：實際執行並記錄三個數字與總數，於變更說明中留存該次輸出。 (Requirement: The absence of a designation SHALL be fillable without deciding what cannot be decided)

## 11. 規格文件（design D3 + D4 的落地紀錄）

- [x] 11.1 `docs/store-format.md` 的人物檔一節不再宣稱名字序列的第一個是顯示名，改為說明 authorized 欄位與解析順序；版本對照補齊 marker 3／4／5 三個缺漏條目並註明各自為何 non-additive。**驗收軸更正（apply 期間）**：初稿寫「搜尋確認『第一個是顯示名』字樣已不存在」，但保留「為何廢除」的說明比抹除字樣有價值——實際驗收為**不再有任何 normative 宣稱**，僅存兩處提及皆為歷史說明（§3.1 的理由段、§5.0 的版本對照）。且新增段落含 authorized 的形狀、兩條不變式與三階解析（person；organization 四階）。 (Requirement: Removing the positional convention SHALL bump the store format marker)
