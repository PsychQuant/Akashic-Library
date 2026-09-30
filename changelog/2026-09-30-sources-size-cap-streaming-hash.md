# 2026-09-30 sources/ 單份上限 256 MB、SHA-256 與複製逐塊、補存時比對既有 blob（#703）

#703 問三件事（b16v verify 第 15、16 則，#606 R2 之後留下的）：`store-source`、`SourceStore` 與 `copy-zotero-attachments`（含乾跑）都把整份檔讀進記憶體，而群組 library 的附件可能是別人放進去的；`copy-zotero-attachments` 判斷「已連過」只看 blob 在不在、index 有沒有條目，被截短或換掉的 blob 看不出來。使用者 2026-09-30 裁決：「三件都做，上限 256 MB」——超過的略過並具名、不截斷；SHA-256 逐塊；補存時比對既有 blob 的內容，不一致具名回報、不覆寫。

## 量到的東西（2026-09-30，唯讀）

| | 檔數 | 合計 | 最大單檔 |
|---|---|---|---|
| Zotero storage | 2,817 | 61,047,841 bytes（`du -sh` 66 MB——磁碟用量，不是檔案大小） | 5,499,190 bytes |
| `sources/`（含 `index.jsonl`） | 104 | 19,820,273 bytes | 3,912,063 bytes |

上限 268,435,456 bytes 是 Zotero 最大單檔的 **48.8 倍**。裁決裡的「約 46 倍」是 256 MB／5.5 MB 的粗算（分子是 MiB、分母是 10⁶ bytes）；兩個數都寫出來，重量腳本在 `zero-instance-guards` 第 72 列的量測段。超過上限的檔兩處都是 0。

## 改了什麼

### 1. 上限：一個常數

`LibraryStore.maxSourceBytes`＝268,435,456（`Sources/AkashicStoreIO/SourceStore.swift`）。讀它的地方：

- `SourceStore.storeSource`（`Data` 與 `FileHandle` 兩個入口，同一條路徑）：看得到大小的先比（不讀），讀的時候超過就停。
- `AkashicService.storeSource(path:)`——`store-source`（CLI）與 `akashic_store_source`（MCP）共用：`fstat` 判大小，超過就整個拒絕，訊息說出路徑、實際大小與上限。
- `ZoteroStorageFile.locate`（lstat 的大小）與 `ZoteroStorageFile.openVerified`（descriptor 的 `fstat`）。
- `copy-zotero-attachments`：計畫（含乾跑）與複製兩段都經上面兩個。

各函式的 `limit` 參數是測試接縫，預設值就是這個常數；對外沒有任何入口能改它。給人看的寫法只有 `LibraryStore.sourceCapDescription`（`268435456 bytes（256 MB）`）。

### 2. 逐塊

- 讀取與 digest 住在新檔 `Sources/AkashicStoreIO/SourceChunks.swift`（`SourceStore.swift` 加上這一輪會超過 800 行）。唯一的讀取迴圈是 `LibraryStore.pump`：每次至多 `sourceChunkBytes`（1 MiB）。`contentDigest(reading:)` 與 `storeSource(contentsOf:)` 都經它；`contentDigest(of:)`（整份 `Data`）與逐塊的入口共用同一個 `digestText`，digest 的形狀（`sha256:` + 64 個小寫 hex）不變。
- **存檔改成兩遍**：第一遍只算 digest、不寫任何東西（要知道 digest 才知道位址、才能問那條路徑的版控排除）；排除驗證過了，第二遍逐塊寫進同一個分片目錄裡的暫存檔（`O_EXCL` 建立），邊寫邊再算一次，兩遍相同才以 `renamex_np(RENAME_EXCL)` 放上位址。兩遍之間內容變了（或長過上限）就刪掉暫存、不落地（`.refused(.changed)`／`.tooLarge`）。
- **暫存檔的路徑也過排除驗證**：只排除 blob 名、不排除暫存名的規則（例如 `sources/??/[0-9a-f]*`）會讓第三方位元組暫時落在一個沒被排除的路徑上；拒寫、什麼都不留。代價是新寫一個 blob 多一次 `git check-ignore`。
- **位址上已有東西就不寫**（任何種類，lstat 語意）。先前用 `fileExists`（跟隨 symlink）加 `Data.write(.atomic)`：懸空的 symlink 會被當成「沒有」、然後被取代。現在不寫穿、不取代；同一時間別人放進來的也不覆寫（`RENAME_EXCL` 的 `EEXIST`）。
- `store-source` 以 descriptor 開檔（`O_NONBLOCK`），`fstat` 確認是普通檔。目錄與 FIFO 先前走 `Data(contentsOf:)`：目錄是一個看不出原因的「讀不到」，FIFO 會讓呼叫卡住等一個寫入者；現在兩者都具名拒絕，開檔不卡住。
- `ZoteroStorageFile.read`（整份讀進 `Data`）換成 `openVerified`：同樣的 `O_NOFOLLOW`、`fstat`、`F_GETPATH` 判斷，交回停在開頭的 descriptor 讓呼叫端逐塊讀。

