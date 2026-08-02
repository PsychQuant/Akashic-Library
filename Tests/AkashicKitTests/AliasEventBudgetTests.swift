import XCTest
import Foundation
import Yams
@testable import AkashicCore

/// #36 / #27：event-level 的 alias 展開預算。
///
/// **三段齊備是判準本身**：擋得住已知攻擊（1）、不誤殺真實資料（2）、不誤殺 emitter
/// 自己的輸出（3）。前五次失敗（R5/R6/R10/R11/PR #42）都是只驗了第一段。
final class AliasEventBudgetTests: XCTestCase {

    private func bomb(levels: Int, fanout: Int, tail: String) -> String {
        var s = "a0: &a0 [x, x, x, x, x, x, x, x, x]\n"
        for i in 1...levels {
            let refs = (0..<fanout).map { _ in "*a\(i - 1)" }.joined(separator: ", ")
            s += "a\(i): &a\(i) [\(refs)]\n"
        }
        return s + tail
    }

    private func assertRefused(_ yaml: String, _ msg: String,
                               file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertThrowsError(try AliasEventBudget.check(yaml, context: "t"), msg,
                             file: file, line: line)
    }

    // MARK: - 1. 已知攻擊（含五輪累積的全部繞道）

    /// R12 的三條繞道。
    func testR12BypassesAreCaught() {
        assertRefused(bomb(levels: 14, fanout: 2, tail: "*a12: 1\n"), "block 隱式 alias key")
        assertRefused(bomb(levels: 14, fanout: 2, tail: "zz: {? *a12 : 1}\n"), "flow 顯式")
        assertRefused(bomb(levels: 14, fanout: 2, tail: "zz: {*a12: 1}\n"), "flow 隱式")
    }

    /// PR #42 的四條繞道——文字掃描全破，event level 全擋。
    func testPR42BypassesAreCaught() {
        // 裸 `>` 讓文字掃描把後續行當 block scalar 而整段跳過
        var gt = "key: a\nnames: [A]\nbomb:\n  - k: x > y\n"
        for l in bomb(levels: 14, fanout: 2, tail: "*a12: 1\n")
                    .split(separator: "\n") { gt += "    " + l + "\n" }
        assertRefused(gt, "`>` 致盲")

        // 跨行 flow collection
        var flow = "extra: [x > y,\n"
        flow += "  &a0 [q,q,q,q,q,q,q,q,q],\n"
        for i in 1...14 {
            flow += "  &a\(i) [" + (0..<9).map { _ in "*a\(i-1)" }.joined(separator: ",") + "],\n"
        }
        flow += "  {*a14: 1}]\n"
        assertRefused(flow, "跨行 flow")

        // CRLF——Swift 的 "\r\n" 是單一 grapheme，文字掃描不分行
        assertRefused(bomb(levels: 14, fanout: 2, tail: "*a12: 1\n")
                        .replacingOccurrences(of: "\n", with: "\r\n"), "CRLF")

        // `#` 判準：plain scalar 內的 `marker-#x` 讓文字掃描吃掉整行
        var hash = "root: {note: marker-#not-a-comment,\n"
        hash += "  a0: &a0 [x,x,x,x,x,x,x,x,x],\n"
        for i in 1...14 {
            hash += "  a\(i): &a\(i) [" + (0..<9).map { _ in "*a\(i-1)" }.joined(separator: ",") + "],\n"
        }
        hash += "  q: *a14}\n"
        assertRefused(hash, "`#` 判準")
    }

    /// **單一 anchor 也擋得住。** PR #42 的 `anchors >= 2` 合取讓這個完全放行——
    /// 單一 anchor 被引用 N 次是 (N+1)× 而非 2×，那是它的錯誤宣稱。
    func testSingleAnchorAmplificationIsCaught() {
        var s = "big: &a [" + (0..<2000).map { "i\($0)" }.joined(separator: ",") + "]\n"
        for i in 0..<200 { s += "k\(i): *a\n" }
        assertRefused(s, "單一 anchor × 多次引用")
    }

    /// **BYPASS（verify 實測）：節點數擋不住「重量」。** 19,000 次引用一個 5 KB scalar
    /// 只算 38,003 節點（過關），但展開後是 **95 MB**。節點是計數，bytes 是重量——
    /// 兩個軸都要。
    func testScalarByteWeightAmplificationIsCaught() {
        let big = String(repeating: "x", count: 5000)
        var s = "a: &a \"\(big)\"\n"
        for i in 0..<19000 { s += "k\(i): *a\n" }
        assertRefused(s, "scalar 重量放大")
    }

