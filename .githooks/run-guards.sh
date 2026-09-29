#!/bin/bash
# **唯一的守衛清單**（#432）。三個消費者共用它：
#
#   1. `.githooks/pre-push`（第三階段）
#   2. `.github/workflows/census-parity.yml` 的 step「全部守衛（與 pre-push 同一份清單；本 runner 有 Swift）」
#      （先前是 `plugin-guards.yml`，已於 `40977531` 刪除——#435；#626 更正本清單）
#   3. 手動執行（`bash .githooks/run-guards.sh`）
#
# **為什麼抽出來**：先前 hook 與 CI **各自列出 21 支守衛**——那是兩份會分岔的規格，
# 而本 repo 反覆記過這個形狀。實測踩到過：#394 R9 加 `guard-python-compat.py` 時
# 得分別改兩個檔案，`trigger-coverage.py` 在我漏掉 CI 那份時立刻叫了。
#
# **順帶解掉 #432**：`PrePushHookTests` 會在測試裡跑一次 hook。先前那次會**重跑整批
# 守衛**（43 分鐘），而外層 hook 兩分鐘後又跑一次同一批、讀同一個工作樹、得同一個
# 結果——純浪費。現在 hook 只在 `AKASHIC_PRE_PUSH_STAGES` 未排除 guards 時才呼叫本檔。
#
# `set -eo pipefail` 與 hook 同——任何一支非零就中止（#129 verify 的教訓）。
set -eo pipefail

# **9 支守衛已遷成 `akashic-guards` 的子命令（#433），它們需要先 build。**
#
# 沒有這個檢查的話，失敗訊息是 shell 的 `No such file or directory` ——那說不出
# 「為什麼」也說不出「怎麼修」。寫下這段時的 CI 消費者 `plugin-guards.yml` 跑在 **ubuntu**
# （無 Swift toolchain），CI 恢復後必然走到這裡；那個 workflow 已於 `40977531` 刪除（#435），
# 現在的 CI 消費者 `census-parity.yml` 跑在 macOS、會先 build。檢查留著，是為了手動執行
# 或新 runner 沒先 build 時，訊息仍說得出為什麼、怎麼修。
if [ ! -x .build/debug/akashic-guards ]; then
  echo "✗ .build/debug/akashic-guards 不存在或不可執行。"
  echo "  9 支守衛已遷成它的子命令（#433），先跑："
  echo "      swift build --product akashic-guards"
  echo "  （CI：本腳本需要 Swift toolchain 並先 build；現行的 census-parity.yml 跑在 macOS、會先 build——見 #435、#626）"
  exit 1
fi

# #625：rule-coverage 逐個 plugin 根跑。根目錄清單只有 `akashic-guards plugin-roots`
# 那一份，這裡不另存。清單為空要紅——否則迴圈跑零次、照樣綠燈。
plugin_roots=$(.build/debug/akashic-guards plugin-roots)
[ -n "$plugin_roots" ] || { echo "✗ akashic-guards plugin-roots 沒有輸出任何根"; exit 1; }
# #629：原為 `bash plugin/tests/rule-coverage.sh "$root"`，現在是同名子命令（呼叫形狀不變：root 是 repo 相對路徑）。
for root in $plugin_roots; do
  .build/debug/akashic-guards rule-coverage "$root"
