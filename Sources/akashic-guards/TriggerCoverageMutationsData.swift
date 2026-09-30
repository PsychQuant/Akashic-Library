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

// **#629：注入的宿主從 Python／shell 守衛換成 Swift 守衛。** 這批 case 原本把探針行注入 `plugin/tests/plugin-store-format-parity.py`
// （讀取形狀）、`plugin/tests/review-claim-audit.sh` 與 `plugin/tests/rule-coverage.sh`（宣告形狀），三個檔隨移植一起刪了。
// 現在的宿主是 `PluginStoreFormatParity.swift`（讀取形狀與大部分宣告形狀）與 `RuleCoverage.swift`（它自己那條真宣告）：
// 錨點 `let src = rawFile(…)`／`import Foundation`／`// trigger-coverage: reads plugin/rules/*.md` 都是這兩個檔裡各自唯一的行。
// 被測的東西是 `trigger-coverage` 對「路徑字面、probe token、宣告樣式」的**文字層**判斷，與宿主的語言無關，所以每格的預期
// 訊息不變。**讀取**的探針行改寫成 Swift 的等價形狀（`rawFile(`）；**absence probe** 的三個 case 刻意保留 Python 形狀
// （`os.path.exists(`、`).exists()` 後綴）——那兩個 token 仍在 `PROBE_PREFIXES`／後綴清單裡（樹裡還有 Python 守衛），
// 本 harness 是文字層的，注入的行不必是宿主語言的合法程式碼；Swift 形狀的 probe 由 `fileExists(`／`profileExists(` 兩個 case 涵蓋。
// 樹裡最後一支 Python 守衛退場時，那三個 case 與這兩個 token 一起處理。

struct TCMCase {
    let isWarn: Bool
    let desc: String
    let edits: [(path: String, old: String, new: String)]
    let expect: String
    /// **同一個注入必須同時出現的其他訊息**（#629 R1 verify 第 11 則）。預設空＝只要求 `expect`。
    /// 「從守衛清單拿掉一支守衛」現在有**兩路**後果：「<守衛> 不在 pre-push 裡」（pre-push 那一路）與「改 X 時 <守衛> 不在任何
    /// CI workflow 跑」（CI 那一路，因為 CI 也只經 `run-guards.sh` 跑守衛）。#629 第一版把 `expect` 放寬成共同前綴
    /// （`<守衛>.swift 不在`），於是停用 pre-push 那一路的訊息，負控仍全綠——全樹只有這兩格驗過它。現在 `expect` 指名 pre-push 那一路，
    /// `alsoExpect` 指名 CI 那一路，兩者都必須出現；第三段判準（不得有無關缺口）對兩者都放行。
    var alsoExpect: [String] = []
    /// **已知缺口那一格**（#690 R1 verify）：rc 必須是 0、`expect` 與 `alsoExpect` 各自出現在一條 `⊘` 行，而且沒有任何缺口、
    /// 沒有任何警告——已知缺口不計入 rc，那正是這一格要驗的事。`isWarn` 必須是 false。
    var isKnownGap: Bool = false
}

