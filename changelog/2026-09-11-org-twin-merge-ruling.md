# organization 的攣生合併：裁決「暫不做」，與把那個裁決寫對（#555）

## 半吊子：記得起來、解不掉

`recordDivergence` 的 `byShape` 收 organization，`resolveDivergence` 對它擲 `unsupportedShape`。#553 把 venue 從同一個狀態救出來時在
`byShape` 的註解裡具名了 org 這一格，而具名之後沒開 issue——下一個讀到那句話的人會以為它已經有人管。#555 立案時量了雙重零實例
（13 筆 org、寬鬆共鍵的重複群 0、含 org 候選的 divergence 0）。

使用者 2026-09-11 拍板：**暫不做——既不實作也不拿掉**，寫成 `zero-instance-guards` 第 24 列附觸發條件（`e7bd950`）。

## R1 verify：裁決沒被推翻，寫下它的散文八處被打到

六席齊、42 列（8 HIGH／14 MEDIUM／9 LOW／11 INFO），FAIL。六席都確認裁決、四條理由、量測值與兩條觸發條件自 `e7bd950` 至 HEAD 逐位元組未變
（#558 對尾句的改寫只動了實作補齊清單）。HIGH 全在寫下裁決的那份散文與規則檔的結構：

- 前言封閉三類、明文禁止類推第四類，而第 24 列的對象（一條已存在的半吊子管線）不屬任一類、diff 沒擴前言（四席各報一次）。
- 用來建立獨特性的那句「前二十三列都是寫或不寫」對第 22 列（裁決「保留」）為假——表格與 bullet 兩處。
- 「留著的代價是零」漏了 issue 自己寫的那項成本：記了第一筆 org divergence 沒有面刪得掉。
- 量測段首句「三個數字都要為零、任一非零即重開」與腳本印的四個數、與觸發條件矛盾——照字面當天就該重開。
- 與第 8 列劃界的「不取決於任何程式」為假：零由 #548 的 `pendingResolution` 扣留與 CJK key 缺口按住，而第 8 列的釘零義務本列沒做。
- 覆寫 #555 `## Expected` 與 #553「不得停在半吊子」沒寫在列內（DA 修正：覆寫在 Key Decisions 有記錄、Expected 依 idd-update 契約不改，殘餘是列內要說）。

## R2：兩個裁決，其餘逐句改真

**D89**（Claude 代裁，使用者可翻）：前言顯式擴入第 4 類「既有的半吊子路徑」——記錄面收、處理面擲、當下零筆走進去——並寫出它的失敗意義
（使用者撞牆、或被當成待修殘留而被人動手）。「不適用於移除」那句得到一個具名例外：第 4 類的裁決可以是「什麼都不動」，那同時裁了不新增與
不拿掉；「拿掉」那一半**不**路由到 `no-compat-fallback`——它管的是同一語意的兩條讀法，`byShape` 收 org 是尚未實作的正面能力、不是相容路徑；
它第 2 條要量的「還有誰在走這條路」正是第 24 列的觸發條件之二。

**D90**：觸發條件之一由工具出聲——`StoreHealth.unmergeableDivergences`：歧異記錄的候選 shape 不在 `DivergenceResolveError.mergeableShapes`
即 warning（一筆記錄一則，doctor／App 各一格、CLI 一行）。第 16 列的紀律：散文觸發條件沒有機制會叫醒任何人；R1 之前第一筆 org divergence
在三個面上與一筆正常待判的 person 歧異長得完全一樣（R1 verify 第 13 列）。重複群那一條仍是散文腳本，bootstrap 的扣留是它在寫入端的閘。

其餘：理由欄改成「前二十三列裡只有第 22 列同樣是不動既有的東西」並寫出兩者對象與失敗的差別；「代價不是零」（記了就刪不掉，#586 開）；
「拿掉」的真實代價換上去（關掉記錄面＝一組真的 org 攣生在合併面落地之前只能留在人的腦裡，#71 的病；venue 在 #553 之前正是這個姿態）；
覆寫 `## Expected` 與 #553 那句的事實寫在列內、覆寫者具名；零的三個來源具名並釘住（`OrgBootstrapResolveTests.testLooseKeyCollisionWithExistingOrgRoutesToPendingResolution`）；
量測段首句改成「兩個數字要為零，另兩個是脈絡」、腳本改 yaml 解析（頂層鍵判 shape、`candidates[].shape`、`.YAML` 也算、值一律 `str()`）、
註明鏡射 `LooseTitleKey.key` 並附固定案例、附真 binary 對帳與 bootstrap 重跑指令；`Organization.swift:84-88` 改引符號；`mergeableShapes` 加
`org-merge-slot` 標記（grep 從 5 變 6）、兩個 throw 入口刻意不標並寫明理由；`byShape` 的註解與 `entity-backlink-completeness` 第 9 條邊各補指標；
bullet 具名兩個「最像」的軸；「沒有重複可合」對三機構黏一格的那筆（#443 的形）結構上看不到，寫成誠實邊界。

**不做**：`parking-lot` label 或 `### Blocking`（R1 verify DA 第 19 列）——#555 以「已裁決」關閉，不是在等；重開條件之一自此由 `StoreHealth`
出聲，比三個散文位置都強。使用者可翻。

R2 的負控（各自重編、跑對應測試、還原後逐位元組比對）：

| mutation | 預期紅的測試 | 結果 |
|---|---|---|
| 掃描拿掉（`unmergeableDivergenceIssues` 不掛進 perRecord） | `UnmergeableDivergenceScanTests.testOrganizationCandidateIsReported` | 紅（0 ≠ 1） |
| 掃描的值域改成手寫 `["person","work","venue","organization"]` | 同上 | 紅（0 ≠ 1） |
| `OrgBootstrap` 的寬鬆扣留拿掉（`looseIndex` 命中不扣） | `OrgBootstrapResolveTests.testLooseKeyCollisionWithExistingOrgRoutesToPendingResolution` | 紅（三個異寫全部建成第二筆） |
| doctor payload 少那一族 | `StoreHealthSurfaceTests.testEveryFamilyAccessorIsConsumedByDoctorAndTheApp` | 紅 |

前兩個 mutation 第一次跑被 harness 記成 NO-RUN：斷言先紅（0 ≠ 1），測試接著 `got[0]` 越界 crash、整個 test process 沒印
`Executed`。修在測試側（`guard let first = got.first else { return }`）——crash 與紅在 harness 上分不開，而 crash 會把同
process 的其他測試一起帶走。全套 2,859 綠、`run-guards.sh` 綠。**E2E（真 binary）**：兩筆 org ＋ 一筆 org 歧異記錄 → `validate`
一則 per-record warning（指向第 24 列與 #586）＋ 家族計數行；`resolve-divergence --dry-run` 仍以 `unsupportedShape` 的誠實訊息拒絕
（裁決不變）；live store 副本 0 則；第 24 列的量測腳本重跑 13／0／0／3；`bootstrap-organizations` 的實際輸出與理由欄的措辭一致。
CLI `doctor` 只印跨記錄問題、家族計數行住在 `validate`（既有慣例，六族同形）。
