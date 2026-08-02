import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicEntity
import AkashicZoteroImport
import AkashicExport
import AkashicIndex

struct Doctor: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "doctor", abstract: "建立/檢查 library 佈局、重建 index、一致性報告")

    @OptionGroup var options: LibraryOptions

    func run() throws {
        let root = try options.resolveRoot()
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let load = try store.load()
        let stats = try LibraryIndex(store: store).rebuild()

        print("library: \(root.path)")
        print("entries: \(stats.entries)")
        print("people: \(stats.people)")
        print("relations: \(stats.relations)")
        let orphaned = load.entries.filter { $0.provenance?.orphanedAt != nil }
        print("orphaned: \(orphaned.count)\(orphaned.isEmpty ? "" : "（" + orphaned.map { displaySafe($0.citekey, max: 200) }.joined(separator: ", ") + "）")")
        let unresolved = load.entries.flatMap { entry in
            entry.authors.compactMap { if case .literal(let s) = $0 { return s } else { return nil } }
        }
        print("unresolved author literals: \(unresolved.count)")
        if !load.quarantined.isEmpty {
            print("quarantined: \(load.quarantined.count)")
            load.quarantineLines.forEach { print($0) }
        }
        // #23 tolerant-preserve：較新 schema 的檔案（未知欄位已保留）——提示升級
        if !load.unknownFieldFiles.isEmpty {
            print("unknown-field files: \(load.unknownFieldFiles.count)（可能由較新版本寫入；升級 binary）")
            load.unknownFieldFiles.forEach { print("  ⚠ \(displaySafe($0, max: 200))") }
        }
    }
}

struct Validate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "validate", abstract: "schema 驗證；quarantine 或 error 時非零退出")

    @OptionGroup var options: LibraryOptions

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        var failed = false
        if !load.quarantined.isEmpty {
            failed = true
            print("quarantined \(load.quarantined.count) 檔：")
            load.quarantineLines.forEach { print($0) }
        }
        for entry in load.entries {
            let issues = entry.validate()
            for issue in issues {
                let mark = issue.severity == .error ? "✗" : "⚠"
                print("\(mark) \(displaySafe(entry.citekey, max: 200)): \(issue.message)")
                if issue.severity == .error { failed = true }
            }
        }
        // #23：person / library 層驗證（未知欄位 warning 不 fail——availability 優先，可見性保留）
        for person in load.people {
            for issue in person.validate() {
                let mark = issue.severity == .error ? "✗" : "⚠"
                print("\(mark) \(displaySafe(person.key, max: 200)): \(issue.message)")
                if issue.severity == .error { failed = true }
            }
        }
        for library in load.libraries {
            for issue in library.validate() {
                let mark = issue.severity == .error ? "✗" : "⚠"
                print("\(mark) \(displaySafe(library.key, max: 200)): \(issue.message)")
                if issue.severity == .error { failed = true }
            }
        }
        // #7b：跨記錄檢查——單筆 validate() 結構上看不到的那一層
        for issue in load.crossRecordIssues() {
            let mark = issue.severity == .error ? "✗" : "⚠"
            print("\(mark) [跨記錄] \(issue.message)")
            if issue.severity == .error { failed = true }
        }
        if failed {
            throw ExitCode(1)
        }
        print("✓ \(load.entries.count) entries、\(load.people.count) people、\(load.libraries.count) libraries 全部通過")
    }
}

