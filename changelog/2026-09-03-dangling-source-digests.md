# 本機缺承重存檔進 `StoreHealth`（#453）

記錄的 provenance 指向一個本機 `sources/` **沒有**的 digest——person／organization／venue 的 `references`
（第 11 條邊三形）、divergence 的 `judgement.restsOn`（第 12 條）、entry 的 `akashic.sources`（#223）與
`references`（第 15 條，#394）——現在由 `LibraryStore.health(from:)` 掃出（`danglingSourceIssues(in:)`），
以 warning 級的 `OwnedIssue` 併入 `perRecordIssues`：CLI `validate` 逐行可見並加一行計數；MCP `akashic_doctor`
進 `recordIssues`（`prefix(20)` 截斷、`count` 送分母）並多一個 `danglingSources` 計數；**App 面未渲染
`perRecordIssues`**（#487 起 App 側欄「記錄」Section 渲染計數）。`StoreHealth.danglingSourcePrefix`／`danglingSources` 給三面單一定義
——與 #464 死 verdict 完全同形。

## 兩層盲區（都實測為真）

1. **`SourceStore.missingSourceDigests(_:)` 不掃 `load.venues`，也不掃 `Entry.references`。** #406 讓 venue 的
   `paginated` 判定帶 rests-on digest 之後，承重證據第一次住在 venue 記錄上；#394 §5 給 work 開了第 15 條邊。
   兩次都是「形狀新增了、掃描沒跟著補」——與 #416 第一版只寫三族、#394 補 venue 時「五族」沒跟著改，是同一個
   形狀（來源以函式主體為準，寫死的族數會漂）。
2. **它零 production 呼叫端。** doctor／`StoreHealth` 接的是 `auditSourceIndex()`，只比 blob↔index——一個捏造的
   （或沒同步的）digest 在 blob 與 index **兩邊都不在**，兩邊一致，audit 說「全部一致」。這是 `zero-instance-guards`
   第 3 列「未涵蓋不得冒充通過」的形：沒被檢查與檢查過且乾淨在輸出上相同。#251 形狀第三次。

## 形狀決定

- **不加 `StoreHealth` 新欄位，改成 per-record warning 進 `perRecordIssues`**——「哪一筆記錄的哪個 digest 本機缺」
  本來就是 per-record 事實；三個消費面已各自渲染 `perRecordIssues`（App 除外，見上）。
- **`missingSourceDigests` 改逐 holder 回傳**（`MissingSourceReport`：`holders` 帶 owner／kind／slot／digest；
  `missing` 維持既有語意——distinct digest、排序；`unreadableShards` 不動）。否則 warning 沒有 owner，落不進
  `OwnedIssue`。既有測試零改動。
- **用詞「本機缺」不寫「偽造」**：`sources/` 不進 git（`replace-endnote-and-zotero` 的承重閘——第三方版權 PDF
  住在那裡），本機分不出「從未存在」與「沒同步」。訊息說出這個邊界，處置寫成兩條（同步／確認）。
- **severity warning**：記錄合法可載入，缺的是位元組；error 會讓 `hasErrors` 翻紅、擋住 export 類流程，而其他
  clone 上「全部 dangling」是常態，不該是紅燈。
- **讀不到 ≠ 缺席**（#265）不動：shard 目錄存在但列不出來 → 不判缺席、不出 warning——那是 `auditSourceIndex`
  的 `unreadableShards` 在報的事。測試釘住。

## 量測

- 每次 `health(from:)` 多一輪 `fileExists`：distinct digest 數（live store 41）——微秒級，pre-push 全套時間差在雜訊內。
- live store（唯讀，2026-09-04）：62 個 digest 引用、41 個 distinct `sha256:`；**本機缺 1 筆**，而那一筆是
  divergence `B354B9E9…` 的 `judgement.restsOn` 裝了 `https://doi.org/10.1038/s41586-025-09680-x`——**不是 digest**。
  這是掃描第一次跑就抓到的真實形狀：`Judgement.restsOn` 的寫入閘與 decode 沒有 `isValidDigest` 檢查
  （`ProvenanceReference` 的 `restsOn` 有），URL 就這樣進了 store。訊息因此分兩種：合法但本機沒有（同步就會有）
  vs 不合法（無從查找，處置是先 `store-source` 再改槽位）。閘的缺口另開 #507（sister，Step 5.7）。
- 拿掉 `sources/` 的副本跑同一支 binary：**41 筆**（40 venue ＋ 1 divergence）——「其他機器上會是多少」的下限。
- 重跑指令見 `zero-instance-guards` 第 15 列下方。

## 相鄰

- PR #482（#464）與本張同在 `health(from:)` 尾端——依使用者裁決，等它 merge 後才開本 branch（2026-09-03 已 merge）。
- #500：(b) 退回 nil 的路與 (c) 翻轉語意，本張不做。
- #504：CLI `doctor` 命令另有一條直接呼叫 `auditSourceIndex()` 的路徑（`Commands.swift:48`），本張不動。
- #487：App 面渲染 per-record warning。

## 兩面

| 面 | 看得到什麼 |
|---|---|
| CLI `validate` | 逐條 `⚠ <kind> <key>: 本機缺承重存檔：<slot> 指向 sha256:…` ＋ 一行計數 `本機缺承重存檔: N` |
| MCP `akashic_doctor` | `recordIssues.first`（截 20）逐條 ＋ `recordIssues.danglingSources` 計數 |
| App | 側欄「記錄」Section：記錄層問題總數＋三個家族的計數，`.help` 帶前幾則（#487） |

兩面都提到 `health.danglingSources` 由 `DanglingSourceScanTests.testBothFacesMentionDanglingSources` 以源碼掃描釘住
——`StoreHealthSurfaceTests` 的反射只看儲存屬性，計算屬性（`deadVerdicts` 亦然）在它視野外。
