# 2026-10-02 `resolve-venues` 的 `suppressed` 改成線性成本；文字更正（#712 R1）

#712 R1 verify（40 則）裡屬於 #712 的部分。

## 列表的成本對 store 內容是二次方（R1 verify 第 0、1 列，HIGH）

第一版把否決表的值從「鍵在不在」改成「壓住這個鍵的每一個 rejected literal」（`[RejectedPairKey: [String]]`），然後對每一條被壓住的邊各做一次 `contains`（O(K)）、一次 `sorted()`（O(K log K)），還把整個排序後的陣列存進那一列。截到 5 個是在 `AkashicService.suppressedPayload` 才做，MCP 的 20 列上限與 48 KiB 預算也都在 `resolve` 跑完之後。N 條邊共用同一組 K 個被否決拼法時，時間是 N×K log K、記憶體是 N×K。store 檔的讀取上限是每檔 8 MiB，所以手改或第三方帶來的 store 能把列表撐到幾分鐘、幾 GB；MCP 的 server 是同一個 actor，會被卡住。

**修法**：

- 每個否決鍵的被否決拼法收成一個 `Set<String>`（建一次，O(R)，R＝rejected verdict 數）。「候選自己是不是其中之一」改成 O(1) 查找；`Set<String>` 的相等是 canonical equivalence，與先前的 `String ==` 同一把。
- 依字串排序的前 `VenueResolver.suppressedLiteralsPerRow`（5）個，每個鍵**至多排一次**，在第一次有列需要它時才排，之後各列共用。
- `VenueSuppressedCandidate` 只帶那至多 5 個拼法，另加 `rejectedLiteralsTotal`（去重後的總數）。截斷從輸出端搬進 resolver；`AkashicService.suppressedLiteralsPerRow` 拿掉，改用 `VenueResolver.suppressedLiteralsPerRow`。
- `VenueResolver.resolve` 多一個 `reportingSuppressed` 參數（預設 `true`）。apply／reject 腿傳 `false`，不組 `suppressed`、不排序（它們不讀它）。預設是 `true`：新的列表面忘了傳時多做一點工，而不是安靜地少一段。

**輸出契約不變**：每列 `rejectedLiterals` 至多 5 個，超過時該列多 `rejectedLiteralsTotal`；兩面同一份 JSON。N=K=4000 的 store 上新舊兩版的輸出逐字相同（下面的量測）。

### 量測（真 binary，debug 建置，暫存的 `AKASHIC_HOME`）

store 由腳本產生：一筆 work 帶 N 條 literal venue 邊，一個 venue 帶 K 筆 `resolution-rejected`，全部是 `psychometrika` 的大小寫變體（同一個 matchingKey、彼此不同、互不相等）。量 `akashic resolve-venues` 列表一次，`/usr/bin/time -l`。

| | N=K=4000（store 760 KB） | N=4000、K=1 |
|---|---|---|
| 修正前（本分支起點，含 #712 第一版） | 16.88 秒、306 MB | 0.26 秒、28 MB |
| 修正後 | **0.88 秒、43 MB** | 0.23 秒、28 MB |

修正後 N=K=2000 是 0.54 秒、29 MB，N=K=4096 是 0.76 秒、42 MB，隨 N、K 線性成長（含載入 YAML 與輸出 4000 列 JSON）。R1 verify DA 席量到「#712 之前的版本 0.57 秒」，是在另一台機器上、而且那一版沒有 `suppressed` 段可印；這裡沒有另外建那一版來比。N=K=4000 時兩版輸出的 JSON 解析後相等。

### 測試

`VenueResolverSuppressedTests` 加三個（7 → 10）：

| 測試 | 驗什麼 |
|---|---|
| `testEachRowCarriesAtMostTheCapEvenWhenManySpellingsWereRejected` | K=200、N=50：每列的 `rejectedLiterals` 恰 5 個（依字串排序的前 5 個），`rejectedLiteralsTotal`＝200。直接讀 resolver 的 report，所以第一版在這裡會看到 200 個 |
| `testFewRejectedSpellingsAreAllShownAndTheTotalMatches` | 被否決的拼法少於 5 個時全列、總數等於陣列長度（payload 據此不帶 `rejectedLiteralsTotal`） |
| `testNotReportingSuppressedLeavesCandidatesAndAmbiguitiesUnchanged` | `reportingSuppressed: false` 時 `suppressed` 為空，`candidates`／`ambiguities` 與列表腿相同 |

`VenueSuppressedByNormalizationTests.testByteBudgetDropsRowsThatDoNotFitAndSaysSo` 改成餵 resolver 截過的列（5 個拼法、總數 6），其餘斷言不變。

**負對照**：把 resolver 裡的截斷拿掉（`shown = spellings.sorted()`，回到每列存全部）→ `testEachRowCarriesAtMostTheCap…` 紅（`200` ≠ `5`，排序前 5 的斷言也紅）；反向編輯還原後綠。

**沒有做牆鐘時間的測試**：牆鐘會隨機器與負載跳，測試會偶發紅。上面那個是結構性的上界（每列的陣列長度與 K 無關），CPU 的那一半靠上表的真 binary 量測。

## 文字更正

- **「同 resolve-people 的 `rejected` 段」不成立**（R1 verify 第 4、39 列）：people 的 `rejected` 段只列逐字等於被否決拼法的作者位，被同一筆否決以正規化鍵壓掉的兄弟拼法不在其中——resolve-people 與 resolve-organizations 的列表對它們仍然沉默，還會說「任何提名層皆無命中」。四席用真 binary 重現；這是 #712 之前就有的缺陷，追蹤在 **#721**。`VenueResolver`／`AkashicService` 的 doc comment、`mcp-cli-parity.md` 的 `akashic_resolve_venues` 列、`resolve-venues --help` 都改成說出這一點；2026-10-01 的 #712 changelog 那兩句加了更正。
- **`--help` 說「撤回面見 #559」是錯的**（R1 verify 第 16、26、30 列）：#559 上線的只有 `update-venue --unauthorize`（撤回名字的對外形），撤回 reject／demote 至今沒有工具面。`resolve-venues --help` 與 `two-kinds-of-edits.md` 的那一句改掉。
- **`akashic-verify-venue` Step 0 寫「已否決沉底」**（R1 verify 第 25、30 列）：venue 列表沒有已否決段，逐字被否決的邊哪裡都不列。Step 0 改成列出 `suppressed`，並把「literal 沒有出現在 candidates」拆成四種可能（歧義、suppressed、逐字否決或已歸戶、店裡沒這個名字）。邊界段那句「那一格是使用者否決過的判定，不要重新提名」過度宣稱——使用者否決的是另一個拼法——改成「報給人，不要自己 apply、reject 或改寫 verdict」。`akashic-venue-works` 第 4 步同樣要報 `suppressed`。
- **2026-10-01 changelog 說 issue 寫了「by matchingKey 但不是 byte-exact literal」**（R1 verify 第 29 列）：issue 內文沒有這句。更正為那是我對 issue 的讀法。`==`（canonical equivalence）而不是位元組相等的選擇仍待使用者確認（R1 verify 第 17、37 列），本輪沒有改。

## 沒有做的

- **people／organization 的列表不動**：主 session 裁定為另案（#721），本輪只把文字改誠實。
- **`truncated` 不改名**（R1 verify 第 34、37 列）：它在 venue 列表腿只說 `suppressed` 被截（candidates／ambiguities 沒有上限），doc comment 已寫明；改名會動到已出貨的回應鍵。若之後 candidates 也加上限，那時要重開。
