// plugin/ 散文的機械守衛：可跟隨的懸空連結、未揭露的 repo 專屬路徑、假的自我量測。
//
// **為什麼這支要出貨**：#407 的驗收前五輪都跑在一個**只存在於作者 scratchpad 的腳本**裡
// （R5 finding 44）——一個沒進版控的守衛，下一個人不會知道它存在、不會跑它、改壞了也
// 不會有人發現。同一輪還證明了更難堪的事：那十三項**全綠**，而把前一輪的原始缺陷做成
// mutation 一跑，13/13 完整存活。所以這裡只保留**驗證過會紅**的那幾項。
//
// trigger-coverage: reads plugin/rules/*.md

import Foundation

/// Python `repr()` 對 `list[str]` 的格式：`[]` 或 `['a', 'b']`。
///
/// 輸出要與 Python 版**逐位元相同**，所以連 repr 的引號規則都要跟——含單引號的字串
/// Python 會改用雙引號包。
/// Python `repr()` / `str()` 對 `list[str]` 的格式——`MeasuredClaimsAudit` 也用它，故非 private。
func pyRepr(_ xs: [String]) -> String {
    "[" + xs.map { s -> String in
        s.contains("'") && !s.contains("\"")
            ? "\"\(s)\""
            : "'" + s.replacingOccurrences(of: "\\", with: "\\\\")
                     .replacingOccurrences(of: "'", with: "\\'") + "'"
    }.joined(separator: ", ") + "]"
}

func pyRepr(_ s: String) -> String { pyRepr([s]).dropFirst().dropLast().description }

/// Python `os.path.abspath`：相對 cwd 轉絕對，並正規化 `..`／`.`。
private func abspath(_ p: String) -> String {
    let full = p.hasPrefix("/") ? p : "\(FileManager.default.currentDirectoryPath)/\(p)"
    return URL(fileURLWithPath: full).standardizedFileURL.path
}

