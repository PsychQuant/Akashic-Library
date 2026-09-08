// `assertions-must-be-measured.md` 第 2 題那張五列判準表的現查。
//
// 那張表的主題是「一個真的查詢，被用來支撐一個那個查詢沒問的性質」，而它自己的五列也是
// 五個可否證的宣稱。這支腳本逐列跑出它們的依據。
//
// **第三列刻意不計數**：前三次量它時用了三種計數方式（`grep -c`、全格 findall、逐格
// 解析），得到三個不同的答案（#407 R25i）。現在直接列出行號與函式名——計數是把多個事實
// 壓成一個數字，而壓縮的方式正是出錯的地方；列舉沒有壓縮。
//
// trigger-coverage: reads plugin/rules/*.md

import Foundation

/// `subprocess.run(c, shell=True).stdout.strip()` 的等價。
private func sh(_ c: String) -> String {
    let p = Process()
    p.executableURL = URL(fileURLWithPath: "/bin/sh")
    p.arguments = ["-c", c]
    p.currentDirectoryURL = URL(fileURLWithPath: repoRoot)
    let out = Pipe(); p.standardOutput = out; p.standardError = Pipe()
    guard (try? p.run()) != nil else { return "" }
    // 先讀到 EOF 再 wait——順序反了就是死鎖（本 repo 為此付過三次 push 失敗）。
    let d = out.fileHandleForReading.readDataToEndOfFile()
    p.waitUntilExit()
    return (String(data: d, encoding: .utf8) ?? "")
        .trimmingCharacters(in: .whitespacesAndNewlines)
}

