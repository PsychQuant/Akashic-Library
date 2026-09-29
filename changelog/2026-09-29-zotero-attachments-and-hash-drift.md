# 2026-09-29 附加來源的變動報告分開「內容變了」與「只有 hash 不同」；Zotero 附件複製進 `sources/`（#608、#606）

兩張 issue 都出自 #605（一筆 work 可帶多個 Zotero 來源）：#608 是 #605 verify R1 的 follow-up finding，#606 是 #605 的 sibling concern（Clarity Surface 第 3 列裁決拆出）。

## #608：`secondarySourceChanged` 分不出「Zotero 端有人改」與「hash 的算法變了」

**問題**：附加來源的變動偵測用 mapping hash（`ZoteroMapping.mappingHash`，涵蓋 type／title／date／mapped fields／authors／attachments 經**目前這版** mapping 算出的 SHA-256）。mapping 演進時（`mappingHash` 的注解記著這是刻意的、可見的大批更新）每個附加來源的 hash 都變，報告把每一個都列成「有變動」。#605 的 store 副本端對端驗證就是這樣：三筆全列出，Zotero 端沒有人改。

**兩個候選只有一個可行**：issue 提的「比對時用同一版 mapping 重算舊 hash」做不到——舊 hash 是舊版 mapping 對**舊內容**算的，兩者都不在手邊（附加來源不存書目欄位，也不存舊版 mapping）；要做到就得在 provenance 裡多存一個 mapping 版本戳，那是 store format 變更。另一個「附上 Zotero version 是否前進」不需要存任何新東西：來源本來就存 `zotero_version`，比對時手上有目前的 `item.version`。

**改了什麼**：附加來源命中時，hash 不同再看 Zotero 的 version——
| 舊 hash | version | 報告 |
|---|---|---|
| 有，與現在不同 | 前進或倒退 | `secondarySourceChanged`（條目在 Zotero 端有變；倒退時不知道發生什麼，維持這一格，寧可多報） |
| 有，與現在不同 | **沒動** | **`secondarySourceHashOnly`（新）**：沒有人改這個條目，變的是 hash 的算法或它涵蓋的子項附件集合 |
| 有，相同 | 前進 | 兩格都不列（既有行為；version 照常更新） |
| 沒有（pre-v1.1） | 前進 | `secondarySourceChanged`（既有：無從比較內容，寧可多報） |

新一格**只說觀察到的事實**（hash 不同、version 沒動），不宣稱原因：Zotero 的子項（附件）有自己的 version，加減附件不推進父條目的 version，而 hash 涵蓋附件路徑——附加來源不存附件清單，這兩種原因分不開。兩格的本地 hash 與 version 都已重算存回，下一趟不再列。MCP payload 多 `secondarySourceHashOnly`（與其餘 `secondarySource*` 同形，空陣列也在），CLI 多一行說明；`docs/store-format.md` §2.5.3 與 `mcp-cli-parity` 的 `akashic_import_zotero` 列同步。**不改 store 存的任何東西、不改 store format。**

## #606：Zotero 附件複製進 Akashic 檔案區（`copy-zotero-attachments`）

**設計盤點（動手前）**：
- 附件記錄（`Entry.attachments`，關係邊第 6 條）的鍵域是封閉的一（#223）：只有 `zotero: storage/<KEY>/<檔名>`，「不得因形狀相似而新增第二種路徑型引用」。可 ingest 的內容一律以 **digest** 引用、住在記錄側的 `akashic.sources`（第 17 條邊，store-format §2.4.1，format ≥ 9；#614 補了第一個寫入面 `update-entry --add-source`）——所以「這個附件的位元組在 `sources/` 的某個 digest」**既有形狀已經表達得了**，不需要新的附件形狀、不改 store format。
- `attachments` 是 **Zotero 擁有的區塊**（namespace 契約 §2.5）：每次 pull 整批以 Zotero 為準。issue 的 Expected 寫「改寫附件記錄指向新位置」，照字面做（拿掉或改寫 `zotero:` 記錄）下一次 `import-zotero` 就被還原；而且它同時就是這份副本的來源記錄。所以**不改寫 `attachments`**（見代裁）。
- `SourceStore.storeSource` 的閘：寫入前用 git 自己的 `check-ignore` 驗證 `sources/` 被版控排除（fail-closed；store 不在 git 裡時跳過並在回條說出來）；index 有壞行拒寫；0 byte 拒收。本命令全部經它，不繞過。

