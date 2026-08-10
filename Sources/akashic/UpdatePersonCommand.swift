import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// #68：person 的部分更新（CLI 面）。與 MCP 的 `akashic_update_person` 共用
/// `AkashicService.updatePerson` ——合併只有一條路，tolerant-preserve 與 canary 白拿。
struct UpdatePersonCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "update-person",
        abstract: "person 的部分更新：提及的欄位整個換、未提及一律不動")

    @OptionGroup var options: LibraryOptions
    @Option(name: .long, help: "person key") var key: String
    @Option(name: .long, help: ArgumentHelp(
        "結構化欄位值（JSON object；缺席時讀 stdin）",
        discussion: "純量欄位收字串或 null（null＝清除）；names/authorized 收字串陣列"
            + "（全量替換）；profile 收維度 object（維度級覆寫，段形狀同 YAML：value/"
            + "start/end/ended/source/note）"))
    var fields: String?
    @Flag(name: .long, help: "只預告會改什麼（含 format gate 預演），不寫入")
    var dryRun: Bool = false

    func run() throws {
        let raw: Data
        if let fields {
            raw = Data(fields.utf8)
        } else {
            raw = FileHandle.standardInput.readDataToEndOfFile()
        }
        guard let parsed = try? JSONSerialization.jsonObject(with: raw),
              let dict = parsed as? [String: Any] else {
            throw ValidationError("--fields 必須是 JSON object（或經 stdin 提供）")
        }
        let store = try options.openStore()
        // `key:` 不可省——見 `PersonCommand.swift` 的長註解（verify #220 HIGH）。
        // **先前的註解說「寫入路徑所以沒炸」——那是假的**（#218 R2 verify MEDIUM，
        // regression 與 DA 兩個 lens 各自打臉）。這兩支同樣走 `ensureFreshIndex()`，
        // 在已註冊的 store 裡會**建整份第二個 index**；`create-entry` 之後 `query`
        // 看不到新資料，而且不自癒（query 的 `ensureCurrent()` 不看 mtime）。
        // 差別只在它們的**主要產出**不取自 index，不是它們不碰 index。
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        // 輸出是 service 的 JSON（已 displaySafe）——CLI 原樣轉印
        print(try service.updatePerson(key: key, fields: dict, dryRun: dryRun))
    }
}
