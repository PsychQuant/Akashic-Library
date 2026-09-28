# 2026-09-28 venue 名字的 canonical 形有修復面了（#575）

`Venue.validate()` 自 #554 R5（D8）起對 names／authorized／variant 的名字內容跑 error 級的不變式，而寫入閘以 error 收尾：一筆違反的 venue 所有寫入面都關門。`fmt` 同一輪改成先 validate、有 error 就拒（它的語意是 canonical 序列化，不修內容）。所以舊 binary 寫出來的 `"Psychometrika "`、NFD 位元組的名字，唯一的修法是手改 YAML。

## 改了什麼

**新命令 `akashic repair-venue-names`**（使用者 2026-09-28 裁決：機械修復面，乾跑預設、顯式 `--apply`）。

- **乾跑是預設。** 逐筆列出「venue　清單[index]　「before」 → 「after」（改了什麼）」。改動說明分四種：未 NFC、前導空白、尾隨空白、內部空白。NFD → NFC 的兩個字串在終端機上看起來一樣，所以說明一律印。
- **只改確定性的那一類。** 條件有四個，要同時成立：字串違反的只有 canonical 形那一條、正規化之後通過其他條；沒有 `field: names`／`field: authorized` 的 reference 以位元組指著這個拼法；這筆 venue 的全部改寫做完之後 `Venue.validate()` 沒有 error（沒造出近重複，authorized ⊆ names 與分割互斥仍成立，也沒有其他 error）；改寫之後 reference 的附著驗證仍通過。
- **要判斷的只具名、不改。** 不可見或控制字元、沒有字母數字、空白、近重複對、正規化之後仍不合法、同一筆記錄的其他 error，都列出字串與理由。同一筆記錄只要還有一項要判斷，它的確定性改寫全部延後（照列、不寫），因為記錄還有 error 就寫不進去。
- **NFC 的單一碼位替換逐碼位說出來。** CJK 相容表意文字 U+FA10 → U+585A 這一類是位元組層有損的，原碼位的區別不保留。它仍是 canonical 形的定義，所以仍算確定性，但乾跑的說明寫成「含單一碼位替換 U+FA10→U+585A」。
- **`--apply` 的兩道閘，乾跑與實跑共用。** 每一筆要改寫的 venue 先過寫入閘（format 閘、validate、encode 自檢），再要求那些 venue 檔已在 git 裡 commit、乾淨（`assertRecordsRecoverable`：被改寫前的位元組只剩 git 那一份）。任一筆不過即整批拒絕、零寫入。乾跑把同一組閘的拒絕當預告印出來。
- **目標 store 確認閘。** `--apply` 過 #298 的閘（`DestructiveTargetGate.destructiveCommands` 同批加入），乾跑不受管制。拒絕訊息的預覽提示用預設的「先跑一次不帶 --apply 的 dry-run」。issue 的裁決寫「with dryRunFlag」，但那個參數是給預設就寫、以 `--dry-run` 預覽的命令（migrate、resolve-divergence）用的；本命令預設就是乾跑，傳它會讓提示說「加 --dry-run」，那是假話。
- **讀不進來的檔要說出來。** store 有 quarantine 的檔時，報告印出個數：「沒有違反」只對走訪過的記錄成立。
- **`--apply` 而沒有可改的**：標頭寫「--apply：沒有可確定性改寫的項目」，不寫「乾跑」也不寫「已寫入」。

**訊息指路**：`NameIdentity.wellFormednessIssue` 的「不是 canonical 形」訊息，除了「在 YAML 裡改成……」，另外指向 `akashic repair-venue-names`。其餘各類（不可見字元、近重複等）的訊息不變，那些是判斷，仍然只能手改。`Venue.validate()` 的逐字串訊息抽成 `Venue.wellFormednessMessage`，讓修復計畫認得哪些 error 是它已經逐字串具名過的，不會對同一個字串說兩次。

**只有 CLI 面。** 維運例外，同 `fmt`／`migrate` 族：改寫既有記錄、逆操作是 git、乾跑逐筆過目之後才寫。MCP 的寫入工具寫不出非 canonical 的名字（`vetVenueNames` 先 canonical），沒有 LLM 流程會產生需求。名字不變式的 error 經 `akashic_doctor` 的 `recordIssues` 到得了 MCP 面，而那則訊息指向這個 CLI 命令，這是記在 parity 表的面不對稱。

## 測試

