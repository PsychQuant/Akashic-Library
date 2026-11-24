## 1. 規格措辭（#802 verify 第 2 輪第 1 列，MEDIUM）

ASSUMPTION: 這條 requirement 的四個 Example 都已有帶 `spec-example: fulltext-gate-look / <Example title>` 標記的測試，這個 change 只改一句的指涉、不改 Example，所以不新增測試 task；`.spectra.yaml` 的 `tdd: true` 對純措辭的改動沒有可以先寫成紅燈的測試。

- [x] 1.1 `An unreadable same-site tab with a human-check marker at a login path SHALL pause the run`：「When the marker is found and the path does not have the look of a login page」改成「When the service-marker check returns `cloudflare-challenge` or `perimeterx-press-and-hold` and the path does not have the look of a login page」。驗證：對照 `FulltextFetch.swift` 的 `judgeUnreadable`（只有 `hit.response == .humanVerification` 才走等人驗證），封存後主規格這一句與 delta 一字不差，主規格再也搜不到「When the marker is found and the path」

## 2. changelog 措辭（#802 verify 第 2 輪第 2–5 列）

- [x] 2.1 `changelog/2026-11-16-fulltext-gate-look-wording-802.md` 開頭那一段：「MODIFIED 三條 requirement，各改一句；既有 scenario 與 Example 原樣保留，對應的測試標記都在」照劃線加箭頭的寫法改成併入之後的說法（主規格裡只剩兩條是這張改的，第三條與它的 Example 由 #821 的改寫取代）。驗證：原句以 `~~` 包住、箭頭後的新句各出現一次
- [x] 2.2 同檔〈規格〉的契約版本那一條：整段原文以 `~~` 劃線，後面接箭頭與「併入 main 時作廢」，拿掉沒有劃線的那份重複。驗證：「改成指這幾格」與「逐格列了四種情形」各只出現在劃線裡
- [x] 2.3 同檔〈併入 main〉的「第三處」改成「規格第三條（契約版本的理由句）」；#802 的 merge note（comment 7064659575）同樣更正。驗證：該檔與那則 comment 都搜不到「第三處」
- [x] 2.4 同檔〈併入 main〉補一句：封存的 proposal 與 tasks 寫的「`fulltext-contract` 仍是 10」是併入之前的歷史；它們的摘要「整批暫停的標記優先」省略了「主機不是登入主機的長相」這個前提，delta 有寫。驗證：該句存在，封存檔不動（`git diff` 不含 `openspec/changes/archive/2026-11-16-*`）
- [x] 2.5 同檔新增一節〈verify 第 2 輪之後〉，記 `idd-802-fix1` 改了什麼、為什麼（引 #802 verify 第 2 輪報告）。驗證：該節存在

## 3. 收尾

- [x] 3.1 `spectra validate idd-802-fix1` 通過；封存後 `spec-change.py links` 對這個 branch 的範圍回 ok、`archived` 對宣告的兩個 change 回 pass。守衛與全套測試照使用者 2026-11-21 的決定在 mini 跑 pre-push 三段
