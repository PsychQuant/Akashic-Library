# verdict holder 遷移網格：四個具名缺口補齊（#463）

`VerdictPairingValue` 的遷移是一張 4 退役操作 × 3 記錄形狀的網格。完整矩陣（Codex R1 要求公開，不再只說「補齊」）：

| 退役操作 | person 記錄 | organization 記錄 | venue 記錄 |
|---|---|---|---|
| `renameEntry`（work rename） | ✅ #232 | ✅ **本次** | ✅ #460 |
| `resolveWorkDivergence`（work merge） | ✅ #271 | ✅ **本次** | ✅ #460 |
| `renamePerson`（person rename） | ✅ #395 | ✅ #395 | **N/A** |
| `resolvePersonDivergence`（person merge） | ✅ **本次** | ✅ **本次** | **N/A** |

**N/A 的理由**：venue 記錄只持有 `work:` holder——`resolve-venues` 的 verdict 落在被判定的 venue 上，配對的另一端
恆為 work（`VerdictHolderKind` 的 doc：`.person`／`.org` 是 org-resolution 的 holder，住在 organization 記錄上）。
所以 person-key 退役對 venue 記錄沒有可遷移的東西。這是結構事實不是省略；若日後 venue 開始持有 `person:` holder，
`VerdictHolderGridTests` 的三族釘子（#464）與本表要一起改。

- **helper 泛化**：`migrateHolderVerdicts(_:merged:survivor:holderKind:)`；`migrateWorkHolderVerdicts` 成為它的
  `.work` 特例（#461 的測試不動；語意逐字相同：觸及集合收攏、survivor 自保、首見留存）。
- **rename×org**：`renameEntry` 加 organization 迴圈（鏡射 venue 迴圈）。**寫入前置條件與 `writeOrganization` 是同一個
  函式**——`assertOrganizationWritable(_:format:)` 抽出全部非 I/O 前置條件（識別碼 ≥13、ended ≥6、attested ≥7、
  verdict ≥8、validate），兩邊不會漂移；只鏡射 key／validate／encode 會在 format ≤ 7 的 store 撕裂（Codex R1）。
- **work-merge×org**：`resolveWorkDivergence` 加 organization 迴圈（複用 helper）。
- **person-merge×org／×person**：`person:<被併鍵>` holder 的改寫分兩段——**keeper 自己持有的（含 #271 剛從 doomed 搬來的）
  在 commit 之前對合併後的 keeper 做**；其餘 organization 與 people 在 commit 之後掃 pre-commit 快照，**排除 merged
  （寫回等於復活）與 survivor（快照是舊的，寫回會蓋掉合併別名）**。Codex R1 抓到第一版把 survivor 也掃了。
- **為什麼漏了三次**：organization 是 #443／OrgResolver 之後才開始持有 `work:` verdict；每次補迴圈時它都「還不存在」
  或「不在列舉裡」。live store 實測 9 條 org 持有的 `work:` verdict（7 個 distinct citekey）——任一 holder 被 rename
  或 merge 就重演 #460（#464 verify 的 DA 在副本上 rename 兩次得 4 條死 verdict）。
- **測試**：`VerdictHolderGridTests`——四格各一支、survivor 自持與 doomed 搬來的 `person:` holder 各一支、format 降級時
  rename 在改動 entry 前擲錯、helper 的 kind 篩選、多 org 指向同一 citekey 的 cardinality 回歸。
- **偵測器**：#464 的死 verdict 掃描是這張網格的守衛——四格補齊後它對這些路徑應恆為 0。
