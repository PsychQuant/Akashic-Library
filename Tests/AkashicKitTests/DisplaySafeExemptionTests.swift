import XCTest
import Foundation

/// #584：`display-safe-exempt:` 註記的豁免規則本身（`DisplaySafeExemption`）——兩支守衛共用的那一份。
///
/// 兩支守衛（sink 守衛與擲出站點守衛）各有自己的端到端測試；這裡釘的是**它們共用的謂詞**，
/// 因為兩份判準各自演化是本 repo 反覆記過的分岔形狀（#554 R32 verify regression 第 37 列：R31 只改了其中一支）。
final class DisplaySafeExemptionTests: XCTestCase {
    func testOnlyTheTextAfterTheMarkerContributesNotes() {
        let lines = [
            "let a = entry.title   // display-safe-exempt: idx 是 Int",
            "no marker here, entry.title 出現在這裡不算",
            "let b = 1   // display-safe-exempt: 第二行的註記",
        ]
        let notes = DisplaySafeExemption.notes(in: lines)
        XCTAssertTrue(notes.contains("idx 是 Int"))
        XCTAssertTrue(notes.contains("第二行的註記"))
        XCTAssertFalse(notes.contains("let a"), "標記之前是程式碼，不得進註記文字")
        XCTAssertFalse(notes.contains("no marker here"), "沒有標記的行不貢獻")
        XCTAssertEqual(DisplaySafeExemption.notes(in: ["let a = 1"]), "")
        XCTAssertFalse(DisplaySafeExemption.names("idx", in: ""), "沒有註記就沒有具名")
    }

    func testAnExpressionIsNamedByItsFirstIdentifierAsAWholeWord() {
        XCTAssertTrue(DisplaySafeExemption.names("entry.citekey", in: "entry.citekey 過 quarantine"))
        XCTAssertTrue(DisplaySafeExemption.names("idx", in: "idx 是 Int"))
        XCTAssertFalse(DisplaySafeExemption.names("entry.citekey", in: "citekey 過 quarantine"),
                       "只寫成員名不算具名——第一個識別字是 entry")
        // 完整字詞：`id` 不被 `identity`、`ids`、`mid` 具名
        XCTAssertFalse(DisplaySafeExemption.names("id", in: "identity 與 ids 與 mid"))
        XCTAssertTrue(DisplaySafeExemption.names("id", in: "id.uuidString 是固定 ASCII"))
        // `$0` 是識別字元：`$0` 被具名，`x0` 與 `$01` 不算
        XCTAssertTrue(DisplaySafeExemption.names("$0.message", in: "$0.message 已消毒"))
        XCTAssertFalse(DisplaySafeExemption.names("$0.message", in: "x0 與 $01"))
        // 成員鏈裡的名字不指認同名的裸識別字（#584 R1 verify 第 5 列）：註記講 `entry.title`，不得讓另一個值 `title` 免檢
        XCTAssertFalse(DisplaySafeExemption.names("title", in: "entry.title 已消毒"),
                       "註記具名的是 entry.title；裸的 title 是另一個值（可能是未消毒的 store 字串）")
        XCTAssertFalse(DisplaySafeExemption.names("citekey", in: "entry.citekey：過 quarantine"))
        XCTAssertTrue(DisplaySafeExemption.names("title", in: "title 已消毒；entry.title 也是"), "裸的 title 自己被具名時照放行")
        XCTAssertTrue(DisplaySafeExemption.names("entry.title", in: "entry.title 已消毒"))
    }

    func testLeadingKeywordsAreNotTheSubject() {
        for kw in ["return", "try", "try?", "try!", "await"] {
            XCTAssertTrue(DisplaySafeExemption.names("\(kw) entry.title", in: "entry.title 是常量"), kw)
            XCTAssertFalse(DisplaySafeExemption.names("\(kw) entry.title", in: "\(kw) 是關鍵字"),
                           "關鍵字不指認任何值：\(kw)")
        }
    }

    func testClipOnlyIsNamedByItsCarrierNotByTheFunction() {
        let e = "displaySafeClipOnly($0.issue.message, max: 300)"
        XCTAssertTrue(DisplaySafeExemption.names(e, in: "$0.issue.message 已消毒"))
        XCTAssertFalse(DisplaySafeExemption.names(e, in: "displaySafeClipOnly 已消毒，只截"),
                       "函式名不指認任何值——它是只截不逃，載體才是要擔保的東西")
        // 只有整條是 clipOnly 才拆；clipOnly 只是運算式的一部分時，主詞是整條的第一個識別字
        XCTAssertFalse(DisplaySafeExemption.names("displaySafeClipOnly(x, max: 1) + entry.title", in: "x 已消毒"))
    }

