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

bash plugin/tests/rule-coverage.sh
# 逐條重建審查者宣稱的失敗情境——一條 finding 若重建不出它宣稱的失敗，
# 那條就是未經量測的（#407 R10 的九條裡有一條正是如此）。
bash plugin/tests/review-claim-audit.sh
python3 plugin/tests/rule-prose-guards.py --venue Sources/AkashicCore/Venue.swift
python3 plugin/tests/rule-prose-guards-mutations.py
bash plugin/skills/akashic-literal-campaign/scripts/tests/hash-table-drift.sh
# 表是逐 code point 的——這支證明對「# + 多 scalar 序列」那樣就夠
# （12 種序列零分歧；理由見該檔）。
swift plugin/skills/akashic-literal-campaign/scripts/tests/multiscalar-parity.swift
bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh
python3 plugin/skills/akashic-literal-campaign/scripts/tests/marker-parity-mutations.py
# 觸發點自己的守衛：每個受保護檔案改動時，讀它的守衛真的會跑起來嗎？
# 判準是**逐對**而非聯集——CLAUDE.md 那張手寫的觸發點表由它量。
python3 plugin/tests/trigger-coverage.py
python3 plugin/tests/trigger-coverage-mutations.py
# 那張四列判準表的現查（#407 R26b）——表自己的四個宣稱也是可否證的。
# 語法相容性要**最先**跑（#394 verify R9）：它便宜（秒級）,而它防的失效會讓
# 後面任何一支守衛在 hook 裡變成 SyntaxError——那個症狀極具誤導性。
python3 plugin/tests/guard-python-compat.py
python3 plugin/tests/measured-claims-audit.py
# CLAUDE.md 的 pre-push 決策矩陣：宣稱值 vs 由兩條語意規則現算的值。
# 那張表錯過一次（R26q），而那個錯撐過了好幾輪人＋AI 審查——散文沒人檢查。
python3 plugin/tests/decision-matrix-drift.py
python3 plugin/tests/decision-matrix-mutations.py
# rule-coverage 與 hash-table-drift 的 negative control（#407 R32）——它們先前
# 每次都綠而從沒紅過，落在本 issue 自己的立場之外。
python3 plugin/tests/audit-guards-mutations.py
python3 plugin/tests/oracle-precondition-control.py
# 規則檔裡的「實測 N」必須有時間錨或可重跑的指令（#407 R36）。
python3 plugin/tests/measured-numbers-audit.py
# mcp-cli-parity.md 的封閉列舉 vs 程式碼實際有的東西（#407 R50）——那條規則自帶的
# 稽核程序先前從來沒人跑。
python3 plugin/tests/parity-table-drift.py
# entity-backlink-completeness.md 的 14 條邊：新的非純量欄位必須先被裁決（#407 R51）。
# 那張表錯過三次，而它的第 ③ 步是人的判斷——本支只做棘輪，不代做裁決。
python3 plugin/tests/backlink-field-ratchet.py
# zero-instance-guards.md 的裁決表：裁決「寫」的那些列，守衛真的存在嗎（#407 R55）。
# **Swift 版**（#433 A 批第 1 支）。Python 版留在樹裡當 oracle,通過整批驗證後才刪
# ——`guards-python-final` 這個 tag 是參照點,但 oracle 要能**跑**（第 3a 步要兩版
# 在同一批 mutation 上逐一比對）。實測:乾淨樹 ＋ 四個 mutation,輸出**逐字相同**。
.build/debug/akashic-guards zero-instance-rows-audit
# census 抽 `literal:` 值的解碼 vs YAML 純量語義（#407 R62）——distinct literal 是
# 整個 campaign 的分母，而它先前 8 種寫法有 7 種分岔。
python3 plugin/tests/literal-scalar-parity.py

