## Why

名字的等值判定目前用**精確字串相等**，於是只差前後空白的近重複（`"謝叔蓉"` vs
`"謝叔蓉 "`）可以分居 `authorized` 與 `variant` 兩個分割、穿透互斥守衛；merge 去重的
`filter { !keeper.names.all.contains($0) }` 有同一假設。

**既有的正規化不可復用，這是本 issue 的真正難點。** `NameNormalization.matchingKey`
的檔頭是鐵律：

> **用於配對，永不用於判定。** 同 key 只代表「值得提名給人看」，不代表同一人。

而互斥檢查與 merge 去重**正是判定**（斷言同一並丟棄）。兩者對假陽性的容忍度相反：
`matchingKey` 容許假陽性（後面有人審），判定必須零假陽性（**沒有下一關**）。

所以精確相等**不是疏漏，是在無更嚴判準可用時唯一安全的選擇**。缺的是判準本身。

## What Changes

新增 `NameIdentity.canonical(_:)`——**判定用**的等值判準，只收「兩個字串只差這個就
必然是同一個名字」的變換：

| 變換 | 收 | 理由 |
|---|---|---|
| NFC（canonical equivalence）| ✅ | Swift `String ==` 已做；同一字元的不同編碼形式 |
| 前後空白 trim | ✅ | 名字不含前後空白 |
| 內部空白**串**收斂（多個→一個）| ✅ | `"李 明"` 與 `"李  明"` 是同一個名字 |
| 大小寫摺疊 | ❌ | 拉丁上機率高但**非必然**——判定不能建立在機率上 |
| NFKC／連字號家族統一 | ❌ | 會把不同名字塌成一個（那是配對的工作）|

三個站點改用它：分割互斥檢查、merge 去重、以及新增的近重複檢查。

**近重複必須被指出。** `matchingKey` 相同但 `canonical` 不同的兩個名字（例如
`"Chang, Y-H."` 與 `"Chang, Y‐H."`），既不能自動收斂（那是判定越界）也不能靜默留著
——新增一條 **warning 級** validation：指出它們未決，交人裁決。

## Non-Goals

- **不改 `matchingKey`**。它的語意（配對、容許假陽性）是對的，本變更不動它一個字元。
- **不自動合併近重複**。指出即止——自動收斂會違反「絕不自動合併」鐵律。
- **不做大小寫摺疊**。它在 CJK 是 no-op、在拉丁上是機率判斷；要收必須是一次顯式裁決，
  不是順手帶進來。
- **不改 `PersonResolver` 的候選提名**。那條路走 `matchingKey`，本來就該容許假陽性。

## Capabilities

### New Capabilities

(none)

### Modified Capabilities

- `authorized-name`: 新增「名字的等值判定 SHALL 有單一判準且零假陽性」與「近重複
  SHALL 被指出為未決」兩條 requirement

## Impact

- Affected specs: `authorized-name`
- Affected code:
  - New: `Sources/AkashicCore/NameIdentity.swift`
  - New: `Tests/AkashicKitTests/NameIdentityTests.swift`
  - Modified: `Sources/AkashicCore/AuthorizedName.swift`
  - Modified: `Sources/AkashicStoreIO/DivergenceResolve.swift`
