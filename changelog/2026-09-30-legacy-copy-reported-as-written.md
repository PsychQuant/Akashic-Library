# 2026-09-30 寫了、但搬移後的 legacy 拷貝沒刪掉的那一筆，各寫入者統一記在成功那一側（#705）

`LibraryStore.writeEntry`／`writePerson` 寫一筆既有記錄時，#631 會把舊佈局的 `entries/<citekey>.yaml`／`people/<key>.yaml` 搬進 `entities/`：先寫新檔、**之後**刪舊檔。舊檔刪不掉時新內容已經寫進去了，同一筆記錄留下兩份。#702 R1 讓這一刻改擲 `StoreIOError.legacyCopyNotRemoved`（訊息以「已寫入」開頭），但各寫入者的處置不一致：

- import-zotero：同時列在成功清單（作者保留／覆寫、拿掉的欄位）與 `writeFailed`。
- 逐筆收容寫入失敗的寫入者（resolve-people 的 apply／reject、enrich、enrich-from-zotero、library add／remove、resolve-organizations 的 CLI apply、copy-zotero-attachments、migrate-provenance）：只算失敗。開工前實測 resolve-people apply：`writeFailed 1 筆`、`本批已改寫 0 檔`，而作者位已在 `entities/` 歸戶。
- 沒有收容的寫入者（tag／link／set-status、update-person、update-entry、resolve-venues、judge／refute、split／un-split／drop／attribute-org、import-wos、rename、rename-person、resolve-divergence、migrate-identifiers、authorize-names……）：整個操作以錯誤結束，同一批後面的記錄沒寫。resolve-venues apply 在寫完 entry 之後、寫 venue verdict 之前擲錯——作者邊升格了、verdict 沒落地。

使用者 2026-09-30 裁決 (a)：這一筆記在**成功那一側**另開的欄位 `writtenWithLegacyCopy`，不算失敗、不進任何失敗清單，全部寫入者統一。

## 改了什麼

**機制（`AkashicStoreIO/LegacyCopyLedger.swift`）**：一個收集範圍 `LegacyCopyLedger.collecting { … }`（task-local）。`writeEntry`／`writePerson` 刪不掉搬移來源時：

- 範圍內 → 記下一筆 `LegacyCopyLeft`（kind、key、id、legacyFile、detail）、照常回傳——它寫了，呼叫端照寫入成功處理（計數、清單、後續的 verdict）。
- 範圍外 → 照舊擲 `legacyCopyNotRemoved`。預設是擲：沒有人收集的地方不會安靜吞掉它。

巢狀時最內層收下；內層的 body 擲錯時它沒有報告可以放，收到的轉交外層、回傳空陣列——每一筆恰好在一個地方被報告。

**範圍開在回報面，封閉列舉**：

| 範圍 | 放在哪 |
|---|---|
| MCP 工具分派（`Server.swift` 的 `handleToolCall`） | 成功的 JSON 物件加鍵 `writtenWithLegacyCopy`（每筆 `{kind, key, written, legacyFile, detail}`，不截）；錯誤回應在訊息末附同一份人可讀報告 |
| CLI 進入點（`AkashicCLI.main`） | 命令結束後（擲錯也是）印在輸出末尾、錯誤訊息之前 |
| 直接印 service JSON 的 CLI 寫入命令（update-person、update-entry、tag、link、set-status、resolve-venues、enrich 的 `--json`） | 鍵進那份 JSON，stdout 仍是一份 JSON；擲錯時轉交進入點 |
| `ZoteroImporter.run` | 新欄位 `ImportReport.writtenWithLegacyCopy`；MCP payload 只在非空時帶出、不截；CLI 印在 index rebuild 之前 |

放在分派層與進入點而不是逐寫入者：新的寫入工具或命令不必記得接它。兩面的人可讀報告是同一個 `LegacyCopyLeft.reportLines`，一句描述與範圍外擲出的 `legacyCopyNotRemoved` 同一份。

