import Foundation
import ArgumentParser
import AkashicCore
import AkashicStoreIO

/// `akashic view` —— view 的**判準**在 `config.yaml`，**外延**現算（#54／#65）。
///
/// 沒有 `view create`：判準是設定，由人編輯 `config.yaml`。給一個寫入指令會讓
/// 「這是設定不是知識」這個區分在使用層被磨掉——設定該用編輯器改，不是用 CLI
/// 造。這與 `library create`（那是 registry metadata、屬 store）刻意不同。
struct ViewCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "view",
        abstract: "列出／展開 config.yaml 宣告的 view（判準是設定，外延是衍生）",
        subcommands: [ViewList.self, ViewShow.self])
}

struct ViewList: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list", abstract: "列出已宣告的 view 與它們的判準")

    @OptionGroup var options: LibraryOptions

    func run() throws {
        let store = try options.openStore()
        let config = try AkashicConfig.read(from: AkashicHome.configURL())
        guard !config.views.isEmpty else {
            print("（config.yaml 沒有宣告任何 view）")
            print("  在 ~/.akashic/config.yaml 加：")
            print("  views:")
            print("    iss:")
            print("      description: 中研院統計所的人與其著作")
            print("      person-affiliation: institute-of-statistical-science")
            print("      work-has-author-in-view: true")
            return
        }
        _ = store
        for key in config.views.keys.sorted() {
            let v = config.views[key]!
            print("\(displaySafe(key, max: 200))"
                  + (v.description.map { "  — \(displaySafe($0, max: 300))" } ?? ""))
            if let a = v.personAffiliation {
                print("  person: 隸屬 \(displaySafe(a, max: 200))")
            }
            if v.workHasAuthorInView { print("  work:   作者在本 view 的 person 外延內") }
        }
    }
}

struct ViewShow: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "show", abstract: "展開一個 view 的外延（現算，不寫檔）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "view key")
    var key: String

    @Flag(name: .long, help: "只印成員 key，一行一個（給下游腳本吃）")
    var keysOnly = false

    func run() throws {
        let store = try options.openStore()
        let config = try AkashicConfig.read(from: AkashicHome.configURL())
        guard let def = config.views[key] else {
            throw RuntimeFailure.state("config.yaml 沒有 view「\(displaySafeInvisible(key, max: 200))」"
                                  + "（`akashic view list` 看有哪些）")
        }
        let ext = def.extension_(in: try store.load())
        if keysOnly {
            // **外延是衍生物**，所以它的用途是餵下游、不是被保存。給一個機器可讀的
            // 形式，正是為了讓下游**不必**再發明一次判準（#65 的病灶）。
            for k in ext.people { print(k) }
            for k in ext.works { print(k) }
            return
        }
        print("view: \(displaySafe(key, max: 200))"
              + (def.description.map { "  — \(displaySafe($0, max: 300))" } ?? ""))
        print("person: \(ext.people.count)")
        for k in ext.people.prefix(20) { print("  \(displaySafe(k, max: 200))") }
        if ext.people.count > 20 { print("  …另 \(ext.people.count - 20) 筆") }
        print("work: \(ext.works.count)")
        for k in ext.works.prefix(20) { print("  \(displaySafe(k, max: 200))") }
        if ext.works.count > 20 { print("  …另 \(ext.works.count - 20) 筆") }
        print("  （外延是衍生物——不進版控、可隨時重算；判準在 ~/.akashic/config.yaml）")
    }
}
