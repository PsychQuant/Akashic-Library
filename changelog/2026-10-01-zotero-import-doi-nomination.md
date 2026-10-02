# 2026-10-01 Zotero 匯入新建的條目與另一筆共用 DOI 時照建，並記一筆歧異提名（#611）

使用者 2026-10-01 裁決：「照建，並自動記一筆歧異提名」。#605 讓同一篇作品在另一個 library 以**同一個 zotero key** 出現時掛成附加來源；key 不同、只有 DOI 相同時，匯入照常新建一筆，攣生要等 `akashic validate` 的跨記錄 DOI 警告或人工攣生合併才被看見。現在新建之後當場寫一筆 work 形狀、**沒有判斷**的歧異記錄，交給既有的攣生合併流程（`resolve-divergence`、`akashic-merge-twins`）判定。

DOI 相等只當提名、不當同一性證據：勘誤與原文共用 DOI，一筆作品也可以有多個 DOI（#394，`identity-is-judged-not-matched`「識別碼終結指涉，不終結描述」）。所以匯入不合併、不掛附加來源、不填 judgement／prefers。

## 改了什麼

- **`DOITwinNomination`**（新檔 `Sources/AkashicZoteroImport/DOINomination.swift`）：在一趟匯入的**所有寫入完成之後**，對這一趟新建且寫入成功的每一筆，找出與它共用 DOI 的其他 work（`canonicalDOIs` 的 `DOI.normalized`，與 `crossRecordIssues` 的 DOI 重複檢查、`create-entry` 的 #637 命中同一個正規形），**一對寫一筆**歧異記錄。比對的是寫完之後的狀態：pull 這一趟改了既有那筆的 DOI、同一趟新建兩筆同 DOI 的，都看得到，與 Zotero 條目的處理順序無關。
- **一對一筆，不是一個 DOI 一筆**（選擇與理由）：
  1. `resolve-divergence` 把候選中 survivor 以外的**全部**併進 survivor。一組「新建的 N＋既有的 A、B」裡若 A 是 N 的攣生、B 是勘誤，那一筆無法正確消解，只能放棄再手記。一對一筆時各自判定；合併 (N, A) 之後，`resolveDivergence` 會把 (N, B) 遷移成 (A, B)。
  2. 匯入只帶來「新建的 N 與既有的某筆」的新資訊。既有的 A、B 之間共用 DOI 早就在庫裡（`validate` 已經報），把它們綁進同一組是替匯入沒發現的事下提名。
  3. 身分穩定：一對的 UUID（`DeterministicUUID.forDivergence`）只取決於這兩個 citekey。一組的 UUID 會隨「有幾筆共用這個 DOI」改變，之後再多一筆就生出一個更大的新記錄。
- **冪等**：只在新建時觸發——再匯入不新建就不提名，所以被 `dismiss-divergence` 放棄的一對不會被下一趟重記。新建時已有一筆 work 歧異記錄的候選同時含這兩筆（同一組，或**更大的一組**）時報 `alreadyRecorded`、指向那一筆、不重寫（重寫會換掉 question，而那筆記錄可能已經帶著人補上的判斷）。**更小的一組不存在**：一對已是最小的候選組。實際會碰到同一組的情形是新建的那一筆被刪掉後重建（citekey 相同）。
- **無法唯一定位的候選不點名**：另一筆的 citekey 在 `unlocatableCitekeys` 裡（citekey 重複、與另一筆共用 id、檔案寫入時會被拒），或這一趟寫入後留下 legacy 拷貝（#705），那一對報 `unlocatable`、不寫。歧異記錄以 citekey 指涉候選，指不到唯一一筆的 key 會讓合併猜。
- **記錄路徑只有一份**：`LibraryStore.recordDivergence` 多一個 ~~`against snapshot:`~~（R1 verify 起收 `DivergenceCandidatePool`，見文末）版本，檢查（參數、候選存在、既有判斷不得被靜默抹掉）與寫入（`writeDivergence`、`DivergenceYAML`）與原本那一個相同，差別只在 store 現況由呼叫端給——原本那一個每一筆都整庫 load 一次（`akashic-merge-twins` 記的 CLI record 約 1.4 秒／組）。原本的入口改成 load 之後呼叫它。
- **寫進的 question** 只寫共用的 DOI 與「DOI 相等只是提名、判定走 resolve-divergence」，**不寫 citekey**：合併與改名會改寫候選的 key，question 不跟著改。
- **寫不進去的**（legacy 佈局、store format < 5）報 `failed` 與原因，不改變匯入的成敗——兩筆都已照建，`akashic validate` 的跨記錄 DOI 警告照樣報這一對。
- **報告**：`ImportReport.doiNominations`（`DOINomination`：`created`、`other`、`dois`、`status`、`divergenceID`、`error`；status ~~封閉四值 `recorded`／`alreadyRecorded`／`unlocatable`／`failed`~~ → 封閉五值，R1 verify 加 `groupTooLarge`，見文末）。
  - MCP `akashic_import_zotero`：鍵 `doiNominations`，每列 `{created, other, dois, status, divergence, error}`，只在非空時出現。~~`recorded`／`alreadyRecorded` 兩種列受 `listLimit`（20）——那兩種的歧異記錄在 store 裡、`akashic_divergences` 列得出來；`unlocatable`／`failed` 不截（沒寫進去、原因只在這份報告，同失敗清單）。~~ → 兩種列各自受 `listLimit`（R1 verify，見文末）。`listTotals` 永遠有這一格（全部列數），被截時進 `truncatedLists`。工具描述加一句。
  - CLI `import-zotero`：一段標題加逐行 `⊕`（記了）／`=`（已有記錄）／`⚠`（無法唯一定位）／`✗`（寫不進去），全列。