`copy-zotero-attachments` 的讀取次數：計畫一遍（算 digest），複製兩遍（`storeSource(contentsOf:expectedDigest:)` 先驗 digest 與計畫相同、再逐塊複製並再算一次）。先前是計畫一遍、複製一遍但整份在記憶體裡。多讀一遍換到的是記憶體與檔案大小無關；三遍都從 `openVerified` 交回的 descriptor 讀。

### 3. 既有 blob 的比對

`LibraryStore.checkStoredBlob(digest:expectedBytes:)`：位置上是普通檔就比大小（不同就不讀、直接判不符），相同再逐塊算 digest。結果是封閉的五種：`absent`、`matches`、`mismatch(bytes:digest:)`、`notRegularFile`、`unreadable`。不改任何東西。

`copy-zotero-attachments` 在計畫時（乾跑也一樣）對三種「位元組已在 `sources/`」的情形比對：

- 已連過、index 有條目（先前直接算「已連過」）；
- 已連過、index 沒有條目（先前直接「補記」取得記錄）；
- **新連結遇到同一個 digest 已有一份**（別筆 work 或 `store-source` 存過）。

第三種不在裁決的字面（「補存時」「已連過」）裡：同一個風險、同一個比對，不比的話會把一份已知是壞的存檔連到 work 上、再替它記一條取得記錄。所以一併比。

不符的列在新的報告欄 `storedBlobMismatch`（`ZoteroAttachmentCopyReport.StoredBlobMismatch`：Zotero 那一份的 item、存檔的實際大小、存檔內容的 digest——大小不同時是 nil、是否已連在 work 上）。處置：**不覆寫**那一份、不補記、不新連。CLI 印一段「sources/ 已有這個 digest 的存檔，但內容與 Zotero 原檔不符」，逐檔列 citekey、路徑、已連／要新連、兩邊的大小與 digest，並說「把 sources/ 裡那一份移走後重跑，會以 Zotero 原檔補存」。`--apply` 遇到時非零結束（收容不是吞掉，與 `writeFailed`、`restoreFailed` 同一條）；乾跑只列出。判不出來的（位置上是目錄、讀不到）沿用 `localCopyUnverifiable` 具名略過。

`copy-zotero-attachments` 只有 CLI 面（`mcp-cli-parity` 的 CLI-only 表），這一欄因此只在 CLI 出現；MCP 的單檔對應 `akashic_store_source` 同批加了同一個上限，回應鍵不變。

## 「略過並具名」與 `lossless-intake` 有界拒絕的五條

那一節（#519）的第 1 條是「整批，不是逐筆略過」。`store-source` 一次一個檔，整個呼叫拒絕就是整批，五條照舊成立。`copy-zotero-attachments` 換成**逐檔**：超過的那個檔略過，其餘照跑。

為什麼仍不是靜默丟棄：第 1 條的理由是「部分寫入會讓『哪些進去了』需要讀報告才知道」，而 `copy-zotero-attachments` 從 #606 起就是逐檔具名略過（檔案不在、不是普通檔、0 byte），它的報告本來就是唯一說得出哪些進去了的地方，乾跑逐檔過目後才 `--apply`。超過上限是同一類「這個檔不能收」；整批拒絕會讓一個大附件擋住其餘全部，換到的資訊量是零。其餘四條都在：零寫入（大小以 stat 判斷，連讀都不讀）、具名（citekey、路徑、實際大小、上限，乾跑就印）、不截斷、上限有量測出處。來源原封不動留在 Zotero。

這個差異寫進了 `lossless-intake.md` 的有界拒絕一節（「第二個實例」），並明寫只及於本來就逐檔具名略過的批次入口，不得類推。

## 規則與文件

