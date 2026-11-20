## 1. 測試先寫（看它們失敗）

- [x] 1.1 在 `Tests/AkashicCLITests/FulltextAttemptCLITests.swift` 寫記帳命令的 CLI 測試，每一個都帶 `--ledger` 指到暫存路徑，帶標記 `spec-example: fulltext-attempt-accounting / First attempt of the day is recorded`、`/ Host case does not split the count`、`/ Eleventh attempt is refused`、`/ Attempts and fetch share one count`、`/ Malformed sites are refused before the ledger is touched`、`/ A garbage line stops the command`；驗證：`swift test --filter FulltextAttemptCLITests` 全部失敗，原因是子命令不存在（結束碼 64）而不是編譯錯誤
- [x] 1.2 在 `Tests/AkashicCLITests/FulltextDivisionOfLabourTests.swift` 寫 SKILL 文字斷言，帶標記 `spec-example: fulltext-division-of-labour / Division of labour section lists five classes`、`/ Retired hand-over sentences are gone`、`/ Click procedure calls the attempt command`；驗證：`swift test --filter FulltextDivisionOfLabourTests` 三支都失敗
- [x] 1.3 把 `Tests/AkashicKitTests/FulltextLoginLookRulingsTests.swift` 的契約 Example 改成斷言 11，標記改為 `spec-example: fulltext-gate-look / Skill and CLI agree on contract 11`；驗證：該測試失敗（現行常數是 10）

## 2. 實作 CLI [after: 1.1, 1.3]

- [x] 2.1 （Requirement: The attempt command SHALL record one attempt in the ledger that fetch uses）新增 `akashic fulltext attempt`，以 `FulltextAttemptLedger.reserve` 記一次、印 `attempt:` 一行、結束碼 0，主機小寫化；驗證：1.1 的前兩支轉綠
- [x] 2.2 （Requirement: The attempt command SHALL stop at the daily cap without recording）到上限時印 `cap:` 一行、結束碼 9、帳本不變，與 `fetch` 共用同一本帳；驗證：`Eleventh attempt is refused` 與 `Attempts and fetch share one count` 轉綠
- [x] 2.3 （Requirement: The attempt command SHALL refuse a site that is not a plain host name）`--site` 不是乾淨的 DNS 主機名稱、或 `--landing` 不是絕對的 https 網址時，在碰帳本之前以 64 結束；驗證：`Malformed sites are refused before the ledger is touched` 轉綠
- [x] 2.4 （Requirement: The attempt command SHALL refuse a ledger it cannot read）帳本讀不懂時結束碼 1、不追加；驗證：`A garbage line stops the command` 轉綠
- [x] 2.5 （Requirement: The fetch contract version SHALL be 11；取代 The fetch contract version SHALL be 10）`FulltextFetch.contractVersion` 改 11 並在版本沿革註解加一行，SKILL 第 0 步門檻改 11、寫明版本 11 是什麼；驗證：1.3 與 `SkillToolsCLITests`、`CheckCLIHookTests` 綠
- [x] 2.6 `Sources/akashic/WriteGateRulings.swift` 加 `fulltext attempt` 一格（只寫 store 之外的每日嘗試帳本），`docs/rulings/mcp-cli-parity.md` 的 `fulltext` 一列補 `attempt` 與缺席理由，`FulltextCmd` 的摘要列出它；驗證：列舉 CLI 子命令的既有測試（`swift test --filter WriteGate`）與 `bash .githooks/run-guards.sh` 綠

## 3. SKILL 與出版商表 [after: 1.2, 2.5]

- [x] 3.1 （Requirement: The skill SHALL make the model the default actor and hand over only a closed list）`plugin/skills/akashic-fetch-fulltext/SKILL.md` 新增〈人機分工〉一節，並改寫 description、規則 1 例外 (d)、規則 3、規則 4、規則 5、〈等人驗證〉（結束碼 8 的那一篇與同站其餘各篇延到最後）、第 2 步開放版本、第 3 步結束碼表與交接表逐列、第 6 步、第 7 步回報的兩種結局；驗證：`Division of labour section lists five classes` 轉綠，並以 grep `交給人|請使用者|請他|授權|代按|等使用者` 逐筆分類，沒有一句與新的預設矛盾
- [x] 3.2 （Requirement: The skill SHALL NOT keep the superseded hand-over rules）刪掉三句舊規定；`pdf-shown`、〈能做到哪裡〉、第 4 步檔案來源改用 `safari-browser save-pdf`，`pdf-cache` 寫成限制註記（PsychQuant/safari-browser#375）；第 5 步 acquisition 加 `browser-save-pdf`；〈不做的事〉只留登入、授權、「接受」、付費並改正出處；驗證：`Retired hand-over sentences are gone` 轉綠
- [x] 3.3 （Requirement: The skill SHALL count each click it makes）SKILL 第 3 步加點擊程序（每一下之前 `snapshot -i` 確認是這篇自己的連結、`akashic fulltext attempt`、節奏工具、按）與落點的封閉列舉，〈每站每天 10 次嘗試〉補上點擊也記；驗證：`Click procedure calls the attempt command` 轉綠
- [x] 3.4 `plugin/skills/akashic-fetch-fulltext/references/publishers.md` 的前言與 Annual Reviews、SAGE、Wiley 各列改成新的分工，並補 2026-11-10（Ovid／LWW、SAGE epub 閱讀頁、AME、Wiley epdf）與 2026-11-19（SAGE 儲存面板、Oxford／silverchair、Project Euclid、ScienceDirect）的實測，每列帶觀察日期，只寫 issue 裡回報過的事；驗證：內容對照 #780 正文與 2026-11-19 的留言逐列核對

## 4. 發布與驗收 [after: 2.6, 3.4]

- [x] 4.1 plugin 殼升版（`plugin/.claude-plugin/plugin.json` 0.13.16 → 0.13.17 與 marketplace 的對應欄位）、`plugin/CHANGELOG.md` 加一則、新增 `changelog/2026-11-19-fulltext-ai-default-781.md`（含 acquisition 新值的名稱），最後才在 `.githooks/plugin-shell-versions.txt` 加一列；驗證：`.build/debug/akashic-guards plugin-shell-version` 通過
- [x] 4.2 `swift build -Xswiftc -warnings-as-errors`、`swift test --filter Fulltext`、全套 `swift test`、`bash .githooks/run-guards.sh` 都通過；驗證：四個指令的結束碼都是 0，結果記在 Implementation Complete
