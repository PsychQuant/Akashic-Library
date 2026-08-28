## Context

`resolve-people` 把每個 (entry, authorIndex, literal) 的提名結果丟進兩個桶：唯一命中進
`candidates`（可 apply），2+ 命中進 `ambiguities`（不可 apply）。分桶是**型別層**的，
不是 runtime 檢查——`PersonResolver.apply` 的簽章只吃 `ResolutionCandidate`，而
`AmbiguousMatch` 是另一個型別，傳不進去。該設計的既有註解寫明目的是讓「不小心 apply
一個歧義」在型別層寫不出來。

問題在於：**歧義的意思是「提名器分不出來」，不是「人／AI 分不出來」。** 2026-08-20 新增的
`.claude/rules/identity-is-judged-not-matched.md` 裁定 `literal → key` 是 AI 判斷函數、
提名是 recall 而判定是另一回事。以「提名器不確定」當寫入閘，等於拿 recall 裝置當 precision
閘。

實測規模：71 列歧義；literal「C-H Chen」的 15 列逐篇查該作者位在論文上登記的機構後分屬
至少 6 個不同機構。歧義的兩條既有出口（補 variant alias、`add-person`）都是全庫動作，
對共用 literal 會誤傷其餘列。

判定的載體大部分已經存在：`ResolutionLedger.record` 的簽章本來就收自由文字的 statement，
並寫成 judgement，且 restsOn 寫死為空（與 #280 的裁決一致）。缺的只是「呼叫端能指名一個
提名器沒提名的配對」。

## Goals / Non-Goals

**Goals:**

- 讓一個經過判定的 (citekey, authorIndex, personKey) 三元組能寫進 store，並留下 judgement 原文
- 保住「不小心 apply 一個歧義」在型別層寫不出來這個既有保證
- 讓判定過的 literal 在其他 entry 的 occurrence 浮出來給判定者看，且來歷可見
- 兩面（CLI／MCP）同步，或記下有理由的缺席

**Non-Goals:**

- **判定怎麼產生**不在本 change 內。查證流程（DOI → 該作者位登記機構 → 共同作者 → 庫內
  出處）屬 `akashic-verify-person` skill 的工作面。本 change 只提供載體與寫入路徑，
  兩者的介面是三段形 id ＋ judgement 文字。
- **judgement 內容的品質驗收**不做。judgement 是自由文字，本 change 不檢查它是否真的引用
  了證據——那與「語法正確不等於書目正確」同型，屬另案。
- **不改 `initials` 層的提名判準。** 那是 #383 的範圍，而該張的修法已於 2026-08-20 撤回
  （前提被 `identity-is-judged-not-matched` 否定）。
- **不新增第三道錯配防線。** 既有兩道（CLI 裸 apply 對非 exact 層一律拒絕、MCP 要求 per-id
  顯式）已足夠，見 Decisions 第 3 條。
- 不動 `#388`（清單顯示上限旗標）與 `#389`（姓名被切壞的資料修復）。

## Decisions

### 決策 1：以 protocol 抽出四個欄位，不新增 `ResolutionTier` case

`PersonResolver.apply` 實際只用到 citekey／authorIndex／literal／personKey 四個欄位做寫入
與三道守衛（記錄存在、索引有效、該位置仍是那個 literal），`tier` 完全不參與。因此定義

```
protocol AuthorPairing { citekey, authorIndex, literal, personKey }
```

`ResolutionCandidate` 與 `JudgedPairing` 並列 conform，`apply` 改為泛型。

**替代方案：新增 `ResolutionTier.judged`。否決。** `ResolutionTier` 的語意是「怎麼被提名
的」且依信心降冪排序；判定不是被提名出來的，塞進提名列舉是範疇錯誤，正是
`identity-is-judged-not-matched` 所裁決的那類混淆。實務代價也具體：`personRule(for tier:)`、
CLI 的 tier 篩選、三態計數都會被迫處理一個不是 tier 的值。

### 決策 2：型別保證由欄位形狀自動保住，不靠紀律

`AmbiguousMatch` 的欄位是 `personKeys: [String]`（複數），結構上無法 conform 到要求
`personKey: String` 的 protocol。理由與既有的兩桶設計同源：歧義的「是哪一個人」尚未決定，
所以那個單數欄位在型別上不存在。

**不採用**「讓 `AmbiguousMatch` 也 conform、取 `personKeys.first`」——那會把既有保證從
「寫不出來」降級成「要記得別寫」。

### 決策 3：判定的 rule 參與 `confirmedByLiteral`（傳染），錯配交既有兩道閘

