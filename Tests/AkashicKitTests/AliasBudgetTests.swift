import XCTest
import Foundation
@testable import AkashicCore

/// #36 / #27：compose 之前的 alias 展開預算。
///
/// **這個測試檔的三段結構就是判準本身**：擋得住已知攻擊（1）、不誤殺真實資料（2）、
/// 不誤殺自己 emitter 的輸出（3）。R11 的守衛之所以災難，正是因為只驗了第一段。
final class AliasBudgetTests: XCTestCase {

    // MARK: - 1. 已知攻擊必須擋下（含 R12 實測的三條繞道）

    /// billion-laughs：N 個 anchor 各引用前一個 k 次。
    private func bomb(levels: Int, fanout: Int, tail: String) -> String {
        var s = "a0: &a0 \"x\"\n"
        for i in 1...levels {
            let refs = (0..<fanout).map { _ in "*a\(i - 1)" }.joined(separator: ", ")
            s += "a\(i): &a\(i) [\(refs)]\n"
        }
        return s + tail
    }

    func testBlockImplicitAliasKeyBypassIsCaught() {
        // R12 繞道 ①：alias 直接當 block 隱式鍵，完全沒有 `? `
        XCTAssertTrue(AliasBudget.scan(bomb(levels: 12, fanout: 2, tail: "*a12: 1\n")).exceedsBudget)
    }
    func testFlowExplicitAliasKeyBypassIsCaught() {
        // R12 繞道 ②
        XCTAssertTrue(AliasBudget.scan(bomb(levels: 12, fanout: 2, tail: "zz: {? *a12 : 1}\n")).exceedsBudget)
    }
    func testFlowImplicitAliasKeyBypassIsCaught() {
        // R12 繞道 ③
        XCTAssertTrue(AliasBudget.scan(bomb(levels: 12, fanout: 2, tail: "zz: {*a12: 1}\n")).exceedsBudget)
    }
    func testValueSideBombAlsoCaught() {
        // #27：known-field 路徑的值側放大同樣無防線
        XCTAssertTrue(AliasBudget.scan(bomb(levels: 12, fanout: 2, tail: "title: *a12\n")).exceedsBudget)
    }

    /// 單一 anchor 最多放大 2×——**不該**被擋。判準是「能不能指數展開」，不是「有沒有 alias」。
    func testSingleAnchorAndAliasIsHarmlessAndAllowed() {
        let benign = "base: &b {x: 1}\nuse: *b\n"
        let c = AliasBudget.scan(benign)
        XCTAssertEqual(c.anchors, 1)
        XCTAssertEqual(c.aliases, 1)
        XCTAssertFalse(c.exceedsBudget)
    }

    // MARK: - 2. 掃描器不得把資料誤認成語法

    func testAmpersandAndStarInsideScalarsAreNotCounted() {
        let cases = [
            "title: R&D methods\n",                       // token 中間的 &
            "title: \"A & B * C\"\n",                     // 雙引號內
            "title: 'it''s A & B * C'\n",                 // 單引號內（含 '' 逸出）
            "note: 2 * 3 = 6\n",                          // 前後有空白的裸 *（不是 alias）
            "# &anchor *alias 在註解裡\ntitle: T\n",       // 註解
            "body: |\n  &notanchor\n  *notalias\n",       // block scalar 內容
            "body: >\n  &a *b &c *d &e *f\n",             // folded scalar 內容
        ]
        for c in cases {
            let n = AliasBudget.scan(c)
            XCTAssertEqual(n.anchors + n.aliases, 0,
                           "誤把資料當語法：\(c.debugDescription) → \(n)")
        }
    }

    /// 空行不結束 block scalar——否則長文字欄位中段的 `&`/`*` 會被誤計。
    func testBlankLineDoesNotEndBlockScalar() {
        let s = "body: |\n  &a *b\n\n  &c *d\nnext: 1\n"
        XCTAssertEqual(AliasBudget.scan(s).anchors + AliasBudget.scan(s).aliases, 0)
    }

    // MARK: - 2b. reviewer probe 實測抓到的繞道（#42 verify）

    /// **裸 `>` 不是 block scalar 標頭**。`k: x > y` 的 `>` 是純量內容；把它當標頭
    /// 會讓掃描器把**後面所有行**當成 block scalar 內容而整段跳過——bomb 藏在那裡
    /// 就完全掃不到。這條由 verify 的 reviewer probe 實測發現。
    func testBareGreaterThanInScalarIsNotBlockScalarHeader() {
        var s = "key: a\nnames: [A]\nbomb:\n  - k: x > y\n"
        s += "    a0: &a0 [x, x, x, x]\n"
        for i in 1...10 {
            s += "    a\(i): &a\(i) [*a\(i-1), *a\(i-1)]\n"
        }
        s += "    *a10: 1\n"
        XCTAssertTrue(AliasBudget.scan(s).exceedsBudget,
                      "裸 `>` 讓掃描器整段跳過 → 繞道：\(AliasBudget.scan(s))")
    }

    /// 同理：`a: b | c`、`x: 3 > 2` 之類都不是標頭。
    func testPipeAndGreaterInPlainScalarsDoNotSuppressScanning() {
        for prefix in ["k: a | b\n", "k: 3 > 2\n", "k: x|y\n", "zz: {k: 3 > 2}\n"] {
            var s = "key: a\nnames: [A]\n" + prefix + "a0: &a0 [x]\n"
            for i in 1...6 { s += "a\(i): &a\(i) [*a\(i-1), *a\(i-1)]\n" }
            XCTAssertTrue(AliasBudget.scan(s).exceedsBudget, "被 \(prefix.debugDescription) 抑制")
        }
    }

