# 2026-09-29 library 有了機器可讀的成員性質，掛錯目錄在寫入時就不寫（#642）

2026-09-24，`akashic-work-references` 往回追一篇種子論文，把 56 筆被引文獻依「掛進種子所屬 library」全部掛了進去，其中一個是 Psychological Methods 的全量目錄。52 筆不是該刊作品，隔天 verify 才發現，已在 store `2f18107a` 移除。根因不在那個 skill：`Library` 只有 key、名稱、描述三個欄位，`setMembership` 只檢查 action、key 格式與 citekey 存在，「這是封閉目錄」只寫在描述的自由文字裡。寫入時擋不下，`validate`／`doctor` 事後也看不出來，唯一的防線是叫模型去讀描述。

使用者的裁定有兩層。2026-09-25（Clarity row 1）：不符規則的條目**不是拒絕、也不是同意後照寫，而是改成正確的再寫**——那 52 筆的正確寫法是不掛。2026-09-28（row 2–4 照提案）：規則型以 store 裡可檢查的資料界定（venue key，可加 type 集合與逐筆排除），外部來源 id 只記來歷；文件型的成員是一筆在庫文件的 `cites`；主題型的依據是使用者的選擇。

## 改了什麼

**資料**：`Library.membership`（`LibraryMembership`：`topic`／`rule(LibraryRule)`／`document(citekey:)`，sum type）。registry 檔多一個 `membership:` 區塊，closed shape：每種性質只收自己的鍵、kind 與 entry type 驗值域、key 文法驗、重複的 `types`／`excluded` 拒讀。缺席＝未標性質。

**store format 升到 21**（整合時改判）：實作時記的是「不 bump」——`membership` 是 registry 頂層的新鍵，舊 binary 走 tolerant-preserve 原樣保留。但保留不等於遵守：舊 binary 的 `library add` 不查規則，對規則型與文件型 library 照樣寫進不符的成員，而且不會出聲。`StoreVersion` 的判準表對這個形狀已經有兩個先例（format 5 的 `authorized`、format 18 的附加 Zotero 來源，都是頂層新鍵、都 bump），所以整合時照先例升到 21，這是 Claude 代裁，使用者可以翻：在 live store 的 marker 升上去之前，把 `supported` 改回 20、拿掉寫入閘即可。寫入閘（`LibraryStore.assertLibraryWritable`，門檻 `StoreVersion.libraryMembershipFormat`）只擋規則型與文件型；主題型不帶規則，舊 binary 的行為與新語意相同，不閘。

**判定只有一份**：`LibraryMembershipCheck`（AkashicCore）。規則型要一條指向規則 venue 的 `.key` 邊（只有未歸戶 literal 的，判「查不出」、指路 `resolve-venues`）、type 在集合內、不在排除清單；文件型要被文件的 `cites` 列到，文件不在庫或 citekey 重複就一律不符。CLI、MCP、App 三個寫入面與 `validate`、`library check`、`library list` 都問它。

**寫入面**（CLI `library` 與 MCP `akashic_libraries` 同一條 service 路徑）：

- `create` 要求 `--kind`／`kind`，規則指涉的 venue 或文件要在庫。
- 新增 `set-kind`（標既有 library 的性質與規則，唯一改寫 registry 檔的路徑 `LibraryStore.updateLibrary`）。現有成員不符新規則時列出來，**不自動移除**。
- 新增 `check`（唯讀，列出不符規則的成員與原因）。CLI 不截；MCP 受 `candidateByteBudget`，以 `total`／`truncated` 揭露。
- `add` 對規則型與文件型逐筆比對：符合的寫、不符的不寫並說原因（`skipped`），回報帶依據（`basis`）。**未標性質的 library 拒絕 add、零寫入**。remove 不查依據。CLI 全部不符時非零結束；MCP 照常回成功，由呼叫端讀 `written`／`skipped`。
- `list` 帶性質、規則與不符數（CLI 每個 library 多印一行依據）。
- App 的加入動作走同一份判定；選單標出性質（主題型／規則型／文件型／未標性質）。

**看得見既有的錯誤**：`Library.validate()` 對未標性質報 per-record warning；跨記錄 warning 報規則指向不在庫的 venue、文件不在庫或 citekey 重複、以及不符規則的既有成員（每個 library 一則，點名前 5 筆，指路 `library check`）。warning 不是 error：成員關係錯了不毀資料，error 會擋下不相干的改名與合併。

**新的關係邊**：規則的 venue、排除清單與文件是 `entity-backlink-completeness` 的第 16 條邊（`Library.membership`，正典側是 library）。規則不隨改名與合併遷移，所以 `rename` 對被規則指涉的 citekey、work 合併對被指涉的被併者、venue 合併對被規則以 venue 界定的被併者一律拒絕、零寫入，訊息指路 `library set-kind`。

## 測試與負控

新增 `LibraryMembershipRuleTests`（10）、`LibraryMembershipStoreTests`（8）、`LibraryMembershipServiceTests`（10），`CLIIntegrationTests` 加 4 支、`AppLibraryMembershipTests` 加 2 支。既有測試裡建 library 的地方補上 `kind: topic`；`RefuseIfNewerGateTests` 那支補上 `--kind topic`，否則它會因為缺 `--kind` 而通過、測不到 marker 閘。

負控 12 組，反向編輯後各自轉紅、還原後 `cmp` 相同：拿掉排除清單的比對、拿掉 type 比對、add 不跳過不符的、拿掉未標性質的拒絕、create 不要求 kind、拿掉跨記錄 warning、拿掉 rename／work 合併／venue 合併的守衛、拿掉 membership 的未知鍵拒讀、App 不比對、CLI 全部不符時不非零結束。

## 規則與文件

`mcp-cli-parity`（`akashic_libraries` 列）、`two-kinds-of-edits`（`library add` 列改寫、加 `library set-kind` 列：程式編輯）、`entity-backlink-completeness`（第 16 條邊、不得儲存兩項）、`WriteGateRulings`（`library set-kind` 不閘、`library check` 不寫）、`BacklinkRatchetData`、`docs/store-format.md` §2.9、`plugin/rules/source-of-truth-over-consent.md` 的誠實邊界、`akashic-venue-works` 的匯入序（目錄 library 改成規則型、排在 `resolve-venues` 之後建與掛）、README。

## 誠實邊界

- **部署之後，live store 的 4 個 library 全部是未標性質**（2026-09-29 讀取量測），`library add` 對它們一律拒絕，直到有人 `set-kind`。標成規則型或文件型要先把 marker 升到 21（CLI、akashic-mcp、App 全部升級之後）；主題型不需要。Psychological Methods 目錄可以直接標成規則型（`--venue psychological-methods --type periodical-article`，1,344 筆成員全部符合）。另外三個依描述是文件型，但它們的文件不在庫，標不上文件型；要先建那筆文件，或由使用者決定性質。
- 工具只比對，不判定：venue 沒歸戶的作品判「查不出」而不寫；文件自己沒登記 `cites` 的，判不是成員。
- 目錄完整性（符合規則卻不是成員的作品）不在本次的檢查裡。live store 有 8 筆 Psychological Methods 的 periodical-article 不在目錄裡。
- `excluded` 只做排除，不做「額外收錄」。提案寫的是「逐筆明列的例外」，這裡依描述「附錄等依裁決排除」讀成排除方向，並把欄位命名成 `excluded` 讓方向寫在資料裡。
- `akashic-work-references` 的 D5（往回追怎麼掛 library）要改成讀 `kind` 而不是讀描述，那個目錄由另一個工作線持有，這次沒有動。
