# 2026-09-30 trigger-coverage 看得見宣告範圍裡不受保護的檔；census-parity 涵蓋整個 Sources/（#690）

#690 問的是：`akashic-guards network-confinement`（#664）掃整個 `Sources/`，而唯一跑守衛的 CI workflow（`census-parity.yml`）只在 `Sources/` 的幾個子路徑改動時觸發。先量，再讓 `trigger-coverage` 說出真實狀態；擴大 macOS runner 的觸發面是計費決定，交給使用者裁決。使用者選 A，`census-parity.yml` 的 `paths` 加 `Sources/**`（見文末〈裁決落地〉）。下面兩節〈改了什麼〉〈負對照〉寫的是裁決之前的狀態（清單兩條），保留原文。

## 量到的東西（2026-09-30）

1. **`ci.yml` 會被 `Sources/**` 的改動觸發，但不跑守衛。** 它的觸發是 push to main 加 `paths-ignore`（`**.md`、`plugin/**`、`plugins/**`、`.claude-plugin/**`、`.claude/**`），所以改任何 `Sources/` 下的 `.swift` 都會跑它；它的步驟是 build、`swift test`、Tractatus、AkashicApp、`load.sql` 端對端，沒有 `run-guards.sh`，也沒有直接呼叫 `network-confinement`。`Tests/` 裡也沒有任何測試執行這支守衛。它沒有 `pull_request` 觸發。
2. **`census-parity.yml` 是唯一跑 `run-guards.sh` 的 workflow。** 它的 `paths:` 在 `Sources/` 底下只列 `AkashicStoreIO/StoreVersion.swift`、`akashic-guards/**`、`AkashicCore/Venue.swift`、`akashic-mcp/Server.swift`、`akashic/*.swift`、`AkashicCore/*.swift`。
3. **`trigger-coverage` 知道宣告，但只在受保護集合裡用它。** `network-confinement` 宣告 `reads Sources/*/*.swift`（`fnmatch` 不帶 `FNM_PATHNAME`，`*` 跨目錄，等於整個 `Sources/`）。`declared()` 最後一步是 `PROTECTED.filter { globMatch($0, pat) }`，所以只算到 34 個受保護的 `Sources/` 檔；逐對表對它們全部報「CI 未覆蓋 0」，最後印「無缺口」。另外 190 個不受保護的檔不在任何一張表裡。
4. **同一個形狀有兩支守衛**：`zero-instance-rows-audit` 也宣告 `reads Sources/*/*.swift`（它在 `Sources/` 裡找裁決表列號的實作）。
5. **缺口大小**：`Sources/*/*.swift` 224 個檔，受保護 34、不受保護 190；190 個裡 CI 觸發涵蓋 75、**不涵蓋 115**。115 個分布在 18 個 target，其中 6 個在 `Sources/AkashicS2/`（`network-confinement` 本來就跳過那個目錄，對它不是缺口；對 `zero-instance-rows-audit` 仍是）。

## 改了什麼

`trigger-coverage` 多一段「宣告範圍裡不在受保護集合的檔」：把每條宣告展開成磁碟上的檔，對不受保護的那些逐檔問逐對表問的同一個問題（有沒有一個 workflow 在它改動時觸發、而且執行這支守衛）。

- 缺口在 `acknowledgedCIGaps`（封閉列舉，兩條，都附 #690）裡的，印在「已知缺口」段（`⊘`），不計入 rc；結尾那句不再說「無缺口」，改說「沒有未列管的缺口（已知缺口 2 條見上）」。
- 不在清單裡的同類缺口是缺口（rc=1）。
- 清單裡的某一條已經沒有缺口（例如 `paths:` 補上了 `Sources/**`）也是缺口：要人把那一條拿掉。
- 解析不到任何受保護檔、或第一段是萬用字元的宣告，上面本來就報缺口，這一段不重複報。

## 負對照

`TriggerCoverageMutationsData.swift` 加兩格：