- 規則與文件：`two-kinds-of-edits` 的 `import-wos`／`import-zotero` 列（程式寫的提名，種類不變）與 `record-divergence` 列；`mcp-cli-parity` 的 `akashic_import_zotero` 列；`akashic-merge-twins` 的提名一節；`plugin/CHANGELOG.md`。
- ~~`zero-instance-guards` 不加列：這一輪沒有新增 validator 的檢查或 warning。~~ → R1 的 `groupTooLarge` 上限與同 id 不同候選的拒絕是零實例的守衛，R2 verify（2026-10-02）補了第 80、81 列（見 `2026-10-02-r2-fixes-611-692-693-708.md`）。

## 量測

**tools/list**（真 binary，stdio 送 initialize ＋ tools/list、量回應那一行的位元組）：51,997 → **52,376** bytes，預算 54,000。

**live store（唯讀）**：以 YAML 解析 `~/.akashic/entities/*.yaml`，DOI 以 `DOI.init` 的前綴剝除與小寫正規化，只數 work、以主來源的 `library_id` 分 library。重跑腳本：

```bash
python3 - <<'EOF'
import glob, io, os, yaml, collections, itertools
root = os.path.expanduser('~/.akashic/entities')
PREFIXES = ["https://doi.org/", "http://doi.org/", "https://dx.doi.org/", "http://dx.doi.org/", "doi:", "DOI:"]
def norm(raw):
    s = str(raw).strip()
    for p in PREFIXES:
        if s.startswith(p): s = s[len(p):]; break
    s = s.lower()
    return s if s.startswith('10.') and '/' in s else None
works = []; bad = 0
for f in glob.glob(root + '/*.yaml'):
    try: d = yaml.safe_load(io.open(f, encoding='utf8'))
    except Exception: bad += 1; continue
    if not isinstance(d, dict): bad += 1; continue
    if 'work' not in d: continue
    dois = [x.get('value') if isinstance(x, dict) else x for x in (d.get('doi') or [])]
    if not dois and isinstance(d.get('fields'), dict) and d['fields'].get('doi'):
        dois = [d['fields']['doi']]
    prov = d.get('provenance') if isinstance(d.get('provenance'), dict) else None
    works.append((str(d.get('citekey')), {n for n in map(norm, dois) if n}, prov is not None, prov.get('library_id') if prov else None))
by = collections.defaultdict(list)
for w in works:
    for x in w[1]: by[x].append(w)
shared = {k: v for k, v in by.items() if len({w[0] for w in v}) > 1}
cross = [v for v in shared.values() if len({w[3] for w in v if w[2] and w[3] is not None}) > 1]
pairs = sum(1 for v in shared.values() for a, b in itertools.combinations(v, 2)
            if a[2] and b[2] and None not in (a[3], b[3]) and a[3] != b[3])
print(f"work {len(works)}｜DOI 被 ≥2 筆 work 共用的組 {len(shared)}｜主來源跨不同 Zotero library 的組 {len(cross)}（配對 {pairs}）｜讀不到的檔 {bad}")
EOF
```

