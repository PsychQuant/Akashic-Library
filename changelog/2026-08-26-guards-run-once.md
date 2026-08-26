# 守衛從跑兩遍變成跑一遍，而代價寫在註解裡

2026-08-26，#432。

## 量到的

| | 先前 | 現在 |
|---|---|---|
| `PrePushHookTests` | **4220 秒** | **0.365 秒** |
| 全套 `swift test` | **3358 秒** | **187 秒** |
| 守衛清單 | hook 與 CI **各一份**（各列 21 支）| **一份**（`.githooks/run-guards.sh`）|
| CI step 數 | 17 | 1 |

`PrePushHookTests` 會在測試裡跑一次 hook，而那次會**重跑整批守衛**；外層 hook
兩分鐘後跑同一批、讀同一個工作樹、得同一個結果。內層那次的覆蓋是外層的真子集。

它斷言的是「`GIT_*` 有沒有被清乾淨」與「swift 有沒有帶 `-Xswiftc -warnings-as-errors`」
—— **兩者都在前兩階段**。hook 因此收一個 `AKASHIC_PRE_PUSH_STAGES`（預設跑全部，
正常 `git push` 行為不變），測試設 `build,test`。

## 實際成本比估計高，而高在 meta 守衛

我以為要改 hook ＋ CI ＋ 測試三個檔案。實際上還要改**兩支「檢查守衛有沒有被接上」
的守衛** —— 它們對「守衛住在哪個檔案」有寫死的假設。每修一輪露出下一層：

| 輪 | 症狀 |
|---|---|
| 1 | `trigger-coverage` 掃 pre-push → **21 缺口** |
| 2 | 修了 hook 側 → CI 側仍 **90 缺口** |
| 3 | 修了兩側 → mutation 的**注入目標脫節** |
| 4 | 修了目標 → **注入不再是外科手術式的** |

**第 2 輪最值得記**：`HOOK` 用純子字串比對（串接文字有效），而 workflow 那側用
`invoked()` 解析 YAML 的 `run:` 行（串接進去的裸 shell 命令它看不見）。
**同一個 indirection、兩種讀法，我只改對一種** —— 而 `pre-push 21/21 綠` 讓我以為好了。
是 `tail -2` 只讓我看到最後兩條，實際 90 條。

## 取捨：CI 側的負控從「具名」降為「類別」

CI 只剩一個 step，所以**任何針對它的注入都是全有全無**。那些負控的期望因此從
「具名某一支」改成「每一條缺口都是 CI 涵蓋缺口」。

`case()` 仍要求**每條缺口同類**，所以鑑別力不歸零 —— 但它**不再能證明「是 X 那一支
掉了」**。先前「一支守衛從 CI 掉了」與「整個守衛階段掉了」是兩種可分辨的故障。

**不拆回去換鑑別力**：那會回到兩份會分岔的清單，而**分岔是安靜的、鑑別力降級是寫在
註解裡看得見的**。兩害相權選看得見的那個。

（hook 側不受影響 —— 從 `run-guards.sh` 拿掉一支仍精確報出是哪一支，實測「缺口 1 條」。）

## 一個附帶發現

合併之後 `plugin-guards.yml` 的 `plugin/**` 涵蓋了 `census-parity.yml` 原本承擔的
資料依賴，於是「從 census 的 paths 拿掉一行」**不再產生缺口**（實測 rc=0）。
那不是 harness 壞了，是**一個 workflow 涵蓋了另一個的角色**。

## 驗證

```
PrePushHookTests                 ✓ 0.365 秒
swift test                       ✓ 2224 tests, 0 failures, 187 秒
trigger-coverage.py              ✓ 零缺口（pre-push 21/21）
trigger-coverage-mutations.py    ✓ 32/32 negative control
```
