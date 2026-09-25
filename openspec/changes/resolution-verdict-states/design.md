## Context

verdict 是住在被判定記錄（person／organization／venue）上的 `ProvenanceReference`：

- `field` 屬封閉對 `resolution-confirmed`／`resolution-rejected`，單一來源是 `ProvenanceReference.resolutionVerdictFields`。
- `value` 的文法是 `<kind>:<key> :: <literal>`。
- statement 帶尾註 `[rule: <name>]`，由 `ResolutionLedger.record` 唯一產生。

「兩筆 verdict 算同一筆」目前只有一個定義，即 `ProvenanceReference.verdictEqualityKey(field:value:)`（#470）：field ＋ holder ＋ 正規化 literal，**不含 rule**。它被約 40 個使用點共用，分布在 8 個檔：寫入去重、合併收攏（D47／D51）、D64 重複掃描、#486 矛盾掃描、rename 的 D55／D60／D62、venue 的 D20／D23／D34。

這個單一定義擋住兩件事。

- **#636**：逐篇判定（rule `author-judged-per-work`）與既有的 apply verdict 同鍵，`appendIfAbsent` 會把判定丟掉。#627 R5 起改成具名略過，但理由仍無處可寫。
- **#619**：「查過、判不出來」沒有欄位可寫。#280 裁決 verdict 不攜 rests-on，而 divergence 的 restsOn 只服務 record↔record 問題。

使用者 2026-09-25 的裁決：#619 加一種未決載體；#636 讓兩筆並存；兩者併進同一個 change。

live store 基線（2026-09-25）：
- 同一配對同時有兩種層級 confirmed 的筆數：0。#627 R5 之後 judge 對這種位置一律略過，寫不出來。
- 未決記錄：0。欄位尚不存在。

所以本 change 不需要資料遷移。它只需要一次 store format bump，擋住舊 binary。

## Goals / Non-Goals

**Goals:**

- store 能寫下「查過、判不出來」的配對，附查過的內容（rests-on digest）與說明。下一輪的提名與批次 apply 看得到它。
- 同一配對可以同時持有 apply（提名層）與逐篇判定兩筆記錄，兩筆都不被去重、合併、rename 吃掉。
- 「兩筆 verdict 是不是同一筆」拆成三把具名的鍵，約 40 個使用點各自顯式指派，不再共用一個語意模糊的鍵。
- 計數分得出「查過未決」與「沒查」。

**Non-Goals:**

- organization 族的未決寫入面（resolve-organizations）。store 層接受 org holder 上的未決記錄（文法一致），但本 change 不加寫入面。另開 issue 追蹤，理由記在 mcp-cli-parity。
- 把既有 apply verdict 「升級」或「取代」成逐篇判定：裁決是並存，不是取代。
- 未決記錄的撤回面，以及「判定之後又改回未決」。未決在配對被判定後只是歷史，不改變狀態。
- person 的 confirmed 撤回（demote）。person 族目前沒有這個面，本 change 不新增。
- 寫入時驗 rests-on digest 是否存在於本機 `sources/`。沿用 `update-venue --paginated` 的先例：只驗形狀；本機缺檔由既有的 dangling-source 掃描（#453）報。
- 比率、機率、自動降權。延續 resolution-judgement-ledger 的立場，只給計數。

## Decisions

### verdict 欄位擴成封閉三值，新增 resolution-undecided

`resolutionVerdictFields` 從兩值擴成三值：`resolution-confirmed`、`resolution-rejected`、`resolution-undecided`。`ResolutionLedger.VerdictKind` 加 `.undecided`。

**Supersedes**: resolution-judgement-ledger / verdict 欄位封閉對（「僅此二值，不得類推第三個」）

**理由：**

- 未決的定位與另外兩個判定相同，都是「holder ＋ literal ＋ 被判實體」。放進同一個封閉集合，就能沿用同一套文法解析、同一個 store 閘、死 verdict 掃描、rename 遷移與 D60 閘，不必新開第二套。
- 改用 `firstOrderRulingFields` 之外的新欄位名，看起來是「不動封閉對」，實際上要在上述每一處另寫一條分支。那正是 #232 當初以單一來源避免的分岔。

