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
- #618：5 輪驗證。R3、R4 的 HIGH 都落在「部分否決」與「批次 apply」上。那些問題散文關不掉：篩選式批次 apply 會帶走範圍內所有候選，包括沒人判定過的配對。使用者裁決停損，工具面另開 #624；查過未決的配對沒有載體，另開 #619。R5 為 0 HIGH，最後的措辭修正在 `7ab986ce`。
- 每一輪都跑 `.githooks/run-guards.sh`，rc=0。

## #624：篩選式批次 apply 不再帶走淘汰而得的唯一候選

`ResolutionCandidate` 多了必填欄位 `eliminatedPairings`，記下這個位置被否決淘汰掉幾個人選。`resolve-people --apply`（不論帶不帶 `--tier`／`--citekey`／`--person`）不套用這種候選：

- 列表每一列都會標出它。
- `--apply` 時另列一份排除清單，並指引改用逐筆 `--judge`。
- 如果整批都被排除，就零寫入、以非零結束碼退出。
- tier 閘改看排除後的套用集。

MCP 列表帶同一個欄位；以三段 id 點名的 apply 照寫，兩段 legacy id 指到這種候選時會被拒絕（MCP 的 apply／reject 與 CLI 的 `--reject` 都拒；CLI 的 `--apply` 只送三段 id）。重複 citekey 這種損壞狀態下，兩個位置可能共用同一個三段 id，這時也拒絕，不猜是哪一筆。其餘路徑見下一節 #627。tier 閘擋下時，錯誤訊息會說明另有幾筆淘汰所得不會套用。查過但判不出來的配對，工具仍然看不到（#619）。

## #635：resolve-people 的 judge／refute 不再靜默丟掉同時送出的其他腿

judge 或 refute 與彼此、或與 apply／reject 一起送出時，過去只會執行其中一條，其餘的被靜默丟掉，回應照樣成功。#627 R4 驗證的 DA 席用真 binary 實測過：`--judge … --refute …` 只執行 judge，refute 的否決沒有寫入，輸出也沒提到。

現在兩面都顯式拒絕這些組合：整批拒絕、零寫入，並具名說明。這與結構腿（split／un-split／drop／attribute-org，#443）的既有契約相同。

## #627：citekey 重複時，resolve-people 一族不再猜是哪一筆

citekey 重複是 store「被支援的損壞態」。過去寫入路徑以 citekey 定位 entry，並用 `uniquingKeysWith` 靜默選一筆。#624 R3 驗證時，DA 席用真 binary 重現了後果：照 `--judge` 的指路，會把判定寫到另一筆 work 的另一個作者上，而且 rc=0。

診斷時又發現更糟的一格：`PersonResolver.apply` 最後以 citekey 對回原陣列，會把同 citekey 的每一筆 entry 都換成同一份。

現在的處理：

- **最後一道防線**：`PersonResolver.apply` 以陣列位置就地改寫，不經任何字典對應回輸出；citekey 重複、或 entry id 重複的位置都不改。第一版改成「以 `Entry.id` 對應回輸出」，R1 驗證以真 binary 否掉：半遷移留下的同 id 拷貝（entities 與 legacy 各一份）會被互相覆寫，被編輯過的那份安靜回退；兩筆不同 citekey 共用 UUID 時，無關的 apply 也會把其中一筆整個換成另一筆（6 次裡 4 次，取決於 hash 順序）。
- **「無法唯一定位」的定義只有一個**：`unlocatableCitekeys`（`Collection` 上的延伸，Element 是 Entry；R3 起限定 `Collection`，因為 `Sequence` 不保證能重走），放在 AkashicCore。它涵蓋 citekey 重複，以及 entry id 與另一筆共用的情形：那一筆的 citekey 本身唯一，但寫入以 id 定檔。R2 驗證用真 binary 重現過，對這種 work 做 drop-author，會把兄弟 work 在 `entities/<id>.yaml` 的唯一一份整個蓋掉。R1 只看重複 citekey。這個集合只看得到載入成功的 entry：若目的檔被 quarantine，或其實是另一種記錄，它不在母體裡，寫入仍會蓋掉它（R3 驗證以真 binary 重現）。這一格要在寫入端確認目的檔屬於同一筆記錄才擋得住，歸 #631。
- **各腿沿用既有的失敗語意**：
  - apply／reject（兩段與三段 id）、split／un-split／drop／attribute-org：整批拒絕、零寫入。
  - judge／refute：該筆具名略過，其餘照寫。全部略過時沒有寫入，CLI 以非零結束；MCP 照常回成功，由呼叫端讀 `skipped`。作者位早已歸給同一個人的判定是 no-op 成功，回在 `alreadyJudged`，不算略過（R4：重跑已落地的判定曾被當成失敗）。已歸給另一個人時仍略過，但不再指路「先否決既有 verdict」：照做會留下矛盾的 verdict 對，作者位也不會變。負的作者索引改為輸入錯。同一次呼叫把同一個作者位判給兩個人時整批拒絕。R2 以健康的 store 重現過：兩個 person 都會寫下 confirmed verdict，作者位卻只套用了第一個。否決不受這條限制。judge 不再吞掉 index 重建的失敗；重建失敗時，錯誤訊息逐行列出略過與已落地的 id。每個 id 一行，因為兩面的輸出每行截在 400 字（R4 驗證）；各清單至多 50 行。理由不重印：它們已經對 JSON 出口消毒過，再逃一次會雙重跳脫。
  - CLI 篩選式 `--apply`：排除並另列，其餘照寫；列表每一列都標出來。
  - App 裁決台的 accept：具名拒絕（`AdjudicationError.unlocatableCitekey`）。先前它依賴 apply 當防線，而 apply 回退拷貝時仍會寫下「確認歸戶」verdict。
  - MCP 候選列表：無法唯一定位的列帶 `unlocatableCitekey: true`，不必送出 apply 才知道會被拒。App 的候選列表沒有這個標記，accept 時才具名拒絕。
- **verdict 只寫給真的改到的作者位**（apply 與 judge 都一樣）。以作者位為單位，不以 citekey 為單位。有了上面的前置拒絕，這一條是備援。若仍有候選沒套用，apply 以 `notApplied` 具名回報；index 重建失敗時，錯誤訊息也列出這些候選。這種情況下 CLI 以非零結束。R1 原本把共用 UUID 交給這條路徑處理，但同一個 store 的 index 重建會先失敗，`notApplied` 永遠到不了呼叫端（R2 驗證）。

重複 citekey 的 store 本來就重建不了 index（UNIQUE），寫入之後的 rebuild 仍會失敗，這一點 `validate` 另行報告。

同型但不屬 resolve-people 一族的 `setMembership`／`enrich`、venue 的 repoint／demote，以及 `VenueResolver.apply`／`OrgResolver.apply` 的同一個字典形狀，見 #628。`writeEntry` 與 `rename` 在 entities 佈局下會留下 legacy 拷貝，等於工具自己造出這些損壞態，見 #631。

