# 2026-10-01 名字分類的判定面一律留判定記錄；store format 22（#564）

使用者 2026-10-01 裁決（#564）：名字分類的判定面——person 的 `authorize-names`、venue 的 `--add-variant`／`--authorize`／`--unauthorize`、organization 的 `--authorize`（CLI 與 MCP 兩面，共五個面）——都是判定型寫入（`two-kinds-of-edits` 的 AI 欄），一律留 judgement 記錄：每次指定、撤回、標異寫都在 `references` 寫一筆 `field: authorized`／`variant` 的判斷型 reference，**理由必填、證據 digest 可空**；對既有值說「確認」也留一筆（先前是無聲的 no-op）；代價是升 store format 21 → 22。#600 同日裁決：既有機械值不跑全量 campaign、按需判定，所以**不回填**。

**organization 的 `--unauthorize`／MCP `unauthorize` 不在這五個面裡**：#557 的裁決只說「先提供 --authorize」，撤回腿未經裁決（#557 的 verify 發現，另案處理）。本 change 不動它——不要求理由、不寫記錄、不收 `judgement`；理由單獨跟著它是用錯（拒絕）；與 `--authorize` 同一次呼叫時，理由只套用到 `--authorize` 的記錄。測試釘住這一點（`testOrganizationUnauthorizeNeedsNoReasonAndLeavesNoRecord` 等）。

## 為什麼

`DivergenceResolve.authorizedDemotedByMerging` 分不出「人確認過的對外形」與 bootstrap 的機械值：venue 的 470 筆 authorized 幾乎全是 `VenueBootstrap` 取第一個名字的機械慣例（#563 起 bootstrap 不再寫），人用 `--authorize` 確認過的與它在 store 裡長得一樣，所以合併只能一律提醒不擋；它的 doc 早就寫著觸發條件（「#564 裁「留」且落地後升成拒絕條件」）。本 change 讓「人判定過」寫得進 store，合併端據此把帶記錄的降級升成拒絕，機械值仍是提醒。

## 契約

### 記錄的形狀與單一解析器

`references` 裡一筆判斷型 reference：`field` 是 `authorized` 或 `variant`（它說的分割）、`value` 是名字、statement 以**封閉三個動作**之一開頭、接全形冒號與理由（`NameClassificationRecord.parse` 是唯一解析器，不得類推第四個）：

| 動作 | 何時寫 |
|---|---|
| `指定：理由` | 名字成為那個分割的成員 |
| `確認：理由` | 對已經是成員的名字再說一次（含只差位元組而被換成 canonical 的舊指定） |
| `撤回：理由` | 名字離開那個分割（venue 的 `--unauthorize`；同書寫系統被換下的舊指定，理由前綴「同書寫系統改指定「X」——」；被抬進 authorized 的 variant，`field: variant`，理由前綴「改指定為 authorized——」） |

```yaml
references:
- field: authorized
  value: Psychometrika
  judgement: 指定：期刊官網刊頭
  rests-on: []
- field: authorized
  value: PSYCHOMETRIKA
  judgement: 撤回：同書寫系統改指定「Psychometrika」——期刊官網刊頭
  rests-on: []
```

- **理由必填、證據可空**：venue 沿用 `judgement`／`--judgement`（至多 4,096 位元組）與 `rests_on`／`--rests-on`（至多 20 個 digest）；organization 新增 `judgement`／`rests_on`；`authorize-names --apply` 新增 `--judgement`（整批一句、不帶證據——一個批次共用同一組 digest 等於宣稱每個人的名字都依據同一份文件）。缺理由整個呼叫拒絕、零寫入（讀 store 之前，CLI 是用法錯誤 64）。**一次呼叫一句理由，套用到該次寫下的每一筆記錄**（連帶的撤回由程式在前面說出原因）。
- **記錄錨定在 names，不在分割**：附著條件是「value 是這筆記錄的名字之一」，不要求名字仍在那個分割內——撤回之後名字離開 authorized，判定史仍在、記錄照樣載入。分類的現況仍是分割清單本身，記錄是 provenance。`field: authorized` 上的其他 reference（擷取型、帶 rests-on 的一般判斷）維持舊語意；`field: variant` 只收名字分類記錄、只在 venue 收。
- 位元組完全相同的記錄不重寫（append-only，`byteExactKey`）；回報 `judgementsRecorded`（這次實際寫下的筆數）。
- venue 的名字分類腿不得與 `paginated`／`clear_paginated` 同一次呼叫（兩個判定各要自己的理由）。
- **只由名字分類面寫與保留**：`update-person` 的 `references` 不收（只經 `authorize-names`）；venue 的 `--remove-reference` 不刪（`variant` 明文拒收、`authorized` 只命中記錄時具名拒絕）；`--edit-name-segment` 移除一個名字的最後一段時被記錄擋下；`repair-venue-names` 把指著某拼法的記錄算 pinned。`--authorize`／`--unauthorize` 換下或撤回名字時，只有名字分類記錄**以外**的 `field: authorized` reference 擋。