**改了什麼**：
- 新命令 `akashic copy-zotero-attachments [--zotero-db PATH] [--citekeys a,b] [--apply]`（`Sources/akashic/CopyZoteroAttachmentsCommand.swift`）；`--zotero-db` 與 `import-zotero` 同一個旗標與預設（`~/Zotero/zotero.sqlite`），附件在它所在目錄的 `storage/` 底下。
- `AkashicService.copyZoteroAttachments`（`Sources/AkashicMCPKit/ZoteroAttachmentCopy.swift`）：對每筆帶 `zotero:` 附件的 work，定位檔案、算 digest、去掉已連過的，剩下的：實跑時 `storeSource`（`origin: zotero:storage/<KEY>/<檔名>`、`acquisition: zotero-storage-copy`、media type 由副檔名推、`retrieved` 是複製當下、note 記 work 與檔案修改時間）→ 把 digest 追加到 `akashic.sources` → `writeEntry`。單筆失敗收容（`import-zotero` 的形，非零退出），其餘照跑。
- `ZoteroStorageFile`（`Sources/AkashicZoteroImport/ZoteroStorageFile.swift`）：附件路徑是**未信任輸入**（YAML 的 path 只驗是字串）——只收恰好 `storage/<KEY>/<檔名>` 三段（無 `..`、`.`、空段、絕對路徑、NUL；這一步不進檔案系統）、lstat 語意不跟 symlink、真實位置要在 `storage/` 內（`storage/` 自己是 symlink 合法）、非空普通檔。
- `LibraryStore.contentDigest(of:)`（`storeSource` 原本內嵌的公式抽出，位址公式只有一份）與 `preflightStoreSource(digest:)`（`storeSource` 在任何磁碟寫入之前會擋的三件事，不寫）——多筆操作要在第一次寫入之前預演，乾跑說「可以」時實跑才不會在第一個 `storeSource` 才被拒。
- 契約：**乾跑預設**；實跑要求被改寫的 work 檔已在 git 裡 commit、乾淨（`assertRecordsRecoverable`，只覆蓋**真的要被改寫**的記錄），且每筆過 `writeEntry` 的全部前置（`preflightWrite`）、每個 digest 過 `storeSource` 的前置——任一道過不了就整批零寫入，乾跑把拒絕當預告放進報告。**可重跑**：digest 已在該筆 `akashic.sources` 上的不重複；blob 早就在 `sources/`（前次跑到一半）的只補連結、index 不重複 append。逐筆具名略過：路徑不合、檔案不在、不是普通檔、0 byte、讀不出來、計畫之後內容變了（digest 對不上——不存、不連）；無法唯一定位的 work（`unlocatableCitekeys`）。
- 裁決兩面：CLI-only，有理由缺席（`mcp-cli-parity` 的 CLI-only 表新增一列——兩面的能力沒缺：單檔的同一件事 MCP 面有 `akashic_store_source` ＋ `akashic_update_entry.add_sources`，CLI 是同一條路徑的批次形）；`two-kinds-of-edits` 加一列（程式編輯：搬運與落地，不是判定）；`WriteGateRulings` 一格（過閘，`--apply` 才閘、乾跑不閘）。`docs/store-format.md` §2.4／§2.4.1、`entity-backlink-completeness` 第 17 條邊、README 同步。

## 測試與負控

`ZoteroImportTests` +5（#608）、`ImportZoteroReportSurfaceTests` +1、`ZoteroStorageFileTests` 9、`ZoteroAttachmentCopyTests` 17（服務層，真 git、假 Zotero 資料目錄）、`CopyZoteroAttachmentsCLITests` 8（真 binary）。全套 `swift test`（4,032 支）在兩處登記表上紅了兩支——`GitSpawnHygieneTests.auditedFiles`（新測試檔 spawn git）與 `PersonCLITests.expectedFiles`（新命令檔建 `AkashicService`）——都是「新檔要登記」的機械守衛，登記後兩個 suite 綠；登記之後沒有重跑整個全套（只重跑那兩個 suite）。另兩個守衛（`SanitizationBoundaryTests` 的 throw-site 逃脫表、`DisplaySinkCoverageTests`）也在第一輪紅過、已加 `display-safe-exempt` 具名註記。`run-guards.sh` rc=0。

