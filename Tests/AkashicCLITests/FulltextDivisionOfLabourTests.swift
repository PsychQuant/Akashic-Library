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
    /// 只看〈一層層按〉第 2 步那一行（#781 verify 第 1 輪第 25 列：先前搜整份 SKILL，〈每站每天 10 次嘗試〉那一句就讓它通過，
    /// 刪掉點擊程序的記帳那一步也不會紅）。
    func testTheClickProcedureCallsTheAttemptCommand() throws {
        let step = try XCTUnwrap(SkillText.line(in: SkillText.section(try skill(), "#### 一層層按"), startingWith: "2. **記帳**"),
                                 "〈一層層按〉沒有第 2 步")
        XCTAssertTrue(step.contains("akashic fulltext attempt --site"), "點擊程序沒有叫記帳命令：\(step)")
        XCTAssertTrue(step.contains("64"), "第 2 步沒有寫結束碼 64：\(step)")
    }

    // spec-example: fulltext-division-of-labour / The site key falls back to the page line
    func testTheSiteKeyFallsBackToThePageLine() throws {
        let section = SkillText.section(try skill(), "## 每站每天 10 次嘗試")
        for marker in ["page:", "64", "帶埠號"] {
            XCTAssertTrue(section.contains(marker), "〈每站每天 10 次嘗試〉缺 \(marker)")
        }
        XCTAssertFalse(section.contains("路徑與埠號）"), "埠號不去掉（#781 第 2 輪 verify 第 12 列）")
    }
}

/// 從 SKILL 取一節、一行。只給 SKILL 文字的測試用：節以標題的 `#` 個數為界（同級或更高一級的下一個標題為止），
/// 程式碼區塊（``` 之間）裡以 `#` 開頭的行不算標題。
enum SkillText {
    static func section(_ text: String, _ heading: String) -> String {
        let level = heading.prefix { $0 == "#" }.count
        var lines: [Substring] = []
        var inside = false
        var fenced = false
        for line in text.split(separator: "\n", omittingEmptySubsequences: false) {
            if line.hasPrefix("```") { fenced.toggle() }
            if !fenced, line.hasPrefix("#") {
                let hashes = line.prefix { $0 == "#" }.count
                let isHeading = line.dropFirst(hashes).hasPrefix(" ")
                if inside, isHeading, hashes <= level { break }
                if !inside, isHeading, line.hasPrefix(heading) { inside = true; continue }
            }
            if inside { lines.append(line) }
        }
        return lines.joined(separator: "\n")
    }

    /// 去掉行首空白之後以 `prefix` 開頭的第一行。
    static func line(in text: String, startingWith prefix: String) -> String? {
        text.split(separator: "\n").map { String($0.drop { $0 == " " }) }.first { $0.hasPrefix(prefix) }
    }

    /// 含 `needle` 的第一行。
    static func line(in text: String, containing needle: String) -> String? {
        text.split(separator: "\n").map(String.init).first { $0.contains(needle) }
    }

    /// 以 `prefix` 開頭、到下一個空行為止的那一段。
    static func paragraph(in text: String, startingWith prefix: String) -> String? {
        let paragraphs = text.components(separatedBy: "\n\n")
        return paragraphs.first { $0.hasPrefix(prefix) }
    }
}
