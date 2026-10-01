# 2026-10-01 #700 R1 verify 之後：四個點名的鍵有情境、鍵名比對收緊、`file add` 進 parity 表

#700（工具描述守衛往下一層看封閉的巢狀路徑表）R1 verify：MEDIUM 1、LOW 若干。finding 編號是那份 verify 報告的編號。2026-09-30 的 changelog
（`2026-09-30-payload-guard-nested-paths.md`）被推翻的句子已在原處劃掉並指到這裡。

## 1. 四個點名的鍵沒有情境產生（第 3、7、19、26 則）

**成立，而且理由已經不成立。** #700 本文點名 `items[].provenanceNotWritten` 與 `person.unknownFields`，另外 `items[].partial`、`person.orcid` 也在列入的路徑上；
四個都沒有情境產生，說明拿掉它們守衛照綠。檔頭與 changelog 寫的理由是「預算只剩 4 bytes」，而 03a8e729 已把上限調到 54,000
（量測 51,997 → 52,381 是 #703 的部分，→ 52,515 是這一張，仍剩約 1,485 bytes）。

- **`items[].provenanceNotWritten`**：`apply with a write failure` 情境——實跑、來源齊備，那一筆的目的檔設成 immutable（與 `EnrichServiceTests`
  同一個做法），`writeFailed` 有它、reference 沒寫進去；情境結束前還原旗標，世界的暫存目錄才刪得掉。同時帶出頂層的 `writeFailed`（先前記在
  「沒涵蓋的腿」）。
- **`items[].partial`**：`dry_run partial identifier` 情境——`isbn` 欄位給兩個 token，一個解得出、一個解不出。
- **`person.unknownFields`、`person.orcid`**：`key with orcid and unknown fields` 情境——另建一個帶 ORCID 與未知欄位的人（`cheng-che` 兩個都沒有，
  所以 R1 verify 第 26 則說巢狀路徑 `person` 只取到四個鍵）。
- **說明**：`akashic_person` 列出「有才出現 orcid／unknownFields」（第 26 則：先前「person 帶 key／names／affiliations／verdicts」讀起來像封閉清單）；
  `akashic_enrich` 補「該筆帶 partial」；`provenanceNotWritten` 本來就在。
- **釘住**：`ToolPayloadKeyGuardTests.namedKeys` 是一張**點名的清單**（不是「情境產生的都算」），`testTheKeysTheIssueNamedAreProducedByScenarios`
  要求每一個真的被產生；`testGuardGoesRedWhenANamedKeyIsDroppedFromTheDescription` 對四個鍵逐一拿掉說明、要求巢狀判定報出它。
- **過期的註解**（第 7、19 則）：`ToolPayloadKeyGuardTests` 檔頭與 `ToolPayloadScenarios` 的「預算只剩 4 bytes」改成現況；2026-09-30 changelog 的預算一節
  劃掉並指到這裡（保留原文：只留結論，下一個人會以為這個理由從來沒有存在過）。

## 2. 鍵名比對收緊（第 8、18 則）

**成立，但語法只補得了一部分。** 先前頂層與巢狀用同一條規則：鍵名以識別字邊界出現在該工具說明的**任何一處**就算有說明。
`indexRebuilt 說 index 有沒有重建` 裡的 `index` 說的是 index 的重建，卻讓 `items[].index` 過關。

**規則（頂層與巢狀同一條，`mentionsIdentifier`）**：識別字邊界，**且不夾在連續的散文之間**——跳過空白之後，左右至少有一邊是標點、括號、反引號，或文字（行）
的頭尾。`（origin／retrieved／…）`、`回報 issnAdded、issnDropped`、`truncated＝true`、`skipped（具名）` 算；`說 index 有沒有重建`、`以 citekey 或 doi 指名`
（兩邊都是字）不算。選這一條而不是更嚴的規則，理由是量出來的（346 個頂層與巢狀鍵，修正前的說明，真 binary 的 `tools/list` 配 97 個情境的回應（本張加情境之前）；數字是舊規則過、新規則不過的鍵）：
兩邊都要緊鄰標點（不跳過空白）112 個、跳過空白後兩邊都要標點 83 個、只看左邊 59 個、只看右邊 30 個，「至少一邊」7 個。掉出來的絕大多數是
「回報 issnMediumRecorded」「列在 provenanceSkipped」「回 key 與 updated」這種**合法的**寫法，逼說明改成守衛喜歡的樣子沒有意義；「至少一邊」只擋下純散文的提及。