**先紅後綠**：#608 的 3 支在實作前紅（報成內容變動／新格為空），2 支對照組先就綠（釘既有行為）；#606 的服務與 CLI 測試在實作前編譯失敗（API 不存在）。

**負控**（反向編輯、`cmp` 確認還原，全部轉紅）：
- #608：附加來源 version 相等時仍報 `secondarySourceChanged` → 3 支紅（含 MCP payload 那支）；不看 version 一律進新格 → 5 支紅（內容變動、version 倒退、兩個附加來源各自分類、payload 都不再成立）。
- #606：拿掉 `assertRecordsRecoverable` → 3 支紅（未 commit、store 不在 git，含 CLI）；拿掉 `preflightStoreSource` 迴圈 → 1 支紅（乾跑不再預告 `sources/` 未排除）；`preflightStoreSource` 不驗排除 → 同 1 支紅；拿掉實跑前的 digest 重驗 → 1 支紅（`changedDuringRun`）；不去掉已連過的 → 4 支紅（重跑、內容相同的兩個附件、閘只覆蓋要改寫的記錄、CLI 重跑）；乾跑也寫入 → 5 支紅；不略過無法唯一定位的 work → 1 支紅；複製後清掉 `attachments` → 4 支紅；`ZoteroStorageFile` 把 symlink 當普通檔 → 3 支紅、不驗路徑各段 → 2 支紅、不驗真實位置在 `storage/` 內 → 1 支紅；CLI 不過目標確認閘 → 2 支紅（含 `WriteGateRulingsTests` 的「表說過閘、原始碼真的呼叫」）。第一次的「不驗路徑形狀」變異寫壞了（0 支紅，實際是別的錯），改成只拿掉各段檢查後 2 支紅。

## 代裁（使用者可翻）

1. **不改寫 `attachments`**（#606）——**待使用者裁決，issue 上沒有使用者對這一條的裁決紀錄**（R1 verify 第 3 列）：issue Expected 與任務說明寫「改寫附件記錄指向新位置、保留原 Zotero 來源作為 provenance」。既有形狀下，位元組的位置由 `akashic.sources` 表達，`zotero:` 記錄原樣保留當來源記錄；改寫它會被下一次 pull 還原，且 `attachments` 鍵域是封閉的一。翻的方式：日後真的切斷 Zotero 時，先 `update-entry --remove-zotero-source` 拿掉來源（之後 pull 不再管它的 `attachments`），再另案決定要不要清掉 `zotero:` 記錄。
2. **`retrieved` 用複製當下、修改時間進 note**：Zotero 端檔案真正的取得時間不可得；`retrieved` 是「你何時取得」，從 Akashic 的角度就是複製當下。
3. **實跑要求 work 檔已 commit**（任務說明的要求）：它是追加、不刪任何東西，嚴格說不需要；照說明保守處理，且被改寫前的位元組只剩 git 那一份。
4. **`--zotero-db` 而非 `--zotero-dir`**：與 `import-zotero`／`enrich-from-zotero` 同一個旗標，資料目錄取 `zotero.sqlite` 的父目錄；要求它存在、且旁邊有 `storage/`。
5. **`akashic.sources` 的 digest 沒有逐附件的對照**：一筆 work 有兩個附件時，哪個 digest 來自哪個路徑只記在（不進 git 的）`sources/index.jsonl` 的 `origin`。可重跑靠 digest 比對，不需要對照；日後若要「這個附件對應哪個 digest」的可追溯查詢，是另一個形狀決定。
6. **#608 的新一格不宣稱原因**（見上）；主來源的 `updated` 有同樣的歧義（mapping 演進讓每一筆都列成 updated），issue 只談附加來源，未動。

## 誠實邊界