**被否決的替代方案：**

- 把未決寫成 divergence：divergence 問的是 record↔record，出口是不可逆的合併，而且沒有移除面（#586）。#616／#618 正是因此把它撤掉。
- 不持久化（#619 的選項 2）：使用者否決。

### 未決記錄允許帶 rests-on，confirmed／rejected 仍不帶

未決記錄的內容是：kind judgement；statement 必填，寫查了什麼、為何判不出來；rests-on 可為空，也可列 sha256 digest。confirmed／rejected 維持 #280 的「不攜 rests-on」。

**Supersedes**: resolution-judgement-ledger / verdict 刻意不攜 rests-on（#280 注記的「未判定 → divergence restsOn」一半）

**理由：**

- 判定已下的配對，證據在被判實體的一般 references 裡（第 11 條邊）。
- 查過未決的配對沒有被判實體可以承認這份證據。證據唯一合理的落點就是未決記錄本身。
- digest 仍是第 11 條邊的內容指標（住在 `Person.references`／`Venue.references`），不新增邊。

**空 rests-on 放行的理由**：有些查證只在線上看過、沒有存檔；「查過」這件事本身就有資訊量。空 rests-on 經 `firstOrderRulingFields` 放行，未決因加入 `resolutionVerdictFields` 而自動進入該集合。

### 判定層級是封閉二值，由 rule 導出

confirmed／rejected 各自分兩個層級：

| 層級 | 條件 |
| --- | --- |
| `judged` | rule 恰為 `author-judged-per-work` |
| `nominated` | 其餘全部：四個 tier 的 rule、`venue-name-exact`、`org-name-exact`、缺尾註的 legacy、無法辨識的 rule |

判準寫成封閉列舉，不寫成「看起來像人判的」這種性質。

**理由：**

- 使用者裁的是「apply 與逐篇判定並存」，不是「每個 rule 各一筆」。
- 若讓整個 rule 字串參與相等，同一配對經不同 tier 重複 apply 就會累積多筆 confirmed。計數的「原始 refs」語意會被灌水，D64 也永遠抓不到這種重複。
- 二值只開放使用者要的那一格。

### 三把具名的鍵取代單一相等定義

新增 `Sources/AkashicCore/VerdictRecordKey.swift`，集中定義三把鍵：

- **`verdictPairingKey(value:)`**：holderKind ＋ holder ＋ `matchingKey(literal)`，不含 field、不含層級。用在矛盾判斷（confirmed 與 rejected 配對鍵相同）、狀態推導、退役相反判定。
- **`verdictRecordKey(_ ref:)`**：寫入去重、合併收攏、D64 重複掃描的單一定義。
  - confirmed／rejected：field ＋ 配對鍵 ＋ 層級。
  - undecided：`byteExactKey`（整筆位元組相等）。同一配對的多次查證是設計上要保留的，只有完全相同的重送才算重複。
  - 非 verdict 欄位：沿用 `verdictEqualityKey` 的回退鍵。
- **`verdictEqualityKey(field:value:)`**：保留，語意不變（field ＋ 配對鍵）。只在呼叫端確實要「同 field、同配對、不分層級」時使用，例如 D20 的退役與 D23 的 confirmed literal 唯一性。

**使用點指派（實作時以 grep 重新盤點，每一處寫進 PR 的指派表）：**