判定寫入的 verdict 使用一個新的 rule 字面值，並與既有 confirmed verdict 一樣進
`confirmedByLiteral`。後果是同一個 literal 在其他 entry 的 occurrence 會以
`confirmedElsewhere` tier 浮出，而既有的弱血統揭露機制會把非 `author-name-exact` 的 rule
逐字印進提名理由。

**替代方案：讓判定的 rule 不進 `confirmedByLiteral`（不傳染）。否決。** 該方案為了防止
「一次正確判定把其餘 occurrence 升成可 apply 候選」，但那個風險**已由既有機制擋住**：
CLI 的裸 apply 對任何非 exact 層一律拒絕、必須顯式具名 tier（該閘的既有註解記載它是實測
「一發寫 5 筆 initials verdict、4 筆錯配」之後加的）；MCP 面則要求 per-id 顯式指名，
而顯式指名本身就是判定行為。加第二道閘的代價是那些 occurrence 永遠停在歧義桶，**沒有任何
東西指出「其中一列已經有人判過了」**——傳染反而讓判定者看得到更多。

### 決策 4：證據走被判 person 的 `references`，不進 verdict

`JudgedPairing` **不帶** restsOn。依 `entity-backlink-completeness` 封閉列舉第 13 條所載的
#280 裁決：resolution verdict 刻意不攜 rests-on，證據載體依生命週期分工（已判定 → 被判實體
的 `references`；未判定 → divergence 的 `judgement.restsOn`），且明文「不得因『verdict 也該
綁證據』而給第 13 條長出第二個內容指標」。`ResolutionLedger.record` 現行把 restsOn 寫死為空
也印證同一設計。

### 決策 5：CLI 只給逐 id 顯式，不給篩選式批次

判定旗標收三段形 id 與 judgement 文字，可重複。**不提供**「對所有歧義列套用」之類的批次
形式。理由是 judgement 必填會形成自然摩擦；批次會讓 judgement 退化成罐頭字串，而罐頭
judgement 等於沒有判定。此分界與 `mcp-cli-parity` 已載明的既有不對稱同型
（tier 閘只加在 CLI 的篩選式批次，MCP 的 per-id 顯式刻意不閘）。

## Implementation Contract

### Behavior

操作者或 AI agent 對一個**歧義** occurrence 給出三段形 id 與一句 judgement 之後：

- 該 entry 的該作者位由 `.literal` 變成 `.key(<personKey>)`
- 被判 person 的記錄新增一筆 `resolution-confirmed` verdict，其 judgement 欄含操作者給的
  原文與新的 rule 尾註
- 重跑 `resolve-people` 時，同一個 literal 在其他 entry 的 occurrence 以
  `confirmedElsewhere` tier 出現，其提名理由含該 rule 字面值
- 該 occurrence 不再出現在歧義清單（它已歸戶）

### Interface / data shape

- `AuthorPairing`：協定，成員為 citekey（String）、authorIndex（Int）、literal（String）、
  personKey（String），皆唯讀
- `ResolutionCandidate`：conform，欄位不變
- `JudgedPairing`：conform，額外持有 judgement（String，非空）。**無** tier、**無** restsOn。
  建構器對空白 judgement 回 nil（同 `AmbiguousMatch.init?` 對少於兩個 key 的既有形狀）
- `PersonResolver.apply`：改為接受任一 conforming 型別的序列，寫入邏輯與三道守衛不變
- CLI：`resolve-people` 新增可重複的判定旗標，值為 `<citekey>:<authorIndex>:<personKey>`，
  另有一個帶 judgement 文字的旗標
- MCP：`akashic_resolve_people` 新增對應的 per-id 判定參數
- verdict rule：一個新的小寫連字號字面值，需能通過既有弱血統揭露的字面檢查
  （`^[a-z][a-z-]{0,60}$`），否則會被顯示成「非標準rule」

### Failure modes

- **judgement 為空白** → 建構失敗，命令以 validation error 結束，不寫入任何東西
- **三段形 id 的 citekey 不存在／authorIndex 超出範圍／該位置已不是那個 literal** →
  該筆略過（既有 `apply` 三道守衛的行為），並在報告中具名列出被略過者。不靜默
- **該位置已是 `.key`** → 同上，略過並具名（不覆寫既有歸戶）
- **同一筆判定重複執行** → verdict 由既有 `appendIfAbsent` 保證冪等，entry 寫入因守衛
  「該位置仍是那個 literal」而自然成為 no-op
