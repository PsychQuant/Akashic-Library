## 1. 規格措辭（delta 已寫，apply 時逐句對照程式）

ASSUMPTION: 三條 requirement 的既有 Example 都已有帶 `spec-example: fulltext-gate-look / <Example title>` 標記的測試（`Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift`、`Tests/AkashicKitTests/FulltextB37Tests.swift`，共 13 個），這個 change 不新增、不改 Example，所以不新增測試 task；`.spectra.yaml` 的 `tdd: true` 對純措辭的改動沒有可以先寫成紅燈的測試。

- [x] 1.1 `An Atypon showLogin path segment SHALL have the look of a login page` 的「導航之前判斷文章站上的 HTML 頁」括號列齊三處：DOI 落地頁落定之後、讀文字時分頁變成的頁、在文章站上 resume 且導航之前。驗證：對照 `FulltextFetch.swift` 的 `resume` 的 `.article` 分支（導航之前網址 `urlGateLook` 是 `login` 時以 `(login page)` 整批暫停），封存後主規格這一句與 delta 一字不差
- [x] 1.2 `An unreadable same-site tab with a human-check marker at a login path SHALL pause the run` 補一句既有的順序：服務標記的判斷優先回整批暫停的標記，標題或網址同時命中這種標記時以它整批暫停（exit 6），訊息是那個標記、不含 `(login page)`。驗證：對照 `BotSignals.serviceMarker`（先回 `pauseBatch` 的標籤）與 `judgeUnreadable` → `stop(for:)` → `botStop(hit.label)`，封存後主規格這一句與 delta 一字不差
- [x] 1.3 `The fetch contract version SHALL be 10` 的理由句「Because two cells changed exit code」改成指這幾格，並指向 `contractVersion` 的逐格註解。驗證：該註解第 10 版那一段列的格數不止兩格；`fulltext-contract` 仍印 10，`SkillToolsCLITests` 不動

## 2. 文件措辭

- [x] 2.1 [P] `changelog/2026-11-11-fulltext-login-look-rulings-777.md`：契約版本那一行「兩格的結束碼變了」改成「這幾格的結束碼變了」；〈併入 main〉最後一句改成「`Sources/`、`Tests/`、`openspec/` 沒有手動修改；main 帶進來的檔照原樣」。驗證：該檔再也搜不到「兩格的結束碼變了」與「也沒有因為這次併入而改動」，其餘行不動（`git diff` 只有這兩行）
- [x] 2.2 [P] `docs/rulings/mcp-cli-parity.md` 的 `fulltext` 列：把「是否保留待使用者裁決（#777 第 4 件，#779 加註）」照該檔慣例寫成 `~~原句~~ → 使用者 2026-11-11 裁決維持（見同列 #777 那一段 (d)）`，原句全文保留。驗證：該列含劃線包住的原句與箭頭後的新句各一次，`git diff` 只動這一處
- [x] 2.3 [P] 新增 `changelog/2026-11-16-fulltext-gate-look-wording-802.md`，逐處記這五處改了什麼、為什麼（引 #802 與 #777 verify 第 2、3 輪），並寫明程式、測試、契約版本都沒動。驗證：檔案存在、五處各一條

## 3. 收尾

- [x] 3.1 規格與連結：`spectra validate idd-802-fulltext-gate-look-777-changelog-parity` 通過；封存後 `spec-change.py links` 對這個 branch 的範圍回 pass（Example 未變、標記都在）。守衛與全套測試由 pre-push 在 push 時跑