    /// **BYPASS（DA 找到、我端到端實證）：深度可以由 alias 展開產生而語法上完全是平的。**
    ///
    /// 這是 PR #49 被打回的原因（第 6 次失敗）。舊版守衛測 `openStack` 的**語法**巢狀
    /// 深度（值 = 2），而這個構造展開後是 8000 層：
    ///
    ///     root: &a0 x / k1: &a1 [*a0] / … / ? *a8000 : 1
    ///
    /// 180 KB、24,005 節點（遠低於門檻）→ 舊版**完全放行**，`akashic validate`
    /// **SIGSEGV（exit 139）**。libyaml 的 `MAX_NESTING_LEVEL` 也不觸發（只管語法）。
    ///
    /// **SIGSEGV 比 DoS 更嚴重**：DoS 會 timeout 然後 quarantine；SIGSEGV 是 Swift 的
    /// `catch` 抓不到的，沒有 quarantine 路徑——那個檔案會讓三個 consumer 每次載入都死。
    func testAliasExpansionDepthIsCaught() {
        func chain(_ lv: Int) -> String {
            var s = "root: &a0 x\n"
            for i in 1...lv { s += "k\(i): &a\(i) [*a\(i-1)]\n" }
            return s + "? *a\(lv)\n: 1\n"
        }
        assertRefused(chain(8000), "DA 的 8000 層（舊版 SIGSEGV）")
        assertRefused(chain(1000), "1000 層")
        // 語法深度必須是 2——證明舊判準確實看不到這個攻擊
        // （用 600 層版本，它剛好超過門檻但仍可估計到深度）
        XCTAssertNoThrow(try AliasEventBudget.estimate(chain(100)))
        let e = try? AliasEventBudget.estimate(chain(100))
        XCTAssertEqual(e?.maxDepthSeen, 102, "展開深度必須被追蹤到，不是語法深度 2")
    }

    /// **自攻擊：估計器的樹算術在三種構造下都不得低估。** DA 殺掉第 6 版靠的正是
    /// 「估計器自己算錯」，所以第 7 版必須先自己攻這一面。三者實測都被**深度軸**擋下
    /// （`tooDeep(513)`，不是撞到別的軸）。
    func testEstimatorArithmeticUnderAdversarialConstructions() {
        // forward reference：alias 指向之後才定義的 anchor（查表得 (1,0,1)）
        var fwd = "head: *aN\na0: &a0 x\n"
        for i in 1...3000 { fwd += "k\(i): &a\(i) [*a\(i-1)]\n" }
        fwd += "aN: &aN [*a3000]\n? *aN\n: 1\n"
        assertRefused(fwd, "forward reference 鏈")

        // anchor 重定義：後面的定義覆蓋前面記錄的 size
        var re = "a: &x [deep]\n"
        for i in 1...2000 { re += "k\(i): &d\(i) [\(i == 1 ? "*x" : "*d\(i-1)")]\n" }
        re += "shallow: &d2000 [q]\n? *d2000\n: 1\n"
        assertRefused(re, "anchor 重定義")

        // anchored 子樹**內部**含 alias——記錄的必須是完全展開的深度
        var nested = "base: &b0 x\n"
        for i in 1...600 { nested += "n\(i): &b\(i) [*b\(i-1)]\n" }
        nested += "wrap: &w [*b600]\n? *w\n: 1\n"
        assertRefused(nested, "anchored 子樹內含 alias")
    }