done
# #625：官方 plugin／marketplace 驗證（`--json` ＋ 只有一項的封閉允許清單，理由在
# `OfficialValidate.swift` 開頭）。沒有 claude CLI 時（CI runner）印出略過——不靜默。
.build/debug/akashic-guards official-validate
# #689：它的負對照。用假的 `claude` 印出錯的報告，所以 CI runner（沒有 claude CLI）上每一格也都會跑。
.build/debug/akashic-guards official-validate-mutations
# （原本這裡有 `bash plugin/tests/review-claim-audit.sh`——逐條重建 #407 R10 審查者宣稱的失敗情境。#629 移除它：
#  九條 finding 的受測物（`literal-census.sh` 的探測寫法、`store-marker-parity.sh` 的 5000 前導零 fixture、
#  parity workflow 的生成表 paths、`derive-hash-extenders.swift` 的假 `--check`）隨 census 移植成 Swift 而全部不存在，
#  剩下的只是對 sed／printf／seq 行為的示範，不守任何 repo 內的東西。逐條處置見 `changelog/2026-09-29-guards-and-census-to-swift.md`。）
# **Swift 版**（#433 C 批 1/3）。遷移當時的驗證是乾淨樹逐位元相同、負控兩版並驗；Python 版已退場（`989ac64`），現在的負控見下方的
# `rule-prose-guards-mutations`。
# 這支不需要 source-injection 豁免：mutation 只作用在 copy 的 plugin 樹上，守衛在原位。
.build/debug/akashic-guards protected-ratchet
.build/debug/akashic-guards workflow-run-scripts
.build/debug/akashic-guards rule-prose-guards --venue Sources/AkashicCore/Venue.swift
# #644：第 1、2 項（repo 專屬路徑不可跟隨、要在同一行揭露）對每個 plugin 根都跑；上一行已涵蓋 `plugin`（五項全跑；第 6 項於 #629 移除），
# 其餘的根只跑那兩項——第 3–5 項綁著 `plugin/` 專屬的內容。根的清單同樣只取自 `plugin-roots`。
for root in $plugin_roots; do
  [ "$root" = plugin ] && continue
  .build/debug/akashic-guards rule-prose-guards --root "$root" --prose-only