**前後量測**（被無關的散文提到才算有說明的鍵——舊規則過、新規則不過，用修正前的說明算）：

| | 頂層 | 巢狀 | 是哪些 |
|---|---|---|---|
| 修正前 | 6 | 1 | `akashic_doctor` 的 `truncated`、`akashic_record_divergence` 的 `id`、`akashic_resolve_organizations`／`akashic_resolve_people`／`akashic_resolve_venues` 的 `skipped`、`akashic_store_source` 的 `digest`；巢狀是 `akashic_enrich` 的 `items[].index` |
| 修正後 | 0 | 0 | 說明改成鍵名的形式：`truncated＝true`、`id／hasJudgement`、`skipped（具名）`、`回 digest；`、`index（提案序）、citekey、` |

**誠實邊界——語法區分不了「回應鍵」與「同名的輸入鍵」。** 第 18 則點名的八個鍵裡，`index` 被擋下了；其餘（`items[].citekey`／`sourceDigest`、
`sourcesAdded[].digest`、`nameSegments[].name`／`reason`、`person.key`）同時是這個工具的輸入（`{name, match?, … reason（必填…）}`、`目標 citekey（…）`），
輸入那一側的提及**本來就在鍵名的位置上**，拿掉回應那一側的說明守衛仍可能綠。修正後對 43 個不同的（工具, 鍵）（`after`／`before` 兩條路徑共用）量**鍵名位置的提及次數**：
34 個恰一次（對拿掉那一處敏感）、8 個兩次以上（`items[].citekey` 2、`sourceDigest` 3、`namesTotal` 2、`sourcesAdded[].digest` 5、`after`／`before` 2、`reason` 2、
`person.key` 2）、1 個是豁免的 `items[].reason`。再嚴一級（只認左邊是標點，診斷用、沒有進守衛）：沒有任何一處「左邊是標點」的提及的有 `category`、`citekey`、`partial`、
`provenanceOmitted`、`provenanceSkipped`、`person.key`、`person.orcid`——除了 `citekey`（它的五處提及全是輸入側或散文，只因右邊有標點而過關），其餘都是「動詞 鍵名（」的形式，
守衛不把它當成問題，因為同一個形式在全部說明裡佔多數（上面 59 個）。
**這是裁決 (a)（整份說明的任何一處）的固有限制**；要補得了，得讓表的每一列寫明每個鍵的「預定提及」（逐鍵錨點），那是另一個設計，本輪不做。

## 3. `file add` 沒有 MCP 對應、parity 表也沒有 CLI-only 的一列（第 9 則）

新列在 `mcp-cli-parity` 的 CLI-only 表：`file add`／`file remove`，有理由缺席——註冊與除名 store 是改 registry，部署層的名冊，與橫切選項表 `--config` 同一個理由；
`akashic_files` 的 `use` 只在名冊內切換 session 的 active store。`akashic_files` 那一列的 ✅ 是 list／use 的功能重疊，不含 add／remove（先前沒有逐 action 裁決）。
`ToolPayloadLegs.commands` 的理由改成指向這一列。觸發條件：出現需要在 MCP session 內註冊新 store 的流程時重開。

**四步稽核**（該檔〈怎麼機械檢查這張表真的封閉〉）：① `Server.swift` 的 `Tool(name:)` 34 個；② CLI 註冊型別 56 個命令（文件裡的 regex 對 `S2Cmd` 會吃掉數字、
解成 `Cmd`，手動對到 `s2`——那是稽核寫法的已知限制，`akashic-guards parity-table-drift` 用的是 Swift 的解析）；③ 與兩張表逐一對：無零裁決格，新列的第一欄
`file add`／`file remove` 對得到 `FileCmd` 底下的兩個子命令；④ 橫切 `ParsableArguments` 兩個（`LibraryOptions`、`FileConfigOptions`），仍在橫切表裡。
`akashic-guards parity-table-drift` 輸出「MCP 34｜CLI 56｜橫切 2」、rc 0。

