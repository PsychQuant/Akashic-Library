# 死 verdict 進 `StoreHealth`（#464）

resolution verdict 的 value 指向一個**沒有載入**的 holder（`work:<citekey>`／`person:<key>`／`org:<key>`）
現在由 `LibraryStore.health(from:)` 掃出（`deadVerdictIssues(in:)`），以 warning 級的 `OwnedIssue` 併入
`perRecordIssues`——CLI `validate` 逐行可見；MCP `akashic_doctor` 進 `recordIssues`（`prefix(20)` 截斷、`count` 送分母，#236 的既有預算）；
**App 面未渲染 `perRecordIssues`**（#416 起的既有缺口，健康區塊閘在 `hasFindings` 而它只計 error）
——追蹤 #487。`StoreHealth.deadVerdictPrefix`／`deadVerdicts` 給三面單一定義。

- **判準**：set-difference——holder 不在已載入的對應 kind 集合。**「不在集合」分兩種說**：holder 的檔
  仍在磁碟但被 quarantine（訊息指名那個檔，先修它）；沒有任何檔宣稱它（退役時遷移漏了——#463 的網格
  ——或走了沒有遷移的路徑；處置是在持有記錄的 references 更新或刪掉那筆 verdict）。掃 person／
  organization／venue 三族；`Entry` 帶不了 verdict（`validateReferenceAttachment` 在 decode 就拒），
  測試釘住這個「三族即全部」。
- **warning 不是 error，三個理由、都是「現在」**：升 error 會把 `zero-instance-guards` 第 8 列釘住的零
  翻掉（死 verdict 會是第一個既非 key 檢查又對已載入記錄可達的 per-record error，`errorsFirst` 從裝飾品
  變承重結構，第 8 列明寫那個轉變不得安靜發生）；#464 的 Expected 逐字寫「warning 級」；今天沒有處置
  命令。**不是**「rename 後常態為真」也**不是**「rename 本來就全遷」——`renameEntry` 沒有 organizations
  迴圈（#463 的格），verify DA 實測兩次 rename 產生 4 條死 verdict；這是 #463 要修的，不是本列調
  severity 的理由。#463 補完後 error 要重開裁決。誠實邊界：warning 級的 `validate` exit 仍為 0——做到
  「掃得到」，做不到「叫醒」。**2026-09-03 補記**：#463（PR #493）同日 merge，`renameEntry` 已有
  organizations 迴圈；「零的第二個來源」消失。修復路徑仍缺，error 的重開裁決未發生。
- **解析不了的 value 對已載入記錄不可達**：decode 期的 `validateReferenceAttachment` 把 malformed
  verdict 整檔 quarantine；測試釘住「零的來源在 load」（`zero-instance-guards` 第 8 列的形狀）。
- **實測**（2026-09-03）：live store 2,700 條 verdict（`grep -h 'field: resolution-' ~/.akashic/entities/*.yaml | wc -l`），
  死引用 0（2026-09-03）。重跑指令**自證**（先確認 binary 含這條檢查）——verify DA 2026-09-03 在一份真有
  5 條死 verdict 的副本上，PATH 上的舊 `akashic` 回 0、`.build/debug/akashic` 回 5。
- **規則表**：`zero-instance-guards.md` 第 13 列（✅ 寫，理由「跡象住在錯的地方」——家族三張 issue
  #232／#271／#460 是三個結構缺口，stale 實際累積一次、三個場外機制全在 #460 那一次）；第 14 列（❌ 不寫，
  第 10 列的形狀）記錄 #461 交叉註記的第二個掃描項——**本輪只做 set-difference，矛盾偵測（同配對
  confirmed／rejected 並存）延後至 #486**，其 Blocking 是 #470 的相等定義。
- **quarantine 宣稱者的判定**（verify Codex R2／R3）：頂層標頭要從第 0 欄開始（縮排的巢狀鍵不算），但
  不要求整行位元組相等——檔首 BOM、CRLF 的 `\r`、標頭後的水平空白都是合法排版。實測抓到一個更深的坑：
  Swift 把 `\r\n` 當**一個** Character，只用 `"\n"` 切行的 CRLF 檔整檔會是一行（Codex R3 的 CRLF case 促成
  實驗、缺陷在 fix round 才發現）——`rawLines` 統一切三種換行（`\n`／`\r\n`／單獨 `\r`，Codex R4）、檔首
  BOM 剝一次；person／org 的共用查詢與既有的 citekey 查詢都走它；CRLF／CR／BOM 各有真檔測試。
- **conformer 棘輪**遞迴掃整個 `Sources/AkashicCore`、只看繼承子句（泛型約束與 `where` **關鍵字**之後不算——用識別碼邊界切、反引號逃逸的 `` `where` `` 不算關鍵字——`Somewhere` 與 `` `where` `` 都不截，Codex R5／R6；巢狀型別名保留）
  ——它是**詞法**棘輪不是編譯器約束，常見寫法的第五個 conformer 會紅、極端排版與註解裡的宣告不保證（Codex R3／R4）；Entry 拒絕斷言改 pattern-match `StoreYAMLError.invalidField` 的 field。
- **Verify 補的**：quarantine 分辨、測試矩陣（正向 person／org holder、錯集合碰撞、
  quarantined holder、malformed 不可達、三族釘子）、第 13 列的歸因與 severity 理由——R1 六席全 FAIL 後的
  fix round。