### store format 22 與部署順序

format-21 binary 對這種記錄整檔 quarantine（三個成因各自足夠：空 rests-on 的判斷型在平面 init 拒收、撤回記錄的 value 不在 authorized、venue 的 `field: variant` 走附著驗證的封閉 default）。寫入閘（`LibraryStore.assertNameClassificationRecordsWritable`）對 format < 22 具名拒絕（訊息含 `store format ≥ 22` 與升級前置）；`StoreVersion.supported` 升到 22。**無資料遷移**（這種記錄在 format 21 寫不出來）。

**升級順序**：CLI、`akashic-mcp`、App 三個 binary **全部**升到 v22 世代**之後**，由使用者手動把 store 的 `format:` 改成 22（live store 目前是 18，19～21 的升級前置一併適用；marker bump 前不 push store repo）。**`authorize-names --apply` 自此不再替人寫 store marker**——它先前結尾無條件寫 `StoreVersion.supported`，在 format 22 下會在沒有人要寫的 store 上安靜地把 marker 從 18 升到 22。升 marker 是使用者的動作。

### venue 合併

- 被併者的 authorized 若會被合併降級、而它對那個名字持有**任何** `field: authorized` 名字分類記錄，合併**拒絕**（preview 與實跑共用前置，`wouldDemoteJudgedAuthorized`）：訊息逐名列出名字與最後一筆記錄，出路是在被併者 `--unauthorize`、或在倖存者 `--authorize`（都要理由）。沒有記錄的機械值維持提醒。判準是「有任何記錄」而不是「最後一筆是指定或確認」。
- 其餘名字分類記錄：名字在合併後的倖存者上分類與被併者相同時逐位元組搬到倖存者（`referencesCarried`）；不同時以 `wouldLoseFields` 拒絕並說出名字與兩邊分類。person 合併維持原狀（本來就拒絕被併者有、倖存者沒有的 authorized 與任何非 verdict reference）。

## 實測（live store，唯讀，2026-10-01）

person 4,575（全有 authorized）、work 2,575、venue 485（470 筆有 authorized、41 筆有 variant）、organization 13、divergence 1；`field: authorized` 或 `field: variant` 的 reference **0** 筆，statement 以三個動作前綴開頭的 reference **0** 筆；store marker **18**。所以今天這些記錄一筆都不存在、合併拒絕必然不觸發、format 22 的寫入閘必拒（零實例守衛，見 `zero-instance-guards` 第 74 列）。

## 測試

全套 `swift test --build-system native`：`Executed 4546 tests, with 1 test skipped and 0 failures (0 unexpected)`（唯一的 skip 是 `MigrateProvenanceCLITests.testWriteFailureIsListedAndExitsNonZero`，這台機器的檔案系統不支援 `chflags`，與本 change 無關）；`swift build --build-system native -Xswiftc -warnings-as-errors` 通過；`bash .githooks/run-guards.sh` rc=0（含 `plugin-store-format-parity`：兩份宣告與 `StoreVersion.supported` 一致，format 22）。