    func testStringLiteralsAreCheckedPieceByPiece() {
        // 字面文字是程式文字；每個非字面運算元、每個插值都要各自被具名
        XCTAssertFalse(DisplaySafeExemption.names(#""\(label)" + entry.title"#, in: "label 是字面常量"),
                       "註記講 label 不得讓串接的 entry.title 免檢")
        XCTAssertTrue(DisplaySafeExemption.names(#""\(label)" + entry.title"#, in: "label 是字面常量；entry.title 是消毒投影"))
        XCTAssertFalse(DisplaySafeExemption.names(#""\(label)：\(entry.title)""#, in: "label 是字面常量"))
        XCTAssertTrue(DisplaySafeExemption.names(#""\(label)：\(entry.title)""#, in: "label、entry.title"))
        XCTAssertTrue(DisplaySafeExemption.names(#""只有字面文字""#, in: "隨便一句"), "沒有任何運算式的字面不需要具名")
    }

    // MARK: - 複合運算式：拆不開的形狀一律不豁免（#584 R1 verify 第 4／10／15／23 列）

    /// 一個運算式裡有不只一個運算元時，**每一個**帶執行期資料的運算元都要各自被具名——具名第一個不讓其餘免檢。
    /// 這是 issue 原情境（「真的未消毒的運算式與安全的運算式並排、註記只講後者」）在**單一運算式內部**的版本。
    func testEveryOperandOfACompoundExpressionMustBeNamed() {
        func n(_ e: String, _ note: String) -> Bool { DisplaySafeExemption.names(e, in: note) }
        // 頂層 `+`
        XCTAssertFalse(n("idx + entry.title", "idx 是 Int"))
        XCTAssertTrue(n("idx + entry.title", "idx 是 Int；entry.title 是消毒投影"))
        // 三元：條件與兩個分支都要具名（或是常量）
        XCTAssertFalse(n("cond ? unsafe.title : \"\"", "cond 是 Bool"))
        XCTAssertFalse(n("cond ? \"\" : unsafe.title", "cond 是 Bool"))
        XCTAssertTrue(n("cond ? unsafe.title : \"\"", "cond 是 Bool；unsafe.title 已消毒"))
        XCTAssertTrue(n("flag ? \"是\" : \"否\"", "flag 是 Bool"), "兩個分支都是字面常量，只有條件需要具名")
        XCTAssertFalse(n("flag ? \"是\" : \"否\"", "這行的註記沒有具名任何運算式"))
        // `??`
        XCTAssertFalse(n("count ?? entry.title", "count 是 Int"))
        XCTAssertTrue(n("count ?? entry.title", "count 是 Int；entry.title 已消毒"))
        XCTAssertTrue(n("keyPubCount[p.key] ?? 0", "keyPubCount 是 dict 查找，值是 Int 計數"), "fallback 是數字常量")
        XCTAssertFalse(n("keyPubCount[p.key] ?? p.name", "keyPubCount 是 dict 查找，值是 Int 計數"),
                       "把 `?? 0` 換成 store 字串時，同一句註記不得繼續放行（守衛的存在理由）")
        // 比較與算術：每個運算元
        XCTAssertFalse(n("count > limit", "count 是 Int"))
        XCTAssertTrue(n("count > limit", "count、limit 都是 Int"))
        XCTAssertTrue(n("count > 0", "count 是 Int"))
        // 型別轉換：右邊是型別、不是值
        XCTAssertTrue(n("value as? String", "value 是內部值"))
    }

    /// 呼叫：函式（或接收者）名與**每個引數**都要具名；函式名不指認引數。
    func testCallArgumentsAreOperandsToo() {
        func n(_ e: String, _ note: String) -> Bool { DisplaySafeExemption.names(e, in: note) }
        XCTAssertFalse(n("fmt(entry.title)", "fmt 是純函式"))
        XCTAssertTrue(n("fmt(entry.title)", "fmt 是純函式；entry.title 已消毒"))
        XCTAssertFalse(n("String(count, radix: 16)", "String 是型別"))
        XCTAssertTrue(n("String(count, radix: 16)", "String、count"), "常量引數（16）不需要具名")
        XCTAssertFalse(n("entry.tags.joined(separator: sep)", "entry.tags 已消毒"))
        XCTAssertTrue(n("entry.tags.joined(separator: sep)", "entry.tags、sep 都是固定 ASCII"))
        // 子字串取值（unlabeled subscript）是查找鍵，不是流進結果的值；`default:` 這種有標籤的引數會流進結果
        XCTAssertTrue(n("counts[lib.key]", "counts 是 dict 查找，值是 Int"))
        XCTAssertFalse(n("names[id, default: entry.title]", "names 是 dict 查找"))
        // 尾隨閉包：body 是運算元
        XCTAssertFalse(n("xs.map { $0.title }", "xs 已消毒"))
        XCTAssertTrue(n("xs.map { $0.title }", "xs、$0.title 已消毒"))
        XCTAssertFalse(n("xs.map { item in item.title }", "xs 已消毒"))
        XCTAssertTrue(n("xs.map { item in item.title }", "xs、item.title 已消毒"))
    }

    /// 以字串字面開頭、後面接**非 `+` 的尾段**（成員呼叫）的運算式：拆不開，一律不豁免——不論註記寫什麼
    ///（R1 verify 第 15 列：尾段沒有插值、也不被 `+` 切開，`allSatisfy` 對空集合為 true，於是不相干的註記就夠）。
    func testALiteralFollowedByATailIsNeverExempt() {
        func n(_ e: String, _ note: String) -> Bool { DisplaySafeExemption.names(e, in: note) }
        XCTAssertFalse(n(#""x".appending(raw)"#, "idx 是 Int"))
        XCTAssertFalse(n(#""x".appending(raw)"#, "raw 已消毒"), "整條拆不開：字面後面的尾段不被逐段對照，具名 raw 也不放行")
        XCTAssertFalse(n(#""\(idx)".appending(entry.title)"#, "idx 是 Int"))
        XCTAssertFalse(n(#""abc".count"#, "abc"))
        // 字面之間的 `+` 才是拆得開的形狀
        XCTAssertTrue(n(#""\(idx)" + "x""#, "idx 是 Int"))
        XCTAssertFalse(n(#""\(idx)" + "x".appending(entry.title)"#, "idx 是 Int"))
        // 三元裡的字面常量照舊放行；字面帶尾段就不行
        XCTAssertFalse(n(#"cond ? "x".appending(raw) : """#, "cond 是 Bool"))
    }

    /// 函式名不指認任何值：`displaySafeClipOnly(x, max:)` 的載體要具名，函式名不算；出現在複合運算式裡也一樣。
    func testAFunctionNameNamesNothingEvenInsideACompound() {
        func n(_ e: String, _ note: String) -> Bool { DisplaySafeExemption.names(e, in: note) }
        let compound = "displaySafeClipOnly(x, max: 1) + entry.title"
        XCTAssertFalse(n(compound, "displaySafeClipOnly 已消毒"), "註記寫了函式名，不得因此讓載體與 entry.title 免檢")
        XCTAssertFalse(n(compound, "x 已消毒"), "載體具名了，entry.title 沒有")
        XCTAssertTrue(n(compound, "x、entry.title 已消毒"))
        XCTAssertFalse(n("cond ? displaySafeClipOnly(x, max: 1) : entry.title", "cond、displaySafeClipOnly"))
    }

    /// 認不得的形狀 fail-closed：拆不開就不豁免，而不是「拆不開就放行」。
    func testUnrecognisedShapesAreNeverExempt() {
        func n(_ e: String, _ note: String) -> Bool { DisplaySafeExemption.names(e, in: note) }
        XCTAssertFalse(n("entry.title+suffix", "entry、suffix"), "沒有空白的運算子不認得——寧可不豁免，多寫一個空白就好")
        // key path 是接收者上的投影：`xs.map(\.title)` 的資料來自 `xs`，所以 `xs` 要具名、key path 不另外要求
        XCTAssertTrue(n(#"xs.map(\.title)"#, "xs 已消毒"))
        XCTAssertFalse(n(#"xs.map(\.title)"#, "title 已消毒"), "具名 key path 的成員名不指認接收者")
        XCTAssertFalse(n("if flag { entry.title } else { \"\" }", "flag、entry.title"), "if 運算式不認得")
        XCTAssertFalse(n("", "任何註記"), "空運算式不是運算式")
        XCTAssertFalse(n("entry.title", ""), "沒有註記就沒有具名")
    }

    /// 壞掉、沒配平、被截斷的運算式不得讓謂詞當掉，也不得被豁免（守衛在讀取路徑上對任意原始碼行求值；多行語句的第一行常常就是半條運算式）。
    func testMalformedExpressionsNeverCrashAndAreNeverExempt() {
        let note = "foo x a b c 已消毒"
        for e in ["foo(", "foo[1", "foo { x", "(", ")", "{", "[", #"\"#, #""unterminated"#, #"#""#, #"\("#, "x ??", "?", ":", "+", " ? : ",
                  "foo(x", "foo(x,", "foo(,)", "a ? b :", "foo.", "foo?.", ".", "..", "$", "$0.", "1.", "-", "!", "try", "await"] {
            XCTAssertFalse(DisplaySafeExemption.names(e, in: note), "壞掉的形狀不得被豁免：\(e)")
        }
        // 沒有結尾但配得起來的形狀照常運作（不是所有奇怪的東西都拒絕）
        XCTAssertTrue(DisplaySafeExemption.names("foo()", in: note))
        XCTAssertTrue(DisplaySafeExemption.names("foo[]", in: note))
        XCTAssertTrue(DisplaySafeExemption.names("foo { }", in: note) || !DisplaySafeExemption.names("foo { }", in: note), "空閉包只要不當掉")
    }

    /// 只認**註解裡**的標記（R1 verify 第 24／27 列）：標記出現在字串字面裡時，後面的程式碼不是註記。
    func testAMarkerInsideAStringLiteralIsNotANote() {
        let inLiteral = #"print("display-safe-exempt: \(entry.title)")"#
        XCTAssertEqual(DisplaySafeExemption.notes(in: [inLiteral]), "", "字面裡的標記不是註記")
        XCTAssertFalse(DisplaySafeExemption.names("entry.title", in: DisplaySafeExemption.notes(in: [inLiteral])))
        // 同一行既有字面裡的標記、又有真的註解：只取註解裡的那一個
        let both = #"print("display-safe-exempt: \(entry.title)")   // display-safe-exempt: idx 是 Int"#
        let notes = DisplaySafeExemption.notes(in: [both])
        XCTAssertTrue(notes.contains("idx 是 Int"))
        XCTAssertFalse(notes.contains("entry.title"), "字面裡的那一段不得混進註記文字：\(notes)")
        // 一般路徑不受影響
        XCTAssertTrue(DisplaySafeExemption.notes(in: ["let a = 1   // display-safe-exempt: a 是常量"]).contains("a 是常量"))
    }

    /// 擲出站點守衛的豁免也是逐引數的（R1 verify 第 14 列）：sink 守衛有三支行為測試，這一半原本只有結構釘——
    /// 把 `exempted` 改成「有註記整條免檢」五十二支全綠。這裡用合成的站點釘住：註記只具名 `stage`，同一語句的另一個引數
    /// 是未消毒的 store 字串 → 要紅。
    /// 負控：`checkThrowSiteArguments` 的 `exempted` 改成 `!notes.isEmpty`，下面第一、第三支斷言就紅。
    func testThrowSiteExemptionIsPerArgument() {
        typealias Guard = SanitizationBoundaryTests
        let site = "probe.swift:1 E.c"
        // 裸引數：註記只具名 stage
        let bare = Guard.checkThrowSiteArguments(site_: site, args: ["stage", "entry.title"], modes: [.raw, .raw], notes: " stage 是封閉列舉")
        XCTAssertEqual(bare.offenders, ["\(site) 裸引數：entry.title"], "沒被具名的引數照報")
        XCTAssertEqual(bare.checked, 1, "被具名的那個不算檢查過")
        // 兩個都具名 → 放行
        XCTAssertEqual(Guard.checkThrowSiteArguments(site_: site, args: ["stage", "entry.title"], modes: [.raw, .raw],
                                                     notes: " stage 是封閉列舉；entry.title 是消毒投影").offenders, [])
        // 字面引數：插值逐個對照
        let lit = Guard.checkThrowSiteArguments(site_: site, args: [#""\(stage)：\(entry.title)""#], modes: [.raw], notes: " stage 是封閉列舉")
        XCTAssertEqual(lit.offenders, ["\(site) \\(entry.title)"])
        // 複合的裸引數：註記只具名第一個運算元不得放行整條
        let compound = Guard.checkThrowSiteArguments(site_: site, args: ["stage ?? entry.title"], modes: [.raw], notes: " stage 是封閉列舉")
        XCTAssertEqual(compound.offenders.count, 1, "複合運算式的每個運算元都要具名")
        // 沒有註記：全部照報
        XCTAssertEqual(Guard.checkThrowSiteArguments(site_: site, args: ["stage", "entry.title"], modes: [.raw, .raw], notes: "").offenders.count, 2)
    }

    /// 兩支守衛都走這一份謂詞：在自己的檔案裡另寫一份比對，就是 #584 要消掉的分岔。
    func testBothGuardsUseTheSharedPredicate() throws {
        let root = SanitizationBoundaryTests.repoRoot
        for name in ["DisplaySinkCoverageTests.swift", "SanitizationBoundaryTests.swift"] {
            // 剝掉註解再找：一句註解提到 `DisplaySafeExemption.names(` 不算呼叫（R1 verify 第 46 列）
            let text = SanitizationBoundaryTests.strippingLineComments(
                try String(contentsOf: root.appendingPathComponent("Tests/AkashicKitTests/\(name)"), encoding: .utf8))
            XCTAssertTrue(text.contains("DisplaySafeExemption.names("), "\(name) 沒有呼叫共用的豁免謂詞")
            XCTAssertTrue(text.contains("DisplaySafeExemption.notes("), "\(name) 沒有用共用的註記抽取")
        }
    }
}
