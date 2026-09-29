# 2026-09-29 #642 的驗證 R1：依據不明確、改名同批遷移、set-kind 是整值替換

`2026-09-29-library-membership-rules.md`（854fd5d3）與 `batch11-integration`（def4ce7c）經六席驗證，51 則發現，其中 14 則 MEDIUM。這份記的是修正，逐項對到發現編號（`第 N 則`＝驗證報告陣列的第 N 個）。

## 問題

三類：

1. **同一個不明確的依據，設定規則時被拒、使用規則時被放行**（第 1、5 則）。`create`／`set-kind` 拒絕重複的 venue key，`add` 卻只比對 key 字串；排除清單的 citekey 從不查存在，打錯的 citekey 讓排除無聲失效，create 成功、`validate` 零診斷。
2. **`set-kind` 是整值替換，卻不回顯舊值、不要求舊值可取回**（第 6、8、17、44 則）；改名與合併的守衛把使用者導向它，而文件型的出路是死路：`set-kind` 要新 citekey 已在庫，`rename` 要它不在庫（第 7、39 則）。
3. **整合與 skill 的敘述沒有跟著變**：verify-venue 只改了三處過期敘述的一處、venue-works 叫 agent 自己替未標性質的 library 標規則型、format 21 的使用者面（拒絕訊息、validate warning、skill）沒有一處說出「rule／document 需要 format ≥ 21，不要改標 topic 來解鎖」、WriteGateRulings 的計數少算兩個命令。

## 改了什麼

**判定（`LibraryMembershipCheck`，AkashicCore）**
- 建構子多一個**必填**的 `venues`（沒有預設值：預設空陣列會讓忘了傳的呼叫端安靜放行重複的 venue key）。規則的 venue key 有不只一筆記錄時，每一筆成員都回 `.ruleVenueAmbiguous`。
- `violation(of:)` 對未標性質回 `.libraryUnmarked`（fail-closed），呼叫端不必另行預查（第 29 則）。
- `basisProblem`：規則的依據本身有問題（venue key 重複、文件不在庫或重複）。`library check` 兩面揭露，零成員的 library 也看得到（第 1 則）。
- 排除清單建構時做成 `Set`，逐成員比對是 O(1)（第 31 則）。
- `details(of:)`：完整規則逐行，含每一個排除的 citekey；`library check` 與 `set-kind` 的「先前」段用它（第 17、44 則）。
- `Library.unmarkedMessage` 與 `assertLibraryWritable` 的訊息都說出：性質由使用者決定、rule／document 需要 store format ≥ 21、**不要改標 topic 來解鎖**（第 10、14、28、42 則）。門檻只定義一次（`LibraryMembership.requiredStoreFormat`）。

**寫入面**
- `create`／`set-kind` 對排除清單裡不在庫的 citekey 具名拒絕、零寫入（第 5 則）。
- `set-kind` 抽成 `setLibraryKind`（CLI 與 MCP 共用，CLI 不再多 load 兩次，第 36 則）：兩面的回應都回顯**先前**的成員性質（CLI 印完整的舊規則；MCP 回 `previous`／`previousBasis`）；替換一條**既有**的性質時，registry 檔要 tracked 且 clean（第 6、8 則）。從未標性質標成任何一種不需要；重送相同的值不需要。
- 可回溯閘抽成共用核心 `LibraryStore.recoverabilityRefusal`（新檔 `RecoverabilityGate.swift`），`assertRecordsRecoverable` 委派給它並多收 `libraries:`（registry 檔）；不複製邏輯。
- `create` 對 topic 不再讀整份 store（第 36 則）。
- MCP doctor 的 library warning 把指路句移到訊息前段，點名 ≥3 筆時也不會被 300 字截掉（第 16 則）；新增 warning：規則的依據不明確、排除清單指向不在庫的 citekey。

**改名與合併（第 7、24、39、45 則）**
- `rename` **同批遷移**規則（文件型的文件、規則型的排除清單）：registry 檔納入改名同一批預檢（format 閘＋encode）與同一批寫入，不撕裂；遷移逐條列在 `RenameReport.libraryRulesRewritten`（CLI 一段、App 回執一行）。
- 三個前置拒絕、零寫入：新 citekey 已被某條規則指涉（懸空的文件或排除，改名之後那條規則會「復活」成指向另一筆 work）；被隔離的 registry 檔提到舊或新 citekey（位元組比對、token 邊界，不會被壞檔永久卡住不相干的改名）；要遷移的 registry 檔不可回溯。
- work 合併與 venue 合併維持拒絕，訊息逐個 library 給出**可直接照做的 `set-kind` 命令**（改指倖存者，type 與排除清單帶過去，來歷指路 `library check`）。這些出路**都不經過 topic**：規則全程都在，只是換了指涉的對象；不需要「降成 topic 再改名」那種期間不檢查規則的繞路。
- 合併對被隔離的 registry 檔本來就拒絕（`quarantinedPresent`，#295，位元組比對、不分目錄）——第 45 則說合併守衛 fail-open 對合併不成立，只有改名缺這一半；補了一支測試釘住合併這一側。

**App（第三面）**
- `addToLibrary` 從磁碟重讀 registry 與 entries 再判定（比照 `mutate()`）；`FileWatcher` 監看 `libraries/`（第 13、30 則）。
- 未標性質的訊息指向終端機（App 沒有標性質的面）；選單項目的 tooltip 帶描述與性質、未標性質的項目停用（第 2、35、47 則）。