2026-10-01：work 2,575｜DOI 被 ≥2 筆 work 共用的組 **16**｜其中主來源跨不同 Zotero library 的組 **10**（配對 10）｜讀不到的檔 0。

對照：把 `entities/`、`libraries/` 與 `store.yaml` 複製到暫存目錄（live store 不動），以這一輪的 binary 跑 `akashic validate`，「DOI「…」被 N 筆 work 共用」的跨記錄警告 16 則，與腳本的 16 組一致。

**這 10 對不會被這一輪提名**：它們是先前的匯入建的，而提名只在新建時觸發。它們照舊由 `akashic validate` 的跨記錄 DOI 警告與 `akashic-merge-twins` 的聯集提名看得到。

## 測試

- `ZoteroDOINominationTests`（11 支，真 importer）：跨 library 同 DOI 照建並記一筆（兩筆都在、既有那一筆一個位元組不動、沒有附加來源、記錄沒有判斷、id 是那一對的決定性 id）；再匯入不再提名、記錄位元組不變；刪掉後重建遇到既有記錄報 `alreadyRecorded`、不重寫；涵蓋判準（同一組優先於更大的一組、別的形狀不算）；同一趟新建兩筆只記一次；勘誤與原文共用 DOI 只提名；citekey 重複的既有那一筆報 `unlocatable`、不進候選，同 DOI 另一筆可定位的照常記；沒有 DOI／DOI 不同什麼都不記；多個 DOI 的既有那一筆以共用的那一個配對；比的是這一趟寫完的 DOI；legacy 佈局寫不進去報 `failed`、匯入照建。
- `ImportZoteroReportSurfaceTests`：payload 只截在 store 裡的兩種列、另兩種全列，`listTotals` 與 `truncatedLists` 揭露；服務層 payload 的那一列指向真的寫進 store 的記錄。既有的 #696 清單測試改成涵蓋 `cappedRowLists`（`doiNominations`），`testEveryReportCollectionIsCappedOrNamed` 照舊要求每個集合欄位不是有上限就是具名理由。
- `ZoteroReportCLITests`（真 binary）：CLI 印出 `⊕` 那一行、`akashic divergences` 列得出那筆記錄；citekey 重複的那一筆印 `⚠`、不點名。
- `ToolPayloadScenarios` 加 `akashic_import_zotero`／`doi nomination` 情境，`ToolPayloadNestedPaths` 加 `doiNominations[]` 一列（#700 的封閉表）：守衛在那一層取到 `created`、`divergence`、`dois`、`other`、`status` 五個鍵，都在工具描述裡。

## 負控

反向編輯、`cmp` 對照改前的副本確認還原；每一輪先 `swift build` 再跑三組測試（`ZoteroDOINominationTests|ImportZoteroReportSurfaceTests|ZoteroReportCLITests`，每輪 Executed 46 tests）。

| # | 變異 | 結果 |
|---|---|---|
| M1 | 不寫記錄（只在記憶體組一筆 `Divergence`） | 紅：17 個斷言、9 支 |
| M2 | 整個提名拿掉（`doiNominations = []`） | 紅：22 個斷言、12 支 |
| M3 | 不查既有涵蓋的記錄 | 紅：1（重建那一支——報成 `recorded`） |
| M4 | 不查無法唯一定位 | 紅：3 個斷言、2 支（importer 與 CLI 各一） |
| M5 | 記錄路徑拿到的現況不含這一趟新建的 | 紅：17 個斷言、9 支（新建的候選「不存在」→ 每一對都 `failed`） |
| M6 | 比對用載入時的 DOI、不用寫完的 | 紅：1（pull 改了 DOI 那一支） |
| M7 | 上限的母體改成全部列（`inStore = nominations`） | **存活**——輸出端的篩選本來就放行 unlocatable／failed，只改母體不改輸出；這個變異沒有打到要測的性質，改用 M7b |
| M7b | 輸出端只留上限內的列（unlocatable／failed 一起被截掉） | 紅：3 個斷言、1 支（初版那一支在列數不對時越界、讓測試行程崩潰，改成先守列數） |
| M8 | CLI 不印提名那一段 | 紅：3 個斷言、2 支（真 binary） |