**其餘同步**：import-zotero 拿掉 #702 的特例（`guardedWrite` 回到單一 `catch`），CLI 那一行的標題回到「已略過續跑」；13 個會寫既有 work／person 的 MCP 工具說明加同一句（`Server.swift` 的 `legacyCopyNote`）；`mcp-cli-parity` 的 13 列各加 #705 註記、表下加一段；`plugin/CHANGELOG.md`；`ToolPayloadKeyGuardTests` 的誠實邊界補這個鍵。

## 各寫入者（`writeEntry(`／`writePerson(` 的呼叫點，逐一 grep 列出）

| 寫入者 | 面 | 現在怎麼報 |
|---|---|---|
| `setMembership` | MCP libraries add／remove、CLI library add／remove | 範圍內寫入成功（不進 `writeFailures`）；MCP 加鍵、CLI 末尾 |
| `writeAndReindex`（setStatus／tag／link） | MCP set_status／tag／link、CLI 同名 | 寫了；rebuild 撞重複時錯誤訊息附報告（MCP）／錯誤之前印（CLI） |
| resolvePeople 的 apply／reject（逐筆收容）、judge／refute、`UndecidedVerdicts`、split／un-split／drop／attribute-org | MCP resolve_people、CLI resolve-people | 不進 `writeFailed`／`confirmWriteFailed`／`rejectWriteFailed`；同上 |
| enrich（逐筆收容）、enrichFromZotero（逐筆收容） | MCP enrich／enrich_from_zotero、CLI enrich（`--json` 進 JSON）、CLI enrich-from-zotero（自己的收容迴圈） | 不進 `writeFailed`／`failed`；同上 |
| `ZoteroImporter.guardedWrite` | MCP import_zotero、CLI import-zotero | 自己的範圍：`ImportReport.writtenWithLegacyCopy`，不進 `writeFailed` |
| `WoSImport.run` | MCP import_wos、CLI import-wos | 寫完整批；分派／進入點報 |
| resolveVenues 的 apply／repoint／demote、`VenueEdgeRemoval` | MCP resolve_venues、CLI resolve-venues（進 JSON） | 寫完整批（先前 apply 在 venue verdict 之前中止）；同上 |
| resolveOrganizations 的 apply、`OrgJudgedVerdicts` | MCP resolve_organizations、CLI resolve-organizations（apply 是 CLI 自己的收容迴圈） | 不進 `failed`；同上 |
| `UpdatePerson.updatePerson` | MCP update_person、CLI update-person（進 JSON） | person 的兩份不擋 index 重建，回成功、帶鍵 |
| `EntryUpdate` 四條腿 | MCP update_entry、CLI update-entry（進 JSON） | 同上（work：rebuild 撞重複時錯誤附報告） |
| `ZoteroAttachmentCopy.storeOne`（逐筆收容） | CLI copy-zotero-attachments | 不進失敗清單；CLI 末尾 |
| `renameEntry`、`renamePerson`、`DivergenceResolve`（三處）、`ProvenanceMigration`（逐筆收容）、`IdentifierMigration`、`AuthorizedNameMigration`、`BootstrapPeople` | CLI rename、rename-person、resolve-divergence、migrate-provenance、migrate-identifiers、authorize-names、bootstrap-people | CLI 末尾（rename、rename-person 這一格在本節寫下時為假，R1 verify 起才成立——見文末〈R1 verify 之後〉） |
| `addPerson`、`createEntries`（`writeEntryExclusive`） | MCP add_person／create_entry | 新記錄、沒有 legacy 可搬——碰不到這一格 |
| App：`AppState.mutate`、`Adjudication` 三處、`AppState.rename` | App | **不變**：沒有開範圍，照舊擲「已寫入……」。App 的單筆編輯沒有報告可以放（**#708 起不成立**：App 在各寫入點開範圍，動作算成功、要清的 legacy 檔列在側欄的非阻斷提示，見 `2026-10-01-app-legacy-copy-notice.md`） |

## 測試與負控

