> 每組標明它實作哪條 requirement 與哪個設計決策，讓覆蓋關係可機械追溯。

> **ASSUMPTION（2026-08-15，unattended apply）**：本檔與 design.md 所稱「format 8」
> 於實作時已被佔用——8 = verdict references（#232）、9 = attachments 鍵域收窄（#223，
> 2026-08-15 renumber 落地）。specs 只要求 SHALL raise the marker、未寫死數字，故本次
> 實作採 **format 10**。與 StoreVersion.swift 對 9 的既有註記同型（「原設計佔 8；rebase
> 時 8 已被 #232 佔用，順延為 9」）。下文任務描述中的「8」一律讀作「10」。

## 1. 型別：PersonNames

實作 spec `authorized-name` 的 **An entity SHALL designate which of its names are addressed outward**；依 design 的 **D1：`PersonNames` 是兩個分割，聯集為 computed** 與 **D3：`ExpressibleByArrayLiteral` 不是 compat fallback**。

- [x] 1.1 RED：在 Tests/AkashicKitTests/AuthorizedNameTests.swift 加測試釘住 `PersonNames` 的契約——`all` 是 `authorized + variant` 的串接（authorized 在前）、array literal 建出「全部是 variant」、`Equatable` 對兩個分割都敏感。型別此時不存在，不編譯即為 RED。
- [x] 1.2 GREEN（實作 An entity SHALL designate which of its names are addressed outward）：在 Sources/AkashicCore/Models.swift 新增 `PersonNames`，含 `authorized: [String]`、`variant: [String]`、computed `all: [String]`，實作 `ExpressibleByArrayLiteral`（字面量全部進 `variant`）。`all` 不得成為儲存屬性。doc 寫明 design 的 **Risks / Trade-offs** 記下的隱性契約：`displayName` 的 fallback 依賴 authorized 在前。

## 2. Person 的欄位改型

同樣實作 **An entity SHALL designate which of its names are addressed outward**（結構層的「子集不可表達」由此成立）。

- [x] 2.1 把 Sources/AkashicCore/Models.swift 的 `Person.names` 型別由 `[String]` 改為 `PersonNames`，**移除** `Person.authorized` 欄位，`displayName` 改讀 `names.authorized.first ?? key`。編譯錯誤即為待修清單。
- [x] 2.2 修正因 2.1 而編譯失敗的生產程式碼呼叫端（`.names` 48 處 / 18 檔、`.authorized` 22 處 / 8 檔）。判準：要「全部名字」的改讀 `names.all`；要「對外名字」的改讀 `names.authorized`。**逐一判斷，不得整批取代**——兩者語意不同，替換錯了會靜默改變行為。
- [x] 2.3 修正測試中 15 個同時傳 `names:` 與 `authorized:` 的建構點（純陣列的 167 處由 array literal 吸收）。改完確認 `swift build -Xswiftc -warnings-as-errors` 通過。

## 3. 序列化

實作 design **Interface / data shape** 定義的 YAML 形狀，以及 spec `authorized-name` 的 **Removing the positional convention SHALL bump the store format marker** 中「舊形狀不得被靜默接受」那一半。

- [x] 3.1 RED：加測試——巢狀形狀 round-trip 位元組相同；每個名字在序列化結果中恰好出現一次；讀到**平坦**的 `names` 陣列時擲錯且訊息點名欄位（不得靜默視為空的 authorized）。
- [x] 3.2 GREEN：在 Sources/AkashicCore/YAML.swift 改 `PersonYAML` 的 encode／decode 走巢狀形狀，decoder 對平坦陣列 fail-closed。沿用該檔既有的 `requireShape` 紀律。

## 4. 身分：id 改為獨立 v4

實作 spec `record-identity` 的 **A record's stable identifier SHALL have exactly one origin event**；依 design **D4：`id` 的產生事件只有一個**。

- [x] 4.1 RED：加測試——不帶 id 建立的兩個 `Person`（即使 key 相同）取得**不同**的 id；新建 person 的 id 不等於既有推導函式對同一 key 的輸出。
- [x] 4.2 GREEN（實作 A record's stable identifier SHALL have exactly one origin event）：把 Sources/AkashicCore/Models.swift 的 `Person.init` 預設值改為 `id ?? UUID()`，並確認 design 的 Behavior 一節所述「同名的兩個人不再共用 id」成立。

## 5. 寫入邊界的兩道閘

實作 spec `authorized-name` 的 **At most one name per writing system SHALL be authorized**（含「每條寫入路徑都要擋」）與 **Removing the positional convention SHALL bump the store format marker**；依 design **D2：`authorized ⊆ names` 這條不變式消失，第二條留下**。對應 design **Failure modes** 表的前兩列。