- 替 `PluginStoreFormatParity.swift` 注入 `reads Sources/*/*.swift`——範圍裡有 CI 不跑它的檔、它不在清單 → 必須紅並指名它。
- 在 `census-parity.yml` 的 `paths:` 加 `Sources/**`——兩條已知缺口都消失、清單卻還在 → 必須紅（兩條「已經沒有缺口」）。

既有一格（「宣告用中間萬用字元，痕跡走回 `Sources`」）原本注入 `Sources/*/*.swift`，新檢查會對它多報一條真的缺口；改注入 `Sources/*/Venue.swift`，要驗的東西（dirname 仍是 `Sources/*`）不變。39/39。

另在暫存目錄以 `swiftc` 各編一支弄壞的守衛：拿掉整段範圍檢查（基準就紅，因為兩條已知缺口對不到而報「已經沒有缺口」）、拿掉「清單過期」檢查（第二格回到 rc=0）、把所有缺口都當成已列管（第一格回到 rc=0）。

## 裁決之前：觸發範圍留給使用者

第一輪沒有改觸發範圍，三個選項與代價寫在 #690 的回報裡。裁決後的處置見下一節。

## 裁決落地：`census-parity.yml` 涵蓋整個 `Sources/`（2026-09-30）

使用者選 A：`census-parity.yml` 的 `paths` 加 `Sources/**`。另外兩個方案沒選：只靠 pre-push；在 `ci.yml` 加守衛步驟。

- **已知缺口清單清空**：上面兩條已知缺口隨之消失，`acknowledgedCIGaps` 清空。清單本身留著：日後出現有 issue 追蹤、暫時補不了的缺口時才加一條，缺口消失時那一條要拿掉，否則過期檢查會出聲。
- **`trigger-coverage` 實測**：「觸發點覆蓋無缺口」，rc=0。
- **負控調整**：`trigger-coverage-mutations` 有兩格改了寫法。
  - 「宣告範圍裡有 CI 不跑的不受保護檔」：要造出缺口得同時拿掉 `Sources/**`，另外兩支讀整個 `Sources/` 的守衛一併列為預期訊息。
  - 原本那一格「已知缺口已經不在、清單那一條卻沒拿掉」：改成「拿掉 `Sources/**` 之後，讀整個 `Sources/` 的兩支守衛必須直接失敗」。
  - 結果 39/39。
- **反向編輯負控**：把兩條 #690 豁免加回清單，守衛的 baseline 直接變紅（過期豁免檢查報「已經沒有缺口」）；還原後 39/39。
- **代價**：改 `Sources/` 的 push 會多跑一個 macOS job（10× 計費），依近 30 天的 commit 估，每月至多約 23 次。CI 目前帳務擱置，實際成本在帳務恢復後才會發生。（R1 verify 更正：這個數重算不出來，「至多」也不成立，見下節。）

## R1 verify 修正（2026-09-30）

六席（requirements、logic、security、regression、devil's advocate、Codex）。與本 issue 有關的有兩個 MEDIUM、十個 LOW；Codex 對 #690 沒有報告。

### 宣告範圍檢查的兩個判斷補上負控

裁決 A 之後改寫的兩格都靠拿掉 `Sources/**` 讓 paths 不成立，只釘住 paths 比對。DA 席實測：把「workflow 有跑這支守衛」改成恆真，或拿掉 `paths-ignore` 的判斷，`trigger-coverage-mutations` 仍 39/39；在暫存目錄新增一個 `paths: Sources/**` 卻只跑 `echo` 的 workflow，突變版報「無缺口」，把缺口藏起來。加兩格：

- `ci.yml` 的 paths 加 `Sources/**`（它不跑守衛）、`census-parity.yml` 拿掉 `Sources/**` → 仍是缺口。
- `census-parity.yml` 加一條 `paths-ignore: Sources/AkashicS2/**` → 那一片改動時守衛不跑，是缺口。

### 已知缺口清單改成資料檔