    /// **深度軸的誤殺面**：一般 entry 的展開深度是 5、#20 的 temporal person 是 6。
    /// 門檻 512 留了 85–100× 餘裕。`d + openStack.count` 不得灌水——若這裡的數字變大，
    /// 代表會計方式出了問題。
    func testOrdinaryRecordsHaveShallowDepth() throws {
        var e = Entry(id: UUID(), citekey: "a2020a", type: "article", title: "T",
                      authors: [.literal("X"), .key("p-one")], date: "2020")
        e.fields["journaltitle"] = "J"; e.akashic.tags = ["t1", "t2"]
        e.akashic.relations.cites = ["b2020b"]
        XCTAssertEqual(try AliasEventBudget.estimate(try EntryYAML.encode(e)).maxDepthSeen, 5)

        var p = Person(key: "big", names: (0..<30).map { "A\($0)" })
        let tl = Timeline((0..<200).map {
            TemporalValue(value: "v\($0)", range: DateRange(start: "2000", end: "2001"),
                          source: "s", note: "n")
        })
        p.profile.affiliations = tl; p.profile.ranks = tl; p.profile.contacts = ["email": tl]
        XCTAssertEqual(try AliasEventBudget.estimate(try PersonYAML.encode(p)).maxDepthSeen, 6)
    }

    /// 語法巢狀同樣要擋——但**上限設在合法可解析範圍之內就是誤殺**：
    /// 實測 500 層的 `[[[…]]]` 仍能被 Yams 正常 compose，所以 512 是下界。
    func testExcessiveSyntacticNestingIsAlsoCaught() {
        assertRefused("a: " + String(repeating: "[", count: 600)
                      + String(repeating: "]", count: 600) + "\n", "超過 512 層")
    }

    /// **上限設在合法可解析範圍之內就是誤殺。** 實測 500 層仍能被 Yams 正常 compose，
    /// 所以 512 是下界；真實書目資料是個位數。
    func testLegitimateNestingDepthPasses() throws {
        // 真實形狀：tolerant-preserve 的未知子樹，10 層已遠超實際
        var s = "id: 11111111-1111-1111-1111-111111111111\ncitekey: a2020a\ntype: article\n"
        s += "title: T\nauthors:\n  - literal: X\nextra:\n"
        var indent = "  "
        for i in 0..<10 { s += "\(indent)level\(i):\n"; indent += "  " }
        s += "\(indent)leaf: value\n"
        XCTAssertNoThrow(try AliasEventBudget.check(s, context: "t"))
        // 500 層 flow：Yams 能 compose，所以守衛也不得擋
        XCTAssertNoThrow(try AliasEventBudget.check(
            "a: " + String(repeating: "[", count: 500)
            + String(repeating: "]", count: 500) + "\n", context: "t"))
    }

    /// **超大 scalar**——§5 記載的另一個未防護面，一個節點也能有數百 MB。
    func testOversizedInputIsRefused() {
        let huge = "title: " + String(repeating: "x", count: 9 * 1024 * 1024) + "\n"
        assertRefused(huge, "超大輸入")
    }

    /// 引號、註解、block scalar 內的 alias-looking 內容**不是** alias——
    /// 這是 parser 的判斷，不是我的猜測。
    func testAliasLikeTextInsideScalarsIsNotCounted() throws {
        let e = try AliasEventBudget.estimate("""
            a: "&anchor *alias"
            b: '&x *y'
            c: |
              &a *b &c *d
            # &e *f
            d: R&D and *emphasis*
            """)
        XCTAssertEqual(e.aliases, 0, "純量內容被當成 alias")
        XCTAssertEqual(e.anchors, 0)
    }

    /// **估計值必須精確等於真實展開量。** 這是整個估計器的正確性判準——不是「夠接近」，
    /// 是相等。verify 抓到的 off-by-one（記錄 anchored 子樹大小時漏算 collection 自己）
    /// 單看是差一，鏈起來卻累積成 84 倍。
    func testEstimateEqualsGroundTruth() throws {
        func trueNodes(_ n: Node) -> Int {
            switch n {
            case .scalar: return 1
            case .sequence(let s): return 1 + s.reduce(0) { $0 + trueNodes($1) }
            case .mapping(let m): return 1 + m.reduce(0) { $0 + trueNodes($1.key) + trueNodes($1.value) }
            case .alias: return 1
            }
        }
        var chain = "root: &a0 x\n"
        for i in 1...50 { chain += "k\(i): &a\(i) [*a\(i-1)]\n" }
        var fan = "a0: &a0 [x,x,x,x,x,x,x,x,x]\n"
        for i in 1...6 { fan += "a\(i): &a\(i) [*a\(i-1),*a\(i-1)]\n" }
        fan += "zz: *a6\n"
        for (name, y) in [("benign", "base: &b [x,y,z]\nuse: *b\n"),
                          ("plain", "a: 1\nb: [x,y]\nc: {d: e}\n"),
                          ("chain50", chain), ("fan2x6", fan)] {
            let est = try AliasEventBudget.estimate(y, nodeLimit: Int.max).expandedNodes
            let truth = try Yams.compose(yaml: y).map { trueNodes($0) } ?? 0
            XCTAssertEqual(est, truth, "\(name)：估計與真實展開量必須相等")
        }
    }

