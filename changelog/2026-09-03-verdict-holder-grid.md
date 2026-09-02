# verdict holder 遷移網格：四個具名缺口補齊，矩陣 12／12（#463）

`VerdictPairingValue` 的遷移是一張 4 退役操作 × 3 記錄形狀的網格。完整矩陣（Codex R1 要求公開，不再只說「補齊」）：

| 退役操作 | person 記錄 | organization 記錄 | venue 記錄 |
|---|---|---|---|
| `renameEntry`（work rename） | ✅ #232 | ✅ **本次** | ✅ #460 |
| `resolveWorkDivergence`（work merge） | ✅ #271 | ✅ **本次** | ✅ #460 |
| `renamePerson`（person rename） | ✅ #395 | ✅ #395 | ✅ **本次（verify）** |
| `resolvePersonDivergence`（person merge） | ✅ **本次** | ✅ **本次** | ✅ **本次（verify）** |

**為什麼最後兩格不是 N/A**（第一版標 N/A，verify security 席指出自相矛盾）：`person:`／`org:` holder 的唯一 producer
是 org-resolution，它只寫 organization 記錄——這對 **person 記錄**也一字不改地成立，而 person 那一格寫了迴圈與測試。
同型兩格不能處置相反；而「結構上不會有」正是本表下方自陳失誤三次的措辭。寫入閘（`validateReferenceAttachment`）
對三族都只驗可解析、不驗 holderKind，所以 venue 記錄**寫得進** `person:` holder（測試就是這樣造出來的）。
兩格各一個迴圈、各一支測試，成本一格十幾行。

**`.org` holder 不在矩陣裡**：今天沒有 organization-key 的退役操作（無 `renameOrganization`、無 org merge），所以沒有
第五個 row；出現時本表要加一列，而 `migrateHolderVerdicts`／`migratedVerdicts` 都已收 `holderKind`。

- **helper 泛化（merge 側）**：`migrateHolderVerdicts(_:merged:survivor:holderKind:)`；`migrateWorkHolderVerdicts` 成為它的
  `.work` 特例（#461 的測試不動；語意逐字相同：觸及集合收攏、survivor 自保、首見留存）。
- **helper 泛化（rename 側）**：`migratedVerdicts(_:from:to:holderKind:)`——#395 的 `.person` 原形加 `holderKind`，
  `renameEntry` 的 person／venue／organization 三段**逐字相同的迴圈**（各 750 字元，verify 實測）改成呼叫它。同一
  commit 剛用「不漂移」證立另一個抽出，這裡沒有理由留三份複本。**已知缺口同步擴大**：rename 側的收攏是靜默的
  （報告沒有 `verdictsCollapsed`，#461 只修了 merge 側），現在 organization 與 venue 也在這條路上。
- **rename×org**：`renameEntry` 加 organization 迴圈（鏡射 venue 迴圈）。**寫入前置條件與 `writeOrganization` 是同一個
  函式**——`assertOrganizationWritable(_:format:)` 抽出全部非 I/O 前置條件（識別碼 ≥13、ended ≥6、attested ≥7、
  verdict ≥8、validate），兩邊不會漂移；只鏡射 key／validate／encode 會在 format ≤ 7 的 store 撕裂（Codex R1）。
  format 是 lazy 讀的——只在某個閘真的需要時才讀 store.yaml，壞掉的 store.yaml 不會擋沒有 gated feature 的
  organization（Codex R2：第一版抽 helper 時改成無條件讀）。
- **work-merge×org**：`resolveWorkDivergence` 加 organization 迴圈（複用 helper）。
- **person-merge×org／×person**：`person:<被併鍵>` holder 的改寫分兩段——**keeper 自己持有的（含 #271 剛從 doomed 搬來的）
  在 commit 之前對合併後的 keeper 做**；其餘 organization 與 people 在 commit 之後掃 pre-commit 快照，**排除 merged
  （寫回等於復活）與 survivor（快照是舊的，寫回會蓋掉合併別名）**。Codex R1 抓到第一版把 survivor 也掃了。
- **為什麼漏了三次**：organization 是 #443／OrgResolver 之後才開始持有 `work:` verdict；每次補迴圈時它都「還不存在」
  或「不在列舉裡」。live store 實測（2026-09-03，掃 `~/.akashic/entities` 中 `organization:` 檔的 `resolution-*`
  value）9 條 org 持有的 `work:` verdict、7 個 distinct citekey——任一 holder 被 rename 或 merge 就重演 #460
  （#464 verify 的 DA 2026-09-03 在副本上 rename 兩次得 4 條死 verdict；那個掃描器在 #464 的 branch，本 branch 不可重跑）。
- **測試**：`VerdictHolderGridTests`——四格各一支、venue 的兩格各一支、survivor 自持與 doomed 搬來的 `person:` holder
  各一支、format 降級時 rename 在改動 entry 前擲錯、壞 store.yaml 只擋需要閘的 org、helper 的 kind 篩選、多 org 指向
  同一 citekey 的 cardinality 回歸。
- **三張的分工**：#463 **遷移**（補格）／#464 **偵測**（`deadVerdictIssues`：任一格漏了會以 warning 出聲）／#488
  **後置條件**（`renameEntry` 一次 rename 不得新增死 verdict——替還沒想到的格提供大聲失敗）。#488 的 Actual 段寫的
  「rename 一個 organizations 持有 verdict 的 citekey 會安靜留下死 verdict」在本張 merge 後不再為真，但它要的斷言
  仍值得做。
- **commit 早退不再寫檔**（verify logic L2）：`resolveWorkDivergence`／`resolvePersonDivergence` 在 `commitResolution`
  回報任何失敗時直接回傳，不跑 holder 遷移迴圈——先前一個回報「未動任何檔案」的失敗仍會改寫 person／venue
  （#271／#460 的既有形狀，本輪一併關）。