- **只複製附件記錄的那一個檔**：HTML snapshot 同目錄的資源檔（`storage/<KEY>/` 底下的其他檔）不複製。
- **`sources/` 不進 git**：別台 clone 讀到 `akashic.sources` 時位元組不在（§2.4.1：載入成功、可報缺席）；`validate` 的「本機缺承重存檔」在那裡會列出來。~~本命令在那台機器上把它們列為「已連過」、不補~~ → R1 起在那台機器上重跑會補存（見下）。
- **沒有大小上限**：~~檔案以 mmap 讀入（不常駐記憶體）~~ → R1 起每個檔整份讀進記憶體、存完即釋放（mmap 在檔案被截短時會讓行程收到 SIGBUS）；複製 GB 級附件會佔磁碟。
- **Zotero 端之後再變**（重新下載、註記編輯）不會回頭更新已複製的副本——那是另一份內容、另一個 digest，下一次跑再連一份；舊的要用 `update-entry --remove-source` 收回。
- **乾跑不保證實跑**：閘在乾跑與實跑之間可以變（有人 commit 或改檔）；計畫之後檔案內容被換掉由 digest 對不上偵測（`changedDuringRun`），檔案不見則落在 `unreadable`。
- **沒有跑過真的 Zotero 資料目錄**：測試用假目錄；live store 唯讀量測 2026-09-29：work 2,572 筆、帶 `zotero:` 附件的 51 筆（51 個附件）、`akashic.sources` 的 digest 0 個。
- **`zero-instance-guards` 沒有需要加的列**：兩件事都不是「為還沒發生的形狀寫守衛」——#608 是報告多一格（不是守衛），#606 是一個有實例的能力（live store 51 個附件、0 個 digest）；整合者若判斷不同再加。

## Verify R1 修正（#606）

以下的「第 N 列」是 batch14 verify R1（b14f）報告的列號。

**計畫之後被改過的 work 不以舊快照覆寫（第 0、7 列）。** 實跑以前在可回溯閘之後把計畫時 load 的整筆記錄寫回。閘證的是「此刻磁碟上的檔已 commit、乾淨」，不是「它還等於計畫時的快照」；閘與複製迴圈之間別的寫入者（MCP server、App、另一個 CLI）改過並 commit 的內容會被整筆蓋掉，而且那次修改不在任何地方。現在寫 work 之前讀閘回傳的那個檔（`LibraryStore.rereadEntry`，與 load 同一份解碼與正規化——load 對 `akashic.libraries` 的去重抽成 `normalizedAfterDecode` 一份），與快照不同就不寫、記進 `writeFailed`（「計畫之後這筆 work 的記錄檔被改過」），其餘照跑；位元組已存進 `sources/`，重跑以新的內容重新計畫、補上連結。App 的 #609 移除面以整個 store 重 load 比對；這裡是批次，逐筆重 load 整個 store 太貴（live store 副本上一次 `validate` 約 6 秒，debug 建置），所以只讀單一檔。**誠實邊界**：重讀與寫入之間仍有很短的窗（沒有 store 層的鎖）。

**「已連過」看本機位元組，不看連結（第 1、6、11、14 列）。** `akashic.sources` 在 git 裡、`sources/` 不在：別台 clone 上連結都在、位元組都不在，以前全部列成「已連過」、印「沒有新東西要複製」，`validate` 同時報「本機缺承重存檔」。現在已連過的 digest 一次查 `sourcePresence`（#614）：在（含只缺取得記錄的孤兒 blob）才算 `alreadyLinked`；不在的進新的 `restoredLocally`——只存位元組與取得記錄、不改連結、不寫 work 檔（所以不過可回溯閘，只過存檔前置）；位置上是目錄／symlink、分片讀不到、或 index 壞到判不出的，以新的略過原因 `localCopyUnverifiable` 具名、不重存。CLI 分一段印「已連過、但本機 sources/ 沒有位元組——要補存／已補存」，這種情形不再印「沒有新東西要複製」。

**丟棄的取得記錄要看得到（第 14 列後半）。** `storeSource` 冪等早退時回 `discardedProvenance`（這次的 `origin: zotero:…` 與 note 沒有寫進 index），以前只記成一個計數 `blobsAlreadyStored`，「自己上次跑到一半」與「同一份位元組先前經別的路徑存過、這次的 Zotero 來源沒落地」混成同一個數。現在逐檔列在 `provenanceNotRecorded`，附 index 保留的那一條的 `origin`（讀自 `sourcePresence`）；`blobsAlreadyStored` 改成它的個數。