## 4. 封閉表以外還有約 90 個巢狀鍵（第 29 則）

**這是裁決 (a) 的預期後果，不是實作錯誤；** 誠實邊界補上量測。2026-10-01 用一支用完即丟的傾印（沒有進 repo：本張加情境之前的 97 個情境的原始回應＋真 binary 的 `tools/list`，
套本輪的規則）量：表外還有 **54 條**一層路徑、**208 個**鍵，其中 **94 個**沒被說明以鍵名的形式提到（含 4 個以資料為鍵的字典項——`issnMediumRecorded` 的 ISSN、
`ambiguousSourceClaims` 的來源鍵——契約鍵約 90 個）。包括寫入腿的回應（`resolve_people` 的 `split[]`／`dropped[]`／`unsplit[]`、`update_entry` 的
`zoteroSourceRemovals[]`／`fieldRemovals[]`、`update_venue` 的 `referencesRemoved[]`、`resolve_venues` 的 `venueEdgesRemoved[]`）、`doctor` 的
`recordIssues{}` 與 `sources{}`，以及 `akashic_person` 的另外兩個容器 `publications[]`（六個鍵）與 `co_authors[]`。表內 `person` 那一列的理由
（「不往下看等於整筆人物資料沒有守衛」）對它們同樣成立——每多一列就是一次預算，使用者裁決是預算只花在列入的路徑上。**沒有守衛維持這個量**
（傾印不在 repo 裡）；寫進 `ToolPayloadKeyGuardTests` 的誠實邊界，下次要不要擴表時以它為基線。

## 預算

`tools/list`（真 binary，單行不含換行）：51,997（03a8e729）→ 52,381（#703 R2）→ **52,515**（本張；上限 54,000，剩 1,485）。本張 +134 bytes：
`akashic_person` +37（`orcid`／`unknownFields`）、`akashic_enrich` +20（`partial`）與 +33（`index`、`citekey`）、`akashic_update_venue` +20（`displayNameChanged（before／after）`）、
`akashic_store_source` +13（`回 digest；`）、三個 `skipped（具名）` 各 +5、`truncated＝true` 與 `id／hasJudgement` 各 −2。

## 負控

每一項都是改原始碼、（動到 `Server.swift` 時）重建 binary、跑 `ToolPayloadKeyGuardTests`（13 支），再以備份還原並 `cmp`（七項皆一致）；判讀前先確認
`Executed N tests` 那一行存在（建置失敗會看起來像通過）。

| 改動 | 結果（`Executed 13 tests`） |
|---|---|
| 寫入失敗情境不設 immutable | 3 則失敗：`provenanceNotWritten` 沒有情境產生、頂層 `writeFailed` 沒帶出、拿掉說明時報不出它 |
| partial 情境改成單一 ISBN | 2 則失敗（`partial` 沒有情境產生、拿掉說明時報不出它） |
| person 情境拿掉 ORCID 與未知欄位 | 4 則失敗（`person.orcid`、`person.unknownFields` 各兩則） |
| 說明拿掉 `partial` | 5 則失敗：守衛本體報 `items[].partial`，與兩支負控 |
| 說明拿掉 `provenanceNotWritten` | 5 則失敗（同上，報 `items[].provenanceNotWritten`） |
| 說明拿掉 `orcid／unknownFields` | 6 則失敗（守衛本體報 `person.orcid`、`person.unknownFields`） |
| 鍵名比對退回只看識別字邊界 | 7 則失敗：散文提及不算的六個斷言、`testGuardGoesRedWhenTheOnlyMentionBecomesRunningProse`（把 `index（提案序）` 換成 `以 index 是提案序`，舊規則看不出差別） |

另外，**修正前的說明**（`Server.swift` 還原到 03a8e729 的樣子）配上新規則，`testEveryPayloadKeyIsDescribedOrExempt` 紅、報出上面〈前後量測〉那七個鍵——那一次就是「修正前」欄的量法。
