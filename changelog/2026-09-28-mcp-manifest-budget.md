# 2026-09-28 MCP 工具描述精簡、`tools/list` 設位元組預算（#578）

`tools/list` 的回應是每個 session、每個呼叫端都要付的固定成本。精簡前它是 **56,382 bytes**（32 個工具；量的是回應那一行的原始位元組，不含換行），比 repo 對單一 MCP 輸出設的 48 KiB（49,152）還大。描述裡累積了每一輪 verify 的裁決編號、R 輪次、issue 考古與理由段落。那些是寫給維護者看的，卻在每次呼叫時付給模型。

使用者 2026-09-27 裁決：先精簡描述，再設預算；預算＝精簡後實測 × 1.25、進位到下一個 1,000。

## 數字

| | 精簡前 | 精簡後 |
|---|---|---|
| `tools/list` 回應（bytes，不含換行） | 56,382 | 39,164（−30.5%） |
| `akashic_resolve_people` | 13,113 | 7,092 |
| `akashic_resolve_venues` | 7,011 | 4,182 |
| `akashic_update_venue` | 6,274 | 3,297 |
| `akashic_enrich` | 4,726 | 3,588 |
| `akashic_resolve_organizations` | 4,538 | 3,122 |
| `akashic_doctor` | 2,483 | 1,600 |

各工具的數字是單一工具物件序列化成 UTF-8 JSON 的位元組數（Python `json.dumps(ensure_ascii=False)`，含預設分隔空白）。前後用同一種量法，所以可以比；但各工具加總不等於回應那一行，回應那一行以測試量到的數字為準。

**預算**：39,164 × 1.25 = 48,955 → **49,000**。預算落在 48 KiB 之下，是因為精簡時刻意壓到 39,200 以下。超過 39,200，×1.25 再進位後的預算就會高過單一 MCP 輸出的上限，守衛等於允許工具清單長回 48 KiB 以上。

守衛是 `StdioE2ETests.testToolsListResponseStaysWithinByteBudget`。它 spawn 真的 `akashic-mcp`，依序送 initialize、notifications/initialized、tools/list，再量回應那一行的位元組。比預算之前，它先確認讀到的是 id 2、帶 `result.tools` 且清單非空；量錯一行（錯誤回應、別的 id）或清單是空的，都不算通過。

**negative control**：把預算改成 39,163（實測 − 1），測試失敗，訊息是「tools/list 回應 39164 bytes，超過預算 39163」，這也確認了測試量到的正是 39,164。以反向編輯改回 49,000 後重跑，通過。

## 拿掉的是什麼

- 裁決編號（D20、D23…D73）、R 輪次、verify 列號。
- issue 考古：「#471 修了 variant 那一半」「在此之前 authorized 沒有判定型寫入面」這類歷史。`judge`／`refute` 描述裡的 `#386`、`#648` 保留，因為 `JudgeReasonCapTests` 用它們定位參數字串。`library` 參數旁的 `#315` 在註解裡，不進 manifest。
- 理由段落：`drop_author` 的 APA7 §9.12 論證、`split_author` 為什麼收分隔符、`authorize` 與 #553 合併的關係、`add_variant` 的遷移史。
- 指路的建議（「出路是 drop_venue」「要留在 git 就寫進 commit message」）與重複的句子。各寫入腿的「單獨呼叫」改由工具描述說一次。
- resolve 三族、libraries、enrich_from_zotero 裡 `\(UnlocatableReason.work)`／`.person` 的內插改成「原因見 akashic validate」。那兩個字串本身就說 validate 會列出是哪一種。

## 契約細節移到哪裡

| 工具 | 從 MCP 描述拿掉的細節、完整版的位置 |
|---|---|
| `akashic_resolve_people` | CLI `akashic resolve-people --help`：judge 的寫入集合先驗與 8 MiB 上限、index 重建失敗時的回報、refute 的逐筆 person 先驗、篩選式 `--apply` 對淘汰所得與查過未決的排除、drop_author 記錄的 statement 形、reject 的「同 literal 他 entry 照提」 |
| `akashic_resolve_venues` | CLI `akashic resolve-venues --help` 的 abstract：同一 work 兩條拼法不同的邊時先到先寫、否決抑制以正規化 literal 為鍵、同一 literal 的另一個拼法也略過 |
| `akashic_resolve_organizations` | CLI `--undecided`／`--judge`／`--reject` 的 help：單筆 id 長度上限的公式、id 解析的例外、work 層級記錄的後果、verdictNotRecorded 的原因（原因本身也在 payload 裡）、拼法變體包含哪幾種 |
| `akashic_update_venue` | CLI `akashic update-venue --help` 與 docs/store-format.md §5.7：ZWJ／ZWNJ 的合法脈絡、canonical 的細節、四個名字回報桶與 authorize 各回報桶的意思 |
| `akashic_doctor` | CLI `akashic validate --help`（`--owner` 那段列出組合式六族、近重複的求值上限）、docs/store-format.md §3.5（duplicateVerdictRecords 不計的那一格） |
| `akashic_enrich` | CLI `akashic enrich --help`（`--from` 的欄位與 format 門檻；門檻也仍在 MCP 描述裡） |

## 刻意留著的（別處沒有）

- `resolve_people` 列表的全部頂層鍵、每列的欄位（tier 四層的意思、counts、eliminatedPairings、undecidedChecks、unlocatable 兩旗標）、people[ref] 的區辨欄位清單，以及四條上限（48 KB、50 筆、20 個 personRefs、60 筆／2 個異名）。CLI 沒有 `--json`，這些只在 MCP 面；`ServiceTests.testToolDescriptionCoversEveryTopLevelPayloadKey` 也要求頂層鍵出現在描述的前 3,000 字元內。
- 查過未決的配對以 id 點名時 apply 照寫；judge 的 rule 是 author-judged-per-work、同 literal 在他處會以 confirmed-elsewhere 提名；repoint 的例外（既有的重複邊與 venue 集合不相交的 move 不擋）；resolve_venues 對沿革各段都配對。這四句第一輪精簡時拿掉了，對照後發現 CLI help 與 §3.5 都沒有，改回精簡版。
- `confirm_tiers` 整句、`verdictsRetired` 截 20 筆（CLI 全列）、enrich 的 items 上限與 provenance 的四個鍵：都是 MCP 面獨有的契約。
- 每條寫入腿的輸入格式、拒絕類別（每類一個短句）、需要的 store format、呼叫端要讀的回應鍵。

## 合進 #670 之後

rebase 到 #670 之上時，resolve_venues／resolve_organizations 的描述補上 #670 新增的兩個列表旗標（`unlocatableVenueKey`、`unlocatableOrganizationKey`），reject／repoint／demote 的拒絕句改為含 venue。之後 `tools/list` 實測 39,286 bytes（多 122）。預算仍是 49,000：它由精簡當下的 39,164 算出，這 122 bytes 是預算允許的成長，不重算預算（重算會把 ×1.25 疊在已經長過的數字上，預算就會跟著描述一起長）。

## 規則

`mcp-cli-parity.md` 在 MCP 裁決表之後加一段：manifest 有預算、由哪支測試量、描述寫什麼；要調高預算，回 #578 重新裁決。
