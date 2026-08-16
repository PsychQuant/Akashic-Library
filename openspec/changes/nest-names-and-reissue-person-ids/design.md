> **ASSUMPTION（2026-08-15，實作時落地）**：本檔所稱「format 8」於實作時已被佔用
> （8 = verdict references #232、9 = attachments 鍵域 #223），實際落地為 **format 10**
> ——下文的「8」一律讀作「10」。正當性核對與細節見 tasks.md 頂部同名註記。

## Context

`Person` 目前有兩處把「識別」與「名字」混在一起：

- `Person.init` 的 `id ?? DeterministicUUID.forPerson(key: key)` 讓 `id` 成為 `v5(key)`。實測 869 筆 person **全部**是 v5 衍生（UUID 第三組首字元為 5），work 則全部是 v4。
- `authorized` 是 `names` 的兄弟欄位，所以 `authorized ⊆ names` 只能靠 `AuthorizedNames.validate` 在執行期擋——PR #245 已把它移到寫入邊界，但**結構本身仍允許違反**。

`key` 由 `PersonBootstrap.suggestedKey` 從名字生成，撞名時用邊跑邊累積的 `taken` 集合決定誰拿 `-2` 後綴——也就是由 **import 順序**決定。而 `id = v5(key)` 讓那個順序產物成為身分。

實測（唯讀，2026-08-12）：

| | |
|---|---|
| person 總數 | 869（866 有 authorized）|
| `authorized ⊄ names` 矛盾 | 0 |
| person UUID 被自己以外的檔案引用 | 0（抽樣 25）|
| entry 引用作者的形狀 | `key`，不是 UUID |
| 帶 `-2` 後綴的 key | 1 |
| 真 store format | 5（binary supported 7）|

## Goals / Non-Goals

**Goals:**

- person 的身分不再是名字的函數，且不隨 import 順序改變
- 既有 869 筆一併重發，store 不留「一半 v5 一半 v4」的混合態
- `authorized` 與 `variant` 各有結構上的位置，矛盾狀態寫不出來
- 遷移可預演、可驗證、失敗時不留半套

**Non-Goals:**

- **entry 改用 UUID 引用作者。** 那可讓 `key` 完全退場，但 YAML 與 git diff 會失去可讀性，而人可讀的 store 是本專案明文的設計前提。`key` 保留為引用把手。
- **Organization 的 names 一併巢狀化。** org 的名字是時間軸（改名有效期），而 `AuthorizedNameTests` 自己寫著「改名與書寫系統是正交兩軸」——把 authorized 塞進時間軸會讓「對外名字」變成時變的。org 側繼續靠寫入邊界的執行期閘守子集關係，**這個不對稱是刻意的**。
- **修正 store format 落後。** 真 store 停在 5，本 change 需要 8；bump 的前置條件（distribution 同步）記在別處，不在本 change 範圍。
- **重新命名任何既有 key。** 本 change 只改「key 之後不再重算」，不動既有 key 的值。
- **處理 `bootstrap-people` 的 key 生成策略。** 撞名後綴的語意問題另案。

## Decisions

### D1：`PersonNames` 是兩個分割，聯集為 computed

```swift
public struct PersonNames: Equatable, ExpressibleByArrayLiteral {
    public var authorized: [String]
    public var variant: [String]
    public var all: [String] { authorized + variant }
}
```

`all` **不儲存**。依據 repo 已寫下的原則（`OrgRef` 的 doc）：「兩個欄位可以互相矛盾，一個 sum type 不會」。存三個欄位就是三個可互相矛盾的真相。

順序語意：`all` 是 `authorized` 在前、`variant` 在後。這讓 `displayName` 的 fallback 有定義（取 `all.first` 即優先拿 authorized），不需要另一條規則。

### D2：`authorized ⊆ names` 這條不變式消失，第二條留下

巢狀化之後 `authorized` 不是 `names` 的子集——它**是** `names` 的一個分割。子集關係變成恆真，`AuthorizedNames.validate` 的第一條檢查成為死碼。

