import Foundation
import ArgumentParser
import AkashicCore

/// #617：`akashic-work-references` skill 的決定論中間運算。兩個子命令都**不寫 store、
/// 不打網路**——PDF 轉文字（`pdftotext`）與 OpenAlex 取得由 skill 經本機工具與
/// safari-browser 完成（`.claude/rules/web-access-via-safari-browser.md`），這裡只吃本機檔。
/// MCP 沒有對應面：輸入是 skill 交來的暫存檔，不是 store 狀態（mcp-cli-parity 的 CLI-only 列）。
struct ReferencesCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "references",
        abstract: "參考文獻清單的中間運算（skill 用）：切分 pdftotext 輸出",
        subcommands: [ReferencesExtractCmd.self])
}

struct ReferencesExtractCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "extract",
        abstract: "從 pdftotext 的輸出切出參考文獻段、逐筆抽欄位 → JSON（只支援作者—年份格式）")

    @Option(name: .long, help: "pdftotext 的輸出檔（UTF-8 純文字）")
    var text: String

    func run() throws {
        let input: String
        do {
            input = try String(contentsOfFile: text, encoding: .utf8)
        } catch {
            throw ValidationError("讀不到 --text 指定的檔（需為 UTF-8 純文字）：\(displaySafe(text))")
        }
        let result = try ReferenceListExtractor.extract(input)
        print(try encodeForDisplay(result))
    }

    /// 逐欄 `displaySafe` 後編碼：PDF 文字是第三方內容，控制字元與方向字元不得原樣
    /// 進終端或 LLM context。上限依欄位用途給：`raw` 要容得下一整筆、其餘是單一欄位。
    func encodeForDisplay(_ r: ReferenceListExtractor.Result) throws -> String {
        var safe = r
        safe.entries = r.entries.map { e in
            var s = e
            s.raw = displaySafe(e.raw, max: 2_000)
            s.firstAuthor = e.firstAuthor.map { displaySafe($0) }
            s.authors = e.authors.map { displaySafe($0) }
            s.title = e.title.map { displaySafe($0, max: 500) }
            s.doi = e.doi.map { displaySafe($0) }
            s.yearSuffix = e.yearSuffix.map { displaySafe($0) }
            return s
        }
        safe.warnings = r.warnings.map { displaySafe($0, max: 500) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(safe), as: UTF8.self)
    }
}
