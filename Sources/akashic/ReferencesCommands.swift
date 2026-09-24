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
        abstract: "參考文獻清單的中間運算（skill 用）：切分 pdftotext 輸出、兩源提名",
        subcommands: [ReferencesExtractCmd.self, ReferencesNominateCmd.self])
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

struct ReferencesNominateCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "nominate",
        abstract: "PDF 參考文獻 × OpenAlex referenced_works 的雙向提名 → JSON（只提名、不判定）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "akashic references extract 的輸出檔")
    var refs: String

    @Option(name: .long, help: "OpenAlex 回應檔（{\"results\": [...]} 或 work 陣列）；可重複，每批一檔")
    var openalex: [String] = []

    func run() throws {
        let parsed: ReferenceListExtractor.Result
        do {
            parsed = try JSONDecoder().decode(ReferenceListExtractor.Result.self,
                                              from: Data(contentsOf: URL(fileURLWithPath: refs)))
        } catch {
            throw ValidationError(
                "--refs \(displaySafe(refs)) 讀不到或不是 akashic references extract 的輸出：\(displaySafeErrorText(error))")
        }
        guard !openalex.isEmpty else {
            throw ValidationError("至少要給一個 --openalex（OpenAlex 回應檔）")
        }

        var works: [ReferenceNominator.Work] = []
        var seen = Set<String>()
        var skipped = 0, duplicates = 0
        for path in openalex {
            let data: Data
            do { data = try Data(contentsOf: URL(fileURLWithPath: path)) } catch {
                throw ValidationError("--openalex \(displaySafe(path)) 讀不到：\(displaySafeErrorText(error))")
            }
            let batch = try ReferenceNominator.parseWorks(data, source: path)
            skipped += batch.skipped
            for w in batch.works {
                if seen.insert(w.id).inserted { works.append(w) } else { duplicates += 1 }
            }
        }

        let (inStore, conflicts) = try storeDOIs()
        var result = ReferenceNominator.nominate(refs: parsed.entries, works: works, inStore: inStore)
        if skipped > 0 { result.warnings.append("略過 \(skipped) 個沒有 id 的 OpenAlex 項目") }
        if duplicates > 0 { result.warnings.append("\(duplicates) 個 OpenAlex work 在多批重複出現，只算一次") }
        if conflicts > 0 {
            result.warnings.append("\(conflicts) 個 DOI 在 store 裡對應到不只一筆記錄（取 citekey 最小者）——先處理重複記錄")
        }
        print(try encodeForDisplay(result))
    }

    /// store 裡每個 DOI（正規形）→ citekey。讀取走 `canonicalDOIs`，不自己比較字串。
    func storeDOIs() throws -> (map: [String: String], conflicts: Int) {
        let load = try options.openStore().load()
        var map: [String: String] = [:]
        var conflicted = Set<String>()
        for entry in load.entries {
            for d in entry.canonicalDOIs {
                if let existing = map[d.normalized], existing != entry.citekey {
                    conflicted.insert(d.normalized)
                    map[d.normalized] = min(existing, entry.citekey)
                } else {
                    map[d.normalized] = entry.citekey
                }
            }
        }
        return (map, conflicted.count)
    }

    /// 同 extract：OpenAlex 內容與 citekey 都逐欄 `displaySafe` 後才編碼。
    func encodeForDisplay(_ r: ReferenceNominator.Result) throws -> String {
        func safe(_ c: ReferenceNominator.Candidate) -> ReferenceNominator.Candidate {
            var s = c
            s.openalex = displaySafe(c.openalex)
            s.doi = c.doi.map { displaySafe($0) }
            s.title = c.title.map { displaySafe($0, max: 500) }
            s.firstAuthor = c.firstAuthor.map { displaySafe($0) }
            s.inStore = c.inStore.map { displaySafe($0) }
            return s
        }
        var out = r
        out.refs = r.refs.map { n in
            var s = n
            s.firstAuthor = n.firstAuthor.map { displaySafe($0) }
            s.title = n.title.map { displaySafe($0, max: 500) }
            s.doi = n.doi.map { displaySafe($0) }
            s.inStore = n.inStore.map { displaySafe($0) }
            s.candidates = n.candidates.map(safe)
            return s
        }
        out.unnominated = r.unnominated.map { w in
            var s = w
            s.openalex = displaySafe(w.openalex)
            s.doi = w.doi.map { displaySafe($0) }
            s.title = w.title.map { displaySafe($0, max: 500) }
            s.firstAuthor = w.firstAuthor.map { displaySafe($0) }
            s.inStore = w.inStore.map { displaySafe($0) }
            return s
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(out), as: UTF8.self)
    }
}
