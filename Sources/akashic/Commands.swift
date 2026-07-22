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
        print("orphaned: \(orphaned.count)\(orphaned.isEmpty ? "" : "（" + orphaned.map(\.citekey).joined(separator: ", ") + "）")")
        let unresolved = load.entries.flatMap { entry in
            entry.authors.compactMap { if case .literal(let s) = $0 { return s } else { return nil } }
        }
        print("unresolved author literals: \(unresolved.count)")
        if !load.quarantined.isEmpty {
            print("quarantined: \(load.quarantined.count)")
            load.quarantineLines.forEach { print($0) }
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
                print("\(mark) \(entry.citekey): \(issue.message)")
                if issue.severity == .error { failed = true }
            }
        }
        if failed {
            throw ExitCode(1)
        }
        print("✓ \(load.entries.count) entries、\(load.people.count) people 全部通過")
    }
}

struct ImportZotero: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "import-zotero", abstract: "Zotero → Akashic 單向 pull（zotero.sqlite 唯讀）")

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "zotero.sqlite 路徑（預設 ~/Zotero/zotero.sqlite）")
    var zoteroDb: String = "~/Zotero/zotero.sqlite"

    func run() throws {
        let root = try options.resolveRoot()
        let store = LibraryStore(root: root)
        try store.ensureLayout()
        let dbURL = URL(fileURLWithPath: (zoteroDb as NSString).expandingTildeInPath)
        guard FileManager.default.fileExists(atPath: dbURL.path) else {
            throw ValidationError("找不到 zotero.sqlite：\(dbURL.path)")
        }
        let report = try ZoteroImporter(store: store).run(zoteroDB: dbURL)
        print("created: \(report.created.count)")
        print("updated: \(report.updated.count)\(report.updated.isEmpty ? "" : "（" + report.updated.joined(separator: ", ") + "）")")
        print("orphaned: \(report.orphaned.count)\(report.orphaned.isEmpty ? "" : "（" + report.orphaned.joined(separator: ", ") + "）")")
        print("unchanged: \(report.unchanged)")
        if !report.authorsPreserved.isEmpty {
            print("authors preserved（已解析、未同步 Zotero 作者欄）: \(report.authorsPreserved.joined(separator: ", "))")
        }
        let stats = try LibraryIndex(store: store).rebuild()
        print("index rebuilt: \(stats.entries) entries")
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

    @Flag(name: .long, help: "套用全部候選（顯式人工確認）")
    var apply = false

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        let candidates = PersonResolver.candidates(entries: load.entries, people: load.people)
        guard !candidates.isEmpty else {
            print("無候選（literal 作者 \(load.entries.flatMap(\.authors).filter { if case .literal = $0 { return true } else { return false } }.count) 個，皆無 alias 完全命中）")
            return
        }
        for c in candidates {
            print("\(c.citekey)[\(c.authorIndex)] 「\(c.literal)」 → \(c.personKey)（\(c.reason)）")
        }
        if apply {
            let applied = PersonResolver.apply(candidates, to: load.entries)
            var written = 0
            for (before, after) in zip(load.entries, applied) where before != after {
                try store.writeEntry(after)
                written += 1
            }
            _ = try LibraryIndex(store: store).rebuild()
            print("✓ 套用 \(candidates.count) 個候選、改寫 \(written) 檔、index 已重建")
        } else {
            print("（只列候選；要套用加 --apply）")
        }
    }
}