    /// 真正的 block scalar 標頭（含 chomping / 明確縮排）仍要正確識別，
    /// 否則內容裡的 `&`/`*` 會被誤計成語法。
    func testGenuineBlockScalarHeadersStillRecognised() {
        for header in ["body: |", "body: >", "body: |-", "body: >+", "body: |2", "body: >2-",
                       "body: |  # 註解", "body: >-   # 註解"] {
            let s = header + "\n  &a *b &c *d &e *f\n  &g *h &i *j\n"
            let c = AliasBudget.scan(s)
            XCTAssertEqual(c.anchors + c.aliases, 0, "\(header.debugDescription) 未被識別 → \(c)")
        }
    }

    /// CRLF 行尾：`split(on: "\n")` 會在行尾留 `\r`，不處理會影響 token 判定。
    func testCRLFLineEndingsDoNotDefeatScanning() {
        var s = "key: a\nnames: [A]\na0: &a0 [x]\n"
        for i in 1...6 { s += "a\(i): &a\(i) [*a\(i-1), *a\(i-1)]\n" }
        s += "*a6: 1\n"
        let crlf = s.replacingOccurrences(of: "\n", with: "\r\n")
        XCTAssertTrue(AliasBudget.scan(crlf).exceedsBudget, "CRLF 版本被繞過")
    }

    // MARK: - 3. 不得誤殺 emitter 自己的輸出（R11 就是死在這裡）

    /// 把對抗性字串當成真實欄位值寫出去再掃回來。**emitter 自我毒化是 R11 的致命傷**：
    /// 守衛拒絕了自己寫出的檔，使記錄永久無法寫入。
    func testEmitterOutputNeverTripsTheBudget() throws {
        let hostileTitles = [
            "R&D and *emphasis*", "&anchor", "*alias", "? explicit", "A & B & C & D & E",
            "* * * * * *", "&&&& ****", String(repeating: "k", count: 200),
            "a: b: c", "- - -", "{flow: yes}", "[a, b]", "line1\nline2\nline3",
            "  leading spaces", "trailing  ", "\ttab", "「中文」與 & 和 *",
        ]
        for t in hostileTitles {
            var e = Entry(id: UUID(), citekey: "test2020a", type: "article",
                          title: t, authors: [.literal(t)], date: "2020")
            e.fields["note"] = t
            let yaml = try EntryYAML.encode(e)
            let c = AliasBudget.scan(yaml)
            XCTAssertFalse(c.exceedsBudget,
                           "emitter 自我毒化：title=\(t.debugDescription) → \(c)\n\(yaml)")
            // 而且必須能讀回來——守衛不得讓 round-trip 斷掉
            let back = try EntryYAML.decode(yaml)
            XCTAssertEqual(back.title, t)
        }
    }

    /// **CI 也要有保護**：真實 corpus 測試在沒有 `~/.akashic` 的機器上永遠 skip，
    /// 等於 CI 完全沒有 false-positive 防護。這個測試用**內建**的書目樣本補上——
    /// 內容取自真實書目會出現的形態（數學/化學/演算法名稱、markdown 強調、R&D、
    /// 中日文、URL、DOI、長摘要），不依賴任何外部檔案。
    func testBundledBibliographicCorpusHasNoFalsePositives() throws {
        let hostileFields = [
            "A*-search and IDA* variants", "C*-algebras and von Neumann algebras",
            "R&D expenditure & innovation", "*Emphasis* and **strong** in markdown",
            "Ca2+ & Mg2+ transport", "p < .05 * p < .01 ** p < .001 ***",
            "Item response theory: 2PL & 3PL models",
            "https://example.org/a?b=1&c=2&d=3&e=4&f=5",
            "10.1000/abc&def*ghi", "多變量分析：主成分 & 因素分析",
            "統計的推測 * 検定 & 推定", "S&P 500 & Russell 2000",
            "AT&T Bell Labs & IBM Research", "α & β & γ & δ & ε",
            "* * * * * * * * * *", "& & & & & & & & & &",
            "&anchor *alias &more *refs &yet *again",   // 全部都在純量裡
        ]
        for (i, v) in hostileFields.enumerated() {
            var e = Entry(id: UUID(), citekey: "corp\(2000 + i)a", type: "article",
                          title: v, authors: [.literal(v)], date: "2020")
            e.fields["journaltitle"] = v
            e.fields["abstract"] = v + "\n\n" + v
            let yaml = try EntryYAML.encode(e)
            let c = AliasBudget.scan(yaml)
            XCTAssertFalse(c.exceedsBudget,
                           "書目內容被誤殺：\(v.debugDescription) → \(c)\n\(yaml)")
            XCTAssertEqual(try EntryYAML.decode(yaml).title, v)
        }
    }

    /// 真實 corpus 若在本機則額外驗。找不到時明確 skip，**不靜默 pass**——
    /// CI 的防護由上面那個內建 corpus 提供，這個是本機的加碼。
    func testRealCorpusHasNoFalsePositives() throws {
        let entries = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".akashic/entries")
        guard let files = try? FileManager.default.contentsOfDirectory(
                at: entries, includingPropertiesForKeys: nil),
              !files.isEmpty else {
            throw XCTSkip("找不到真實 corpus（~/.akashic/entries）——跳過，不當作通過")
        }
        var scanned = 0, tripped: [String] = []
        for f in files where f.pathExtension.lowercased() == "yaml" {
            guard let text = try? String(contentsOf: f, encoding: .utf8) else { continue }
            scanned += 1
            if AliasBudget.scan(text).exceedsBudget { tripped.append(f.lastPathComponent) }
        }
        XCTAssertGreaterThan(scanned, 100, "corpus 太小，證明力不足")
        XCTAssertTrue(tripped.isEmpty, "真實資料被誤殺 \(tripped.count) 檔：\(tripped.prefix(5))")
    }
}