第二條（每書寫系統至多一個 authorized）是**內容**約束，結構管不到，繼續在寫入邊界執行。

**兩者都要處理**：刪掉整個檢查會讓書寫系統那條失去執行；原樣留著會讓一條永遠為真的檢查繼續存在，下一個讀的人會以為它還在防什麼。

### D3：`ExpressibleByArrayLiteral` 不是 compat fallback

`PersonNames` 接受 `["a", "b"]`，意義是「兩個 variant，沒有指定」。實測 182 個測試建構中 167 個是純陣列，這讓它們不必改。

`.claude/rules/no-compat-fallback.md` 的封閉列舉是三類「為了讀**舊資料**而保留的路徑」（缺欄位推導／舊欄位別名／舊佈局回退）。array literal 是**型別轉換**，不讀舊資料，不在那三類內。

反面界線同樣要守：**decoder 不得**接受平坦陣列。舊格式的讀取只能經由遷移，不能經由「decoder 順便相容」——那才會落進第一類。

### D4：`id` 的產生事件只有一個

`Person.init` 的預設值改為 `UUID()`。`DeterministicUUID.forPerson(key:)` 不再是任何預設路徑，只保留給遷移本身使用（它需要算出舊 id 才能找到舊檔）。

遷移完成後該函式**沒有生產呼叫端**。依 no-compat-fallback 的第 3 條（退場後刪掉），本 change 在遷移落地後即移除它——不留著當保險。

### D5：遷移三件事必須原子

對每筆 person：發新 v4 `id` → 寫入新檔名 → 刪除舊檔。三者任一失敗都不得留下「新舊並存」或「檔名與 `id` 不符」的中間態。

`LibraryStore` 有「檔名 UUID 與 `person.id` 不符 → quarantine」的檢查，所以中間態的後果是整批進 quarantine（人檔在 CLI/App 上消失）。

順序上先寫新檔再刪舊檔：崩潰在中間會留下重複記錄（可偵測、可清理），而先刪後寫會留下資料遺失（不可回復）。

### D6：遷移預設 dry-run，且要求 store 工作樹乾淨

沿用既有補資料流程的形狀（`run(store:apply:)`，預設只回報）。

額外的前置條件：`~/.akashic` 是 git repo，那是這次不可逆遷移的回復路徑。實測目前有 398 個未 commit 變更——在那之上重寫 869 個檔名會讓 `git checkout` 救不回來。遷移在 `apply: true` 時**必須先檢查 store 工作樹乾淨**，不乾淨就拒絕並說明理由。

## Implementation Contract

### Behavior

- 新建的 person 取得隨機 v4 `id`；同名的兩個人不再共用 `id`
- 既有 869 筆 person 遷移後各自持有新的 v4 `id`，檔名同步更新，`akashic doctor` 重建 index 後查詢結果不變
- person 的 YAML 中 `names` 為含 `authorized` 與 `variant` 兩個子鍵的 mapping；同一字串不再出現兩次
- entry 的 `authors:` **完全不變**（引用走 `key`）
- 遷移不帶 `--apply` 時只列出將要做的事，不寫任何檔案
- 遷移帶 `--apply` 但 store 工作樹不乾淨時**拒絕執行**，訊息說明要先 commit

### Interface / data shape

新 YAML 形狀：

```yaml
person:
id: <v4 uuid>
key: liang-yu-jen
names:
  authorized:
  - 梁佑任
  - Yu-Jen Liang
  variant:
  - Liang, Yu-Jen
```

新型別：

- `PersonNames`（`AkashicCore`）：`authorized: [String]`、`variant: [String]`、computed `all: [String]`
- `Person.names` 型別由 `[String]` 改為 `PersonNames`
- `Person.authorized` 欄位**移除**（改為 `names.authorized`）

新遷移入口：

- `PersonIdentityMigration.run(store:apply:)` 回傳含「已遷移筆數／被跳過筆數／拒絕原因」的 report
- CLI 子命令 `migrate-person-identity`，預設 dry-run，`--apply` 實際寫入