**讀 Zotero 檔只開一次（第 25 列）。** `ZoteroStorageFile.read`：`O_NOFOLLOW | O_NONBLOCK` 開啟、`fstat` 確認是非空普通檔、以 `F_GETPATH` 問 kernel 這個 descriptor 的真實位置在 `storage/` 之內（`storage/` 自己也經 descriptor 問，兩邊同一種寫法），再從同一個 descriptor 讀完。計畫與實跑兩次讀都走它。以前兩次都是 `Data(contentsOf:, .mappedIfSafe)` 以路徑讀——`locate` 之後把檔換成 symlink 或把 KEY 目錄換成指出去的 symlink，兩次讀都會跟過去且 digest 一致；mmap 在檔案被截短時會 SIGBUS。

**未改（第 3 列）**：「改寫附件記錄」的替代仍是待使用者裁決的代裁 1，行為不動；上面的代裁 1 已寫明 issue 上沒有使用者的裁決紀錄。

**測試**：`ZoteroAttachmentCopyTests` +4（閘之後改過並 commit 的 work 不被覆寫且重跑補上、連結在而本機缺位元組的補存不改連結且不要求 work 檔乾淨、本機那一份位置上是目錄時具名略過、丟棄的取得記錄附保留的 origin）；`CopyZoteroAttachmentsCLITests` +1（真 binary：第二份 clone 拿掉 `sources/` 後重跑補回、work 檔位元組不變、`validate` 不再報缺）；`ZoteroStorageFileTests` +6（讀回位元組、定位後換成 symlink、KEY 目錄換成指出去的 symlink、換成 FIFO 不卡住、被清空、`storage/` 本身是 symlink）。

**負控**（反向編輯、`cmp` 確認還原）：拿掉重讀比對 → 1 支紅（閘之後改過的那支）；`.absent` 當成已連過 → 2 支紅（服務層與 CLI 的補存）；不記丟棄的取得記錄 → 3 支紅（新的一支與既有兩支 `blobsAlreadyStored`）；`read` 拿掉 `O_NOFOLLOW` → 1 支紅（換成 symlink）；拿掉 kernel 真實位置的前綴比對 → 1 支紅（KEY 目錄換出去）。`O_NONBLOCK` 沒有做負控：拿掉它的結果是測試卡住，不是紅。

## Verify R2 修正（#606）

第二輪六席（requirements、logic、security、regression、devil's advocate、Codex）；全輪 62 則沒有 HIGH。R1 的 HIGH（以計畫時的快照覆寫）由 requirements、logic、security、regression、devil's advocate 五席各自確認已關閉，Codex 沒有對它下判斷。以下「第 N 則」是本輪報告的編號。

**孤兒 blob 補記取得記錄（第 5、16 則）。** 位元組在、`sources/index.jsonl` 沒有它的條目時，以前算進「已連過」，每次重跑都說做完了、`akashic doctor` 一直報孤兒 blob，而工具手上就有補記需要的資料。現在另列 `recordRestored`（乾跑「要補記」、實跑「已補記」），走同一個 `storeSource`：blob 已在所以不重寫，index 沒有條目所以補上這一次的取得記錄（`origin: zotero:…`）。不改連結、不動 work 檔，只過存檔前置。**沒做的一半**：第 16 則另提「以 Zotero 的位元組比對既有 blob 的內容」。「已連過」仍只看 blob 在不在與 index 有沒有條目，不重算既有 blob 的 digest；被截短或換掉的 blob 由這個命令看不出來。型別 doc 寫明這一點，先前那句「位元組層的語意」改掉。

**同一筆 work 兩個內容相同的附件只補存一次（第 6 則）。** 補存那一條路以前只以路徑去重：digest 已連、本機缺位元組時兩個都進 `restoredLocally`，第二次 `storeSource` 冪等早退，被報成「取得記錄沒寫進去」，CLI 說補存了 2 個檔。現在與新連結那一條路同形：第二個列在「已連過」。