## 誠實邊界

- **只在新建時觸發**：live store 裡既有的 10 對跨 library 攣生不會被這一輪提名；pull 讓一筆**既有**的 work 改成與另一筆共用 DOI 時也不提名（兩者都不是新建）。這兩種仍靠 `validate` 的跨記錄 DOI 警告與 `akashic-merge-twins`。
- **「這一趟寫入後留下 legacy 拷貝」那一類不點名**沒有專屬測試：要造出那個狀態得讓 legacy 檔刪不掉（#705 的測試用唯讀目錄），這一輪沒有做；拿掉那一類的變異不會讓任何測試紅。
- **`error` 鍵沒有情境產生**：payload 守衛在 `doiNominations[]` 那一層只看得到情境產生的五個鍵，`error` 寫進了描述但守衛看不到它被拿掉（與 #700 記的 `items[].partial` 同形）。
- ~~**一個 DOI 被很多筆共用時**：一對一筆，新建 k 筆 × 既有 m 筆共用同一個 DOI 會寫 k×m ＋ C(k,2) 筆記錄。live store 的 16 個共用組全部恰好 2 筆（暫存副本上 `akashic validate` 的 16 則警告都是「被 2 筆 work 共用」），沒有設上限。~~ → R1 verify 設了上限：超過 10 筆的 DOI 一對都不記（見文末）。
- ~~寫不進去的提名不讓 CLI 以非零結束：匯入自己的寫入都成功了，提名是建議性的，而 legacy 佈局的 store 每一趟新建攣生都會撞到它——把它當失敗會讓那種 store 的每一次匯入都失敗。~~ → R1 verify 反轉：沒記下來的提名讓 CLI 以非零結束（見文末，含這條舊理由為什麼不成立）。

## R1 verify 之後（2026-10-01）

六席驗證（本輪與 #708、#692、#693 同一次，全輪 56 則）對本張的裁決：MEDIUM 2（第 1、5 則）進修正輪，LOW 一起處理。

| # | 問題 | 處置 |
|---|---|---|
| 1、21 | `coveringRecord` 的「同一組」分支只比 id、不看形狀。歧異記錄的 id 只雜湊候選 key，person 的 `{a, b}` 與 work 的 `{a, b}` 是同一個檔，別種形狀的記錄被當成「已涵蓋這一對 work」，提名靜默消失 | 涵蓋判斷改成 `WorkDivergenceIndex`，**只有 work 形狀的記錄算涵蓋**（同一組與更大的一組都一樣）。id 被別種形狀占用時這一對不算涵蓋；接著寫的時候**記錄路徑拒絕覆寫**（`recordDivergence` 比同一個 id 既有記錄的候選 `(shape, key)`，不同就擲 `destinationHoldsAnotherRecord`），報 `failed`、原因說出兩邊的形狀，原記錄位元組不動。這個拒絕在記錄路徑本身，所以 `record-divergence`／`akashic_record_divergence` 同樣受益（先前互相覆寫、不出聲） |
| 5、10、30、35 | 一對一筆沒有上限：k 筆共用同一個 DOI 寫 C(k,2) 筆記錄，時間超過二次方（DA 實測）；MCP 的 unlocatable／failed 列不截 | 見下方「數字」。一個 DOI 被**超過 10 筆** work 共用（這一趟新建的加上其餘的）時**一對都不記**，改報一列 `groupTooLarge`（一個 DOI 一列、`dois` 是那個 DOI、`groupSize` 是共用的 work 數、`created` 是這一趟新建的 citekey 最小的一筆、沒有 `other`）。沒有新建的 work 的組不觸發（既有的過大群組不會每次匯入都被重報）；一對同時共用另一個沒超過門檻的 DOI 時仍由那個 DOI 提名。涵蓋判斷的索引與候選存在的 key 集合各**建一次**（`WorkDivergenceIndex`、`DivergenceCandidatePool`），不再每一對掃全部歧異記錄、也不再每一筆把四個形狀的 key 集合重建一遍。MCP 的兩種列各自受 `listLimit`：在 store 裡的（recorded／alreadyRecorded）與沒記下來的（unlocatable／failed／groupTooLarge），`listTotals` 仍是全部列數 |
| 9 | 提名失敗或因 unlocatable 略過之後，重新匯入不會再提名（只在新建時觸發），結束碼與摘要都看不出來 | CLI：摘要行說出「有 N 列提名沒有記下來」、提名只在新建時觸發、重新匯入不會再提名、手記用 `record-divergence`，並**以非零結束**（與 `writeFailed` 同一條慣例，在 index rebuild 之後）。MCP：payload 多 `doiNominationsUnrecorded`（沒記下來的列數，永遠完整、非零才出現）。「沒記下來」是三種狀態：`unlocatable`、`failed`、`groupTooLarge`。**首版那條理由（legacy 佈局每一趟新建攣生都會撞到 failed，非零會讓那種 store 的每一次匯入都失敗）為何不成立**：legacy 佈局的 store 寫不了歧異記錄本身就是要人處理的狀態（`migrate`），每一次匯入都報它是對的；而 unlocatable 是 store 裡有重複 citekey 之類的問題，一樣要人處理。MCP 面不以錯誤結束，由呼叫端讀 `doiNominationsUnrecorded`（有記錄的兩面差異，見 `mcp-cli-parity`） |
| 25、31 | `recordDivergence(against:)` 的 doc 要求「snapshot 必須是磁碟現況」，唯一的呼叫端給的卻是記憶體內重組的快照；匯入期間別的程序補上的判斷會被無判斷的重錄抹掉 | 採「寫入當下重新讀磁碟」，不靠 doc 約束：`against:` 改收 `DivergenceCandidatePool`（**只管「候選存在」**），同一組候選的既有記錄一律由 `divergenceOnDisk(id:)` 讀磁碟上那一個檔（一次單檔讀取，與候選數無關），既有判斷與 prefers 的兩道保護與上面的形狀檢查都讀它。也消掉第 31 則另提的「`checkDivergenceArguments` 跑兩次」：兩個入口各跑一次、共同本體（`recordCheckedDivergence`）不重跑。代價：別的程序在匯入期間補上判斷時，這一對報 `failed`（原因是「這組候選已有判斷…無判斷的重呼叫不得靜默抹掉它」），而不是 `alreadyRecorded`——保守、不丟資料；窗口只有匯入的持續時間 |
| 8 | `docs/store-format.md` §2.5 沒有新行為與新鍵 | 補上：新建之後記提名、只在新建時觸發、`doiNominations` 五個 status、`doiNominationsUnrecorded`、沒記下來的處置（§2.5 那一條 bullet） |

