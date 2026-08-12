import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// #219：單一 entry 的檢視面（CLI）。與 MCP 的 `akashic_get_entry` 共用
/// `AkashicService.getEntry`。`query` 是**搜尋**（找符合條件的集合），這裡是
/// **檢視**（一筆記錄的全貌）——兩件事形狀不同，`query` 不涵蓋。
struct GetEntryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "get-entry",
        abstract: "看一筆 entry：全欄位 + tags/status/relations（citekey 指名）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "citekey（不存在 → exit 1）")
    var citekey: String

    @Flag(name: .long, help: "原樣輸出 service JSON（與 MCP akashic_get_entry 逐欄位相同）")
    var json: Bool = false

    func run() throws {
        let store = try options.openStore()
        // `key:` 不可省（#220 HIGH；理由詳 PersonCommand.swift）
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.getEntry(citekey: citekey)
        if json {
            print(payload)
            return
        }
        guard let data = payload.data(using: .utf8),
              let d = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ValidationError("service 回應不是預期的 JSON 物件")
        }
        print("citekey\t\(d["citekey"] as? String ?? "")")   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
        print("type\t\(d["type"] as? String ?? "")")   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
        print("title\t\(d["title"] as? String ?? "")")   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
        if let date = d["date"] as? String { print("date\t\(date)") }   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
        if let authors = d["authors"] as? [[String: String]] {
            let rendered = authors.map { $0["key"].map { "@\($0)" } ?? ($0["literal"] ?? "") }
            print("authors\t\(rendered.joined(separator: "; "))")   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
        }
        if let fields = d["fields"] as? [String: String] {
            for k in fields.keys.sorted() { print("field:\(k)\t\(fields[k] ?? "")") }   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
        }
        if let attachments = d["attachments"] as? [[String: String]] {
            // 封閉列舉第 6 條邊——JSON 面有的，人可讀面也要看得到（#219 verify F1）
            for a in attachments {
                for (kind, path) in a { print("attachment:\(kind)\t\(path)") }   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
            }
        }
        if let akashic = d["akashic"] as? [String: Any] {
            if let tags = akashic["tags"] as? [String] {
                print("tags\t\(tags.joined(separator: ", "))")   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
            }
            if let status = akashic["status"] as? String { print("status\t\(status)") }   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
            if let cites = akashic["cites"] as? [String] {
                print("cites\t\(cites.joined(separator: ", "))")   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
            }
            if let related = akashic["related"] as? [String] {
                print("related\t\(related.joined(separator: ", "))")   // display-safe-exempt: 值取自 AkashicService.getEntry（entryDict 已逐欄位 displaySafe），二次消毒非冪等（\u{5C} 逃逸）
            }
            if let libraries = akashic["libraries"] as? [String] {
                // 封閉列舉第 5 條邊；值由 load-time StoreKey 閘門保證（verify D4）
                print("libraries\t\(libraries.joined(separator: ", "))")   // display-safe-exempt: StoreKey.pattern 結構上容不下控制字元（load-time quarantine）
            }
        }
    }
}