| 測試 | 驗什麼 |
|---|---|
| `NameClassificationRecordTests`（20 個，Kit） | 單一解析器（三動作、前綴不符或理由空白回 nil）；附著錨定 names（撤回後仍載入、value 不是記錄的名字拒收、空 rests-on 的非文法判斷型拒收、`field: variant` 只在 venue、既有擷取型與帶 rests-on 的一般判斷維持舊語意）；三種 holder 的 format 22 寫入閘（format 21 拒、format 22 寫得進去也讀得回）；位元組去重的 append |
| `NameClassificationJudgementTests`（27 個，服務層） | venue 三條腿缺理由整批拒絕零寫入、各寫恰好一筆且形狀正確、對既有值寫確認、被換下與被抬出 variant 的名字各寫一筆撤回、撤回後史留存、第二次同一句確認不重寫、證據套用到每一筆、與 `paginated` 不同一次呼叫、理由與證據的上限；organization `authorize` 同一組、`unauthorize` 不要理由不寫記錄、理由單獨跟著它拒絕、兩條腿同一次呼叫時理由只套用到 `authorize`；只由名字分類面寫與保留四處（`update-person` 拒收、移除面不刪、名字最後一段被擋、`repair-venue-names` 算 pinned、換下／撤回不被記錄擋） |
| `NameClassificationMergeTests`（8 個） | 帶記錄的降級在 preview 與實跑都拒絕；「有任何記錄」（最後一筆是撤回也拒）；機械值仍合併並提醒；分類一致的記錄逐位元組搬、variant 記錄隨名字搬；分類不一致以 `wouldLoseFields` 拒絕；person 合併維持原狀 |
| `AuthorizeNamesJudgementTests`（7 個） | `--apply` 缺理由拒絕且早於讀 store、理由上限不截斷、乾跑不需要理由、每個寫入的名字各一筆、已有 authorized 的人不寫、format 21 零寫入、`--apply` 永遠不寫 marker |
| `NameClassificationCLITests`（5 個，真 binary） | `update-venue`／`update-organization`／`authorize-names` 的 `--judgement`／`--rests-on`：缺理由用法錯誤 64 早於開 store（對不存在的 store 路徑也是）、寫出的記錄逐筆核對、organization 撤回腿不要理由不寫記錄、format 21 具名拒絕且 marker 不動 |
| `NameDesignationStdioTests` 多兩個（真 binary、stdio） | venue 與 organization 的 `judgement`／`rests_on` 到得了服務層；畸形的 `rests_on`（少一層括號）整個呼叫拒絕 |
| `ToolPayloadScenarios`／`ToolPayloadScenariosResolve` 改寫 | 每個回應鍵出現在工具說明裡（#672、含新的 `judgementsRecorded`）；每個參數有情境宣告（#700、含 organization 新的 `judgement`／`rests_on`） |
| 既有測試改寫 | 約 70 處呼叫三條腿的既有測試補上 `judgement`（機械加的 fixture 理由）；釘住 21 的三個測試改成 22（`StoreVersion.supported` 相關）；`VenueVariantWriteTests.testAddVariantIsRefusedBelowFormat14` 逼出一個順序裁決：format < 14 的 variant 寫入要先說 14、不是 22——名字分類記錄的閘放在 `assertVenueWritable` 所有格式世代閘的最後 |

第一輪全套抓到的紅：`DisplaySinkCoverageTests`（兩個 `Self.maxStatementBytes` 的插值沒有具名的 `display-safe-exempt`）、`SanitizationBoundaryTests`（三個擲出點：`judged` 裸引數、兩個 Int 插值）、`ToolPayloadKeyGuardTests`／`ToolPayloadLegTests`（新參數與新回應鍵沒有情境）——都是新守衛在現場的作用，不是退步。



## 負對照

每個 mutant 改一處、重編、跑名字分類的 71 個測試（`NameClassification*`、`AuthorizeNamesJudgementTests`、`NameDesignationStdioTests`；M18 另加 `Format13GateTests`、`KnownLayerEvolutionTests`），以**反向編輯在同一個偏移量還原**並以 `cmp` 對事先存下的副本確認逐位元組相同。數字是 XCTest 的 failures（斷言數，不是測試數）；每一行都先確認有 `Executed N tests` 行。

