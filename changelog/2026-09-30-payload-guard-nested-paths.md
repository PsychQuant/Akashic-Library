# 2026-09-30 工具描述守衛往下一層看封閉的巢狀路徑表；每條寫入腿都要有 payload 情境（#700）

#672 的守衛（`ToolPayloadKeyGuardTests`）只取回應的頂層鍵，物件底下的陣列或物件的鍵看不到；它的「新增工具要同時加情境」也只擋新工具，擋不到既有工具的新腿——#675 的 `edit_name_segment` 就是這樣漏掉、batch14 R1 verify 才抓到的。使用者 2026-09-30 裁決 (a)：守衛只對一張封閉的巢狀路徑表往下一層，每一列寫明為什麼那一層的鍵要說明；另以 `WriteGateRulings` 的逐腿裁決表為來源，要求每條寫入腿都有一個 payload 情境。

## 巢狀路徑表（`ToolPayloadNestedPaths`）

封閉列舉，六列，都是 #700 本文點名的路徑。路徑的形狀是封閉的三種：`person`（值是物件，取它的鍵）、`items[]`（物件陣列，取元素鍵的聯集）、`people[ref]`（以資料為鍵的字典，取各值的鍵的聯集）。守衛往下**恰好一層**：表外的巢狀物件不看，列入的路徑也不看第二層。

| 工具 | 路徑 | 為什麼那一層的鍵要說明 | 情境取到的鍵 |
|---|---|---|---|
| `akashic_enrich` | `items[]` | 每筆提案的結果只在這一層（補了什麼、來源 reference 寫了沒、哪些值被拒）；#672 點名的 provenance 鍵住在這裡 | 13：additions、alreadyPresent、category、citekey、index、matches、provenanceOmitted、provenancePlanned、provenanceSkipped、provenanceWritten、reason、refused、sourceDigest |
| `akashic_resolve_people` | `people[ref]` | 歧義條目的 personRefs 是不透明 ref，區辨一個人的欄位只在這一層送一次 | 11：currentAffiliation、died、formerAffiliation、formerAffiliationEnd、key、names、namesTotal、observedAffiliation、observedAffiliationAt、openalex、orcid |
| `akashic_update_entry` | `sourcesAdded[]` | add_sources 宣告的每份副本的取得記錄只在這一層 | 6：acquisition、digest、mediaType、note、origin、retrieved |
| `akashic_update_venue` | `nameSegments[]` | edit_name_segment 是判定型寫入，每一段做了什麼只在這一層回報 | 5：action、after、before、name、reason |
| `akashic_update_venue` | `displayNameChanged` | 沒有 authorized 的 venue 改名字段會連帶換掉顯示名；前後值只在這一層 | 2：after、before |
| `akashic_person` | `person` | person key 直查時人物本身的資料都在這一層；頂層只有三個容器鍵 | 4：affiliations、key、names、verdicts |

巢狀鍵的比對與頂層同一條規則：鍵名以識別字邊界出現在該工具說明的任何一處就算數（裁決 (a)，不要求寫成 `items[].<鍵>`）。刻意不寫的鍵在 `ToolPayloadKeyExemptions` 以全名豁免（`items[].reason`）。`testEveryNestedPathIsLive` 要求每一列在至少一個情境裡以宣稱的形狀出現、取得到鍵——形狀不對（宣稱陣列而實際是物件）記成情境問題、守衛紅，不是悄悄取零個鍵。

為了讓這幾列有東西可守，加了兩個情境：`akashic_enrich` 的「dry_run provenance states」（來源齊備、值補了而 reference 刻意不寫、來源只給 digest、ISSN 被拒）與 `akashic_resolve_people` 的「list with distinguishing fields」（三個名字、ORCID／OpenAlex／卒年／現職、已結束與只被觀測到的隸屬）。

## 每條腿都要有情境（`ToolPayloadLegTests`）

兩個來源，缺一不可：

1. **MCP 工具的每個參數**（真 binary `tools/list` 的 `inputSchema.properties`，148 個）：要有情境在 `PayloadScenario.params` 宣告它（124 個），或在 `ToolPayloadLegs.unexercised` 寫一列理由（24 個：`akashic_search` 的查詢條件、`akashic_s2` 其他端點的輸入、`akashic_libraries` 文件型與規則型的規則內容、`resolve_people` 的 `confirm_tiers` 等）。宣告了而 schema 沒有、寫了理由而其實有情境，都紅（不留過期的列）。**擋住 #675 那一類的是這一半**：`update-venue` 在裁決表裡是命令層的一格，逐腿表只涵蓋三個 resolve 命令。
2. **CLI 裁決表**（`Sources/akashic/WriteGateRulings.swift`）：37 個會寫 store 的命令（過閘或不閘），加上三個逐腿命令的 19 條寫入腿。命令與腿先照機械規則對到 MCP（`update-venue` → `akashic_update_venue`、`--drop-venue` → `drop_venue`，19 條腿全部對得上）；對不上的在 `ToolPayloadLegs.commands` 寫一列——`library create／add／remove／set-kind` 對到 `akashic_libraries` 的 `action=…`，另外 16 個只有 CLI、各寫理由（15 個引 `mcp-cli-parity` 的 CLI-only 表）。對到的 MCP 參數必須有情境**宣告**它，只寫理由不算。

