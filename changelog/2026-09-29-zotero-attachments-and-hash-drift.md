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

1. **不改寫 `attachments`**（#606）：issue Expected 與任務說明寫「改寫附件記錄指向新位置、保留原 Zotero 來源作為 provenance」。既有形狀下，位元組的位置由 `akashic.sources` 表達，`zotero:` 記錄原樣保留當來源記錄；改寫它會被下一次 pull 還原，且 `attachments` 鍵域是封閉的一。翻的方式：日後真的切斷 Zotero 時，先 `update-entry --remove-zotero-source` 拿掉來源（之後 pull 不再管它的 `attachments`），再另案決定要不要清掉 `zotero:` 記錄。
2. **`retrieved` 用複製當下、修改時間進 note**：Zotero 端檔案真正的取得時間不可得；`retrieved` 是「你何時取得」，從 Akashic 的角度就是複製當下。
3. **實跑要求 work 檔已 commit**（任務說明的要求）：它是追加、不刪任何東西，嚴格說不需要；照說明保守處理，且被改寫前的位元組只剩 git 那一份。
4. **`--zotero-db` 而非 `--zotero-dir`**：與 `import-zotero`／`enrich-from-zotero` 同一個旗標，資料目錄取 `zotero.sqlite` 的父目錄；要求它存在、且旁邊有 `storage/`。
5. **`akashic.sources` 的 digest 沒有逐附件的對照**：一筆 work 有兩個附件時，哪個 digest 來自哪個路徑只記在（不進 git 的）`sources/index.jsonl` 的 `origin`。可重跑靠 digest 比對，不需要對照；日後若要「這個附件對應哪個 digest」的可追溯查詢，是另一個形狀決定。
6. **#608 的新一格不宣稱原因**（見上）；主來源的 `updated` 有同樣的歧義（mapping 演進讓每一筆都列成 updated），issue 只談附加來源，未動。

## 誠實邊界

- **只複製附件記錄的那一個檔**：HTML snapshot 同目錄的資源檔（`storage/<KEY>/` 底下的其他檔）不複製。
- **`sources/` 不進 git**：別台 clone 讀到 `akashic.sources` 時位元組不在（§2.4.1：載入成功、可報缺席）；`validate` 的「本機缺承重存檔」在那裡會列出來。
- **沒有大小上限**：檔案以 mmap 讀入（不常駐記憶體），但複製 GB 級附件會佔磁碟。
- **Zotero 端之後再變**（重新下載、註記編輯）不會回頭更新已複製的副本——那是另一份內容、另一個 digest，下一次跑再連一份；舊的要用 `update-entry --remove-source` 收回。
- **乾跑不保證實跑**：閘在乾跑與實跑之間可以變（有人 commit 或改檔）；計畫之後檔案內容被換掉由 digest 對不上偵測（`changedDuringRun`），檔案不見則落在 `unreadable`。
- **沒有跑過真的 Zotero 資料目錄**：測試用假目錄；live store 唯讀量測 2026-09-29：work 2,572 筆、帶 `zotero:` 附件的 51 筆（51 個附件）、`akashic.sources` 的 digest 0 個。
- **`zero-instance-guards` 沒有需要加的列**：兩件事都不是「為還沒發生的形狀寫守衛」——#608 是報告多一格（不是守衛），#606 是一個有實例的能力（live store 51 個附件、0 個 digest）；整合者若判斷不同再加。