新測試（先紅後綠——開工前全部 RED：範圍內照樣擲錯、payload 沒有鍵、CLI stdout 不是 JSON、import-zotero 的 `writeFailed` 帶著「已寫入」）：

- `LegacyCopyLedgerTests`（這一段的 7 支；下一節另加 2 支）：範圍外照舊擲；範圍結束後不殘留；範圍內 work 與 person 都記下、照常回傳、內容在 `entities/`、legacy 還在；訊息具名；巢狀時最內層收下；內層擲錯時轉交外層。
- `ZoteroImportReportAfterWriteTests.testWriteThatLandsBeforeLegacyRemovalFailsIsReportedAsWritten` 改寫：不在 `writeFailed`，在 `writtenWithLegacyCopy`。
- `WrittenWithLegacyCopyTests`（9 支）：回應形狀（加鍵、原樣、錯誤附記、非物件附記、消毒、import payload）；以分派的順序重演 update_person（成功回應帶鍵）、resolve_people apply（錯誤訊息 `writeFailed 0 筆`）、enrich（`本趟已落地 1 筆`、沒有 `writeFailed`）。
- `StdioE2ETests`（真 binary，3 支）：update_person 成功回應帶鍵、tag 之後 rebuild 失敗時錯誤文字附報告、13 個工具的說明都提到這個鍵。
- `LegacyCopyCLITests`（真 binary，3 支）與 `ZoteroReportCLITests.testImportPrintsTheLegacyCopyLeftOnTheSuccessSide`：update-person 的 stdout 仍是 JSON 且帶鍵；tag 失敗仍印報告；enrich 文字輸出末尾有報告、沒有 writeFailed；import-zotero 印在成功那一側、沒有 write failed。

刪不掉的造法同 #702：legacy 檔受 git 追蹤、乾淨，所在目錄設成唯讀。以 root 執行、權限擋不住刪檔時 skip。

負控（反向編輯一行 → 跑相關測試 → 從位元組備份還原、`cmp` 確認）：

| # | 反向編輯 | 紅的測試 |
|---|---|---|
| NC1 | `removeMovedLegacy` 拿掉「範圍內記下、照常回傳」那一行（一律擲） | 14 支：`LegacyCopyLedgerTests` 5 支、`WrittenWithLegacyCopyTests` 3 支（三個寫入者的流程）、e2e 2 支、CLI 3 支、import-zotero 的 KitTests 1 支 |
| NC2 | `ZoteroImporter.run` 不把收到的放進報告 | import-zotero 的 KitTests 與 CLI 各 1 支 |
| NC3 | 工具分派不附（`return outcome`） | e2e 2 支（成功回應沒有鍵、錯誤文字沒有報告） |
| NC4 | CLI 進入點不印 | CLI 2 支（tag、enrich 文字輸出）；update-person 照綠——它的鍵在 JSON 裡，不靠進入點 |
| NC5 | 內層擲錯時不轉交外層 | `testAFailedInnerScopeHandsOffToTheOuter` 與 CLI tag 那支（`payload` 擲錯之後進入點收不到） |
| NC6 | `importReportPayload` 不帶鍵 | `testTheImportReportPayloadCarriesIt` |
| NC7 | `akashic_tag` 的說明拿掉那一句 | `testWriterToolDescriptionsNameWrittenWithLegacyCopy` |
| NC8 | CLI update-person 改回直接印 service JSON | `testUpdatePersonPutsItInTheJSONItPrints`（進入點的報告接在 JSON 後面，stdout 不再是一份 JSON） |
| NC9 | CLI import-zotero 不印報告的這一段 | `testImportPrintsTheLegacyCopyLeftOnTheSuccessSide` |

九格都紅，九格都以位元組備份還原、`cmp` 相同。

## 誠實邊界