format gate：

- 新結構需要 store format 8；`writePerson` 在 format < 8 時拒絕，訊息沿用既有 ended/attested gate 的形狀（說明要確認所有 binary 已升級後手動改 `store.yaml`）

### Failure modes

| 情況 | 行為 |
|---|---|
| `--apply` 且 store 工作樹不乾淨 | 拒絕，說明先 commit（回復路徑必須有效） |
| store format < 8 且嘗試寫新結構 | 拒絕，訊息指路 |
| 遷移中途單筆失敗 | 該筆保持原狀，繼續處理其餘，report 列出失敗筆與原因；**不**中止整批 |
| decoder 讀到平坦的舊 `names` 陣列 | **拒絕**（quarantine），不靜默相容——舊格式只能經遷移 |
| 遷移已跑過（記錄已是新結構） | 該筆跳過，計入 report 的「已是新形狀」；重跑安全 |

### Acceptance criteria

- `swift test` 全綠，且新增的遷移測試涵蓋：檔名與 `id` 同步（否則 quarantine）、dry-run 不寫檔、髒工作樹被拒、重跑安全、單筆失敗不中止整批
- `swift build -Xswiftc -warnings-as-errors` 通過
- 對真實 store 的**副本**跑一次 `--apply`，之後 `akashic validate` 與 `akashic doctor` 皆無新增錯誤，且 `akashic search` 的結果數與遷移前相同
- `DeterministicUUID.forPerson(key:)` 在遷移落地後於 `Sources/` 中沒有生產呼叫端
- decoder 對平坦 `names` 陣列的拒絕有測試覆蓋

### Out of scope

Organization 的名字結構、entry 的作者引用形式、既有 key 的值、store format 的實際 bump（那是使用者知情的動作）。

## Risks / Trade-offs

- **不可逆**：id 重發之後無法從新 store 推回舊 id。緩解：dry-run 預設、要求工作樹乾淨（git 即回復路徑）、先寫後刪的順序。
- **format 8 的連鎖**：遷移後的 store 無法被舊 binary 讀取。緩解：format gate 的訊息明說前置條件；實際 bump 由使用者執行。
- **`all` 的順序成為隱性契約**：`displayName` 的 fallback 依賴 authorized 在前。緩解：在 `PersonNames` 的 doc 明寫，並以測試釘住。

**關於 task 數量。** 自審的 scope check 門檻是 15。本 change 有 19 個 pending task，超過了，所以要說明為什麼仍然是一個。

19 個裡有 6 對是 RED/GREEN（1.1/1.2、3.1/3.2、4.1/4.2、5.1/5.2、6.1/6.2），那是同一個工作單元的兩步，不是兩件事。以工作單元計是 7 組、約 10 單元。**不把它們合併寫成一條**——合併只會讓數字好看，卻讓「先寫失敗的測試」這件事從 task 層消失。

更根本的理由是：拆開會**產生第二次遷移**。#227（names 巢狀化）與 #241（id 重發）都要遍歷同一批 869 筆記錄、都要 format bump。分成兩個 change 就是讓使用者的 store 經歷兩次不可逆變更，而那正是 `.claude/rules/no-compat-fallback.md`（要改就一次改全部）要防的事。使用者 2026-08-12 明確裁決合併。

也就是說：這裡的取捨不是「大 change vs 小 change」，是「一次不可逆遷移 vs 兩次」。

## Migration Plan

1. 前置：確認 `~/.akashic` 工作樹乾淨（`git -C ~/.akashic status`），不乾淨先 commit
2. 前置：確認會碰這個 store 的 CLI / MCP / App 都已是新版
3. 跑 dry-run，檢視 report
4. `--apply`，之後 `akashic doctor` 重建 index
5. 驗證：`akashic validate`、`akashic search` 結果數與遷移前一致
6. 把 `store.yaml` 的 `format:` 改為 **10**（原文寫 8——見頂部 ASSUMPTION）

## Open Questions

（無。四項設計裁決已由使用者確認，五條假設已逐條確認。）
