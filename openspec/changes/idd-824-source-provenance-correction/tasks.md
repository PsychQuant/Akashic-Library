## 0. 開工前

- [ ] 0.1 確認 proposal〈Open questions for the maintainer〉五題的答案；選了建議預設以外的，先改 `specs/provenance-reference/spec.md` 對應的 requirement 與下面的 tasks
- [ ] 0.2 Q2 與 #825 的 Q1 一起定：#825 要在既有列補 `version` 時，把 `version` 加成第二個可更正的欄位（spec 的封閉列舉從一項改兩項），兩個 change 的實作順序寫進兩邊的 tasks
- [ ] 0.3 Q4 照建議時：查 `docs/store-format.md` §5 版本表的下一號，與其他進行中的 change 有沒有搶同一號

## 1. 測試先寫（在本 change 開工時的 main 上看它們失敗）

- [ ] 1.1 （Requirement: A stored source's provenance note SHALL be correctable by appending a correction row）更正後既有各行逐位元組不變、檔案多一行、現行 note 是更正後的；更正的更正形成鏈、三列都在；改 `note` 以外的欄位拒絕、零寫入
- [ ] 1.2 （同上，重存的 scenario）同一份位元組帶不同 note 重存：不加列、`discardedProvenance` 照舊；CLI 人可讀分支那一句改指向更正的入口（字串測試）
- [ ] 1.3 （Requirement: A correction row SHALL be parseable under the existing index grammar and distinguishable from a duplicate row）在**現行的** `scanIndex` 上，帶更正列的 index 沒有無法解析的行、第一列照舊是現行列（這一支在開工時的 main 上應該就通過：它釘住舊讀法不被更正列弄壞）；並行留下的兩個 plain 列不被當成更正；缺 `reason`、`supersedes` 不是正整數的更正列算無法解析的行，之後的 `store-source` 被拒
- [ ] 1.4 （Requirement: Readers SHALL present the current note and mark what was superseded）兩筆並行的更正都指同一行：檔案順序的第一筆生效、第二筆不生效，讀取面與 doctor 都說出第二筆沒生效；`update-entry --add-source` 的 `sourcesAdded` 與 `--remove-source` 的 `sourcesRemoved`：現行 note、是否更正過的旗標、被取代的原文與每次更正的理由和時間；沒更正過的列旗標為否。兩面（CLI 與 MCP）各一次
- [ ] 1.5 （Requirement: The correction entry point SHALL be available on both interfaces and SHALL refuse a closed list of cases）六種拒絕各一個 fixture，每一種都零寫入；note 與現行相同時零寫入、回報已是現行、不是錯誤；回應的四個欄位；CLI 與 MCP 對同一個 fixture 寫出除 `corrected` 時間外相同的列
- [ ] 1.6 （同上，doctor）手改 index 讓更正列的 `supersedes` 指到別的 digest 的行、指到不存在的行：doctor 列出它、不改 index
- [ ] 1.7 （同上，不說成驗證）更正入口的說明文字與回應裡沒有「verified／驗證過」之類把更正當成查證的字樣（字串測試，比照 `provenance-reference` 對 audit 的同一條）
- [ ] 1.8 驗證：帶 requirement 標記的新測試（1.3 的第一部分除外）在開工時的 main 上都失敗；commit

## 2. 程式 [after: 1.8]

- [ ] 2.1 `SourceStore.swift`：`scanIndex` 認得更正列、算出每個 digest 的現行列與被取代的鏈；更正列的追加沿用 `appendIndexEntry` 的三道防線（index 路徑的排除驗證、結尾換行守衛、`O_APPEND`）；`SourcePresence` 帶出現行 note 與鏈
- [ ] 2.2 Q4 照建議時：`StoreVersion` 的新一號；更正的寫入閘要求 format ≥ 那一號；舊 binary 拒開的行為由既有的 refuse-if-newer 涵蓋（測試確認）
- [ ] 2.3 `AkashicService`：更正的服務函式（兩面共用）；`EntryUpdate` 的兩個讀取面帶出現行 note 與鏈
- [ ] 2.4 CLI：更正的子命令（名稱實作時定，寫進 `docs/rulings/mcp-cli-parity.md`），加進 `Sources/akashic/CLI.swift` 的 subcommands；`store-source` 人可讀分支那一句改指向它；doctor 的新一類
- [ ] 2.5 MCP：更正的工具；`tools/list` 的位元組預算由 `StdioE2ETests.testToolsListResponseStaysWithinByteBudget` 量（上限 65,000；超過要回 #578 重新裁決，不得自行調高）
- [ ] 2.6 `Sources/akashic/WriteGateRulings.swift`：新命令一格。建議 `.gated`：它在既有的 store 資料上加一筆會改變讀法的陳述（與 `store-source` 的「同一份內容冪等、不改寫任何記錄」不同類）；`WriteGateRulingsTests` 要綠
- [ ] 2.7 `ToolPayloadScenarios`、`ToolPayloadLegs`：新工具的情境；`akashic_update_entry` 的 `sourcesAdded[]`（在 `ToolPayloadNestedPaths` 的封閉表裡）多出的鍵要寫進說明或具名豁免；`ToolPayloadKeyGuardTests`、`ToolPayloadLegTests` 要綠

## 3. 文件與裁決表 [after: 2.7]

- [ ] 3.1 `docs/store-format.md`：更正列的形狀、現行列的算法、只增不改不變；Q4 照建議時版本表加一列（寫明是語意上的 bump）
- [ ] 3.2 `docs/rulings/mcp-cli-parity.md`：新工具一列（跑該規則〈怎麼機械檢查這張表真的封閉〉的稽核）
- [ ] 3.3 `docs/rulings/two-kinds-of-edits.md`：更正入口歸「程式」（落地；「哪一句才對」的判定在寫的人，理由欄就是它的依據，比照第 39 行 `update-entry --add-source` 那一列）
- [ ] 3.4 `plugin/skills/akashic-bootstrap/references/writing-to-the-store.md`：note 寫錯時用更正入口，不手改 index；`plugin/skills/akashic-fetch-fulltext/SKILL.md` 第 6 步提到 note 的地方指向它
- [ ] 3.5 `plugin/CHANGELOG.md`、`.githooks/plugin-shell-versions.txt`、`changelog/<日期>-source-provenance-correction-824.md`

## 4. 驗證 [after: 3.5]

- [ ] 4.1 `swift build -Xswiftc -warnings-as-errors`、全套 `swift test`、`bash .githooks/run-guards.sh`、`spectra validate idd-824-source-provenance-correction` 都通過
- [ ] 4.2 用一份 store 副本（不是使用者的 store）重演 #824 的兩筆：寫更正、`update-entry --add-source` 乾跑看到現行 note 與原文