- **work 的兩份會讓 index 重建失敗。** 兩份共用 citekey，`LibraryIndex.rebuild` 撞 `UNIQUE constraint failed: entries.citekey`。所以會在寫入後重建 index 的工具（多數）在這種狀態下回錯誤，`writtenWithLegacyCopy` 在錯誤訊息末（MCP）或錯誤之前（CLI）；成功回應帶鍵的只有不重建、或 person 那一格（index 的 people 表對重複 key 留第一筆，#670）。這是 store 的真實狀態——刪掉 legacy 那份之前 index 重建不了、load 把這筆記錄標成無法唯一定位——不是這一筆沒寫。讓 index 容忍這種兩份並存是另一個裁決（`doctor` 對重複 citekey 刻意不重建，#35／#138），不在這次範圍。
- **App 沒有開範圍。** 它的單筆編輯（狀態、標籤、library、關係、裁決台的三個動作、改名）照舊擲「已寫入……」的錯誤、不重讀 index。要改得先決定 App 在哪裡顯示「寫了但留下兩份」，不在這次範圍。（**#708 已處理**：使用者 2026-09-30 裁決動作算成功、另以非阻斷提示列出要清的檔，見 `2026-10-01-app-legacy-copy-notice.md`。）
- **範圍靠 task-local 傳遞。** 寫入若發生在另一個執行緒或 detached task（目前的寫入者都沒有），範圍收不到，照舊擲錯——大聲，不是靜默。
- **MCP 回應鍵守衛看不到它**：這個鍵只在 legacy 拷貝刪不掉時出現，情境造不出來；說明的涵蓋由 `testWriterToolDescriptionsNameWrittenWithLegacyCopy` 對一份手寫的 13 個工具名單檢查，新的寫入工具要記得加進名單。
- **tools/list 位元組**：13 句說明與 import_zotero 的「該步未寫入」讓回應從 50,233 變成 51,499 bytes（預算 52,000，#578），剩 501。
- **同一筆多步失敗的串接沒有專屬測試。** `ZoteroImporter` 的 `writeFailed` 對同一筆第二則不同的訊息改成以「；」附加、不覆寫（見下節）；相同的訊息不重複。目前沒有 fixture 能讓同一筆在同一趟出現兩則**不同**的失敗訊息——先前會的那一格（稍早寫了、之後被 #631 拒絕）現在由前置檢查接走——所以這一行是防禦性的，反向編輯它不會讓任何測試紅。

## #702 R2 verify 的 LOW（同一分支處理）

#702 第二輪審查在同一段程式碼上留了九則 LOW（7、8、9、15、16、19、20、22、26），併在這裡：

- **同一趟對同一筆寫兩次（15、19、20、26）**：import-zotero 的主來源、附加來源、orphan 標記可能在同一趟各寫一次同一筆。第一步寫了、legacy 刪不掉之後，第二步一定被 #631 拒絕（兩份並存），而 #702 讓那句拒絕蓋掉第一步的「已寫入」訊息——`orphanCleared` 說寫了、`writeFailed` 只說「兩份都在，拒絕寫入」。現在第一步在 `writtenWithLegacyCopy`；`guardedWrite` 在寫之前查這一趟的收集範圍（`LegacyCopyLedger.collected`），同一筆已經留下 legacy 拷貝就不再嘗試，`writeFailed` 記一則說出「這一趟稍早已寫入這一筆（見 writtenWithLegacyCopy）……這一步的改動沒有套用」；同一筆的多則訊息改成附加、不覆寫。新測試 `testASecondStepAfterALeftoverSaysTheFirstStepLanded`：legacy 文章帶 orphan 標記、Zotero 版本較新、`entries/` 唯讀——orphan 清除落地、更新沒有套用（作者沒被覆寫），`writeFailed` 以那句話開頭。
- **legacy 檔已經不在（8）**：`removeMovedLegacy` 先前對任何刪除失敗都說「同一筆記錄現在有兩份」，包括別的程序先刪掉了的那一種。現在只有「沒有這個檔」（`NSFileNoSuchFileError`／`ENOENT`）這一種錯誤碼算成功——搬移要的終態就是它不在；權限擋住的照舊。新測試 `testALegacyFileThatIsAlreadyGoneIsNotALeftover` 也確認權限擋住的錯誤不被誤認。
- **writePerson 那一半沒有測試（9、16）**：新增 `testOutsideAnyScopeThePersonWriteStillThrows`（範圍外擲 `legacyCopyNotRemoved`、描述以「已寫入 entities/<id>.yaml」開頭、點名 `people/<key>.yaml`、內容已落地）；work 那一格補上同樣的描述斷言。範圍內兩格原本就有。
- **import_zotero 的說明（7、22）**：`writeFailed` 那一句加「該步未寫入」，寫了的那一筆由 `writtenWithLegacyCopy` 那一句說明（13 個工具共用）。`AkashicService.importReportCappedLists` 的註解改說「沒寫進去的那一步」，並列出 `writtenWithLegacyCopy`。

