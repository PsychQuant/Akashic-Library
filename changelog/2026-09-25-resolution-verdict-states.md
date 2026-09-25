# 查過未決的記錄、逐篇判定與 apply 並存（#619、#636；change `resolution-verdict-states`）

> 設計、spec 與 tasks 在 `openspec/changes/resolution-verdict-states/`。

## 為什麼

「這個 literal 是不是這個 person／venue」這個配對問題，store 過去只寫得下「是」與「不是」。有兩種真實狀態寫不進去：

1. **查過但判不出來（#619）**：#616／#618 把判不出來的出口改成「讓 literal 留著、來源只寫在報告裡」，於是「查過」與
   「從沒查過」在 store 裡是同一個觀察（`pending`），下一輪要整套重查。
2. **先 apply、後補逐篇判定（#636）**：同一配對已有 `--apply` 寫的 confirmed 時，`--judge` 的判定被 `appendIfAbsent`
   當成重複丟掉——verdict 以配對去重，rule 不參與相等。

使用者 2026-09-25 裁決：#619 加一種「未決」載體；#636 兩筆並存；兩者併進同一份 change。

## 實作前探勘發現、已寫回 spec 的三處更正

- **resolve-venues 兩面都沒有篩選式批次 apply**（CLI 的 `--apply` 收 id 清單），列表也沒有 counts。所以「篩選式 `--apply`
  排除查過未決的候選」只作用於 resolve-people；venue 列表只揭露次數。
- **判定層級不只一個 rule**：`attribute-org` 寫的 `author-organization-judged` 同樣是逐篇判定、同樣有 #636 的形狀。
  `judged` 層級因此是封閉的兩個 rule，其餘一律 `nominated`。
- 三處測試釘死舊值（verdict 欄位封閉對、`byteExactKey` 使用檔清單、`supported == 18`），列為預期變更。

## 做了什麼

- **verdict 欄位封閉三值**：新增 `resolution-undecided`（查過、判不出來；statement 寫查了什麼，可帶 rests-on digest）。
  未決不是判定：不抑制提名、不構成矛盾、不被退役，配對被判定之後保留為查證歷史。
- **相等拆成三把鍵**（`VerdictRecordKey.swift`）：配對鍵（矛盾與狀態）、記錄鍵（去重、合併收攏、D64；帶判定層級，
  未決比整筆位元組）、`verdictEqualityKey`（同 field 同配對、不分層級：D20、D23）。約 40 個使用點逐一指派，指派表在批 B 的 commit。
- **判定層級**：`judged`（`author-judged-per-work`、`author-organization-judged`）與 `nominated`（其餘）。
  `--judge`／`--refute` 對「已由 apply／reject 同向判過」的配對改為寫一筆並存的逐篇判定（回應 `coexistsWith: nominated`），
  作者位不動；在此之前一律具名略過。
- **寫入面**：resolve-people 與 resolve-venues 的 undecided 腿（CLI `--undecided`／`--rests-on`，MCP `undecided`／`rests_on`），
  兩面同契約。resolve-organizations 沒有（#643）。
- **提名與計數**：列表揭露 `undecidedChecks`／「查過未決 N 次」；計數四態、頂層 `undecidedTotal`，查過未決的配對不再算進
  pending；CLI 篩選式 `--apply` 排除它並另列（MCP 逐 id apply 照寫，同 #624）。
- **檢視面**：`akashic person`／`akashic venue` 逐筆印未決記錄查了什麼；CLI person 渲染三值分開（先前未決會被印成 confirmed），並在逐篇判定那一行標〔逐篇判定〕——並存的兩筆 confirmed 否則長得一模一樣（真 binary 端到端時發現）。
- **規則與 skill**：`entity-backlink-completeness` 的 #280 注記收窄成三段載體分工、第 13 條邊改為封閉三值；`mcp-cli-parity`
  三列重新確認；`two-kinds-of-edits` 加一列；`zero-instance-guards` 第 14／28 列補記鍵；四個查證 skill 的「判不出來」出口改寫成記未決。

## 升級前置（store format 19）

format-18 binary 讀到 `resolution-undecided` 會整檔 quarantine，而且它的合併與 rename 會把並存的兩筆判定收成一筆。
**CLI／MCP／App 全部升到 v19 世代之後，才手動把 `store.yaml` 改成 `format: 19`**；marker bump 之前不 push store repo。
沒有資料要遷移（兩種新形狀在 format 18 都寫不出來）。