**裁決表讀原始碼**：AkashicMCPTests 已連結 `akashic-mcp` 執行檔模組，再連結 `akashic` 會讓一個 test bundle 帶兩個執行檔模組，預設建置系統（Xcode 27 起是 swiftbuild）下沒有驗過，所以沒有改 `Package.swift`。表的寫法是一格一行的字面值；`WriteGateRulingsTests.testTheTableIsWrittenOneEntryPerLine`（AkashicCLITests，那裡 `@testable import akashic`）釘住「逐行讀出來的（多重集合）＝編譯後的兩張表」。讀法對讀不出來的行報錯，不略過。

## 第一次跑抓到的

- **`akashic_update_entry` 的 `remove_zotero_sources`（#680）沒有情境。** 補上乾跑情境之後，它回應的 `zoteroSourcesRemaining`／`zoteroSourcesRemainingTotal` 不在說明裡——寫進說明；`reimportNote` 是給人讀的一句話（結構化的是各筆的 `reimportEffect`），以 advisory 豁免。
- **巢狀鍵沒有說明的**：`items[]` 的 `category`／`additions`／`alreadyPresent`／`refused`，`person` 的 `names`／`affiliations`／`verdicts`，`sourcesAdded[]` 的 `origin`／`retrieved`／`mediaType`／`acquisition`／`note`，`nameSegments[]` 的 `action`／`before`／`after`——寫進說明（只寫鍵名加一句意思）。`items[].reason` 是說明這筆為什麼落在它的 category 的一句話，呼叫端依 `category` 分支，以 advisory 豁免。~~`displayNameChanged` 的 `before`／`after` 由 `nameSegments（action／before／after）` 那一處滿足，沒有另寫（見〈預算〉）。~~（R1 verify 第 8 則：預算理由已不成立，另寫成 `displayNameChanged（before／after）`；見 `2026-10-01-payload-guard-r1-fixes.md`。）
- 幾個情境順手改成真的傳它宣告的參數：`akashic_link` 帶 `remove`、`akashic_create_entry` 帶 `isbn`、`akashic_store_source` 帶 `note`、`akashic_libraries` 的 create 帶 `description`、`akashic_add_person` 帶 `openalex`、`akashic_update_venue` 的 add_names 帶 `type`。

## 預算

~~`tools/list` 從 **51,710** 到 **51,996 bytes**（+286；上限 `StdioE2ETests.toolsListByteBudget` 52,000，**剩 4 bytes**）。為了放進去，`displayNameChanged` 後面原本要寫的「（before／after）」（20 bytes）拿掉了。預算沒有調高（那是使用者的裁決）。~~

~~列入的路徑上還有兩個鍵**沒有情境產生、也沒有寫進說明**，守不到：~~

- ~~`person.unknownFields`（#700 本文點名的那一個）：最短的寫法「／unknownFields」要 16 bytes，超過剩下的 4。~~
- ~~`items[].partial`（識別碼部分解析，只發生在 isbn 這類多值欄位）：最短的寫法「、partial 部分解析的值」要 29 bytes。~~

~~要守它們，得先從別處省出位元組，或回 #578 重新裁決預算。~~

（R1 verify 第 3、7、19 則：上面整段是 2026-09-30 的狀態。03a8e729 把上限調到 54,000 之後「剩 4 bytes」不成立，`person.unknownFields`、`items[].partial` 與另外兩個鍵（`person.orcid`、`items[].provenanceNotWritten`）都補了情境與說明；見 `2026-10-01-payload-guard-r1-fixes.md`。保留上面的原文是因為只留結論，下一個人會以為「預算不夠」這個理由從來沒有存在過。）

## 負控

每一項都是改原始碼、重建、跑測試，再以反向編輯還原並 `cmp` 對注入前的備份（四項皆一致）；判讀前先確認 `Executed N tests` 那一行存在（建置失敗會看起來像通過）。

