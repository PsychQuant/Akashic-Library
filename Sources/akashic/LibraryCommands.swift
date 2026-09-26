import ArgumentParser
import Foundation
import AkashicCore
import AkashicMCPKit
import AkashicStoreIO
import AkashicIndex

/// #13 多 library（membership views）：registry 管理 + 成員操作。
/// store 是全集；library 只是具名成員集合，成員關係存在各 entry 的 akashic.libraries。
struct LibraryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "library",
        abstract: "具名 library（成員集合視角）管理：list / create / add / remove。注意：同一 store 的並發 add/remove/create（如 CLI 與 MCP 同時操作）不保證安全——見 README",
        subcommands: [LibraryList.self, LibraryCreate.self, LibraryAdd.self, LibraryRemove.self])
}

struct LibraryList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "列出 registry 中的 libraries 與成員數")

    @OptionGroup var options: LibraryOptions

    func run() throws {
        let store = try options.openStore()
        let load = try store.load()
        if load.libraries.isEmpty {
            print("（無 library——用 akashic library create <key> --name <名> 建立）")
            return
        }
        var counts: [String: Int] = [:]
        for entry in load.entries {
            for key in Set(entry.akashic.libraries) { counts[key, default: 0] += 1 }
        }
        for library in load.libraries {
            let desc = library.description.map { "　\($0)" } ?? ""
            print("\(displaySafe(library.key, max: 200))\t\(displaySafe(library.name, max: 800))（\(counts[library.key] ?? 0) entries）\(displaySafe(desc, max: 800))")   // display-safe-exempt: dict 查找，值是 Int 計數；key 只是索引不進輸出
        }
    }
}

struct LibraryCreate: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "create", abstract: "建立 library（registry metadata；不動任何 entry）")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key（StoreKey 格式：小寫英數與連字號）") var key: String
    @Option(name: .long, help: "顯示名稱") var name: String
    @Option(name: .long, help: "描述（選填）") var description: String?

    /// 驗證先行：未驗證 key 不得進任何路徑組合（存在性 oracle 防護）。放在 `validate()` 而不是 `run()`（#549 R1）：
    /// 它只看 argv，要早於開 store——否則 store 缺佈局時先報執行期失敗，同一個打錯的 key 得到不同的 exit code。
    func validate() throws { try requireValidLibraryKey(key) }

    func run() throws {
        let store = try options.openStore()
        guard !FileManager.default.fileExists(atPath: store.libraryURL(key: key).path) else {
            throw RuntimeFailure.state("library「\(displaySafeInvisible(key, max: 200))」已存在")
        }
        do {
            let url = try store.writeLibrary(Library(key: key, name: name, description: description))
            print("created: \(url.lastPathComponent)")
        } catch {
            throw RuntimeFailure.state(displaySafeErrorText(error))
        }
    }
}

/// library key 的格式檢查只看 argv——三個 library 子命令共用（#549 R1：add／remove 先前把它交給服務層，服務層的
/// `ServiceError` 被包成執行期失敗，同一個打錯的 key 在 create 回 64、在 add 回 1）。
private func requireValidLibraryKey(_ key: String) throws {
    guard StoreKey.isValid(key) else {
        throw ValidationError("library key「\(displaySafeInvisible(key, max: 200))」不符合 \(StoreKey.pattern)，拒絕寫入")
    }
}

/// add／remove 走 service 的批次形 `setMembership`（#455）：一次 load、整批驗（任一 citekey 不存在 → 整批
/// 拒絕零寫入）、逐筆寫、一次 rebuild。**先前 CLI 自己有一條 `mutateMembership`**（讀盤後 patch＋reindex），與
/// MCP 的 `libraries(action:)` 是兩條會分岔的實作路徑——`entity-backlink-completeness` 執行細節 2。
private func runMembership(options: LibraryOptions, action: String, libraryKey: String,
                           citekeys: [String]) throws -> AkashicService.MembershipReport {
    let store = try options.openStore()
    let service = AkashicService(root: store.root, key: store.key,
                                 environment: ProcessInfo.processInfo.environment)
    do {
        let report = try service.setMembership(action: action, key: libraryKey, citekeys: citekeys)
        guard report.writeFailures.isEmpty else {
            for f in report.writeFailures {
                print("  ! \(displaySafe(f.citekey, max: 200)) — \(displaySafeClipOnly(f.error, max: 3_200))")   // display-safe-exempt: error 已消毒（生產端 displaySafeError，R28 D80），只截
            }
            throw RuntimeFailure.state("\(report.writeFailures.count) 筆寫入失敗（其餘已寫入且 index 已重建）")   // display-safe-exempt: Int
        }
        return report
    } catch let e as ServiceError {
        throw RuntimeFailure.state(displaySafeErrorText(e))
    }
}

struct LibraryAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add",
        abstract: "把 entry 加入 library（寫 entry 的 akashic.libraries）。可一次給多個 citekey：任一不存在即整批拒絕（#455）")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key") var libraryKey: String
    @Argument(help: "citekey（可多個）") var citekeys: [String]

    func validate() throws { try requireValidLibraryKey(libraryKey) }

    func run() throws {
        let report = try runMembership(options: options, action: "add", libraryKey: libraryKey, citekeys: citekeys)
        for ck in report.written {
            print("added: \(displaySafe(ck, max: 200)) → \(displaySafe(libraryKey, max: 200))")
        }
    }
}

struct LibraryRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove", abstract: "把 entry 移出 library。可一次給多個 citekey：任一不存在即整批拒絕（#455）")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key") var libraryKey: String
    @Argument(help: "citekey（可多個）") var citekeys: [String]

    func validate() throws { try requireValidLibraryKey(libraryKey) }

    func run() throws {
        let report = try runMembership(options: options, action: "remove", libraryKey: libraryKey, citekeys: citekeys)
        for ck in report.written {
            print("removed: \(displaySafe(ck, max: 200)) ✕ \(displaySafe(libraryKey, max: 200))")
        }
    }
}
