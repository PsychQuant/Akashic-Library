# 識別碼真的落地了：讀取→raw、寫入→normalized，以及三個不在清單上的發現（#394 §4）

2026-08-24 傍晚。接續同日稍早那則（`2026-08-24-identifiers-typed-not-yet-serialized.md`）——
**那一則描述的狀態已經結束**：新欄位不再是「型別存在但寫不進也讀不出」。§4 落地之後
`venue.issn`／`organization.ror`／`entry.doi`・`pmid`・`isbn` 都真的進 YAML 了。

那則的「安全理由很窄（目前沒有生產者）」也隨之退場——現在有生產者，而它是對的那一個。

## 落地的三件事

**一份編解碼，四個型別共用。** `IdentifierYAML` 管序列化，`IdentifierDiagnostics` 管
非正規形的 diagnostic。`Person.orcid` 原本自己有一份 decode（§3 留下的），一併收斂進來
——同一份規格的兩份副本必然分岔，這是本 repo 反覆記過的形狀。

**空清單不寫鍵。** 既有記錄零 diff 靠這一條：全庫沒有任何記錄帶識別碼欄位時，序列化
輸出必須逐位元不變。

**非正規形出聲但不擋路。** severity 是 warning 而非 error：值指涉正確、只是寫法不是
正規形，遷移會修它。依 #416 的判準 `hasFindings` 只計 error——記成 error 會讓一份正常的
store 常態顯示不健康，那個布林就失去訊號。訊息同時給原樣值與正規形，否則讀的人不知道
要改成什麼。

## 一個必須先裁決的分岔（三份規格互不相容）

「讀取面要寬容到什麼程度」，三份文件講的不是同一件事：

| 來源 | 涵蓋範圍 |
|---|---|
| spec scenario | “does not match **the normal form**”——只涵蓋非正規形 |
| design.md Failure modes | 「**形狀不合法**的識別碼在讀取面被接受並保留」 |
| 已落地的 §3 程式碼 | `orcid: not-an-orcid` → 整筆 quarantine，測試綠著 |

而 §3 的測試註解明寫它預期 §4 會把這個行為翻過來。所以這不是誤讀，是規格自己分岔。

差別很實際：`ISSN("12345")` 回 `nil`，`[ISSN]` 裝不下它。要做到 design 那句就得新增一個
機制（型別的 invalid 狀態或 per-field 殘留），而那要一路穿過相等、export、遷移、
provenance 四處。

**使用者裁定取窄讀法**：非正規形載入並保留，形狀不合法仍拒讀。理由不是「比較好做」，
是 `id` 與 `issn` 的不對稱——`id` 壞掉是**身分**壞掉（不知道這是哪一筆），`issn` 壞掉是
**屬性**壞掉。但 quarantine 是**看得見**的失敗（`doctor`／`validate` 報得出來），沒有
違反 `lossless-intake` 的「靜默是最糟的形式」；而觸發寬容版的情形是**零實例**（寫入面
已拒絕、遷移對無法解析者略過，只有手改 YAML 到得了那一格）。

裁決、理由、以及**何時該重新裁決**都寫進 design.md 的 Failure modes 了。依
`zero-instance-guards` 的立場，這一格要不要防是一列一列裁決的，而這一列是「現在不防」。

## `Venue.validate()` 在全樹零呼叫端（既有缺陷，本輪順帶補上）

`StoreHealth.perRecordIssues` 收 entry／person／library／organization／divergence **五族**，
venue 不在裡面——#416 把 per-record 驗證抽進 `StoreHealth` 時，那一輪的封閉列舉就漏了它。

後果是：venue 的 key 格式錯誤、authorized 與 names 不符、未知欄位警告**一直都沒有任何
讀取面看得到**。這正是 `entity-backlink-completeness` 執行細節 2 記過的形狀：一個 entity
kind 在讀取面沒有路徑，而缺席不會有任何跡象。

它是 4.3 的前置條件（沒有它 `venue.issn` 的 diagnostic 出不來），所以本輪補上。**但它
本身是一個獨立於 #394 的既有缺陷**，記在這裡是為了它不要隨著本 change 一起被遺忘。

## 型別層測試對這種缺口是結構性地盲

task 4.3 的驗證目標寫的是「對**暫時 store** 執行 validate」，不是「`validate()` 回傳
那則 diagnostic」。一開始只驗到型別層，補寫 CLI 層測試之後**立刻紅**——印出
「0 entries、0 people、0 libraries 全部通過」，venue 根本不在 validate 的視野裡。

「函式回傳正確的 diagnostic」與「沒有人呼叫那個函式」可以同時成立，而型別層的斷言對後者
全綠。規格作者把驗證目標寫在 CLI 層，是因為知道這一格會漏。

**同一支測試還抓到測試自己的錯**：第一版用 `writeVenue` 寫非正規值，但寫入面**會正規化**
——那個測試斷言的狀態在結構上不可能發生。非正規形只存在於遷移前的舊記錄，測試得直接
改寫磁碟上的檔案才模擬得出來。

## 順帶：一支守衛的假陽性（#407，單獨 commit）

`measured-claims-audit.py` 斷言 HEAD **完全沒有** trailer，而那個前提是「HEAD 不會是
GitHub 的 merge commit」——從未寫下、也從未被測，因為 pre-push 永遠在 merge **之前**跑。

GitHub 的 merge commit body 會回音 PR 的 commit 標題，而 `feat: …` 符合 git 的 trailer
文法，於是被當成 trailer。**實測最近 20 個 merge commit 有 11 個會踩到。**

修法不是跳過 merge commit（那會讓真的 `Reviewed-by:` 掛在 merge commit 上時抓不到），
是讓 trailer 與 header 問同一個問題：token 是不是 review 類，兩邊共用 `REVIEW_ISH`。
附兩個方向的回歸 fixture——只釘「不誤報」的話，把檢查改成永遠回空也會綠。

假陽性正是 `zero-instance-guards` 第 6 列點名最貴的失效：它讓人學會「這支有時候會紅，
重跑就好」，而那個習慣會套用到所有守衛身上。

## 量測

| | |
|---|---|
| `swift build -Xswiftc -warnings-as-errors` | 通過 |
| 新增測試 | `IdentifierCodecTests` 10 條、`IdentifierValidateCLITests` 3 條（走真 binary） |
| 守衛負控 | 53/53 |
| 進度 | #394 **10/21**，§5–§9 共 11 個 task 未做 |

## 還沒做

§5（基數決定 provenance 驗證分支）、§6（format 12 → 13）、§7（匯出面）、
§8（`migrate-identifiers` 遷移）、§9（兩面對等與收尾）。

一個已知的小缺口留到 §9：`validate` 的摘要行是「N entries、N people、N libraries
全部通過」，**沒有數 venue 與 organization**。它們現在會被檢查了，但摘要仍不提它們。
