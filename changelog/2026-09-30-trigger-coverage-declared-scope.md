# 2026-09-30 trigger-coverage 看得見宣告範圍裡不受保護的檔（#690，觸發範圍待裁決）

#690 問的是：`akashic-guards network-confinement`（#664）掃整個 `Sources/`，而唯一跑守衛的 CI workflow（`census-parity.yml`）只在 `Sources/` 的幾個子路徑改動時觸發。這一輪先量，再讓 `trigger-coverage` 說出真實狀態；**觸發範圍本身沒有改**——擴大 macOS runner 的觸發面是計費決定，留給使用者裁決。

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

## 沒有改的：觸發範圍

三個選項與代價寫在 #690 的回報裡，等使用者裁決。選定之後這一段的已知缺口清單跟著改：擴大觸發面時清單兩條要拿掉（守衛會提醒），決定只靠 pre-push 時把清單的理由從「待裁決」改成那個裁決。