| 使用點（以函式命名） | 指派 |
| --- | --- |
| `ResolutionLedger.appendIfAbsent` | 記錄鍵 |
| `ResolutionLedger.supersede`（D20） | 相反 field 的 `verdictEqualityKey`，兩個層級一起退役；不動 undecided |
| `StoreHealth.contradictoryVerdicts`（#486） | 配對鍵，confirmed × rejected，不分層級；undecided 不參與 |
| `StoreHealth` 的 D64 重複判定記錄掃描 | 記錄鍵 |
| `StoreHealth` 的死 verdict 掃描、venue verdict 預算 | 三值全部納入（不涉相等） |
| `LibraryStore.migratedVerdicts`、`verdictsStillPointingAt`（rename 的 D55／D60／D62） | D60 看 holder（三值全部）；D62 的折疊仍只折整筆位元組相等 |
| `DivergenceResolve.dedupKey`、`mergedPersonKeeper`、`migrateWorkHolderVerdicts`、`rewrittenVerdicts`（收攏） | 記錄鍵 |
| `DivergenceResolve.verdictPairingKey`、`verdictViolations`、`newVerdictViolations`、`assertNoNewViolations`（D31／D34） | 矛盾用配對鍵、不分層級；雙 literal（venue）不變 |
| `DivergenceResolve.fieldsLostByMerging` | `byteExactKey`，不變 |
| `Venue.evaluateGroup`（D36） | 只看 confirmed，不變 |
| `PersonResolver`／`VenueResolver` 的否決抑制 | 配對鍵（等同既有 `matchingKey` 比對） |
| `AkashicService.judgeAuthorships` | 記錄鍵 |
| `UpdatePerson.appendReferences` | 維持 D73 的 `byteExactKey`；閘接受 undecided |
| `Provenance.validateReferenceAttachment` | 接受三值 |

**被否決的替代方案**：直接讓 `verdictEqualityKey` 帶層級。那會一刀切換約 40 個使用點，其中 D20、D23、#486 恰好需要「不分層級」。會安靜錯在最需要對的那幾處。

### 狀態推導：decided 大於 undecided 大於 pending

一個配對（holder ＋ literal ＋ 被判實體）的狀態由記錄現算，不存：

| 狀態 | 條件 |
| --- | --- |
| decided | 有任一層級的 confirmed 或 rejected |
| undecided | 否則，有 ≥1 筆 undecided |
| pending | 以上皆無 |

後續規則：

- 未決記錄在配對被判定後**保留**，作為查證歷史，不退役，也不構成矛盾。
- 對已 decided 的配對寫未決：該筆具名略過，理由是「已判定，未決不改變狀態」。
- confirmed 與 rejected 並存，無論層級，仍是 #486 的矛盾。

**理由**：刪掉未決記錄等於程式編輯刪掉判定編輯的產物（D60 的立場）。保留它的成本只是 YAML 裡幾行；保留的好處是判定者日後看得到「判定之前查過什麼」。

### 四態計數

`ResolutionLedger.counts` 從 `(confirmed, rejected, pending)` 改成 `(confirmed, rejected, undecided, pending)`：

- confirmed／rejected 仍數原始 refs，依 rule 分桶；並存的兩筆各計入各自的 rule 桶。
- undecided 與 pending 以**候選配對**為單位，依候選自己的 rule 分桶：
  - undecided：該配對狀態為 undecided。
  - pending：該配對狀態為 pending。

MCP 列表的 `counts` 多一個 `undecided` 欄，頂層多一個 `undecidedTotal`；CLI 的計數行同步。

### 提名與批次 apply 對未決的處理

- 提名照常產生。未決不是否決，不抑制提名。
- MCP 的候選列與歧義條目帶 `undecidedChecks`（該配對的未決記錄數，> 0 才出現）。
- CLI 候選列標「查過未決 N 次」。
- CLI 篩選式 `--apply` 排除帶未決記錄的候選：逐筆列出，並指向 `--judge`／`--refute`。全數被排除時零寫入、非零結束。tier 閘看排除後的套用集。
- MCP 逐 id apply 照寫。這與 #624 的淘汰而得、tier 閘同型：MCP 是顯式指名，CLI 篩選是未指名的掃蕩。
- resolve-venues 同一套規則。

### 並存的寫入面：judge／refute 在已同向判過的配對上寫入

`judgeAuthorships` 對「作者位已歸給同一人」的配對：