    /// **verify 的 1.1 MB bypass**：chain 509 層讓 anchored size 被低估，再用 19 萬個
    /// alias 放在 key 位置放大——修前四個軸全過、真實展開 9.7e7 節點。
    func testCriticalChainUnderestimateBypass() {
        var s = "root: &a0 x\n"
        for i in 1...509 { s += "k\(i): &a\(i) [*a\(i-1)]\n" }
        s += "? [" + (0..<190_000).map { _ in "*a509" }.joined(separator: ",") + "]\n: 1\n"
        assertRefused(s, "chain 低估 + key 位置放大")
    }

    /// **節點軸只對有 alias 的輸入有意義。** alias-free 的檔案放大定義上不可能，
    /// 成本由 `maxBytes` 已界住。不 gate 的話 1.8 MB 的正常大檔會被擋並告知
    /// 「這是攻擊的形狀」——那是誤殺，而且訊息還是錯的。
    func testAliasFreeLargeFileIsNotRefused() throws {
        var s = "a: 1\n"
        for i in 0..<120_000 { s += "k\(i): v\(i)\n" }
        let e = try AliasEventBudget.estimate(s)
        XCTAssertEqual(e.aliases, 0)
        XCTAssertGreaterThan(e.expandedNodes, AliasEventBudget.maxExpandedNodes,
                             "這個檔的節點數確實超過門檻——重點是它仍不得被擋")
        XCTAssertNoThrow(try AliasEventBudget.check(s, context: "t"))
    }

    /// **write path 需要遲滯。** 讀寫用完全相同的門檻 → 一筆 199,999 節點的記錄讀得進來，
    /// 但下次編輯多一個節點就永遠寫不回，使用者的修改被丟掉。R9 對 oracle 預算做過
    /// 同一件事（「放寬為 2×，避免『讀得到但永遠寫不回』的邊界檔」）。
    func testWritePathHasHysteresis() throws {
        var p = Person(key: "big", names: ["A"])
        let tl = Timeline((0..<2600).map {
            TemporalValue(value: "v\($0)", range: DateRange(start: "2000", end: "2001"),
                          source: "s", note: "n")
        })
        p.profile.affiliations = tl; p.profile.ranks = tl; p.profile.administrative = tl
        p.profile.appointments = tl; p.profile.fields = tl
        p.profile.contacts = ["email": tl, "phone": tl]
        XCTAssertNoThrow(try PersonYAML.encode(p), "讀得進來的記錄必須寫得回去")
    }

    // MARK: - 2. 不誤殺真實資料

    /// 良性 alias（單一 anchor、單次引用）正常通過。
    func testBenignAliasPasses() throws {
        XCTAssertNoThrow(try AliasEventBudget.check("base: &b [x, y, z]\nuse: *b\n", context: "t"))
    }