done
# **Swift 版**（#433，第二支遷移的 harness）。乾淨樹逐位元相同（19 行、rc=0）。
# case 數以它印的 `negative control N/N` 為準（#644 起含一格 plugin/ 以外的根、一格不存在的根；#629 移除第 6 項的 case 後數字下降，
# 2026-09-29 實測 14/14，先前這裡與 changelog 寫 15）＋ 一個注入 PoC（不只看守衛紅不紅，還看**副作用有沒有發生**）。
.build/debug/akashic-guards rule-prose-guards-mutations
# （原本這裡有 census 的四件套：`hash-table-drift.sh`、`multiscalar-parity.swift`、`store-marker-parity.sh`、
#  `marker-parity-mutations`。#629 移除：census 改成 `akashic literal-census`，marker 直接呼叫 `StoreVersion.read`——
#  「兩份實作會不會分岔」的命題結構上不再成立。那張 46 格的 fixture 矩陣與 `_scalar` 的解碼對照搬進了
#  `Tests/AkashicKitTests/StoreMarkerMatrixTests.swift` 與 `LiteralCensusTests.swift`。）
# 觸發點自己的守衛：每個受保護檔案改動時，讀它的守衛真的會跑起來嗎？
# 判準是**逐對**而非聯集——CLAUDE.md 那張手寫的觸發點表由它量。
# **Swift 版**（#433 B 批 4/4，全樹最大的一支 846 行）。驗證：乾淨樹逐位元相同、
# 19 個手動 mutation、**負控的 case**（`trigger-coverage-mutations` 子命令）。
#
# 上一版這裡寫「30 個 case 兩版並驗（`trigger-coverage-mutations.py`…）／對每個 case 同時跑
# 兩版並要求輸出逐字相同」——**那段有三個都不成立的東西**：那個 `.py` 在 `989ac64` 已刪、
# 兩版並驗（Python 當 oracle）隨它一起退場、格數也早就不是 30。#521 的第一輪只改了前半句、
# 留著後半句描述那個已退場的機制，相鄰兩行互相矛盾（R2 verify，Codex 席指名）。整段重寫。
# **不寫死格數**：它每輪都在長。
# 另含 `shlex(posix, punctuation_chars)` 的等價實作，差分測試 63 個 case 逐 token 相同。
.build/debug/akashic-guards trigger-coverage
# **Swift 版**（#433，第四支遷移的 harness）。mutation 的格數以它印的 `negative control N/N` 為準（不寫死：它隨 case 增減，
# 這裡先前寫的「32 個（26 case ＋ 6 warn_case）」在 #629 時已是 37）。字串**機械抽出不手抄**（`TriggerCoverageMutationsData.swift`）——它們全是
# `t.replace(字面, 字面)`，而 harness 斷言注入必須真的改到東西，手抄一個空白之差會讓
# case 靜默失效而輸出看起來像「被注入的檔案改了」。
.build/debug/akashic-guards trigger-coverage-mutations
# #625：檔案系統上的 plugin 根與 marketplace manifest 雙向一致（五類封閉列舉），
# 以及 plugin/ 以外的根真的被守衛看見的負對照（每格含對照組）。
.build/debug/akashic-guards marketplace-consistency
.build/debug/akashic-guards plugin-roots-mutations
# #664：網路與 keychain API（九個字樣的封閉列舉）只准出現在 Sources/AkashicS2/，及其負對照（九個字樣各注入一次）。
.build/debug/akashic-guards network-confinement
.build/debug/akashic-guards network-confinement-mutations
# 那張四列判準表的現查（#407 R26b）——表自己的四個宣稱也是可否證的。
# 語法相容性要**最先**跑（#394 verify R9）：它便宜（秒級）,而它防的失效會讓
# `guard-python-compat.py` 已退場（#433 Step 5）：它的存在理由是「Python 守衛要能在
# system 3.9 跑」，而現在沒有 Python 守衛了。
# **Swift 版**（#433 C 批 2/3）。驗證：乾淨樹逐位元相同（29 行、rc=0），負控在
# `audit-guards-mutations.py` 的 `MIGRATED` 表裡兩版並驗。
# **注意**：本支有 case 注入守衛**自己的原始碼**，Swift 側結構上測不到（harness 會把
# 那幾格彙總印出，不靜默）——它們目前只驗了 Python 版。
.build/debug/akashic-guards measured-claims-audit
# CLAUDE.md 的 pre-push 決策矩陣：宣稱值 vs 由兩條語意規則現算的值。
# 那張表錯過一次（R26q），而那個錯撐過了好幾輪人＋AI 審查——散文沒人檢查。
# **Swift 版**（#433 A 批 2/2）。實測:乾淨樹 ＋ 五個 mutation,輸出**逐字相同**。
.build/debug/akashic-guards decision-matrix-drift
# 每支**實際在跑**的 Swift 守衛，都有 negative control 在驗它嗎（#433）？
# 這個形狀已經踩過三次——兩次修了、第三次（`decision-matrix-drift`，A 批第一支、
# 負控是獨立 harness 而不在 `MIGRATED` 表裡）在我修完前兩個之後**仍然漏掉**。
# 一條記在散文裡的紀律擋不住它：它要求人每次遷移都想起來，而我沒有。
.build/debug/akashic-guards migrated-guard-control
# **Swift 版**（#433，第一支遷移的 harness）。乾淨樹逐位元相同（17 行、rc=0）。
# 它自己就是 `decision-matrix-drift` 的負控，並在 `runBoth` 裡對每個 case 同時跑守衛的
# 兩版、要求輸出逐字相同——刪掉 Python 守衛時把那一半拿掉即可。
.build/debug/akashic-guards decision-matrix-mutations
# rule-coverage 的 negative control（#407 R32；#629 起 hash-table-drift 已隨 census 退場，只剩前者）——它先前
# 每次都綠而從沒紅過，落在本 issue 自己的立場之外。
# **Swift 版**（#433，最大的一支 835 行）。52 個 case 機械抽出＋**自我驗證**（抽出的
# edits 套用結果必須與原 lambda 逐字相同）——那道驗證當場抓到兩個會靜默的抽取缺陷：
# 丟掉 `count` 引數（5 個 case 換錯範圍）、鏈式 replace 只抽最外層（2 個 case 注入不完整）。
.build/debug/akashic-guards audit-guards-mutations
# **Swift 版**（#433）。它 monkey-patch 不了 harness（Swift 沒那個機制），改用
# **環境變數 ＋ subprocess**——好處是它跑的是**真的出貨路徑**。三個注入變數帶 `AKASHIC_`
# 前綴、在被注入處具名、**未設定時完全沒有行為**（實測：輸出與 Python 版逐位元相同）。
.build/debug/akashic-guards oracle-precondition-control
# 規則檔裡的「實測 N」必須有時間錨或可重跑的指令（#407 R36）。
# **Swift 版**（#433 B 批 3/4）。乾淨副本 ＋ **12 個 mutation**（三個負向:fence 內、
# 四位數年份、有錨即不報）,輸出**逐字相同**。契約交叉核對另確認三處**理由**而非行為
# 的一致:40 行表格視窗、`[i-4, i+8)` 指令視窗、以及 `countRe` 的字元類**刻意比**
# `digits` 認得的寬（否則「解析不出要報」那條路徑不可達,#407 R67i）。
.build/debug/akashic-guards measured-numbers-audit
# mcp-cli-parity.md 的封閉列舉 vs 程式碼實際有的東西（#407 R50）——那條規則自帶的
# 稽核程序先前從來沒人跑。
# **Swift 版**（#433 B 批 1/4）。實測:乾淨副本 ＋ 四個 mutation,輸出**逐字相同**。
# 註:Swift 版用 **cwd** 定位 repo,Python 版用 `__file__`——後者讓它在複製出來的
# 樹上仍讀**原始** repo。比對 harness 因此必須呼叫**副本裡的**那份 .py（我第一次
# 呼叫原始路徑,四個 mutation 全部 py=0,看起來像 Swift 版報假警,實際是 harness 的 bug）。
.build/debug/akashic-guards parity-table-drift
# entity-backlink-completeness.md 的 14 條邊：新的非純量欄位必須先被裁決（#407 R51）。
# 那張表錯過三次，而它的第 ③ 步是人的判斷——本支只做棘輪，不代做裁決。
# **Swift 版**（#433 B 批 2/4）。乾淨副本 ＋ 四個 mutation,輸出**逐字相同**。
# 113 個已裁決欄位由 Python 版 `ast.literal_eval` **機械抽取**——兩版的清單同源。
.build/debug/akashic-guards backlink-field-ratchet
# zero-instance-guards.md 的裁決表：裁決「寫」的那些列，守衛真的存在嗎（#407 R55）。
# **Swift 版**（#433 A 批第 1 支）。Python 版留在樹裡當 oracle,通過整批驗證後才刪
# ——`guards-python-final` 這個 tag 是參照點,但 oracle 要能**跑**（第 3a 步要兩版
# 在同一批 mutation 上逐一比對）。實測:乾淨樹 ＋ 四個 mutation,輸出**逐字相同**。
.build/debug/akashic-guards zero-instance-rows-audit
# （原本這裡有 `literal-scalar-parity`——census 抽 `literal:` 值的解碼 vs YAML 純量語義（#407 R62）。#629 移植成
#  `LiteralCensusTests.testScalarDecoderAgreesWithYams`：census 現在是 Swift，解碼函數可以直接呼叫，
#  oracle 是 Yams（store 讀端本來就用它），不必再從 shell 檔裡抽出 Python 函數來 spawn。）


