import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// #219：people 的讀取面（CLI）。與 MCP 的 `akashic_people` 共用
/// `AkashicService.people`——同 `person`（#218）的作法：一個讀取面只有
/// 一條實作路徑，人可讀輸出從同一份 JSON 排版。
struct PeopleCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "people",
        abstract: "列出 person 記錄（可用子字串過濾 key 或名字）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "過濾子字串（比對 key 與 names，不分大小寫；省略 = 全列）")
    var query: String?

    @Flag(name: .long, help: "原樣輸出 service JSON（與 MCP akashic_people 逐欄位相同）")
    var json: Bool = false

    func run() throws {
        let store = try options.openStore()
        // `key:` 不可省——省略即 index 分岔（#220 HIGH；理由詳 PersonCommand.swift）
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.people(query: query)
        if json {
            print(payload)   // service 輸出已 displaySafe，原樣轉印
            return
        }
        guard let data = payload.data(using: .utf8),
              let people = try JSONSerialization.jsonObject(with: data) as? [[String: Any]] else {
            throw ValidationError("service 回應不是預期的 JSON 陣列")
        }
        if people.isEmpty {
            // 「零筆」是結果不是錯誤——與 person --name 無候選同一立場。
            // 不回顯 query（#219 verify F2 探針實證：argv 是未消毒的使用者輸入，
            // 回顯會把 raw ESC／bidi 直送終端機；此處也拿不到 service 端的消毒器）
            print(query == nil ? "（無 person 記錄）" : "（無符合過濾條件的 person 記錄）")
            return
        }
        for p in people {
            let key = p["key"] as? String ?? ""
            let names = (p["names"] as? [String])?.joined(separator: "、") ?? ""
            var line = "\(key)\t\(names)"
            if let orcid = p["orcid"] as? String { line += "\torcid:\(orcid)" }
            if let openalex = p["openalex"] as? String { line += "\topenalex:\(openalex)" }
            if let unknown = p["unknownFields"] as? [String], !unknown.isEmpty {
                line += "\tunknown:\(unknown.joined(separator: ","))"   // #31：只有鍵、無值
            }
            print(line)   // display-safe-exempt: 值取自 AkashicService.people（已逐欄位 displaySafe，含 #219 補上的 orcid/openalex），二次消毒非冪等
        }
    }
}
