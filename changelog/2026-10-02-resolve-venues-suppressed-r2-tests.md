# 2026-10-02 `resolve-venues` 的 `suppressed`：每個否決鍵一份的快取有測試、寫入腿不組它有守衛（#712 R2）

#712 R2 verify 裡屬於 #712 的三則（第 3、10、15 列）。三則都是**測試**的缺口，不是行為的缺陷：R1 的程式是對的（R2 verify 第 3 列用 release
binary 對兩筆被否決拼法不同的 work 實測，各自報各自的拼法），但改錯了不會有任何測試變紅。本輪沒有改 `VenueResolver` 或 `AkashicService`
的任何一行。

## 每個否決鍵一份的快取（R2 verify 第 3 列，MEDIUM）

R1 把「依字串排序的前 5 個被否決拼法」快取在每個否決鍵上（`RejectedSpellings.shown`），第一次有列需要時才排序。它決定每一列 `suppressed`
帶的是**哪幾個**拼法——#712 的「哪些」那一半。R2 verify 把快取改成整個函式共用一份，R1 的十個 `VenueResolverSuppressedTests` 與
`VenueSuppressedByNormalizationTests` 全綠：每個情境只有一個否決鍵有被壓住的列（`testRejectionIsPerWorkPerVenue` 有兩筆 work，但只有一筆
產生被壓住的列）。

新測試 `testEachRejectedKeyReportsItsOwnSpellingsAndTotal`：三筆 work、兩個 venue、四個 (work, venue) 否決鍵——兩個同 venue 不同 work
（`a2020` 一個拼法、`b2021` 兩個），兩個同 work 不同 venue（`c2022` 對 `psychometrika` 一個、對 `psychological-methods` 三個），每個鍵恰有一條
被壓住的邊。斷言四列各自的 `rejectedLiterals` 與 `rejectedLiteralsTotal`。只以 work 或只以 venue 為鍵的快取也會在這裡紅。

**負對照**：把 `rejectedNorm[rejectedKey]?.shown = shown` 那一段換成函式層級的一個 `var sharedShown: [String]?`（第一列排好的那份給所有列用）
→ 新測試紅（`b2021` 那一列帶了 `a2020` 的 `["Psychometrika"]`）；以反向編輯還原後綠。

## 寫入腿傳 `reportingSuppressed: false`（R2 verify 第 10 列）

R1 效能修正的一半住在 `AkashicService` 的兩個呼叫點上：apply＋reject 組合腿的前置列表傳 `false`，主路徑傳「apply 與 reject 都空」。翻回 `true`
不會改變任何輸出（那兩條腿不讀 `suppressed`），只有 CPU 與記憶體退步，所以行為測試抓不到。

新測試 `testWriteLegsPassReportingSuppressedFalse`（源碼掃描）：`Sources/` 裡每個 `VenueResolver.resolve(`（定義它的檔除外）都必須**顯式**傳這個
引數，而且全部的值恰是 `false` 與 `(apply ?? []).isEmpty && (reject ?? []).isEmpty` 各一次。新增呼叫點時會紅——那時決定它是不是列表腿，再改這張清單。

**負對照**：組合腿的 `reportingSuppressed: false` 改成 `true` → 紅；反向編輯還原後綠。

## 歧義那一個斷言比的是 `[]` 與 `[]`（R2 verify 第 15 列）

`testNotReportingSuppressedLeavesCandidatesAndAmbiguitiesUnchanged` 的分身叫 `Psychometrika 2`，`matchingKey` 與 `Psychometrika` 不同，兩個 report 的
`ambiguities` 都是空的。R1 的 changelog 說它涵蓋「candidates／ambiguities 與列表腿相同」——ambiguities 那一半是空話。改成分身與 `psychometrika`
同名（真的歧義），被壓住的那條邊放在第三個 venue（歧義一向不被抑制，被壓住的列不能與歧義共用同一個名字），並先斷言三個前提：列表腿恰有一列
`suppressed`、一個歧義、一個候選。

`VenueResolverSuppressedTests` 10 → 12。

## 沒有做的

- **「同一個拼法」用 canonical equivalence（Swift `String ==`）還是位元組相等**（R2 verify 第 26 列）：仍待使用者確認，與 R1 相同，本輪沒有改。
- **people／organization 的列表**：#721。
