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
- **記錄路徑只有一份**：`LibraryStore.recordDivergence` 多一個 `against snapshot:` 版本，檢查（參數、候選存在、既有判斷不得被靜默抹掉）與寫入（`writeDivergence`、`DivergenceYAML`）與原本那一個相同，差別只在 store 現況由呼叫端給——原本那一個每一筆都整庫 load 一次（`akashic-merge-twins` 記的 CLI record 約 1.4 秒／組）。原本的入口改成 load 之後呼叫它。
- **寫進的 question** 只寫共用的 DOI 與「DOI 相等只是提名、判定走 resolve-divergence」，**不寫 citekey**：合併與改名會改寫候選的 key，question 不跟著改。
- **寫不進去的**（legacy 佈局、store format < 5）報 `failed` 與原因，不改變匯入的成敗——兩筆都已照建，`akashic validate` 的跨記錄 DOI 警告照樣報這一對。
- **報告**：`ImportReport.doiNominations`（`DOINomination`：`created`、`other`、`dois`、`status`、`divergenceID`、`error`；status 封閉四值 `recorded`／`alreadyRecorded`／`unlocatable`／`failed`）。
  - MCP `akashic_import_zotero`：鍵 `doiNominations`，每列 `{created, other, dois, status, divergence, error}`，只在非空時出現。`recorded`／`alreadyRecorded` 兩種列受 `listLimit`（20）——那兩種的歧異記錄在 store 裡、`akashic_divergences` 列得出來；`unlocatable`／`failed` 不截（沒寫進去、原因只在這份報告，同失敗清單）。`listTotals` 永遠有這一格（全部列數），被截時進 `truncatedLists`。工具描述加一句。
  - CLI `import-zotero`：一段標題加逐行 `⊕`（記了）／`=`（已有記錄）／`⚠`（無法唯一定位）／`✗`（寫不進去），全列。
- 規則與文件：`two-kinds-of-edits` 的 `import-wos`／`import-zotero` 列（程式寫的提名，種類不變）與 `record-divergence` 列；`mcp-cli-parity` 的 `akashic_import_zotero` 列；`akashic-merge-twins` 的提名一節；`plugin/CHANGELOG.md`。
- `zero-instance-guards` 不加列：這一輪沒有新增 validator 的檢查或 warning。

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
- **一個 DOI 被很多筆共用時**：一對一筆，新建 k 筆 × 既有 m 筆共用同一個 DOI 會寫 k×m ＋ C(k,2) 筆記錄。live store 的 16 個共用組全部恰好 2 筆（暫存副本上 `akashic validate` 的 16 則警告都是「被 2 筆 work 共用」），沒有設上限。
- 寫不進去的提名不讓 CLI 以非零結束：匯入自己的寫入都成功了，提名是建議性的，而 legacy 佈局的 store 每一趟新建攣生都會撞到它——把它當失敗會讓那種 store 的每一次匯入都失敗。
