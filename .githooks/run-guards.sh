#!/bin/bash
# **唯一的守衛清單**（#432）。三個消費者共用它：
#
#   1. `.githooks/pre-push`（第三階段）
#   2. `.github/workflows/plugin-guards.yml`
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
# 「為什麼」也說不出「怎麼修」。`plugin-guards.yml` 跑在 **ubuntu**（無 Swift
# toolchain），所以 CI 恢復後它必然走到這裡；讓它講清楚，而不是留一個看起來像
# 路徑打錯的訊息。
if [ ! -x .build/debug/akashic-guards ]; then
  echo "✗ .build/debug/akashic-guards 不存在或不可執行。"
  echo "  9 支守衛已遷成它的子命令（#433），先跑："
  echo "      swift build --product akashic-guards"
  echo "  （CI：本腳本現在需要 Swift toolchain——ubuntu runner 尚未具備，見 #435）"
  exit 1
fi

bash plugin/tests/rule-coverage.sh
# 逐條重建審查者宣稱的失敗情境——一條 finding 若重建不出它宣稱的失敗，
# 那條就是未經量測的（#407 R10 的九條裡有一條正是如此）。
bash plugin/tests/review-claim-audit.sh
# **Swift 版**（#433 C 批 1/3）。驗證：乾淨樹逐位元相同、負控的 **14 個 case 兩版並驗**
# （`rule-prose-guards-mutations.py` 對每個 case 同時跑兩版並要求 stdout 與 rc 逐字相同）。
# 這支不需要 source-injection 豁免：mutation 只作用在 copy 的 plugin 樹上，守衛在原位。
.build/debug/akashic-guards rule-prose-guards --venue Sources/AkashicCore/Venue.swift
python3 plugin/tests/rule-prose-guards-mutations.py
bash plugin/skills/akashic-literal-campaign/scripts/tests/hash-table-drift.sh
# 表是逐 code point 的——這支證明對「# + 多 scalar 序列」那樣就夠
# （12 種序列零分歧；理由見該檔）。
swift plugin/skills/akashic-literal-campaign/scripts/tests/multiscalar-parity.swift
bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh
python3 plugin/skills/akashic-literal-campaign/scripts/tests/marker-parity-mutations.py
# 觸發點自己的守衛：每個受保護檔案改動時，讀它的守衛真的會跑起來嗎？
# 判準是**逐對**而非聯集——CLAUDE.md 那張手寫的觸發點表由它量。
# **Swift 版**（#433 B 批 4/4，全樹最大的一支 846 行）。驗證：乾淨樹逐位元相同、
# 19 個手動 mutation、**負控的 30 個 case 兩版並驗**（`trigger-coverage-mutations.py`
# 對每個 case 同時跑兩版並要求輸出逐字相同；另 2 個 case 注入守衛自己的原始碼，
# Swift 側結構上測不到，harness 會把它們彙總印出而不靜默）。
# 另含 `shlex(posix, punctuation_chars)` 的等價實作，差分測試 63 個 case 逐 token 相同。
.build/debug/akashic-guards trigger-coverage
python3 plugin/tests/trigger-coverage-mutations.py
# 那張四列判準表的現查（#407 R26b）——表自己的四個宣稱也是可否證的。
# 語法相容性要**最先**跑（#394 verify R9）：它便宜（秒級）,而它防的失效會讓
# 後面任何一支守衛在 hook 裡變成 SyntaxError——那個症狀極具誤導性。
python3 plugin/tests/guard-python-compat.py
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
# rule-coverage 與 hash-table-drift 的 negative control（#407 R32）——它們先前
# 每次都綠而從沒紅過，落在本 issue 自己的立場之外。
python3 plugin/tests/audit-guards-mutations.py
python3 plugin/tests/oracle-precondition-control.py
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
# census 抽 `literal:` 值的解碼 vs YAML 純量語義（#407 R62）——distinct literal 是
# 整個 campaign 的分母，而它先前 8 種寫法有 7 種分岔。
# **Swift 版**（#433 C 批 3/3——C 批完成）。乾淨樹逐位元相同，負控進 `MIGRATED` 兩版並驗。
# **它仍 spawn `python3`**，而那不是遷移沒做完：被測的東西**就是** census.sh 內嵌的 Python
# 函數（該檔 598 行裡 573 行是內嵌 Python）。用 Swift 重寫一份等價解碼，驗的就變成我寫的
# 那份，而不是實際在跑的那份。
.build/debug/akashic-guards literal-scalar-parity