其餘同步更新：`mcp-cli-parity` 的 `akashic_import_zotero` 列（舊句劃掉、指向新句）、`two-kinds-of-edits` 的 import 列、`akashic-merge-twins` 的提名一節（沒記下來的三種與手記的指令）、`plugin/CHANGELOG.md` 的 #611 條目。MCP 工具描述改寫那一句：`tools/list` 53,403 → **53,772** bytes（真 binary 量，預算 54,000；53,403 是 7de07935 的基線，先前寫的 52,376 是 #611 首版當時、之後別的工作加了描述）。

### 數字（實測：`import-zotero` 真 binary，AKASHIC_HOME 沙箱、假 zotero.sqlite，debug build）

同一份腳本產生 zotero.sqlite（`GROUPS` 個 DOI、每個被 `SIZE` 筆 item 共用，一趟全部新建），兩個 binary 各跑：基線是 7de07935 的 `akashic`，修後是這個 commit。秒數是 debug 版牆鐘，只作量級參考。

| 情境 | 基線 | 修後 |
|---|---|---|
| 1 個 DOI × 10 筆 | 45 筆記錄、0.14 秒 | 45 筆記錄、0.15 秒（門檻上，行為不變） |
| 1 個 DOI × 20 筆 | 190 筆記錄、0.46 秒 | 0 筆記錄（`groupTooLarge`）、0.12 秒、rc 1 |
| 1 個 DOI × 40 筆 | 780 筆、1.70 秒 | 0 筆、0.15 秒 |
| 1 個 DOI × 50 筆 | 1,225 筆、2.73 秒 | 0 筆、0.17 秒 |
| 1 個 DOI × 80 筆 | 3,160 筆、10.90 秒 | 0 筆、0.25 秒 |
| 2,000 個 DOI × 各 2 筆（正常規模、近線性） | 2,000 筆、20.5 秒（兩次 20.46／20.67） | 2,000 筆、12.4 秒（兩次 12.26／12.59） |
| 200 個 DOI × 各 10 筆（都在門檻內） | 9,000 筆、78.3 秒 | 9,000 筆、17.2 秒 |

