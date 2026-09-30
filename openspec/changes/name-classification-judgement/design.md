## Context

名字分類在三種實體上各有寫入面：person 的 `authorize-names`（#81，CLI-only 的批次提名）、venue 的 `update-venue --add-variant`（#471）／`--authorize`（#554）／`--unauthorize`（#559）與 MCP `akashic_update_venue` 的同名參數、organization 的 `update-organization --authorize`／`--unauthorize`（#557）與 MCP `akashic_update_organization`。venue 與 organization 的替換與撤回邏輯住在同一份 `AuthorizedDesignation`。這些面都不留判定記錄；同一個 `updateVenue` 裡的 `paginated`（#406）卻要 judgement＋rests-on、寫一筆 `ProvenanceReference`。

使用者 2026-10-01 裁決（#564）：五個面一律留 judgement 記錄，每次指定、撤回、標異寫都寫一筆，理由必填、證據 digest 可空；對既有值說「確認」也留一筆；合併端因此分得出人確認過的與機械值，前者升成拒絕條件；代價是升 store format。#600 同日裁決既有機械值不跑全量 campaign、按需判定。

2026-10-01 唯讀量測 live store：person 4,575 筆（有 authorized 4,575）、venue 485 筆（有 authorized 470、有 variant 41）、organization 13 筆；`field: authorized` 或 `field: variant` 的 reference **0 筆**；store marker 是 18。

## Goals / Non-Goals

**Goals:**

- 五個名字分類面的每一次指定、確認、撤回、標異寫都在 store 裡留一筆可讀的判定記錄，理由必填、證據可空。
- 記錄在名字離開分割之後仍然合法（判定史不因撤回而成孤兒）。
- 舊 binary 讀不懂這種記錄時，由 store format 的 refuse-if-newer 出聲，而不是整檔 quarantine。
- venue 合併分得出人判定過的 authorized：降級它要拒絕，機械值維持提醒。

**Non-Goals:**

- 不回填：既有 470 筆 venue 與 4,575 筆 person 的機械 authorized 不補記錄（#600 按需判定）。
- 不新增 person 的 variant 面，也不讓 person 或 organization 收 `field: variant` 的記錄（person 的 variant 分割是「其他名字」，沒有判定面寫它；organization 沒有 variant 分割）。
- 不新增撤回 variant 的面（venue 的 variant 仍沒有移除面，只有被 `--authorize` 抬出時連帶撤回）。
- 不改 person 合併：它本來就拒絕 authorized 的降級，也拒絕被併者帶有倖存者沒有的任何非 verdict reference。
- 不在 `StoreHealth` 新增「最後一筆記錄與現在分類不一致」的掃描。
- 不動 organization 合併（尚未實作，#555）。

## Decisions

### 判定記錄沿用 ProvenanceReference 的 judgement，statement 以封閉三動作前綴區分

一筆記錄是 `ProvenanceReference(field: "authorized" | "variant", value: 名字, kind: .judgement(statement:, restsOn:))`，statement 是 `指定：理由`、`確認：理由`、`撤回：理由` 三者之一（封閉列舉，不得類推第四個）。解析只有一份：新檔 `NameClassificationRecord`（AkashicCore）的 `parse(statement)`，回傳動作與理由，前綴不符或理由去空白後為空回 nil。形狀取自作者位記錄（`拆為 ⟦a⟧ ⟦b⟧：理由`／`移除：理由`，#450／#457）：同一個 field 住多種記錄，由 statement 前綴分辨，各有唯一解析器。

沒選：另開一個欄位名（例如 `name-classification`）。裁決原文就寫 `field: authorized` 或 `variant`，且 authorized 的既有 reference 本來就是「關於那個名字的對外形身分」的記錄；另開欄位會讓同一件事有兩個家。

### 記錄錨定在 names，不在分割

既有的 `field: authorized` reference 要求 value 在 authorized 清單內；撤回記錄與被換下的名字的記錄恰恰描述已離開 authorized 的名字，照舊規則會成孤兒、整筆記錄寫不進去。所以名字分類記錄的附著條件是「value 是這筆記錄的名字之一」（person：`names.all`；venue／organization：`names` 時間軸的任一段；相等用 `String ==`，與既有 `field: names` 同一把）。**分類的現況仍是分割本身**（authorized／variant 清單），記錄是 provenance，不是狀態；兩者不一致時以清單為準。