func measuredClaimsAudit() -> Int32 {
    var fails: [String] = []
    /// **印 ✓／✗ 而永遠 exit 0，與沒有這支腳本對 CI 是同一件事。**
    ///
    /// R26b 出貨的第一版正是那樣（四列全是 print、零個 assert、rc 恆 0）——而「驗收套件
    /// 對它宣稱要檢查的東西是盲的」是本 issue 最早記下的失敗之一（#407 R26e）。
    func check(_ ok: Bool, _ msg: String) -> String {
        if !ok { fails.append(msg) }
        return ok ? "✓" : "✗"
    }

    print("逐列現查（每列問「我跑的指令，回答的是不是正好這句話」）\n")

    // ① 三個 commit 是純新增
    print("① 「實測三個是純新增」")
    for h in ["41bd3d8", "848939a", "3eda486"] {
        let d = sh("git show \(h) --format='' --numstat -- plugin/ | awk '{d+=$2} END{print d+0}'")
        print("     \(h) 刪除行數 \(d)  \(check(d == "0", "\(h) 不是純新增（刪除 \(d) 行）"))")
    }

    // ② git 的欄位
    print("② 「git 證立時序，證立不了有檢查」")
    // **這一列走過三版，前兩版都不可否證**（#407 R26g）：R26b 寫死 `✓`（字串常數）；
    // R26f 掃 `git log --help` 的 placeholder——而 placeholder 是 `%an`／`%ct` **縮寫**，
    // 結構上不可能含 `review` 這個英文字。把「寫死」換成「查詢」不等於變成可否證——
    // **那個查詢問的東西必須有可能命中**。
    //
    // 這一版問 commit **物件本身**的欄位名（`git cat-file -p`），那是 git 物件格式的一部分。
    // 欄位名是**真的單字**，所以 review 類字樣有可能出現——若 git 日後加了那種欄位，這裡會紅。
    let REVIEW_ISH = ["review", "approv", "signoff", "sign-off", "verdict", "attest"]
    // 已知且判定「不是審查證據」的欄位（含縮寫）。出現在這裡＝看過、判過。
    //
    // **清單怎麼來的**（#407 R26l——上一版憑印象列，漏了 `gpgsig-sha256`）：直接從 git
    // binary 的字串常數窮舉，不用猜——
    //
    //     strings $(command -v git) | grep -oE '^(tree|parent|author|committer|gpgsig[a-z0-9-]*|mergetag|encoding)$' | sort -u
    //
    // 當次輸出（2026-08-23，`git version 2.55.0` / darwin-arm64）就是下面這八個，一個
    // 不多一個不少。**版號寫出來**是因為別的 git build 可能不同——那時這張表要重新導出。
    //
    // **`gpgsig` 不算，而理由要寫清楚**：它證明**簽署**（這是誰寫的），不證明**審查**
    // （有人檢查過內容）。兩者的差別正是第 ② 列的主題。列進來是為了讓「我看過它並判定
    // 它不算」這件事可查，而不是靠清單漏掉它來蒙混。
    let KNOWN_NOT_REVIEW: Set<String> = ["tree", "parent", "author", "committer",
                                         "gpgsig", "gpgsig-sha256", "mergetag", "encoding"]
    // **多行 header 的續行以空格開頭**（RFC 式折疊）——`gpgsig` 的 PGP 簽章就是那樣。
    // 上一版對每一行取第一個 token，於是 signed commit 抽出 **19 個「欄位」**，其中 15 個
    // 是 base64 片段（#407 R26k）。**HEAD 剛好不是 signed commit，所以本機全綠**——
    // 它在有 GPG 的環境會炸，而那是常態。
    func headerFields(_ text: String) -> [String] {
        Array(Set(text.components(separatedBy: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty && !$0.hasPrefix(" ") }
            .compactMap { $0.split(separator: " ").first.map(String.init) })).sorted()
    }
    let header = sh("git cat-file -p HEAD | sed -n '1,/^$/p'")
    let fields = headerFields(header)
    let hit = fields.filter { f in REVIEW_ISH.contains { f.lowercased().contains($0) } }

    // trailer 是第二個可能的載體（commit message 尾註）。
    //
    // **只問 review 類 token，不是「有沒有 trailer」**（2026-08-24）。上一版斷言 HEAD
    // **完全沒有** trailer，而那個前提是「HEAD 不會是 GitHub 的 merge commit」——它從來
    // 沒被寫下來也沒被測過，因為 pre-push 永遠在 merge **之前**跑。GitHub 的 merge commit
    // body 會回音 PR 的 commit 標題，而 `feat: …` 正好符合 git 的 trailer 文法
    // （`token: value`）。**實測最近 20 個 merge commit 有 11 個會踩到這一格。**
    //
    // 修法不是把 merge commit 整格跳過（那會製造盲點——真的 `Reviewed-by:` 掛在 merge
    // commit 上就抓不到了），是**讓 trailer 與 header 問同一個問題**：token 是不是 review 類。
    func reviewIshTrailers(_ raw: String) -> [String] {
        raw.components(separatedBy: "\n").compactMap { line -> String? in
            guard let i = line.firstIndex(of: ":") else { return nil }
            let token = String(line[line.startIndex..<i]).trimmingCharacters(in: .whitespaces).lowercased()
            return REVIEW_ISH.contains(where: { token.contains($0) })
                ? line.trimmingCharacters(in: .whitespaces) : nil
        }
    }
    let trailersRaw = sh("git log -1 --format='%(trailers)' HEAD")
    let trailers = reviewIshTrailers(trailersRaw)
    let unknown = fields.filter { !KNOWN_NOT_REVIEW.contains($0) }

    // **不只驗 HEAD**：HEAD 剛好不是 signed commit 時，續行的坑看不出來（R26k）。本 repo
    // 有 signed commit（GitHub 的 web merge），所以順帶對第一個 signed commit 跑同一個
    // 抽取式——**兩種形狀都要對，才叫這個檢查有意義**。
    //
    // **偵測式要錨定在 header 且錨定行首**（#407 R26o，自己撞到）：上一版寫
    // `head -6 | grep -q gpgsig`，兩個錯——(a) header 只有 4–5 行，`head -6` 會越過空行
    // 進入 **message**；(b) 不錨行首，message 裡提到那個字就命中。於是它抓到了 R26l 那個
    // commit（標題正是「漏了 gpgsig-sha256」）——**我寫的那句話讓偵測式抓到了它自己**。
    //
    // **`^gpgsig` 是前綴，所以 SHA-256 repo 的 `gpgsig-sha256` 也會被抓到**——那不是巧合
    // 而是 grep 的自然行為，但日後有人「修正」成 `^gpgsig `（加空格）就會漏掉那種 repo。
    // 上一版只把這句寫成註解（R26r），**而註解不會在它變假時發出聲音**——現在是出貨的斷言。
    //
    // **pattern 只有一份**（#407 R26u）：上一版的 fixture 自己寫了一份 regex，而真偵測式
    // 用的是 shell 的那份——**兩份獨立的 pattern**。有人把偵測式改成 `^gpgsig ` 時，fixture
    // 那格照樣綠。現在從本檔原始碼抽出偵測式實際用的 regex 再跑 fixture。
    //
    // **抽取要排除註解，並要求恰好一處**（#407 R26x）：上一版取第一個命中，而檔案裡有
    // **兩處**符合（註解與真偵測式）。目前兩者字面相同所以看起來正確，但有人改壞偵測式而
    // 註解沒跟著改時，斷言仍讀註解、仍然綠。
    //
    // **Swift 版讀的是 source 檔而不是 `__file__`**（#433）：binary 與原始碼分離，所以
    // 路徑寫明。守衛只在 repo 內跑（run-guards／pre-push），source 一定在；讀不到就報，
    // 不靜默——那與抽出 0 個 pattern 是同一個出口。
    let LINES = ["gpgsig -----BEGIN", "gpgsig-sha256 -----BEGIN"]
    let selfSrc = rawFile("Sources/akashic-guards/MeasuredClaimsAudit.swift")
    let srcCode = selfSrc.components(separatedBy: "\n")
        .filter { !$0.drop(while: { $0 == " " || $0 == "\t" }).hasPrefix("//") }
        .joined(separator: "\n")
    let ms = matches(srcCode, #"grep -q '(\^gpgsig[^']*)'"#).map {
        (srcCode as NSString).substring(with: $0.range(at: 1))
    }
    let pat: String? = ms.count == 1 ? ms[0] : nil
    let hitPrefix = LINES.filter { l in pat.map { !matches(l, "^" + $0.dropFirst()).isEmpty } ?? false }.count
    print("     偵測式實際用的 pattern：\(pat.map { "'\($0)'" } ?? "None")（從原始碼抽出，非另寫一份）")
    print("     它對 gpgsig／gpgsig-sha256 命中 \(hitPrefix)／2  "
        + check(pat != nil && hitPrefix == 2,
                "抽出 \(ms.count) 個 pattern（須恰好 1）或它只命中 \(hitPrefix)／2——SHA-256 repo 會被漏掉"))
    let signed = sh("git rev-list --all | while read h; do "
                  + "git cat-file -p $h | sed '/^$/q' | grep -q '^gpgsig' "
                  + "&& echo $h && break; done")
    if !signed.isEmpty {
        let shHdr = sh("git cat-file -p \(signed) | sed -n '1,/^$/p'")
        let sf = headerFields(shHdr)
        let su = sf.filter { !KNOWN_NOT_REVIEW.contains($0) }
        print("     signed commit \(String(signed.prefix(8))) 的欄位：\(pyRepr(sf))  "
            + check(su.isEmpty, "signed commit 抽出未判定欄位：\(pyRepr(Array(su.prefix(3))))"))
    } else {
        // **靜默是最糟的形式**（`lossless-intake` 執行細節 3）。找不到 signed commit 時整段
        // 跳過而不出聲，會讓「這個形狀沒被測」與「測過且乾淨」在輸出上長得一樣——而這正是
        // R26k 的修法要驗的那個形狀。淺 clone（CI 常見的 `fetch-depth: 1`）也會走到這裡。
        print("     ⚠ 找不到 signed commit——**本形狀未測**（淺 clone？）。"
            + "mergetag fixture 仍會跑，但真實 gpgsig 續行沒有被驗證")
    }
    // **本 repo 沒有 mergetag 的 commit，所以那個形狀用構造的測**（#407 R26o）。git 合併一個
    // signed tag 時，會把**整個 tag 物件**內嵌成 mergetag 的續行——其中有 `type`／`tag`／
    // `tagger` 這些看起來像欄位名的行。舊抽取式對它抽出 **7 個未判定欄位**；濾掉續行之後是 0。
    let MERGETAG_FIXTURE = "tree abc\nparent def\nparent 123\nauthor X <x@y> 1 +0000\n"
        + "committer X <x@y> 1 +0000\nmergetag object 456\n type commit\n tag v1.0\n"
        + " tagger X <x@y> 1 +0000\n \n Release v1.0\n -----BEGIN PGP SIGNATURE-----\n"
        + " iQEcBAAB\n -----END PGP SIGNATURE-----"
    let mtFields = headerFields(MERGETAG_FIXTURE)
    let mtUnknown = mtFields.filter { !KNOWN_NOT_REVIEW.contains($0) }
    print("     mergetag fixture（構造，本 repo 無實例）：\(pyRepr(mtFields))  "
        + check(mtUnknown.isEmpty, "mergetag 續行沒被濾掉：\(pyRepr(Array(mtUnknown.prefix(3))))"))
    // **回歸 fixture：merge commit 的 body 回音 vs 真的 review trailer**（2026-08-24）。
    // 兩個方向都要釘——只釘「不誤報」會讓人把整個檢查改成回空也照樣綠。
    let MERGE_BODY_TRAILER = "feat: pages 欄位的形狀守衛——三筆實測缺陷裡有兩筆完全不會出聲"
    let REAL_REVIEW_TRAILER = "Reviewed-by: Someone <s@example.com>"
    let fp = reviewIshTrailers(MERGE_BODY_TRAILER)
    let tp = reviewIshTrailers(REAL_REVIEW_TRAILER)
    print("     merge-body 回音不誤報：\(fp.isEmpty ? "無" : pyRepr(fp))  "
        + check(fp.isEmpty, "conventional-commit 標題被當成 review 載體：\(pyRepr(fp))"))
    print("     真的 review trailer 仍抓得到：\(pyRepr(tp))  "
        + check(tp.count == 1, "Reviewed-by 沒被抓到——檢查被改壞成永遠回空"))
    print("     commit 物件的欄位：\(pyRepr(fields))")
    print("     其中 review 類：\(hit.isEmpty ? "無" : pyRepr(hit))｜"
        + "未判定過的欄位：\(unknown.isEmpty ? "無" : pyRepr(unknown))｜"
        + "HEAD 的 review 類 trailer：\(trailers.isEmpty ? "無" : pyRepr(trailers))"
        + "（原始 trailer：\(trailersRaw.replacingOccurrences(of: "\n", with: " / ").isEmpty ? "無" : trailersRaw.replacingOccurrences(of: "\n", with: " / "))）")
    let msg = "git 出現了 review 類載體或未判定過的欄位：\(pyRepr(hit))／\(pyRepr(trailers))／\(pyRepr(unknown))"
    print("     " + check(hit.isEmpty && trailers.isEmpty && unknown.isEmpty, msg))

    // ③ 那三格全是 warn case——直接列，不用計數
    //
    // **來源在 #433 換過，本檢查在 #521 才跟上。** 原本讀
    // `plugin/tests/trigger-coverage-mutations.py`，而該檔已於 `989ac64`（Python 歸零）
    // 刪除。`rawFile` 對不存在的檔回**空字串**，於是這個迴圈零次迭代——標題印了、本體
    // 一行都沒有、rc 仍是 0。**看起來像檢查通過了**，而它其實什麼都沒驗。
    //
    // 命題本身仍為真（#521 實測：三格全部 `isWarn: true`），所以處置是**指向新來源**
    // 而不是退場。
    //
    // **標題不寫死行號**（#521 R1 verify，四席 ＋ Codex 獨立命中）。上一版寫「行 62／106／142」，
    // 而**同一個 commit** 在該資料檔頂端插入了 12 行負控 case，把三格推到 74／118／154——
    // 標題與它自己下一行的輸出當場矛盾，而行號那一半**零斷言**（只驗 `isWarn` 與 `found == 3`），
    // 所以那句假話通過了它自己的檢查。同檔第 ④ 列早就寫著「刻意不寫死 19／13……驗的是恆等式」。
    // 行號不是語意契約，逐格輸出印實際值即可；要守的命題是「恰 3 格且全是 warn」。
    let claimSrc = "Sources/akashic-guards/TriggerCoverageMutationsData.swift"
    print("③ 「\(claimSrc) 裡以 `一次都沒出現過` 為 expect 的格，恰 3 格且全是 warn」")
    let src = rawFile(claimSrc).components(separatedBy: "\n")
    // **來源讀不到就出聲，不要靜默走訪空陣列**（#521）。
    //
    // **它的價值是更準確的診斷，不是唯一的防線**（#521 R1 verify，Codex 席更正）——
    // 下面的 `found == 3` 本身就擋得住原本那個零次迭代：來源讀不到時 `found` 會是 0
    // 而它會紅。上一版把這一句寫成「本次修正的核心」，那是誇大。它買到的是：紅的時候
    // 說得出**為什麼**（來源不見了），而不是丟一句「找到 0 格」讓人去查資料檔。
    if src.count <= 1 && (src.first ?? "").isEmpty {
        print("     " + check(false, "讀不到 \(claimSrc)——本檢查等於沒跑（#521 的失效形狀）"))
    } else {
        var found = 0
        for (i0, l) in src.enumerated() where l.contains("expect: \"一次都沒出現過\"") {
            let i = i0 + 1
            var isWarn = "?"
            var j = i0
            while j >= max(0, i0 - 14) {
                let s = src[j].trimmingCharacters(in: .whitespaces)
                if s.hasPrefix("TCMCase(isWarn:") {
                    // **用 hasPrefix 而非 contains**（#521 R1 verify，logic 席）。舊的
                    // `.py` 版比的是**函式名**（`warn_case` vs `case`），是結構性判別；
                    // port 過來寫成對整行做 `contains("isWarn: true")` 之後判別力退化：
                    // 一個 `isWarn: false` 的 case 只要 `desc` 裡含那個字串就會被印成
                    // `warn ✓`（實測會過）。失效方向是靜默的綠。
                    isWarn = s.hasPrefix("TCMCase(isWarn: true") ? "warn" : "fail"
                    break
                }
                j -= 1
            }
            found += 1
            print("     行 \(i): \(isWarn)  \(check(isWarn == "warn", "行 \(i) 是 \(isWarn) case，不是 warn"))")
        }
        print("     " + check(found == 3, "找到 \(found) 格，宣稱是 3 格"))
    }

    // ④ 19 = 13 + 6
    print("④ 「run: 的分類：總數 ＝ 單行 ＋ block」")
    print("     刻意不寫死 19／13——R26b 加一個 CI 步驟就變 20／14；驗的是恆等式")
    let tot = sh(#"grep -hcE '^\s*(-\s*)?run:' .github/workflows/*.yml | awk '{s+=$1} END{print s}'"#)
    let sg = sh(#"grep -hE '^\s*(-\s*)?run: [^|]' .github/workflows/*.yml | wc -l"#)
    let bl = sh(#"grep -hE '^\s*(-\s*)?run: \|' .github/workflows/*.yml | wc -l"#)
    let sgN = Int(sg) ?? -1, blN = Int(bl) ?? -1, totN = Int(tot) ?? -2
    print("     總 \(tot)｜單行 \(sg)｜block \(bl) → \(sgN + blN)  "
        + check(sgN + blN == totN, "總數 \(tot) ≠ 單行 \(sg) + block \(bl)"))

    print("")
    // ⑤ 時態（#394 verify R8）
    print("⑤ 「差的是時態，不是內容」")
    // 前四列的形狀是「查詢問的不是那個性質」；這一列的查詢問的**正是**那個性質，只是它
    // 還沒回答完。所以現查方式也不同——不是重跑一個 grep，而是確認這一列**有沒有被人
    // 悄悄刪掉或改寫成不可否證的形式**。
    //
    // **刻意不寫死那個 SHA**：寫死的話，它終於推上去之後這裡就永遠綠，而那正好讓這一列
    // 失去意義（本檔第 ② 列走過同一條路）。
    let rule = rawFile("plugin/rules/assertions-must-be-measured.md")
    let ruleLines = rule.components(separatedBy: "\n")
    let r5 = ruleLines.filter { $0.contains("No commit found") && $0.hasPrefix("|") }
    print("     第 5 列在場且恰一列：\(r5.count) \(check(r5.count == 1, "第 5 列不見了或重複"))")
    // 那一列必須同時具名「時態」與一個**可否證的觀察**（422／No commit found），否則它會
    // 退化成一句感想。
    let ok5 = r5.count == 1 && r5[0].contains("時態") && r5[0].contains("422")
    print("     它具名了時態與可否證的觀察："
        + check(ok5, "第 5 列被改寫成沒有可否證觀察的形式——那會讓它退化成感想"))
    // 表頭宣稱的列數必須與**那一張表**的實際列數一致（本檔記過的計數分岔形狀）。
    // **範圍要收在那張表上**——第一版掃全檔所有表格得到 47，那是在量別的東西。
    guard let start = ruleLines.firstIndex(where: { $0.hasPrefix("| 我跑的 |") }) else {
        print("     ✗ 找不到那張表的表頭")
        fails.append("找不到 `| 我跑的 |` 表頭")
        return 1
    }
    var n = 0
    for l in ruleLines[(start + 2)...] {          // +2 跳過表頭與分隔列
        if !l.hasPrefix("|") { break }
        n += 1
    }
    let hdr = ruleLines.filter { $0.contains("都不是假指令") }
    let words = [3: "三個", 4: "四個", 5: "五個", 6: "六個", 7: "七個"]
    // **那一句裡有兩個計數詞**（「N 個都不是假指令，N 個都不是假數字」），所以用「包含」
    // 檢查會被另一個的存在救起來——負控實測：只改前半，`in` 照樣命中而守衛不紅。
    // 改成**抽出全部計數詞、要求每一個都對**。
    let cnts: [String] = hdr.count == 1
        ? matches(hdr[0], #"([一二三四五六七八九十]個)都不是"#).map {
            (hdr[0] as NSString).substring(with: $0.range(at: 1)) }
        : []
    let want = words[n]
    let okCnt = !cnts.isEmpty && cnts.allSatisfy { $0 == want }
    let msgCnt = "散文的計數詞 \(pyRepr(cnts)) 與實際 \(n) 列不符"
    print("     散文計數與表一致：表 \(n) 列，散文說 \(cnts.isEmpty ? "?" : pyRepr(cnts)) \(check(okCnt, msgCnt))")

    if !fails.isEmpty {
        print("══ \(fails.count) 個宣稱不成立 ══")
        for m in fails { print("  ✗ \(m)") }
        return 1
    }
    print("══ 五列全部現查成立 ══")
    return 0
}