門檻內的情境快了 1.7 到 4.5 倍，那是索引（涵蓋判斷不再掃全部既有記錄、不再每對建 `Set`）與候選 key 集合只建一次的效果；剩下的時間主要是每筆一次 `atomicWrite`。

重跑（`mkzotero.py OUT GROUPS SIZE`；schema 是 `ZoteroFixture` 的最小集合加 title 與 DOI 兩個欄位）：

```python
"""mkzotero.py OUT GROUPS SIZE : GROUPS distinct DOIs, each shared by SIZE journalArticle items (all new on first import)."""
import sqlite3, sys, os
out, groups, size = sys.argv[1], int(sys.argv[2]), int(sys.argv[3])
if os.path.exists(out): os.remove(out)
db = sqlite3.connect(out)
for sql in [
    "CREATE TABLE itemTypes(itemTypeID INTEGER PRIMARY KEY, typeName TEXT)",
    "CREATE TABLE items(itemID INTEGER PRIMARY KEY, itemTypeID INT, key TEXT, version INT, libraryID INT)",
    "CREATE TABLE fields(fieldID INTEGER PRIMARY KEY, fieldName TEXT)",
    "CREATE TABLE itemDataValues(valueID INTEGER PRIMARY KEY, value TEXT)",
    "CREATE TABLE itemData(itemID INT, fieldID INT, valueID INT)",
    "CREATE TABLE creators(creatorID INTEGER PRIMARY KEY, firstName TEXT, lastName TEXT, fieldMode INT)",
    "CREATE TABLE creatorTypes(creatorTypeID INTEGER PRIMARY KEY, creatorType TEXT)",
    "CREATE TABLE itemCreators(itemID INT, creatorID INT, creatorTypeID INT, orderIndex INT)",
    "CREATE TABLE itemTypeCreatorTypes(itemTypeID INT, creatorTypeID INT, primaryField INT)",
    "CREATE TABLE deletedItems(itemID INT)",
    "CREATE TABLE itemAttachments(itemID INT, parentItemID INT, path TEXT, contentType TEXT)",
    "CREATE TABLE tags(tagID INTEGER PRIMARY KEY, name TEXT)",
    "CREATE TABLE itemTags(itemID INT, tagID INT, type INT)",
]: db.execute(sql)
db.execute("INSERT INTO itemTypes VALUES (1,'journalArticle')")
db.execute("INSERT INTO creatorTypes VALUES (1,'author')")
db.execute("INSERT INTO itemTypeCreatorTypes VALUES (1,1,1)")
db.execute("INSERT INTO fields VALUES (1,'title')")
db.execute("INSERT INTO fields VALUES (6,'DOI')")
item = 0; val = 0
for g in range(groups):
    for c in range(size):
        item += 1; val += 1
        db.execute("INSERT INTO items VALUES (?,1,?,1,?)", (item, f"K{g:05d}X{c:03d}", 1 + (c % 4)))
        db.execute("INSERT INTO itemDataValues VALUES (?,?)", (val, f"Copy {c} of paper {g}"))
        db.execute("INSERT INTO itemData VALUES (?,1,?)", (item, val))
        val += 1
        db.execute("INSERT INTO itemDataValues VALUES (?,?)", (val, f"10.5555/bench.{g}"))
        db.execute("INSERT INTO itemData VALUES (?,6,?)", (item, val))
db.commit(); db.close()
print(f"{out}: {groups} groups x {size} items")
```

```bash
SANDBOX=$(mktemp -d); mkdir -p "$SANDBOX/home" "$SANDBOX/store"
python3 mkzotero.py "$SANDBOX/z.sqlite" 1 50
time AKASHIC_HOME="$SANDBOX/home" akashic import-zotero --zotero-db "$SANDBOX/z.sqlite" --library "$SANDBOX/store"
ls "$SANDBOX/store/entities" | wc -l    # 50 個 work ＋ 提名的記錄數
```

### 測試

