# 2026-09-28 #569／#647／#588 的 R2 verify 修正

R2 只審 R1 的兩個修正 commit（`32be9f9a`、`a44ea26f`），六席回報 27 條：3 HIGH、8 MEDIUM，其餘 LOW／INFO。兩條 HIGH 是 R1 的修正自己造成的回歸。

## #569 文件出口：R1 把正當內容改寫成字面標記（HIGH，三席同指）

R1 讓 `documentSafe` 改接 `escapesInDisplay`，這個集合含非 U+0020 的空白、SHY 與私用區。`export-bib` 的預設 stdout（`> refs.bib`、`| pbcopy`）與 `graph` 因此把 NBSP、thin space、U+3000、SHY、造字改寫成字面的 `U+00A0`。這個標記有損，沒有任何 .bib、TeX 或 XML 消費端解得回來。live store 有 16 筆 work 帶著這些字元（U+2009 ×27、U+2002 ×23、U+00A0 ×12、U+00AD ×5）。#569 之前的 `documentSafe` 本來不動它們；人可讀輸出逃脫它們是使用者的裁決，文件出口不在那個裁決裡。

新的 `UnsafeToEmitScalar.escapesInDocument` 從輸出閘的性質扣掉文件的正當內容：
- 非 U+0020 的 Zs；
- SHY；
- 私用區；
- ZWJ／ZWNJ。

另外加上 noncharacter：DA 發現 U+FFFF 原樣通過 graphml 就不是合法 XML。這個問題不是 R1 引入的，舊列舉同樣漏掉；但 R1 重寫了這個函式，就一併處理。TAG 字元、ZWSP、bidi、C0／C1 照舊逃脫。CSL-JSON 走 `documentSafeJSON`，以 JSON 自己的 `\uXXXX` 逃脫，無損，所以不受影響。

ZWJ／ZWNJ 在文件出口保留是**比照**人可讀輸出的裁決所做的類推，不是使用者裁決本身。`akashic_export` 的 bib 與 `akashic_graph` 回到 LLM context，零寬 joiner 串是已記錄的殘餘風險（security、requirements 兩席指出，兩條都是 INFO）。

## #647 預驗漏了 #631 的目的檔檢查（HIGH，DA 真 binary 重現）

`write*` 在內容閘之後還跑 `personWritePlan`、`entryWritePlan`、`assertEntitiesDestination`。R1 的預驗只補了內容閘。DA 的重現：legacy 佈局、未 commit 的 entry 讓 person 先落盤，之後才被拒。現在預驗三種記錄都跑目的檔檢查，形狀同 venue 路徑的先例。

另外兩條：
- **判給已否決這個配對的 org**（MEDIUM，DA）：歧義條目的 orgKeys 不過濾否決，所以照寫會留下 confirmed＋rejected 的矛盾對，而回報是乾淨的 judged。現在這一筆略過並具名；翻轉判定不是這條腿的事。
- **`verdictNotRecorded` 依實際原因選訊息**（MEDIUM，三席）：R1 依 store format 選訊息，format 8–18 的 store 遇到「同配對、理由不同」時，會被錯誤地叫去升 format。

## #588

- 兩面的工具描述補上 `field: issn` provenance 會一併刪除、`referencesRemoved` 回報筆數、理由要留在 git 得自己寫進 commit message（MEDIUM，兩席）。
- changelog 的下一條仍寫「理由只剩 git 這一份副本」，已改掉（MEDIUM，兩席）。
- `two-kinds-of-edits` 的逆操作說明補上一句：`--add-issn` 只加回號，被刪的 provenance 要從 git 的移除前副本取回。

## 文件

- `rendersBlank` 的 doc 寫成是機械掃描的結果，但照它自己寫的判準重跑會命中約 90 個碼位。現在寫明「掃描之後，人工只收參考字形是空白的」，並列出沒收的幾類；U+303F 判定不確定，記在 doc 裡。
- `NameIdentity` 與 `escapingInvisibleScalars` 的 doc 不再只寫 U+2800。
- README 的消毒器表更正：CSL-JSON 不走 `documentSafe`；另補上文件出口不逃脫哪幾類。
- MCP `judge` 的描述補上略過否決、`verdictNotRecorded`、整批先驗。

## 查過、不改

- Codex P2「理由在逃脫膨脹後仍會被截斷」不成立。`displaySafe` 的逃脫支以**輸入** scalar 計預算（#554 R32 D84），而 4,096 位元組的理由至多 4,096 個 scalar，`max: maxStatementBytes` 不會截到它。這條 Codex 沒有以真 binary 重現。

## 測試

新增：
- `ExportBoundaryTests.testDocumentExitsKeepTypographicContentAndStayValidXML`
- `ExportBoundaryTests.testCLIStdoutKeepsTypographicContent`
- `OrgJudgeLegTests.testJudgingToAnOrganizationThatRejectedThePairingIsSkipped`
- `OrgJudgeLegTests.testDestinationChecksRunBeforeAnyWrite`

R1 那支文件出口測試裡「SHY 被逃脫」的斷言改成「SHY 保留」。比對用 `range(of:options: .literal)`：它比 UTF-16，不比 grapheme。負控五組全紅。