# plugin.json 的 description 宣告 store format，而它與 `StoreVersion.supported`
# 是同一份規格的**三個**副本（第三份是出貨物 `mcpb/manifest.json`，
# `release-signed.sh` 會 zip 進 .mcpb）。實測三次漂移零次被發現（#408）。
#
# **這支原本是 Python**（`plugin/tests/plugin-store-format-parity.py`）——#433 的 16 支遷完之後 main 才長出它（#408），
# 所以它不在那批裡；當時的判斷是「只讀三個檔的文字、不需要 build，遷成 Swift 得不到任何東西」。#629 起
# `swift-is-the-implementation-language` 規定新的程式一律是 Swift，且它現在與其餘守衛住在同一個 binary 裡，
# 所以移植成 `akashic-guards plugin-store-format-parity`（判定不變；負控在 `AuditGuardsMutationsData.swift`）。
.build/debug/akashic-guards plugin-store-format-parity

# （#629：原本這裡有三條 skill 腳本的測試——`plugin/tests/ndjson-abstracts-to-proposals.py`（階段 B 摘要 → 提案的 fixture）、
#  `akashic-fetch-fulltext/scripts/tests/test_rules_and_verify.py`（54 個純函式測試）、`fetch-fulltext-paths.sh`（對 stub 瀏覽器的
#  19 條路徑）。受測物都移植成 `akashic` 的子命令（`Sources/AkashicSkillTools/`），測試成為 Swift 測試——
#  `AbstractProposalsTests`、`FulltextRulesTests`（54 個逐案移植）、`FulltextFetchPathTests`（對記憶體內的假瀏覽器跑同樣 19 條路徑，
#  `SafariBrowser` 介面讓中止條款的每個出口都能在測試裡逐條斷言）、`CrossrefMatchTests`、`TitleCalibrationTests`、
#  `SkillToolsCLITests`——由 pre-push 的 `swift test` 跑，不再需要這裡。**最要緊的一條反例照樣被釘住**：付費牆的 Loading 殼
#  不得被當成起疑（`BotSignalsTests.testPaywallLoadingShellIsNotSuspicion`、`FulltextFetchPathTests.testPaywallShellIsNoAccess`）。）