`field: authorized` 上的其他 reference（擷取型、或 statement 不符名字分類文法的判斷型）維持舊語意：value 要在 authorized 內，且判斷型要有 rests-on。`field: variant` 只收名字分類記錄（先前這個欄位名在任何形狀上都不存在）。

### 名字分類記錄進 firstOrderRulingFields，理由必填、證據可空

裁決說證據 digest 可空，而平面 init 對空 rests-on 只放行 `firstOrderRulingFields`。`authorized` 與 `variant` 加進這個集合；因為這個集合是以 field 放行，附著驗證再補一道：這兩個 field 上空 rests-on 的判斷型必須符合名字分類文法，否則拒收。它們不進 `resolutionVerdictFields`（那個集合被當 verdict 文法解析，#450 記過同一個理由）。

### 一次呼叫的理由套用到該次每一筆記錄；連帶的撤回由程式組句

venue 與 organization 的一次呼叫可以同時指定、撤回好幾個名字；理由是一句，套用到那次呼叫寫下的每一筆記錄，rests-on 也同。連帶的分類改變各寫一筆撤回，理由由程式在使用者的理由前加一段說明：

| 情形 | 記錄 |
|---|---|
| `authorize X`，X 原本不在 authorized | authorized `指定：理由` |
| `authorize X`，X 已在 authorized（含只差位元組而被換成 canonical 的） | authorized `確認：理由` |
| 同書寫系統的舊指定 Y 被 X 換下 | authorized（value Y）`撤回：同書寫系統改指定「X」——理由` |
| X 原本在 variant、被抬進 authorized | variant（value X）`撤回：改指定為 authorized——理由` |
| `unauthorize X` | authorized `撤回：理由` |
| `add_variant X`，X 原本不在 variant | variant `指定：理由` |
| `add_variant X`，X 已在 variant | variant `確認：理由` |
| `authorize-names --apply` 採用或提名 X | authorized `指定：理由` |

沒選：被換下、被抬出的名字不寫記錄。那樣做，人指定過 Y 的那筆「指定」會一直是 Y 的最後一筆記錄，而 Y 已不是對外形；讀記錄的人與合併端都會讀錯。裁決原文也把撤回列為要留記錄的判定。

### venue 沿用 judgement／rests_on，與 paginated 不同一次呼叫

venue 面沿用既有的 `judgement`（CLI `--judgement`）與 `rests_on`（`--rests-on`）；只要這次呼叫帶了至少一個非空白的 `add_variant`／`authorize`／`unauthorize` 名字，`judgement` 就必填（去空白後非空、至多 4,096 位元組），`rests_on` 可省略、至多 20 個 digest。`paginated`／`clear_paginated` 與名字分類腿不得同一次呼叫：兩個判定各要自己的理由，共用一句會讓其中一筆的理由說的是另一件事。檢查排在名字 vetting 與兩句矛盾的檢查之後，讀 store 之前（#654 的形狀）；既有的名字不合法、兩句矛盾的拒絕訊息不變。

organization 新增 `judgement`／`rests_on`（CLI `--judgement`／`--rests-on`），規則同上。

沒選：另開 `name_judgement` 參數。多一個參數多一份 `tools/list` 位元組（預算 54,000，基線 53,024），也讓 `judgement` 在同一個工具裡有兩種理由來源。

### authorize-names 的理由是整批一句

`authorize-names` 沒有逐人或逐名的形式，所以 `--apply` 必附 `--judgement`，那一句套用到這次寫下的每一筆記錄；乾跑不需要理由。不收 `--rests-on`：一個批次共用同一組 digest，等於宣稱每個人的名字都依據同一份文件，那幾乎一定是假的。`authorize-names` 只對 authorized 為空的人寫入，所以它不會寫「確認」。

### 位元組完全相同的記錄不重寫

append-only：與既有 reference 位元組完全相同（`byteExactKey`）的一筆不再寫，同 `update-person` 的 references。回報 `judgementsRecorded`（這次實際寫下的筆數）。第二次以同一句理由確認同一個名字不會長出第二筆。

### store format 22 與寫入閘