let triggerCoverageMutationCases: [TCMCase] = [
    // **#521 R3 的負控（三）：前綴 token 必須有 identifier 邊界。**
    // `hasSuffix("fileExists(")` 對 `profileExists(` 也成立——一個自家函式的名字碰巧以
    // 允許的 token 結尾，就能消音死引用（實測 0 缺口）。這一格鎖住那個邊界檢查。
    //
    // **`XPath(`（同型、命中 `Path(`）刻意不另開一格**：兩者走的是同一個謂詞，分成兩格
    // 會讓計數多一而事實沒多一件——`zero-instance-guards` 第 5 列（對自己的覆蓋率說謊）
    // 管的正是這個。這裡改成把涵蓋範圍寫出來。
    TCMCase(isWarn: false, desc: "名字碰巧以允許 token 結尾的函式（profileExists）不得豁免",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift",
             old: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n",
             new: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n"
                + "    let _q = profileExists(\"plugin/tests/gone-r3-no-boundary.py\")\n"),
        ], expect: "引用了 `plugin/tests/gone-r3-no-boundary.py`，而**那個檔不存在**"),
    // **#521 R3 的負控（四）：邊界檢查不得做在剝光空白的字串上。**
    // 這是上一格修法自帶的陷阱（Codex 同席指名）：把空白全剝掉之後，`if os.path.exists(`
    // 變成 `ifos.path.exists(`，token 前一個字元成了 `if` 的 `f`，於是**最常見的合法形狀**
    // 被判成沒有邊界。一行兩件事：一個 `if` 開頭的 probe（必須豁免）＋ 一個真的死引用
    // （必須報）。前綴側若退回全剝，probe 會多出一條缺口，這一格就以「另有無關缺口」失敗。
    TCMCase(isWarn: false, desc: "`if` 緊接的 absence probe 仍須豁免（邊界不得在剝空白後判）",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift",
             old: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n",
             new: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n"
                + "    let _gone = rawFile(\"plugin/tests/gone-r3-if-boundary.py\")\n"
                + "    if os.path.exists(\"plugin/tests/absent-if-probe-r3.py\"):\n        pass\n"),
        ], expect: "引用了 `plugin/tests/gone-r3-if-boundary.py`，而**那個檔不存在**"),
    // **#521 R3 的負控（一）：豁免的 probe token 不得以任意接收者結尾。**
    // R2 的修法把豁免綁到字面的前後緊鄰文字，但前綴清單裡留了一支**裸的** `exists(`，
    // 於是任何 `<接收者>.exists("路徑")` 都被豁免。這一格注入的正是那個形狀，指向一個
    // 不存在的檔——正確行為是報一條缺口。裸 `exists(` 若回來，這一格會以「rc=0」失敗。
    TCMCase(isWarn: false, desc: "任意接收者的 .exists(\"死引用\") 不得被當成 absence probe",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift",
             old: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n",
             new: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n"
                + "    let _q = registry.exists(\"plugin/tests/gone-r3-bare-exists.py\")\n"),
        ], expect: "引用了 `plugin/tests/gone-r3-bare-exists.py`，而**那個檔不存在**"),
    // **#521 R3 的負控（二）：跨行 absence probe 的豁免不得被縮排推出窗外。**
    // 訊息與註解都承諾「去掉空白後緊鄰即豁免」，而 R2 的窗是在**剝空白之前**取 40 個
    // 原始字元——縮排 50 格就掉出去。這一格一行兩件事：一個縮排 50 格的跨行 probe
    // （必須豁免）＋ 一個真的死引用（必須報）。窗若縮回 40，probe 會多出一條缺口，
    // 這一格就以「另有 1 條無關缺口」失敗。50 是刻意選的：> 40（舊窗）且 < 400（新窗）。
    TCMCase(isWarn: false, desc: "縮排 50 格的跨行 absence probe 仍須豁免",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift",
             old: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n",
             new: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n"
                + "    let _ok = fileExists(\n" + String(repeating: " ", count: 50)
                + "\"plugin/tests/deliberately-absent-r3-probe.py\"\n)\n"
                + "    let _gone = rawFile(\"plugin/tests/gone-across-lines-r3.py\")\n"),
        ], expect: "引用了 `plugin/tests/gone-across-lines-r3.py`，而**那個檔不存在**"),
    // **#521 R2 的負控：豁免不得溢出到同行的其他字面。**
    // R2 verify（Codex 跨模型席）在第一版的豁免上找到一個我自己引入的 false negative：
    // 豁免當時套在**整行**，於是同一行只要出現任何 probe token，真正的死引用就被消音。
    // 修法是把豁免綁到**這一個字面**的前後緊鄰文字；這一格把那個修法鎖住。
    //
    // 注入是一行兩件事：一個**真的讀取**指向不存在的檔，加一個指向**存在**的檔的
    // absence probe。正確行為是恰好一條缺口（讀取那個），probe 那個不算。
    TCMCase(isWarn: false, desc: "同行的無關 absence probe 不得消音真正的死引用",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift",
             old: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n",
             new: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n    let _d = rawFile(\"plugin/tests/gone-by-433.py\"); let _o = os.path.exists(\"plugin/.claude-plugin/plugin.json\")\n"),
        ], expect: "引用了 `plugin/tests/gone-by-433.py`，而**那個檔不存在**"),
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
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift",
             old: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n",
             new: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n"
                + "    let _gone = rawFile(\"plugin/tests/this-file-was-deleted-by-433.py\")\n"
                + "    let _ok = (ROOT / \"plugin/tests/deliberately-absent-probe.py\").exists()\n"),
        ], expect: "引用了 `plugin/tests/this-file-was-deleted-by-433.py`，而**那個檔不存在**"),
    // **#518 的負控**：讓一支守衛開始引用一個存在、但不在受保護集合裡的檔。
    // 這正是 #516 的形狀——守衛進了人口、它讀的檔沒進，而報表照印「無缺口」。
    // `ShellLex.swift` 是刻意選的：它在 `Sources/akashic-guards/` 裡卻**不是守衛**
    // （`main.swift` 沒有對應的 `case`），所以它永遠不會因為別的原因進 `PROTECTED`。
    TCMCase(isWarn: false, desc: "讓守衛引用一個未受保護的檔",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift",
             old: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n",
             new: "    let src = rawFile(\"Sources/AkashicStoreIO/StoreVersion.swift\")\n    let _probe = rawFile(\"Sources/akashic-guards/ShellLex.swift\")\n"),
        ], expect: "讀 `Sources/akashic-guards/ShellLex.swift`"),
    // **#629：這兩格要求兩路訊息都出現。** 原本的守衛（`store-marker-parity.sh`）除了 `run-guards.sh` 之外，
    // 還被 workflow 的一個獨立 step 直接執行，所以從 run-guards 拿掉它只會少一條 pre-push 的缺口。現在所有守衛都**只**經
    // `run-guards.sh` 執行（pre-push 與 CI 共用），拿掉那一行等於兩邊都不跑：除了「不在 pre-push 裡」，它讀的每個受保護檔
    // 都多一條「改 X 時它不在任何 CI workflow 跑」——它們是**同一個注入的後果**，不是無關缺口。
    // **第一版（7d34e7f7）把 `expect` 放寬成共同前綴 `PluginStoreFormatParity.swift 不在`，而那個字串也被 CI 那一路滿足**：
    // 停用 pre-push 那一路的訊息（`TriggerCoverage.swift` 的 `uncoveredHook` 迴圈改成空的），兩格照樣 ✓、`37/37`
    // （R1 verify 第 11 則實測）——「守衛不在 pre-push」是這支守衛的核心職責，卻沒有任何負控。現在 `expect` 指名 pre-push 那一路、
    // `alsoExpect` 指名 CI 那一路，缺哪一路都紅。
    TCMCase(isWarn: false, desc: "從守衛清單拿掉一支守衛",
        edits: [
            (path: ".githooks/run-guards.sh", old: ".build/debug/akashic-guards plugin-store-format-parity\n", new: ""),
        ], expect: "PluginStoreFormatParity.swift 不在 pre-push 裡", alsoExpect: ["PluginStoreFormatParity.swift 不在任何 CI workflow 跑"]),
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
            (path: ".githooks/run-guards.sh", old: ".build/debug/akashic-guards plugin-store-format-parity\n", new: "# TODO: 之後再接 .build/debug/akashic-guards plugin-store-format-parity\n"),
        ], expect: "PluginStoreFormatParity.swift 不在 pre-push 裡", alsoExpect: ["PluginStoreFormatParity.swift 不在任何 CI workflow 跑"]),
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
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: test -f /nonexistent || bash .githooks/run-guards.sh"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: true, desc: "守衛用純 glob 讀宣告的目錄、從不寫目錄名（宣告為真，不得誤殺）",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n// trigger-coverage: reads plugin/rules/*.md\nfor f in glob(\"../*/*.md\") { _ = f }"),
        ], expect: "一次都沒出現過"),
    TCMCase(isWarn: true, desc: "編造宣告 + 一句含該目錄名的散文（有提到但非路徑脈絡）",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n# trigger-coverage: reads Sources/AkashicCore/*.swift\n# 註：本檔不碰 AkashicCore，只重建審查者的失敗情境。"),
        ], expect: "有出現但不在路徑脈絡裡"),
    TCMCase(isWarn: false, desc: "把 run: 換成 `cat <守衛> | bash`（直譯器從 stdin 讀）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: cat .githooks/run-guards.sh | bash"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: true, desc: "宣告指向守衛自己所在的目錄（可能多餘、也可能必要）",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n// trigger-coverage: reads Sources/akashic-guards/*.swift"),
        ], expect: "那正是它自己所在的目錄"),
    TCMCase(isWarn: false, desc: "啞宣告①：少了註解標記",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\ntrigger-coverage: reads plugin/rules/*.md"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告②：行尾多一句註記（DECLARE 要求行尾就結束）",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n// trigger-coverage: reads plugin/rules/*.md  // 新增"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告③：沒給 glob",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n# trigger-coverage: reads"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告⑤：Swift 的 `///` doc comment",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n/// trigger-coverage: reads plugin/rules/*.md"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告⑥：shell 的段標 `##`",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n## trigger-coverage: reads plugin/rules/*.md"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: false, desc: "啞宣告④：關鍵字打成 read",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n// trigger-coverage: read plugin/rules/*.md"),
        ], expect: "這一行是啞的"),
    TCMCase(isWarn: true, desc: "編造宣告 + 巧合子串（`rulesets` 含 `rules`，非路徑脈絡）",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n# trigger-coverage: reads plugin/rules/*.md\n# 說明：本檔不處理 rulesets，只重建審查者的失敗情境。"),
        ], expect: "有出現但不在路徑脈絡裡"),
    // **注入的是真守衛用的宣告形式 `Sources/*/*.swift`**（`network-confinement`、`zero-instance-rows-audit` 都是這一條）。
    // #690 的第一輪把它換成 `Sources/*/Venue.swift`，理由是那個範圍有 115 個 CI 不跑的檔、宣告範圍檢查會多報一條；
    // 裁決 A（`census-parity.yml` 加 `Sources/**`）之後那 115 個檔已被涵蓋，換樣式的理由不在了（R1 verify regression 席），
    // 改回來。這一格要驗的是「中間萬用字元時痕跡走回 `Sources`」。
    TCMCase(isWarn: true, desc: "宣告用中間萬用字元（`Sources/*/*.swift`）——痕跡走回 `Sources`",
        edits: [
            (path: "Sources/akashic-guards/RuleCoverage.swift", old: "// trigger-coverage: reads plugin/rules/*.md", new: "// trigger-coverage: reads Sources/*/*.swift"),
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
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: shellcheck .githooks/run-guards.sh"),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把 run: 改成管線形式（`cat x | bash <守衛>` 後半換成 echo）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: cat /dev/null | echo \"見 .githooks/run-guards.sh\""),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把 run: 換成印出 ./ 形式檔名的 echo（R20 修法的殘留半邊）",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: echo \"見 ./.githooks/run-guards.sh 的說明\""),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "把 run 改成 `bash setup.sh && bash <守衛>` 再把後半換成 echo",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "run: bash .githooks/run-guards.sh", new: "run: bash scripts/setup.sh && echo \"見 .githooks/run-guards.sh\""),
        ], expect: "不在任何 CI workflow 跑"),
    TCMCase(isWarn: false, desc: "在真宣告旁邊多寫一行教學範例（DA 指名的類別）",
        edits: [
            (path: "Sources/akashic-guards/RuleCoverage.swift", old: "// trigger-coverage: reads plugin/rules/*.md", new: "// trigger-coverage: reads plugin/rules/*.md\n// trigger-coverage: reads plugin/rules/*.md"),
        ], expect: "重複的宣告樣式"),
    TCMCase(isWarn: true, desc: "給一個不讀 rules/ 的守衛加一條格式正確的誤宣告",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n// trigger-coverage: reads plugin/rules/*.md"),
        ], expect: "一次都沒出現過"),
    TCMCase(isWarn: false, desc: "把宣告改成 `reads *.sh`（比例判準會放過，結構判準擋下）",
        edits: [
            (path: "Sources/akashic-guards/RuleCoverage.swift", old: "// trigger-coverage: reads plugin/rules/*.md", new: "// trigger-coverage: reads *.sh"),
        ], expect: "第一段是萬用字元"),
    TCMCase(isWarn: false, desc: "把宣告改成 `reads */*.sh`（含斜線但第一段是萬用字元）",
        edits: [
            (path: "Sources/akashic-guards/RuleCoverage.swift", old: "// trigger-coverage: reads plugin/rules/*.md", new: "// trigger-coverage: reads */*.sh"),
        ], expect: "第一段是萬用字元"),
    // ── #690：宣告範圍裡不在受保護集合的檔 ──────────────────────────────
    // 逐對表只走受保護集合；宣告卻可以指向一整片不受保護的檔。一支守衛新宣告讀 `Sources/*/*.swift`，
    // 而那片範圍有 CI 不跑它的檔、它又不在已知缺口清單（`.githooks/acknowledged-ci-gaps.txt`）——必須是缺口。
    TCMCase(isWarn: false, desc: "宣告範圍裡有 CI 不跑的不受保護檔，而它不在已知缺口清單",
        edits: [
            (path: "Sources/akashic-guards/PluginStoreFormatParity.swift", old: "import Foundation", new: "import Foundation\n// trigger-coverage: reads Sources/*/*.swift"),
            // #690 之後 `Sources/**` 涵蓋整個 Sources/，要造出缺口得同時拿掉它；另外兩支讀整個 Sources/ 的守衛因此也報，一併列為預期。
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
        ], expect: "PluginStoreFormatParity.swift 宣告讀 `Sources/*/*.swift`：其中",
        alsoExpect: ["NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中", "ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中"]),
    // #690 落地後清單是空的：拿掉 `Sources/**`，讀整個 `Sources/` 的兩支守衛必須直接失敗——不得被當成已知缺口放過。
    // 有人把 #690 那兩條豁免加回已知缺口清單，這一格會轉紅（輸出變成「已知缺口」而 rc 不再是 1）。
    TCMCase(isWarn: false, desc: "拿掉 Sources/** 之後，讀整個 Sources/ 的守衛不在任何 CI 跑",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
        ], expect: "NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中",
        alsoExpect: ["ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中"]),
    // ── #690 R1 verify：宣告範圍檢查的兩個判斷各有一格 ──────────────────────
    // 上面兩格都靠拿掉 `Sources/**` 讓 paths 不成立，所以只釘住 paths 比對：把「workflow 有跑這支守衛」改成恆真、或拿掉
    // paths-ignore 的判斷，兩格照樣紅（DA 席實測存活）。
    // (1) 另一個 workflow 的 paths 涵蓋 `Sources/**`、但它不跑守衛——仍是缺口。
    //     **注入後的 workflow 要是 GitHub Actions 收的設定**（#690 R2 verify，Codex 席）：上一版在 `ci.yml` 既有的 `paths-ignore:`
    //     前面插 `paths:`，同一個事件兩個鍵都有，Actions 拒收——那一格只證明自製的解析器怎麼讀一份不合法的設定。
    //     現在把 `ci.yml` 的事件篩選整段換成單一的 `paths:`。
    TCMCase(isWarn: false, desc: "另一個 workflow 的 paths 涵蓋 Sources/** 卻不跑守衛，仍是缺口",
        edits: [
            (path: ".github/workflows/ci.yml", old: "    paths-ignore:\n      - \"**.md\"\n      - \"plugin/**\"\n      # #625：其他 plugin 根與 marketplace manifest 同樣不含 Swift——守衛由 census-parity 跑\n      - \"plugins/**\"\n      - \".claude-plugin/**\"\n      - \".claude/**\"\n", new: "    paths:\n      - \"Sources/**\"\n"),
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
        ], expect: "NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中",
        alsoExpect: ["ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中"]),
    // (2) 跑守衛的 workflow 以 paths-ignore 排除宣告範圍的一部分——那一部分改動時守衛不跑。
    //     同樣要是合法的設定（#690 R2 verify）：上一版把 `paths-ignore:` 插在 `push` 既有的 `paths:` 前面。現在 `push` 照舊只有
    //     `paths`，`pull_request` 改成只有 `paths-ignore`——兩個事件各一個鍵，Actions 收。只動 `Sources/AkashicS2/` 的 PR 真的不觸發
    //     這個 workflow；守衛不分事件，看到 `paths-ignore` 排除它就算未覆蓋，這一格要的正是這個判斷。
    TCMCase(isWarn: false, desc: "跑守衛的 workflow 以 paths-ignore 排除宣告範圍的一部分",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "  pull_request:\n    paths: *parity_paths\n", new: "  pull_request:\n    paths-ignore:\n      - \"Sources/AkashicS2/**\"\n"),
        ], expect: "NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中",
        alsoExpect: ["ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中"]),
    // ── #690 R1 verify：已知缺口清單是資料檔，三條分支各有一格 ──────────────
    // 清單是編譯期常數時，harness 改不到它，清空之後「已知缺口」與「過期」兩條分支沒有任何格子走得到（requirements、logic、
    // regression 三席）。
    TCMCase(isWarn: false, desc: "已知缺口清單有一條、缺口卻已經不在（過期）",
        edits: [
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\t#690\n"),
        ], expect: "已經沒有缺口"),
    TCMCase(isWarn: false, desc: "拿掉 Sources/**、兩支守衛列在已知缺口清單——列管，不計入 rc",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\t#690\nSources/akashic-guards/ZeroInstanceRowsAudit.swift\tSources/*/*.swift\t#690\n"),
        ], expect: "NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中",
        alsoExpect: ["ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中"], isKnownGap: true),
    TCMCase(isWarn: false, desc: "已知缺口清單有一行格式不對（少一欄）",
        edits: [
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\n"),
        ], expect: "格式不對"),
    // ── #690 R2 verify：格式閘與比對的每個條件各有一格 ──────────────────────
    // 上面那格只少一欄，只走得到 `f.count == 3`。拿掉 `#<issue>` 的格式檢查、或比對時只比守衛不比樣式，負控仍全綠
    // （regression、logic、DA 三席以 mutant 實測）。
    // 第三欄不是 `#<issue>`：列兩條真的缺口、第三欄寫 TODO——若被收下，兩條缺口都會被當成已知缺口放過（rc=0）。
    TCMCase(isWarn: false, desc: "已知缺口清單的第三欄不是 #<issue>（TODO），缺口不得被放過",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\tTODO\nSources/akashic-guards/ZeroInstanceRowsAudit.swift\tSources/*/*.swift\tTODO\n"),
        ], expect: "格式不對",
        alsoExpect: ["NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中", "ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中"]),
    // ── #710：issue 號本身的形狀 ─────────────────────────────────────────
    // `\A#[0-9]+\z` 收 `#0`、`#0000` 與任意長的數字，「每一條附 issue 號」可以用占位字串滿足。現在 issue 號不得以 0 開頭、至多 7 位
    // （2026-09-30 本 repo 最大的 issue 號是 710）。三格的形狀同上一格：兩條真的缺口、兩行寫同一個占位號——被收下就兩條都被放過（rc=0）。
    // **一種占位一格，不合成一格**：`\A#(?:0|[1-9][0-9]{0,6})\z` 只收 `#0`、`\A#(?:0{2,}|[1-9][0-9]{0,6})\z` 只收 `#0000`，兩種改壞法
    // 都寫得出來。合成一格（一行 `#0`、一行 `#0000`）時只有一行被收，rc 仍非 0、兩條訊息都在（`⊘` 行也含那段文字），那一格照綠。
    TCMCase(isWarn: false, desc: "已知缺口清單的第三欄是 #0，缺口不得被放過",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\t#0\nSources/akashic-guards/ZeroInstanceRowsAudit.swift\tSources/*/*.swift\t#0\n"),
        ], expect: "格式不對",
        alsoExpect: ["NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中", "ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中"]),
    TCMCase(isWarn: false, desc: "已知缺口清單的第三欄是 #0000，缺口不得被放過",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\t#0000\nSources/akashic-guards/ZeroInstanceRowsAudit.swift\tSources/*/*.swift\t#0000\n"),
        ], expect: "格式不對",
        alsoExpect: ["NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中", "ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中"]),
    TCMCase(isWarn: false, desc: "已知缺口清單的第三欄是 8 位數的 issue 號，缺口不得被放過",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\t#12345678\nSources/akashic-guards/ZeroInstanceRowsAudit.swift\tSources/*/*.swift\t#12345678\n"),
        ], expect: "格式不對",
        alsoExpect: ["NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中", "ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中"]),
    // 第一欄或第二欄是空的：兩行各缺一欄。任一個非空檢查拿掉，那一行被收下、報成「對不到任何宣告」——不在預期裡，第三段判準擋下。
    TCMCase(isWarn: false, desc: "已知缺口清單的第一欄或第二欄是空的",
        edits: [
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\n\tSources/*/*.swift\t#690\nSources/akashic-guards/NetworkConfinement.swift\t\t#690\n"),
        ], expect: "格式不對"),
    // 樣式與守衛的宣告不逐字相同：條目不得抵掉那支守衛的缺口，而且要說它對不到宣告（不是「已經沒有缺口」）。
    TCMCase(isWarn: false, desc: "已知缺口清單的樣式與守衛的宣告不同，缺口不得被放過",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\nSources/akashic-guards/NetworkConfinement.swift\tSources/**/*.swift\t#690\nSources/akashic-guards/ZeroInstanceRowsAudit.swift\tSources/*/*.swift\t#690\n"),
        ], expect: "NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中",
        alsoExpect: ["對不到任何宣告"]),
    // CRLF 行尾（含一個 CRLF 空行）：照樣是兩條已知缺口，`#690` 後面不夾 `\r`。
    TCMCase(isWarn: false, desc: "已知缺口清單是 CRLF 行尾——照樣列管，不計入 rc",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\r\n\r\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\t#690\r\nSources/akashic-guards/ZeroInstanceRowsAudit.swift\tSources/*/*.swift\t#690\r\n"),
        ], expect: "NetworkConfinement.swift 宣告讀 `Sources/*/*.swift`：其中",
        alsoExpect: ["ZeroInstanceRowsAudit.swift 宣告讀 `Sources/*/*.swift`：其中", "已知缺口，#690 追蹤"], isKnownGap: true),
    // 同一條列兩次：第二條是格式問題、要具名，不得報成「已經沒有缺口」（缺口其實還在）。
    TCMCase(isWarn: false, desc: "已知缺口清單同一條列兩次",
        edits: [
            (path: ".github/workflows/census-parity.yml", old: "      - \"Sources/**\"\n", new: ""),
            (path: ".githooks/acknowledged-ci-gaps.txt", old: "# ── 條目從下一行開始 ──\n", new: "# ── 條目從下一行開始 ──\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\t#690\nSources/akashic-guards/ZeroInstanceRowsAudit.swift\tSources/*/*.swift\t#690\nSources/akashic-guards/NetworkConfinement.swift\tSources/*/*.swift\t#690\n"),
        ], expect: "重複"),
]