| mutant | 結果 |
|---|---|
| M01 venue 不寫名字分類記錄 | 25 |
| M02 共用入口不要求理由（venue 與 organization 都走它） | 20 |
| M03 附著不錨定 names（記錄得在 authorized 內） | 40 |
| M04 format 寫入閘放行 | 17（四個 format 21 拒絕測試） |
| M05 合併不拒絕帶記錄的 authorized 降級 | 2 |
| M06 合併一律搬名字分類記錄（不看分類是否一致） | 1（`testDisagreeingClassificationRefusesTheMerge`） |
| M07 `--remove-reference` 也刪名字分類記錄 | 2 |
| M08 對已是對外形的名字不寫「確認」 | 5 |
| M09 被換下的舊指定不寫撤回 | 5 |
| M10 `update-person` 收名字分類記錄 | 1 |
| M11 記錄不去重（位元組相同的也再寫） | 4 |
| M12 `paginated` 可與名字分類同一次呼叫 | 6 |
| M13 organization 不寫名字分類記錄 | 11 |
| M14 organization 不要求理由 | 7 |
| M15 名字最後一段被刪時不擋名字分類記錄 | 第一輪 **0**（被 store 邊界的孤兒附著驗證擋下、擲出的是另一句訊息，測試只看「有擲」）→ 收緊成斷言編輯面自己的「判定史不刪」後 1 |
| M16 `repair-venue-names` 不把名字分類記錄算 pinned | 第一輪 **0**（改寫後的 validate 也會報，判斷項裡有別句含 `reference`）→ 收緊成斷言「指著這個拼法」後 1 |
| M17 換下／撤回的 pinned 檢查把名字分類記錄也算進去 | 16 |
| M18 store format 維持 21 | 57（93 個測試） |
| M19 `authorize-names` 不寫記錄 | 8 |
| M20 `authorize-names` 不要求理由 | 6 |
| M21 `authorize-names` 又替使用者寫 marker | 1（`testApplyNeverWritesTheMarker`） |
| M22 organization 的 `unauthorize` 也寫撤回記錄 | 2 |
| M23 organization 的 `unauthorize` 也要求理由 | 10 |
| M24 venue 的 `unauthorize` 不要求理由 | 12 |
| M25 對已是異寫的名字再標一次不寫「確認」 | 1 |
| M26 CLI `update-organization` 沒把 `--judgement` 轉給服務 | 5 |
| M27 MCP 分派沒把 organization 的 `judgement` 轉給服務 | 5 |
| M28 MCP 分派沒把 organization 的 `rests_on` 轉給服務 | 1 |

M15、M16 是負對照抓到的**弱測試**：第一版的斷言在 mutant 之下仍然綠，因為另一道防線（store 邊界、repair 自己的 validate）替它擲了錯。縱深防禦讓功能正確，卻讓這兩個測試驗不到自己要驗的那一層——所以斷言改成只有編輯面自己的那句訊息才過。



## `tools/list` 位元組

以真 binary（`akashic-mcp` stdio，`tools/list` 回應整行）量：base（7132d033）**53,024** → **53,453**（+429）。預算 54,000（`StdioE2ETests.testToolsListResponseStaysWithinByteBudget`）。增加的只有 venue 的 `judgement`／`rests_on` 兩個參數說明、organization 工具說明與新增的 `judgement`／`rests_on` 參數；第一版 +505（53,529），為了不逼近 ~53,500 的線，把說明各縮了幾個字。

## 誠實邊界

- 機械值不回填（#600）：470 筆 venue 與 4,575 筆 person 的既有 authorized 仍沒有記錄；合併端把它們視為機械值、維持提醒。
- 一句剛好以「指定：」「確認：」「撤回：」開頭的一般判斷（帶 rests-on、掛在 `field: authorized`）會被當成名字分類記錄；live store 這種 reference 為 0 筆，通用寫入面本來就不收 `field: authorized`。
- 合併時被併者的記錄接在倖存者記錄之後，對同一個名字交錯時「最後一筆」不代表時間上的最後，所以拒絕判準用「有任何記錄」。
- venue 的 variant 沒有獨立的撤回面（只有被 `--authorize` 抬出時連帶撤回）。
- person 合併在兩邊記錄位元組不同時被擋（保守；出路是逐字把記錄加進倖存者的 YAML）。
- Spectra 的 CLI 在 git worktree 裡解析專案根目錄到主 checkout，所以 `spectra validate`／`analyze`／`status`／`task done` 對本 change 在 worktree 裡看不到檔案；artifacts 的驗證改在隔離的臨時拷貝裡跑（`spectra validate`／`analyze` 皆 clean），tasks.md 的勾選手動完成。

## 待使用者確認

1. **理由一句套用到整次呼叫的每一筆記錄**（含連帶的撤回）；`authorize-names` 是整批一句、不收證據。
2. **記錄錨定 names、不錨分割**——換來判定史不因撤回成孤兒，代價是 `authorized`／`variant` 上的 statement 前綴文法成了保留語法。
3. **合併拒絕的判準是「有任何記錄」**（不是最後一筆）。
4. **`authorize-names --apply` 不再寫 marker**（行為改變）。
5. **organization 的 `unauthorize` 維持原樣**（未經裁決），與 `authorize` 同一次呼叫時理由只套用到 `authorize`。
6. venue 名字分類腿與 `paginated` 不得同一次呼叫。