負控：

| # | 反向編輯 | 紅的測試 |
|---|---|---|
| NC10 | `guardedWrite` 的前置檢查永遠不成立 | `testASecondStepAfterALeftoverSaysTheFirstStepLanded`（訊息回到「同一筆記錄有兩份……拒絕寫入」） |
| NC11 | 拿掉「已經不在就算成功」那一格 | `testALegacyFileThatIsAlreadyGoneIsNotALeftover` |
| NC12 | `writePerson` 改回直接 `removeItem` | person 的兩支（範圍內、範圍外） |

三格都紅，都以位元組備份還原、`cmp` 相同。

守衛面跟著改的測試表（全套測試第一次跑紅的七則，都是新程式碼碰到既有守衛）：`GitSpawnHygieneTests` 的封閉清單加兩個 CLI 測試檔；`ImportZoteroReportSurfaceTests` 的 `uncappedCollections` 具名 `writtenWithLegacyCopy` 不截的理由、`fullReport` 填它；`SanitizationBoundaryTests` 的 Error → 文字入口表跟著 `recordWriteFailure` 改寫；`Server.swift` 的型別完整分支不做 Error → 文字轉換；擲出端 `legacyCopyNotRemoved` 的 detail 在擲出站點逃脫；`reportLines` 的豁免具名 `$0.message`。

## R1 verify 之後

第一輪驗證的處置與負控詳見 `2026-09-30-b22-r1-fixes-705-695.md`。摘要：

- **rename、rename-person 其實沒有涵蓋（兩席 MEDIUM，DA 以真 binary 重現）**：兩者寫完新鍵之後自己 `removeItem` 舊鍵的 legacy 檔，唯讀目錄讓改名以原始錯誤中止、引用沒改寫。上方寫入者表那一列與 `mcp-cli-parity` 的 #705 段對這兩個命令都是假的。現在走 `removeMovedLegacy`，改名做完、legacy 那份進報告；App 的改名照舊擲，但擲的是「已寫入……」（#708 起 App 的改名也在範圍裡，見上方表格那一列的註記）。
- **import 的 rebuild 失敗時報告被錯誤出口截掉（Codex MEDIUM）**：importer 收下的那幾筆改交給分派的範圍（`LegacyCopyLedger.handToEnclosingScope`），放在回應最前面、不截；嵌進錯誤的 payload 不再帶。真 binary 以三十二筆驗過。
- **錯誤回應把報告放在最前面**（上方〈誠實邊界〉第一條與 `plugin/CHANGELOG.md` 說的「附在訊息末」自此改成「放在最前面」）。讓 index 容忍兩份並存是另一個 issue。
- **成功回應已帶這個鍵時併進同一個陣列**（先前會把 JSON 變成 JSON 加文字）。
- **沒有外層範圍時，失敗不再帶走收到的那幾筆**：`ZoteroImporter.run` 與 `LegacyCopyReport.payload` 改經 `LegacyCopyLedger.get`，沒有外層時擲 `LegacyCopyLeftBeforeFailure`（帶著寫了的那幾筆與原本的錯誤）。
- 說明句名單（13 個工具）仍是手寫的：程式裡沒有「寫既有 work／person 的 MCP 工具」這個分類可以推導，理由在那份 changelog。