func ruleProseGuards(argv: [String]) -> Int32 {
    var plugin = "\(repoRoot)/plugin"
    var venueArg: String? = nil
    // `--root <dir>` / `--venue <path>`：讓 negative control 能對**一份 copy** 跑，而不是
    // 就地改寫出貨檔。前一版的 harness 改的是版控中的規則檔，而跨模型審查在審查期間實際
    // 觀察到姊妹 harness 把 tracked 的 census 改壞三次。
    var a = argv
    while !a.isEmpty {
        if a[0] == "--root", a.count > 1 { plugin = abspath(a[1]); a.removeFirst(2) }
        else if a[0] == "--venue", a.count > 1 { venueArg = abspath(a[1]); a.removeFirst(2) }
        else { print("✗ 未知參數：\(a[0])"); return 1 }
    }
    let rulePath = "\(plugin)/rules/assertions-must-be-measured.md"

    // repo 專屬路徑 ＝ 讀者要有那個 repo 才找得到的東西。三種形狀。
    let REPO_ONLY = #"\.claude/rules/|Sources/Akashic\w+/|(?<!\w)docs/[a-z-]+\.md|Akashic-Library/blob/"#
    // 揭露 ＝ 讓讀者知道自己可能取不到
    let DISCLOSE = #"private|存取權|取不到|讀不到|跑不了|拿不到"#

    var results: [Bool] = []
    func check(_ n: Int, _ desc: String, _ actual: [String], _ expected: [String]) {
        let ok = actual == expected
        results.append(ok)
        print("[\(n)] \(ok ? "PASS" : "FAIL")  \(desc)")
        if !ok {
            print("      期望 \(pyRepr(expected))")
            print("      實際 \(pyRepr(actual))")
        }
    }

    // **兩個路徑檢查都只涵蓋散文**：markdown 的每一行，以及 .sh/.py 的**註解行**。
    // 可執行的程式碼行不算——那種用法沒有東西可以「跟隨」；而一個 negative control
    // 腳本必須能把違規字面寫成字串常數，否則它沒辦法注入。
    //
    // 這個收窄是刻意的，而且是被實測逼出來的：不收窄的話，本檔自己的 regex 定義會被
    // 第 2 項 flag，本目錄的 mutation 腳本會被第 1 項 flag。兩次的替代方案都是「加一份
    // 豁免清單」——而豁免清單才是真正會長出漏洞的東西。
    func proseLines(_ fp: String) -> [(Int, String)] {
        let md = fp.hasSuffix(".md")
        let text = (try? String(contentsOfFile: fp, encoding: .utf8)) ?? ""
        var out: [(Int, String)] = []
        for (i, line) in text.components(separatedBy: "\n").enumerated() {
            let s = line.drop(while: { $0 == " " || $0 == "\t" })
            if md || s.hasPrefix("#") { out.append((i + 1, line)) }
        }
        // Python 的 `enumerate(open(...), 1)` 對最後一行沒有換行的檔案不會多產生一行；
        // `components(separatedBy:)` 會在結尾換行後補一個空字串。空行對兩個謂詞都不命中，
        // 所以行為等價——但行號必須一致，故不裁掉（裁掉會讓其後行號少一）。
        return out
    }

    func walkFiles(_ root: String) -> [String] {
        guard let e = FileManager.default.enumerator(atPath: root) else { return [] }
        var out: [String] = []
        for case let p as String in e
        where p.hasSuffix(".md") || p.hasSuffix(".sh") || p.hasSuffix(".py") {
            out.append("\(root)/\(p)")
        }
        return out
    }
    // `os.walk` 的走訪順序影響 `followable`／`undisclosed` 的排列，而那兩個 list 會被
    // 逐字印出。兩邊都排序即可穩定——Python 版靠 os.walk 的目錄順序，這裡顯式排序，
    // 而**當兩者都是空 list 時（唯一的通過狀態）順序不可觀察**。
    let allFiles = walkFiles(plugin).sorted()

    // ── 1. repo 專屬路徑不得以「可跟隨的連結」出現 ─────────────────────────
    //    點下去會 404，而 private repo 的 404 與「已刪除／從不存在」不可區分：
    //    等於把缺訊號換成假訊號。主要讀者是未認證的 agent。
    var followable: [String] = []
    for fp in allFiles {
        for (i, line) in proseLines(fp) {
            // 謂詞用**同一個** REPO_ONLY，不另寫一份縮寫版。前一版這裡手寫了它四種形狀
            // 中的兩種，於是把一個指向另外兩種的可跟隨連結注入進去，5/5 全綠。
            // **一份規格的兩個副本必然分岔。**
            guard !matches(line, #"\]\([^)]*"#).isEmpty else { continue }
            let tail = (line as NSString).range(of: "](").location != NSNotFound
                ? String(line[line.range(of: "](")!.lowerBound...]) : ""
            if !matches(tail, REPO_ONLY).isEmpty { followable.append("\(base(fp)):\(i)") }
        }
    }
    check(1, "repo 專屬路徑以可跟隨連結出現", followable, [])

    // ── 2. 每一處提到 repo 專屬路徑，都要在**同一行**揭露讀者可能取不到 ────
    //    刻意不用 ±N 行的視窗：曾經有一行借用了兩行外、針對**另一個路徑**的揭露而
    //    假通過。鄰近不等於「這個揭露在講這個路徑」。
    var undisclosed: [String] = []
    for fp in allFiles {
        for (i, line) in proseLines(fp) {
            // **`trigger-coverage` 的宣告行豁免**（#407 R48）：那條檢查與 `DECLARE`
            // 結構性衝突——DECLARE 要求宣告行在 glob 之後**不得有任何東西**，而本檢查
            // 要求同一行揭露取用限制。豁免是對的那一邊：宣告行不是給人跟隨的連結。
            // **豁免要與 DECLARE 逐字同寬**（#407 R49）：上一版只錨行首，於是一條帶
            // 尾註的假宣告逃得掉揭露檢查卻**不是**真宣告。
            if !matches(line, #"^\s*(?:#|//)\s*trigger-coverage:\s*reads\s+(\S+)\s*$"#).isEmpty { continue }
            if !matches(line, REPO_ONLY).isEmpty && matches(line, DISCLOSE).isEmpty {
                undisclosed.append("\(base(fp)):\(i)")
            }
        }
    }
    check(2, "提到 repo 專屬路徑卻未在同一行揭露取用限制", undisclosed, [])

    let ruleTxt = (try? String(contentsOfFile: rulePath, encoding: .utf8)) ?? ""
    let ruleLines = ruleTxt.components(separatedBy: "\n")

    // ── 3. 規則檔不得回到分類法形式 ────────────────────────────────────────
    //    前兩版都是分類法，兩版都被跨模型審查打掉，原因相同：每條分類邊界本身
    //    就是一個關於命題世界的斷言。
    let taxonomy = ["三分法", "封閉列舉，只有三類", "軸 A", "軸 B"].filter { ruleTxt.contains($0) }
    check(3, "規則檔殘留分類法用語（**只比四個歷史字面**，非通用偵測）", taxonomy, [])

    // ── 4. 規則檔不得再出現被同段證據否證的假全稱句 ────────────────────────
    //    「三筆都回傳了 volume／issue」——而同句括號印著第一筆 vol=None。
    //    掃描前剝掉「…」：**引述**一句假話不等於斷言它（失敗史必須引述得了它）。
    func unquoted(_ s: String) -> String {
        s.replacingOccurrences(of: "「[^」]*」", with: "", options: .regularExpression)
    }
    let falseAll = ruleLines.filter {
        let u = unquoted($0)
        return u.contains("都回傳了 volume") || u.contains("三筆都帶著 volume")
    }
    check(4, "規則檔殘留「三筆都…volume」的假全稱句", falseAll, [])

    // ── 5. 規則檔自陳的量測指令，跑出來要是它宣稱的數字 ────────────────────
    //    上一版出貨的指令跑出來是 8 而非 6（它數整個檔案的 case 行，而括號裡寫著
    //    「取 enum VenueType 區塊」）。旗艦主張的自我量測，第一列就不成立。
    //    謂詞不是「`六值` 這個字串在不在」——第一版是那樣寫的，而 negative control
    //    立刻證明它是盲的。要驗的是**每一處關於 VenueType 的數量宣稱都正確**。
    let CJK_NUM: [Character: Int] = ["一": 1, "二": 2, "三": 3, "四": 4, "五": 5,
                                     "六": 6, "七": 7, "八": 8, "九": 9, "十": 10]
    let venueSrc = venueArg ?? abspath("\(plugin)/../Sources/AkashicCore/Venue.swift")

    func skipExit(_ n: Int, _ msg: [String]) -> Int32 {
        // **未涵蓋不得冒充通過**（`zero-instance-guards` 第 3 列）。前一版在這裡只
        // print 一行 SKIP，於是 plugin 單獨安裝時輸出「4/4 PASS」並 exit 0——
        // 「沒被檢查」與「檢查過且乾淨」在輸出上完全一樣。
        for m in msg { print(m) }
        print("")
        print("=== \(results.filter { $0 }.count)/\(results.count) PASS，但第 \(n) 項未涵蓋 ===")
        if n == 5 && msg.count > 1 {
            print("   plugin 單獨安裝時取不到 Akashic repo 的原始碼（該 repo 為 private）。")
            print("   這不是通過：用 --venue <path> 指向 Venue.swift，或在 repo 內跑。")
        }
        return results.allSatisfy { $0 } ? 2 : 1
    }

    guard FileManager.default.fileExists(atPath: venueSrc) else {
        return skipExit(5, ["[5] SKIP  取不到 Venue.swift（\(venueSrc)）——**本項未執行**", ""])
    }
    let body = (try? String(contentsOfFile: venueSrc, encoding: .utf8)) ?? ""
    guard body.contains("enum VenueType") else {
        // `--venue` 指到一個不含該 enum 的檔（打錯路徑、上游改名）→ 走「未涵蓋」出口，
        // 不是崩潰。前一版直接取 split 的第二段，於是拋未捕捉的 IndexError——而本檔
        // 自己寫好的 SKIP 分支就在下面沒被用到（R6 finding 62）。
        return skipExit(5, ["[5] SKIP  \(venueSrc) 裡找不到 `enum VenueType`——**本項未執行**"])
    }
    let afterEnum = body.components(separatedBy: "enum VenueType")[1]
    let seg = afterEnum.components(separatedBy: "\n}")[0]
    let cases = matches(seg, #"(?m)^\s+case (\w+)$"#).map {
        (seg as NSString).substring(with: $0.range(at: 1))
    }
    let nCase = cases.count
    var wrong: [String] = []
    for (ln, line) in ruleLines.enumerated() {
        let bare = unquoted(line)
        guard line.contains("VenueType") || line.contains("值域") else { continue }
        for m in matches(bare, #"([一二三四五六七八九十])值"#) {
            let ns = bare as NSString
            let d = Character(ns.substring(with: m.range(at: 1)))
            if CJK_NUM[d] != nCase {
                wrong.append("第 \(ln + 1) 行宣稱 \(ns.substring(with: m.range(at: 0)))，實測 \(nCase)")
            }
        }
    }
    // **也要驗值，不只驗數量**（R6 finding 27）：把一個 case 改名（真缺陷）做成
    // mutation，只驗數量的謂詞 5/5 全綠。凡是逐一列出值域的那一行，列出的每個名字
    // 都必須真的存在於 enum 裡。
    for (ln, line) in ruleLines.enumerated() {
        guard line.components(separatedBy: "`／`").count - 1 >= 2 else { continue }
        let listed = matches(line, #"`(\w+)`(?=／|）|\)|、|$)"#).map {
            (line as NSString).substring(with: $0.range(at: 1))
        }
        if listed.count >= 3 {
            for name in listed where !cases.contains(name) && (name.first?.isLowercase ?? false) {
                wrong.append("第 \(ln + 1) 行列出 `\(name)`，而 enum 裡沒有這個 case")
            }
        }
    }
    // **也要真的跑規則檔展示的那條指令**（R6 finding 10）。守衛要驗的是「讀者照著跑會
    // 拿到什麼」，不是它自己另算一套。
    //
    // **但絕不執行來自散文的字串。** 上一版把擷取到的字串交給 shell，旁邊註解著「只接受
    // 以 awk 開頭的指令」——那句話是假的：regex 只管開頭與結尾，中間的 `;`／管線／
    // 命令替換／換行全部放行。跨模型審查做出 PoC：payload 尾端補一個 `echo 6` 讓輸出等於
    // 預期值，守衛報 **5/5 PASS、exit 0**，同時以使用者身分執行了注入的指令（R7 兩個
    // CRITICAL）。觸發面是 pre-push hook 與 pull_request workflow，且本樹經公開
    // marketplace 出貨。
    //
    // 現在的作法：指令是**這裡的常數**，規則檔必須逐字展示它，執行的是常數本身、
    // 以參數陣列（不經 shell）跑。要驗的性質完全保住，而散文不再有任何執行路徑。
    let CANONICAL_CMD = "awk '/^public enum VenueType/{f=1} f&&/^}/{exit} f&&/^    case /{n++} "
                      + "END{print n+0}' Sources/AkashicCore/Venue.swift"
    if !ruleTxt.contains("`\(CANONICAL_CMD)`") {
        wrong.append("規則檔展示的計數指令與守衛內建的那條不逐字相同（守衛只執行內建的那條——不執行來自散文的字串）")
    }
    // 檔案裡**每一條**同型指令都必須是那一條。安全性質（不執行散文）已由上面的常數化
    // 保證；這一條管的是**散文完整性**：一個讀者可能複製到別的那條。注入 PoC 的 payload
    // 正是這個形狀——它不再被執行，但它仍是一句假的量測。
    for m in matches(ruleTxt, #"`(awk\b[^`]*Venue\.swift)`"#) {
        let other = (ruleTxt as NSString).substring(with: m.range(at: 1))
        if other != CANONICAL_CMD {
            wrong.append("規則檔另外展示了一條同型的計數指令，而它不是 canonical 那條：\(pyRepr(String(other.prefix(60))))…")
        }
    }
    if ruleTxt.contains("`\(CANONICAL_CMD)`") {
        let p = Process()
        p.executableURL = URL(fileURLWithPath: "/usr/bin/awk")
        p.arguments = ["/^public enum VenueType/{f=1} f&&/^}/{exit} f&&/^    case /{n++} END{print n+0}",
                       venueSrc]
        let pipe = Pipe(); p.standardOutput = pipe; p.standardError = Pipe()
        var got: String
        do {
            try p.run()
            // 先讀到 EOF 再 wait——順序反了就是死鎖（本 repo 已為此付過三次 push 失敗）。
            let d = pipe.fileHandleForReading.readDataToEndOfFile()
            p.waitUntilExit()
            got = p.terminationStatus == 0
                ? String(data: d, encoding: .utf8)!.trimmingCharacters(in: .whitespacesAndNewlines)
                : "(exit \(p.terminationStatus))"
        } catch {
            got = "(執行失敗：\(error))"     // 任何失敗都要說出來
        }
        if got != String(nCase) {
            wrong.append("規則檔展示的指令印出 \(pyRepr(got))，而實測是 \(nCase)")
        }
    }
    check(5, "規則對 VenueType 的數量與值一致，且它展示的指令真的印出該數字"
           + "（實測 \(nCase)：\(cases.joined(separator: "／"))）", wrong, [])

    // ── 6. 規則檔自我量測表裡「會長的數字」是否還等於當下實測 ───────────────
    //
    // 那張表是本規則的旗艦論證（「我說的每句話都量過」）。2026-08-22 重量八列，
    // **兩列已過期**——parity 26→46、mutation 11→14。過期的正是兩個「會長」的數字：
    // 每輪加 fixture 就變，而表格把它們寫得跟「VenueType 是六值」一樣像恆定事實。
    //
    // 這一項只做**靜態計數**（數 fixture 定義與 mutation 項目），不跑那兩支腳本——
    // parity 需要 swift build、mutation 要數分鐘。實測靜態計數與實跑一致，而會漂的是
    // 計數本身，不是通過率。
    let PARITY = "\(plugin)/skills/akashic-literal-campaign/scripts/tests/store-marker-parity.sh"
    // **來源換成 Swift 資料檔**（#433 Step 5）：`marker-parity-mutations.py` 已刪除，
    // 那 14 個 mutation 現在住在 `MarkerParityMutationsData.swift`（機械抽出時生成的）。
    // 數的仍是同一件事——那張自我量測表裡「會長的數字」有沒有跟上實際的 mutation 數。
    let MUTS = abspath("\(plugin)/../Sources/akashic-guards/MarkerParityMutationsData.swift")
    guard FileManager.default.fileExists(atPath: PARITY),
          FileManager.default.fileExists(atPath: MUTS) else {
        return skipExit(6, ["[6] SKIP  取不到 parity／mutation 腳本——**本項未執行**", ""])
    }
    let parityTxt = (try? String(contentsOfFile: PARITY, encoding: .utf8)) ?? ""
    let mutTxt = (try? String(contentsOfFile: MUTS, encoding: .utf8)) ?? ""
    var stale: [String] = []
    let nFix = matches(parityTxt, #"(?m)^check "#).count
    var nMut = -1
    if let mm = matches(mutTxt, #"(?s)markerParityMutationsTable[^=]*=\s*\[(.*?)\n\]"#).first {
        let blk = (mutTxt as NSString).substring(with: mm.range(at: 1))
        nMut = matches(blk, #"(?m)^\s{4}\(old:"#).count
    }
    if nMut < 0 { stale.append("數不到 mutation 表的項目數——抽取式已與宣告寫法脫節") }
    // **proxy 的有效前件也要驗**（#407 R20）：`^check ` 只認 column 0。若有人把一個
    // check 移進 if／函式區塊，實跑的 fixture 數不變而靜態計數少一——散文若跟著改成
    // 那個錯的數字，這一項會綠而表格已與實際不符。
    let indented = matches(parityTxt, #"(?m)^\s+check "#).count
    if indented > 0 {
        stale.append("store-marker-parity.sh 有 \(indented) 個縮排的 check——"
                   + "靜態計數（只認 column 0）不再等於實跑的 fixture 數，本項的 proxy 前件失效")
    }
    // 表格裡標 ↗ 的那兩列必須帶當下的數字。
    if !ruleTxt.contains("**\(nFix)** 格 fixture") {
        stale.append("自我量測表的 parity 列不是當下的 \(nFix) 格")
    }
    if !ruleTxt.contains("**\(nMut)/\(nMut)**") {
        stale.append("自我量測表的 mutation 列不是當下的 \(nMut)/\(nMut)")
    }
    check(6, "自我量測表裡會長的數字仍等於實測（parity \(nFix) 格、mutation \(nMut)）", stale, [])

    // ── 考慮過但**不加**的檢查：「散文裡的 repo 路徑必須存在」 ──────────────
    //
    // 憑記憶寫路徑是本 issue 反覆踩到的形狀（#407 R19 的坑 (a)），所以自然會想到
    // 「掃散文裡所有 backtick 路徑，不存在就紅」。**實測後裁決不加**：14 個 backtick
    // 路徑裡 3 個不存在，而三個全是假陽性，且各有不同的排除理由——相對於 plugin 根而
    // 非 repo 根的、屬於**別的 repo** 的、以及**刻意引述的錯誤路徑**（它必須不存在，
    // 那正是該句的內容）。三個排除規則都需要判斷，機械化必然失真。一個 100% 假陽性的
    // 檢查比沒有檢查更糟：它訓練讀者忽略輸出，而下一個真缺陷就混在被忽略的那批裡。
    //
    // **真正防住那個坑的是別的東西**：`trigger-coverage` 對它的受保護清單逐條驗存在
    // ——那份清單是**程式碼**（會被執行），不是散文，所以謂詞可以是精確的。
    print("")
    print("=== \(results.filter { $0 }.count)/\(results.count) PASS ===")
    return results.allSatisfy { $0 } ? 0 : 1
}