- **(a) 說明拿掉一個巢狀鍵**：`akashic_person` 的說明刪掉「affiliations／」→ `testEveryPayloadKeyIsDescribedOrExempt` 紅，報「akashic_person：person.affiliations」（Executed 1 test, 1 failure）。
- **(b) 刪掉一條寫入腿唯一的情境**：刪掉 `akashic_resolve_venues` 的 `drop_venue` 情境 → `testEveryToolParameterIsExercisedOrNamed`（「參數 drop_venue 沒有情境宣告它」）與 `testEveryWriteLegInTheRulingTableHasAPayloadScenario`（「resolve-venues --drop-venue：…沒有情境宣告 drop_venue」）紅；那個情境產生的豁免鍵隨之過期，`testEveryExemptionIsLive` 也紅（Executed 15 tests, 5 failures）。
- **(c) 裁決表多一條沒有情境的腿**：`legRulings["resolve-people"]` 加 `"--fake-leg": .notGated(…)` → `testEveryWriteLegInTheRulingTableHasAPayloadScenario` 紅（「akashic_resolve_people 的 schema 沒有參數 fake_leg」）；它不是真的 CLI 旗標，`WriteGateRulingsTests` 的兩條也紅（Executed 16 tests, 3 failures）。對到的參數只在 `unexercised` 寫了理由的那一種（`--confirm-tiers` → `confirm_tiers`）由 `testAWriteLegWithoutAScenarioInTheRulingTableGoesRed` 對判定函式直接驗——`WriteGateRulingsTests` 看不到那一種。
- **(d) 一格改成非字面值的寫法**：`"fmt": .notGated(` 改成 `"fmt": WriteGateRuling.notGated(`（編譯後的表不變）→ 讀法報那一行讀不出來、`ToolPayloadLegs.commands` 的 `fmt` 列過期，`testTheTableIsWrittenOneEntryPerLine` 紅（Executed 2 tests, 3 failures）。

測試裡另有四支對判定函式本身的負控：說明拿掉 `observedAffiliationAt` 時頂層判定不報、巢狀判定報 `people[ref].observedAffiliationAt`；`akashic_update_venue` 的 schema 多一個參數即紅（#675 的形狀）；刪掉 `drop_venue` 的情境兩個判定都紅；裁決表多一條腿、多一個沒有同名工具的寫入命令都紅。

## 誠實邊界

- **情境宣告的參數是宣告。** 情境直接呼叫 `AkashicService`、不經 MCP 的引數解碼：驗得到參數名在真 binary 的 schema 裡，驗不到情境真的傳了它。
- **覆蓋的單位是參數，不是參數的每一個值。** `akashic_files` 的 `action` 有 list 的情境就算有情境，`use` 仍然沒有；值層只在 `ToolPayloadLegs.commands` 點名的地方檢查（`library add` → `action=add`）。
- **巢狀鍵的比對是整份說明的任何一處。** 通用字（`key`、`names`、`index`、`note`）會被別處的同一個字滿足——#672 已記的固有限制，對巢狀一樣。
- **`file add` 在 MCP 面沒有對應的 action**，而 `mcp-cli-parity` 的 `akashic_files` 列把整個 `file` 家族記成 ✅。這一格寫在 `ToolPayloadLegs.commands` 的理由裡，沒有改 parity 表。
- 兩個新守衛不是零實例守衛（`zero-instance-guards` 不加列）：第一次跑就各有實例（`remove_zotero_sources` 沒有情境、18 個巢狀鍵沒有說明，其中 1 個改以 advisory 豁免）。

## R1 verify 之後（2026-10-01）

R1 verify 的 #700 部分：MEDIUM 1、LOW 若干。細節、量測與負對照在 `changelog/2026-10-01-payload-guard-r1-fixes.md`；這裡只列上面被推翻的句子：

- **「預算只剩 4 bytes」與兩個守不到的鍵**（第 3、7、19 則）：已劃掉。`person.unknownFields`、`person.orcid`、`items[].partial`、`items[].provenanceNotWritten` 都有情境產生、說明也寫了；`testTheKeysTheIssueNamedAreProducedByScenarios` 釘住它們真的被產生。
- **「巢狀鍵的比對是整份說明的任何一處」**（第 8、18 則）：收緊成「識別字邊界，且不夾在連續的散文之間」，頂層與巢狀同一條規則。
- **`file add` 只記在測試註解**（第 9 則）：`mcp-cli-parity` 的 CLI-only 表補了 `file add`／`file remove` 一列。
- **表外的巢狀鍵**（第 29 則）：誠實邊界補上量測（54 條路徑、208 個鍵、94 個沒被說明以鍵名的形式提到）。
