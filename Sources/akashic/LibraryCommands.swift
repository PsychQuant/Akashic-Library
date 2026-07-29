import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO
import AkashicIndex

/// #13 多 library（membership views）：registry 管理 + 成員操作。
/// store 是全集；library 只是具名成員集合，成員關係存在各 entry 的 akashic.libraries。
struct LibraryCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "library",
        abstract: "具名 library（成員集合視角）管理：list / create / add / remove",
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
            print("\(library.key)\t\(library.name)（\(counts[library.key] ?? 0) entries）\(desc)")
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

    func run() throws {
        let store = try options.openStore()
        // 驗證先行：未驗證 key 不得進任何路徑組合（存在性 oracle 防護）
        guard StoreKey.isValid(key) else {
            throw ValidationError("library key「\(key)」不符合 \(StoreKey.pattern)，拒絕寫入")
        }
        guard !FileManager.default.fileExists(atPath: store.libraryURL(key: key).path) else {
            throw ValidationError("library「\(key)」已存在")
        }
        do {
            let url = try store.writeLibrary(Library(key: key, name: name, description: description))
            print("created: \(url.lastPathComponent)")
        } catch {
            throw ValidationError((error as? LocalizedError)?.errorDescription ?? "\(error)")
        }
    }
}

/// add/remove 共用：讀盤後 patch（沿 #11 mutate 慣例——不用記憶體舊快照）+ reindex。
private func mutateMembership(store: LibraryStore, libraryKey: String, citekey: String,
                              requireRegistry: Bool, change: (inout [String]) -> Void) throws {
    let load = try store.load()
    // add 要求 registry 存在；remove 不要求——dangling membership（spec 允許存在）
    // 必須能用正式介面清理
    if requireRegistry, !load.libraries.contains(where: { $0.key == libraryKey }) {
        throw ValidationError("library「\(libraryKey)」不存在（先 akashic library create）")
    }
    guard var entry = load.entries.first(where: { $0.citekey == citekey }) else {
        throw ValidationError("citekey「\(citekey)」不存在")
    }
    change(&entry.akashic.libraries)
    try store.writeEntry(entry)
    _ = try LibraryIndex(store: store).rebuild()
}

struct LibraryAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add", abstract: "把 entry 加入 library（寫 entry 的 akashic.libraries）")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key") var libraryKey: String
    @Argument(help: "citekey") var citekey: String

    func run() throws {
        let store = try options.openStore()
        try mutateMembership(store: store, libraryKey: libraryKey, citekey: citekey,
                             requireRegistry: true) {
            if !$0.contains(libraryKey) { $0.append(libraryKey) }
        }
        print("added: \(citekey) → \(libraryKey)")
    }
}

struct LibraryRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove", abstract: "把 entry 移出 library")

    @OptionGroup var options: LibraryOptions
    @Argument(help: "library key") var libraryKey: String
    @Argument(help: "citekey") var citekey: String

    func run() throws {
        let store = try options.openStore()
        try mutateMembership(store: store, libraryKey: libraryKey, citekey: citekey,
                             requireRegistry: false) {
            $0.removeAll { $0 == libraryKey }
        }
        print("removed: \(citekey) ✕ \(libraryKey)")
    }
}
