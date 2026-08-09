import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit
import BiblatexAPA

/// `akashic create-entry` —— CLI 的**無損**建檔入口（#206）。
///
/// ## 為什麼要有這支
///
/// 在此之前，能帶任意欄位的入口**只有 MCP** 的 `akashic_create_entry`；CLI 的
/// 33 個 subcommand 沒有一個做得到。實際後果：要把一份 `.bib` 無損收進 store，
/// 得繞過 CLI、用 stdio 驅動 `akashic-mcp` 逐筆呼叫——那條路只有寫程式的人走得到。
///
/// **能不能無損匯入，不該取決於使用者會不會寫 script。**
/// 見 `.claude/rules/lossless-intake.md`。
///
/// ## 與 MCP 共用同一條寫入路徑
///
/// 走 `AkashicService.createEntry`（同 `update-person` 的作法）——citekey 生成、
/// quarantine 檔名佔位、format gate、index rebuild 全部白拿，且**不會與 MCP 面分岔**。
struct CreateEntryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create-entry",
        abstract: "建庫外文獻，**保留來源的所有欄位**（JSON 或 .bib；citekey 自動生成）")

    enum Format: String, ExpressibleByArgument, CaseIterable {
        case json, bib
    }

    @OptionGroup var options: LibraryOptions

    @Option(name: .long, help: "輸入格式：json（同 MCP fields object）或 bib（biblatex）")
    var format: Format = .json

    @Option(name: .long, help: "輸入檔路徑；省略時讀 stdin")
    var file: String?

    @Flag(name: .long, help: "只回報會建什麼，不寫入")
    var dryRun = false

    func run() throws {
        let raw: Data
        if let file {
            raw = try Data(contentsOf: URL(fileURLWithPath: (file as NSString).expandingTildeInPath))
        } else {
            raw = FileHandle.standardInput.readDataToEndOfFile()
        }
        guard let text = String(data: raw, encoding: .utf8) else {
            throw ValidationError("輸入不是合法的 UTF-8")
        }

        let drafts: [EntryDraft]
        switch format {
        case .json: drafts = try Self.parseJSON(raw)
        case .bib:  drafts = Self.parseBib(text)
        }
        guard !drafts.isEmpty else {
            // **零筆不得靜默。**「解析成功但一筆都沒有」與「格式沒被辨識」是兩件事，
            // 而使用者從 exit 0 + 無輸出分不出來（同 import-wos 的既有立場）。
            throw ValidationError("解析出 0 筆——確認 --format \(format.rawValue) 與輸入相符")
        }

        if dryRun {
            print("（dry-run）將建 \(drafts.count) 筆：")
            for d in drafts {
                print("  \(displaySafe(d.title, max: 90))"
                    + "  [\(displaySafe(d.type, max: 40))]"
                    + "  作者 \(d.authors.count)"
                    + "  欄位 \(d.fields.count)")
            }
            return
        }

        let store = try options.openStore()
        let service = AkashicService(root: store.root,
                                     environment: ProcessInfo.processInfo.environment)
        var created = 0
        var failed: [(String, String)] = []
        for d in drafts {
            do {
                // service 的輸出已 displaySafe，原樣轉印
                print(try service.createEntry(type: d.type, title: d.title,
                                              authors: d.authors, date: d.date,
                                              fields: d.fields))
                created += 1
            } catch {
                // **per-item 收容**：一筆壞掉不該讓其餘的全滅（同 resolve-people
                // 的多檔迴圈立場）。失敗清單最後一起報，不吞。
                failed.append((d.title, displaySafe(String(describing: error), max: 400)))
            }
        }
        print("✓ created \(created)")
        if !failed.isEmpty {
            print("failed \(failed.count)：")
            for (t, e) in failed.prefix(10) {
                print("  ! \(displaySafe(t, max: 80)) — \(e)")
            }
        }
    }

    // MARK: - 解析

    struct EntryDraft {
        var type: String
        var title: String
        var authors: [String]
        var date: String?
        var fields: [String: String]
    }

    /// JSON：單一 object 或 object 陣列。形狀與 MCP `akashic_create_entry` 相同。
    static func parseJSON(_ data: Data) throws -> [EntryDraft] {
        let parsed = try JSONSerialization.jsonObject(with: data)
        let objects: [[String: Any]]
        if let one = parsed as? [String: Any] { objects = [one] }
        else if let many = parsed as? [[String: Any]] { objects = many }
        else { throw ValidationError("JSON 必須是 object 或 object 陣列") }

        return try objects.map { o in
            guard let type = o["type"] as? String, !type.isEmpty,
                  let title = o["title"] as? String, !title.isEmpty else {
                throw ValidationError("每筆都必須有非空的 type 與 title")
            }
            var fields: [String: String] = [:]
            if let f = o["fields"] as? [String: Any] {
                for (k, v) in f {
                    // 值一律轉字串（`Entry.fields` 是 [String: String]）。
                    // 數字／布林在 JSON 裡合法，硬性要求字串會讓使用者為了型別
                    // 重寫來源——那與「盡量接受資訊」相反。
                    fields[k] = (v as? String) ?? String(describing: v)
                }
            }
            return EntryDraft(type: type, title: title,
                              authors: (o["authors"] as? [String]) ?? [],
                              date: o["date"] as? String, fields: fields)
        }
    }

    /// `.bib`：走 `BibParser`，**除 title／author／date 外的欄位全部原樣保留**。
    static func parseBib(_ text: String) -> [EntryDraft] {
        BibParser.parse(content: text).entries.map { e in
            var fields: [String: String] = [:]
            for key in e.fields.keys {
                let lower = key.lowercased()
                // 這三個抽成一級欄位，其餘留在 fields
                if lower == "title" || lower == "author" || lower == "date" { continue }
                guard let v = e.fields[key] else { continue }
                fields[FieldKey.normalized(lower) ?? lower] = v
            }
            let authorRaw = e.fields.caseInsensitiveValue(forKey: "AUTHOR") ?? ""
            return EntryDraft(
                type: e.entryType.lowercased(),
                title: e.fields.caseInsensitiveValue(forKey: "TITLE") ?? "",
                authors: splitBibAuthors(authorRaw),
                date: e.fields.caseInsensitiveValue(forKey: "DATE")
                    ?? e.fields.caseInsensitiveValue(forKey: "YEAR"),
                fields: fields)
        }
    }

    /// biblatex 的 `A and B and C` → 顯示名陣列，並把 `Family, Given` 翻成
    /// `Given Family`。
    ///
    /// **翻面不是美觀偏好，是 citekey 正確性**：`AkashicService.createEntry` 取
    /// 「空格後最後一字」當姓（假設 `Given Family`），而 biblatex 慣例是
    /// `Family, Given`。不翻的話 `Terada, Yoshikazu` 會被當成姓 `Yoshikazu`，
    /// citekey 產出 `yoshikazu2024…`。
    ///
    /// 方向與 store 的既有分布一致：literal 作者 2071 筆是 `Given Family`、
    /// 只有 60 筆帶逗號。
    ///
    /// **機構名（`{...}` 標記）不翻**——那是 #6 的既有約定，切開會產出
    /// 「Organization, World Health」這種錯誤輸出。
    static func splitBibAuthors(_ raw: String) -> [String] {
        raw.components(separatedBy: " and ")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
            .map { name in
                if name.hasPrefix("{") || !name.contains(",") { return name }
                let parts = name.split(separator: ",", maxSplits: 1).map {
                    $0.trimmingCharacters(in: .whitespaces)
                }
                guard parts.count == 2, !parts[1].isEmpty else { return name }
                return "\(parts[1]) \(parts[0])"
            }
    }
}
