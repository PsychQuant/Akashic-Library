## Context

三個站點目前用精確 `String ==`：分割互斥（`AuthorizedName.validateDisjointPartitions`）、
merge 去重（`DivergenceResolve.swift` 的 `filter { !keeper.names.all.contains($0) }`）、
以及尚不存在的近重複檢查。

既有的 `NameNormalization.matchingKey`（NFKC + 連字號統一 + 空白收斂 + 大小寫摺疊）
**不可復用於判定**——它的檔頭是鐵律。

## Goals

- 判定用的等值判準有單一定義，三個站點共用
- 近重複要嘛被判準收斂，要嘛被指出為未決——不得靜默留成兩個

## Non-Goals

**In scope**：新增判準型別、三個站點接上、兩條 spec requirement。

**Out of scope**（各有理由）：

- 改 `matchingKey` —— 它的語意是對的
- 自動合併近重複 —— 違反「絕不自動合併」鐵律
- 大小寫摺疊 —— 見 D2
- `PersonResolver` 的候選提名 —— 那條路本來就該容許假陽性

## Decisions

### D1：判準的收錄條件是「必然」不是「通常」

判定會**丟棄資料**（去重時丟掉一個名字）且**沒有下一關**。所以收錄條件是：

> 兩個字串只差這個變換，就**必然**是同一個名字。

不是「幾乎總是」、不是「在我們的資料裡沒見過反例」。這條件把三個變換收進來、把三個
擋在外面：

| 收 | 擋 |
|---|---|
| NFC（Swift `==` 已做）| NFKC |
| 前後空白 trim | 大小寫摺疊 |
| 內部空白**串**收斂 | 連字號家族統一 |

空白三者的共同理由：**空白不是名字的一部分**。沒有兩個人的名字只差在前後或重複的
空白——那是輸入時的雜訊，不是命名的內容。

### D2：大小寫摺疊刻意不收——這是本設計最容易被「順手加上」的一項

`"Macdonald"` 與 `"MacDonald"` 幾乎總是同一個名字。但「幾乎總是」不滿足 D1。

而它的代價不對稱：收了之後，判定會在**拉丁書寫系統**上多丟掉一批名字，卻在 CJK 上
完全沒有效果（大小寫摺疊對 CJK 是 no-op）。也就是說它用「拉丁側的假陽性風險」換
「拉丁側的便利」，對本 store 的主要書寫系統毫無幫助。

要收必須是一次**顯式裁決**（新開 issue、附實測），不是順手帶進來。

### D3：近重複的處置是 warning 而非 error

`matchingKey` 相同但 `canonical` 不同 → **報出來，不擋寫入**。

理由：那兩個名字**可能真的不同**（`matchingKey` 容許假陽性正是為此）。擋寫入等於
把「值得問一下」升級成「你錯了」，而規則明寫這是未決不是違規。

與既有的「同書寫系統兩個 authorized 是**未決的問題**，不是指定」同型。

### D4：判準放 `AkashicCore` 的新檔，不放進 `NameNormalization`

兩者語意相反（容許假陽性 vs 零假陽性），放同一個檔會讓下一個人拿錯——那正是本
issue 的成因。分開放，各自的檔頭鐵律互相指認。

## Risks

- **有人把 `NameIdentity.canonical` 拿去做配對** —— 它比 `matchingKey` 嚴格，會漏掉
  該提名的候選。緩解：檔頭鐵律寫明方向，並在 `NameNormalization` 的檔頭加交叉指認。
- **近重複 warning 在既有 store 大量觸發** —— 實作後對真 store 實測計數，若過多則
  該數字本身就是 `#303` campaign 的一項發現，不是本變更的缺陷。

## Implementation Contract

### `NameIdentity.canonical(_ s: String) -> String`

- **行為**：NFC → trim 前後空白 → 內部空白串收斂為單一 U+0020
- **不做**：NFKC、大小寫摺疊、連字號映射、任何字元刪除
- **性質**：冪等（`canonical(canonical(x)) == canonical(x)`）

### `NameIdentity.same(_ a: String, _ b: String) -> Bool`

- `canonical(a) == canonical(b)`

### `AuthorizedName.validateDisjointPartitions`

- 互斥判定改用 `NameIdentity.same`
- **驗收**：`"謝叔蓉"` 與 `"謝叔蓉 "` 分居兩分割時被報為重疊

### merge 去重（`DivergenceResolve`）

- `incoming` 的過濾改用 `NameIdentity.same`
- **驗收**：keeper 有 `"Li  Ming"`、doomed 有 `"Li Ming"` 時不重複加入

### `AuthorizedName.validateNearDuplicates(names:ownerKey:) -> [ValidationIssue]`

- 對 `names.all` 兩兩比較：`matchingKey` 相同 **且** `NameIdentity.same` 為 false → 一條
  `severity: .warning` 的 issue，訊息列出兩個名字
- **驗收**：`"Chang, Y-H."` 與 `"Chang, Y‐H."`（U+2010）觸發；`"鄭澈"` 與 `"Che Cheng"`
  不觸發
