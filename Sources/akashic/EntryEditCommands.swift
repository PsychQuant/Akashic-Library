import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// #219：關係／狀態的寫入面（CLI）——`link`／`tag`／`set-status` 三格。
/// 各自與 MCP 的同名 tool 共用同一個 `AkashicService` 函式；kind 合法值、
/// citekey 存在性、寫入與 reindex 全由 service 判——CLI 不重寫一份判準，
/// 兩面才不會分岔（#206 → #218 → #219 同一條裁決線）。

struct LinkCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "link",
        abstract: "建立／移除 entry 之間的關係邊（cites／related）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "citekey（邊存在它身上：cites 有向、related 對稱但存 entry 側）")
    var citekey: String

    @Option(name: .long, help: "關係種類：cites / related（與 MCP schema 一致）")
    var kind: String

    @Option(name: .long, parsing: .upToNextOption, help: "要加入的對端 citekey")
    var add: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "要移除的對端 citekey")
    var remove: [String] = []

    func run() throws {
        guard !add.isEmpty || !remove.isEmpty else {
            throw ValidationError("--add 與 --remove 至少要給一個")
        }
        let store = try options.openStore()
        // `key:` 不可省（#220 HIGH）——寫入格經 writeAndReindex，丟 key 會在
        // 已註冊 store 的 root 長出第二份 index
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        print(try service.link(citekey: citekey, kind: kind, add: add, remove: remove))
    }
}

struct TagCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "tag",
        abstract: "為 entry 加／移除標籤")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "citekey")
    var citekey: String

    @Option(name: .long, parsing: .upToNextOption, help: "要加入的 tag")
    var add: [String] = []

    @Option(name: .long, parsing: .upToNextOption, help: "要移除的 tag")
    var remove: [String] = []

    func run() throws {
        // 「至少給一個」的守衛在 service（#258 下沉——兩面共用同一份判準）
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        print(try service.tag(citekey: citekey, add: add, remove: remove))
    }
}

struct SetStatusCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "set-status",
        abstract: "設定／清除 entry 的閱讀狀態")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "citekey")
    var citekey: String

    @Argument(help: "狀態值（與 --clear 互斥）")
    var status: String?

    @Flag(name: .long, help: "清除狀態（與狀態值互斥）")
    var clear: Bool = false

    func run() throws {
        // 三態守衛（缺席拒絕、互斥拒絕）在 service（#258 下沉——原本只有 CLI 有
        // 這層、MCP 面「省略＝清除」，危害最大的面恰無守衛；單一判準兩面共用）
        let store = try options.openStore()
        let service = AkashicService(root: store.root, key: store.key,
                                     environment: ProcessInfo.processInfo.environment)
        print(try service.setStatus(citekey: citekey, status: status, clear: clear))
    }
}