struct ImportZotero: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-zotero", abstract: "Zotero → Akashic 單向 pull（zotero.sqlite 唯讀）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "zotero.sqlite 路徑（預設 ~/Zotero/zotero.sqlite）")
    var zoteroDb: String = "~/Zotero/zotero.sqlite"

    @Option(name: .long, help: "Zotero libraryID（預設全部 libraries；指定則只拉該 library，如 1＝personal）")
    var libraryId: Int?

    func run() throws {
        let root = try options.resolveRoot()
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let dbURL = URL(fileURLWithPath: (zoteroDb as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw ValidationError("找不到 zotero.sqlite：\(dbURL.path)")
        }
        let report = try ZoteroImporter(store: store).run(zoteroDB: dbURL, libraryID: libraryId)
        print("created: \(report.created.count)")
        print("updated: \(report.updated.count)\(report.updated.isEmpty ? "" : "（" + report.updated.map { displaySafe($0, max: 200) }.joined(separator: ", ") + "）")")
        print("orphaned: \(report.orphaned.count)\(report.orphaned.isEmpty ? "" : "（" + report.orphaned.map { displaySafe($0, max: 200) }.joined(separator: ", ") + "）")")
        print("unchanged: \(report.unchanged)")
        if !report.orphanCleared.isEmpty {
            print("orphan cleared（Zotero 端復原）: \(report.orphanCleared.map { displaySafe($0, max: 200) }.joined(separator: ", "))")
        }
        if !report.authorsPreserved.isEmpty {
            print("authors preserved（已解析、未同步 Zotero 作者欄）: \(report.authorsPreserved.map { displaySafe($0, max: 200) }.joined(separator: ", "))")
        }
        if !report.droppedFields.isEmpty {
            let summary = report.droppedFields.keys.sorted()
                .map { "\($0)×\(report.droppedFields[$0]!)" }.joined(separator: ", ")
            print("dropped fields（未映射的 Zotero 欄位，未入庫）: \(summary)")
        }
        if !report.unnormalizedDates.isEmpty {
            print("unnormalized dates（date 保留原字串）: \(report.unnormalizedDates.count)（\(report.unnormalizedDates.prefix(8).map { displaySafe($0, max: 200) }.joined(separator: ", "))\(report.unnormalizedDates.count > 8 ? ", …" : "")）")
        }
        if report.skippedLinkedAttachments > 0 {
            print("skipped linked attachments（非 storage 附件，未入庫）: \(report.skippedLinkedAttachments)")
        }
        // R6（M9）：per-item 寫入失敗不中斷 import——照實列出，人工處理
        if !report.writeFailed.isEmpty {
            print("write failed（單筆寫入失敗，已略過續跑）: \(report.writeFailed.count)")
            for key in report.writeFailed.keys.sorted() {
                print("  ✗ \(displaySafe(key, max: 200)) — \(displaySafe(report.writeFailed[key]!, max: 512))")
            }
        }
        let stats = try LibraryIndex(store: store).rebuild()
        // #37：index 已搬出 store root，路徑不再顯而易見——doctor 必須說它在哪。
        print("index rebuilt: \(stats.entries) entries → \(store.indexURL.path)")
        // R7（R6-verify M22）：收容 ≠ 吞掉 process 層訊號——有單筆失敗仍以
        // 非零退出，自動化（cron pull、CI）才看得到
        if !report.writeFailed.isEmpty {
            throw ExitCode(1)
        }
    }
}

struct ExportBib: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "export-bib", abstract: ".bib 匯出（編譯產物；經 biblatex-apa-swift）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "輸出檔（預設 stdout）")
    var output: String?

    @Option(name: .long, help: "只匯出這些 citekeys（逗號分隔）")
    var citekeys: String?

    @Flag(name: .long, help: "改輸出 CSL-JSON")
    var cslJson = false

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        var entries = load.entries
        if let filter = citekeys {
            let wanted = Set(filter.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) })
            entries = entries.filter { wanted.contains($0.citekey) }
            let missing = wanted.subtracting(entries.map(\.citekey))
            guard missing.isEmpty else {
                throw ValidationError("citekeys 不存在：\(missing.sorted().joined(separator: ", "))")
            }
        }
        let content: String = cslJson
            ? try CSLExport.cslJSON(entries: entries, people: load.people)
            : BibExport.bibFile(entries: entries, people: load.people)
        if let output {
            try content.write(toFile: (output as NSString).expandingTildeInPath,
                              atomically: true, encoding: .utf8)
            print("寫出 \(entries.count) entries → \(output)")
        } else {
            print(content, terminator: "")
        }
    }
}