- **judgement 含控制字元** → 依既有顯示面紀律消毒後輸出；寫入 store 的值保持原樣

### Acceptance criteria

- 新測試檔 `Tests/AkashicKitTests/JudgedPairingTests.swift`：
  - `JudgedPairing` 對空白 judgement 建構失敗
  - `apply` 接受 `JudgedPairing` 並正確改寫該作者位
  - `apply` 對「該位置已不是那個 literal」的判定略過且不改寫
  - **反面斷言**：`AmbiguousMatch` 無法傳入 `apply`（以不編譯為證的替代形式：斷言
    `AmbiguousMatch` 不具備 `personKey` 這個單數成員，同既有 `PersonCLITests` 用型別反射
    斷言 `Person` 無 `works` 成員的手法）
  - 判定寫出的 verdict 其 judgement 含操作者原文與新 rule 字面值
  - 新 rule 字面值通過弱血統揭露的字面檢查（不被顯示成「非標準rule」）
- 真實 store 驗收：對 `chen2006decision` 的第 6 個作者位與 `huang2015symptom` 的第 4 個
  作者位（兩者的 literal 皆為「C.-H. Chen」）判給 `chun-houh-chen`，判定依據為兩篇論文在
  該作者位登記的機構皆為 Institute of Statistical Science, Academia Sinica。判定後：
  - `akashic validate` 全綠
  - 歧義列數比判定前少 2
  - 重跑 `resolve-people` 時，其餘「C-H Chen」occurrence 出現 `confirmedElsewhere` 提名，
    且提名理由含新 rule 字面值
  - **逐筆解釋歧義集合的每一個增減**——不得只看總數（此紀律的既有教訓：補 alias 後歧義
    少了 28 而非預期的 27，多的那筆落在另一個人身上）

### 範圍邊界

**In scope**：`AuthorPairing`／`JudgedPairing` 的定義、`apply` 泛型化、verdict 的新 rule
字面值、CLI 與 MCP 的判定入口、`person-resolution` spec 的新 scenario、`mcp-cli-parity`
的表列更新。

**Out of scope**：判定的產生流程、judgement 品質的機械驗收、`initials` 層的提名判準、
清單顯示上限、姓名資料修復。

## Risks / Trade-offs

- **型別保證在實作時被圖方便繞過**：若有人為了省事把 `AmbiguousMatch` 轉成
  `ResolutionCandidate`（取第一個 key），保證就沒了。**緩解**：上述的反面斷言測試。
- **判定路徑被當成提名濫用**：有了第二條寫入路徑後，可能有人拿它繞過 tier 閘做批次寫入。
  **緩解**：CLI 只給逐 id 顯式；judgement 必填形成摩擦。**殘餘風險存在**——一個決心繞過的
  呼叫者可以逐 id 送幾十筆並給同一句罐頭 judgement。本 change 不機械阻止它。
- **傳染讓錯的判定擴散得更快**：判定錯誤時，其餘 occurrence 會拿到指向錯人的
  `confirmedElsewhere` 提名。**緩解**：那些提名仍是提名（需顯式 tier 具名或 per-id 指名
  才能 apply），且 verdict 可 reject、store 是 git repo 可回溯。這是
  `identity-is-judged-not-matched` 明寫接受的風險（「判定會錯，所以要留 verdict、
  要可回溯」），不是本 change 要消除的。
- **`confirmedElsewhere` 的語意被擴張**：該 tier 原本的意思是「同 literal 已於他處
  confirmed」，現在包含「已於他處**判定**」。兩者都是「有人說過這個字串是這個人」，
  但證據強度不同。**緩解**：rule 字面值不同且會被逐字揭露，讀者分得出來。

## Migration Plan

無資料遷移。本 change 純新增能力：

- 既有 store 檔案格式不變（verdict 的 field／value 文法沿用，只多一個 rule 字面值）
- 既有 `resolve-people` 行為不變（不給判定旗標時逐 byte 相同）
- 既有 verdict 不受影響；新 rule 只出現在本 change 之後寫入的判定上
- 無 store format bump

## Open Questions

- **rule 字面值的確切拼法**：需在實作時定案並寫進 spec。約束是通過
  `^[a-z][a-z-]{0,60}$`，且與既有三個字面值（author-name-exact 一族／org-name-exact／
  venue-name-exact）在語意上可區分。
- **CLI 旗標的確切形狀**：judgement 與 id 是同一個旗標的兩段，還是兩個成對旗標？後者在
  多筆判定時需要配對規則。實作時擇一並在 spec 的 scenario 中固定。
