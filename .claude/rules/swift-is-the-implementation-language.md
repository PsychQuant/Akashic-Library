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

## 不適用（同樣是封閉列舉，只有五類）

1. **`SKILL.md` 與文件裡給模型或人照著執行的指令列**——呼叫 `akashic`、`safari-browser`、
   `pdftotext`、`gh` 等。那是使用工具，不是在 repo 裡新增程式。
2. **被呼叫的外部工具本身**——它們用什麼語言寫不歸本 repo 管。
3. **`repos/` 底下的 submodule**——各自是獨立的 repo。
4. **不 commit 的一次性量測腳本**——放暫存目錄、量完即丟；要留下來重跑的，就不是一次性的，
   依上表寫成 Swift。
5. **`docs/skill-evals/**/skill-snapshot-*/` 底下的舊 skill 快照**（2026-09-29 #629 R1 加入，使用者可翻）。目前恰一個：
   `docs/skill-evals/akashic-bootstrap-workspace/skill-snapshot-old/scripts/crossref_match.py`。它是評測 A／B 比對用的**基準線**——
   當時的 skill 長什麼樣子（含它自己以 `urllib` 直連 Crossref 的腳本）就是被比較的東西；刪掉它、或移植它，會讓基準線失去意義。它不被
   任何 skill、CLI、守衛或測試執行。**第一版把這件事寫成一節〈誰沒被「移植」〉而沒有加進這張封閉列舉**（R1 verify 第 44 則：那是在
   列舉之外新增第五類卻不改列舉）；現在顯式加列。判準不是「凡是 `docs/` 底下的都不適用」——**只有凍結的評測快照**；`docs/` 底下若有
   會被執行的腳本，它仍然適用本規則。要推翻這一列：刪掉那個快照檔，並把本列與〈誰沒被「移植」〉一併拿掉。

## 既有檔（grandfathered，2026-09-24 量，tracked）

**2026-09-29（#629 第二塊移植後）：清單是空的。** shell 與 Python 各為零個既有檔；例外 2 的「逐檔列在這裡」目前沒有任何成員。
成文當日（2026-09-24）是 shell 七個（不含例外 1 的四個）、Python 十一個；第一塊（守衛與普查）拿掉了其中的 shell 五個、Python 二個，
第二塊（下面）拿掉其餘的。這張清單只減不增——**空了之後，新檔更不得加進來**（例外 2 是為「成文前已存在」的檔開的，不是一扇會再開的門）。

**已移植（#629 第一塊，2026-09-29）**：`plugin-store-format-parity.py`、`rule-coverage.sh`、`review-claim-audit.sh`、
`scan-yaml-profile.py`、promote-literals 的四支 shell（`literal-census.sh` ＋ 三支守它的測試）已從清單拿掉——
去處與理由見 `changelog/2026-09-29-guards-and-census-to-swift.md`（兩個守衛成為 `akashic-guards` 子命令、普查成為
`akashic literal-census`、YAML profile 掃描成為 `akashic scan-yaml-profile`；`review-claim-audit` 與 census 的
parity 測試不是「移植」而是**受測物不存在後退場**）。

**已移植（#629 第二塊，2026-09-29）**：`akashic-fetch-fulltext` 的 `scripts/`（`verify_pdf.py`、`pdf_url_rules.py`、`bot_signals.py`、
`jitter.py`、`calibrate_title_match.py`、`fetch-fulltext.sh`、`tests/test_rules_and_verify.py`、`tests/fetch-fulltext-paths.sh`）、
`akashic-bootstrap/scripts/crossref_match.py`、`akashic-venue-works/scripts/ndjson-abstracts-to-proposals.py` 與它的測試
`plugin/tests/ndjson-abstracts-to-proposals.py`——去處與新舊比對的證據見 `changelog/2026-09-29-fulltext-scripts-to-swift.md`。對映：

| 舊檔 | 新去處 |
|---|---|
| `verify_pdf.py`、`pdf_url_rules.py`、`bot_signals.py`、`jitter.py` | `akashic fulltext verify`／`url-rule`／`bot-signals`／`jitter`（`Sources/AkashicSkillTools/`） |
| `calibrate_title_match.py` | `akashic fulltext calibrate`（Crossref 記錄改讀本機目錄，**不連網**） |
| `fetch-fulltext.sh` ＋ `fetch-fulltext-paths.sh` | `akashic fulltext fetch`（`FulltextFetch`，對 `SafariBrowser` 介面編排；路徑測試對記憶體內的假瀏覽器跑） |
| `crossref_match.py` | `akashic crossref-match`（重播式：缺的請求由 skill 經 safari-browser 取回，**不連網**） |
| `ndjson-abstracts-to-proposals.py` ＋ 它的測試 | `akashic abstracts-to-proposals`（`AbstractProposals`） |
| `test_rules_and_verify.py`（54 個） | `Tests/AkashicKitTests/FulltextRulesTests.swift`（54 個逐案移植） |

**`fetch-fulltext.sh` 與 `fetch-fulltext-paths.sh` 沒有改列為例外 1，而是移進 Swift**（issue 的判準是「純串接者可改列為例外、含判斷者移進 Swift」）。
判斷的依據：領域判斷（起疑訊號、出版商網址規則、驗證）搬走之後，剩下的腳本**仍然有判斷**——每個結束碼落在哪條路徑（中止條款的 11 個出口
各自是 6 而不是 1）、「頁面沒落定」「本文是 0 位元組」「分頁跑到別的站」各算不算起疑、Loading 殼算無權限（4）而不是起疑（6）、
判定不過時檔案存成什麼名字。這些是**中止條款的政策**，不是串接；而例外 1 的定義是「只做串接——檢查 binary、依序呼叫、下載、編排外部 CLI」。
它的測試也帶著一個 Python stub 與一個 Python 產生器（內嵌在 shell 裡），留著就是把兩個 runtime 留在 skill 目錄。

## 誰沒被「移植」：`docs/skill-evals/` 底下的舊快照

`docs/skill-evals/akashic-bootstrap-workspace/skill-snapshot-old/scripts/crossref_match.py` 是評測用的**舊 skill 快照**（基準線），不是
可執行的程式碼、也不是 skill 現行的內容。它沒有動；它提到的 `scripts/crossref_match.py` 是快照當時的樣子。它屬於上面〈不適用〉第 5 類。
`.claude/rules/web-access-via-safari-browser.md` 的直連量法（只掃 `plugin/skills`、`plugins/*/skills`、`Sources`）同樣不涵蓋它，
理由相同：凍結的基準線，不被執行。

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

## 語言組成（tracked，排除 `repos/`、`docs/`、`changelog/`、`openspec/`）

**2026-09-29（#629 R1 修正後重量）**：Swift 511、Python 0、shell 4（含沒有副檔名的 `.githooks/pre-push`；恰為例外 1 的四個檔）。
第一版這裡寫 Swift 497，驗證席在同一個 commit 上重量得 501（R1 verify 第 20 則；497 是 rebase 之前量的）——**這個數字隨每個 commit 變動**（別的工作線也在加 Swift 檔），
不要照抄，重量。第一塊移植後是 472／9／6，成文當日（2026-09-24）是 372／11／11。量法：`git ls-files` 依副檔名計數，排除 `repos/`、`docs/`、`changelog/`、`openspec/`。
