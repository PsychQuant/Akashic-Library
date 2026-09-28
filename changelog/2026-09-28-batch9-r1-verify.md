# 2026-09-28 #569／#647／#570／#588 的 R1 verify 修正

R1 ensemble verify（六席：四個 lens、devil's advocate、Codex）回報 35 條：3 HIGH、11 MEDIUM、其餘 LOW／INFO。本輪修掉三條 HIGH 與範圍內的 MEDIUM／LOW；不在範圍內的記在最後一節。

## #569 輸出閘

**`documentSafe` 改用同一份性質**（HIGH，三席同指）。它是 `akashic_export`（bib、csl-json）、`akashic_graph` 與 CLI `export-bib`／`graph` stdout 的消毒，先前是一張手抄的舊列舉。#569 把輸出閘改成性質時它沒有跟著改，所以 TAG 字元、ZWSP、SHY 經匯出原樣進 LLM context；它的 doc 還寫著「集合與 `displaySafe` 完全相同」。現在：

- `documentSafe` 逃脫 `UnsafeToEmitScalar.escapesInDisplay`，另外保留 TAB、LF 與反斜線（文件的結構與語法），ZWJ／ZWNJ 保留。
- CSL-JSON 改走新的 `documentSafeJSON`：以 JSON 自己的 `\uXXXX` 逃脫、連 ZWJ／ZWNJ 一起，無損（解回來逐字相同）。先前寫成 `U+202E` 標記，解不回原字元。

**渲染成空白的另外四個碼位**（DA）。U+13441／U+13442 EGYPTIAN HIEROGLYPH FULL／HALF BLANK（Lo）、U+16FE4 KHITAN SMALL SCRIPT FILLER（Mn）、U+1D159 MUSICAL SYMBOL NULL NOTEHEAD（So）不在任何一類。DA 用真 binary 建出一筆唯一名字是空白象形字的 venue，也建出一筆靠 Khitan filler 規避近重複的攣生 venue。它們與 U+2800 一起收進 `UnsafeToEmitScalar.rendersBlank`，名字閘與輸出閘共用。這份清單只保證名稱掃描（FILLER／BLANK／NULL／SPACE）的結果，已寫進 §5.7 與 venue-entity spec 當誠實邊界。

**`library list` 的分隔符**（logic）。程式自己放的 U+3000 被整串消毒印成 `\u{3000}`；改成只消毒 store 字串。

**文件更正**：`jsonEscape` 的「集合全在 BMP」、changelog 裡誤寫成原字元的 ZWNJ／ZWJ 逃脫字串。

**有記錄、不改的三項**：

- 人可讀輸出現在逃脫 NBSP、thin space、en space、SHY。這是使用者裁決的直接後果，changelog 已量過（62 個空白、5 個 SHY）。影響另外兩處：App 的未歸戶作者列會顯示 `\u{00AD}Abby C. King`；從人可讀輸出複製 literal 餵給以值定位的腿（`--un-split`、`--drop-author`）會對不上，這時要改用 MCP 或 `get-entry --json`。
- ZWJ／ZWNJ 在人可讀輸出一律保留，不看脈絡。security 席實測 160 個交錯 joiner 組成的零寬二進位字串原樣印出。這是使用者裁決的殘餘風險，比 TAG 字元弱、同一類。
- `references extract`／`nominate`（#617 的檔案，本輪不動）：extract 的輸出是 nominate 的輸入，私用區字元現在以逃脫文字進入 title 與人名的比對器，會多出 `u`、`e000` 這種雜訊 token；兩個 JSON 出口也沒有走 `escapingUnsafeScalars`，ZWJ／ZWNJ 原樣輸出。已在 #617 留言。

## #647 organization 逐篇判定

**整個寫入集合先驗**（HIGH，Codex）。先前只驗收到 verdict 的目標 org；person、entry、上級機構被改寫的 holder org 到寫入當下才被拒，前面的檔已經落盤。現在對 `changedPeople`、`changedEntries`、`changedOrgKeys` 的最終版本逐一跑寫入閘，全部通過才寫。

**理由沒寫進去要說出來**（logic）。verdict 以 (holder, literal) 配對、不帶作者位索引：同一筆 work 兩個作者位是同一個 literal 時，兩個位置都歸戶，第二句理由卻被去重吃掉，而回報照列兩筆。現在那一列帶 `verdictNotRecorded`，CLI 印 ⚠。format < 19 時提名層的 confirmed 擋下逐篇判定，走同一個欄位。形狀同 resolve-people 的 judge。回報裡的理由也改成不截斷。

`VerdictRecordKey` 的 doc 不再寫死 `judgedRules` 的個數（曾停在「兩個」）。

## #570 venue 名字規格

- `@trace` 的 code 清單指向了 #617 的 references 檔案（archive 時 Spectra 依當時的 diff 自動填入），改成實際承載這條 Requirement 的 `Venue.swift`、`NameIdentity.swift`、`Models.swift`、`VenueNameInvariantTests.swift`。
- 「`validate` 與 `doctor` 會報告」改成「`validate`、MCP `akashic_doctor` 與 App」：CLI `doctor` 不印 per-record 問題（DA 實測）。

## #588 ISSN 移除

**帶 provenance 的號移除不掉**（MEDIUM，兩席）。指向那個號的 `field: issn` reference 在號被移除後成了孤兒，寫入閘會拒絕整個呼叫，而 venue 的 reference 沒有任何移除面（#587），出路又回到手改 YAML。現在那些 reference 在同一次寫入一併移除，`issnRemoved` 逐號回報 `referencesRemoved`；git 閘已確認移除前的檔有副本。

**理由只在報告裡**（MEDIUM，兩席）。回報曾截在 600 scalar，而入口收 4,096 位元組，較長理由的尾段在唯一一份紀錄裡消失；現在不截。文件寫成「理由進 git 歷史」是過度宣稱：git 保存的是移除前的檔，理由要留在 git 得由操作者寫進 commit message。這句已在 changelog、`mcp-cli-parity`、`two-kinds-of-edits`、`zero-instance-guards` 第 36 列與程式註解改掉。

豁免註記的措辭改成與程式一致（「在這裡消毒一次」）。

## 測試

新增：

- `ExportBoundaryTests.testDocumentExitsUseTheOutputGateProperty`。寫這支測試時踩到一件事：Swift 的 `String.contains` 以 grapheme 為單位，ZWJ 與 TAG 是 extender、併進前一個 cluster，單獨找永遠找不到——「不含」的斷言會恆真。所以改比 scalar。
- `VenueNameInvariantTests.testOtherBlankRenderingCodePointsAreNotPartOfAName`
- `TerminalOutputSafetyTests.testLibraryListKeepsItsOwnSeparator`
- `OrgJudgeLegTests.testInvalidHolderOrganizationRefusesTheWholeBatchBeforeAnyWrite`、`testSecondReasonForTheSamePairingIsReportedAsNotRecorded`
- `ISSNRemovalTests.testProvenanceOfTheRemovedISSNGoesWithIt`、`testTheReasonIsReportedInFull`

負控九組，七組由腳本判紅；理由截斷那一組腳本的計數沒抓到失敗格式，手動重跑確認紅。拿掉 person 那一行預驗仍綠，這是預期：測試裡的 person 本身合法，承重的是 organization 那一行，它的負控是紅的。

## 不在範圍內、記錄

- `assertRecordsRecoverable` 重構後 #573 的三個拒絕分支只有「不在 git 工作樹」有訊息斷言（regression 席，LOW）。
- 重號 warning 把所有 venue key 放在同一則訊息裡、不設上限：線性家族，只影響手改的 store（INFO）。
