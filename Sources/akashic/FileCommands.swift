import ArgumentParser
import Foundation
import AkashicCore
import AkashicStoreIO

/// #18 多「檔案」：具名 store root registry 管理。
/// 各檔案互不相通（entries/libraries/people/graph/index 各自獨立）。
struct FileCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "file",
        abstract: "管理多個實體庫（檔案）：list / add / remove / use",
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
                print("\(marker) \(key)\t\(config.files[key]!)")
            }
        }
        if let legacy = config.library {
            let note = config.current == nil ? "（current 未設時作為預設）" : "（被 current 覆蓋）"
            print("  library: \(legacy) \(note)")
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
        let expanded = (path as NSString).expandingTildeInPath
        let root = URL(fileURLWithPath: expanded)
        try LibraryStore(root: root).ensureLayout()
        config.files[key] = expanded
        try config.write(to: options.configURL)
        print("✓ 已註冊「\(key)」→ \(expanded)（layout 已確保；用 file use \(key) 切換）")
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
        config.current = key
        try config.write(to: options.configURL)
        print("✓ current →「\(key)」（\(path)）")
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
            print("ℹ current 是「\(key)」，已清空（回落 legacy library 或需重新 file use）")
        }
        try config.write(to: options.configURL)
        print("✓ 已除名「\(key)」（資料未刪除）")
    }
}