**Skill 與規則（第 2、3、4、9、15、18、21、25、28、33、47 則）**
- `akashic-verify-venue`：步驟 3(c) 的重號掃描與移除面、`argList` 敘述、`--remove-issn` 的引號問題。
- `akashic-venue-works` 步驟 5：本 skill 自己建的全量目錄依定義是規則型、可以建並告訴使用者；**已存在的 library 不論 kind 都停下來問**，不代他分類；撞 format 閘停下來回報，不得改標 topic；命令裡插的值只從 store 取，寫出引號規則。
- `source-of-truth-over-consent`：「逐筆明列的例外」明寫是**排除**；「skill 不再讀描述」改成規則的要求、`akashic-work-references` 尚未跟上（#678）。

**文件與計數**：`zero-instance-guards` 第 37 列的量測改成實印的 59／59／不寫 20／不閘 18／逐腿 3／過閘 18；第 44 列的量測說明它量的是 live marker；第 47 列的「舊 binary」來源改成實際情況、Python 對照保留重複；`entity-backlink-completeness` 第 16 條邊、`mcp-cli-parity`（`akashic_libraries` 與 `rename` 兩列）、`two-kinds-of-edits`、`docs/store-format.md` §2.9、README、CLI 的 help；兩支釘 supported 的測試改名（`…Twenty` → `…TwentyOne`）；`StoreVersion.supported` 的 doc 移除整合過程敘事；`UpdateEntryCLITests` 重複的註解。

## 測試與負控

新增測試：`LibraryMembershipRuleTests` +5、`LibraryMembershipStoreTests` +12、−1（換掉舊的「改名一律拒絕」那支；改名遷移、三個前置拒絕、registry 預檢不撕裂、合併出路、排除懸空、依據不明確、指路句在前 300 字內）、`LibraryMembershipServiceTests` +6、`LibraryMembershipFormatGateTests` +1、`AppLibraryMembershipTests` +5、`AppStateTests` +1、`FileWatcherTests` +1、`StdioE2ETests` +1（字串型 `types`／`excluded` 經真 binary 被拒、registry 位元組不變）、新檔 `LibraryRuleCLITests`（5，真 binary）。

負控 19 組，反向編輯（不用 `git checkout`）後各自轉紅、還原後 `cmp` 逐位元組相同：規則 venue 重複不再是依據問題（13 個斷言失敗）、未標性質 fail-open、create／set-kind 不查排除清單、懸空排除不報 warning、指路句移回訊息尾端（300 字截斷切掉它）、set-kind 替換不要求可回溯（10）、set-kind 不回顯先前、改名不遷移規則（7）、改名不擋新 citekey 已被規則指涉、改名不擋被隔離的 registry 檔、改名不要求 registry 可回溯（8）、registry 預檢不進同一批（work 先改名而規則沒跟上）、合併出路不給命令、App 用記憶體快照判定、`FileWatcher` 不監看 `libraries/`、create topic 也 load、未標性質訊息不警告 topic、`check` 不揭露依據問題、選單 help 不帶描述。

第 20 組（排除清單改回線性 `contains`）**沒有紅，這是預期的**：`Set` 與 `Array.contains` 功能等價，這一項是純效能重構，沒有負控；測試只釘功能（20,000 筆排除清單仍逐筆精確比對）。

第一次跑 `FileWatcherTests` 篩選時負控是綠的——不是守衛沒抓到，是我新加的測試住在 `FileWatcherWatchTargetsTests` 這個類別、篩選器沒涵蓋；改用測試函式名重跑後轉紅。

## 誠實邊界

- **「放寬規則要明確確認」沒做**（第 6 則的建議）：`set-kind` 把規則降成 topic、清掉排除清單、換 venue 都不需要額外確認參數。現在的防線是「回顯舊值」加「舊值在 git（要求 registry 檔已 commit）」。MCP 面無法分辨呼叫端是使用者還是 agent，這一點沒有解決；列為待使用者決定。
- 替換既有性質的可回溯閘**包含 topic**（原本是 topic 也要求 registry 檔已 commit）。topic 沒有參數可失去，這一格比必要的嚴；依「最保守、可逆」照 brief 的字面做，使用者可以翻。
- 合併的出路命令要求倖存者一定在庫（合併前置已驗），排除清單超過 8 筆時命令裡不內嵌全部、改指路 `library check`。倖存者是被排除 citekey 時合併放行（既有行為，未改）。
- 第 45 則另兩點沒修：被隔離的 venue 在 `set-kind` 被說成「不在庫」（訊息誤導、方向仍是拒絕）、文件型只看 `hits == 1` 不看共用 id 的 `unlocatableCitekeys`。
- 沒做多份文件支援（第 26、41 則）：一個 library 只能指一份文件；`psy1007-115-1` 那類多來源的目錄標不成文件型。follow-up 提案：`document` 改成 `documents: [citekey]`（成員是它們 `cites` 的聯集），需要 store format 與 `LibraryMembership` 的 sum type 一起動。
- 沒限制 `source` 的字元集（第 32 則）：確認它進回應與訊息都經 `displaySafe…`（payload 600 字、basis 200 字），字元集文法是另一個決定。
- `excluded` 的筆數在 decode 時沒有上限（第 31 則的後半）：現在的比對是 O(1)，decode 仍是每個元素一次 `StoreKey` 驗證，受 8 MiB 檔案上限約束。
- `authorize-names --apply` 仍無條件把 marker 寫成 `supported`（第 27、50 則），只在整合 changelog 的升級前置補了說明；`migrate` 升到 `supported` 是它的語意。
