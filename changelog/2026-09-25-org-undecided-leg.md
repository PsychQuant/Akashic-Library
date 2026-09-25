# 2026-09-25 — org-undecided-leg（#643）

resolve-organizations 補上未決（`resolution-undecided`）的寫入面，與 resolve-people／resolve-venues（#619）同契約。

## 新增

- **未決腿**：CLI `resolve-organizations --undecided <id>@<orgKey>=<說明> [--rests-on …]`，MCP `akashic_resolve_organizations` 的 `undecided`／`rests_on`。單獨呼叫，不與 apply／reject 組合。三種 holder 都開：person 的 affiliation、organization 的 parents、work 的團體作者位。
- **id 形狀**（使用者 2026-09-25 裁決）：`<列表的 id>@<orgKey>=<說明>`。列表的 id 逐字取用：`holderKey::literal`，或 work 的 `citekey[i]::literal`。
  - org 的 id 帶 literal，而機構名稱可能含 `=`、`@`。所以解析不以第一個或最後一個 `=` 切：在每個 `@<StoreKey>=` 位置試切，前綴必須恰為這次列表的已知 id，恰一個位置成立才收，零個或多個一律整批拒絕。
  - orgKey 必須是那一列提名的 org。
- **歧義條目可記**：一個 literal 命中 2+ 個 org 時，可以逐個 org 記未決；MCP 的歧義條目自此帶 `id`。
- **揭露**：
  - MCP 候選列帶 `undecidedChecks`（整數）；歧義條目帶 `undecidedChecks`（orgKey 對應次數，只列非零）；頂層帶 `undecidedTotal`。
  - CLI 列表逐列印 `id:`，查過未決的列標「查過未決 N 次」。
- **CLI 篩選式 `--apply` 排除查過未決的候選**：另列排除清單，並指路到 MCP 的逐 id apply。全數排除時零寫入、非零結束。`--reject` 不排除。

## 契約（兩面同）

- 整批拒絕、零寫入：
  - 切不出或切出多個位置；
  - id 重複；
  - 說明空白；
  - org 不存在，或不屬於那一列；
  - digest 形狀不合；
  - store format < 19；
  - `rests_on` 沒有伴隨 `undecided`；
  - 超過上限：一次 200 個 id、20 個 digest、單句 4,096 位元組。
- 逐筆略過並具名：配對已判定，或 citekey 無法唯一定位（#628）。
- 完全相同的記錄已在時回報 `alreadyRecorded`。同一次呼叫的第二個相同記錄報成本次寫入。
- 已知 id 取自一次不帶否決過濾的 resolve：已否決配對的 id 仍然認得，會走「已判定、逐筆略過」。

## 重構

- people／venues／organizations 三個未決腿共用 `checkUndecidedCall`（上限、format、rests-on）、`checkUndecidedStatement`（說明）與 `undecidedPayload`。
- 列表回程把手 `orgRowID` 收成單一定義，由候選列、歧義條目、未決 id 共用。

## 不在範圍

- 沒有任何 org 命中的 literal：它不在列表上，也沒有被判的 org。
- 撤回未決。
- App 的 org 裁決台（目前不存在）。