- [x] 5.1 RED：加測試——(a) 含巢狀 names 的 person 寫入 format < 8 的 store 被拒且訊息說明升級前置；(b) 同書寫系統兩個 authorized 仍被拒，且**每條寫入路徑**都擋；(c) 確認「authorized 不在 names 內」的舊測試已**移除**而非改成恆真（結構上已不可表達）。
- [x] 5.2 GREEN（實作 At most one name per writing system SHALL be authorized）：在 Sources/AkashicStoreIO/LibraryStore.swift 的 `writePerson` 加 format 8 gate（沿用既有 gate 的訊息形狀），並把 Sources/AkashicCore/AuthorizedName.swift 的 `AuthorizedNames.validate` 縮小到只檢查書寫系統那條——移除子集檢查，doc 說明它已由結構承擔。
- [x] 5.3 實作 Removing the positional convention SHALL bump the store format marker：在 Sources/AkashicStoreIO/StoreVersion.swift 把 `supported` 提升到 8，並在 docs/store-format.md 記錄 v8 的形狀變更與升級前置條件。

## 6. 遷移

實作 spec `record-identity` 的 **Identifier reassignment SHALL keep the record locatable at every point** 與 **An irreversible reassignment SHALL require a working recovery path**；依 design **D5：遷移三件事必須原子** 與 **D6：遷移預設 dry-run，且要求 store 工作樹乾淨**。對應 design **Failure modes** 表的後三列。

- [x] 6.1 RED：新增 Tests/AkashicKitTests/PersonIdentityMigrationTests.swift，涵蓋五條——dry-run 不寫任何檔；檔名與 `id` 遷移後一致（不一致會進 quarantine，這是首要風險）；工作樹不乾淨時寫入被拒；重跑安全（已是新形狀者計入「跳過」）；單筆失敗不中止整批且 report 點名。
- [x] 6.2 GREEN（實作 Identifier reassignment SHALL keep the record locatable at every point）：新增 Sources/AkashicStoreIO/PersonIdentityMigration.swift，提供 `run(store:apply:)` 回傳含「已遷移／已跳過／失敗及原因」的 report。每筆的三件事（發新 v4 id、以新 id 寫新檔、刪舊檔）依此順序，使中斷留下可偵測的重複而非資料遺失。
- [x] 6.3 實作 An irreversible reassignment SHALL require a working recovery path：在寫入路徑加入「store 工作樹必須乾淨」的前置檢查——store 是 git repo，那是本次不可逆遷移的回復路徑。不乾淨時拒絕並說明要先 commit。
- [x] 6.4 [P] 在 Sources/akashic/Commands.swift 新增 `migrate-person-identity` 子命令，預設 dry-run，另有明確旗標才寫入，輸出沿用既有遷移命令的呈現形狀。

## 7. key 的重算退場

實作 spec `record-identity` 的 **A record's human-readable key SHALL NOT be recomputed after assignment**。

- [x] 7.1 RED：加測試——對一個記錄已帶 key 的 store 再跑一次 key 指派，**沒有任何既有 key 改變**；並釘住「撞名後綴是關於指派順序的事實，不是關於該記錄的資訊」（後綴不得被任何判斷邏輯讀取）。
- [x] 7.2 GREEN（實作 A record's human-readable key SHALL NOT be recomputed after assignment）：讓 key 指派路徑在記錄已有 key 時直接沿用，不重新推導。範圍限於「不再重算」，**不改**既有 key 的值、也不改撞名後綴的生成策略（那是 design **Out of scope** 明列的另案）。

## 8. 退場與驗收

對應 design 的 **Acceptance criteria**，並完成 **D4** 要求的退場動作。

- [x] 8.1 移除 Sources/AkashicCore/DeterministicUUID.swift 的 person 推導函式，確認 Sources/ 內無生產呼叫端（遷移後補值用途歸零；依 no-compat-fallback 第 3 條，退場後刪掉不留著當保險）。若遷移本身仍需它定位舊檔，改為遷移內部的 private helper。
- [x] 8.2 對真實 store 的**複本**（複製到暫存目錄，不動原始 store）跑一次寫入，之後執行 validate 與 doctor，確認無新增錯誤、search 結果筆數與遷移前相同。三個數字記進 PR 說明。
- [ ] 8.3 全套 `swift test` 與 `swift build -Xswiftc -warnings-as-errors` 通過；逐條 mutation 驗證新增測試（還原對應實作時必須轉紅），不是只看綠燈。