struct ResolvePeople: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "resolve-people",
        abstract: "列出 literal→person 高信心候選；--apply 才寫入（絕不自動合併）")

    @OptionGroup var options: LibraryOptions

    @Flag(name: .long, help: "套用候選（顯式人工確認）；可用 --citekey / --person 收窄範圍")
    var apply = false

    /// #5：alias 完全命中**仍可能同名不同人**——people 庫還沒記錄第二個人時，
    /// 歧義偵測不會觸發。所以「全套用」對這種情境是危險的預設，必須能逐項挑。
    @Option(name: .long, parsing: .upToNextOption,
            help: "只套用這些 citekey 的候選（可重複；與 --person 取交集）")
    var citekey: [String] = []

    @Option(name: .long, parsing: .upToNextOption,
            help: "只套用指向這些 person key 的候選（可重複；與 --citekey 取交集）")
    var person: [String] = []

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        let all = PersonResolver.candidates(entries: load.entries, people: load.people)
        // 篩選只影響 **--apply**，列表一律顯示全部——否則使用者用 --citekey 收窄後
        // 會以為其他候選不存在。
        let ckSet = Set(citekey), pkSet = Set(person)
        let candidates = all.filter {
            (ckSet.isEmpty || ckSet.contains($0.citekey))
                && (pkSet.isEmpty || pkSet.contains($0.personKey))
        }
        guard !all.isEmpty else {
            print("無候選（literal 作者 \(load.entries.flatMap(\.authors).filter { if case .literal = $0 { return true } else { return false } }.count) 個，皆無 alias 完全命中）")
            return
        }
        let selected = Set(candidates.map { "\($0.citekey)#\($0.authorIndex)" })
        for c in all {
            // 被篩掉的候選仍列出，但標明不會套用——收窄範圍不等於「其他不存在」
            let mark = (apply && !selected.contains("\(c.citekey)#\(c.authorIndex)")) ? "  (skip) " : "  "
            print("\(mark)\(displaySafe(c.citekey, max: 200))[\(c.authorIndex)] 「\(displaySafe(c.literal, max: 200))」 → \(displaySafe(c.personKey, max: 200))（\(displaySafe(c.reason, max: 300))）")
        }
        if apply {
            // 篩選條件寫了卻一個都沒中——多半是打錯 key，別靜默什麼都不做
            if !(citekey.isEmpty && person.isEmpty), candidates.isEmpty {
                throw ValidationError(
                    "--citekey / --person 的篩選條件沒有命中任何候選"
                    + "（共 \(all.count) 個候選）——請對照上面的清單確認 key 是否正確")
            }
            let applied = PersonResolver.apply(candidates, to: load.entries)
            var written = 0
            var writeFailed: [(String, String)] = []
            // R7（R6-verify M21）：encode 自 v1.3 起可拒寫——多檔迴圈 per-item
            // 收容，index 照 rebuild，不留「部分改寫 + index stale」的撕裂
            for (before, after) in zip(load.entries, applied) where before != after {
                do {
                    try store.writeEntry(after)
                    written += 1
                } catch {
                    writeFailed.append((after.citekey, displaySafe(String(describing: error), max: 512)))
                }
            }
            // R9（R8-verify M8）：writeFailed 先印再 rebuild——rebuild 擲錯
            // 不得吞掉已發生的寫入失敗報告
            if !writeFailed.isEmpty {
                print("write failed（單筆寫入失敗，已略過）: \(writeFailed.count)")
                for (key, msg) in writeFailed { print("  ✗ \(displaySafe(key, max: 200)) — \(displaySafe(msg, max: 512))") }
            }
            _ = try LibraryIndex(store: store).rebuild()
            // R8（R7-verify L29/L15）：成功行不誇報（✓ 只在全數成功時）
            if writeFailed.isEmpty {
                print("✓ 套用 \(candidates.count) 個候選、改寫 \(written) 檔、index 已重建")
            } else {
                print("部分套用：改寫 \(written) 檔、失敗 \(writeFailed.count) 檔、index 已重建")
                throw ExitCode(1)
            }
        } else {
            print("（只列候選；要套用加 --apply）")
        }
    }
}

struct Rename: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "rename", abstract: "citekey 改名：搬檔 + 全庫 relations 遷移（UUID 不變）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "現有 citekey") var from: String
    @Argument(help: "新 citekey") var to: String

    func run() throws {
        let store = try options.openStore()
        let report = try store.renameEntry(from: from, to: to)
        _ = try LibraryIndex(store: store).rebuild()
        print("✓ \(displaySafe(from, max: 200)) → \(displaySafe(to, max: 200))")
        if !report.relationsRewritten.isEmpty {
            print("relations 已遷移：\(report.relationsRewritten.map { displaySafe($0, max: 200) }.joined(separator: ", "))")
        }
    }
}
