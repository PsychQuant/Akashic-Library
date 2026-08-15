## Summary

把 person 的**身分**（`id`）與**名字結構**（`names`）在同一次遷移裡改對：`id` 改為獨立 v4 並重發既有 869 筆、`key` 改為配發後永不重算的穩定 handle、`names` 巢狀化為 `authorized` / `variant` 兩個分割。

## Motivation

### 身分是名字的函數（#241）

`Person.init` 的 `id ?? DeterministicUUID.forPerson(key: key)` 讓身分成為 `v5(key)`——而 `key` 由名字生成、撞名時用 **import 順序**決定誰拿 `-2` 後綴。於是同一個人在不同 import 順序下會得到不同 UUID，而**兩個不同的人只要 key 相同就會得到相同 UUID**。

後者是不可逆的資料毀損：專案目標是完全取代 Zotero（見 `.claude/rules/replace-endnote-and-zotero.md`），那意味著將來會匯入別人的 library，而兩個 library 裡各自叫 `chen-wei` 的不同人會在合併時安靜熔成一筆。

實測 869 筆 person **全部**是 v5 衍生；work 則全部是 v4（隨機）。同一個 store 裡兩種身分模型並存，而弱的那個用在更會撞名的實體上。

v5 當初是對的：舊格式的 `people/<key>.yaml` 沒有 `id` 欄位，兩台未協調的機器必須推出相同的值。但實測**磁碟上 869 筆全部已有 `id`**，補值用途歸零——現在唯一還走得到那條 fallback 的是「新建記錄」，也就是它會傷害的那個情況。

### 結構允許矛盾（#227）

`authorized` 是 `names` 的兄弟欄位，所以 `authorized ⊆ names` 這條 spec 立的不變式**只能靠執行期驗證**——結構本身允許違反它。同一個字串在 YAML 裡出現兩次。

而 RDA 的術語本身就是階層的：*authorized* access point 與 *variant* access point 都是 access point 的一種。現行結構**沒有 variant 的位置**，所以文件只能拿 `names` 頂替（那個誤植是同一個根因的另一個症狀）。

### 為什麼兩者要一起做

兩者都要遍歷同一批 869 筆記錄、都需要 store format bump。分兩次做會讓使用者的 store 經歷**兩次**不可逆遷移，而 `.claude/rules/no-compat-fallback.md`（要改就一次改全部）正是為此而立。

## Proposed Solution

### 型別

新增 `PersonNames`，含 `authorized: [String]` 與 `variant: [String]` 兩個分割；聯集 `all` 是 computed 而非儲存欄位（避免第三個可與前兩者矛盾的真相）。`PersonNames` 實作 `ExpressibleByArrayLiteral`，字面量意義為「全部是 variant，沒有指定」。

`Person.id` 的預設值改為 `UUID()`；`DeterministicUUID.forPerson(key:)` 從 `Person.init` 的預設位置移除。

### 遷移

新增一支遷移，對每筆 person 同時做三件事：

1. 發一個新的 v4 `id`
2. 把檔名改為新 `id`（`entities/<uuid>.yaml`）
3. 把平坦的 `names` + `authorized` 折成巢狀 `PersonNames`

**預設 dry-run**，沿用既有補資料流程的形狀。

### 不變式的歸屬變化

`authorized ⊆ names` 由結構保證後，寫入邊界的檢查縮小到只管「每書寫系統至多一個」——那是**內容**約束，結構管不到。

### store format

新結構需要 format 8（**實作時順延為 10**——8/9 已被 #232／#223 佔用，見 tasks.md／design.md 的 ASSUMPTION）。寫入低於該 format 的 store 時拒絕，沿用既有的 format gate 機制與訊息形狀。

## Non-Goals

（本 change 有 design.md，Non-Goals 寫在那裡。）

## Alternatives Considered

- **entry 改用 UUID 引用作者**：可讓 key 完全退場，但 YAML 與 git diff 失去可讀性，而人可讀的 store 是本專案明文的設計前提。已否決。
- **只改新記錄、既有 869 筆凍結**：改動最小，但既有記錄的跨 library 熔合風險保留，且 store 長期處於「一半 v5 一半 v4」的混合態——違反 no-compat-fallback。已否決。
- **Organization 一併巢狀化**：org 的名字是時間軸（改名有效期），而指定與改名是正交兩軸；把 authorized 塞進時間軸會讓「對外名字」變成時變的。已否決，理由寫進 design.md。

## Impact

- Affected specs:
  - `record-identity`（**新增**）：識別子如何配發——只有一個產生事件，不由屬性推導
  - `authorized-name`（修改）：子集關係改由結構保證，書寫系統那條留在執行期
- Affected code:
  - New:
    - Sources/AkashicStoreIO/PersonIdentityMigration.swift
    - Tests/AkashicKitTests/PersonIdentityMigrationTests.swift
  - Modified:
    - Sources/AkashicCore/Models.swift
    - Sources/AkashicCore/AuthorizedName.swift
    - Sources/AkashicCore/DeterministicUUID.swift
    - Sources/AkashicCore/YAML.swift
    - Sources/AkashicStoreIO/LibraryStore.swift
    - Sources/AkashicStoreIO/StoreVersion.swift
    - Sources/akashic/Commands.swift
    - Tests/AkashicKitTests/AuthorizedNameTests.swift
    - docs/store-format.md
  - Removed: （無）