- **dry-run preview 對 verdict 面仍沉默**（#467，issue note 建議同輪落地）——本輪**不做**：preview 的回報形狀要與
  `ResolveReport` 三個 verdict 欄位一起裁，不是加三個迴圈的事；#467 的 `### Blocking` 記本張。

## verify fix round 2（Codex R3 ＋ DA）

- **commit 失敗語意：揭露與遷移都看 `survivorUpdated`**（logic L2 → Codex R3 N1 → DA-2／DA-4；謂詞改了兩次）。
  四個案例：A：commit 前早退（被併檔不可刪）→ 不揭露、不遷移；B keeper 寫後 entry 寫入失敗 → 揭露 keeper、遷移照做
  （冪等，重跑補完）；C 被併檔**部分**刪除失敗 → `merged` 不填，而已刪 key 的 holder 不遷移就是**重跑救不回**的死 verdict
  （`validatePersonPreconditions` 對缺檔候選擲 `candidateMissing`）；D 全刪成、只剩主歧異記錄刪除失敗 → 同 C。
  `failures.isEmpty`（fix round 1）擋掉 B／C／D；DA 提的 `!merged.isEmpty` 修 D 仍擋 C；`survivorUpdated` 只擋 A——
  凍結態（無條件遷移）在 B／C／D 本來就對，錯的只有 A。兩支 failure-injection 測試（A：被併檔 immutable；B：keeper 寫後
  entry immutable）；C／D 沒有注入手段（前移的可刪檢查會在 A 就擋下 immutable），是程式路徑推導。
- **person 腿的寫入閘**（DA-3）：`assertPersonWritable(_:format:)` 從 `writePerson` 抽出（ended ≥6、attested ≥7、
  verdict ≥8、巢狀 names ≥10、validate），renameEntry／renamePerson 的 person 迴圈與被改名的 person 本身都接上。此前
  只 encode——DA 用 format 7 fixture 重現：entry 已改名、person 的 verdict 沒遷移。兩支測試（rename／rename-person）。
- **DA-1 的 live 形狀回歸**：venue 持兩條 `paginated` 判定（value 皆 nil、rests-on 不同；`bmc-genomics` 三刊的真實形狀），
  無關的 `rename` 與 `rename-person` 後兩條都在、報告不列它。
- **rename 側 helper 只對可解析的 verdict 收攏**（R3 N2）：#395 的 `migratedVerdicts` 對**每一筆** reference 做
  (field, value) dedup，抽出共用後 renameEntry 也繼承了它——一次無關的 rename 會靜默丟掉兩筆同 (field, value)、不同
  來源的 affiliation reference 並把記錄算進報告。統一到 renameEntry 原本的窄語意（非 verdict 原樣通過）；renamePerson
  因此只會少收攏。nil／文法不合的 verdict 在載入後的記錄上到不了 helper（三族 `validate()` 擋、load quarantine）。
- **rename 的 format 閘 lazy、讀一次共用**（R3 N3）：`lazyStoreFormat()`，renameEntry／renamePerson 的 venue 與
  organization 閘共用。**但 R3 的前提對 rename 不成立**：整個 rename 在 `load()` 就讀 marker（`StoreVersion.read(data:)`），
  壞掉的 store.yaml 擋住**任何** rename，與閘無關——第一版測試「壞 marker 下純 person rename 成功」實測紅，改成只斷言
  provider 讀一次並快取。改動的價值是與 R2 同一條紀律（不無條件讀），不是可達性；`writeOrganization` 不讀佈局，R2 對它才是可達性。
- `PersonRenameReport.verdictValuesRewritten` doc 補 venue（N4）；`migratedVerdicts` 回 `private`（N5）；
  `assertOrganizationWritable` 的 provider 單次讀取有可殺 mutant 的測試（N6：帶 verdict 的 org 經過兩個要 format 的閘）。
- CLI 標籤改成不列舉 holder 種類（「持有記錄 key」）——與 #465 對使用者可見字串的同一裁決：列舉第四種出現時就過期。

### 這一輪同時寫下的邊界與義務

- **矩陣沒有 work 記錄欄**，這是本表**唯一**真正結構性的缺席：`Entry.validateReferenceAttachment` 的值域只有
  doi／pmid／isbn，verdict 欄位落 `default` 直接 throw，entry 記錄不可能持有 verdict（DA-8）。
- **量 live verdict 要走 YAML 解析，不要單行 grep**：`DB88AB9C-1AE0-56EB-B328-7D65AF7F6D8C.yaml` 的 value 被 YAML
  折行，` :: ` 在下一行——單行 regex 得 8／6，正確是 9／7（logic L3 因此 REJECTED）。給 #464 的掃描器同一個提醒
  （它走已解析的 `references`，不受影響；留 comment 附這個檔當 fixture）。
- **被 quarantine 的記錄整張網格看不見**（DA-7）：一筆 names 不合法的 organization 持 `person:doomed` verdict，
  `rename-person` 成功並印「無其他記錄引用此 key」，磁碟上那條仍指向退役 key。四格補齊只涵蓋 `load()` 看得見的
  記錄；#488 的後置條件若也只看 `load()` 同樣看不見。開 follow-up。
- **merge 後要更新的地方**：#464 第 13 列的歸因（合法 rename 不再產生死 verdict——DA-3 修完這句才成立）；#465 的
  `AppState.rename` doc 與 `changelog/2026-09-03-app-rename-report.md`（rename 報告的 holder 種類多了 organization）；
  #467（preview 對 verdict 面沉默）與 #469（rename 側收攏靜默、`RenameReport` 沒有 `verdictsCollapsed`）的範圍隨本張擴大。