**補存失敗另列（第 7 則）。** 補存擲錯（I/O、磁碟滿）以前記在 `writeFailed[citekey]`：同一筆 work 的新連結已經寫進去時，同一個 citekey 同時在 `written` 與 `writeFailed`，訊息說寫入失敗。現在記在 `restoreFailed`（檔、訊息），CLI 另一段「補存失敗（連結沒動、work 檔沒動；重跑會再補）」，照樣非零結束。測試接縫多一個 internal 的 `beforeStore`（每一次 `storeSource` 之前呼叫，擲錯即當成那一次存檔擲錯），對外的入口沒有這個參數。

**報告的措辭（第 8、20、27 則）。**
- 標題：`applied` 只說走到了寫入那一段。有改寫 work 才說「已寫入」；只補存時說「已補存本機 sources/，沒有改寫任何 work 檔」；全部略過時說「沒有改寫任何 work 檔、也沒有補存任何檔」。第 20 則另提結束碼：全部略過仍是 0——略過逐行具名、與新連結那一條路同一個規則；真的失敗（`writeFailed`、`restoreFailed`）才非零。
- 結尾：沒有改寫 work 檔時說「沒有東西要 commit（sources/ 不進 git）」，不再叫人 validate 之後 commit。
- 丟棄的取得記錄：以前一律說「位元組早就在 sources/」，而 index 的條目還在、blob 被清過時，位元組其實是這一次補存的——同一份輸出剛說過「已補存」。現在標題說「index 已有這份內容的取得記錄、這次的 Zotero 來源沒有寫進去」，每一行說位元組是「已在（先前或這一趟稍早存的）」還是「這一次才存進 sources/」。判斷來自 `SourceReceipt` 新的 `bytesWritten`（這次呼叫有沒有寫出 blob，與 `indexEntryCreated` 是兩件事）；`blobsAlreadyStored` 只數前者。

**過期的註解（第 18 則）**：計畫階段那句「讀檔只為算 digest（mmap，不常駐）」改成整份讀進記憶體、算完即釋放。

**沒有大小上限，寫成誠實邊界（第 15 則）**：`ZoteroStorageFile.read` 把整個附件讀進記憶體，乾跑也一樣（要讀完才算得出 digest）；群組 library 的附件是別人放的，一個幾 GB 的檔會吃掉等量的記憶體。`store-source` 與 `SourceStore` 本來就沒有大小上限，這裡不另立一個數字；型別 doc 補上「乾跑也一樣」。

**不修的**：
- 第 1 則（MEDIUM）：issue 的 Expected「改寫附件記錄指向新位置」仍未照字面實作，是待使用者裁決的代裁 1；行為不動，這一則留在 issue 的 Blocking。
- 第 17、19 則：`rereadVenue` 沒有被 #606 用到——在 main 頂端它是 #675 的 `VenueNameSegmentEdit` 在用（devil's advocate 第 59 則），不是死碼。第 17 則說 public 的 `rereadEntry`／`rereadVenue` 沒有路徑包含檢查：今天的輸入只來自可回溯閘自己列舉的檔名，不是外部字串；本輪不動。

**測試**：`ZoteroAttachmentCopyTests` +4（孤兒 blob 補記取得記錄、內容相同的已連附件只補存一次、補存失敗不算 work 的寫入失敗、index 留著而 blob 被清過時丟棄照列但標明位元組是這次才存的）；`CopyZoteroAttachmentsCLITests` +1（真 binary：同一個情形的輸出沒有「早就在」）、既有的第二份 clone 那一支多驗標題不說「已寫入」、結尾不叫人 commit。

**負控**（反向編輯、以備份逐位元組還原）：孤兒 blob 回到「已連過」→ 1 支紅；拿掉補存那一條路的去重 → 1 支；補存失敗記回 `writeFailed` → 1 支；`bytesWereAlreadyStored` 一律 true → 2 支（服務層 1 支、兩則斷言；CLI 1 支）；CLI 標題改回「applied 就說已寫入」→ 1 支；結尾改回一律叫人 commit → 1 支；丟棄那一行改回「位元組早就在 sources/」→ 1 支。
