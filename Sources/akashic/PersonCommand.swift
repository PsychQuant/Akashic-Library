import Foundation
import ArgumentParser
import AkashicCore
import AkashicMCPKit

/// #218：person 的**讀取面**（CLI）。與 MCP 的 `akashic_person` 共用
/// `AkashicService.person` ——同 `update-person`（#68）與 `create-entry`（#206）的作法。
///
/// ## 為什麼這個命令需要存在
///
/// 「這個人寫了什麼」的衍生鏈本來就是完整的：
///
///     LibraryIndex  authors(person_key) + idx_authors_key
///       → QueryEngine.personPublications(key:library:)
///         → AkashicService.person()      ← MCP 面到此為止
///
/// 但那條鏈**只有 MCP 接上去**。CLI 能用 `update-person` **改寫**一筆 person
/// 記錄，卻沒有任何入口**讀出**一筆——能力可用性取決於使用者走哪個面，正是
/// #206 已經裁決過的那個不對稱（其餘同族缺口見 #219）。
///
/// ## 著作不在記錄裡，而且不該在
///
/// `Person` 沒有、也不會有 `works:` 欄位。`work.authors` 已經是正典；在 person
/// 再存一份就是**第二份 canonical state**，歸戶／改名／刪除都要兩邊同步而它們會
/// 分岔。方向是**衍生而非儲存**——`entity-backlink-completeness` 規則寫的就是這件事。
///
/// 這也不是一個 view：view 的成員資格由**判準**定義（住 `config.yaml`，見
/// `ViewDefinition`），而「某人的著作」沒有判準可設，它就是把既有的邊反過來讀。
///
/// ## 為什麼人可讀輸出要繞一趟 JSON
///
/// 兩種輸出都從 `service.person(...)` 的**同一個回應**產生：`--json` 原樣轉印，
/// 人可讀則解析後排版。看起來繞，但這是刻意的——若人可讀分支自己去問
/// `QueryEngine`，CLI 與 MCP 就變成兩條會分岔的路徑，而那正是本 issue 在修的病。
/// `testCLIAndServiceAgreeOnPublications` 是機械防線。
struct PersonCmd: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "person",
        abstract: "看一個人：記錄 + 著作 + 合著者（著作由反向邊算出，不存在記錄裡）")

    @OptionGroup var options: LibraryOptions

    @Argument(help: "person key（與 --name 互斥）")
    var key: String?

    @Option(name: .long, help: "模糊名，回候選清單（絕不自動選；與 key 互斥）")
    var name: String?

    @Option(name: .customLong("in-library"), help: "只算這個 library 內的著作")
    var inLibrary: String?

    @Flag(name: .long, help: "原樣輸出 service JSON（與 MCP akashic_person 逐欄位相同）")
    var json: Bool = false

    func run() throws {
        // key/name 互斥、空白拒絕、not-found 都由 service 判——CLI 不重寫一份判準
        let store = try options.openStore()
        let service = AkashicService(root: store.root,
                                     environment: ProcessInfo.processInfo.environment)
        let payload = try service.person(key: key, name: name, library: inLibrary)
        if json {
            print(payload)   // service 的輸出已 displaySafe，原樣轉印
            return
        }
        try PersonCmd.render(payload)
    }

    /// 把 service 的 JSON 排成人可讀。欄位分隔沿用 `query` 的 TSV 慣例。
    ///
    /// `internal` 而非 `private`：測試要能對照同一份 JSON 的兩種輸出。
    ///
    /// ## 為什麼這裡不再 `displaySafe`（#193 守衛的 exemption 理由）
    ///
    /// 本函式的輸入是 `AkashicService.person()` 的回應，那裡**已經逐欄位消毒**
    /// （`summaryDict` 的 citekey／type／title／authors／journal、`personDict` 的
    /// key／names／orcid／unknownFields、co_authors 的 name／person_key、
    /// candidates 的 person_key／names／literal——`AkashicService.swift` 全部
    /// 包在 `displaySafe(` 內）。本函式不從 store 另外讀任何東西。
    ///
    /// 而 **`displaySafe` 不冪等**：它把反斜線自身也逃脫（`Models.swift`
    /// 「`v == 0x5C`」那條）。對已消毒的字串再呼叫一次，會把第一次產生的
    /// `\u{0009}` 變成 `\u{005C}u{0009}`——**輸出反而壞掉**。
    ///
    /// 兩句都可否證：前者 grep `AkashicService.swift` 的 `summaryDict`／`personDict`
    /// 看有沒有裸送；後者 grep `Models.swift` 的 `0x5C`。
    static func render(_ payload: String) throws {
        guard let obj = try JSONSerialization.jsonObject(with: Data(payload.utf8))
                as? [String: Any] else {
            throw ValidationError("service 回應不是 JSON object")
        }

        // 模糊名分支：候選清單。**不自動選**——與 service 同一個立場
        if let candidates = obj["candidates"] as? [[String: Any]] {
            guard !candidates.isEmpty else {
                print("（無候選）")
                return
            }
            print("候選（\(candidates.count)）")
            for c in candidates {
                // 已歸戶的有 person_key + names；未歸戶的只有 literal——兩者都是
                // 誠實的狀態，不把 literal 冒充成 identity（同 EntityRef 的立場）
                let ident = (c["person_key"] as? String) ?? (c["literal"] as? String) ?? "?"
                let n = (c["publications"] as? Int).map(String.init) ?? "?"
                let names = (c["names"] as? [String])?.joined(separator: "; ") ?? ""
                print("\(ident)\t\(n)\t\(names)")
            }
            if obj["truncated"] as? Bool == true {
                print("（已截斷至 50 筆——用更精確的名字，或直接給 key）")
            }
            return
        }

        // key 分支：記錄 + 著作 + 合著者
        if let person = obj["person"] as? [String: Any] {
            print((person["key"] as? String) ?? "?")
            if let names = person["names"] as? [String], !names.isEmpty {
                print("  names: \(names.joined(separator: "; "))")
            }
            if let orcid = person["orcid"] as? String { print("  orcid: \(orcid)") }
            if let unknown = person["unknownFields"] as? [String], !unknown.isEmpty {
                // #31：未知欄位是被保留而非丟棄的——讀取面要說出來，否則
                // 「保留了」這件事對 CLI 使用者不可見
                print("  unknownFields: \(unknown.joined(separator: ", "))")
            }
        }

        let pubs = (obj["publications"] as? [[String: Any]]) ?? []
        print("")
        print("著作（\(pubs.count)）")
        if pubs.isEmpty {
            // 空集合要說出來。person 記錄存在但一篇都沒有，與「查不到這個人」
            // 是兩件事——後者由 service 擲 notFound
            print("（無）")
        } else {
            for p in pubs {
                let year = (p["year"] as? Int).map(String.init) ?? "----"
                let authors = (p["authors"] as? [String])?.joined(separator: "; ") ?? ""
                let citekey = (p["citekey"] as? String) ?? "?"
                let title = (p["title"] as? String) ?? ""
                print("\(citekey)\t\(year)\t\(authors)\t\(title)")   // display-safe-exempt: 值取自 AkashicService.summaryDict，該處已逐欄位 displaySafe；再呼叫一次會二次逃脫（displaySafe 逃脫 0x5C，不冪等）——見本函式 doc
            }
        }

        let co = (obj["co_authors"] as? [[String: Any]]) ?? []
        if !co.isEmpty {
            print("")
            print("合著者（\(co.count)）")
            for c in co {
                let n = (c["count"] as? Int).map(String.init) ?? "?"
                let who = (c["name"] as? String) ?? "?"
                // 已歸戶的另外標 key——讓使用者看得出哪些合著者還沒歸戶
                let k = (c["person_key"] as? String).map { "\t\($0)" } ?? ""
                print("\(n)\t\(who)\(k)")
            }
        }
    }
}