名字分類記錄對 format-21 binary 是非 additive：person／organization 上空 rests-on 的記錄在平面 init 拒收、撤回記錄的 value 不在 authorized、venue 的 `field: variant` 走附著驗證的封閉 default，三者都讓整筆記錄 quarantine。所以 `StoreVersion.supported` 升到 22，新增 `nameClassificationRecordFormat = 22`；person、organization、venue 三個寫入閘在記錄帶有名字分類記錄而 format < 22 時具名拒絕（訊息說出需要的 format 與升級前置）。解讀不受 format 影響（decode 不知道 format）。無資料遷移：這種記錄在 format 21 寫不出來，既有記錄零 diff。

### authorize-names 不再替使用者升 marker

`AuthorizedNameMigration.run(apply: true)` 先前在結尾無條件把 marker 寫成 `StoreVersion.supported`（#81 的 format 5 語意）。現在 person 的寫入閘已保證任何寫入都發生在 format ≥ 10 的 store（巢狀 names），名字分類記錄又要求 ≥ 22，那一步對正確性已無作用；留著它，在沒有人要寫的 store 上（live store 4,575/4,575 已有 authorized）`--apply` 會把 marker 從 18 安靜地升到 22，跳過 19–21 的升級前置、鎖掉舊 binary。部署說明把升 marker 定為使用者的動作，所以移除那一步。

### venue 合併：帶記錄的 authorized 降級改為拒絕

`authorizedDemotedByMerging` 回報的每一個降級，若被併者對那個名字持有任何 `field: authorized` 的名字分類記錄，合併拒絕（preview 與實跑共用前置），新錯誤 `wouldDemoteJudgedAuthorized` 逐名列出名字與那筆最後的 statement，並指路：在被併者上 `update-venue --unauthorize`（留理由）、或在倖存者上 `update-venue --authorize` 那個名字（留理由），再合併。沒有記錄的機械值維持提醒。判準是「有任何記錄」而不是「最後一筆是指定或確認」：人對那個名字的對外形身分說過話，合併就不替人改；最後一筆是撤回卻仍在 authorized 只可能是手改，那時保守地拒絕。

### venue 合併：名字分類記錄在分類一致時隨合併搬移

被併者的名字分類記錄，在它的名字於合併後的倖存者上的分類（在不在 authorized、在不在 variant）與它在被併者上的分類相同時，逐位元組搬到倖存者（與 `field: names`／`issn` 的搬移同一條路 `venueReferenceCarry`，dry-run 與實跑同一份計算，搬了什麼列在 `referencesCarried`）。分類不同時照「會遺失」拒絕，那一行說出是哪個名字、兩邊的分類，出路是先讓兩邊的分類一致（都要理由）。倖存者的分類以合併後為準：authorized 就是倖存者的 authorized（合併不增加 authorized），variant 是倖存者的 variant 加上被標 variant 搬進來的名字。

沒選：一律搬。被併者說「X 是異寫」而倖存者把 X 放在未標，搬過去的記錄會說一句倖存者的分類不承認的話。

### person 合併維持現狀

person 合併本來就拒絕被併者有、倖存者沒有的 authorized（#81），也拒絕被併者帶有倖存者沒有的任何非 verdict reference（子集判準）。名字分類記錄因此在被併者與倖存者位元組不同時擋住合併——保守、有記錄的邊界；同一批 `authorize-names` 對同名寫下的記錄位元組相同，不擋。

### 名字分類記錄只由名字分類面寫入與保留

- `update-person` 的 `references`：判斷型、field 是 `authorized` 且 statement 符合名字分類文法的一筆拒收（只經 `authorize-names`）。
- venue 的 `--remove-reference`：`field: variant` 在解析時拒收；`field: authorized` 定位只看名字分類記錄以外的 reference，只命中名字分類記錄時具名拒絕。判定史不在移除面，要改分類用 `--authorize`／`--unauthorize`。
- `authorize`／`unauthorize` 換下或撤回名字時，只有名字分類記錄以外的 `field: authorized` reference 擋（名字分類記錄錨定 names，不會成孤兒）。
- `repair-venue-names` 改寫一個名字的拼法時，指著那個拼法的名字分類記錄算「pinned」（它們錨定 names，改寫會讓它們對不上），交給人判斷。
- `--edit-name-segment` 移除一個名字的最後一段時，若有名字分類記錄指著它，具名拒絕（判定史不刪，沒有工具面，只能手改 YAML）。

## Implementation Contract

**行為**：