    /// 真實 corpus 全數通過。找不到時明確 skip，**不靜默 pass**。
    func testRealCorpusPasses() throws {
        let dir = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".akashic/entities")
        guard let files = try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil), !files.isEmpty else {
            throw XCTSkip("找不到真實 corpus——跳過，不當作通過")
        }
        var n = 0, maxNodes = 0
        for f in files where f.pathExtension.lowercased() == "yaml" {
            guard let t = try? String(contentsOf: f, encoding: .utf8) else { continue }
            n += 1
            let e = try AliasEventBudget.estimate(t)
            maxNodes = max(maxNodes, e.expandedNodes)
            XCTAssertNoThrow(try AliasEventBudget.check(t, context: f.lastPathComponent))
        }
        XCTAssertGreaterThan(n, 100, "corpus 太小，證明力不足")
        // 門檻要留足夠餘裕——真實最大檔與門檻至少差兩個數量級
        XCTAssertLessThan(maxNodes * 100, AliasEventBudget.maxExpandedNodes,
                          "真實最大檔 \(maxNodes) 節點，門檻餘裕不足")
    }

    /// **把「文件裡的數字」變成可證偽的斷言**（PR #42 的教訓機械化）。
    ///
    /// PR #42 的頭號宣稱「corpus 536 檔為 0 個 anchor/alias」是假的——作者量了
    /// `exceedsBudget`（全 false）卻寫成「0 個」。這一輪我又犯一次同型：§5 寫
    /// 「corpus 最大 ~700 節點」，實測是 **180**（沿用了未重量過的舊估計）。
    ///
    /// 所以把數字釘進測試：**文件改了而實測沒跟上，測試就失敗。**
    func testDocumentedMeasurementsMatchReality() throws {
        // 合法最壞情形（#20 的 temporal person）
        var p = Person(key: "big", names: (0..<30).map { "A\($0)" })
        let tl = Timeline((0..<200).map {
            TemporalValue(value: "v\($0)",
                          range: DateRange(start: "20\($0 % 90)", end: "20\(($0 + 1) % 90)"),
                          source: "https://example.org/\($0)", note: "note \($0)")
        })
        p.profile.affiliations = tl; p.profile.ranks = tl; p.profile.administrative = tl
        p.profile.appointments = tl; p.profile.fields = tl
        p.profile.contacts = ["email": tl, "phone": tl]
        let worst = try AliasEventBudget.estimate(try PersonYAML.encode(p))
        XCTAssertEqual(worst.expandedNodes, 15_457, "§5 記載的合法最壞情形變了，文件要同步")

        // 已知最小 bomb
        var b = "a0: &a0 [x,x,x,x,x,x,x,x,x]\n"
        for i in 1...12 {
            b += "a\(i): &a\(i) [" + (0..<2).map { _ in "*a\(i-1)" }.joined(separator: ",") + "]\n"
        }
        b += "*a12: 1\n"
        XCTAssertEqual(b.utf8.count, 262, "§5 記載的構造大小變了")
        // **這個構造不需要被擋**——實測 compose 只要 0.01 s。文件曾把它誤稱為
        // 「已知最小 bomb」，量了才知道節點數多不等於 compose 貴。
        XCTAssertNoThrow(try AliasEventBudget.check(b, context: "t"))

        // **真正會痛的**：fanout 9 × 7 層（357 B、compose 4.8 s）必須被擋，
        // 而且門檻要擋在痛點**之前**——fanout 9 × 5 層（0.118 s）就該超標。
        func fan9(_ lv: Int) -> String {
            var s = "a0: &a0 [x,x,x,x,x,x,x,x,x]\n"
            for i in 1...lv {
                s += "a\(i): &a\(i) [" + (0..<9).map { _ in "*a\(i-1)" }.joined(separator: ",") + "]\n"
            }
            return s + "*a\(lv): 1\n"
        }
        assertRefused(fan9(7), "真正會痛的構造")
        assertRefused(fan9(5), "門檻必須擋在痛點之前")

        // 餘裕：合法最壞情形與門檻的距離
        XCTAssertEqual(AliasEventBudget.maxExpandedNodes / worst.expandedNodes, 12,
                       "§5 記載的餘裕倍數變了")
    }

    /// **CI 也要有防護**：不依賴外部檔案的內建書目樣本，含 PR #42 誤殺的形態。
    func testBundledBibliographicCorpusPasses() throws {
        for v in ["A*-search and IDA* variants", "C*-algebras", "R&D expenditure & innovation",
                  "*Emphasis* and **strong**", "p < .05 * p < .01 ** p < .001 ***",
                  "https://example.org/a?b=1&c=2&d=3&e=4", "S&P 500 & Russell 2000",
                  "Science &amp; Nature &amp; Society",
                  "Human Female *Achievement *Motivation *Learning *Memory",
                  "&anchor *alias &more *refs &yet *again"] {
            var e = Entry(id: UUID(), citekey: "corp2020a", type: "article",
                          title: v, authors: [.literal(v)], date: "2020")
            e.fields["abstract"] = v + "\n\n" + v
            let yaml = try EntryYAML.encode(e)
            XCTAssertNoThrow(try AliasEventBudget.check(yaml, context: "t"),
                             "書目內容被誤殺：\(v.debugDescription)")
        }
    }

    /// **門檻必須由合法資料的最壞情形校準，不是由現況。** #20 的 temporal person
    /// （六個維度 × 200 段 + 聯絡資訊）估到約 15,000 節點——那是**合法資料**，
    /// 而 #20 明說「全部維度都要記錄歷史」。門檻若貼著現況設，這種記錄會被誤殺，
    /// 而誤殺代表**永久寫不回**（encode canary 也走這道守衛）。
    func testLegitimateTemporalPersonHasWideMargin() throws {
        var p = Person(key: "big-person", names: (0..<30).map { "Alias \($0)" })
        let tl = Timeline((0..<200).map {
            TemporalValue(value: "v\($0)",
                          range: DateRange(start: "20\($0 % 90)", end: "20\(($0 + 1) % 90)"),
                          source: "https://example.org/\($0)", note: "note \($0)")
        })
        p.profile.affiliations = tl; p.profile.ranks = tl
        p.profile.administrative = tl; p.profile.appointments = tl; p.profile.fields = tl
        p.profile.contacts = ["email": tl, "phone": tl]
        let yaml = try PersonYAML.encode(p)          // encode canary 也走守衛
        let e = try AliasEventBudget.estimate(yaml)
        XCTAssertLessThan(e.expandedNodes * 10, AliasEventBudget.maxExpandedNodes,
                          "合法的 temporal person 估到 \(e.expandedNodes) 節點，"
                          + "門檻 \(AliasEventBudget.maxExpandedNodes) 餘裕不足 10×")
        XCTAssertEqual(try PersonYAML.decode(yaml), p)
    }

    /// 45 位作者（真實 corpus 的實際最大值）+ 大量欄位。
    func testLargeAuthorListHasWideMargin() throws {
        var e1 = Entry(id: UUID(), citekey: "big2020a", type: "article",
                       title: String(repeating: "Long title ", count: 40),
                       authors: (0..<45).map { .literal("Author Number \($0) With A Long Name") },
                       date: "2020")
        for i in 0..<40 {
            e1.fields["field\(i)"] = String(repeating: "value ", count: 100)
        }
        let yaml = try EntryYAML.encode(e1)
        let e = try AliasEventBudget.estimate(yaml)
        XCTAssertLessThan(e.expandedNodes * 100, AliasEventBudget.maxExpandedNodes,
                          "45 作者的 entry 估到 \(e.expandedNodes) 節點")
    }

    // MARK: - 3. 不誤殺 emitter 自己的輸出（R11 與 PR #42 的死因）

    /// **含跨行折行的長 abstract**——PR #42 正是死在這裡（Yams 對 >80 欄的純量必折行，
    /// 而它的掃描器每行重設引號狀態）。
    func testEmitterOutputNeverTripsBudget() throws {
        let long = "Findings: *significant* at *p* < .05, *robust* across *samples*, "
            + "and *replicable*. Compare with Harcourt, Brace & World and Little, Brown & Co. "
            + String(repeating: "Additional discussion text. ", count: 20)
        for t in [long, "R&D and *emphasis*", "&anchor", "*alias", "? explicit",
                  "A & B & C & D & E", "* * * * * *", String(repeating: "k", count: 200),
                  "line1\nline2\nline3", "「中文」與 & 和 *"] {
            var e = Entry(id: UUID(), citekey: "test2020a", type: "article",
                          title: t, authors: [.literal(t)], date: "2020")
            e.fields["note"] = t
            e.fields["abstract"] = long
            let yaml = try EntryYAML.encode(e)
            XCTAssertNoThrow(try AliasEventBudget.check(yaml, context: "t"),
                             "emitter 自我毒化：\(t.prefix(40).debugDescription)")
            XCTAssertEqual(try EntryYAML.decode(yaml).title, t)
        }
    }

    // MARK: - 掃描成本與輸入大小成正比（不隨展開量爆炸）

    /// 這是 event level 相對於 compose 的**根本差異**——`Yams.compose` 對同一個檔要
    /// 25 秒，這裡是毫秒級。
    func testScanCostIsProportionalToInputNotExpansion() throws {
        let payload = bomb(levels: 24, fanout: 2, tail: "*a24: 1\n")
        XCTAssertLessThan(payload.utf8.count, 2000, "payload 本身很小")
        let t0 = Date()
        assertRefused(payload, "應擋下")
        let dt = Date().timeIntervalSince(t0)
        XCTAssertLessThan(dt, 1.0, "掃描耗時 \(dt)s——event level 不該隨展開量增長")
    }
}
