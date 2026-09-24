# 查證 skill 的「判不出來」出口改寫、取全文 skill 審查（#612、#613、#616、#618）

四張 issue 都是 plugin skill 的散文或腳本，沒有動到 store 格式或 CLI／MCP 介面。

## akashic-verify-venue：逐次查詢的證據清單與號的核對（#612、#616）

- **報告第 3 項一次查詢一列**，每列一個值：查無／多刊命中／衝突／不可達／未需要。在此之前，模糊搜尋「回了不相干的東西」
  被標成「歧義」，跟歧義列撞名。同一本刊但沿革某一段對不上時，另立「衝突」，只擋那一段，不擋配對。
- **哪些號進第 4 項**：通過三道核對的號才進第 4 項。沒過的號連同原因寫在第 2 項。撞號時的三種結果（持號的是本刊／
  持號那一筆的號錯了／判不出來）各有處置，而且三種結果都不決定 literal 的配對。
- **分裂的刊**（多本刊共用一個前身）store 表達不了（#421）：分裂那年之前的 entry 不可判定，literal 留著。其餘處置在
  #615，目前擱置，等 #421 的觸發條件。
- divergence 的 candidates **不寫死兩筆**（#616）：放目的 venue、持號那一筆，以及查證顯示同為本刊的其他兄弟記錄。
  判不出來時，只擋撞號的號與持號那一筆；更新腿其他通過核對的號，照第 4 項各自確認。

## person 域「查不出來」的出口（#618）

`akashic-verify-person`、`akashic-disambiguate`、`akashic-promote-literals` 原本叫人「記 divergence 落進度、下次續查」。
這個寫法有兩個問題：

1. **照做會被工具拒絕**：rests_on 帶 URL，而 `recordDivergence` 自 #507 起只收 `sha256:` digest，且 judgement 與
   rests_on 要成對；把 literal 當候選也會被拒，因為 candidates 必須是兩筆以上同 shape 的記錄 key。
2. **問錯了問題**：「這個 literal 是 A 還是 B」是指涉問題，不是「兩筆記錄是不是同一個實體」。divergence 的出口是
   不可逆的合併，而且沒有移除面（#586）。

使用者 2026-09-24 裁決：判不出來時**讓 literal 留著**，不 judge、不 refute，查過的來源寫在報告裡。store 不留查過的
紀錄；下次重跑 resolve 時，有候選或歧義就會再列一次。只有兩筆以上 person 記錄本身可能是同一個人時，才記 divergence。
這與 `disambiguate-before-irreversible-writes` 的 residue 出口是同一件事。

## akashic-fetch-fulltext 審查 R1–R6（#613）

- **中止條款**：分頁跑到別的網域、頁面讀不到、回應卡住或空白、fetch 拋錯，一律回結束碼 6，不再落成可重試的 1。
  `--expect-profile` 在開分頁前就核對 profile。`--out` 不得落在沒有 ignore 它的 git 工作樹裡。
- **「是這篇」的判定**：原本用字詞重疊，在 29 份真實 PDF 上交叉錯收 14/808。現在改成比對標題行，身分再分級：
  PDF 自己的 XMP DOI 是強證據；首頁第一個 DOI 是中等證據，而且頁數要吻合（勘誤或回應文可能先印原文的 DOI）；
  沒有 DOI 的不自動收。校準結果：本篇收 22/28，別篇錯收 0/808。被拒的 6 篇都缺中繼資料 DOI，也沒有可比的頁數，
  交給人看。
- 測試：單元 54 支、stub 瀏覽器路徑 19 支，已接進 `run-guards.sh`，所以 pre-push 與 CI 跑的是同一條。對 11 個
  結束碼 6 的呼叫點逐一做突變，每一個都恰好被一條測試抓到。

## 驗證

- #612：10 輪 ensemble verify，最後一輪 0 HIGH／0 MEDIUM。
- #616：5 輪，最後一輪 0 HIGH／0 MEDIUM，唯一的 LOW 已修。
- #618：R1 FAIL（2 HIGH），R2 依裁決改寫，驗證中。
- 每一輪都跑 `.githooks/run-guards.sh`，rc=0。