| 既有 confirmed 的層級 | judge 的行為 |
| --- | --- |
| 僅有 `nominated` | 寫一筆 `judged` confirmed，與既有那筆並存；作者位不動；回在 `judged`，並帶 `coexistsWith: nominated` |
| 已有同一句理由的 `judged` | no-op，回在 `alreadyJudged`（沿用） |
| 已有理由不同的 `judged` | 該筆具名略過（記錄鍵相同，理由無處另存；要改理由不在本 change） |

literal 仍由既有 verdict 逐字取回，且只在恰好取得一個時使用。

refute 對「已有 nominated rejected（`--reject`）」的配對同理：寫一筆 judged rejected 並存。

refute 對「作者位歸給同一人」的配對仍略過，因為那是矛盾，行為不變。

### 未決的寫入面

兩面同契約：

- **CLI**：`resolve-people --undecided <citekey:authorIndex:personKey=說明>`（可重複）、`resolve-venues --undecided <citekey:venueIndex:venueKey=說明>`（可重複），可附 `--rests-on <sha256:…>`（可重複，套用到本次呼叫的每一筆未決）。
- **MCP**：`akashic_resolve_people`／`akashic_resolve_venues` 的 `undecided`（字串陣列）與 `rests_on`（字串陣列）。

**失敗語意**：

- 整批拒絕、零寫入：
  - 語法錯（缺 `=`、非三段、重複 id、說明空白）
  - 被判實體不存在
  - digest 形狀不合
  - store format < 19
  - `rests_on` 沒有伴隨 `undecided`
- 該筆具名略過（store 狀態不符）：
  - work 不存在、索引越界
  - citekey 無法唯一定位（#627／#628）
  - 該位置不是 literal
  - 配對已 decided
- no-op：完全相同的記錄已在，回在 `alreadyRecorded`。

**單獨呼叫**：不與 apply／reject／judge／refute／split／un-split／drop／attribute-org 組合，組合整批拒絕（#635 的樣式）。

**rule 尾註**：`[rule: checked-undecided]`，由 `ResolutionLedger` 的唯一產生器補。

**id 形狀**：`--rests-on` 對整次呼叫生效，而不是每一筆各帶，理由是 CLI 的字串 id 沒有地方放結構化的第二欄（`split_author` 記過同一個限制）。要對不同配對附不同證據，就分次呼叫。MCP 刻意用同一個形狀，不收物件陣列，兩面才是同一份契約。

### store format 18 → 19

`StoreVersion.supported` 升到 19。

**理由有兩個，任一都足以要求 bump：**

1. 舊 binary 的 `validateReferenceAttachment` 不認得 `resolution-undecided`，讀到會 quarantine 整個 person／venue 檔。
2. 舊 binary 的合併與 rename 以舊鍵收攏，會把並存的 judged／nominated 收成一筆，丟掉其中一筆理由。

**寫入面的閘：**

- 未決寫入、以及「寫入後會形成並存」的 judge／refute，都要求 store format ≥ 19。
- 對「本來就不會並存」的 judge／refute（位置仍是 literal），沿用既有的 ≥ 8 閘。

**部署**：沒有資料要改寫。部署順序依既有的三 binary 鏈：release → 三個 binary 更新 → 手動把 store marker 升到 19。

## Implementation Contract

**Behavior（使用者看得到的）：**

- `akashic resolve-people --undecided 'chen2020a:1:chen-ch=查了論文機構欄只寫 Taipei；共同作者兩邊都有' --rests-on sha256:…` 在 `chen-ch` 的記錄寫一筆 `resolution-undecided`。之後：
  - 同一配對在列表上標「查過未決 1 次」；
  - 篩選式 `--apply` 排除它並另列；
  - MCP 列表該列帶 `undecidedChecks: 1`、`counts.undecided`。
- 對已 `--apply` 歸給 `chen-ch` 的作者位跑 `--judge 'chen2020a:1:chen-ch=理由'`：寫入一筆 judged confirmed，與既有 apply verdict 並存。回應不再是「略過，升級見 #636」。
- 合併、rename 之後兩筆並存的記錄都還在。`akashic validate` 不把它們報成重複判定記錄。

**Interface / data shape：**