- `akashic update-venue <key> --authorize X --judgement R`：寫入 X 的分類變更，另在 venue 的 references 追加名字分類記錄（上表），回報 `judgementsRecorded`。少了 `--judgement`（且有非空白的 `--authorize`／`--unauthorize`／`--add-variant`）→ 用法錯誤、零寫入。帶 `--paginated` 或 `--clear-paginated` 同時帶名字分類腿 → 用法錯誤。MCP `akashic_update_venue` 同契約（`judgement`、`rests_on`）。
- `akashic update-organization <key> --authorize X --judgement R [--rests-on D…]`：同上；MCP `akashic_update_organization` 新增 `judgement`、`rests_on`。
- `akashic authorize-names --apply --judgement R`：每個寫入的 person 每個被採用或提名的名字各一筆 `指定：R`；`--apply` 沒有 `--judgement` → 用法錯誤、早於開 store；乾跑不需要理由；不再寫 store marker。
- store marker < 22 時上述寫入具名拒絕，訊息含「store format ≥ 22」與升級前置。
- `resolve-divergence`（venue）：被併者帶記錄的 authorized 會被降級 → `wouldDemoteJudgedAuthorized` 拒絕，preview 同；其餘名字分類記錄依分類一致與否搬移或以 `wouldLoseFields` 拒絕。

**資料形狀**：

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

**失敗模式**：缺理由、理由超過 4,096 位元組、rests_on 超過 20 個或不是合法 digest、paginated 與名字分類同一次呼叫、format < 22、合併降級帶記錄的 authorized、手寫的名字分類記錄文法不合（空 rests-on 的判斷型 statement 不符、`field: variant` 不是名字分類記錄、value 不是這筆記錄的名字）——全部具名拒絕；寫入面整批零寫入，載入面整檔 quarantine（手寫的壞記錄）。

**驗收**：`NameClassificationRecordTests`（解析、附著、寫入閘）、`NameClassificationJudgementTests`（五個面的記錄形狀、缺理由拒絕、確認、撤回留史、位元組相同不重寫、ownership 四處）、`NameClassificationMergeTests`（拒絕 vs 提醒、分類一致搬移、不一致拒絕）、CLI 與 stdio 各至少一個 venue 面與一個 organization 面、`ToolPayloadKeyGuardTests` 與 `ToolPayloadLegTests` 的新情境、`tools/list` 以真 binary 量測不超過 53,500。全套 `swift test` 與 `run-guards.sh` 綠。

**範圍**：五個面、三個寫入閘、venue 合併、ownership 四處、authorize-names 的 marker、規則與文件。不含：回填、person variant 面、variant 撤回面、StoreHealth 掃描、organization 合併、App（App 沒有名字分類面）。

## Risks / Trade-offs

- [live store 的 marker 是 18，名字分類面在使用者升到 22 之前全部拒絕] → 拒絕訊息說出需要的 format 與升級前置；部署順序寫在 changelog 與 README 的 format 表。
- [判斷型 `field: authorized` reference 以 statement 前綴分成兩種語意；一句剛好以「指定：」開頭的一般判斷會被當成名字分類記錄] → live store 這種 reference 0 筆；通用寫入面本來就不收 `field: authorized`；記在 docs/store-format.md 的誠實邊界。
- [合併時被併者的記錄接在倖存者記錄之後，兩邊對同一個名字的記錄交錯時，「最後一筆」不代表時間上的最後] → 只在分類一致時搬，交錯的記錄說的是同一個結論；判準用「有任何記錄」而不是「最後一筆」。
- [person 合併在兩邊記錄位元組不同時被擋] → 保守；出路是逐字把記錄加進倖存者的 YAML（既有訊息已說）。
- [`tools/list` 預算只剩約 976 bytes] → 描述只加必要的字（`judgement` 必填、`judgementsRecorded`），以真 binary 量測。

## Migration Plan

1. 發布含 format 22 的 CLI、`akashic-mcp`、App；三個 binary 都升級。
2. 使用者手動把 store 的 `store.yaml` 改成 `format: 22`（live store 目前 18，19–21 的升級前置一併適用）。
3. 之後名字分類面才寫得進去。回退：在 marker 升級之前沒有任何名字分類記錄寫得進去；升級之後回退 binary 會被 refuse-if-newer 擋下，要先刪掉名字分類記錄再降 marker。

## Open Questions

（無：理由參數沿用、authorize-names 的整批理由、合併判準、marker 移除都在上面裁決並記錄；需要使用者回頭看的列在 changelog 的「待使用者確認」。）
