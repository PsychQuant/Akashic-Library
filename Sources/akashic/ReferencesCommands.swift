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
            throw ValidationError("讀不到 --text 指定的檔（需為 UTF-8 純文字）：\(displaySafeInvisible(text, max: 300))")
        }
        let result = try ReferenceListExtractor.extract(input)
        print(try encodeForDisplay(result))
    }

    /// 逐欄 `displaySafe` 後編碼：PDF 文字是第三方內容，控制字元與方向字元不得原樣
    /// 進終端或 LLM context。上限依欄位用途給：`raw` 要容得下一整筆、其餘是單一欄位。
    ///
    /// **這份輸出同時是 `nominate` 的輸入**（#617 verify）：截斷會附加「…（已截斷）」、反斜線
    /// 會逃成 `\u{005C}`，兩者都會進到比對。所以會被比對的欄位（`doi`、`title`）上限放寬到
    /// 實務上碰不到；真的碰到時，那筆的 DOI 比對不上、標題多出雜訊詞——落在「只在 PDF」由人判斷。
    func encodeForDisplay(_ r: ReferenceListExtractor.Result) throws -> String {
        var safe = r
        safe.entries = r.entries.map { e in
            var s = e
            s.raw = displaySafe(e.raw, max: 2_000)
            s.firstAuthor = e.firstAuthor.map { displaySafe($0) }
            s.authors = e.authors.map { displaySafe($0) }
            s.title = e.title.map { displaySafe($0, max: 1_000) }
            s.doi = e.doi.map { displaySafe($0, max: 500) }
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
                "--refs \(displaySafeInvisible(refs, max: 300)) 讀不到或不是 akashic references extract 的輸出：\(displaySafeErrorText(error))")
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
                throw ValidationError("--openalex \(displaySafeInvisible(path, max: 300)) 讀不到：\(displaySafeErrorText(error))")
            }
            let batch = try ReferenceNominator.parseWorks(data, source: path)
            skipped += batch.skipped
            for w in batch.works {
                if seen.insert(w.id).inserted { works.append(w) } else { duplicates += 1 }
            }
        }

        let snapshot = try storeSnapshot()
        var result = ReferenceNominator.nominate(refs: parsed.entries, works: works,
                                                 doiIndex: snapshot.doiIndex, store: snapshot.records)
        if skipped > 0 { result.warnings.append("略過 \(skipped) 個沒有 id 的 OpenAlex 項目") }
        if duplicates > 0 { result.warnings.append("\(duplicates) 個 OpenAlex work 在多批重複出現，只算一次") }
        // 只計入**這次**涉及的 DOI（R2 G2：原本全 store 計數，store 裡既有的無關重複也會讓每次 run 停下）
        let involved = Set(works.compactMap { $0.doi?.normalized }
                           + parsed.entries.compactMap { $0.doi.flatMap(DOI.init)?.normalized })
        let conflicts = involved.filter { (snapshot.doiIndex[$0]?.count ?? 0) > 1 }.count
        if conflicts > 0 {
            result.warnings.append("\(conflicts) 個本次涉及的 DOI 在 store 裡對應到不只一筆記錄——這些 DOI 的 inStore 留空、"
                                   + "改列 inStoreConflict；不要擅選一筆連 cites，先處理重複記錄（akashic-merge-twins）")
        }
        if snapshot.quarantined > 0 {
            result.warnings.append("store 有 \(snapshot.quarantined) 個被隔離（quarantined）的檔案沒有被掃描——它們的 DOI"
                                   + "與標題看不到，「不在庫」的判斷因此不完整；先修好那些檔（akashic validate）再寫入")
        }
        print(try encodeForDisplay(result))
    }

    /// store 的快照：DOI（正規形，讀取走 `canonicalDOIs`）→ 所有持有它的 citekey；標題索引；
    /// 被隔離而沒掃到的檔數（#617 verify F6／F7：原本同 DOI 取字串最小者、隔離檔無聲略過）
    func storeSnapshot() throws -> (doiIndex: ReferenceNominator.DOIIndex,
                                    records: [ReferenceNominator.StoreRecord], quarantined: Int) {
        let load = try options.openStore().load()
        var index: [String: Set<String>] = [:]
        var records: [ReferenceNominator.StoreRecord] = []
        for entry in load.entries {
            for d in entry.canonicalDOIs { index[d.normalized, default: []].insert(entry.citekey) }
            records.append(.init(citekey: entry.citekey, title: entry.title,
                                 tokens: ReferenceNominator.titleTokens(entry.title),
                                 year: ReferenceNominator.year(of: entry.date)))
        }
        return (index.mapValues { $0.sorted() }, records, load.quarantined.count)
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
            s.inStoreConflict = c.inStoreConflict.map { $0.map { displaySafe($0) } }
            s.storeMatches = c.storeMatches.map(safeMatch)
            return s
        }
        func safeMatch(_ m: ReferenceNominator.StoreMatch) -> ReferenceNominator.StoreMatch {
            var t = m
            t.citekey = displaySafe(m.citekey)
            t.title = displaySafe(m.title, max: 500)
            return t
        }
        var out = r
        out.refs = r.refs.map { n in
            var s = n
            s.firstAuthor = n.firstAuthor.map { displaySafe($0) }
            s.title = n.title.map { displaySafe($0, max: 500) }
            s.doi = n.doi.map { displaySafe($0) }
            s.inStore = n.inStore.map { displaySafe($0) }
            s.inStoreConflict = n.inStoreConflict.map { $0.map { displaySafe($0) } }
            s.storeMatches = n.storeMatches.map(safeMatch)
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
            s.inStoreConflict = w.inStoreConflict.map { $0.map { displaySafe($0) } }
            return s
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(out), as: UTF8.self)
    }
}