- `VenueNameRepairPlanTests` 14 支：乾淨的 venue 沒有計畫；尾隨空白在 names 與 authorized 一起改、改完 validate 零 error、再算一次是空計畫；NFD 改成 NFC 位元組；單一碼位替換要說出來；空白類的改動說明；正規化後仍含不可見字元只具名、理由說的是真正的問題、不被「不是 canonical 形」重報；空白與純符號只具名；改完會造出近重複的延後；不相交的沿革段不算近重複、時間欄位不動；同一筆記錄有判斷項時改寫全部延後；authorized ⊆ names 由改寫恢復；只有近重複時只具名；名字內容沒違反而只有別的 error 不在範圍；reference 指著舊拼法時不改。
- `VenueNameRepairServiceTests` 7 支：乾跑不寫；`--apply` 只寫確定性的那筆、要判斷的那筆一個位元組都不動、再跑一次是空的；未 commit 的檔讓 `--apply` 整批拒絕、乾跑預告；store 不在 git 裡拒絕；一筆過不了寫入閘（format 13 的 store 帶 `paginated`）整批零寫入；沒有違反；quarantine 的檔被數出來。
- `RepairVenueNamesCLITests` 5 支（真 binary、scratch store、`AKASHIC_HOME` 指 scratch）：乾跑印出改寫與判斷項、原始不可見字元不落終端機、零寫入；`--apply` 寫入且 `validate` 對那筆零 error、判斷項照報；未 commit 的 store 整批零寫入；未指名目標的 `--apply` 被 #298 閘擋下而乾跑不被擋、`--yes` 是出路；`--apply` 而沒有可改的時標頭照實說。
- `DestructiveTargetGateTests` 的封閉列舉加入本命令，三條稽核照舊。

**負控（每支都暫時拿掉守衛、確認轉紅、反向編輯還原並以 `cmp` 確認位元組相同）**：拿掉「正規化之後仍不合法」一支，3 則失敗（這一次也讓計畫把一筆 validate 不過的記錄報成可寫，所以同輪補了一道：改完之後 validate 仍有 error 而一項判斷都沒有時，照實列出、不寫）；拿掉 reference 指著舊拼法的檢查，1 則；拿掉改完之後的 validate，3 則（兩支近重複測試）；拿掉單一碼位替換的說明，1 則；拿掉 git 可回溯閘，5 則；拿掉寫入閘的預演，2 則（另一筆照樣被寫了，106 對 109 位元組）；報告不數 quarantine，1 則；CLI 不呼叫 #298 閘，4 則（含 `DestructiveTargetGateTests` 的呼叫稽核）；`--apply` 而沒有可改的時標頭寫成乾跑，2 則。

**實測**：2026-09-28 讀 live store（唯讀）：venue 485 筆、名字字串 1,052 個、不是 canonical 形的 0 個——這個命令今天對 live store 是空操作。scratch store 手改三種違反（尾隨空白、NFD、U+FA10；另一筆夾 U+200B 與前導空白）後乾跑列出 4 筆確定性改寫與 1 筆要判斷的 venue，`--apply` 只改前一筆，`validate` 只剩那筆的兩則 error。

## 規則與文件

- `two-kinds-of-edits` 加一列（程式編輯；不併進 `migrate-*`／`fmt` 那一列，因為改的是名字的內容位元組）。
- `mcp-cli-parity` 的 CLI-only 表加一列（有理由缺席，維運例外；寫明不是從 `fmt`／`migrate` 類推來的）。
- `zero-instance-guards` 第 25 列的「修法是人改 YAML」補上確定性那一類的修復面，並記下它是名字的第六個寫入者、同樣經 `writeVenue`。
- `docs/store-format.md` §5.7：刪掉「工具不提供 `--repair`」，補修復面的四個條件（封閉）與閘；部署視窗那一段補「#575 起確定性的那一類可以修」。
- `openspec/specs/venue-entity/spec.md` 的「Venue name well-formedness」：修法那一句補上機械例外，加兩個 scenario。§5.7 寫著兩處要一起改。

## 誠實邊界

- **寫回走 `VenueYAML.encode`。** 檔案原本若不是 §3.4 的 canonical 序列化，git diff 會多出排版差異；名字以外的內容不變。
- **寫入中途的 I/O 失敗不是零寫入。** 寫入閘與 git 閘在寫之前全部過完，但若第 N 筆的原子寫入本身失敗（磁碟），前 N−1 筆已經寫了。那幾筆的舊位元組在 git 裡（`--apply` 要求已 commit），可以 `git checkout` 回去。
- **reference 以位元組指著舊拼法時不改**，即使改寫之後 reference 的 value 也可以跟著確定性地改。那筆 provenance 是一次取得或一次判定的記錄，它的 value 要不要跟著改交給人。今天零實例。
- **零實例的 CLI 命令沒有進 `zero-instance-guards`。** 那份規則的前言點名「零實例的 CLI 命令」是要顯式擴入的第五類候選。本命令正是零實例（live store 0 筆違反），但它的「要不要現在做」已由使用者在 #575 裁決；是否因此擴入第五類，留給使用者裁決，這裡沒有擅自擴。
