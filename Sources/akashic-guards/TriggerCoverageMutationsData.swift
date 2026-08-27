// **本檔由腳本生成，不要手改。** 來源：`plugin/tests/trigger-coverage-mutations.py`
//
// **為什麼機械抽而不是手抄**（#433）：32 個 mutation 全是 `t.replace(字面, 字面)`，而
// harness 斷言注入必須真的改到東西（沒改到即該 case 無效）。手抄一個空白之差會讓 case
// 靜默失效，而輸出看起來像「被注入的檔案改了」。
//
// 重新生成：`ast` 走訪 `case`／`warn_case` 呼叫 → dict key（含用模組常數的）→
// `Lambda.body.args` 逐一 `literal_eval`。

struct TCMCase {
    let isWarn: Bool
    let desc: String
    let edits: [(path: String, old: String, new: String)]
    let expect: String
}

let triggerCoverageMutationCases: [TCMCase] = [
    TCMCase(isWarn: false, desc: "從守衛清單拿掉一支守衛",
        edits: [
            (path: ".githooks/run-guards.sh", old: "bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh\n", new: ""),
        ], expect: "store-marker-parity.sh 不在 pre-push 裡"),
    TCMCase(isWarn: false, desc: "從 workflow 的 paths 拿掉一個受保護檔",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"plugin/**\"\n", new: ""),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "從 workflow 拿掉守衛階段（整批不再被執行）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: true  # 被拿掉了"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把守衛清單裡的一支換成只提到它的註解",
        edits: [
            (path: ".githooks/run-guards.sh", old: "bash plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh\n", new: "# TODO: 之後再接 plugin/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh\n"),
        ], expect: "store-marker-parity.sh 不在 pre-push 裡"),
    TCMCase(isWarn: false, desc: "把 workflow 的一個 run: 換成只印檔名的 echo",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: echo \"見 .githooks/run-guards.sh 的說明\""),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把 run: 換成 `cat <守衛> | bash`（管線下游的裸直譯器）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: bash --version && cat .githooks/run-guards.sh | bash"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把守衛掛到 `||` 之後（語意判不出，守衛須說明而非斷言）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: test -f /nonexistent || bash plugin/tests/rule-coverage.sh"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: true, desc: "守衛用純 glob 讀宣告的目錄、從不寫目錄名（宣告為真，不得誤殺）",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n# trigger-coverage: reads plugin/rules/*.md\nfor f in \"$(dirname \"$0\")\"/../*/*.md; do :; done"),
        ], expect: "一次都沒出現過"),
    TCMCase(isWarn: true, desc: "編造宣告 + 一句含該目錄名的散文（有提到但非路徑脈絡）",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n# trigger-coverage: reads Sources/AkashicCore/*.swift\n# 註：本檔不碰 AkashicCore，只重建審查者的失敗情境。"),
        ], expect: "有出現但不在路徑脈絡裡"),
    TCMCase(isWarn: false, desc: "把 run: 換成 `cat <守衛> | bash`（直譯器從 stdin 讀）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: cat .githooks/run-guards.sh | bash"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: true, desc: "宣告指向守衛自己所在的目錄（可能多餘、也可能必要）",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n# trigger-coverage: reads plugin/tests/*.py"),
        ], expect: "那正是它自己所在的目錄"),
    TCMCase(isWarn: false, desc: "啞宣告①：少了註解標記",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\ntrigger-coverage: reads plugin/rules/*.md"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告②：行尾多一句註記（DECLARE 要求行尾就結束）",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n# trigger-coverage: reads plugin/rules/*.md  # 新增"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告③：沒給 glob",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n# trigger-coverage: reads"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告⑤：Swift 的 `///` doc comment",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n/// trigger-coverage: reads plugin/rules/*.md"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告⑥：shell 的段標 `##`",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n## trigger-coverage: reads plugin/rules/*.md"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告④：關鍵字打成 read",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n# trigger-coverage: read plugin/rules/*.md"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: true, desc: "編造宣告 + 巧合子串（`rulesets` 含 `rules`，非路徑脈絡）",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n# trigger-coverage: reads plugin/rules/*.md\n# 說明：本檔不處理 rulesets，只重建審查者的失敗情境。"),
        ], expect: "有出現但不在路徑脈絡裡"),
    TCMCase(isWarn: true, desc: "宣告用中間萬用字元（`Sources/*/*.swift`）——痕跡走回 `Sources`",
        edits: [
            (path: "plugin/tests/rule-coverage.sh", old: "# trigger-coverage: reads plugin/rules/*.md", new: "# trigger-coverage: reads Sources/*/*.swift"),
        ], expect: "一次都沒出現過"),
    TCMCase(isWarn: false, desc: "把某個守衛改成 block scalar 形式呼叫（續行要讀得到）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: |\n          set -e\n          echo 開始\n          python3 plugin/tests/DELETED-numbers-audit.py"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把守衛名字藏進 heredoc 主體（不得算成有跑）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: |\n          cat > /tmp/w.sh <<'EOF'\n          python3 plugin/tests/measured-numbers-audit.py\n          EOF\n          chmod +x /tmp/w.sh"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "heredoc 結束字帶連字號，其後的真呼叫不得被吞掉",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: |\n          cat > /tmp/s.sh <<SETUP-EOF\n          echo hi\n          SETUP-EOF\n          python3 plugin/tests/DELETED-numbers-audit.py"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把 run: 換成 shellcheck（靜態檢查，不執行守衛）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: shellcheck plugin/tests/rule-coverage.sh"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把 run: 改成管線形式（`cat x | bash <守衛>` 後半換成 echo）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: cat /dev/null | echo \"見 plugin/tests/rule-coverage.sh\""),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把 run: 換成印出 ./ 形式檔名的 echo（R20 修法的殘留半邊）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: echo \"見 ./.githooks/run-guards.sh 的說明\""),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把 declared() 改成走 code_only()（宣告行是註解，會被剝掉）",
        edits: [
            (path: "plugin/tests/trigger-coverage.py", old: "    for line in io.open(path, encoding='utf8', errors='replace'):\n        m = DECLARE.search(line)", new: "    for line in code_only(path).split('\\n'):\n        m = DECLARE.search(line)"),
        ], expect: "宣告機制失效了"),
    TCMCase(isWarn: false, desc: "把 run 改成 `bash setup.sh && bash <守衛>` 再把後半換成 echo",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: bash scripts/setup.sh && echo \"見 plugin/tests/rule-coverage.sh\""),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "在真宣告旁邊多寫一行教學範例（DA 指名的類別）",
        edits: [
            (path: "plugin/tests/rule-coverage.sh", old: "# trigger-coverage: reads plugin/rules/*.md", new: "# trigger-coverage: reads plugin/rules/*.md\n# trigger-coverage: reads plugin/rules/*.md"),
        ], expect: "重複的宣告樣式"),
    TCMCase(isWarn: true, desc: "給一個不讀 rules/ 的守衛加一條格式正確的誤宣告",
        edits: [
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n# trigger-coverage: reads plugin/rules/*.md"),
        ], expect: "一次都沒出現過"),
    TCMCase(isWarn: false, desc: "把宣告改成 `reads *.sh`（比例判準會放過，結構判準擋下）",
        edits: [
            (path: "plugin/tests/rule-coverage.sh", old: "# trigger-coverage: reads plugin/rules/*.md", new: "# trigger-coverage: reads *.sh"),
        ], expect: "第一段是萬用字元"),
    TCMCase(isWarn: false, desc: "把宣告改成 `reads */*.sh`（含斜線但第一段是萬用字元）",
        edits: [
            (path: "plugin/tests/rule-coverage.sh", old: "# trigger-coverage: reads plugin/rules/*.md", new: "# trigger-coverage: reads */*.sh"),
        ], expect: "第一段是萬用字元"),
    TCMCase(isWarn: false, desc: "把受保護檔案的路徑改成不存在的（憑記憶寫路徑的那個坑）",
        edits: [
            (path: "plugin/tests/trigger-coverage.py", old: "'Sources/AkashicStoreIO/StoreVersion.swift'", new: "'Sources/AkashicCore/StoreVersion.swift'"),
        ], expect: "不存在的路徑"),
]
