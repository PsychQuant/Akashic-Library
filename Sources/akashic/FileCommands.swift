import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO

/// #18 多「檔案」：具名 store root registry 管理。
/// 各檔案互不相通（entries/libraries/people/graph/index 各自獨立）。
struct FileCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file",
        abstract: "管理多個實體庫（檔案）：list / add / remove / use。config 寫入為 read-modify-write、無跨程序鎖（單機單使用者；並發寫最後寫者勝）",
        subcommands: [FileList.self, FileAdd.self, FileRemove.self, FileUse.self])
}

struct FileConfigOptions: ParsableArguments {
    @Option(name: .long, help: "config 路徑（預設 ~/.akashic/config.yaml）")
    var config: String?

    var configURL: URL {
        config.map { URL(fileURLWithPath: ($0 as NSString).expandingTildeInPath) }
            ?? AkashicConfig.defaultURL
    }
}

struct FileList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "列出已註冊的檔案（* 為 current）")

    @OptionGroup var options: FileConfigOptions

    func run() throws {
        let config = try AkashicConfig.read(from: options.configURL)
        if config.files.isEmpty {
            print("（無已註冊檔案）")
        } else {
            for key in config.files.keys.sorted() {
                let marker = key == config.current ? "*" : " "
                print("\(marker) \(displaySafe(key, max: 200))\t\(displaySafe(config.files[key]!, max: 800))")
            }
        }
        if let legacy = config.library {
            let note = config.current == nil ? "（current 未設時作為預設）" : "（被 current 覆蓋）"
            print("  library: \(displaySafe(legacy, max: 800)) \(note)")
        }
    }
}

struct FileAdd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "add", abstract: "註冊一個檔案並確保 layout（冪等；不切換 current）")

    @Argument(help: "檔案 key（小寫英數起頭、僅 a-z0-9-）") var key: String
    @Argument(help: "store root 路徑") var path: String
    @OptionGroup var options: FileConfigOptions

    func run() throws {
        guard StoreKey.isValid(key) else {
            throw ValidationError("key「\(key)」不合法（小寫英數起頭、僅 a-z0-9-）")
        }
        var config = try AkashicConfig.read(from: options.configURL)
        guard config.files[key] == nil else {
            throw ValidationError("key「\(key)」已存在（→ \(config.files[key]!)）。先 file remove 再重加。")
        }
        // 正規化為絕對路徑後才入 config——相對路徑會依各程序 CWD 指向不同
        // universe（CLI/App/launchd 起的 MCP 各有各的 CWD，Codex R1 #3）
        let expanded = (path as NSString).expandingTildeInPath
        let absolute = URL(fileURLWithPath: expanded).standardizedFileURL.path
        if let existing = config.files.first(where: {
            URL(fileURLWithPath: ($0.value as NSString).expandingTildeInPath).standardizedFileURL.path == absolute
        }) {
            throw ValidationError("路徑已由 key「\(existing.key)」註冊（同一實體庫不重複註冊——檔案間互不相通）")
        }
        // **key 要傳進去**（#101）：這裡正在註冊它，所以這個 store 是「已註冊」的，
        // index 會住 `~/.akashic/index/<key>.sqlite`。省略 key 會讓 ensureLayout 以為
        // 這是未註冊 store，替它建一個永遠用不到的 in-store `.akashic/` 回落位置。
        try LibraryStore(root: URL(fileURLWithPath: absolute), key: key).ensureLayout()
        config.files[key] = absolute
        try config.write(to: options.configURL)
        print("✓ 已註冊「\(displaySafe(key, max: 200))」→ \(displaySafe(absolute, max: 800))（layout 已確保；用 file use \(displaySafe(key, max: 200)) 切換）")
    }
}

struct FileUse: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "use", abstract: "切換 current 檔案（寫入 config）")

    @Argument(help: "已註冊的檔案 key") var key: String
    @OptionGroup var options: FileConfigOptions

    func run() throws {
        var config = try AkashicConfig.read(from: options.configURL)
        guard let path = config.files[key] else {
            let known = config.files.keys.sorted().joined(separator: ", ")
            throw ValidationError("key「\(key)」未註冊。已註冊：\(known.isEmpty ? "（無）" : known)")
        }
        // 與 MCP/App 一致的目標驗證（Codex R1 #7）：指過去必須是 library
        let target = URL(fileURLWithPath: (path as NSString).expandingTildeInPath)
        guard LibraryStore.isLibraryRoot(target) else {
            throw ValidationError("「\(path)」不是 Akashic library（缺 entries/ 目錄）。目錄被移走？file remove 後重加。")
        }
        config.current = key
        try config.write(to: options.configURL)
        print("✓ current →「\(displaySafe(key, max: 200))」（\(displaySafe(path, max: 800))）")
    }
}

struct FileRemove: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "remove", abstract: "自 registry 除名（不刪除任何資料）")

    @Argument(help: "已註冊的檔案 key") var key: String
    @OptionGroup var options: FileConfigOptions

    func run() throws {
        var config = try AkashicConfig.read(from: options.configURL)
        guard config.files[key] != nil else {
            throw ValidationError("key「\(key)」未註冊。")
        }
        config.files.removeValue(forKey: key)
        if config.current == key {
            config.current = nil
            print("ℹ current 是「\(displaySafe(key, max: 200))」，已清空（回落 legacy library 或需重新 file use）")
        }
        try config.write(to: options.configURL)
        print("✓ 已除名「\(displaySafe(key, max: 200))」（資料未刪除）")
    }
}
