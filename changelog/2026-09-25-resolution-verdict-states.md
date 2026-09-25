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

## R1 verify（6 席，37 項：1 HIGH、10 MEDIUM）之後的修正

- **judge 對仍是 literal 的作者位**（HIGH，Codex＋regression）：層級檢查只在作者位不會變時決定 no-op／略過；位置仍是 literal
  時照常歸戶、verdict 只去重。先前已有逐篇判定時回報 `alreadyJudged` 而作者位從未歸戶。「同一句理由」改比 statement 與
  rests-on，不比 literal 的位元組
- **work 攣生合併後 judge 卡死**（DA，真 binary 重現）：取回原 literal 時以正規化鍵去重——只差位元組的兩個拼法是同一個配對
- **format 18 上的既有寫入面**：apply／reject／App accept／attribute-org／org apply／reject 在 format < 19 時不造出兩層級並存
  （`appendIfAbsent(allowCoexistence:)`），不再「entry 已寫入、person 才被擋下」；person 合併的 dry-run 跑與實跑同一道 keeper 閘
- **計數以配對為單位、狀態推導用正規化配對**：同一筆 work 兩個作者位同一 literal 時，一筆未決不再計兩次；讀取端與寫入端同一把正規化
- **未決腿**：寫入前逐筆驗證可寫（中途失敗不再留下沒回報的部分寫入）、重建 index 失敗時列出已落地的記錄、同一次呼叫的第二個
  相同 id 回報為寫入而非「已在」；一次至多 200 筆、rests-on 至多 20 個、說明至多 4,096 位元組（超過整批拒絕）
- **MCP 參數**：`undecided`／`rests_on` 給了就必須是非空字串陣列，否則整個呼叫拒絕（先前非陣列會被靜默當成沒給）
- **檢視面有界**：未決記錄的 rests-on 只列前 5 個＋總數；判定後保留的未決記錄標「查證歷史」而不是 stale
- **App 裁決台**（第三面）標出查過未決的次數；venue 的節點預算把 rests-on 的 digest 算進去
- **提名理由的血統**：並存時 exact 優先、其次 judged（初稿 judged 優先，讓 exact 的配對多出一個弱血統註記）
- 散文：format bump 的理由只有「合併」會收攏（rename 不會）、三態 → 四態、多處過時的「無處另存／verdictEqualityKey」說法
- CLI 的計數行標籤從「三態計數」改成「四態計數」並插入「查過未決」一欄——以欄位位置解析這一行的外部腳本要跟著改

## R2 verify（6 席，31 項：1 HIGH、15 MEDIUM）之後的修正

- **判定理由沒寫進去要說出來**（HIGH，Codex；另有四席同形）：judge 與 attribute-org 在作者位照常歸戶、而理由存不進去時
  （store format < 19 已有提名層判定；或該配對已有理由不同的同層級逐篇判定，含同一次呼叫的另一個作者位），回應那一列帶
  `verdictNotRecorded` 說明原因、CLI 印「⚠ 這次的理由沒有寫入」；`personsRewritten` 只計真的有寫入的 person
- **未決腿的「本次寫入」以被判實體區分**（Codex）：先前只比 reference 的位元組，另一個實體的既有記錄會被報成本次寫入
- **檢視面的「查證歷史」看實際的判定**：同一個 holder 對這個正規化配對持有 confirmed／rejected 才標 history——work 消失或
  literal 被移除只是觀測不到（仍是 stale），reject 之後 literal 還在的也是 history
- **上限寫進規格**：200 個 id／20 個 digest／4,096 位元組進了 spec、design、兩面的描述，`zero-instance-guards` 第 30 列記量測出處
  （live store 最長理由 687 位元組、rests-on 最多 3 個；id 數是推估）；上限只約束一次呼叫、不約束累積——person 側的預警缺口記 #645
- `pending` 的計數也以正規化配對去重（未決之外的附帶變化；live store 前後相同，R2 verify DA 實測）
- venue 預算 warning 印出 rests-on 換算後的等效筆數；venue CLI 檢視面揭露 rests-on 的總數；寫入失敗的訊息不再一律說「寫到一半」
- 散文：「約 40 個使用點、8 個檔」改成可重跑的量法（排除註解後 16 行、9 個檔）；`confirmedPairings` 的同級取捨說法與實作一致

**記錄但不動**：檢視面仍逐筆列出全部 verdict（既有行為，未決只加有界的說明與 digest；累積另見 #645）；寫入前的閘不跑 encode
canary（與其他寫入面同一道 `assertPersonWritable`）；format 18 上 work 合併遇到兩層級並存會被擋（設計「合併在 format 18 會被擋」的既定裁決）。

## 升級前置（store format 19）

format-18 binary 讀到 `resolution-undecided` 會整檔 quarantine，而且它的合併會把並存的兩筆判定收成一筆（rename 只折位元組相同的記錄，不受影響）。
**CLI／MCP／App 全部升到 v19 世代之後，才手動把 `store.yaml` 改成 `format: 19`**；marker bump 之前不 push store repo。
沒有資料要遷移（兩種新形狀在 format 18 都寫不出來）。
