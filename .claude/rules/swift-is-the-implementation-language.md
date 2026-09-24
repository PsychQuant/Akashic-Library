# 實作語言是 Swift：新的程式一律寫成 Swift

使用者 2026-09-24（+08:00）定調：「你可以在專案的 claude.md 跟 .claude/rules 裡面都寫要用 swift」。
起因是同一天的問句「Akashic-Library 的本體我是不是有改成 swift?」——答案是是，而我剛在 #625
用 Python 寫了一支 repo 層級的守衛。

**本 repo 的本體是 Swift**：核心 package AkashicKit（`Package.swift`）、`akashic` CLI、
`akashic-mcp` server、`akashic-guards` 守衛全部是 Swift。守衛在 #433 從 Python 遷成 Swift，
理由是「單一 toolchain 消除版本歪斜」。本規則把那個方向從「守衛」擴大到「所有新的程式」。

## 規則

**新增的可執行程式碼一律寫成 Swift，並放進下表其中一處。** 這是封閉列舉，只有四列；
遇到表裡沒有的情形，依 `CLAUDE.md`〈Rules〉第 3 條**加一列**，不要從既有列推導。

| 要寫的東西 | 放在哪裡 | 理由 |
|---|---|---|
| 守衛與它的負對照 | `akashic-guards` 的子命令；檔名依子命令名的 PascalCase（`plugin-roots` → `PluginRoots.swift`） | 受保護清單以這個對應找出 Swift 守衛（`swiftGuards()`）；檔名不符的守衛不受保護 |
| 使用者可呼叫的能力 | `akashic` CLI 子命令及／或 `akashic-mcp` tool，兩面依 [mcp-cli-parity.md](mcp-cli-parity.md) 裁決 | 能力只有一份實作，CLI 與 MCP 共用 `Sources/` 的型別與 store IO |
| plugin skill 需要的確定性計算（驗證、比對、轉換、評分） | `akashic` CLI 子命令，skill 以指令呼叫它 | skill 目錄裡的腳本會重寫一份 store 已有的邏輯，兩份會分岔；CLI 隨 release 發布，使用者端不需要另一個 runtime |
| 測試 | `Tests/` 的 Swift test target；守衛的負對照寫成 `*-mutations` 子命令 | 與被測程式同一個 toolchain，版本不會歪斜 |

## 例外：可以不是 Swift 的檔案（封閉列舉，只有兩類，不得依性質相似類推第三類）

1. **在 Swift binary 存在之前就得先跑、或本身是外部工具約定入口的殼層**。目前恰為四個檔：
   `.githooks/pre-push`、`.githooks/run-guards.sh`（git hook 與守衛入口）、
   `plugin/bin/akashic-mcp-wrapper.sh`（下載 server binary）、`scripts/release-signed.sh`
   （編排 `codesign`／`notarytool`）。**它們只做串接**——檢查 binary、依序呼叫、下載、編排外部
   CLI。領域判斷一旦出現在裡面，就移進 Swift。
2. **本規則成文前已存在的檔（grandfathered）**，逐檔列在下方〈既有檔〉。可以修 bug、可以
   小改；**不得在它們旁邊新增同類檔案**，也不得把新功能長在它們裡面。大幅改寫時移植成
   上表的 Swift 形式。

## 不適用（同樣是封閉列舉，只有四類）

1. **`SKILL.md` 與文件裡給模型或人照著執行的指令列**——呼叫 `akashic`、`safari-browser`、
   `pdftotext`、`gh` 等。那是使用工具，不是在 repo 裡新增程式。
2. **被呼叫的外部工具本身**——它們用什麼語言寫不歸本 repo 管。
3. **`repos/` 底下的 submodule**——各自是獨立的 repo。
4. **不 commit 的一次性量測腳本**——放暫存目錄、量完即丟；要留下來重跑的，就不是一次性的，
   依上表寫成 Swift。

## 既有檔（grandfathered，2026-09-24 量，tracked）

**shell（七個，不含例外 1 的四個）**：
`plugin/skills/akashic-fetch-fulltext/scripts/fetch-fulltext.sh`、
`plugin/skills/akashic-fetch-fulltext/scripts/tests/fetch-fulltext-paths.sh`、
`plugin/skills/akashic-promote-literals/scripts/literal-census.sh`、
`plugin/skills/akashic-promote-literals/scripts/tests/hash-table-drift.sh`、
`plugin/skills/akashic-promote-literals/scripts/tests/store-marker-parity.sh`、
`plugin/tests/review-claim-audit.sh`、`plugin/tests/rule-coverage.sh`

**Python（十一個）**：
`plugin/skills/akashic-bootstrap/scripts/crossref_match.py`、
`plugin/skills/akashic-fetch-fulltext/scripts/{bot_signals,calibrate_title_match,jitter,pdf_url_rules,verify_pdf}.py`、
`plugin/skills/akashic-fetch-fulltext/scripts/tests/test_rules_and_verify.py`、
`plugin/skills/akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py`、
`plugin/tests/ndjson-abstracts-to-proposals.py`、`plugin/tests/plugin-store-format-parity.py`、
`scripts/scan-yaml-profile.py`

這張清單只減不增：檔案移植成 Swift 或刪除時從這裡拿掉，新檔不得加進來。

## 為什麼

1. **本體已經是 Swift**。store 的型別、YAML 規範形、store IO、身分解析都在 `Sources/`。
   在 skill 裡用 Python 做同一件事，要嘛重寫一份（會與 Swift 版分岔），要嘛繞回去呼叫 CLI——
   後者本來就是上表的第三列。
2. **兩個 toolchain 會歪斜**。#394 踩過：守衛用了 Python 3.12 才有的語法，CI runner 上跑不動。
   #433 把守衛遷成 Swift 就是為了消除這一類問題。
3. **受保護清單只認得 Swift 守衛的命名對應**。Python 守衛只有放在 `plugin/tests/` 才會被
   glob 看見；放在別處，被刪或沒接線都不會有任何守衛出聲。

## 觸發過的實例

| 日期 | 實例 | 處置 |
|---|---|---|
| 2026-09-24 | #625：官方 plugin 驗證守衛第一版寫成 `plugin/tests/official-validate.py`，與 #433 的方向相反；使用者問「本體是不是改成 swift」才發現 | 同一輪改寫成 `akashic-guards official-validate`（`OfficialValidate.swift`），四個情境（實際 repo、未知欄位、允許清單過期、沒有 CLI）輸出與 Python 版一致 |
| 2026-09-23～24 | akashic-fetch-fulltext skill 新增 5 支 Python 與 1 支 Python 測試（`verify_pdf.py` 等），在本規則成文之前 | 列入〈既有檔〉；移植成 `akashic` CLI 子命令由 #629 追蹤 |

## 語言組成（2026-09-24 量，tracked，排除 `repos/`、`docs/`、`changelog/`、`openspec/`）

Swift 372、Python 11、shell 11（含沒有副檔名的 `.githooks/pre-push`）。量法：
`git ls-files` 依副檔名計數。數字會隨移植下降，以重量為準，不要照抄這一行。
