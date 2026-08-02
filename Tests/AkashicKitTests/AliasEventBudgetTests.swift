import XCTest
import Foundation
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
        assertRefused(bomb(levels: 12, fanout: 2, tail: "*a12: 1\n"), "block 隱式 alias key")
        assertRefused(bomb(levels: 12, fanout: 2, tail: "zz: {? *a12 : 1}\n"), "flow 顯式")
        assertRefused(bomb(levels: 12, fanout: 2, tail: "zz: {*a12: 1}\n"), "flow 隱式")
    }

    /// PR #42 的四條繞道——文字掃描全破，event level 全擋。
    func testPR42BypassesAreCaught() {
        // 裸 `>` 讓文字掃描把後續行當 block scalar 而整段跳過
        var gt = "key: a\nnames: [A]\nbomb:\n  - k: x > y\n"
        for l in bomb(levels: 12, fanout: 2, tail: "*a12: 1\n")
                    .split(separator: "\n") { gt += "    " + l + "\n" }
        assertRefused(gt, "`>` 致盲")

        // 跨行 flow collection
        var flow = "extra: [x > y,\n"
        flow += "  &a0 [q,q,q,q,q,q,q,q,q],\n"
        for i in 1...12 {
            flow += "  &a\(i) [" + (0..<9).map { _ in "*a\(i-1)" }.joined(separator: ",") + "],\n"
        }
        flow += "  {*a12: 1}]\n"
        assertRefused(flow, "跨行 flow")

        // CRLF——Swift 的 "\r\n" 是單一 grapheme，文字掃描不分行
        assertRefused(bomb(levels: 12, fanout: 2, tail: "*a12: 1\n")
                        .replacingOccurrences(of: "\n", with: "\r\n"), "CRLF")

        // `#` 判準：plain scalar 內的 `marker-#x` 讓文字掃描吃掉整行
        var hash = "root: {note: marker-#not-a-comment,\n"
        hash += "  a0: &a0 [x,x,x,x,x,x,x,x,x],\n"
        for i in 1...12 {
            hash += "  a\(i): &a\(i) [" + (0..<9).map { _ in "*a\(i-1)" }.joined(separator: ",") + "],\n"
        }
        hash += "  q: *a12}\n"
        assertRefused(hash, "`#` 判準")
    }

    /// **單一 anchor 也擋得住。** PR #42 的 `anchors >= 2` 合取讓這個完全放行——
    /// 單一 anchor 被引用 N 次是 (N+1)× 而非 2×，那是它的錯誤宣稱。
    func testSingleAnchorAmplificationIsCaught() {
        var s = "big: &a [" + (0..<2000).map { "i\($0)" }.joined(separator: ",") + "]\n"
        for i in 0..<200 { s += "k\(i): *a\n" }
        assertRefused(s, "單一 anchor × 多次引用")
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