`ZoteroDOINominationTests` 11 → 22 支：涵蓋判斷的同一組／更大一組／別種形狀（含「同一個 id、別種形狀」）、索引隨寫隨加；id 被 person 形狀占用時報 `failed`、原因說出兩邊形狀、原記錄位元組不動；記錄路徑拒絕覆寫別種形狀的記錄（`record-divergence` 同走）；pool 建好之後別的程序補上判斷，無判斷的重錄仍被擋；門檻值釘成字面 10；超過門檻一個 DOI 一列且一對都沒記、恰在門檻上仍逐對、同一趟新建很多筆也是一列、沒有新建的過大群組不報、只略過過大的那個 DOI、50 筆的群組不寫任何記錄。`ImportZoteroReportSurfaceTests`：兩種列各自受上限與總數、沒記下來的列單獨超過上限、`doiNominationsUnrecorded` 永遠完整且只在非零時出現、服務層 payload 說出來。`ZoteroReportCLITests`（真 binary）：`groupTooLarge` 時 CLI 印摘要行並以 1 結束、`created: 1` 照建、store 沒有提名。`ToolPayloadScenarios` 加 `doi nomination group too large` 情境，讓 `groupSize` 與 `doiNominationsUnrecorded` 進 payload 鍵守衛（工具描述都點名了）。

### 負控（反向編輯、`cmp` 對照改前副本確認還原；每輪先 `swift build --build-tests` 再跑 `ZoteroDOINominationTests|ImportZoteroReportSurfaceTests|ZoteroReportCLITests|ToolPayloadKeyGuard|ToolPayloadScenario`）

| # | 變異 | 結果 |
|---|---|---|
| M1 | 涵蓋判斷的「同一組」分支不看形狀 | 紅：2 支（涵蓋判斷的形狀矩陣、id 被 person 占用那一支） |
| M2 | 記錄路徑的「同一個 id 只能是同一組候選」守衛拿掉 | 紅：2 支（id 被占用那一支、`record-divergence` 拒絕覆寫那一支） |
| M3 | 門檻改成 30 | 紅：5 支（過大的群組不再報、同一趟很多筆、只略過過大的 DOI、CLI 非零、門檻值）。**第一版測試引用 `DOINomination.maxGroupSize` 算群組大小，門檻被改大時群組跟著變大、變異存活**，所以測試改成字面 10 |
| M4 | 既有記錄不讀磁碟（`existing = nil`） | 紅：3 支（id 被占用、pool 之後補上的判斷、拒絕覆寫） |
| M5 | CLI 不因沒記下來的提名而非零結束 | 紅：1 支（真 binary） |
| M6 | MCP 沒記下來的列不截 | 紅：2 支 |
| M7 | 不給 `doiNominationsUnrecorded` | 紅：3 支 |
| M9 | 逐對處理時不略過過大的 DOI | 紅：6 支 |
| M10 | 沒有新建的 work 的過大群組也報 | 紅：1 支 |
| M8 | 寫完一筆不把它加進索引（`covered.add(d)`） | **存活，而且是等價變異**：一趟之內寫的都是不同的一對（`seenPairs` 已去重），而一對的記錄只涵蓋它自己，所以後面的對用不到前面寫的。`add` 留著是讓索引不變式（載入的加上這一趟寫的）成立；索引型別的 `add` 由 `testIndexSeesRecordsAddedLater` 直接釘住 |

### 誠實邊界（本輪新增）

- **門檻 10 是一次裁量，不是量出來的**：live store 的 16 個共用組全部恰好 2 筆，所以沒有資料指出一個「自然」的切點；10 筆（45 對）取的是「遠離現實、又擋得住批次貼入與概念 DOI」。要改值只有一處（`DOINomination.maxGroupSize`），測試釘住字面值。
- **`groupTooLarge` 只報 DOI 與共用數，不列成員**：要看哪幾筆共用，用 `akashic validate` 的跨記錄 DOI 警告；這一列刻意不列成員（一個 10 筆以上的清單進報告沒有資訊量）。
- **別的程序在匯入期間補上判斷時報 `failed` 而非 `alreadyRecorded`**：見第 25／31 則的代價。
- **MCP 面不以錯誤結束**：呼叫端若不讀 `doiNominationsUnrecorded`，仍看不見那幾對；MCP 的先例（`writeFailed` 也不讓呼叫失敗）同。
- **`recordDivergence(…against:)` 的簽章改了**（`LibraryLoad` → `DivergenceCandidatePool`）：那個多載是 #611 首版才有，全樹唯一的呼叫端是 `DOITwinNomination`，沒有其他呼叫端要遷移。