- 新欄位值 `resolution-undecided`。value 文法同其他 verdict；statement 以 `[rule: checked-undecided]` 結尾；rests-on 為 0 到多個 `sha256:<64 hex>`。
- `ResolutionLedger.VerdictKind` 三值。新增 `ResolutionLedger.pairingState(...)`，回 `decided`／`undecided`／`pending`。
- `ResolutionLedger.counts` 回傳 tuple 加 `undecided`。
- MCP resolve-people／resolve-venues 回應新增 `undecided`（已記錄）、`alreadyRecorded`、`skipped`；列表列新增 `undecidedChecks`；頂層新增 `undecidedTotal`。judge 回應的 `judged` 列可帶 `coexistsWith`。
- CLI 旗標 `--undecided`、`--rests-on`（兩個命令）。

**Failure modes：**

- 見「未決的寫入面」的失敗語意。
- 所有拒絕與略過都具名：id、原因、下一步。
- 沒有任何路徑會刪除未決記錄。

**Acceptance criteria：**

- `VerdictRecordKeyTests`：三把鍵對下列組合各有正反例：同配對異層級、同配對同層級異拼法、未決同配對異 statement、未決完全相同。
- `UndecidedVerdictTests`：寫入、累積、decided 後略過、四態計數、篩選式 apply 排除、MCP 逐 id 照寫、rests-on 形狀拒絕、format < 19 拒絕、單獨呼叫拒絕組合。
- `JudgedCoexistenceTests`：apply 後 judge 寫入並存；合併（person 與 work 兩種）與 rename 之後兩筆仍在；D64 不報；#486 對「nominated confirmed ＋ judged rejected」仍報矛盾。
- 負控：把記錄鍵的層級拿掉，`JudgedCoexistenceTests` 必紅；把排除拿掉，篩選式 apply 測試必紅。
- 全套 `swift test` 0 失敗，守衛 rc=0。
- 真 binary 端到端（假 HOME、scratch store、format 19）走完上面 Behavior 的兩個情境。

**Scope boundaries：**

- In：person 與 venue 兩族的未決寫入面；person 族的並存（venue 族沒有 judged 層級）；三把鍵與約 40 個使用點的指派；四態計數；format bump；規則文件（entity-backlink-completeness 的 #280 注記、mcp-cli-parity、two-kinds-of-edits、zero-instance-guards 第 14／28 列的鍵描述）；akashic-disambiguate skill 把「判不出來」的出口改成寫未決。
- Out：organization 族的寫入面、未決撤回、person demote、App 的未決寫入 UI（App 只需顯示計數）、rests-on 存在性驗證。

## Risks / Trade-offs

- **[約 40 個使用點指派錯一處會安靜錯]** → Mitigation：
  - 指派表逐處寫進 PR。
  - 每一類（去重、收攏、矛盾、D64）各有一支測試，同時覆蓋並存與未決兩種形狀。
  - `VerdictKind` 加 case 之後，編譯器會逼出所有 exhaustive switch；`where v.kind == .confirmed` 這類過濾不會被逼出，要靠 grep 列出來逐一判讀。
- **[未決記錄無上限累積]**：一個配對被反覆查證會不斷長。→ Mitigation：
  - venue 的 verdict 節點預算（第 16 列）把未決一起計入。
  - 列表只給次數，不列內容；內容由 `akashic person`／`akashic venue` 檢視面逐筆印出。
- **[並存讓 `confirmedPairings` 不再是一對一]** → 回傳改成 judged 優先。提名理由揭露 judged 血統，因為 judged 是更強的出身。代價是提名理由不再同時提到「也曾 apply 過」；那筆記錄仍在，檢視面看得到。
- **[format bump 打斷三個 binary]** → 沿用既有部署鏈與記憶中的六步順序。本 change 沒有資料遷移，回退只要不升 marker 即可。
- **[`--rests-on` 套用整次呼叫]** → 可能把某筆證據誤掛到同一次呼叫的另一筆未決上。→ Mitigation：
  - 回應逐筆印出掛上的 digest。
  - help 寫明「不同證據分次呼叫」。
