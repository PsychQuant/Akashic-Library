# 2026-09-29 #593 與 #599 的 R2 驗證修正

R2 六席（requirements、logic、security、regression、devil's advocate、Codex）對 #593、#599、#629 三張一起驗，帶回 63 則
（HIGH 2、MEDIUM 19、LOW 24、INFO 18）。兩個 HIGH 都在 #629（見 `2026-09-29-b13p-verify-r1.md` 第八節）；本檔記 #593 與 #599 的部分。

**這一輪的原則**：#556 的散文修了九輪，每一輪加的句子都被下一輪打破。所以這一輪對散文只收縮——刪掉或縮短，不加新的程序。

## R2 驗證的修正（#593：`web-access.md`、`akashic-verify-venue`、規則檔）

| R2 # | 級 | 一句話 | 處置 |
|---|---|---|---|
| 7、10、15、16 | MEDIUM | R1 加的「落地網址也要驗」照字面永遠不過（`location.href` 帶著 `#akashic-<T>`，而「完整網址」一列不收 `#`）；它是散文不是區塊；排在區塊二讀頁面之後；而且發生在帶 cookie 的導航之後 | **刪掉**，不修補。鎖對不到就停的規則仍只在〈鎖不到的時候〉一處；〈會轉址的頁面〉只補一句「轉到哪裡由出版商在 `doi.org` 登記，本檔不驗落地的網址」 |
| 11、17 | MEDIUM | 轉址的更正（HTTP 3xx 留 fragment、meta refresh／JS 轉址不留）只改了一處，另外兩處仍說鎖不受轉址影響 | **收成一處**：web-access.md〈會轉址的頁面〉。鎖法那一段與規則檔〈使用紀律〉改成指向它。`akashic-venue-works/references/site-access.md` 說 PsycNet 的跳轉鏈沒量過——那是關於 PsycNet 的事實，仍然成立，不動 |
| 6、43 | MEDIUM／LOW | 〈承重存檔〉說「取得伺服器原始位元組的面不存在」，verify-venue 說頁內 fetch 的原始位元組可以存；兩邊都不精確——`akashic fulltext fetch` 用 `r.arrayBuffer()` 存的就是回應本文的位元組 | **邊界只寫一處**：〈承重存檔〉改說 `r.arrayBuffer()` 拿到的是本文位元組（壓縮已解開、沒有字元集轉換）、本檔的區塊讀 `r.text()`；verify-venue 的三處敘述改成指向那一段 |
| 25 | LOW | 分頁數的重驗只在四個動到分頁的區塊裡的兩個 | **補齊**：「導航到下一頁」與「關分頁」兩個區塊也先數；鎖法那一段改寫成「每個區塊動作前自己數一次」 |
| 26、40、55 | LOW／INFO | 表要求照實寫 media-type，區塊卻沒抓 `Content-Type`；新的 `acquisition` 值 `browser-automation` 只出現在這一份 | 區塊的回報多印 `c`（`Content-Type`）；`acquisition` 改用既有的 `browser-download`（與 akashic-fetch-fulltext 同一個值、`store-source` 的說明列著它），讀的是什麼由 `origin` 說。live store 的 `index.jsonl` 唯讀量到 11 種值，這個欄位實際上是開放的；要不要在 store-format 定一份值域不在這一輪 |
| 31 | LOW | 「讀回是空的算失敗」只在散文裡 | 取 API 與讀頁面兩個區塊各加一行 `grep -q '[^[:space:]]'`；`--large --output` 對空字串寫出什麼沒有實測，所以散文的定義保留 |
| 24、32 | LOW | 規則檔還寫「第 4 源的瀏覽器契約待 #593」 | 改指 #692 |
| 42 | LOW | 規則檔稱評測快照「不適用」，卻不在「不適用」的封閉列舉裡（#629 R1 寫的段落） | 〈不適用〉顯式加第 4 類；原段落縮成一句指向它 |
| 45、48、52 | INFO | Codex 對 #593 沒有報；R1 的轉址 HIGH 已關（fail-closed）；#593 自己的 Expected（第 4 源的瀏覽器契約）沒交付、移到 #692 | #593 要不要以 #692 取代而關，是使用者的決定 |

## R2 驗證的修正（#599：上游優先規則、公開 repo 的敘述）

| R2 # | 級 | 一句話 | 處置 |
|---|---|---|---|
| 14、23、29、39 | MEDIUM／LOW | 這一批新加的三處文字說本 repo 是 private；`gh repo view` 回 PUBLIC | **修**：`AbstractProposals.swift` 的註解、`akashic-fetch-fulltext/SKILL.md`、`akashic-venue-works/SKILL.md` 改成「plugin 安裝處讀不到」（那才是真正的限制）。更早的同類敘述（plugin CHANGELOG 2026-08-21 的 `isPrivate=true` 量測等）由 #693 第 4 項追蹤，不在這一輪改 |
| 8 | MEDIUM | plugin 副本沒落地，三份還不能互相指向 | **待使用者裁決**（#691） |
| 13 | MEDIUM | 人名與私有 repo 名仍在公開的 main 歷史裡 | **待使用者裁決**（#693）；已經公開，重寫歷史也收不回既有的 clone |
| 49、53、58、62 | INFO | 鏡像的規則段逐字一致（唯一差異是 3(b)）、鏡像只在本機 | 確認，不動 |

`upstream-first-bibliographic-updates.md` 與 `no-compat-fallback.md` 這一輪沒有改：R2 對它們沒有要修的內容，#599 剩下的兩件都在等使用者。

## 誠實邊界

- 仍沒有實跑 Safari：web-access.md 的區塊（含新加的兩行數分頁、兩行空讀檢查、`c` 欄位）都只讀過 `--help`，沒有對真的頁面跑。
- 刪掉落地網址檢查之後，`doi.org` 轉到哪裡完全由出版商的登記決定；在開分頁之前先查 `doi.org` 的 handle API 是一條可行的路（R2 security 席提的），這一輪沒有做。