- `zero-instance-guards`：第 72 列（整合時與 #689 的第 71 列相撞而順延；表頭 71 → 72）、量測段、「各列共通的東西」的第 72 列。
- `lossless-intake`：有界拒絕一節加「第二個實例」。
- `mcp-cli-parity`：`akashic_store_source` 列與 CLI-only 表的 `copy-zotero-attachments` 列各加「#703 重新確認，裁決不變、契約有改」。
- `two-kinds-of-edits`：`copy-zotero-attachments` 列補一句（比對是決定論式的，種類不變）。
- `docs/store-format.md`：`sources/` 一節加上限與逐塊寫入；`copy-zotero-attachments` 那一條加 #703。
- `plugin/CHANGELOG.md`：`akashic_store_source` 的新拒絕（回應形狀不變）。
- MCP `akashic_store_source` 的描述加一句上限（64 bytes）；`tools/list` 實測 50,297 bytes（預算 52,000）。

## 測試

新增 `SourceIntakeStreamingTests`（14 支）、`StoreSourceSizeCapCLITests`（1 支）；`ZoteroStorageFileTests` 的讀取測試改經 `openVerified`，加 3 支上限；`ZoteroAttachmentCopyTests` 加 6 支；`StoreSourceEntryPointTests` 加 3 支；`CopyZoteroAttachmentsCLITests` 加 2 支。超過真上限的情形用 APFS 的 sparse 檔（`truncate(atOffset:)`，不佔磁碟；大小以 stat 判斷，測試同時斷言 descriptor 一個位元組都沒讀）；其餘用注入的小上限。

全套（`swift test --build-system native`）：4,363 支，1 支跳過（`MigrateProvenanceCLITests` 既有的權限條件），1 支失敗——`SanitizationBoundaryTests.testErrorTextWorkIsLinearInTheInput` 的計時比值 8.44 超過 8.0，當時機器的 load average 約 100（三個 worktree 同時跑測試）；單獨重跑通過（2.3 秒）。與本輪無關的程式碼。守衛（`.githooks/run-guards.sh`）rc=0。

## 負對照（反向編輯、`cmp` 對照備份確認還原）

| 反向編輯 | 紅的測試 |
|---|---|
| `storeSource(chunks:)` 拿掉讀取前的大小判斷、`pump` 拿掉讀到超過就停 | `SourceIntakeStreamingTests` 4 支（真上限的 sparse 檔整份存進去、注入上限的兩支、讀的時候長大的那支） |
| `ZoteroStorageFile` 的 `locate` 與 `openVerified` 拿掉上限 | `ZoteroStorageFileTests` 3 支 |
| `pump` 一次要 `Int.max`（改回整份讀） | `testDigestAndCopyNeverAskForMoreThanOneChunk` |
| `checkStoredBlob` 一律回 `matches` | `testCheckStoredBlob…`、`ZoteroAttachmentCopyTests` 4 支比對、CLI 的截短 blob 那支 |

第二格拿掉 `ZoteroStorageFile` 的上限時，`copy-zotero-attachments` 的兩支上限測試仍綠：`pump` 讀到超過上限就停，同一個檔照樣以大小具名略過。那是設計上的第二道，不是測試漏看；兩道各自有紅的負對照。

## 誠實邊界

- **上限只約束寫入**：既有的存檔不因此變成不合法，`checkStoredBlob` 對它們不設上限（逐塊，記憶體仍與大小無關）。
- **逐塊只由讀取迴圈證明**：`testDigestAndCopyNeverAskForMoreThanOneChunk` 證的是經過 `pump` 的讀取每次只要一塊。所有讀 handle 的路徑都經 `pump`（`contentDigest(reading:)`、`storeSource(contentsOf:)`），但一個日後新加、自己 `readToEnd()` 的呼叫端不會讓任何測試紅。沒有量測記憶體用量的測試（會不穩定）。
- **比對在計畫時做**：計畫到實跑之間，`sources/` 裡那一份再被換掉看不到（沒有 store 層的鎖），與 #606 既有的時間窗同一類。
- **`store-source` 讀兩遍**：兩遍之間檔案變了，拒絕（`在讀取期間內容變了`），不會存下一份與 digest 不符的內容；但也就要人重跑。
- **不符的 blob 沒有工具面可以移除**：`sources/` 沒有「移除一筆存檔」的面（與 #544 同族），訊息請人手動移走那一份（它不進 git）。
- **`store-source` 碰到既有 blob 仍不比對**：裁決的第三件只及於 `copy-zotero-attachments`。`store-source` 重存一份位址上已有東西的內容時，照舊回 `bytesWritten: false`、不覆寫，不檢查那一份對不對。
