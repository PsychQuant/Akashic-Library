import XCTest
import Foundation

/// #781：`akashic-fetch-fulltext` 的人機分工——預設由 Claude 做，交給人只有封閉清單。SKILL 是模型照著執行的文字，
/// 這裡只釘住三件可以機械檢查的事：分工那一節在、被取代的舊規定不在、點擊程序叫得到記帳命令。
final class FulltextDivisionOfLabourTests: XCTestCase {
    private func skill() throws -> String {
        var dir = URL(fileURLWithPath: #filePath)
        for _ in 0..<10 {
            dir.deleteLastPathComponent()
            if FileManager.default.fileExists(atPath: dir.appendingPathComponent("Package.swift").path) {
                return try String(contentsOf: dir.appendingPathComponent("plugin/skills/akashic-fetch-fulltext/SKILL.md"), encoding: .utf8)
            }
        }
        throw XCTSkip("找不到 repo root")
    }

    // spec-example: fulltext-division-of-labour / Division of labour section lists five classes
    func testTheDivisionOfLabourSectionListsFiveClasses() throws {
        let text = try skill()
        let start = try XCTUnwrap(text.range(of: "\n## 人機分工"), "SKILL 沒有〈人機分工〉一節")
        let rest = text[start.upperBound...]
        let section = rest.range(of: "\n## ").map { String(rest[..<$0.lowerBound]) } ?? String(rest)
        for marker in ["(a)", "(b)", "(c)", "(d)", "(e)", "封閉列舉", "不得依性質相似類推"] {
            XCTAssertTrue(section.contains(marker), "〈人機分工〉缺 \(marker)")
        }
    }

    // spec-example: fulltext-division-of-labour / Retired hand-over sentences are gone
    func testTheRetiredHandOverSentencesAreGone() throws {
        let text = try skill()
        for retired in ["不要代按任何按鈕", "當次對話授權", "等使用者處理完再做下一篇", "先用 `pdf-cache get"] {
            XCTAssertFalse(text.contains(retired), "被取代的舊規定還在：\(retired)")
        }
        for present in ["safari-browser save-pdf", "browser-save-pdf"] {
            XCTAssertTrue(text.contains(present), "SKILL 缺 \(present)")
        }
    }

    // spec-example: fulltext-division-of-labour / Click procedure calls the attempt command
    func testTheClickProcedureCallsTheAttemptCommand() throws {
        XCTAssertTrue(try skill().contains("akashic fulltext attempt --site"), "點擊程序沒有叫記帳命令")
    }
}
