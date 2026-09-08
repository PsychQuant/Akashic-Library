// **本檔曾由腳本生成，現為手維護。** 原生成器 `plugin/tests/trigger-coverage-mutations.py`
// 已於 `989ac64`（#433 Step 5「Python 歸零」）刪除，所以「重新生成」那條路徑**不存在了**。
// 檔頭原本仍寫著「不要手改」——而唯一能改它的方式就是手改，#518 加負控 case 時撞上這個
// 矛盾，故一併更正。新增 case 直接在下方陣列手寫，並沿用既有格式。
//
// **為什麼機械抽而不是手抄**（#433）：32 個 mutation 全是 `t.replace(字面, 字面)`，而
// harness 斷言注入必須真的改到東西（沒改到即該 case 無效）。手抄一個空白之差會讓 case
// 靜默失效，而輸出看起來像「被注入的檔案改了」。
//
// 原生成方式（存查）：`ast` 走訪 `case`／`warn_case` 呼叫 → dict key（含用模組常數的）→
// `Lambda.body.args` 逐一 `literal_eval`。**該腳本已刪除，此段只為說明既有條目的來歷。**

struct TCMCase {
    let isWarn: Bool
    let desc: String
    let edits: [(path: String, old: String, new: String)]
    let expect: String
}

let triggerCoverageMutationCases: [TCMCase] = [
    // **#521 的負控**：讓一支守衛引用一個**不存在**的檔。這是 #518 那個 case 的鏡像
    // ——那個驗「存在但未受保護」，這個驗「根本不存在」。兩者共用同一個出口。
    //
    // 為什麼這一格值得存在：`rawFile` 對不存在的檔回空字串，走訪它的迴圈零次迭代、
    // 檢查靜默通過。#521 立案時 `MeasuredClaimsAudit` 的檢查 ③ 就是這樣——標題印了、
    // 本體一行都沒有、rc 仍是 0。**這一格是唯一擋得住它復發的東西。**
    // **注入的是真的讀取形狀，不是只建一個 Path**（#521 R1 verify，Codex 跨模型席）。
    // 上一版注入 `_gone = ROOT / "…"` ——那**一個字都沒讀**，於是這一格驗到的其實是
    // 「任意不存在的路徑字面會被拒絕」，而不是它宣稱的「守衛讀取不存在的來源會被拒絕」。
    // 換成 `.read_text()` 之後，它模擬的才是 #521 立案時 `MeasuredClaimsAudit` 的形狀。
    //
    // **同一格順便驗豁免**：注入裡另有一個**同行 absence probe**，它指向另一個不存在的
    // 檔。harness 的第三段判準（不得有無關缺口）因此變成豁免的負控——若豁免失效，那個
    // probe 會多出一條缺口，這一格就會以「另有 N 條無關缺口」失敗。
    TCMCase(isWarn: false, desc: "守衛讀取一個不存在的來源（同一格驗 absence probe 豁免）",
        edits: [
            (path: "plugin/tests/plugin-store-format-parity.py",
             old: "src = (ROOT / \"Sources/AkashicStoreIO/StoreVersion.swift\").read_text(encoding=\"utf8\")\n",
             new: "src = (ROOT / \"Sources/AkashicStoreIO/StoreVersion.swift\").read_text(encoding=\"utf8\")\n"
                + "_gone = (ROOT / \"plugin/tests/this-file-was-deleted-by-433.py\").read_text()\n"
                + "_ok = (ROOT / \"plugin/tests/deliberately-absent-probe.py\").exists()\n"),
        ], expect: "引用了 `plugin/tests/this-file-was-deleted-by-433.py`，而**那個檔不存在**"),
    // **#518 的負控**：讓一支守衛開始引用一個存在、但不在受保護集合裡的檔。
    // 這正是 #516 的形狀——守衛進了人口、它讀的檔沒進，而報表照印「無缺口」。
    // `ShellLex.swift` 是刻意選的：它在 `Sources/akashic-guards/` 裡卻**不是守衛**
    // （`main.swift` 沒有對應的 `case`），所以它永遠不會因為別的原因進 `PROTECTED`。
    TCMCase(isWarn: false, desc: "讓守衛引用一個未受保護的檔",
        edits: [
            (path: "plugin/tests/plugin-store-format-parity.py",
             old: "src = (ROOT / \"Sources/AkashicStoreIO/StoreVersion.swift\").read_text(encoding=\"utf8\")\n",
             new: "src = (ROOT / \"Sources/AkashicStoreIO/StoreVersion.swift\").read_text(encoding=\"utf8\")\n_probe = ROOT / \"Sources/akashic-guards/ShellLex.swift\"\n"),
        ], expect: "讀 `Sources/akashic-guards/ShellLex.swift`"),
    TCMCase(isWarn: false, desc: "從守衛清單拿掉一支守衛",
        edits: [
            (path: ".githooks/run-guards.sh", old: "bash plugin/skills/akashic-promote-literals/scripts/tests/store-marker-parity.sh\n", new: ""),
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
            (path: ".githooks/run-guards.sh", old: "bash plugin/skills/akashic-promote-literals/scripts/tests/store-marker-parity.sh\n", new: "# TODO: 之後再接 plugin/skills/akashic-promote-literals/scripts/tests/store-marker-parity.sh\n"),
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
            (path: "plugin/tests/review-claim-audit.sh", old: "#!/bin/bash", new: "#!/bin/bash\n# trigger-coverage: reads plugin/tests/*.sh"),
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
]
