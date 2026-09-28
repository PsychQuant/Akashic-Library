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

    /// 兩支守衛都走這一份謂詞：在自己的檔案裡另寫一份比對，就是 #584 要消掉的分岔。
    func testBothGuardsUseTheSharedPredicate() throws {
        let root = SanitizationBoundaryTests.repoRoot
        for name in ["DisplaySinkCoverageTests.swift", "SanitizationBoundaryTests.swift"] {
            let text = try String(contentsOf: root.appendingPathComponent("Tests/AkashicKitTests/\(name)"), encoding: .utf8)
            XCTAssertTrue(text.contains("DisplaySafeExemption.names("), "\(name) 沒有呼叫共用的豁免謂詞")
            XCTAssertTrue(text.contains("DisplaySafeExemption.notes("), "\(name) 沒有用共用的註記抽取")
        }
    }
}