使用者 2026-09-30 裁決：機制留著、清單清空。但清單是編譯期常數時，harness 改的是 copy 裡的檔、改不到 binary，「已知缺口」（`⊘`，rc=0）與「列了卻已經沒有缺口」兩條分支沒有任何格子走得到（requirements、logic、regression 三席）。改成 `.githooks/acknowledged-ci-gaps.txt`：一行一條，守衛檔、宣告的樣式、`#<issue>`，TAB 分隔；`#` 開頭的行與空行略過；格式不對的行是缺口。檔案只有檔頭註解。它進了受保護清單（`trigger-coverage` 讀它），棘輪以 `protected-ratchet --accept` 更新為 61 條。

三格：清單有一條而缺口已經不在（過期，rc=1）；拿掉 `Sources/**` 並把兩支守衛列進清單（rc=0，兩條 `⊘`，沒有缺口、沒有警告）；清單有一行少一欄（rc=1）。`TriggerCoverageMutations.swift` 為第二格加一種預期（`isKnownGap`）。44/44。

`TriggerCoverage.swift` 的 doc comment 仍寫「封閉列舉，只有這兩條」「由 #690 裁決」，與空清單矛盾；已知缺口的訊息寫死「待裁決」。兩處都改成描述現況（「有 issue 追蹤」）。`zero-instance-guards` 加第 70 列記這個保留的決定。

### 反向編輯

在暫存目錄複製 `Sources/akashic-guards/`、改 `TriggerCoverage.swift` 一處、以 `swiftc` 編成另一支 binary，對一份複製的 repo 跑 `trigger-coverage-mutations`（工作樹不動）。五個 mutant：「workflow 有跑守衛」恆真、不看 `paths-ignore`、不檢查過期、忽略清單、格式不對的行不報。每一個都只讓它對應的那一格失敗（43/44）。

### 代價的說法

「依近 30 天 commit 估每月至多約 23 次」重算不出來（requirements、regression、DA、security 四席）：觸發以 push 與 PR 更新計，不以 commit 計；`pull_request` 用同一份 paths anchor，只算 push 也漏了 PR。改成可重跑的參考量，不宣稱上界：

2026-08-31 到 2026-09-30（臺北時間），`cbc7d400` 以前 558 個 commit 裡，碰 `Sources/` 的 325 個、分布 25 天；其中舊 paths（加 `Sources/**` 之前的那十四條）一條都沒碰到的 56 個、分布 12 天——這些 commit 在裁決 A 之前不會觸發這個 workflow。它不是上界，也不是嚴格的下界：多天的 commit 可以合成一次 push，一天也可以 push 多次，PR 的每次更新另算。

```bash
TZ=Asia/Taipei git log cbc7d400 --since=2026-08-31T00:00:00+08:00 --until=2026-09-30T23:59:59+08:00 \
  --date=format-local:%Y-%m-%d --format=@%ad --name-only
# 以 @ 開頭的是日期行，其餘是那個 commit 動到的檔。逐 commit 判斷「有沒有 Sources/ 的檔」與「有沒有檔符合舊 paths」
# （GitHub 的語意：`**` 跨目錄、`*` 不跨 `/`），再數相異的日期。
```

`census-parity.yml` 的註解與 `CLAUDE.md` 的 CI 成本段同步改寫，`CLAUDE.md` 的觸發點表與「第四維」那一列補上 `Sources/**`。workflow 檔頭「範圍刻意窄」那一句標明只描述 #407 當時。

### 另外

- 「宣告用中間萬用字元」那一格原本注入 `Sources/*/*.swift`，第一輪因為新檢查會多報一條缺口而換成 `Sources/*/Venue.swift`。裁決 A 之後那個理由不在了（regression 席實測改回去只剩預期的警告），改回真守衛用的形式。
- `026e3c03`（本 issue 裁決落地的 commit）同時帶了 `plugin/CHANGELOG.md` 裡 #608、#694、#696 的一段（`akashic_import_zotero` 的回應形狀改變），與 #690 無關。內容本身對；歷史不改寫，記在這裡，追 #696 時從這一行找得到。
- 不修：security 席建議把 actions 改用 SHA 釘住、檢查 fork PR 的核准設定。那是既有狀態，不在 #690 的範圍；`permissions: contents: read`、`persist-credentials: false`、沒有 `secrets`、沒有 `pull_request_target` 已確認。
